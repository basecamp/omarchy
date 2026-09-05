#pragma once

#include "consent_review.hpp"
#include "revision_verifier_adapter.hpp"

#include <memory>
#include <mutex>
#include <optional>
#include <span>
#include <string>

namespace omarchy::plugin_runtime::channel {

class PluginRuntimeRoot;
class RuntimeBootstrap;
#ifdef OMARCHY_PLUGIN_PERMISSION_AUTHORITY_TESTING
class PluginPermissionAuthorityTestAccess;
#endif
struct RuntimeServices;

} // namespace omarchy::plugin_runtime::channel

namespace omarchy::plugin_runtime::bridge {
#ifdef OMARCHY_PLUGIN_MANAGER_TESTING
class PluginManager;
#endif
class PermissionControl;
namespace detail {
class PluginRuntimeController;
}
}

namespace omarchy::plugin_runtime::channel {

namespace definitions = omarchy::plugins::definitions;
namespace permissions = omarchy::plugins::permissions;

struct ReviewedPermissionApplyResult {
  host_session::ConsentResult publication =
      host_session::ConsentResult::invalid_review;
  host_session::AuthorityMutationResult promotion =
      host_session::AuthorityMutationResult::invalid;
  std::optional<permissions::ActivationBinding> binding;
};

// Trusted-host-only permission composition. Plugin IPC has no reference to
// this object: callers choose only typed decisions/selectors, while the fixed
// activation record, descriptor verifier and AuthorityStore supply identity.
class PluginPermissionAuthority final {
public:
  ~PluginPermissionAuthority() = default;

private:
  [[nodiscard]] static std::shared_ptr<PluginPermissionAuthority> open(
      int activation_root_fd, int revision_root_fd, int state_root_fd,
      host_session::OwnedDescriptor authority_root,
      permissions::PluginId expected_plugin, std::uint32_t trusted_uid,
      std::shared_ptr<const definitions::TrustedDefinitionRegistry> definitions,
      std::shared_ptr<const RuntimeServices> services,
      std::string fixed_record_name);
  PluginPermissionAuthority(
      host_session::OwnedDescriptor activation_root,
      host_session::OwnedDescriptor revision_root,
      host_session::OwnedDescriptor state_root,
      std::unique_ptr<host_session::AuthorityStore> authority,
      host_session::FilesystemIdentity authority_identity,
      permissions::PluginId expected_plugin, std::uint32_t trusted_uid,
      std::shared_ptr<const definitions::TrustedDefinitionRegistry> definitions,
      std::shared_ptr<const RuntimeServices> services,
      std::string fixed_record_name);

  [[nodiscard]] std::optional<host_session::AuthorityView> list() const;
  [[nodiscard]] std::shared_ptr<const host_session::ConsentReview>
  prepare_review();
  [[nodiscard]] ReviewedPermissionApplyResult apply_review(
      const host_session::ConsentReview &review,
      const host_session::ConsentConfirmation &confirmation,
      std::span<const host_session::BuiltinConsentDecision> builtin_decisions,
      std::span<const host_session::DynamicConsentDecision> dynamic_decisions,
      host_session::AuthorityFenceObserver *observer = nullptr);
  [[nodiscard]] host_session::AuthorityRevocationResult
  revoke(const permissions::CapabilityKey &capability,
         std::uint64_t expected_sequence,
         host_session::AuthorityFenceObserver *observer = nullptr);
  [[nodiscard]] host_session::AuthorityRevocationResult
  revoke(const definitions::CapabilityReference &definition,
         std::uint64_t expected_sequence,
         host_session::AuthorityFenceObserver *observer = nullptr);
  [[nodiscard]] bool
  provider_available(const permissions::CapabilityKey &capability) const
      noexcept;
  [[nodiscard]] bool provider_available(
      const definitions::CapabilityReference &definition) const noexcept;

  template <typename Selector>
  [[nodiscard]] host_session::AuthorityRevocationResult
  revoke_exact(const Selector &selector, std::uint64_t expected_sequence,
               host_session::AuthorityFenceObserver *observer);

  [[nodiscard]] host_session::ActivationResult load_activation() const;
  [[nodiscard]] std::optional<host_session::PreparedLiveBinding>
  prepare_live_activation(
      const permissions::ActivationBinding &binding,
      const std::shared_ptr<host_session::LiveGenerationState> &live);
  [[nodiscard]] bool commit_live_activation(
      host_session::PreparedLiveBinding prepared,
      const permissions::ActivationBinding &expected_binding,
      const std::shared_ptr<host_session::LiveGenerationState> &expected_live);
#ifdef OMARCHY_PLUGIN_SESSION_TESTING
  [[nodiscard]] host_session::AuthorityStore &authority_for_test() noexcept {
    return *authority_;
  }
#endif

  host_session::OwnedDescriptor activation_root_;
  host_session::OwnedDescriptor revision_root_;
  host_session::OwnedDescriptor state_root_;
  std::unique_ptr<host_session::AuthorityStore> authority_;
  host_session::DescriptorRevisionVerifier revision_verifier_;
  host_session::ActivationSource activation_source_;
  const permissions::PluginId expected_plugin_;
  std::shared_ptr<const definitions::TrustedDefinitionRegistry> definitions_;
  std::shared_ptr<const RuntimeServices> services_;
  definitions::DynamicScopeValidator scope_validator_;
  const std::string record_name_;
  mutable std::mutex mutex_;

  friend class PluginRuntimeRoot;
  friend class RuntimeBootstrap;
#ifdef OMARCHY_PLUGIN_PERMISSION_AUTHORITY_TESTING
  friend class PluginPermissionAuthorityTestAccess;
#endif
#ifdef OMARCHY_PLUGIN_SESSION_TESTING
  friend class PluginRuntimeRootTestAccess;
#endif
#ifdef OMARCHY_PLUGIN_MANAGER_TESTING
  friend class omarchy::plugin_runtime::bridge::PluginManager;
#endif
  friend class omarchy::plugin_runtime::bridge::PermissionControl;
  friend class omarchy::plugin_runtime::bridge::detail::PluginRuntimeController;
};

} // namespace omarchy::plugin_runtime::channel
