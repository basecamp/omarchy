#pragma once

#include "../host-session/consent_review.hpp"
#include "plugin_activation_coordinator.hpp"

#include <memory>
#include <mutex>
#include <optional>
#include <span>
#include <string>

namespace omarchy::plugin_runtime::channel {

namespace definitions = omarchy::plugins::definitions;

struct ReviewedPermissionApplyResult {
  host_session::ConsentResult publication =
      host_session::ConsentResult::invalid_review;
  host_session::AuthorityMutationResult promotion =
      host_session::AuthorityMutationResult::invalid;
  std::optional<PluginActivationResult> activation;
};

struct PermissionRevokeApplyResult {
  host_session::AuthorityRevocationResult revocation;
  std::optional<PluginActivationResult> activation;
};

// Trusted-host-only permission composition. Plugin IPC has no reference to
// this object: callers choose only typed decisions/selectors, while the fixed
// activation record, descriptor verifier and AuthorityStore supply identity.
class PluginPermissionController final {
public:
  PluginPermissionController(
      PluginActivationCoordinator &coordinator,
      const definitions::TrustedDefinitionRegistry &definitions,
      definitions::DynamicScopeValidator scope_validator,
      std::string fixed_record_name);

  [[nodiscard]] std::optional<host_session::AuthorityView> list() const;
  [[nodiscard]] std::shared_ptr<const host_session::ConsentReview>
  prepare_review();
  [[nodiscard]] ReviewedPermissionApplyResult apply_review(
      const host_session::ConsentConfirmation &confirmation,
      std::span<const host_session::BuiltinConsentDecision> builtin_decisions,
      std::span<const host_session::DynamicConsentDecision> dynamic_decisions);
  [[nodiscard]] PermissionRevokeApplyResult
  revoke(const permissions::CapabilityKey &capability,
         std::uint64_t expected_sequence);
  [[nodiscard]] PermissionRevokeApplyResult
  revoke(const definitions::CapabilityReference &definition,
         std::uint64_t expected_sequence);

private:
  template <typename Selector>
  [[nodiscard]] PermissionRevokeApplyResult
  revoke_exact(const Selector &selector, std::uint64_t expected_sequence);

  host_session::AuthorityStore &authority_;
  PluginActivationCoordinator &coordinator_;
  const definitions::TrustedDefinitionRegistry &definitions_;
  definitions::DynamicScopeValidator scope_validator_;
  const std::string record_name_;
  mutable std::mutex mutex_;
  std::shared_ptr<const host_session::ConsentReview> pending_review_;
};

} // namespace omarchy::plugin_runtime::channel
