#include "omarchy/plugin_runtime/broker/broker_schema.hpp"

#include <array>
#include <bit>

namespace omarchy::plugin_runtime::broker {
namespace wire = omarchy::plugin::wire;
namespace {

using permissions::OperationId;
using wire::CorrelationRule;
using wire::DirectionMask;
using wire::MessageRule;
using wire::MessageSemantic;

constexpr std::array kRules{
    MessageRule{static_cast<std::uint16_t>(OperationId::storage_read),
                DirectionMask::worker_to_host, CorrelationRule::nonzero,
                MessageSemantic::request, 24, 65536},
    MessageRule{static_cast<std::uint16_t>(OperationId::storage_write),
                DirectionMask::worker_to_host, CorrelationRule::nonzero,
                MessageSemantic::request, 24, 65536},
    MessageRule{static_cast<std::uint16_t>(OperationId::storage_remove),
                DirectionMask::worker_to_host, CorrelationRule::nonzero,
                MessageSemantic::request, 24, 65536},
    MessageRule{static_cast<std::uint16_t>(OperationId::notification_send),
                DirectionMask::worker_to_host, CorrelationRule::nonzero,
                MessageSemantic::request, 11, 65536},
    MessageRule{static_cast<std::uint16_t>(OperationId::audio_play_cue),
                DirectionMask::worker_to_host, CorrelationRule::nonzero,
                MessageSemantic::request, 11, 65536},
    MessageRule{static_cast<std::uint16_t>(OperationId::fake_status_list),
                DirectionMask::worker_to_host, CorrelationRule::nonzero,
                MessageSemantic::request, 16, 65536},
    MessageRule{
        static_cast<std::uint16_t>(OperationId::fake_status_acknowledge),
        DirectionMask::worker_to_host, CorrelationRule::nonzero,
        MessageSemantic::request, 16, 65536},
    MessageRule{kBrokerResultMessage, DirectionMask::host_to_worker,
                CorrelationRule::nonzero, MessageSemantic::terminal, 0, 65536},
};

constexpr bool valid_reason(BrokerErrorReason reason) {
  return reason >= BrokerErrorReason::denied &&
         reason <= BrokerErrorReason::cancelled;
}

constexpr bool valid_decision(permissions::GrantDecisionCode decision) {
  return decision >= permissions::GrantDecisionCode::allowed &&
         decision <= permissions::GrantDecisionCode::gesture_used;
}

} // namespace

std::span<const wire::MessageRule> broker_wire_rules() { return kRules; }

wire::RoleSchemaView broker_role_schema() {
  return {.role = wire::EndpointRole::broker,
          .version = kBrokerRoleVersion,
          .messages = kRules,
          .typed_error_minimum_payload = kBrokerErrorBytes,
          .typed_error_maximum_payload = kBrokerErrorBytes};
}

const wire::RoleSchemaRegistryView &broker_schema_registry() {
  static const std::array schemas{broker_role_schema()};
  static const wire::RoleSchemaRegistryView registry(schemas);
  return registry;
}

bool registered_operation(std::uint16_t message_type) {
  const auto operation = static_cast<OperationId>(message_type);
  return permissions::find_operation(operation) != nullptr;
}

std::array<std::byte, kBrokerErrorBytes>
encode_broker_error(const BrokerTypedError &error) {
  std::array<std::byte, kBrokerErrorBytes> output{};
  const auto operation = static_cast<std::uint16_t>(error.failed_operation);
  const auto reason = static_cast<std::uint16_t>(error.reason);
  output[0] = static_cast<std::byte>(operation >> 8U);
  output[1] = static_cast<std::byte>(operation);
  output[2] = static_cast<std::byte>(reason >> 8U);
  output[3] = static_cast<std::byte>(reason);
  output[4] = static_cast<std::byte>(error.decision);
  return output;
}

bool decode_broker_error(std::span<const std::byte> bytes,
                         BrokerTypedError &output) {
  if (bytes.size() != kBrokerErrorBytes || bytes[5] != std::byte{0} ||
      bytes[6] != std::byte{0} || bytes[7] != std::byte{0}) {
    return false;
  }
  const auto operation =
      static_cast<std::uint16_t>(std::to_integer<std::uint8_t>(bytes[0]) << 8U |
                                 std::to_integer<std::uint8_t>(bytes[1]));
  const auto reason = static_cast<BrokerErrorReason>(
      std::to_integer<std::uint8_t>(bytes[2]) << 8U |
      std::to_integer<std::uint8_t>(bytes[3]));
  const auto decision = static_cast<permissions::GrantDecisionCode>(
      std::to_integer<std::uint8_t>(bytes[4]));
  if (!registered_operation(operation) || !valid_reason(reason) ||
      !valid_decision(decision) ||
      (reason == BrokerErrorReason::denied) !=
          (decision != permissions::GrantDecisionCode::allowed)) {
    return false;
  }
  output = {.failed_operation = static_cast<OperationId>(operation),
            .reason = reason,
            .decision = decision};
  return true;
}

} // namespace omarchy::plugin_runtime::broker
