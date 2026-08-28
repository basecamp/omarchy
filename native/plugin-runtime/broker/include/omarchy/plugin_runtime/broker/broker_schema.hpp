#pragma once

#include "omarchy/plugin/wire/role_registry.hpp"
#include "permission_contract.hpp"

#include <array>
#include <cstddef>
#include <cstdint>
#include <span>

namespace omarchy::plugin_runtime::broker {

namespace permissions = omarchy::plugins::permissions;

inline constexpr std::uint16_t kBrokerRoleVersion = 1;
inline constexpr std::uint16_t kBrokerResultMessage = 0x5000;
inline constexpr std::size_t kBrokerErrorBytes = 8;

enum class BrokerErrorReason : std::uint16_t {
  denied = 1,
  malformed_request = 2,
  provider_unavailable = 3,
  provider_failed = 4,
  cancelled = 5,
};

struct BrokerTypedError {
  permissions::OperationId failed_operation{};
  BrokerErrorReason reason = BrokerErrorReason::denied;
  permissions::GrantDecisionCode decision =
      permissions::GrantDecisionCode::ungranted;
};

[[nodiscard]] std::span<const omarchy::plugin::wire::MessageRule>
broker_wire_rules();
[[nodiscard]] omarchy::plugin::wire::RoleSchemaView broker_role_schema();
[[nodiscard]] const omarchy::plugin::wire::RoleSchemaRegistryView &
broker_schema_registry();
[[nodiscard]] bool registered_operation(std::uint16_t message_type);

[[nodiscard]] std::array<std::byte, kBrokerErrorBytes>
encode_broker_error(const BrokerTypedError &error);
[[nodiscard]] bool decode_broker_error(std::span<const std::byte> bytes,
                                       BrokerTypedError &output);

} // namespace omarchy::plugin_runtime::broker
