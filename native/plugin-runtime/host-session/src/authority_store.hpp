#pragma once

#include "activation_snapshot.hpp"
#include "dynamic_activation.hpp"

#include <memory>
#include <mutex>
#include <sys/types.h>

namespace omarchy::plugin_runtime::channel {
class PluginPermissionAuthority;
}

namespace omarchy::plugin_runtime::host_session {

namespace definitions = omarchy::plugins::definitions;

class AuthorityFenceObserver {
public:
  virtual ~AuthorityFenceObserver() = default;
  virtual void live_generation_closed() noexcept = 0;
};

struct AuthorityRevisionRef {
  permissions::Digest snapshot_digest;
  std::uint64_t generation = 0;
  bool operator==(const AuthorityRevisionRef &) const = default;
};

struct AuthoritySlots {
  std::uint64_t sequence = 0;
  std::uint64_t generation_high_watermark = 0;
  std::optional<AuthorityRevisionRef> active;
  std::optional<AuthorityRevisionRef> candidate;
  bool operator==(const AuthoritySlots &) const = default;
};

struct AuthorityView {
  AuthoritySlots authority_slots;
  std::optional<policy::GrantSnapshot> active;
};

enum class AuthorityMutationResult {
  applied,
  invalid,
  stale_sequence,
  reentrant_effect,
  io_error,
  poisoned,
};

#ifdef OMARCHY_AUTHORITY_STORE_TESTING
enum class AuthorityCrashPoint {
  none,
  grant_write,
  grant_file_sync,
  grant_rename,
  grant_directory_sync,
  slots_write,
  slots_file_sync,
  slots_rename,
  slots_directory_sync,
};
#endif

struct AuthorityRevocationResult {
  AuthorityMutationResult status = AuthorityMutationResult::invalid;
  std::optional<permissions::ActivationBinding> binding;
  bool activatable = false;
};

#ifdef OMARCHY_AUTHORITY_STORE_TESTING
class AuthorityStoreTestAccess;
#endif
class AuthorityStore;

class PreparedLiveBinding final {
public:
  PreparedLiveBinding(PreparedLiveBinding &&) noexcept = default;
  PreparedLiveBinding &operator=(PreparedLiveBinding &&) noexcept = default;
  PreparedLiveBinding(const PreparedLiveBinding &) = delete;
  PreparedLiveBinding &operator=(const PreparedLiveBinding &) = delete;

private:
  PreparedLiveBinding(AuthorityStore *owner, FilesystemIdentity root_identity,
                      permissions::ActivationBinding binding,
                      std::shared_ptr<LiveGenerationState> live,
                      std::uint64_t mutation_epoch) noexcept
      : owner_(owner), root_identity_(root_identity),
        binding_(std::move(binding)), live_(std::move(live)),
        mutation_epoch_(mutation_epoch) {}

  AuthorityStore *owner_ = nullptr;
  FilesystemIdentity root_identity_{};
  permissions::ActivationBinding binding_;
  std::shared_ptr<LiveGenerationState> live_;
  std::uint64_t mutation_epoch_ = 0;

  friend class AuthorityStore;
};

// Descriptor-rooted, single-owner authority for exact reviewed grants. Open
// takes a nonblocking lifetime lock; all mutations route through this host
// owner rather than opening the store from a CLI or second process. Owner/mode
// checks, exact digests and sandbox exclusion protect v2 and detect corruption;
// they do not authenticate against arbitrary code already running as the
// expected uid, which could ignore the advisory lock and rewrite owner files.
class AuthorityStore final : public GrantAuthority {
public:
  [[nodiscard]] static std::unique_ptr<AuthorityStore>
  open(int root_directory_fd, std::uint32_t expected_uid,
       permissions::PluginId expected_plugin);

  ~AuthorityStore() override;
  AuthorityStore(const AuthorityStore &) = delete;
  AuthorityStore &operator=(const AuthorityStore &) = delete;

  [[nodiscard]] std::optional<AuthoritySlots> read_slots() const;
  // Coherent review baseline: slots and active snapshot are read under one
  // mutex. A later mutation is rejected by publish_candidate's sequence CAS.
  [[nodiscard]] std::optional<AuthorityView> read_authority_view() const;
  [[nodiscard]] std::optional<FilesystemIdentity> root_identity() const;
  // The prepare/commit fence binds one not-yet-started product session to the
  // exact durable active revision. Promotion revokes this shared state before
  // replacing authority.
  [[nodiscard]] std::optional<PreparedLiveBinding>
  prepare_live_activation(const permissions::ActivationBinding &binding,
                          const std::shared_ptr<LiveGenerationState> &live);
  [[nodiscard]] bool commit_live_activation(
      PreparedLiveBinding prepared,
      const permissions::ActivationBinding &expected_binding,
      const std::shared_ptr<LiveGenerationState> &expected_live);
  [[nodiscard]] AuthorityMutationResult
  publish_candidate(const VerifiedRevision &verified,
                    const policy::GrantSnapshot &snapshot,
                    std::uint64_t expected_sequence,
                    const definitions::TrustedDefinitionRegistry &definitions,
                    definitions::DynamicScopeValidator scope_validator);
  [[nodiscard]] AuthorityMutationResult
  promote_candidate(const permissions::ActivationBinding &candidate,
                    std::uint64_t expected_sequence);
  [[nodiscard]] AuthorityMutationResult
  discard_candidate(const permissions::ActivationBinding &candidate,
                    std::uint64_t expected_sequence);

  [[nodiscard]] GrantResolution
  resolve(std::string_view plugin_id,
          std::string_view revision_sha256) const override;

private:
  AuthorityStore(OwnedDescriptor root, OwnedDescriptor lock,
                 std::uint32_t expected_uid,
                 permissions::PluginId expected_plugin);
  [[nodiscard]] AuthorityMutationResult replace_slots(AuthoritySlots slots);
  [[nodiscard]] AuthorityRevocationResult
  revoke_active(const permissions::CapabilityKey &capability,
                std::uint64_t expected_sequence,
                AuthorityFenceObserver *observer = nullptr);
  [[nodiscard]] AuthorityRevocationResult
  revoke_active(const definitions::CapabilityReference &definition,
                std::uint64_t expected_sequence,
                AuthorityFenceObserver *observer = nullptr);
  [[nodiscard]] AuthorityRevocationResult
  revoke_active(const permissions::CapabilityKey *capability,
      const definitions::CapabilityReference *definition,
      std::uint64_t expected_sequence, AuthorityFenceObserver *observer);
  [[nodiscard]] AuthorityMutationResult promote_candidate(
      const permissions::ActivationBinding &candidate,
      std::uint64_t expected_sequence, AuthorityFenceObserver *observer);
  [[nodiscard]] AuthorityMutationResult
  fence_bound_live(std::unique_lock<std::mutex> &lock,
                   const AuthoritySlots &preimage,
                   AuthorityFenceObserver *observer = nullptr);
#ifdef OMARCHY_AUTHORITY_STORE_TESTING
  [[nodiscard]] AuthorityMutationResult
  replace_active_for_testing(const policy::GrantSnapshot &snapshot);
  static void set_crash_point_for_testing(AuthorityCrashPoint point) noexcept;
#endif

  OwnedDescriptor root_;
  OwnedDescriptor lock_;
  std::uint32_t expected_uid_;
  permissions::PluginId expected_plugin_;
  pid_t owner_pid_;
  mutable std::mutex mutation_mutex_;
  std::weak_ptr<LiveGenerationState> bound_live_;
  bool poisoned_ = false;
  bool transitioning_ = false;
  std::uint64_t mutation_epoch_ = 0;
  std::optional<FilesystemIdentity> prepared_root_identity_;

  friend class omarchy::plugin_runtime::channel::PluginPermissionAuthority;
#ifdef OMARCHY_AUTHORITY_STORE_TESTING
  friend class AuthorityStoreTestAccess;
#endif
};

} // namespace omarchy::plugin_runtime::host_session
