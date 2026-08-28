#include "omarchy/plugin/wire/envelope.hpp"
#include "omarchy/plugin/wire/state.hpp"
#include "omarchy/plugin_runtime/broker/broker_codec.hpp"
#include "omarchy/plugin_runtime/sandbox/policy.h"
#include "omarchy/plugin_runtime/surface/render_messages.hpp"
#include "omarchy/plugin_runtime/surface/shared_layout.hpp"

#include <algorithm>
#include <array>
#include <cstddef>
#include <cstdint>
#include <iostream>
#include <limits>
#include <span>
#include <stdexcept>
#include <string>
#include <string_view>
#include <vector>

namespace {

namespace broker = omarchy::plugin_runtime::broker;
namespace permissions = omarchy::plugins::permissions;
namespace sandbox = omarchy::plugin_runtime::sandbox;
namespace surface = omarchy::plugin_runtime::surface;
namespace wire = omarchy::plugin::wire;

void require(bool condition, std::string_view message) {
  if (!condition)
    throw std::runtime_error(std::string(message));
}

std::vector<std::byte> packet(std::size_t payload_size) {
  std::vector<std::byte> payload(payload_size, std::byte{0x5a});
  std::vector<std::byte> output(wire::kHeaderSize + payload.size());
  const wire::EnvelopeHeader header{
      .endpoint_role = wire::EndpointRole::control,
      .message_type = 0x1000,
      .role_protocol_version = 1,
      .payload_length = static_cast<std::uint32_t>(payload.size()),
      .launch_generation = 7,
      .correlation_id = 1};
  const auto encoded = wire::encode_packet(header, payload, output);
  require(static_cast<bool>(encoded), "valid corpus packet did not encode");
  return output;
}

void put32(std::span<std::byte> bytes, std::size_t offset,
           std::uint32_t value) {
  for (std::size_t index = 0; index < 4; ++index)
    bytes[offset + index] =
        static_cast<std::byte>(value >> ((3U - index) * 8U));
}

void malformed_envelope_campaign() {
  const auto valid = packet(32);
  for (std::size_t length = 0; length < wire::kHeaderSize; ++length)
    require(!wire::decode_packet(std::span(valid).first(length),
                                 wire::EndpointRole::control),
            "truncated envelope was accepted");

  for (std::size_t iteration = 0; iteration < 10'000; ++iteration) {
    auto mutated = valid;
    const std::size_t offset = (iteration * 17U + 3U) % wire::kHeaderSize;
    mutated[offset] ^= static_cast<std::byte>((iteration % 251U) + 1U);
    const auto decoded =
        wire::decode_packet(mutated, wire::EndpointRole::control);
    if (decoded)
      require(decoded.packet.payload.size() == 32 &&
                  decoded.packet.header.endpoint_role ==
                      wire::EndpointRole::control,
              "mutated envelope escaped bounded decode invariants");
  }

  auto oversized = valid;
  put32(oversized, 16, wire::payload_cap(wire::EndpointRole::control) + 1U);
  require(!wire::decode_packet(oversized, wire::EndpointRole::control),
          "oversized declared payload was accepted");
  oversized.resize(wire::kHeaderSize +
                       wire::payload_cap(wire::EndpointRole::control) + 1U,
                   std::byte{0});
  put32(oversized, 16, wire::payload_cap(wire::EndpointRole::control) + 1U);
  require(!wire::decode_packet(oversized, wire::EndpointRole::control),
          "oversized materialized payload was accepted");
}

void request_and_frame_caps() {
  wire::FixedOperationTable<32> operations;
  for (std::uint64_t correlation = 1; correlation <= 32; ++correlation)
    require(operations.insert(correlation, 32) == wire::FatalReason::none,
            "in-budget correlation was rejected");
  require(operations.insert(33, 32) ==
                  wire::FatalReason::maximum_in_flight_exceeded &&
              operations.size() == 32,
          "request flood grew the fixed correlation table");

  const surface::FrameReady frame{.surface = {.id = 1, .generation = 7},
                                  .slot = 0,
                                  .slot_sequence = 2,
                                  .frame_sequence = 1};
  const auto encoded_frame = surface::encode_frame_ready(frame);
  for (std::size_t length = 0; length < encoded_frame.size(); ++length) {
    surface::FrameReady ignored{};
    require(!surface::decode_frame_ready(std::span(encoded_frame).first(length),
                                         ignored),
            "truncated frame-ready payload was accepted");
  }
  require(!surface::make_allocation({.id = 1, .generation = 7},
                                    std::numeric_limits<std::uint32_t>::max(),
                                    std::numeric_limits<std::uint32_t>::max(),
                                    std::numeric_limits<std::uint32_t>::max(),
                                    std::numeric_limits<std::uint32_t>::max(),
                                    1, 1, 4096),
          "overflowing frame allocation was accepted");

  std::vector<std::byte> provider(broker::kBrokerRequestHeaderBytes +
                                      broker::kMaximumProviderPayloadBytes + 1,
                                  std::byte{0});
  put32(provider, 4,
        static_cast<std::uint32_t>(broker::kMaximumProviderPayloadBytes + 1));
  broker::DecodedBrokerRequest decoded{};
  require(broker::decode_broker_request(
              static_cast<std::uint16_t>(
                  permissions::OperationId::notification_send),
              provider,
              decoded) == broker::BrokerDecodeResult::payload_too_large,
          "broker provider-output-sized request bypassed its byte cap");
}

void kernel_resource_contract() {
  const auto plan = sandbox::build_plan();
  require(plan.resources.memory_high_bytes < plan.resources.memory_max_bytes &&
              plan.resources.memory_max_bytes == 512ULL * 1024ULL * 1024ULL &&
              plan.resources.scratch_max_bytes == 64ULL * 1024ULL * 1024ULL &&
              plan.resources.tasks_max == 16 &&
              plan.resources.cpu_quota_percent == 50 &&
              plan.resources.open_files_max == 64 &&
              plan.resources.output_burst_bytes == 64ULL * 1024ULL &&
              plan.resources.output_bytes_per_second == 4096 &&
              plan.process.standard_output_is_bounded_pipe &&
              plan.process.standard_error_is_bounded_pipe &&
              !plan.process.descendants_permitted,
          "kernel resource or output-flood policy was weakened");
}

} // namespace

int main() {
  try {
    malformed_envelope_campaign();
    request_and_frame_caps();
    kernel_resource_contract();
  } catch (const std::exception &error) {
    std::cerr << "FAIL: " << error.what() << '\n';
    return 1;
  }
  std::cout << "F1 deterministic exhaustion corpus passed\n";
  return 0;
}
