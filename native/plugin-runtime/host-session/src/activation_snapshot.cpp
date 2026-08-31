#include "activation_snapshot.hpp"

#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

#include <array>
#include <cerrno>
#include <ranges>
#include <utility>

namespace omarchy::plugin_runtime::host_session {
namespace {

constexpr std::size_t kMaximumRecordBytes = 16 * 1024;

bool component(std::string_view value) {
  return !value.empty() && value != "." && value != ".." &&
         value.find('/') == std::string_view::npos &&
         value.find('\\') == std::string_view::npos &&
         value.find('\0') == std::string_view::npos;
}

bool digest(std::string_view value) {
  return value.size() == 64 &&
         std::ranges::all_of(value, [](unsigned char byte) {
           return (byte >= '0' && byte <= '9') || (byte >= 'a' && byte <= 'f');
         });
}

FilesystemIdentity identity_of(const struct stat &metadata) {
  return {.device = static_cast<std::uint64_t>(metadata.st_dev),
          .inode = static_cast<std::uint64_t>(metadata.st_ino)};
}

struct OpenedRecord {
  std::string bytes;
  OwnedDescriptor descriptor;
};

bool trusted_metadata(const struct stat &metadata, std::uint32_t trusted_uid,
                      mode_t expected_type) {
  return (metadata.st_mode & S_IFMT) == expected_type &&
         metadata.st_uid == trusted_uid && (metadata.st_mode & 0022) == 0;
}

bool unchanged_metadata(const struct stat &before, const struct stat &after) {
  return before.st_dev == after.st_dev && before.st_ino == after.st_ino &&
         before.st_mode == after.st_mode && before.st_uid == after.st_uid &&
         before.st_gid == after.st_gid && before.st_nlink == after.st_nlink &&
         before.st_size == after.st_size &&
         before.st_mtim.tv_sec == after.st_mtim.tv_sec &&
         before.st_mtim.tv_nsec == after.st_mtim.tv_nsec &&
         before.st_ctim.tv_sec == after.st_ctim.tv_sec &&
         before.st_ctim.tv_nsec == after.st_ctim.tv_nsec;
}

bool trusted_record_metadata(const struct stat &metadata,
                             std::uint32_t trusted_uid) {
  return S_ISREG(metadata.st_mode) && metadata.st_uid == trusted_uid &&
         metadata.st_nlink == 1 && (metadata.st_mode & 07777) == 0600;
}

std::optional<OpenedRecord> read_record(int root_fd, std::string_view name,
                                        std::uint32_t trusted_uid,
                                        ActivationError &error) {
  const std::string owned_name(name);
  const int fd = ::openat(root_fd, owned_name.c_str(),
                          O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK);
  if (fd < 0) {
    error = ActivationError::record_unavailable;
    return std::nullopt;
  }
  OwnedDescriptor owned(fd);
  struct stat metadata{};
  if (::fstat(fd, &metadata) < 0 ||
      !trusted_record_metadata(metadata, trusted_uid)) {
    error = ActivationError::record_untrusted;
    return std::nullopt;
  }
  if (metadata.st_size < 0 ||
      static_cast<std::uint64_t>(metadata.st_size) > kMaximumRecordBytes) {
    error = ActivationError::record_invalid;
    return std::nullopt;
  }
  std::string bytes;
  bytes.reserve(static_cast<std::size_t>(metadata.st_size));
  std::array<char, 4096> chunk{};
  for (;;) {
    const ssize_t count = ::read(fd, chunk.data(), chunk.size());
    if (count < 0 && errno == EINTR)
      continue;
    if (count < 0) {
      error = ActivationError::record_invalid;
      return std::nullopt;
    }
    if (count == 0)
      break;
    const auto amount = static_cast<std::size_t>(count);
    if (amount > kMaximumRecordBytes - bytes.size()) {
      error = ActivationError::record_invalid;
      return std::nullopt;
    }
    bytes.append(chunk.data(), amount);
  }
  struct stat final_metadata{};
  if (bytes.size() != static_cast<std::size_t>(metadata.st_size) ||
      ::fstat(fd, &final_metadata) < 0 ||
      !unchanged_metadata(metadata, final_metadata)) {
    error = ActivationError::record_invalid;
    return std::nullopt;
  }
  return OpenedRecord{.bytes = std::move(bytes),
                      .descriptor = std::move(owned)};
}

std::optional<ActivationRecord> parse_record(std::string_view bytes) {
  constexpr std::array<std::string_view, 5> keys{
      "format",          "plugin",          "revision-directory",
      "revision-sha256", "state-directory"};
  std::array<std::string_view, keys.size()> values{};
  std::size_t offset = 0;
  for (std::size_t index = 0; index < keys.size(); ++index) {
    const auto end = bytes.find('\n', offset);
    if (end == std::string_view::npos)
      return std::nullopt;
    const auto line = bytes.substr(offset, end - offset);
    const auto separator = line.find('=');
    if (separator == std::string_view::npos ||
        line.substr(0, separator) != keys[index])
      return std::nullopt;
    values[index] = line.substr(separator + 1);
    offset = end + 1;
  }
  if (offset != bytes.size() || values[0] != "omarchy-plugin-activation-v2" ||
      !component(values[1]) || !component(values[2]) || !digest(values[3]) ||
      !component(values[4]))
    return std::nullopt;
  return ActivationRecord{.plugin_id = std::string(values[1]),
                          .revision_directory = std::string(values[2]),
                          .revision_sha256 = std::string(values[3]),
                          .state_directory = std::string(values[4])};
}

std::optional<OwnedDescriptor> open_directory(int root_fd,
                                              std::string_view name) {
  const std::string owned_name(name);
  const int fd = ::openat(root_fd, owned_name.c_str(),
                          O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
  if (fd < 0)
    return std::nullopt;
  return OwnedDescriptor(fd);
}

bool authoritative_snapshot(const policy::GrantSnapshot &snapshot,
                            const ActivationRecord &record,
                            const VerifiedRevision &revision) {
  try {
    if (snapshot.binding.plugin.view() != record.plugin_id ||
        snapshot.binding.revision.view() != record.revision_sha256)
      return false;
    if (snapshot.source_request_fingerprint.view() != revision.request_sha256)
      return false;
    const permissions::Digest calculated(
        permissions::policy_request_fingerprint(snapshot.requests));
    if (snapshot.binding.policy_fingerprint != calculated)
      return false;
    permissions::validate_requests(snapshot.requests);
    permissions::PermissionAuthority authority(
        snapshot.binding, snapshot.requests, snapshot.grants);
    (void)authority;
    return true;
  } catch (...) {
    return false;
  }
}

ActivationResult failure(ActivationError error) {
  return {.snapshot = std::nullopt,
          .error = error,
          .grant_status = GrantStatus::unavailable};
}

} // namespace

std::optional<std::string>
encode_activation_record(const ActivationRecord &record) {
  if (!component(record.plugin_id) || !component(record.revision_directory) ||
      !digest(record.revision_sha256) || !component(record.state_directory))
    return std::nullopt;
  return "format=omarchy-plugin-activation-v2\nplugin=" + record.plugin_id +
         "\nrevision-directory=" + record.revision_directory +
         "\nrevision-sha256=" + record.revision_sha256 +
         "\nstate-directory=" + record.state_directory + "\n";
}

InspectedActivationRecord::InspectedActivationRecord(
    ActivationRecord record, OwnedDescriptor descriptor,
    StableMetadata metadata) noexcept
    : record_(std::move(record)), descriptor_(std::move(descriptor)),
      metadata_(metadata) {}

bool InspectedActivationRecord::unchanged() const noexcept {
  struct stat current {};
  return descriptor_ && ::fstat(descriptor_.get(), &current) == 0 &&
         metadata_.device == static_cast<std::uint64_t>(current.st_dev) &&
         metadata_.inode == static_cast<std::uint64_t>(current.st_ino) &&
         metadata_.size == static_cast<std::uint64_t>(current.st_size) &&
         metadata_.modified_seconds == current.st_mtim.tv_sec &&
         metadata_.modified_nanoseconds == current.st_mtim.tv_nsec &&
         metadata_.changed_seconds == current.st_ctim.tv_sec &&
         metadata_.changed_nanoseconds == current.st_ctim.tv_nsec &&
         metadata_.mode == static_cast<std::uint32_t>(current.st_mode) &&
         metadata_.uid == static_cast<std::uint32_t>(current.st_uid) &&
         metadata_.gid == static_cast<std::uint32_t>(current.st_gid) &&
         metadata_.links == static_cast<std::uint64_t>(current.st_nlink);
}

std::optional<InspectedActivationRecord>
inspect_activation_record(int activation_root_fd,
                          std::string_view record_name,
                          std::uint32_t trusted_uid) {
  if (!component(record_name))
    return std::nullopt;
  ActivationError error = ActivationError::none;
  auto opened = read_record(activation_root_fd, record_name, trusted_uid, error);
  if (!opened)
    return std::nullopt;
  struct stat metadata {};
  if (::fstat(opened->descriptor.get(), &metadata) < 0 ||
      !trusted_record_metadata(metadata, trusted_uid))
    return std::nullopt;
  auto record = parse_record(opened->bytes);
  if (!record)
    return std::nullopt;
  return InspectedActivationRecord(
      std::move(*record), std::move(opened->descriptor),
      InspectedActivationRecord::StableMetadata{
          .device = static_cast<std::uint64_t>(metadata.st_dev),
          .inode = static_cast<std::uint64_t>(metadata.st_ino),
          .size = static_cast<std::uint64_t>(metadata.st_size),
          .modified_seconds = metadata.st_mtim.tv_sec,
          .modified_nanoseconds = metadata.st_mtim.tv_nsec,
          .changed_seconds = metadata.st_ctim.tv_sec,
          .changed_nanoseconds = metadata.st_ctim.tv_nsec,
          .mode = static_cast<std::uint32_t>(metadata.st_mode),
          .uid = static_cast<std::uint32_t>(metadata.st_uid),
          .gid = static_cast<std::uint32_t>(metadata.st_gid),
          .links = static_cast<std::uint64_t>(metadata.st_nlink)});
}

bool distinct_authority_objects(
    std::span<const FilesystemIdentity> identities) noexcept {
  for (std::size_t left = 0; left < identities.size(); ++left) {
    for (std::size_t right = left + 1; right < identities.size(); ++right) {
      if (identities[left] == identities[right])
        return false;
    }
  }
  return true;
}

OwnedDescriptor::~OwnedDescriptor() {
  if (descriptor_ >= 0)
    ::close(descriptor_);
}

OwnedDescriptor::OwnedDescriptor(OwnedDescriptor &&other) noexcept
    : descriptor_(std::exchange(other.descriptor_, -1)) {}

OwnedDescriptor &OwnedDescriptor::operator=(OwnedDescriptor &&other) noexcept {
  if (this != &other) {
    if (descriptor_ >= 0)
      ::close(descriptor_);
    descriptor_ = std::exchange(other.descriptor_, -1);
  }
  return *this;
}

int OwnedDescriptor::release() noexcept {
  return std::exchange(descriptor_, -1);
}

LiveGenerationState::LiveGenerationState(permissions::ActivationBinding binding)
    : plugin_(std::move(binding.plugin)),
      revision_(std::move(binding.revision)),
      policy_fingerprint_(std::move(binding.policy_fingerprint)),
      generation_(binding.generation) {}

bool LiveGenerationState::current(
    const permissions::ActivationBinding &binding) const noexcept {
  const auto generation = generation_.load(std::memory_order_acquire);
  return generation != 0 && generation == binding.generation &&
         plugin_ == binding.plugin && revision_ == binding.revision &&
         policy_fingerprint_ == binding.policy_fingerprint;
}

std::uint64_t LiveGenerationState::generation() const noexcept {
  return generation_.load(std::memory_order_acquire);
}

LiveGenerationState::EffectToken::EffectToken(
    std::shared_ptr<LiveGenerationState> state, std::uint64_t use_id) noexcept
    : state_(std::move(state)), use_id_(use_id) {}

LiveGenerationState::EffectToken::EffectToken(EffectToken &&other) noexcept
    : state_(std::move(other.state_)), use_id_(other.use_id_) {}

LiveGenerationState::EffectToken::~EffectToken() {
  if (!state_)
    return;
  state_->release_effect(use_id_);
}

bool LiveGenerationState::EffectToken::current() const noexcept {
  return state_ && state_->effect_current(use_id_);
}

std::optional<LiveGenerationState::EffectToken>
LiveGenerationState::acquire_effect(
    const permissions::ActivationBinding &binding) {
  auto state = shared_from_this();
  std::scoped_lock lock(effect_mutex_);
  if (!current(binding))
    return std::nullopt;
  if (next_effect_id_ == UINT64_MAX)
    return std::nullopt;
  const auto use_id = ++next_effect_id_;
  effect_uses_.push_back(
      {.id = use_id, .thread = std::this_thread::get_id(), .entered = false});
  return EffectToken(std::move(state), use_id);
}

LiveGenerationState::EffectAdmissionCloseResult
LiveGenerationState::close_effect_admission() noexcept {
  std::scoped_lock lock(effect_mutex_);
  generation_.store(0, std::memory_order_release);
  const auto owner = std::this_thread::get_id();
  if (std::ranges::any_of(effect_uses_, [&](const auto &candidate) {
        return candidate.thread == owner;
      }))
    return EffectAdmissionCloseResult::reentrant;
  return EffectAdmissionCloseResult::ready_to_drain;
}

void LiveGenerationState::drain_closed_effects() noexcept {
  std::unique_lock lock(effect_mutex_);
  effect_drained_.wait(lock, [&] { return effect_uses_.empty(); });
}

LiveGenerationRevokeResult LiveGenerationState::revoke_and_drain() noexcept {
  const auto result = close_effect_admission();
  if (result == EffectAdmissionCloseResult::reentrant)
    return LiveGenerationRevokeResult::reentrant;
  drain_closed_effects();
  return LiveGenerationRevokeResult::drained;
}

bool LiveGenerationState::effect_current(std::uint64_t use_id) noexcept {
  std::scoped_lock lock(effect_mutex_);
  const auto use = std::ranges::find_if(effect_uses_, [&](const auto &item) {
    return item.id == use_id;
  });
  if (use == effect_uses_.end() ||
      generation_.load(std::memory_order_acquire) == 0)
    return false;
  const auto executing_thread = std::this_thread::get_id();
  if (use->entered)
    return use->thread == executing_thread;
  use->thread = executing_thread;
  use->entered = true;
  return true;
}

void LiveGenerationState::release_effect(std::uint64_t use_id) noexcept {
  std::scoped_lock lock(effect_mutex_);
  const auto use = std::ranges::find_if(effect_uses_, [&](const auto &item) {
    return item.id == use_id;
  });
  if (use == effect_uses_.end())
    std::terminate();
  effect_uses_.erase(use);
  if (effect_uses_.empty())
    effect_drained_.notify_all();
}

ActivationSource::ActivationSource(int activation_root_fd, int revision_root_fd,
                                   int state_root_fd,
                                   const RevisionVerifier &revision_verifier,
                                   const GrantAuthority &grant_authority,
                                   FilesystemIdentity grant_authority_root,
                                   std::string expected_state_directory,
                                   std::uint32_t trusted_uid)
    : activation_root_(::fcntl(activation_root_fd, F_DUPFD_CLOEXEC, 0)),
      revision_root_(::fcntl(revision_root_fd, F_DUPFD_CLOEXEC, 0)),
      state_root_(::fcntl(state_root_fd, F_DUPFD_CLOEXEC, 0)),
      revision_verifier_(revision_verifier), grant_authority_(grant_authority),
      grant_authority_root_(grant_authority_root),
      expected_state_directory_(std::move(expected_state_directory)),
      trusted_uid_(trusted_uid) {}

std::optional<ActivationSource::VerifiedSelection>
ActivationSource::select(std::string_view record_name,
                         ActivationError &error) const {
  const auto reject = [&](ActivationError value) {
    error = value;
    return std::optional<VerifiedSelection>{};
  };
  error = ActivationError::none;
  if (!component(record_name))
    return reject(ActivationError::invalid_name);
  if (!activation_root_ || !revision_root_ || !state_root_)
    return reject(ActivationError::root_unavailable);
  auto opened_record = read_record(activation_root_.get(), record_name,
                                   trusted_uid_, error);
  if (!opened_record)
    return {};
  const auto record = parse_record(opened_record->bytes);
  if (!record || record->state_directory != expected_state_directory_)
    return reject(ActivationError::record_invalid);

  struct stat activation_root{}, revision_root{}, state_root{};
  if (::fstat(activation_root_.get(), &activation_root) < 0 ||
      ::fstat(revision_root_.get(), &revision_root) < 0 ||
      ::fstat(state_root_.get(), &state_root) < 0)
    return reject(ActivationError::root_unavailable);
  if (!trusted_metadata(activation_root, trusted_uid_, S_IFDIR) ||
      !trusted_metadata(revision_root, trusted_uid_, S_IFDIR) ||
      !trusted_metadata(state_root, trusted_uid_, S_IFDIR))
    return reject(ActivationError::root_untrusted);
  const std::array root_identities{identity_of(activation_root),
                                   identity_of(revision_root),
                                   identity_of(state_root),
                                   grant_authority_root_};
  if (!distinct_authority_objects(root_identities))
    return reject(ActivationError::root_alias);

  auto revision =
      open_directory(revision_root_.get(), record->revision_directory);
  if (!revision)
    return reject(ActivationError::revision_unavailable);
  auto state = open_directory(state_root_.get(), record->state_directory);
  if (!state)
    return reject(ActivationError::state_unavailable);
  struct stat revision_metadata{}, state_metadata{};
  if (::fstat(revision->get(), &revision_metadata) < 0 ||
      ::fstat(state->get(), &state_metadata) < 0)
    return reject(ActivationError::revision_state_alias);
  if (!trusted_metadata(revision_metadata, trusted_uid_, S_IFDIR))
    return reject(ActivationError::revision_unavailable);
  if (!trusted_metadata(state_metadata, trusted_uid_, S_IFDIR) ||
      (state_metadata.st_mode & 07777) != 0700)
    return reject(ActivationError::state_unavailable);
  const std::array authority_identities{
      root_identities[0], root_identities[1], root_identities[2],
      root_identities[3], identity_of(revision_metadata),
      identity_of(state_metadata)};
  if (!distinct_authority_objects(authority_identities))
    return reject(ActivationError::revision_state_alias);

  auto verified =
      revision_verifier_.verify_open_revision(revision->get());
  if (!verified || verified->manifest.id != record->plugin_id ||
      verified->tree_sha256 != record->revision_sha256)
    return reject(ActivationError::revision_unverified);
  return VerifiedSelection{
      .record = *record,
      .verified = std::move(*verified),
      .activation_record = std::move(opened_record->descriptor),
      .revision_directory = std::move(*revision),
      .state_directory = std::move(*state)};
}

std::optional<VerifiedRevision>
ActivationSource::verified_revision(std::string_view record_name) const {
  ActivationError error = ActivationError::none;
  auto selected = select(record_name, error);
  return selected ? std::optional(std::move(selected->verified)) : std::nullopt;
}

ActivationResult ActivationSource::load(std::string_view record_name) const {
  ActivationError error = ActivationError::none;
  auto selected = select(record_name, error);
  if (!selected)
    return failure(error);
  auto grants = grant_authority_.resolve(selected->record.plugin_id,
                                         selected->record.revision_sha256);
  if (!grants.snapshot || grants.status == GrantStatus::unavailable)
    return failure(ActivationError::grant_unavailable);
  if (!authoritative_snapshot(*grants.snapshot, selected->record,
                              selected->verified))
    return failure(ActivationError::grant_mismatch);
  auto live =
      std::make_shared<LiveGenerationState>(grants.snapshot->binding);
  return {.snapshot = ActivationSnapshot{
              .record = std::move(selected->record),
              .manifest = std::move(selected->verified.manifest),
              .grants = std::move(*grants.snapshot),
              .activation_record = std::move(selected->activation_record),
              .revision_directory = std::move(selected->revision_directory),
              .state_directory = std::move(selected->state_directory),
              .live = std::move(live)},
          .error = ActivationError::none,
          .grant_status = grants.status};
}

} // namespace omarchy::plugin_runtime::host_session
