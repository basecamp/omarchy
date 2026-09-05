#include "dynamic_broker_runtime.hpp"

#include "manifest_contract.hpp"

#include <algorithm>
#include <stdexcept>
#include <utility>

namespace omarchy::plugin_runtime::runtime {

DynamicBrokerRuntime::DynamicBrokerRuntime(
    const definitions::TrustedDefinitionRegistry &registry,
    std::vector<DynamicRoute> reconstructed_routes,
    omarchy::plugins::audit::AuditSink &audit_sink)
    : registry_(registry), routes_(std::move(reconstructed_routes)),
      audit_(audit_sink) {
  for (std::size_t index = 0; index < routes_.size(); ++index) {
    const auto &route = routes_[index];
    if (!definitions::review_dynamic_grant(registry_, route.grant,
                                           route.scope_validator) ||
        route.adapter.dispatch == nullptr)
      throw std::runtime_error(
          "dynamic route was not reconstructed from an exact grant");
    if (!binding_)
      binding_ = route.grant.binding;
    else if (*binding_ != route.grant.binding)
      throw std::runtime_error("dynamic routes mix activation bindings");
    for (std::size_t previous = 0; previous < index; ++previous) {
      const auto &existing = routes_[previous].grant.request.definition;
      const auto &candidate = route.grant.request.definition;
      if (existing == candidate)
        throw std::runtime_error("duplicate exact dynamic route");
    }
  }
}

bool DynamicBrokerRuntime::accepts_binding(
    const omarchy::plugins::permissions::ActivationBinding &binding)
    const noexcept {
  return binding_.has_value() && *binding_ == binding;
}

DynamicBrokerResult DynamicBrokerRuntime::dispatch(
    const wire::PacketView &packet,
    const omarchy::plugins::permissions::ActivationBinding &channel_binding,
    std::span<std::byte> response, DynamicGestureAuthority *gesture_authority) {
  if (failed_ || packet.header.message_type != broker::kDynamicInvokeMessage ||
      packet.header.correlation_id == 0 ||
      packet.header.correlation_id <= last_correlation_)
    return {.outcome = definitions::DynamicDispatchResult::malformed};
  definitions::DynamicInvocation invocation;
  if (!definitions::decode_dynamic_invocation(packet.payload, invocation))
    return {.outcome = definitions::DynamicDispatchResult::malformed};
  if (!binding_)
    return {.outcome = definitions::DynamicDispatchResult::denied,
            .decision = definitions::DynamicDecision::unknown_definition};
  using omarchy::plugins::permissions::AuditEvent;
  using omarchy::plugins::permissions::AuditMetric;
  using omarchy::plugins::permissions::AuditOutcome;
  using omarchy::plugins::permissions::AuditProducer;
  using omarchy::plugins::permissions::DynamicAuditAttemptIdentity;
  using omarchy::plugins::permissions::DynamicAuditIdentity;
  using omarchy::plugins::permissions::GrantDecisionCode;
  const auto attempt_identity = DynamicAuditAttemptIdentity{
      .opaque_digest = omarchy::plugins::permissions::Digest(
          omarchy::plugins::manifest::sha256_hex(packet.payload))};
  const auto decision_code = [](definitions::DynamicDecision decision) {
    switch (decision) {
    case definitions::DynamicDecision::allowed:
      return GrantDecisionCode::allowed;
    case definitions::DynamicDecision::revoked:
      return GrantDecisionCode::revoked;
    case definitions::DynamicDecision::scope_expanded:
      return GrantDecisionCode::outside_scope;
    case definitions::DynamicDecision::operation_undeclared:
      return GrantDecisionCode::capability_undeclared;
    case definitions::DynamicDecision::operation_ungranted:
      return GrantDecisionCode::ungranted;
    case definitions::DynamicDecision::gesture_missing:
      return GrantDecisionCode::gesture_missing;
    case definitions::DynamicDecision::unknown_definition:
    case definitions::DynamicDecision::stale_definition:
    case definitions::DynamicDecision::denied:
    case definitions::DynamicDecision::adapter_mismatch:
      return GrantDecisionCode::ungranted;
    }
    return GrantDecisionCode::ungranted;
  };
  const auto append = [&](AuditEvent event, AuditOutcome outcome,
                          definitions::DynamicDecision decision,
                          const std::optional<DynamicAuditIdentity> &identity,
                          std::size_t response_bytes) {
    omarchy::plugins::permissions::AuditDraft draft{
        .event = event,
        .outcome = outcome,
        .plugin = binding_->plugin,
        .revision = binding_->revision,
        .generation = binding_->generation,
        .correlation = packet.header.correlation_id,
        .dynamic_operation = identity,
        .dynamic_attempt =
            identity ? std::nullopt : std::optional(attempt_identity),
        .operation = std::nullopt,
        .capability = std::nullopt,
        .decision = decision_code(decision),
        .metadata = {}};
    draft.metadata.push_back(
        {AuditMetric::request_bytes,
         static_cast<std::int64_t>(packet.payload.size())});
    if (response_bytes > 0)
      draft.metadata.push_back({AuditMetric::response_bytes,
                                static_cast<std::int64_t>(response_bytes)});
    return append_audit(std::move(draft));
  };
  const auto route = std::ranges::find_if(routes_, [&](const auto &candidate) {
    return candidate.grant.request.definition == invocation.definition;
  });
  if (route == routes_.end()) {
    constexpr auto unknown = definitions::DynamicDecision::unknown_definition;
    if (!append(AuditEvent::operation_decided, AuditOutcome::denied, unknown,
                std::nullopt, 0)) {
      failed_ = true;
      return {.outcome = definitions::DynamicDispatchResult::adapter_failed,
              .decision = unknown};
    }
    last_correlation_ = packet.header.correlation_id;
    if (!append(AuditEvent::operation_completed, AuditOutcome::denied, unknown,
                std::nullopt, 0)) {
      failed_ = true;
      return {.outcome = definitions::DynamicDispatchResult::adapter_failed,
              .decision = unknown};
    }
    return {.outcome = definitions::DynamicDispatchResult::denied,
            .decision = unknown};
  }
  definitions::DynamicDecision decision = definitions::DynamicDecision::denied;
  definitions::DynamicAuthorization authorization;
  bool authorized = false;
  if (channel_binding != route->grant.binding) {
    decision = definitions::DynamicDecision::denied;
  } else {
    authorization = definitions::authorize_dynamic_operation(
        registry_, route->grant.request, route->grant.grant,
        invocation.operation.view(), invocation.demand_scope.view(),
        route->adapter.binding, route->scope_validator, false);
    if (authorization.decision ==
            definitions::DynamicDecision::gesture_missing &&
        invocation.gesture && gesture_authority != nullptr &&
        gesture_authority->consume(channel_binding, *invocation.gesture)
            .has_value())
      authorization = definitions::authorize_dynamic_operation(
          registry_, route->grant.request, route->grant.grant,
          invocation.operation.view(), invocation.demand_scope.view(),
          route->adapter.binding, route->scope_validator, true);
    decision = authorization.decision;
    authorized = authorization.allowed();
  }
  const auto resolved = registry_.resolve(route->grant.request.definition);
  const auto trusted_operation =
      resolved ? std::ranges::find_if(resolved->definition->operations.values(),
                                      [&](const auto &operation) {
                                        return operation.name.view() ==
                                               invocation.operation.view();
                                      })
               : decltype(resolved->definition->operations.values().begin()){};
  const bool operation_resolved =
      resolved &&
      trusted_operation != resolved->definition->operations.values().end();
  const std::optional<DynamicAuditIdentity> identity =
      operation_resolved
          ? std::optional(DynamicAuditIdentity{
                .capability = omarchy::plugins::permissions::CapabilityId(
                    route->grant.request.definition.canonical_name.view()),
                .definition_generation =
                    route->grant.request.definition.definition_generation,
                .definition_digest =
                    route->grant.request.definition.definition_digest,
                .operation = omarchy::plugins::permissions::BoundedString<128>(
                    trusted_operation->name.view()),
                .grant_epoch = route->grant.grant.epoch})
          : std::nullopt;
  if (!append(AuditEvent::operation_decided,
              authorized ? AuditOutcome::allowed : AuditOutcome::denied,
              decision, identity, 0)) {
    failed_ = true;
    return {.outcome = definitions::DynamicDispatchResult::adapter_failed,
            .decision = decision};
  }
  last_correlation_ = packet.header.correlation_id;
  std::size_t written = 0;
  definitions::DynamicDispatchResult outcome =
      definitions::DynamicDispatchResult::denied;
  if (authorized) {
    const definitions::AuthorizedDynamicRequest request{
        .authorization = {.binding = channel_binding,
                          .definition = route->grant.grant.definition,
                          .grant_epoch = route->grant.grant.epoch},
        .operation = invocation.operation.view(),
        .demand_scope = invocation.demand_scope.view(),
        .payload = invocation.payload};
    outcome = route->adapter.dispatch(request, response, written,
                                      route->adapter.context) &&
                      written <= response.size()
                  ? definitions::DynamicDispatchResult::dispatched
                  : definitions::DynamicDispatchResult::adapter_failed;
  }
  const auto terminal_outcome =
      outcome == definitions::DynamicDispatchResult::dispatched
          ? AuditOutcome::allowed
          : (authorized ? AuditOutcome::failed : AuditOutcome::denied);
  const auto completed_bytes =
      outcome == definitions::DynamicDispatchResult::dispatched ? written : 0;
  if (!append(AuditEvent::operation_completed, terminal_outcome, decision,
              identity, completed_bytes)) {
    failed_ = true;
    return {.outcome = definitions::DynamicDispatchResult::adapter_failed,
            .decision = decision};
  }
  return {.outcome = outcome,
          .decision = decision,
          .response_bytes = completed_bytes};
}

DynamicRevocationResult DynamicBrokerRuntime::apply_reconstructed_revocation(
    const definitions::DynamicRevisionGrant &updated) {
  if (failed_)
    return {.status = DynamicRevocationStatus::failed};
  const auto route = std::ranges::find_if(routes_, [&](const auto &candidate) {
    return candidate.grant.binding == updated.binding &&
           candidate.grant.request.definition == updated.request.definition;
  });
  if (route == routes_.end() || route->grant.request != updated.request ||
      updated.grant.epoch != route->grant.grant.epoch + 1 ||
      updated.grant.definition != route->grant.grant.definition ||
      !definitions::review_dynamic_grant(registry_, updated,
                                         route->scope_validator))
    return {.status = DynamicRevocationStatus::binding_mismatch};
  const auto resolved = registry_.resolve(route->grant.request.definition);
  if (!resolved ||
      updated.grant.state != omarchy::plugins::permissions::GrantState::revoked)
    return {.status = DynamicRevocationStatus::binding_mismatch};
  const bool restart_worker = resolved->definition->revocation ==
                              definitions::RevocationPolicy::restart_worker;
  for (const auto &operation : route->grant.grant.operations.values()) {
    omarchy::plugins::permissions::AuditDraft draft{
        .event = omarchy::plugins::permissions::AuditEvent::capability_revoked,
        .outcome = omarchy::plugins::permissions::AuditOutcome::denied,
        .plugin = updated.binding.plugin,
        .revision = updated.binding.revision,
        .generation = updated.binding.generation,
        .correlation = 0,
        .dynamic_operation =
            omarchy::plugins::permissions::DynamicAuditIdentity{
                .capability = omarchy::plugins::permissions::CapabilityId(
                    updated.grant.definition.canonical_name.view()),
                .definition_generation =
                    updated.grant.definition.definition_generation,
                .definition_digest = updated.grant.definition.definition_digest,
                .operation = omarchy::plugins::permissions::BoundedString<128>(
                    operation.view()),
                .grant_epoch = updated.grant.epoch},
        .dynamic_attempt = std::nullopt,
        .operation = std::nullopt,
        .capability = std::nullopt,
        .decision = omarchy::plugins::permissions::GrantDecisionCode::revoked,
        .metadata = {}};
    if (!append_audit(std::move(draft)))
      return {.status = DynamicRevocationStatus::audit_failed,
              .restart_worker = restart_worker};
  }
  route->grant = updated;
  return {.status = DynamicRevocationStatus::accepted,
          .restart_worker = restart_worker};
}

bool DynamicBrokerRuntime::append_audit(
    omarchy::plugins::permissions::AuditDraft draft) noexcept {
  try {
    if (audit_
            .append(omarchy::plugins::permissions::AuditProducer::broker,
                    std::move(draft))
            .status.ok())
      return true;
  } catch (...) {
  }
  failed_ = true;
  return false;
}

} // namespace omarchy::plugin_runtime::runtime
