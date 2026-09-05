#include "omarchy/plugin_runtime/broker/broker_codec.hpp"

#include <limits>
#include <string_view>

namespace omarchy::plugin_runtime::broker {
namespace {

std::uint16_t get16(std::span<const std::byte> bytes, std::size_t offset) {
  return static_cast<std::uint16_t>(
      std::to_integer<std::uint8_t>(bytes[offset]) << 8U |
      std::to_integer<std::uint8_t>(bytes[offset + 1]));
}

std::uint32_t get32(std::span<const std::byte> bytes, std::size_t offset) {
  std::uint32_t value = 0;
  for (std::size_t index = 0; index < 4; ++index) {
    value =
        (value << 8U) | std::to_integer<std::uint8_t>(bytes[offset + index]);
  }
  return value;
}

std::uint64_t get64(std::span<const std::byte> bytes, std::size_t offset) {
  std::uint64_t value = 0;
  for (std::size_t index = 0; index < 8; ++index) {
    value =
        (value << 8U) | std::to_integer<std::uint8_t>(bytes[offset + index]);
  }
  return value;
}

bool is_storage(permissions::OperationId operation) {
  return operation == permissions::OperationId::storage_read ||
         operation == permissions::OperationId::storage_write ||
         operation == permissions::OperationId::storage_remove;
}

bool is_token(permissions::OperationId operation) {
  return operation == permissions::OperationId::notification_send ||
         operation == permissions::OperationId::audio_play_cue;
}

} // namespace

BrokerDecodeResult decode_broker_request(std::uint16_t message_type,
                                         std::span<const std::byte> payload,
                                         DecodedBrokerRequest &output) {
  const auto operation = static_cast<permissions::OperationId>(message_type);
  const auto *definition = permissions::find_operation(operation);
  if (definition == nullptr) {
    return BrokerDecodeResult::unknown_operation;
  }
  if (payload.size() < kBrokerRequestHeaderBytes) {
    return BrokerDecodeResult::malformed_header;
  }
  const auto repeated_operation = get16(payload, 0);
  const auto demand_bytes = get16(payload, 2);
  const auto provider_bytes = get32(payload, 4);
  if (repeated_operation != message_type ||
      provider_bytes > kMaximumProviderPayloadBytes ||
      demand_bytes > payload.size() - kBrokerRequestHeaderBytes ||
      provider_bytes !=
          payload.size() - kBrokerRequestHeaderBytes - demand_bytes) {
    return provider_bytes > kMaximumProviderPayloadBytes
               ? BrokerDecodeResult::payload_too_large
               : BrokerDecodeResult::malformed_header;
  }
  const auto demand = payload.subspan(kBrokerRequestHeaderBytes, demand_bytes);
  permissions::Scope scope;
  if (is_storage(operation)) {
    if (demand.size() != 16) {
      return BrokerDecodeResult::malformed_demand;
    }
    scope = permissions::QuotaScope{.total_bytes = get64(demand, 0),
                                    .item_bytes = get64(demand, 8)};
  } else if (is_token(operation)) {
    if (demand.size() < 3 || get16(demand, 0) != demand.size() - 2) {
      return BrokerDecodeResult::malformed_demand;
    }
    const auto token_bytes = demand.subspan(2);
    const std::string_view token(
        reinterpret_cast<const char *>(token_bytes.data()), token_bytes.size());
    if (token.empty() || token.size() > 96 ||
        token.find('\0') != std::string_view::npos) {
      return BrokerDecodeResult::malformed_demand;
    }
    permissions::TokenScope tokens;
    tokens.tokens.insert(permissions::ScopeToken(token));
    scope = std::move(tokens);
  } else {
    if (demand.size() != 8 || get16(demand, 4) != message_type ||
        get16(demand, 6) != 0 || get32(demand, 0) == 0) {
      return BrokerDecodeResult::malformed_demand;
    }
    permissions::ResourceScope resources;
    resources.resources.insert(get32(demand, 0));
    resources.operations.insert(operation);
    scope = std::move(resources);
  }
  if (!permissions::valid_scope(*definition, scope)) {
    return BrokerDecodeResult::malformed_demand;
  }
  output = {.operation = operation,
            .demand = std::move(scope),
            .provider_payload = payload.last(provider_bytes)};
  return BrokerDecodeResult::accepted;
}

} // namespace omarchy::plugin_runtime::broker
