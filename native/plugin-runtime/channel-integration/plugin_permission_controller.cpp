#include "plugin_permission_controller.hpp"

#include <utility>

namespace omarchy::plugin_runtime::channel {
namespace {

bool same_revision(const host_session::VerifiedRevision &left,
                   const host_session::VerifiedRevision &right) {
  // The verified tree digest authenticates the complete installed revision;
  // request identity is repeated here to make the consent binding explicit.
  return left.manifest.id == right.manifest.id &&
         left.tree_sha256 == right.tree_sha256 &&
         left.request_sha256 == right.request_sha256;
}

} // namespace

PluginPermissionController::PluginPermissionController(
    PluginActivationCoordinator &coordinator,
    const definitions::TrustedDefinitionRegistry &definitions,
    definitions::DynamicScopeValidator scope_validator,
    std::string fixed_record_name)
    : authority_(coordinator.authority_), coordinator_(coordinator),
      definitions_(definitions), scope_validator_(scope_validator),
      record_name_(std::move(fixed_record_name)) {}

std::optional<host_session::AuthorityView>
PluginPermissionController::list() const {
  std::scoped_lock lock(mutex_);
  return authority_.read_authority_view();
}

std::shared_ptr<const host_session::ConsentReview>
PluginPermissionController::prepare_review() {
  std::scoped_lock lock(mutex_);
  pending_review_.reset();
  auto verified = coordinator_.verify_revision(record_name_);
  if (!verified)
    return {};
  auto review = host_session::prepare_consent_review(
      authority_, *verified, definitions_, scope_validator_);
  if (!review)
    return {};
  pending_review_ =
      std::make_shared<const host_session::ConsentReview>(std::move(*review));
  return pending_review_;
}

ReviewedPermissionApplyResult PluginPermissionController::apply_review(
    const host_session::ConsentConfirmation &confirmation,
    std::span<const host_session::BuiltinConsentDecision> builtin_decisions,
    std::span<const host_session::DynamicConsentDecision> dynamic_decisions) {
  std::scoped_lock lock(mutex_);
  const auto review = std::move(pending_review_);
  if (!review)
    return {};
  const auto verified = coordinator_.verify_revision(record_name_);
  if (!verified || !same_revision(*verified, review->verified))
    return {};

  ReviewedPermissionApplyResult result;
  result.publication = host_session::publish_consent_review(
      authority_, *review, confirmation, builtin_decisions, dynamic_decisions,
      definitions_, scope_validator_);
  if (result.publication != host_session::ConsentResult::applied)
    return result;

  coordinator_.stop();
  result.promotion = authority_.promote_candidate(
      review->candidate_binding, review->expected_sequence + 1);
  if (result.promotion != host_session::AuthorityMutationResult::applied)
    return result;
  result.activation = coordinator_.activate(record_name_);
  return result;
}

PermissionRevokeApplyResult PluginPermissionController::revoke(
    const permissions::CapabilityKey &capability,
    std::uint64_t expected_sequence) {
  return revoke_exact(capability, expected_sequence);
}

PermissionRevokeApplyResult PluginPermissionController::revoke(
    const definitions::CapabilityReference &definition,
    std::uint64_t expected_sequence) {
  return revoke_exact(definition, expected_sequence);
}

template <typename Selector>
PermissionRevokeApplyResult PluginPermissionController::revoke_exact(
    const Selector &selector, std::uint64_t expected_sequence) {
  std::scoped_lock lock(mutex_);
  PermissionRevokeApplyResult result;
  try {
    result.revocation =
        authority_.revoke_active(selector, expected_sequence);
  } catch (...) {
    // AuthorityStore is specified to return a typed failure, but keep the
    // product boundary fail-closed if a future persistence path violates it.
    pending_review_.reset();
    coordinator_.stop();
    result.revocation.status = host_session::AuthorityMutationResult::io_error;
    return result;
  }
  if (result.revocation.status ==
          host_session::AuthorityMutationResult::invalid ||
      result.revocation.status ==
          host_session::AuthorityMutationResult::stale_sequence)
    return result;
  pending_review_.reset();
  if (result.revocation.status ==
      host_session::AuthorityMutationResult::reentrant_effect)
    return result;
  coordinator_.stop();
  if (result.revocation.status ==
          host_session::AuthorityMutationResult::applied &&
      result.revocation.activatable)
    result.activation = coordinator_.activate(record_name_);
  return result;
}

template PermissionRevokeApplyResult
PluginPermissionController::revoke_exact(
    const permissions::CapabilityKey &, std::uint64_t);
template PermissionRevokeApplyResult
PluginPermissionController::revoke_exact(
    const definitions::CapabilityReference &, std::uint64_t);

} // namespace omarchy::plugin_runtime::channel
