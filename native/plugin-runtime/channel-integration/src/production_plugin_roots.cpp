#include "production_plugin_roots.hpp"

#include <fcntl.h>
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
#include <string>
#include <string_view>
#include <vector>

namespace omarchy::plugin_runtime::channel {
namespace {

using host_session::OwnedDescriptor;

constexpr std::size_t kMaximumPasswdBuffer = 1024 * 1024;
constexpr std::size_t kMaximumAccountLookupAttempts = 16;
constexpr std::array<std::string_view, 6> kRevisionComponents{
    ".local", "share", "omarchy", "plugin-security", "v2", "revisions"};
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

OwnedDescriptor duplicate_directory(int descriptor) noexcept {
  if (descriptor < 0)
    return {};
  return OwnedDescriptor(::openat(
      descriptor, ".", O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW));
}

template <std::size_t Size>
OwnedDescriptor
open_fixed_root(int home_fd, const std::array<std::string_view, Size> &parts,
                std::uint32_t uid, ProductionPluginRootsError &error) {
  auto current = duplicate_directory(home_fd);
  if (!current) {
    error = ProductionPluginRootsError::home_untrusted;
    return {};
  }
  for (std::size_t index = 0; index < parts.size(); ++index) {
    const std::string component(parts[index]);
    OwnedDescriptor next(
        ::openat(current.get(), component.c_str(),
                 O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW));
    if (!next) {
      error = ProductionPluginRootsError::path_unavailable;
      return {};
    }
    struct stat metadata{};
    if (::fstat(next.get(), &metadata) < 0) {
      error = ProductionPluginRootsError::path_unavailable;
      return {};
    }
    const bool leaf = index + 1 == parts.size();
    if ((leaf && !exact_private_root(metadata, uid)) ||
        (!leaf && !secure_parent(metadata, uid))) {
      error = ProductionPluginRootsError::root_untrusted;
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

std::unique_ptr<ProductionPluginRoots>
ProductionPluginRoots::open_from_home_fd_impl(
    int home_fd, std::uint32_t uid, ProductionPluginRootsError &error) {
  struct stat home_metadata{};
  if (home_fd < 0 || ::fstat(home_fd, &home_metadata) < 0 ||
      !secure_parent(home_metadata, uid)) {
    error = ProductionPluginRootsError::home_untrusted;
    return {};
  }
  auto revisions = open_fixed_root(home_fd, kRevisionComponents, uid, error);
  if (!revisions)
    return {};
  auto activations =
      open_fixed_root(home_fd, kActivationComponents, uid, error);
  if (!activations)
    return {};
  auto authority = open_fixed_root(home_fd, kAuthorityComponents, uid, error);
  if (!authority)
    return {};
  auto state = open_fixed_root(home_fd, kStateComponents, uid, error);
  if (!state)
    return {};

  const std::array identities{identity(revisions.get()),
                              identity(activations.get()),
                              identity(authority.get()), identity(state.get())};
  if (!std::ranges::all_of(
          identities, [](const auto &value) { return value.has_value(); })) {
    error = ProductionPluginRootsError::root_untrusted;
    return {};
  }
  const std::array exact{*identities[0], *identities[1], *identities[2],
                         *identities[3]};
  if (!host_session::distinct_authority_objects(exact)) {
    error = ProductionPluginRootsError::aliased_roots;
    return {};
  }
  error = ProductionPluginRootsError::none;
  return std::unique_ptr<ProductionPluginRoots>(new ProductionPluginRoots(
      uid, std::move(revisions), std::move(activations), std::move(authority),
      std::move(state)));
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
                                     ProductionPluginRootsError &error) {
  if (lookup == nullptr || initial_buffer_size == 0 ||
      initial_buffer_size > kMaximumPasswdBuffer) {
    error = ProductionPluginRootsError::account_unavailable;
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
    error = ProductionPluginRootsError::account_unavailable;
    return {};
  }
  auto home = open_absolute_home(account.pw_dir,
                                 static_cast<std::uint32_t>(effective_uid));
  if (!home)
    error = ProductionPluginRootsError::home_untrusted;
  return home;
}

} // namespace

ProductionPluginRoots::ProductionPluginRoots(std::uint32_t trusted_uid,
                                             OwnedDescriptor revisions,
                                             OwnedDescriptor activations,
                                             OwnedDescriptor authority,
                                             OwnedDescriptor state) noexcept
    : trusted_uid_(trusted_uid), revisions_(std::move(revisions)),
      activations_(std::move(activations)), authority_(std::move(authority)),
      state_(std::move(state)) {}

std::unique_ptr<ProductionPluginRoots>
ProductionPluginRoots::open(ProductionPluginRootsError &error) noexcept {
  error = ProductionPluginRootsError::none;
  try {
    const uid_t effective_uid = ::geteuid();
    if (static_cast<std::uintmax_t>(effective_uid) >
        std::numeric_limits<std::uint32_t>::max()) {
      error = ProductionPluginRootsError::account_unavailable;
      return {};
    }
    long suggested = ::sysconf(_SC_GETPW_R_SIZE_MAX);
    if (suggested < 0)
      suggested = 16 * 1024;
    if (static_cast<std::uintmax_t>(suggested) > kMaximumPasswdBuffer) {
      error = ProductionPluginRootsError::account_unavailable;
      return {};
    }
    std::size_t buffer_size = static_cast<std::size_t>(suggested);
    if (buffer_size == 0)
      buffer_size = 1024;
    auto home = resolve_account_home(effective_uid, buffer_size,
                                     system_account_lookup, error);
    if (!home)
      return {};
    return open_from_home_fd_impl(
        home.get(), static_cast<std::uint32_t>(effective_uid), error);
  } catch (const std::bad_alloc &) {
    error = ProductionPluginRootsError::resource_exhausted;
    return {};
  } catch (...) {
    error = ProductionPluginRootsError::internal_failure;
    return {};
  }
}

#ifdef OMARCHY_PRODUCTION_PLUGIN_ROOTS_TESTING
std::unique_ptr<ProductionPluginRoots> ProductionPluginRoots::open_from_home_fd(
    int home_fd, std::uint32_t trusted_uid,
    ProductionPluginRootsError &error) noexcept {
  error = ProductionPluginRootsError::none;
  try {
    return open_from_home_fd_impl(home_fd, trusted_uid, error);
  } catch (const std::bad_alloc &) {
    error = ProductionPluginRootsError::resource_exhausted;
    return {};
  } catch (...) {
    error = ProductionPluginRootsError::internal_failure;
    return {};
  }
}

int ProductionPluginRoots::open_absolute_home_for_test(
    const char *path, std::uint32_t trusted_uid,
    ProductionPluginRootsError &error) noexcept {
  error = ProductionPluginRootsError::none;
  if (path == nullptr) {
    error = ProductionPluginRootsError::home_untrusted;
    return -1;
  }
  try {
    auto home = open_absolute_home(path, trusted_uid);
    if (!home)
      error = ProductionPluginRootsError::home_untrusted;
    return home.release();
  } catch (const std::bad_alloc &) {
    error = ProductionPluginRootsError::resource_exhausted;
    return -1;
  } catch (...) {
    error = ProductionPluginRootsError::internal_failure;
    return -1;
  }
}

int ProductionPluginRoots::resolve_account_home_for_test(
    std::uint32_t trusted_uid, std::size_t initial_buffer_size,
    AccountLookupForTest lookup,
    ProductionPluginRootsError &error) noexcept {
  error = ProductionPluginRootsError::none;
  try {
    auto home = resolve_account_home(static_cast<uid_t>(trusted_uid),
                                     initial_buffer_size, lookup, error);
    return home.release();
  } catch (const std::bad_alloc &) {
    error = ProductionPluginRootsError::resource_exhausted;
    return -1;
  } catch (...) {
    error = ProductionPluginRootsError::internal_failure;
    return -1;
  }
}

bool ProductionPluginRoots::absolute_ancestor_is_secure_for_test(
    std::uint32_t owner_uid, std::uint32_t mode,
    std::uint32_t trusted_uid) noexcept {
  struct stat metadata{};
  metadata.st_uid = static_cast<uid_t>(owner_uid);
  metadata.st_mode = static_cast<mode_t>(mode);
  return secure_absolute_ancestor(metadata, trusted_uid);
}
#endif

} // namespace omarchy::plugin_runtime::channel
