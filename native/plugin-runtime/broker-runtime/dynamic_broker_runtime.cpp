#include "dynamic_broker_runtime.hpp"

#include <algorithm>
#include <stdexcept>
#include <utility>

namespace omarchy::plugin_runtime::runtime {

bool DynamicGestureLatch::arm(
    const omarchy::plugins::permissions::ActivationBinding &binding,
    const definitions::DynamicInvocation::GestureClaim &claim) {
  const auto now = clock_.now_nanoseconds();
  constexpr std::uint64_t lifetime = 5'000'000'000ULL;
  if (claim.surface_id == 0 || claim.surface_generation == 0 ||
      claim.input_sequence == 0 || now > UINT64_MAX - lifetime ||
      (armed_ && binding == binding_ && claim.surface_id == claim_.surface_id &&
       claim.surface_generation == claim_.surface_generation &&
       claim.input_sequence <= claim_.input_sequence)) {
    clear();
    return false;
  }
  binding_ = binding;
  claim_ = claim;
  deadline_nanoseconds_ = now + lifetime;
  armed_ = true;
  return true;
}

bool DynamicGestureLatch::consume(
    const omarchy::plugins::permissions::ActivationBinding &binding,
    const definitions::DynamicInvocation::GestureClaim &claim) {
  if (!armed_)
    return false;
  if (clock_.now_nanoseconds() > deadline_nanoseconds_) {
    clear();
    return false;
  }
  if (binding != binding_ || claim != claim_)
    return false;
  clear();
  return true;
}

void DynamicGestureLatch::clear() noexcept {
  armed_ = false;
  deadline_nanoseconds_ = 0;
  claim_ = {};
}

DynamicBrokerRuntime::DynamicBrokerRuntime(
    const definitions::TrustedDefinitionRegistry &registry,
    std::vector<DynamicRoute> reconstructed_routes,
    omarchy::plugins::audit::AuditSink &audit_sink)
    : registry_(registry), routes_(std::move(reconstructed_routes)),
      audit_(audit_sink) {
  for (const auto &route : routes_) {
    if (!definitions::review_dynamic_grant(registry_, route.grant,
                                            route.scope_validator) ||
        route.adapter.dispatch == nullptr)
      throw std::runtime_error("dynamic route was not reconstructed from an exact grant");
  }
}

DynamicBrokerResult DynamicBrokerRuntime::dispatch(
    const wire::PacketView &packet,
    const omarchy::plugins::permissions::ActivationBinding &channel_binding,
    std::span<std::byte> response,
    DynamicGestureAuthority *gesture_authority) {
  if (failed_ || packet.header.message_type != broker::kDynamicInvokeMessage ||
      packet.header.correlation_id == 0 ||
      packet.header.correlation_id <= last_correlation_)
    return {.outcome = definitions::DynamicDispatchResult::malformed};
  definitions::DynamicInvocation invocation;
  if (!definitions::decode_dynamic_invocation(packet.payload, invocation))
    return {.outcome = definitions::DynamicDispatchResult::malformed};
  const auto route = std::ranges::find_if(routes_, [&](const auto &candidate) {
    return candidate.grant.request.definition.canonical_name ==
               invocation.definition.canonical_name &&
           candidate.grant.request.definition.definition_generation ==
               invocation.definition.definition_generation &&
           candidate.grant.request.definition.definition_digest ==
               invocation.definition.definition_digest;
  });
  if (route == routes_.end())
    return {};
  definitions::DynamicDecision decision = definitions::DynamicDecision::denied;
  bool authorized = false;
  if (channel_binding != route->grant.binding) {
    decision = definitions::DynamicDecision::denied;
  } else {
    auto authorization = definitions::authorize_dynamic_operation(
        registry_, route->grant.request, route->grant.grant,
        invocation.operation.view(), invocation.demand_scope.view(),
        route->adapter.binding, route->scope_validator, false);
    if (authorization.decision == definitions::DynamicDecision::gesture_missing &&
        invocation.gesture && gesture_authority != nullptr &&
        gesture_authority->consume(channel_binding, *invocation.gesture))
      authorization = definitions::authorize_dynamic_operation(
          registry_, route->grant.request, route->grant.grant,
          invocation.operation.view(), invocation.demand_scope.view(),
          route->adapter.binding, route->scope_validator, true);
    decision = authorization.decision;
    authorized = authorization.allowed();
  }
  const auto code = [&] {
    if (decision == definitions::DynamicDecision::allowed)
      return omarchy::plugins::permissions::GrantDecisionCode::allowed;
    if (decision == definitions::DynamicDecision::revoked)
      return omarchy::plugins::permissions::GrantDecisionCode::revoked;
    if (decision == definitions::DynamicDecision::scope_expanded)
      return omarchy::plugins::permissions::GrantDecisionCode::outside_scope;
    return omarchy::plugins::permissions::GrantDecisionCode::ungranted;
  }();
  const auto identity = omarchy::plugins::permissions::DynamicAuditIdentity{
      .capability = omarchy::plugins::permissions::CapabilityId(
          invocation.definition.canonical_name.view()),
      .definition_generation = invocation.definition.definition_generation,
      .definition_digest = invocation.definition.definition_digest,
      .operation = omarchy::plugins::permissions::BoundedString<128>(
          invocation.operation.view()),
      .grant_epoch = route->grant.grant.epoch};
  const auto append = [&](omarchy::plugins::permissions::AuditEvent event,
                          omarchy::plugins::permissions::AuditOutcome audit_outcome,
                          std::size_t response_bytes) {
    omarchy::plugins::permissions::AuditDraft draft{
        .event = event, .outcome = audit_outcome,
        .plugin = route->grant.binding.plugin,
        .revision = route->grant.binding.revision,
        .generation = route->grant.binding.generation,
        .correlation = packet.header.correlation_id,
        .dynamic_operation = identity, .operation = std::nullopt,
        .capability = std::nullopt, .decision = code, .metadata = {}};
    draft.metadata.push_back(
        {omarchy::plugins::permissions::AuditMetric::request_bytes,
         static_cast<std::int64_t>(packet.payload.size())});
    if (response_bytes > 0)
      draft.metadata.push_back(
          {omarchy::plugins::permissions::AuditMetric::response_bytes,
           static_cast<std::int64_t>(response_bytes)});
    return audit_.append(omarchy::plugins::permissions::AuditProducer::broker,
                         std::move(draft)).status.ok();
  };
  if (!append(omarchy::plugins::permissions::AuditEvent::operation_decided,
              authorized ? omarchy::plugins::permissions::AuditOutcome::allowed
                         : omarchy::plugins::permissions::AuditOutcome::denied,
              0)) {
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
  const auto terminal_outcome = outcome == definitions::DynamicDispatchResult::dispatched
                                    ? omarchy::plugins::permissions::AuditOutcome::allowed
                                    : (authorized
                                           ? omarchy::plugins::permissions::AuditOutcome::failed
                                           : omarchy::plugins::permissions::AuditOutcome::denied);
  if (!append(omarchy::plugins::permissions::AuditEvent::operation_completed,
              terminal_outcome, written)) {
    failed_ = true;
    return {.outcome = definitions::DynamicDispatchResult::adapter_failed,
            .decision = decision};
  }
  return {.outcome = outcome, .decision = decision, .response_bytes = written};
}

bool DynamicBrokerRuntime::apply_reconstructed_update(
    const definitions::DynamicRevisionGrant &updated) {
  const auto route = std::ranges::find_if(routes_, [&](const auto &candidate) {
    return candidate.grant.binding == updated.binding &&
           candidate.grant.request.definition.canonical_name ==
               updated.request.definition.canonical_name;
  });
  if (route == routes_.end() || route->grant.request.definition.definition_generation !=
                                  updated.request.definition.definition_generation ||
      route->grant.request.definition.definition_digest !=
          updated.request.definition.definition_digest ||
      route->grant.request.operations != updated.request.operations ||
      route->grant.request.scope != updated.request.scope ||
      route->grant.request.required != updated.request.required ||
      updated.grant.epoch != route->grant.grant.epoch + 1 ||
      updated.grant.definition.canonical_name != route->grant.grant.definition.canonical_name ||
      updated.grant.definition.definition_generation != route->grant.grant.definition.definition_generation ||
      updated.grant.definition.definition_digest != route->grant.grant.definition.definition_digest ||
      !definitions::review_dynamic_grant(registry_, updated,
                                          route->scope_validator))
    return false;
  for (const auto &operation : updated.grant.operations.values()) {
    omarchy::plugins::permissions::AuditDraft draft{
        .event = omarchy::plugins::permissions::AuditEvent::capability_revoked,
        .outcome = omarchy::plugins::permissions::AuditOutcome::denied,
        .plugin = updated.binding.plugin, .revision = updated.binding.revision,
        .generation = updated.binding.generation, .correlation = 0,
        .dynamic_operation = omarchy::plugins::permissions::DynamicAuditIdentity{
            .capability = omarchy::plugins::permissions::CapabilityId(
                updated.grant.definition.canonical_name.view()),
            .definition_generation = updated.grant.definition.definition_generation,
            .definition_digest = updated.grant.definition.definition_digest,
            .operation = omarchy::plugins::permissions::BoundedString<128>(
                operation.view()),
            .grant_epoch = updated.grant.epoch},
        .operation = std::nullopt, .capability = std::nullopt,
        .decision = omarchy::plugins::permissions::GrantDecisionCode::revoked,
        .metadata = {}};
    if (!audit_.append(omarchy::plugins::permissions::AuditProducer::broker,
                       std::move(draft)).status.ok()) {
      failed_ = true;
      return false;
    }
  }
  route->grant = updated;
  return true;
}

} // namespace omarchy::plugin_runtime::runtime
