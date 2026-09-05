#pragma once

#include "permission_contract.hpp"

#include <cstddef>
#include <cstdint>
#include <span>

namespace omarchy::plugin_runtime::broker {

namespace permissions = omarchy::plugins::permissions;

inline constexpr std::size_t kBrokerRequestHeaderBytes = 8;
inline constexpr std::size_t kMaximumProviderPayloadBytes = 60 * 1024;

enum class BrokerDecodeResult : std::uint8_t {
  accepted,
  unknown_operation,
  malformed_header,
  malformed_demand,
  payload_too_large,
};

struct DecodedBrokerRequest {
  permissions::OperationId operation{};
  permissions::Scope demand;
  std::span<const std::byte> provider_payload;
};

[[nodiscard]] BrokerDecodeResult
decode_broker_request(std::uint16_t message_type,
                      std::span<const std::byte> payload,
                      DecodedBrokerRequest &output);

} // namespace omarchy::plugin_runtime::broker
