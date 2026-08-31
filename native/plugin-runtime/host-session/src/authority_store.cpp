#include "authority_store.hpp"
#include "authority_snapshot_codec.hpp"

#include "manifest_contract.hpp"

#include <algorithm>
#include <array>
#include <atomic>
#include <cerrno>
#include <charconv>
#include <fcntl.h>
#include <linux/fs.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <type_traits>
#include <unistd.h>
#include <vector>

namespace omarchy::plugin_runtime::host_session {
namespace {
constexpr std::string_view kLockName = ".authority.lock";
constexpr std::string_view kSlotsName = "slots";
std::atomic<std::uint64_t> temporary_sequence{1};

#ifdef OMARCHY_AUTHORITY_STORE_TESTING
std::atomic<AuthorityCrashPoint> authority_crash_point{
    AuthorityCrashPoint::none};

void crash_after(AuthorityCrashPoint point) noexcept {
  if (authority_crash_point.load(std::memory_order_relaxed) == point)
    ::_exit(86);
}
#define OMARCHY_AUTHORITY_CRASH_AFTER(point)                                   \
  crash_after(AuthorityCrashPoint::point)
#else
#define OMARCHY_AUTHORITY_CRASH_AFTER(point) ((void)0)
#endif

bool trusted_directory(const struct stat &metadata, std::uint32_t uid) {
  return S_ISDIR(metadata.st_mode) && metadata.st_uid == uid &&
         (metadata.st_mode & 0777) == 0700;
}

bool trusted_file(const struct stat &metadata, std::uint32_t uid) {
  return S_ISREG(metadata.st_mode) && metadata.st_uid == uid &&
         metadata.st_nlink == 1 && (metadata.st_mode & 0777) == 0600;
}

bool secure_created_file(int descriptor, std::uint32_t uid) {
  struct stat metadata{};
  return ::fchmod(descriptor, 0600) == 0 &&
         ::fstat(descriptor, &metadata) == 0 && trusted_file(metadata, uid);
}

std::optional<std::vector<std::byte>> read_file(int root_fd,
                                                std::string_view name,
                                                std::uint32_t uid,
                                                bool missing_is_empty = false) {
  const std::string owned_name(name);
  OwnedDescriptor file(
      ::openat(root_fd, owned_name.c_str(),
               O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK));
  if (!file)
    return missing_is_empty && errno == ENOENT
               ? std::optional(std::vector<std::byte>{})
               : std::nullopt;
  struct stat before{}, after{};
  if (::fstat(file.get(), &before) < 0 || !trusted_file(before, uid) ||
      before.st_size < 0 ||
      static_cast<std::uint64_t>(before.st_size) >
          authority_snapshot_codec::kMaximumEncodedAuthorityBytes)
    return std::nullopt;
  std::vector<std::byte> bytes(static_cast<std::size_t>(before.st_size));
  std::size_t offset = 0;
  while (offset < bytes.size()) {
    const auto count =
        ::read(file.get(), bytes.data() + offset, bytes.size() - offset);
    if (count < 0 && errno == EINTR)
      continue;
    if (count <= 0)
      return std::nullopt;
    offset += static_cast<std::size_t>(count);
  }
  std::byte trailing{};
  if (::read(file.get(), &trailing, 1) != 0)
    return std::nullopt;
  if (::fstat(file.get(), &after) < 0 || before.st_dev != after.st_dev ||
      before.st_ino != after.st_ino || before.st_size != after.st_size ||
      before.st_mtim.tv_sec != after.st_mtim.tv_sec ||
      before.st_mtim.tv_nsec != after.st_mtim.tv_nsec)
    return std::nullopt;
  return bytes;
}

bool write_all(int descriptor, std::span<const std::byte> bytes) {
  while (!bytes.empty()) {
    const auto count = ::write(descriptor, bytes.data(), bytes.size());
    if (count < 0 && errno == EINTR)
      continue;
    if (count <= 0)
      return false;
    bytes = bytes.subspan(static_cast<std::size_t>(count));
  }
  return true;
}

std::string temporary_name(std::string_view role) {
  return "." + std::string(role) + "." + std::to_string(::getpid()) + "." +
         std::to_string(temporary_sequence.fetch_add(1));
}

std::string digest(std::span<const std::byte> bytes) {
  return plugins::manifest::sha256_hex(bytes);
}

std::string record_name(const AuthorityRevisionRef &reference) {
  return "grant-" + std::string(reference.snapshot_digest.view());
}

std::optional<AuthoritySlots> read_slots_unlocked(int root_fd,
                                                  std::uint32_t uid) {
  struct stat metadata{};
  if (::fstatat(root_fd, std::string(kSlotsName).c_str(), &metadata,
                AT_SYMLINK_NOFOLLOW) < 0) {
    if (errno == ENOENT)
      return AuthoritySlots{};
    return std::nullopt;
  }
  auto bytes = read_file(root_fd, kSlotsName, uid);
  if (!bytes)
    return std::nullopt;
  return authority_snapshot_codec::decode_slots(*bytes);
}

bool canonical_digest(const permissions::Digest &value) {
  return value.size() == 64 && std::ranges::all_of(value.view(), [](char byte) {
           return (byte >= '0' && byte <= '9') || (byte >= 'a' && byte <= 'f');
         });
}

bool valid_slots(const AuthoritySlots &slots) {
  if (slots.sequence < slots.generation_high_watermark)
    return false;
  for (const auto *reference : {&slots.active, &slots.candidate}) {
    if (!*reference)
      continue;
    if (!canonical_digest((*reference)->snapshot_digest) ||
        (*reference)->generation == 0 ||
        (*reference)->generation > slots.generation_high_watermark)
      return false;
  }
  if (slots.candidate &&
      slots.candidate->generation != slots.generation_high_watermark)
    return false;
  if (slots.active && slots.candidate &&
      slots.active->generation >= slots.candidate->generation)
    return false;
  return true;
}

void cleanup_unreferenced(int root_fd, const AuthoritySlots &before,
                          const AuthoritySlots &after) {
  const auto retained = [&after](const AuthorityRevisionRef &reference) {
    return (after.active &&
            after.active->snapshot_digest == reference.snapshot_digest) ||
           (after.candidate &&
            after.candidate->snapshot_digest == reference.snapshot_digest);
  };
  std::optional<permissions::Digest> removed;
  for (const auto *reference : {&before.active, &before.candidate}) {
    if (!*reference || retained(**reference) ||
        (removed && *removed == (*reference)->snapshot_digest))
      continue;
    if (::unlinkat(root_fd, record_name(**reference).c_str(), 0) == 0)
      removed = (*reference)->snapshot_digest;
  }
  if (removed)
    (void)::fsync(root_fd);
}

std::optional<policy::GrantSnapshot>
load_snapshot(int root_fd, std::uint32_t uid,
              const AuthorityRevisionRef &reference) {
  auto bytes = read_file(root_fd, record_name(reference), uid);
  if (!bytes || digest(*bytes) != reference.snapshot_digest.view())
    return std::nullopt;
  policy::GrantSnapshot snapshot;
  std::vector<std::byte> canonical;
  if (!authority_snapshot_codec::decode_snapshot(*bytes, snapshot) ||
      !authority_snapshot_codec::encode_snapshot(snapshot, canonical) ||
      canonical != *bytes ||
      snapshot.binding.generation != reference.generation)
    return std::nullopt;
  try {
    permissions::PermissionAuthority builtin(
        snapshot.binding, snapshot.requests, snapshot.grants);
    (void)builtin;
    if (permissions::policy_request_fingerprint(snapshot.requests) !=
        snapshot.binding.policy_fingerprint.view())
      return std::nullopt;
    definitions::Name previous;
    bool have_previous = false;
    for (const auto &dynamic : snapshot.dynamic_grants) {
      if (dynamic.binding != snapshot.binding ||
          dynamic.request.definition != dynamic.grant.definition ||
          dynamic.grant.epoch == 0 ||
          static_cast<std::uint8_t>(dynamic.grant.state) >
              static_cast<std::uint8_t>(permissions::GrantState::revoked) ||
          !std::ranges::all_of(dynamic.grant.operations.values(),
                               [&](const auto &operation) {
                                 return dynamic.request.operations.contains(
                                     operation);
                               }) ||
          (have_previous &&
           !(previous < dynamic.request.definition.canonical_name)))
        return std::nullopt;
      previous = dynamic.request.definition.canonical_name;
      have_previous = true;
    }
  } catch (...) {
    return std::nullopt;
  }
  return snapshot;
}

AuthorityMutationResult
store_snapshot_record(int root_fd, std::uint32_t expected_uid,
                      const policy::GrantSnapshot &snapshot,
                      AuthorityRevisionRef &reference) {
  std::vector<std::byte> bytes;
  if (!authority_snapshot_codec::encode_snapshot(snapshot, bytes))
    return AuthorityMutationResult::invalid;
  const auto hash = digest(bytes);
  reference = authority_snapshot_codec::reference_for(snapshot, hash);
  const auto name = record_name(reference);
  const auto temporary = temporary_name("grant");
  OwnedDescriptor file(
      ::openat(root_fd, temporary.c_str(),
               O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, 0600));
  if (!file || !secure_created_file(file.get(), expected_uid) ||
      !write_all(file.get(), bytes)) {
    ::unlinkat(root_fd, temporary.c_str(), 0);
    return AuthorityMutationResult::io_error;
  }
  OMARCHY_AUTHORITY_CRASH_AFTER(grant_write);
  if (::fsync(file.get()) < 0) {
    ::unlinkat(root_fd, temporary.c_str(), 0);
    return AuthorityMutationResult::io_error;
  }
  OMARCHY_AUTHORITY_CRASH_AFTER(grant_file_sync);
  if (::syscall(SYS_renameat2, root_fd, temporary.c_str(), root_fd,
                name.c_str(), RENAME_NOREPLACE) < 0) {
    if (errno != EEXIST) {
      ::unlinkat(root_fd, temporary.c_str(), 0);
      return AuthorityMutationResult::io_error;
    }
    auto existing = read_file(root_fd, name, expected_uid);
    if (!existing || *existing != bytes ||
        ::unlinkat(root_fd, temporary.c_str(), 0) < 0) {
      ::unlinkat(root_fd, temporary.c_str(), 0);
      return AuthorityMutationResult::io_error;
    }
  }
  OMARCHY_AUTHORITY_CRASH_AFTER(grant_rename);
  if (::fsync(root_fd) < 0)
    return AuthorityMutationResult::io_error;
  OMARCHY_AUTHORITY_CRASH_AFTER(grant_directory_sync);
  return AuthorityMutationResult::applied;
}

bool activatable(const policy::GrantSnapshot &snapshot) {
  for (const auto &request : snapshot.requests.values()) {
    if (!request.required)
      continue;
    const auto granted =
        std::ranges::find_if(snapshot.grants.values(), [&](const auto &grant) {
          return grant.capability == request.capability &&
                 grant.state == permissions::GrantState::granted;
        });
    if (granted == snapshot.grants.values().end())
      return false;
  }
  return std::ranges::all_of(snapshot.dynamic_grants, [](const auto &dynamic) {
    return !dynamic.request.required ||
           dynamic.grant.state == permissions::GrantState::granted;
  });
}
} // namespace

AuthorityStore::AuthorityStore(OwnedDescriptor root, OwnedDescriptor lock,
                               std::uint32_t expected_uid,
                               permissions::PluginId expected_plugin)
    : root_(std::move(root)), lock_(std::move(lock)),
      expected_uid_(expected_uid), expected_plugin_(std::move(expected_plugin)),
      owner_pid_(::getpid()) {}

AuthorityStore::~AuthorityStore() {
  std::unique_lock lock(mutation_mutex_);
  auto live = bound_live_.lock();
  bound_live_.reset();
  if (!live)
    return;
  const auto closed = live->close_effect_admission();
  lock.unlock();
  if (closed == LiveGenerationState::EffectAdmissionCloseResult::ready_to_drain)
    live->drain_closed_effects();
}

std::unique_ptr<AuthorityStore>
AuthorityStore::open(int root_directory_fd, std::uint32_t expected_uid,
                     permissions::PluginId expected_plugin) {
  OwnedDescriptor root(::fcntl(root_directory_fd, F_DUPFD_CLOEXEC, 0));
  struct stat metadata{};
  if (!root || ::fstat(root.get(), &metadata) < 0 ||
      !trusted_directory(metadata, expected_uid))
    return nullptr;
  int lock_fd = ::openat(
      root.get(), std::string(kLockName).c_str(),
      O_RDWR | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK, 0600);
  if (lock_fd >= 0) {
    if (!secure_created_file(lock_fd, expected_uid)) {
      ::close(lock_fd);
      return nullptr;
    }
  } else if (errno == EEXIST) {
    lock_fd = ::openat(root.get(), std::string(kLockName).c_str(),
                       O_RDWR | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK);
  }
  OwnedDescriptor lock(lock_fd);
  if (!lock || ::fstat(lock.get(), &metadata) < 0 ||
      !trusted_file(metadata, expected_uid) ||
      ::flock(lock.get(), LOCK_EX | LOCK_NB) < 0)
    return nullptr;
  return std::unique_ptr<AuthorityStore>(
      new AuthorityStore(std::move(root), std::move(lock), expected_uid,
                         std::move(expected_plugin)));
}

std::optional<AuthoritySlots> AuthorityStore::read_slots() const {
  std::scoped_lock lock(mutation_mutex_);
  if (::getpid() != owner_pid_ || poisoned_ || transitioning_)
    return std::nullopt;
  auto slots = read_slots_unlocked(root_.get(), expected_uid_);
  if (!slots || !valid_slots(*slots))
    return std::nullopt;
  return slots;
}

std::optional<AuthorityView> AuthorityStore::read_authority_view() const {
  std::scoped_lock lock(mutation_mutex_);
  if (::getpid() != owner_pid_ || poisoned_ || transitioning_)
    return std::nullopt;
  auto slots = read_slots_unlocked(root_.get(), expected_uid_);
  if (!slots || !valid_slots(*slots))
    return std::nullopt;
  std::optional<policy::GrantSnapshot> active;
  if (slots->active) {
    active = load_snapshot(root_.get(), expected_uid_, *slots->active);
    if (!active || active->binding.plugin != expected_plugin_)
      return std::nullopt;
  }
  return AuthorityView{.authority_slots = *slots, .active = std::move(active)};
}

std::optional<FilesystemIdentity> AuthorityStore::root_identity() const {
  std::scoped_lock lock(mutation_mutex_);
  struct stat metadata{};
  if (::getpid() != owner_pid_ || ::fstat(root_.get(), &metadata) < 0)
    return std::nullopt;
  return FilesystemIdentity{
      .device = static_cast<std::uint64_t>(metadata.st_dev),
      .inode = static_cast<std::uint64_t>(metadata.st_ino)};
}

std::optional<PreparedLiveBinding> AuthorityStore::prepare_live_activation(
    const permissions::ActivationBinding &binding,
    const std::shared_ptr<LiveGenerationState> &live) {
  std::unique_lock lock(mutation_mutex_);
  if (::getpid() != owner_pid_ || poisoned_ || transitioning_ || !live ||
      !live->current(binding))
    return {};
  auto slots = read_slots_unlocked(root_.get(), expected_uid_);
  if (!slots || !valid_slots(*slots) || !slots->active ||
      slots->active->generation != binding.generation)
    return {};
  auto active = load_snapshot(root_.get(), expected_uid_, *slots->active);
  if (!active || active->binding != binding || !activatable(*active))
    return {};
  struct stat metadata{};
  if (::fstat(root_.get(), &metadata) < 0)
    return {};
  const FilesystemIdentity identity{
      .device = static_cast<std::uint64_t>(metadata.st_dev),
      .inode = static_cast<std::uint64_t>(metadata.st_ino)};
  prepared_root_identity_ = identity;
  if (auto previous = bound_live_.lock(); previous != live) {
    const auto fenced = fence_bound_live(lock, *slots);
    if (fenced != AuthorityMutationResult::applied)
      return {};
    if (!live->current(binding)) {
      transitioning_ = false;
      return {};
    }
    bound_live_ = live;
    transitioning_ = false;
  }
  if (mutation_epoch_ == UINT64_MAX)
    return {};
  ++mutation_epoch_;
  return PreparedLiveBinding(this, identity, binding, live, mutation_epoch_);
}

bool AuthorityStore::commit_live_activation(
    PreparedLiveBinding prepared,
    const permissions::ActivationBinding &expected_binding,
    const std::shared_ptr<LiveGenerationState> &expected_live) {
  std::scoped_lock lock(mutation_mutex_);
  const auto bound = bound_live_.lock();
  if (prepared.owner_ != this || ::getpid() != owner_pid_ || poisoned_ ||
      transitioning_ || prepared.mutation_epoch_ != mutation_epoch_ ||
      prepared_root_identity_ != prepared.root_identity_ ||
      prepared.binding_ != expected_binding ||
      prepared.live_ != expected_live || bound != prepared.live_ ||
      !prepared.live_ || !prepared.live_->current(prepared.binding_) ||
      mutation_epoch_ == UINT64_MAX)
    return false;
  ++mutation_epoch_;
  return true;
}

AuthorityMutationResult
AuthorityStore::fence_bound_live(std::unique_lock<std::mutex> &lock,
                                 const AuthoritySlots &preimage,
                                 AuthorityFenceObserver *observer) {
  if (!lock.owns_lock() || transitioning_ || poisoned_)
    return poisoned_ ? AuthorityMutationResult::poisoned
                     : AuthorityMutationResult::invalid;
  transitioning_ = true;
  auto live = bound_live_.lock();
  bound_live_.reset();
  if (live) {
    const auto closed = live->close_effect_admission();
    if (observer)
      observer->live_generation_closed();
    if (closed == LiveGenerationState::EffectAdmissionCloseResult::reentrant) {
      transitioning_ = false;
      poisoned_ = true;
      return AuthorityMutationResult::reentrant_effect;
    }
    lock.unlock();
    live->drain_closed_effects();
    lock.lock();
  }
  try {
    const auto exact = read_slots_unlocked(root_.get(), expected_uid_);
    if (::getpid() != owner_pid_ || !transitioning_ || !exact ||
        *exact != preimage) {
      transitioning_ = false;
      poisoned_ = true;
      return AuthorityMutationResult::io_error;
    }
  } catch (...) {
    transitioning_ = false;
    poisoned_ = true;
    return AuthorityMutationResult::io_error;
  }
  return AuthorityMutationResult::applied;
}

AuthorityMutationResult AuthorityStore::replace_slots(AuthoritySlots slots) {
  const auto bytes = authority_snapshot_codec::encode_slots(slots);
  if (bytes.empty())
    return AuthorityMutationResult::invalid;
  const auto temporary = temporary_name("slots");
  OwnedDescriptor file(
      ::openat(root_.get(), temporary.c_str(),
               O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, 0600));
  if (!file || !secure_created_file(file.get(), expected_uid_) ||
      !write_all(file.get(), bytes)) {
    ::unlinkat(root_.get(), temporary.c_str(), 0);
    return AuthorityMutationResult::io_error;
  }
  OMARCHY_AUTHORITY_CRASH_AFTER(slots_write);
  if (::fsync(file.get()) < 0) {
    ::unlinkat(root_.get(), temporary.c_str(), 0);
    return AuthorityMutationResult::io_error;
  }
  OMARCHY_AUTHORITY_CRASH_AFTER(slots_file_sync);
  if (::renameat(root_.get(), temporary.c_str(), root_.get(),
                 std::string(kSlotsName).c_str()) < 0) {
    ::unlinkat(root_.get(), temporary.c_str(), 0);
    return AuthorityMutationResult::io_error;
  }
  OMARCHY_AUTHORITY_CRASH_AFTER(slots_rename);
  if (::fsync(root_.get()) < 0)
    return AuthorityMutationResult::io_error;
  OMARCHY_AUTHORITY_CRASH_AFTER(slots_directory_sync);
  return AuthorityMutationResult::applied;
}

#undef OMARCHY_AUTHORITY_CRASH_AFTER

#ifdef OMARCHY_AUTHORITY_STORE_TESTING
void AuthorityStore::set_crash_point_for_testing(
    AuthorityCrashPoint point) noexcept {
  authority_crash_point.store(point, std::memory_order_relaxed);
}

AuthorityMutationResult AuthorityStore::replace_active_for_testing(
    const policy::GrantSnapshot &snapshot) {
  std::scoped_lock lock(mutation_mutex_);
  auto slot_state = read_slots_unlocked(root_.get(), expected_uid_);
  if (!slot_state)
    return AuthorityMutationResult::io_error;
  AuthorityRevisionRef reference;
  const auto stored =
      store_snapshot_record(root_.get(), expected_uid_, snapshot, reference);
  if (stored != AuthorityMutationResult::applied)
    return stored;
  slot_state->active = std::move(reference);
  return replace_slots(std::move(*slot_state));
}
#endif

AuthorityMutationResult AuthorityStore::publish_candidate(
    const VerifiedRevision &verified, const policy::GrantSnapshot &snapshot,
    std::uint64_t expected_sequence,
    const definitions::TrustedDefinitionRegistry &definitions,
    definitions::DynamicScopeValidator scope_validator) {
  std::scoped_lock lock(mutation_mutex_);
  if (::getpid() != owner_pid_)
    return AuthorityMutationResult::io_error;
  if (mutation_epoch_ == UINT64_MAX)
    return AuthorityMutationResult::poisoned;
  ++mutation_epoch_;
  if (poisoned_ || transitioning_)
    return AuthorityMutationResult::poisoned;
  if (!authority_snapshot_codec::complete_snapshot(
          verified, snapshot, definitions, scope_validator))
    return AuthorityMutationResult::invalid;
  if (snapshot.binding.plugin != expected_plugin_)
    return AuthorityMutationResult::invalid;
  auto slots = read_slots_unlocked(root_.get(), expected_uid_);
  if (!slots || !valid_slots(*slots))
    return AuthorityMutationResult::io_error;
  if (slots->sequence != expected_sequence)
    return AuthorityMutationResult::stale_sequence;
  if (slots->sequence == UINT64_MAX)
    return AuthorityMutationResult::invalid;
  if (slots->generation_high_watermark == UINT64_MAX ||
      snapshot.binding.generation != slots->generation_high_watermark + 1)
    return AuthorityMutationResult::invalid;
  const auto previous = *slots;

  AuthorityRevisionRef reference;
  const auto stored =
      store_snapshot_record(root_.get(), expected_uid_, snapshot, reference);
  if (stored != AuthorityMutationResult::applied)
    return stored;
  slots->candidate = reference;
  slots->generation_high_watermark = snapshot.binding.generation;
  ++slots->sequence;
  const auto result = replace_slots(*slots);
  if (result == AuthorityMutationResult::applied)
    cleanup_unreferenced(root_.get(), previous, *slots);
  return result;
}

AuthorityMutationResult AuthorityStore::promote_candidate(
    const permissions::ActivationBinding &candidate,
    std::uint64_t expected_sequence) {
  return promote_candidate(candidate, expected_sequence, nullptr);
}

AuthorityMutationResult AuthorityStore::promote_candidate(
    const permissions::ActivationBinding &candidate,
    std::uint64_t expected_sequence, AuthorityFenceObserver *observer) {
  std::unique_lock lock(mutation_mutex_);
  if (::getpid() != owner_pid_)
    return AuthorityMutationResult::io_error;
  if (mutation_epoch_ == UINT64_MAX)
    return AuthorityMutationResult::poisoned;
  ++mutation_epoch_;
  if (poisoned_ || transitioning_)
    return AuthorityMutationResult::poisoned;
  auto slots = read_slots_unlocked(root_.get(), expected_uid_);
  if (!slots || !valid_slots(*slots))
    return AuthorityMutationResult::io_error;
  if (slots->sequence != expected_sequence)
    return AuthorityMutationResult::stale_sequence;
  if (!slots->candidate)
    return AuthorityMutationResult::invalid;
  auto candidate_snapshot =
      load_snapshot(root_.get(), expected_uid_, *slots->candidate);
  if (!candidate_snapshot)
    return AuthorityMutationResult::invalid;
  if (candidate_snapshot->binding != candidate)
    return AuthorityMutationResult::invalid;
  if (!activatable(*candidate_snapshot))
    return AuthorityMutationResult::invalid;
  if (slots->sequence == UINT64_MAX)
    return AuthorityMutationResult::invalid;
  const auto previous = *slots;
  const auto fenced = fence_bound_live(lock, previous, observer);
  if (fenced != AuthorityMutationResult::applied)
    return fenced;
  poisoned_ = true;
  try {
    slots->active = std::move(slots->candidate);
    slots->candidate.reset();
    ++slots->sequence;
    const auto result = replace_slots(*slots);
    if (result != AuthorityMutationResult::applied) {
      transitioning_ = false;
      return result;
    }
    cleanup_unreferenced(root_.get(), previous, *slots);
    poisoned_ = false;
    transitioning_ = false;
    return AuthorityMutationResult::applied;
  } catch (...) {
    transitioning_ = false;
    return AuthorityMutationResult::io_error;
  }
}

AuthorityMutationResult AuthorityStore::discard_candidate(
    const permissions::ActivationBinding &candidate,
    std::uint64_t expected_sequence) {
  std::scoped_lock lock(mutation_mutex_);
  if (::getpid() != owner_pid_)
    return AuthorityMutationResult::io_error;
  if (mutation_epoch_ == UINT64_MAX)
    return AuthorityMutationResult::poisoned;
  ++mutation_epoch_;
  if (poisoned_ || transitioning_)
    return AuthorityMutationResult::poisoned;
  auto slots = read_slots_unlocked(root_.get(), expected_uid_);
  if (!slots || !valid_slots(*slots))
    return AuthorityMutationResult::io_error;
  if (slots->sequence != expected_sequence)
    return AuthorityMutationResult::stale_sequence;
  if (!slots->candidate)
    return AuthorityMutationResult::invalid;
  auto candidate_snapshot =
      load_snapshot(root_.get(), expected_uid_, *slots->candidate);
  if (!candidate_snapshot || candidate_snapshot->binding != candidate)
    return AuthorityMutationResult::invalid;
  if (slots->sequence == UINT64_MAX)
    return AuthorityMutationResult::invalid;
  const auto previous = *slots;
  slots->candidate.reset();
  ++slots->sequence;
  const auto result = replace_slots(*slots);
  if (result == AuthorityMutationResult::applied)
    cleanup_unreferenced(root_.get(), previous, *slots);
  return result;
}

AuthorityRevocationResult
AuthorityStore::revoke_active(const permissions::CapabilityKey &capability,
                              std::uint64_t expected_sequence,
                              AuthorityFenceObserver *observer) {
  return revoke_active(&capability, nullptr, expected_sequence, observer);
}

AuthorityRevocationResult AuthorityStore::revoke_active(
    const definitions::CapabilityReference &definition,
    std::uint64_t expected_sequence, AuthorityFenceObserver *observer) {
  return revoke_active(nullptr, &definition, expected_sequence, observer);
}

AuthorityRevocationResult AuthorityStore::revoke_active(
    const permissions::CapabilityKey *capability,
    const definitions::CapabilityReference *definition,
    std::uint64_t expected_sequence, AuthorityFenceObserver *observer) {
  const auto failure = [](AuthorityMutationResult status) {
    return AuthorityRevocationResult{
        .status = status, .binding = std::nullopt, .activatable = false};
  };
  std::unique_lock lock(mutation_mutex_);
  if (::getpid() != owner_pid_)
    return failure(AuthorityMutationResult::io_error);
  if (mutation_epoch_ == UINT64_MAX)
    return failure(AuthorityMutationResult::poisoned);
  ++mutation_epoch_;
  if (poisoned_ || transitioning_)
    return failure(AuthorityMutationResult::poisoned);
  if ((capability == nullptr) == (definition == nullptr))
    return failure(AuthorityMutationResult::invalid);

  auto slots = read_slots_unlocked(root_.get(), expected_uid_);
  if (!slots || !valid_slots(*slots) || !slots->active)
    return failure(AuthorityMutationResult::io_error);
  if (slots->sequence != expected_sequence)
    return failure(AuthorityMutationResult::stale_sequence);
  if (slots->sequence == UINT64_MAX ||
      slots->generation_high_watermark == UINT64_MAX)
    return failure(AuthorityMutationResult::invalid);
  auto active = load_snapshot(root_.get(), expected_uid_, *slots->active);
  if (!active || active->binding.plugin != expected_plugin_)
    return failure(AuthorityMutationResult::io_error);

  bool found = false;
  if (capability != nullptr) {
    for (auto &grant : active->grants.values()) {
      if (grant.capability != *capability)
        continue;
      if (found || grant.state != permissions::GrantState::granted)
        return failure(AuthorityMutationResult::invalid);
      grant.state = permissions::GrantState::revoked;
      found = true;
    }
  } else {
    for (auto &dynamic : active->dynamic_grants) {
      if (dynamic.request.definition != *definition)
        continue;
      if (found || dynamic.grant.state != permissions::GrantState::granted)
        return failure(AuthorityMutationResult::invalid);
      dynamic.grant.state = permissions::GrantState::revoked;
      found = true;
    }
  }
  if (!found)
    return failure(AuthorityMutationResult::invalid);

  const auto next_generation = slots->generation_high_watermark + 1;
  active->binding.generation = next_generation;
  for (auto &grant : active->grants.values())
    grant.epoch = next_generation;
  for (auto &dynamic : active->dynamic_grants) {
    dynamic.binding = active->binding;
    dynamic.grant.epoch = next_generation;
  }

  const auto previous = *slots;
  const auto fenced = fence_bound_live(lock, previous, observer);
  if (fenced != AuthorityMutationResult::applied)
    return failure(fenced);
  // From this fence until a complete typed success result exists, every exit
  // leaves this process unable to reuse potentially ambiguous durable state.
  poisoned_ = true;
  try {
    AuthorityRevisionRef reference;
    const auto stored =
        store_snapshot_record(root_.get(), expected_uid_, *active, reference);
    if (stored != AuthorityMutationResult::applied)
      return failure(stored);

    slots->active = reference;
    slots->candidate.reset();
    slots->generation_high_watermark = next_generation;
    ++slots->sequence;
    const auto replaced = replace_slots(*slots);
    if (replaced != AuthorityMutationResult::applied)
      return failure(replaced);
    cleanup_unreferenced(root_.get(), previous, *slots);
    AuthorityRevocationResult success{.status =
                                          AuthorityMutationResult::applied,
                                      .binding = active->binding,
                                      .activatable = activatable(*active)};
    static_assert(
        std::is_nothrow_move_constructible_v<AuthorityRevocationResult>);
    poisoned_ = false;
    transitioning_ = false;
    return success;
  } catch (...) {
    // Once the old live generation is fenced, no exceptional persistence path
    // may leave this in-process store usable against ambiguous durable state.
    transitioning_ = false;
    return failure(AuthorityMutationResult::io_error);
  }
}

GrantResolution
AuthorityStore::resolve(std::string_view plugin_id,
                        std::string_view revision_sha256) const {
  std::scoped_lock lock(mutation_mutex_);
  if (::getpid() != owner_pid_ || poisoned_ || transitioning_)
    return {};
  auto slots = read_slots_unlocked(root_.get(), expected_uid_);
  if (!slots || !valid_slots(*slots) || plugin_id != expected_plugin_.view() ||
      !slots->active)
    return {};
  auto snapshot = load_snapshot(root_.get(), expected_uid_, *slots->active);
  if (!snapshot || snapshot->binding.plugin.view() != plugin_id ||
      snapshot->binding.revision.view() != revision_sha256)
    return {};
  const auto status = activatable(*snapshot) ? GrantStatus::activatable
                                             : GrantStatus::permission_disabled;
  return {.snapshot = std::move(snapshot), .status = status};
}

} // namespace omarchy::plugin_runtime::host_session
