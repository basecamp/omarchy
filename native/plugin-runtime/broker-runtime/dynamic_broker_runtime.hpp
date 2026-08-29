#pragma once

#include "dynamic_activation.hpp"
#include "omarchy/plugin_runtime/broker/broker_schema.hpp"

#include <cstddef>
#include <cstdint>
#include <span>
#include <vector>

namespace omarchy::plugin_runtime::runtime {

namespace definitions = omarchy::plugins::definitions;
namespace wire = omarchy::plugin::wire;

struct DynamicRoute {
  definitions::DynamicRevisionGrant grant;
  definitions::DynamicAdapter adapter;
  definitions::DynamicScopeValidator scope_validator;
};

struct DynamicBrokerResult {
  definitions::DynamicDispatchResult outcome =
      definitions::DynamicDispatchResult::denied;
  definitions::DynamicDecision decision = definitions::DynamicDecision::denied;
  std::size_t response_bytes = 0;
};

class DynamicBrokerRuntime {
public:
  DynamicBrokerRuntime(const definitions::TrustedDefinitionRegistry &registry,
                       std::vector<DynamicRoute> reconstructed_routes);

  [[nodiscard]] DynamicBrokerResult dispatch(
      const wire::PacketView &packet,
      const omarchy::plugins::permissions::ActivationBinding &channel_binding,
      std::span<std::byte> response,
      bool fresh_gesture = false);

  // Accepts only the next persisted epoch for the exact same request and
  // definition. The caller remains responsible for cancelling an asynchronous
  // provider before publishing the permission snapshot.
  [[nodiscard]] bool apply_reconstructed_update(
      const definitions::DynamicRevisionGrant &updated);

private:
  const definitions::TrustedDefinitionRegistry &registry_;
  std::vector<DynamicRoute> routes_;
};

} // namespace omarchy::plugin_runtime::runtime
