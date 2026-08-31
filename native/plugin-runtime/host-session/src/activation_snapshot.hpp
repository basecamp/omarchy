#pragma once

#include "grant_snapshot.hpp"
#include "manifest_contract.hpp"

#include <atomic>
#include <condition_variable>
#include <cstdint>
#include <memory>
#include <mutex>
#include <optional>
#include <span>
#include <string>
#include <string_view>
#include <thread>
#include <vector>

namespace omarchy::plugin_runtime::host_session {

namespace permissions = omarchy::plugins::permissions;
namespace policy = omarchy::plugin_runtime::policy;

// A descriptor is the lifetime of an activated filesystem object.  Activation
// never converts it back to a pathname: the verifier, sandbox launcher and
// state broker must use descriptor-relative operations on these exact objects.
class OwnedDescriptor {
public:
  OwnedDescriptor() = default;
  explicit OwnedDescriptor(int descriptor) noexcept : descriptor_(descriptor) {}
  ~OwnedDescriptor();
  OwnedDescriptor(OwnedDescriptor &&other) noexcept;
  OwnedDescriptor &operator=(OwnedDescriptor &&other) noexcept;
  OwnedDescriptor(const OwnedDescriptor &) = delete;
  OwnedDescriptor &operator=(const OwnedDescriptor &) = delete;

  [[nodiscard]] int get() const noexcept { return descriptor_; }
  [[nodiscard]] int release() noexcept;
  [[nodiscard]] explicit operator bool() const noexcept {
    return descriptor_ >= 0;
  }

private:
  int descriptor_ = -1;
};

struct ActivationRecord {
  std::string plugin_id;
  std::string revision_directory;
  std::string revision_sha256;
  std::string state_directory;
};

// Canonical inverse of the strict activation-record parser. Invalid record
// fields are rejected rather than escaped or normalized.
[[nodiscard]] std::optional<std::string>
encode_activation_record(const ActivationRecord &record);

// One exact, metadata-stable activation record selected relative to a trusted
// root. Catalog/bootstrap code retains this object rather than recovering or
// reopening a pathname after inspection.
class InspectedActivationRecord final {
public:
  InspectedActivationRecord(InspectedActivationRecord &&) noexcept = default;
  InspectedActivationRecord &
  operator=(InspectedActivationRecord &&) noexcept = default;
  InspectedActivationRecord(const InspectedActivationRecord &) = delete;
  InspectedActivationRecord &
  operator=(const InspectedActivationRecord &) = delete;

  [[nodiscard]] const ActivationRecord &record() const noexcept {
    return record_;
  }
  [[nodiscard]] int descriptor() const noexcept { return descriptor_.get(); }
  [[nodiscard]] bool unchanged() const noexcept;

private:
  struct StableMetadata {
    std::uint64_t device = 0;
    std::uint64_t inode = 0;
    std::uint64_t size = 0;
    std::int64_t modified_seconds = 0;
    std::int64_t modified_nanoseconds = 0;
    std::int64_t changed_seconds = 0;
    std::int64_t changed_nanoseconds = 0;
    std::uint32_t mode = 0;
    std::uint32_t uid = 0;
    std::uint32_t gid = 0;
    std::uint64_t links = 0;
  };

  InspectedActivationRecord(ActivationRecord record, OwnedDescriptor descriptor,
                            StableMetadata metadata) noexcept;

  ActivationRecord record_;
  OwnedDescriptor descriptor_;
  StableMetadata metadata_;

  friend std::optional<InspectedActivationRecord>
  inspect_activation_record(int, std::string_view, std::uint32_t);
};

// The borrowed root remains owned by the caller. The returned record FD is
// close-on-exec and owned by the inspection for its complete lifetime.
[[nodiscard]] std::optional<InspectedActivationRecord>
inspect_activation_record(int activation_root_fd, std::string_view record_name,
                          std::uint32_t trusted_uid);

struct VerifiedRevision {
  plugins::manifest::ManifestV2 manifest;
  std::string tree_sha256;
  std::string request_sha256;
};

struct FilesystemIdentity {
  std::uint64_t device = 0;
  std::uint64_t inode = 0;

  bool operator==(const FilesystemIdentity &) const = default;
};

// Every authority root and selected plugin directory must name a distinct
// filesystem object. This prevents writable state from aliasing trusted roots.
[[nodiscard]] bool distinct_authority_objects(
    std::span<const FilesystemIdentity> identities) noexcept;

// Discovery currently verifies by path. Activation instead hands this seam the
// exact already-open revision directory. Implementations must derive both
// returned values using descriptor-relative reads and must not reopen a path.
class RevisionVerifier {
public:
  virtual ~RevisionVerifier() = default;
  [[nodiscard]] virtual std::optional<VerifiedRevision>
  verify_open_revision(int revision_directory_fd) const = 0;
};

enum class GrantStatus : std::uint8_t {
  unavailable,
  activatable,
  permission_disabled,
};

struct GrantResolution final {
  std::optional<policy::GrantSnapshot> snapshot;
  GrantStatus status = GrantStatus::unavailable;
};

// The activation record never supplies grants or their fingerprint. The trusted
// authority resolves the persisted decision for the verified identity instead.
class GrantAuthority {
public:
  virtual ~GrantAuthority() = default;
  [[nodiscard]] virtual GrantResolution
  resolve(std::string_view plugin_id,
          std::string_view revision_sha256) const = 0;
};

enum class LiveGenerationRevokeResult : std::uint8_t { drained, reentrant };

class LiveGenerationState final
    : public std::enable_shared_from_this<LiveGenerationState> {
public:
  class EffectToken final {
  public:
    EffectToken(EffectToken &&other) noexcept;
    EffectToken &operator=(EffectToken &&) = delete;
    EffectToken(const EffectToken &) = delete;
    EffectToken &operator=(const EffectToken &) = delete;
    ~EffectToken();

    [[nodiscard]] bool current() const noexcept;

  private:
    EffectToken(std::shared_ptr<LiveGenerationState> state,
                std::uint64_t use_id) noexcept;
    std::shared_ptr<LiveGenerationState> state_;
    std::uint64_t use_id_ = 0;
    friend class LiveGenerationState;
  };

  explicit LiveGenerationState(permissions::ActivationBinding binding);

  [[nodiscard]] bool
  current(const permissions::ActivationBinding &binding) const noexcept;
  [[nodiscard]] std::uint64_t generation() const noexcept;
  [[nodiscard]] std::optional<EffectToken>
  acquire_effect(const permissions::ActivationBinding &binding);
  [[nodiscard]] LiveGenerationRevokeResult revoke_and_drain() noexcept;

private:
  enum class EffectAdmissionCloseResult : std::uint8_t {
    ready_to_drain,
    reentrant,
  };
  [[nodiscard]] EffectAdmissionCloseResult
  close_effect_admission() noexcept;
  void drain_closed_effects() noexcept;
  [[nodiscard]] bool effect_current(std::uint64_t use_id) noexcept;
  void release_effect(std::uint64_t use_id) noexcept;
  struct EffectUse {
    std::uint64_t id = 0;
    std::thread::id thread;
    bool entered = false;
  };
  permissions::PluginId plugin_;
  permissions::Digest revision_;
  permissions::Digest policy_fingerprint_;
  std::atomic<std::uint64_t> generation_;
  std::mutex effect_mutex_;
  std::condition_variable effect_drained_;
  std::vector<EffectUse> effect_uses_;
  std::uint64_t next_effect_id_ = 0;

  friend class AuthorityStore;
};

struct ActivationSnapshot {
  ActivationRecord record;
  plugins::manifest::ManifestV2 manifest;
  policy::GrantSnapshot grants;
  // Keep the trusted record and both selected directories pinned for the full
  // activation. A rename or path replacement cannot retarget a live session.
  OwnedDescriptor activation_record;
  OwnedDescriptor revision_directory;
  OwnedDescriptor state_directory;
  std::shared_ptr<LiveGenerationState> live;
};

enum class ActivationError {
  none,
  invalid_name,
  record_unavailable,
  record_untrusted,
  record_invalid,
  root_unavailable,
  root_untrusted,
  root_alias,
  revision_unavailable,
  state_unavailable,
  revision_state_alias,
  revision_unverified,
  grant_unavailable,
  grant_mismatch,
};

struct ActivationResult {
  std::optional<ActivationSnapshot> snapshot;
  ActivationError error = ActivationError::none;
  GrantStatus grant_status = GrantStatus::unavailable;
};

class ActivationSource {
public:
  ActivationSource(int activation_root_fd, int revision_root_fd,
                   int state_root_fd, const RevisionVerifier &revision_verifier,
                   const GrantAuthority &grant_authority,
                   FilesystemIdentity grant_authority_root,
                   std::string expected_state_directory,
                   std::uint32_t trusted_uid);

  [[nodiscard]] ActivationResult load(std::string_view record_name) const;
  // Trusted-host read-only selection. This verifies through the same
  // descriptor-pinned selection as load(), but returns no authority or FDs.
  [[nodiscard]] std::optional<VerifiedRevision>
  verified_revision(std::string_view record_name) const;

private:
  struct VerifiedSelection {
    ActivationRecord record;
    VerifiedRevision verified;
    OwnedDescriptor activation_record;
    OwnedDescriptor revision_directory;
    OwnedDescriptor state_directory;
  };
  [[nodiscard]] std::optional<VerifiedSelection>
  select(std::string_view record_name, ActivationError &error) const;
  OwnedDescriptor activation_root_;
  OwnedDescriptor revision_root_;
  OwnedDescriptor state_root_;
  const RevisionVerifier &revision_verifier_;
  const GrantAuthority &grant_authority_;
  FilesystemIdentity grant_authority_root_;
  std::string expected_state_directory_;
  std::uint32_t trusted_uid_;
};

} // namespace omarchy::plugin_runtime::host_session
