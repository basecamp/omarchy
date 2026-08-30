#pragma once

#include "activation_snapshot.hpp"
#include "dynamic_activation.hpp"

#include <memory>
#include <mutex>
#include <sys/types.h>

namespace omarchy::plugin_runtime::host_session {

namespace definitions = omarchy::plugins::definitions;

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
};

struct AuthorityView {
  AuthoritySlots authority_slots;
  std::optional<policy::GrantSnapshot> active;
};

enum class AuthorityMutationResult {
  applied,
  invalid,
  stale_sequence,
  io_error,
  poisoned,
};

struct AuthorityRevocationResult {
  AuthorityMutationResult status = AuthorityMutationResult::invalid;
  std::optional<permissions::ActivationBinding> binding;
  bool activatable = false;
};

class PermissionController;
class AuthorityStoreTestAccess;

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
  // Binds one not-yet-started product session to the exact durable active
  // revision. Promotion revokes this shared state before replacing authority.
  [[nodiscard]] bool bind_live_activation(
      const permissions::ActivationBinding &binding,
      const std::shared_ptr<LiveGenerationState> &live);
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

  [[nodiscard]] std::optional<policy::GrantSnapshot>
  resolve(std::string_view plugin_id,
          std::string_view revision_sha256) const override;

private:
  AuthorityStore(OwnedDescriptor root, OwnedDescriptor lock,
                 std::uint32_t expected_uid,
                 permissions::PluginId expected_plugin);
  [[nodiscard]] AuthorityMutationResult replace_slots(AuthoritySlots slots);
  [[nodiscard]] AuthorityRevocationResult
  revoke_active(const permissions::CapabilityKey &capability,
                std::uint64_t expected_sequence);
  [[nodiscard]] AuthorityRevocationResult
  revoke_active(const definitions::CapabilityReference &definition,
                std::uint64_t expected_sequence);
  [[nodiscard]] AuthorityRevocationResult revoke_active(
      const permissions::CapabilityKey *capability,
      const definitions::CapabilityReference *definition,
      std::uint64_t expected_sequence);

  OwnedDescriptor root_;
  OwnedDescriptor lock_;
  std::uint32_t expected_uid_;
  permissions::PluginId expected_plugin_;
  pid_t owner_pid_;
  mutable std::mutex mutation_mutex_;
  std::weak_ptr<LiveGenerationState> bound_live_;
  bool poisoned_ = false;

  friend class PermissionController;
  friend class AuthorityStoreTestAccess;
};

#ifdef OMARCHY_AUTHORITY_STORE_TESTING
class AuthorityStoreTestAccess final {
public:
  [[nodiscard]] static AuthorityRevocationResult
  revoke_active(AuthorityStore &store,
                const permissions::CapabilityKey &capability,
                std::uint64_t expected_sequence) {
    return store.revoke_active(capability, expected_sequence);
  }
  [[nodiscard]] static AuthorityRevocationResult
  revoke_active(AuthorityStore &store,
                const definitions::CapabilityReference &definition,
                std::uint64_t expected_sequence) {
    return store.revoke_active(definition, expected_sequence);
  }
};
#endif

} // namespace omarchy::plugin_runtime::host_session
