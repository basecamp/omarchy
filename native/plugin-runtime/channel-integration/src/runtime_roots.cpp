#include "runtime_roots.hpp"

#include <fcntl.h>
#include <sys/file.h>
#include <sys/random.h>
#include <sys/syscall.h>
#include <dirent.h>
#include <pwd.h>
#include <sys/stat.h>
#include <unistd.h>

#include <algorithm>
#include <array>
#include <cerrno>
#include <limits>
#include <new>
#include <optional>
#include <ranges>
#include <span>
#include <stdexcept>
#include <string>
#include <string_view>
#include <vector>

namespace omarchy::plugin_runtime::channel {
namespace {

using host_session::OwnedDescriptor;

struct DirectoryCloser {
  void operator()(DIR *directory) const noexcept {
    if (directory != nullptr)
      ::closedir(directory);
  }
};

#ifdef OMARCHY_RUNTIME_ROOTS_TESTING
CandidateRecordCrashPoint candidate_crash_point =
    CandidateRecordCrashPoint::none;
ProvisioningRacePoint provisioning_race_point = ProvisioningRacePoint::none;
ProvisioningRaceHook provisioning_race_hook = nullptr;
void crash_candidate_if_requested(CandidateRecordCrashPoint point) noexcept {
  if (candidate_crash_point == point)
    ::_exit(90 + static_cast<int>(point));
}

void run_provisioning_race_hook(ProvisioningRacePoint point) {
  if (provisioning_race_point == point && provisioning_race_hook != nullptr)
    provisioning_race_hook();
}
#endif

constexpr std::size_t kMaximumPasswdBuffer = 1024 * 1024;
constexpr std::size_t kMaximumAccountLookupAttempts = 16;
constexpr std::array<std::string_view, 5> kRevisionComponents{
    ".local", "share", "omarchy-plugin-security", "v2", "revisions"};
constexpr std::array<std::string_view, 6> kActivationComponents{
    ".local", "state", "omarchy", "plugin-security", "v2", "activations"};
constexpr std::array<std::string_view, 6> kAuthorityComponents{
    ".local", "state", "omarchy", "plugin-security", "v2", "authority"};
constexpr std::array<std::string_view, 6> kStateComponents{
    ".local", "state", "omarchy", "plugin-security", "v2", "state"};

bool secure_parent(const struct stat &metadata, std::uint32_t uid) noexcept {
  return S_ISDIR(metadata.st_mode) && metadata.st_uid == uid &&
         (metadata.st_mode & 0022) == 0;
}

bool exact_private_root(const struct stat &metadata,
                        std::uint32_t uid) noexcept {
  return S_ISDIR(metadata.st_mode) && metadata.st_uid == uid &&
         (metadata.st_mode & 07777) == 0700;
}

void require_transaction(bool condition, std::string_view message) {
  if (!condition)
    throw std::runtime_error(std::string(message));
}

std::string candidate_temporary_name() {
  std::array<unsigned char, 12> random{};
  require_transaction(::getrandom(random.data(), random.size(), 0) ==
                          static_cast<ssize_t>(random.size()),
                      "cannot generate activation staging name");
  constexpr char hex[] = "0123456789abcdef";
  std::string result = ".candidate-";
  for (const auto byte : random) {
    result.push_back(hex[byte >> 4]);
    result.push_back(hex[byte & 15]);
  }
  return result;
}

bool canonical_candidate_temporary(std::string_view name) {
  constexpr std::string_view prefix = ".candidate-";
  return name.size() == prefix.size() + 24 && name.starts_with(prefix) &&
         std::ranges::all_of(name.substr(prefix.size()), [](char byte) {
           return (byte >= '0' && byte <= '9') ||
                  (byte >= 'a' && byte <= 'f');
         });
}

void recover_candidate_temporaries_locked(int root,
                                          std::uint32_t trusted_uid) {
  constexpr std::size_t maximum_candidates = 1024;
  const int scan = ::openat(root, ".",
                            O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
  require_transaction(scan >= 0, "cannot scan activation root");
  DIR *raw = ::fdopendir(scan);
  if (raw == nullptr) {
    ::close(scan);
    throw std::runtime_error("cannot enumerate activation root");
  }
  std::unique_ptr<DIR, DirectoryCloser> directory(raw);
  std::vector<std::string> candidates;
  for (;;) {
    errno = 0;
    const auto *entry = ::readdir(directory.get());
    if (entry == nullptr) {
      require_transaction(errno == 0, "cannot enumerate activation root");
      break;
    }
    const std::string_view name(entry->d_name);
    if (!name.starts_with(".candidate-"))
      continue;
    require_transaction(canonical_candidate_temporary(name),
                        "activation root has malformed candidate staging");
    struct stat metadata{};
    require_transaction(
        ::fstatat(root, entry->d_name, &metadata, AT_SYMLINK_NOFOLLOW) == 0 &&
            S_ISREG(metadata.st_mode) && metadata.st_uid == trusted_uid &&
            metadata.st_nlink == 1 && (metadata.st_mode & 07777) == 0600,
        "activation candidate staging is untrusted");
    require_transaction(candidates.size() < maximum_candidates,
                        "too many activation candidate staging files");
    candidates.emplace_back(name);
  }
  directory.reset();
  for (const auto &name : candidates) {
    struct stat metadata{};
    require_transaction(
        ::fstatat(root, name.c_str(), &metadata, AT_SYMLINK_NOFOLLOW) == 0 &&
            S_ISREG(metadata.st_mode) && metadata.st_uid == trusted_uid &&
            metadata.st_nlink == 1 && (metadata.st_mode & 07777) == 0600,
        "activation candidate staging changed");
    OwnedDescriptor pinned(::openat(root, name.c_str(),
                                    O_RDONLY | O_CLOEXEC | O_NOFOLLOW |
                                        O_NONBLOCK));
    struct stat opened{};
    require_transaction(pinned && ::fstat(pinned.get(), &opened) == 0 &&
                            opened.st_dev == metadata.st_dev &&
                            opened.st_ino == metadata.st_ino,
                        "activation candidate staging identity changed");
    require_transaction(::unlinkat(root, name.c_str(), 0) == 0,
                        "cannot recover activation candidate staging");
  }
  require_transaction(::fsync(root) == 0,
                      "cannot sync activation candidate recovery");
}

bool recover_candidate_temporaries(int activation_root,
                                   std::uint32_t trusted_uid) {
  try {
    OwnedDescriptor locked(::openat(
        activation_root, ".", O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW));
    require_transaction(static_cast<bool>(locked) &&
                            ::flock(locked.get(), LOCK_EX) == 0,
                        "cannot lock activation root");
    recover_candidate_temporaries_locked(locked.get(), trusted_uid);
    return true;
  } catch (...) {
    return false;
  }
}

void write_all(int descriptor, std::string_view bytes) {
  while (!bytes.empty()) {
    const auto count = ::write(descriptor, bytes.data(), bytes.size());
    if (count < 0 && errno == EINTR)
      continue;
    require_transaction(count > 0, "cannot write activation candidate");
    bytes.remove_prefix(static_cast<std::size_t>(count));
  }
}

void ensure_private_plugin_directory(int root, std::string_view plugin,
                                     std::uint32_t trusted_uid) {
  OwnedDescriptor locked(::openat(root, ".",
                                  O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW));
  struct stat root_metadata{};
  require_transaction(
      locked && ::flock(locked.get(), LOCK_EX) == 0 &&
          ::fstat(locked.get(), &root_metadata) == 0 &&
          S_ISDIR(root_metadata.st_mode) &&
          root_metadata.st_uid == trusted_uid &&
          (root_metadata.st_mode & 07777) == 0700,
      "plugin private root is untrusted");
  root = locked.get();
  const std::string name(plugin);
  const bool created = ::mkdirat(root, name.c_str(), 0700) == 0;
  if (!created)
    require_transaction(errno == EEXIST,
                        "cannot create plugin private state directory");
  if (created) {
    // Btrfs reports one link for a valid named directory; only zero means the
    // pinned inode was unlinked before its named identity was confirmed.
    OwnedDescriptor path(::openat(root, name.c_str(),
                                  O_PATH | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW));
    struct stat named{};
    struct stat pinned{};
    require_transaction(
        path && ::fstatat(root, name.c_str(), &named, AT_SYMLINK_NOFOLLOW) == 0 &&
            ::fstat(path.get(), &pinned) == 0 && S_ISDIR(pinned.st_mode) &&
            pinned.st_uid == trusted_uid && pinned.st_dev == named.st_dev &&
            pinned.st_ino == named.st_ino && pinned.st_nlink != 0 &&
            ::syscall(SYS_fchmodat2, path.get(), "", 0700, AT_EMPTY_PATH) == 0,
        "cannot normalize plugin private directory mode");
  }
  OwnedDescriptor state(::openat(root, name.c_str(),
                                 O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW));
  struct stat metadata{};
  require_transaction(static_cast<bool>(state) &&
                          ::fstat(state.get(), &metadata) == 0 &&
                          S_ISDIR(metadata.st_mode) &&
                          metadata.st_uid == trusted_uid &&
                          (metadata.st_mode & 07777) == 0700,
                      "plugin private state directory is untrusted");
  require_transaction(::fsync(state.get()) == 0 && ::fsync(root) == 0,
                      "cannot sync plugin private state directory");
}

void publish_candidate_record(int activation_root,
                              const host_session::ActivationRecord &record,
                              std::uint32_t trusted_uid) {
  const auto encoded = host_session::encode_activation_record(record);
  require_transaction(encoded.has_value(), "invalid activation candidate");
  OwnedDescriptor locked(::openat(activation_root, ".",
                                  O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW));
  struct stat root{};
  require_transaction(static_cast<bool>(locked) &&
                          ::flock(locked.get(), LOCK_EX) == 0 &&
                          ::fstat(locked.get(), &root) == 0 &&
                          S_ISDIR(root.st_mode) && root.st_uid == trusted_uid &&
                          (root.st_mode & 07777) == 0700,
                      "activation root is untrusted");
  recover_candidate_temporaries_locked(locked.get(), trusted_uid);
  const auto temporary = candidate_temporary_name();
  OwnedDescriptor output(::openat(locked.get(), temporary.c_str(),
                                  O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC |
                                      O_NOFOLLOW,
                                  0600));
  require_transaction(static_cast<bool>(output),
                      "cannot create activation candidate staging");
  bool named = true;
  try {
    struct stat metadata{};
    require_transaction(::fchmod(output.get(), 0600) == 0 &&
                            ::fstat(output.get(), &metadata) == 0 &&
                            S_ISREG(metadata.st_mode) &&
                            metadata.st_uid == trusted_uid &&
                            metadata.st_nlink == 1 &&
                            (metadata.st_mode & 07777) == 0600,
                        "activation candidate staging is untrusted");
    write_all(output.get(), *encoded);
#ifdef OMARCHY_RUNTIME_ROOTS_TESTING
    crash_candidate_if_requested(CandidateRecordCrashPoint::write);
#endif
    require_transaction(::fsync(output.get()) == 0,
                        "cannot sync activation candidate");
#ifdef OMARCHY_RUNTIME_ROOTS_TESTING
    crash_candidate_if_requested(CandidateRecordCrashPoint::file_sync);
#endif
    require_transaction(::renameat(locked.get(), temporary.c_str(), locked.get(),
                                   record.plugin_id.c_str()) == 0,
                        "cannot publish activation candidate");
    named = false;
#ifdef OMARCHY_RUNTIME_ROOTS_TESTING
    crash_candidate_if_requested(CandidateRecordCrashPoint::rename);
#endif
    require_transaction(::fsync(locked.get()) == 0,
                        "cannot sync activation candidate publication");
#ifdef OMARCHY_RUNTIME_ROOTS_TESTING
    crash_candidate_if_requested(CandidateRecordCrashPoint::directory_sync);
#endif
  } catch (...) {
    if (named)
      ::unlinkat(locked.get(), temporary.c_str(), 0);
    throw;
  }
}

OwnedDescriptor duplicate_directory(int descriptor) noexcept {
  if (descriptor < 0)
    return {};
  return OwnedDescriptor(::openat(
      descriptor, ".", O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW));
}

enum class FixedRootAccess : std::uint8_t { existing, provision };

OwnedDescriptor
open_fixed_root(int home_fd, std::span<const std::string_view> parts,
                std::uint32_t uid, FixedRootAccess access,
                RuntimeRootsError &error) {
  auto current = duplicate_directory(home_fd);
  if (!current) {
    error = RuntimeRootsError::home_untrusted;
    return {};
  }
  for (std::size_t index = 0; index < parts.size(); ++index) {
    const std::string component(parts[index]);
    bool created = false;
    OwnedDescriptor next(
        ::openat(current.get(), component.c_str(),
                 O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW));
    if (!next && access == FixedRootAccess::provision && errno == ENOENT) {
      if (::mkdirat(current.get(), component.c_str(), 0700) == 0) {
        created = true;
      } else if (errno != EEXIST) {
        error = RuntimeRootsError::path_unavailable;
        return {};
      }
#ifdef OMARCHY_RUNTIME_ROOTS_TESTING
      run_provisioning_race_hook(ProvisioningRacePoint::after_mkdir);
#endif
      OwnedDescriptor pinned(
          ::openat(current.get(), component.c_str(),
                   O_PATH | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW));
#ifdef OMARCHY_RUNTIME_ROOTS_TESTING
      run_provisioning_race_hook(ProvisioningRacePoint::after_pin);
#endif
      struct stat named{};
      struct stat metadata{};
      if (!pinned || ::fstat(pinned.get(), &metadata) < 0 ||
          ::fstatat(current.get(), component.c_str(), &named,
                    AT_SYMLINK_NOFOLLOW) < 0) {
        error = RuntimeRootsError::root_untrusted;
        return {};
      }
#ifdef OMARCHY_RUNTIME_ROOTS_TESTING
      run_provisioning_race_hook(ProvisioningRacePoint::after_named_stat);
#endif
      if (!S_ISDIR(metadata.st_mode) || metadata.st_uid != uid ||
          metadata.st_dev != named.st_dev || metadata.st_ino != named.st_ino) {
        error = RuntimeRootsError::root_untrusted;
        return {};
      }
      // fchmodat2(AT_EMPTY_PATH) is required so normalization applies to the
      // pinned object. Kernels without it fail closed instead of reopening a
      // potentially substituted pathname.
      if (created &&
          ::syscall(SYS_fchmodat2, pinned.get(), "", 0700, AT_EMPTY_PATH) < 0) {
        error = RuntimeRootsError::path_unavailable;
        return {};
      }
      next = OwnedDescriptor(
          ::openat(current.get(), component.c_str(),
                   O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW));
      struct stat opened{};
      if (!next || ::fstat(next.get(), &opened) < 0 ||
          opened.st_dev != metadata.st_dev || opened.st_ino != metadata.st_ino) {
        error = RuntimeRootsError::root_untrusted;
        return {};
      }
      if (created &&
          (::fsync(next.get()) < 0 || ::fsync(current.get()) < 0)) {
        error = RuntimeRootsError::path_unavailable;
        return {};
      }
    }
    if (!next) {
      error = RuntimeRootsError::path_unavailable;
      return {};
    }
    struct stat metadata{};
    if (::fstat(next.get(), &metadata) < 0) {
      error = RuntimeRootsError::path_unavailable;
      return {};
    }
    const bool leaf = index + 1 == parts.size();
    if ((leaf && !exact_private_root(metadata, uid)) ||
        (!leaf && !secure_parent(metadata, uid))) {
      error = RuntimeRootsError::root_untrusted;
      return {};
    }
    current = std::move(next);
  }
  return current;
}

std::optional<host_session::FilesystemIdentity>
identity(int descriptor) noexcept {
  struct stat metadata{};
  if (::fstat(descriptor, &metadata) < 0)
    return std::nullopt;
  return host_session::FilesystemIdentity{
      .device = static_cast<std::uint64_t>(metadata.st_dev),
      .inode = static_cast<std::uint64_t>(metadata.st_ino)};
}

} // namespace

std::unique_ptr<RuntimeRoots>
RuntimeRoots::open_from_home_fd_impl(
    int home_fd, std::uint32_t uid, RuntimeRootsError &error) {
  struct stat home_metadata{};
  if (home_fd < 0 || ::fstat(home_fd, &home_metadata) < 0 ||
      !secure_parent(home_metadata, uid)) {
    error = RuntimeRootsError::home_untrusted;
    return {};
  }
  auto revisions =
      open_fixed_root(home_fd, kRevisionComponents, uid,
                      FixedRootAccess::existing, error);
  if (!revisions)
    return {};
  auto activations =
      open_fixed_root(home_fd, kActivationComponents, uid,
                      FixedRootAccess::existing, error);
  if (!activations)
    return {};
  auto authority =
      open_fixed_root(home_fd, kAuthorityComponents, uid,
                      FixedRootAccess::existing, error);
  if (!authority)
    return {};
  auto state = open_fixed_root(home_fd, kStateComponents, uid,
                               FixedRootAccess::existing, error);
  if (!state)
    return {};
  const std::array identities{identity(revisions.get()),
                              identity(activations.get()),
                              identity(authority.get()), identity(state.get())};
  if (!std::ranges::all_of(
          identities, [](const auto &value) { return value.has_value(); })) {
    error = RuntimeRootsError::root_untrusted;
    return {};
  }
  const std::array exact{*identities[0], *identities[1], *identities[2],
                         *identities[3]};
  if (!host_session::distinct_authority_objects(exact)) {
    error = RuntimeRootsError::aliased_roots;
    return {};
  }
  if (!recover_candidate_temporaries(activations.get(), uid)) {
    error = RuntimeRootsError::root_untrusted;
    return {};
  }
  error = RuntimeRootsError::none;
  return std::unique_ptr<RuntimeRoots>(new RuntimeRoots(
      uid, std::move(revisions), std::move(activations), std::move(authority),
      std::move(state)));
}

std::unique_ptr<RuntimeRoots>
RuntimeRoots::provision_from_home_fd_impl(
    int home_fd, std::uint32_t uid, RuntimeRootsError &error) {
  struct stat home_metadata{};
  if (home_fd < 0 || ::fstat(home_fd, &home_metadata) < 0 ||
      !secure_parent(home_metadata, uid)) {
    error = RuntimeRootsError::home_untrusted;
    return {};
  }
  auto locked = duplicate_directory(home_fd);
  if (!locked || ::flock(locked.get(), LOCK_EX) < 0) {
    error = RuntimeRootsError::home_untrusted;
    return {};
  }
  const std::array roots{std::span<const std::string_view>(kRevisionComponents),
                         std::span<const std::string_view>(kActivationComponents),
                         std::span<const std::string_view>(kAuthorityComponents),
                         std::span<const std::string_view>(kStateComponents)};
  for (const auto parts : roots) {
    if (!open_fixed_root(locked.get(), parts, uid,
                         FixedRootAccess::provision, error))
      return {};
  }
  // A failed attempt may leave only verified 0700 ancestor directories.
  // Retrying is safe: existing components take the same no-follow trust path.
  return open_from_home_fd_impl(locked.get(), uid, error);
}

namespace {

bool secure_absolute_ancestor(const struct stat &metadata,
                              std::uint32_t uid) noexcept {
  return S_ISDIR(metadata.st_mode) &&
         (metadata.st_uid == 0 || metadata.st_uid == uid) &&
         (metadata.st_mode & 0022) == 0;
}

OwnedDescriptor open_absolute_home(std::string_view path,
                                   std::uint32_t uid) {
  if (path.empty() || path.front() != '/')
    return {};
  OwnedDescriptor current(
      ::open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW));
  struct stat root_metadata{};
  if (!current || ::fstat(current.get(), &root_metadata) < 0 ||
      !secure_absolute_ancestor(root_metadata, uid))
    return {};
  std::size_t offset = 1;
  while (offset < path.size()) {
    while (offset < path.size() && path[offset] == '/')
      ++offset;
    if (offset == path.size())
      break;
    const auto end = path.find('/', offset);
    const auto component =
        path.substr(offset, end == std::string_view::npos ? path.size() - offset
                                                          : end - offset);
    if (component.empty() || component == "." || component == "..")
      return {};
    const std::string name(component);
    OwnedDescriptor next(
        ::openat(current.get(), name.c_str(),
                 O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW));
    if (!next)
      return {};
    struct stat metadata{};
    if (::fstat(next.get(), &metadata) < 0 ||
        !secure_absolute_ancestor(metadata, uid))
      return {};
    current = std::move(next);
    if (end == std::string_view::npos)
      break;
    offset = end + 1;
  }
  return current;
}

using AccountLookup = int (*)(uid_t, struct passwd *, char *, std::size_t,
                              struct passwd **);

int system_account_lookup(uid_t uid, struct passwd *account, char *buffer,
                          std::size_t buffer_size,
                          struct passwd **result) noexcept {
  return ::getpwuid_r(uid, account, buffer, buffer_size, result);
}

OwnedDescriptor resolve_account_home(uid_t effective_uid,
                                     std::size_t initial_buffer_size,
                                     AccountLookup lookup,
                                     RuntimeRootsError &error) {
  if (lookup == nullptr || initial_buffer_size == 0 ||
      initial_buffer_size > kMaximumPasswdBuffer) {
    error = RuntimeRootsError::account_unavailable;
    return {};
  }
  std::vector<char> buffer(initial_buffer_size);
  struct passwd account{};
  struct passwd *result = nullptr;
  int status = 0;
  bool completed = false;
  for (std::size_t attempt = 0; attempt < kMaximumAccountLookupAttempts;
       ++attempt) {
    result = nullptr;
    status = lookup(effective_uid, &account, buffer.data(), buffer.size(),
                    &result);
    if (status == EINTR)
      continue;
    if (status == ERANGE) {
      if (buffer.size() >= kMaximumPasswdBuffer)
        break;
      buffer.resize(
          std::min(kMaximumPasswdBuffer, buffer.size() * std::size_t{2}));
      continue;
    }
    completed = true;
    break;
  }
  if (!completed || status != 0 || result != &account ||
      account.pw_uid != effective_uid || account.pw_dir == nullptr) {
    error = RuntimeRootsError::account_unavailable;
    return {};
  }
  auto home = open_absolute_home(account.pw_dir,
                                 static_cast<std::uint32_t>(effective_uid));
  if (!home)
    error = RuntimeRootsError::home_untrusted;
  return home;
}

} // namespace

#ifdef OMARCHY_RUNTIME_ROOTS_TESTING
void set_candidate_record_crash_point_for_testing(
    CandidateRecordCrashPoint point) noexcept {
  candidate_crash_point = point;
}

void set_provisioning_race_hook_for_testing(
    ProvisioningRacePoint point, ProvisioningRaceHook hook) noexcept {
  provisioning_race_point = point;
  provisioning_race_hook = hook;
}
#endif

RuntimeRoots::RuntimeRoots(std::uint32_t trusted_uid,
                                             OwnedDescriptor revisions,
                                             OwnedDescriptor activations,
                                             OwnedDescriptor authority,
                                             OwnedDescriptor state) noexcept
    : trusted_uid_(trusted_uid), revisions_(std::move(revisions)),
      activations_(std::move(activations)), authority_(std::move(authority)),
      state_(std::move(state)) {}

omarchy::plugins::discovery::PublishedRevision
RuntimeRoots::stage_revision_for_review(int archive_fd) const {
  auto published = omarchy::plugins::discovery::publish_revision_archive(
      archive_fd, revisions_.get(), trusted_uid_);
  const auto &plugin = published.verified().manifest.id;
  const auto &digest = published.verified().identity.tree_sha256;
  ensure_private_plugin_directory(state_.get(), plugin, trusted_uid_);
  ensure_private_plugin_directory(authority_.get(), plugin, trusted_uid_);
  publish_candidate_record(
      activations_.get(),
      {.plugin_id = plugin,
       .revision_directory = digest,
       .revision_sha256 = digest,
       .state_directory = plugin},
      trusted_uid_);
  return published;
}

std::unique_ptr<RuntimeRoots>
RuntimeRoots::open(RuntimeRootsError &error) noexcept {
  error = RuntimeRootsError::none;
  try {
    const uid_t effective_uid = ::geteuid();
    if (static_cast<std::uintmax_t>(effective_uid) >
        std::numeric_limits<std::uint32_t>::max()) {
      error = RuntimeRootsError::account_unavailable;
      return {};
    }
    long suggested = ::sysconf(_SC_GETPW_R_SIZE_MAX);
    if (suggested < 0)
      suggested = 16 * 1024;
    if (static_cast<std::uintmax_t>(suggested) > kMaximumPasswdBuffer) {
      error = RuntimeRootsError::account_unavailable;
      return {};
    }
    std::size_t buffer_size = static_cast<std::size_t>(suggested);
    if (buffer_size == 0)
      buffer_size = 1024;
    auto home = resolve_account_home(effective_uid, buffer_size,
                                     system_account_lookup, error);
    if (!home)
      return {};
    return provision_from_home_fd_impl(
        home.get(), static_cast<std::uint32_t>(effective_uid), error);
  } catch (const std::bad_alloc &) {
    error = RuntimeRootsError::resource_exhausted;
    return {};
  } catch (...) {
    error = RuntimeRootsError::internal_failure;
    return {};
  }
}

#ifdef OMARCHY_RUNTIME_ROOTS_TESTING
std::unique_ptr<RuntimeRoots> RuntimeRoots::open_from_home_fd(
    int home_fd, std::uint32_t trusted_uid,
    RuntimeRootsError &error) noexcept {
  error = RuntimeRootsError::none;
  try {
    return open_from_home_fd_impl(home_fd, trusted_uid, error);
  } catch (const std::bad_alloc &) {
    error = RuntimeRootsError::resource_exhausted;
    return {};
  } catch (...) {
    error = RuntimeRootsError::internal_failure;
    return {};
  }
}

std::unique_ptr<RuntimeRoots> RuntimeRoots::provision_from_home_fd(
    int home_fd, std::uint32_t trusted_uid,
    RuntimeRootsError &error) noexcept {
  error = RuntimeRootsError::none;
  try {
    return provision_from_home_fd_impl(home_fd, trusted_uid, error);
  } catch (const std::bad_alloc &) {
    error = RuntimeRootsError::resource_exhausted;
    return {};
  } catch (...) {
    error = RuntimeRootsError::internal_failure;
    return {};
  }
}

int RuntimeRoots::open_absolute_home_for_test(
    const char *path, std::uint32_t trusted_uid,
    RuntimeRootsError &error) noexcept {
  error = RuntimeRootsError::none;
  if (path == nullptr) {
    error = RuntimeRootsError::home_untrusted;
    return -1;
  }
  try {
    auto home = open_absolute_home(path, trusted_uid);
    if (!home)
      error = RuntimeRootsError::home_untrusted;
    return home.release();
  } catch (const std::bad_alloc &) {
    error = RuntimeRootsError::resource_exhausted;
    return -1;
  } catch (...) {
    error = RuntimeRootsError::internal_failure;
    return -1;
  }
}

int RuntimeRoots::resolve_account_home_for_test(
    std::uint32_t trusted_uid, std::size_t initial_buffer_size,
    AccountLookupForTest lookup,
    RuntimeRootsError &error) noexcept {
  error = RuntimeRootsError::none;
  try {
    auto home = resolve_account_home(static_cast<uid_t>(trusted_uid),
                                     initial_buffer_size, lookup, error);
    return home.release();
  } catch (const std::bad_alloc &) {
    error = RuntimeRootsError::resource_exhausted;
    return -1;
  } catch (...) {
    error = RuntimeRootsError::internal_failure;
    return -1;
  }
}

bool RuntimeRoots::absolute_ancestor_is_secure_for_test(
    std::uint32_t owner_uid, std::uint32_t mode,
    std::uint32_t trusted_uid) noexcept {
  struct stat metadata{};
  metadata.st_uid = static_cast<uid_t>(owner_uid);
  metadata.st_mode = static_cast<mode_t>(mode);
  return secure_absolute_ancestor(metadata, trusted_uid);
}
#endif

} // namespace omarchy::plugin_runtime::channel
