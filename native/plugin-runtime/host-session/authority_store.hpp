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

enum class AuthorityMutationResult {
  applied,
  invalid,
  stale_sequence,
  io_error,
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
  resolve(std::string_view plugin_id, std::string_view revision_sha256,
          std::uint64_t generation) const override;

private:
  AuthorityStore(OwnedDescriptor root, OwnedDescriptor lock,
                 std::uint32_t expected_uid,
                 permissions::PluginId expected_plugin);
  [[nodiscard]] AuthorityMutationResult replace_slots(AuthoritySlots slots);

  OwnedDescriptor root_;
  OwnedDescriptor lock_;
  std::uint32_t expected_uid_;
  permissions::PluginId expected_plugin_;
  pid_t owner_pid_;
  mutable std::mutex mutation_mutex_;
};

} // namespace omarchy::plugin_runtime::host_session
