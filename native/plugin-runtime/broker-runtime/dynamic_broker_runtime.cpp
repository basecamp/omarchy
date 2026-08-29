#include "dynamic_broker_runtime.hpp"

#include <algorithm>
#include <stdexcept>
#include <utility>

namespace omarchy::plugin_runtime::runtime {

DynamicBrokerRuntime::DynamicBrokerRuntime(
    const definitions::TrustedDefinitionRegistry &registry,
    std::vector<DynamicRoute> reconstructed_routes)
    : registry_(registry), routes_(std::move(reconstructed_routes)) {
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
    bool fresh_gesture) {
  if (packet.header.message_type != broker::kDynamicInvokeMessage ||
      packet.header.correlation_id == 0)
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
  std::size_t written = 0;
  definitions::DynamicDecision decision = definitions::DynamicDecision::denied;
  const auto outcome = definitions::dispatch_dynamic_invocation(
      registry_, route->grant, channel_binding, packet.payload,
      route->adapter, route->scope_validator, fresh_gesture, response, written,
      decision);
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
  route->grant = updated;
  return true;
}

} // namespace omarchy::plugin_runtime::runtime
