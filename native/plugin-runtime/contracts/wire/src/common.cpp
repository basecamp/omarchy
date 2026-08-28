#include "omarchy/plugin/wire/common.hpp"
#include "omarchy/plugin/wire/state.hpp"

#include <algorithm>

namespace omarchy::plugin::wire {
namespace {

void put16(std::span<std::byte> output, std::size_t offset,
           std::uint16_t value) {
  output[offset] = static_cast<std::byte>(value >> 8U);
  output[offset + 1] = static_cast<std::byte>(value);
}

void put32(std::span<std::byte> output, std::size_t offset,
           std::uint32_t value) {
  put16(output, offset, static_cast<std::uint16_t>(value >> 16U));
  put16(output, offset + 2, static_cast<std::uint16_t>(value));
}

std::uint16_t get16(std::span<const std::byte> input, std::size_t offset) {
  return (std::to_integer<std::uint16_t>(input[offset]) << 8U) |
         std::to_integer<std::uint16_t>(input[offset + 1]);
}

std::uint32_t get32(std::span<const std::byte> input, std::size_t offset) {
  return (static_cast<std::uint32_t>(get16(input, offset)) << 16U) |
         get16(input, offset + 2);
}

EnvelopeHeader common_header(EndpointRole role, CommonMessageType type) {
  return EnvelopeHeader{.endpoint_role = role,
                        .message_type = static_cast<std::uint16_t>(type)};
}

} // namespace

std::array<std::byte, 4> encode_hello_payload(const HelloPayload &payload) {
  std::array<std::byte, 4> output{};
  put16(output, 0, payload.supported.minimum);
  put16(output, 2, payload.supported.maximum);
  return output;
}

std::array<std::byte, 8> encode_welcome_payload(const WelcomePayload &payload) {
  std::array<std::byte, 8> output{};
  put32(output, 0, payload.maximum_payload);
  put32(output, 4, payload.maximum_in_flight);
  return output;
}

std::array<std::byte, 6>
encode_negotiation_failed_payload(const NegotiationFailedPayload &payload) {
  std::array<std::byte, 6> output{};
  put16(output, 0, static_cast<std::uint16_t>(payload.reason));
  put16(output, 2, payload.trusted_supported.minimum);
  put16(output, 4, payload.trusted_supported.maximum);
  return output;
}

std::array<std::byte, 2> encode_cancel_result_payload(CancelOutcome outcome) {
  std::array<std::byte, 2> output{};
  put16(output, 0, static_cast<std::uint16_t>(outcome));
  return output;
}

std::array<std::byte, 2>
encode_protocol_error_payload(ProtocolErrorReason reason) {
  std::array<std::byte, 2> output{};
  put16(output, 0, static_cast<std::uint16_t>(reason));
  return output;
}

bool decode_hello_payload(std::span<const std::byte> bytes,
                          HelloPayload &output) {
  if (bytes.size() != 4) {
    return false;
  }
  output.supported = {get16(bytes, 0), get16(bytes, 2)};
  return output.supported.minimum != 0 &&
         output.supported.minimum <= output.supported.maximum;
}

bool decode_welcome_payload(std::span<const std::byte> bytes,
                            WelcomePayload &output) {
  if (bytes.size() != 8) {
    return false;
  }
  output = {get32(bytes, 0), get32(bytes, 4)};
  return output.maximum_payload != 0 && output.maximum_in_flight != 0;
}

bool decode_negotiation_failed_payload(std::span<const std::byte> bytes,
                                       NegotiationFailedPayload &output) {
  if (bytes.size() != 6) {
    return false;
  }
  output = {static_cast<NegotiationFailure>(get16(bytes, 0)),
            {get16(bytes, 2), get16(bytes, 4)}};
  return output.reason == NegotiationFailure::no_common_role_version &&
         output.trusted_supported.minimum != 0 &&
         output.trusted_supported.minimum <= output.trusted_supported.maximum;
}

bool decode_cancel_result_payload(std::span<const std::byte> bytes,
                                  CancelOutcome &output) {
  if (bytes.size() != 2) {
    return false;
  }
  output = static_cast<CancelOutcome>(get16(bytes, 0));
  return output >= CancelOutcome::accepted &&
         output <= CancelOutcome::not_cancellable;
}

bool decode_protocol_error_payload(std::span<const std::byte> bytes,
                                   ProtocolErrorReason &output) {
  if (bytes.size() != 2) {
    return false;
  }
  output = static_cast<ProtocolErrorReason>(get16(bytes, 0));
  return output == ProtocolErrorReason::invalid_message;
}

NegotiationResult TrustedNegotiator::accept_hello(const PacketView &packet) {
  if (hello_seen_ || selected_ || failed_) {
    failed_ = true;
    return {.error = FatalReason::duplicate_hello};
  }
  hello_seen_ = true;
  if (packet.header.endpoint_role != role_ ||
      packet.header.message_type !=
          static_cast<std::uint16_t>(CommonMessageType::hello) ||
      packet.header.role_protocol_version != 0 ||
      packet.header.launch_generation != 0 ||
      packet.header.correlation_id != 0 || supported_.minimum == 0 ||
      supported_.minimum > supported_.maximum || generation_ == 0 ||
      maximum_payload_ == 0 || maximum_payload_ > payload_cap(role_) ||
      maximum_in_flight_ == 0) {
    failed_ = true;
    return {.error = FatalReason::invalid_message_order};
  }
  HelloPayload hello{};
  if (!decode_hello_payload(packet.payload, hello)) {
    failed_ = true;
    return {.error = FatalReason::invalid_common_payload};
  }

  const auto minimum = std::max(supported_.minimum, hello.supported.minimum);
  const auto maximum = std::min(supported_.maximum, hello.supported.maximum);
  if (minimum > maximum) {
    failed_ = true;
    NegotiationResult result{};
    result.kind = NegotiationKind::negotiation_failed;
    result.header = common_header(role_, CommonMessageType::negotiation_failed);
    const auto payload = encode_negotiation_failed_payload(
        {NegotiationFailure::no_common_role_version, supported_});
    std::copy(payload.begin(), payload.end(), result.payload.begin());
    result.payload_size = payload.size();
    return result;
  }

  selected_ = true;
  selected_version_ = maximum;
  NegotiationResult result{};
  result.kind = NegotiationKind::welcome;
  result.header = common_header(role_, CommonMessageType::welcome);
  result.header.role_protocol_version = selected_version_;
  result.header.launch_generation = generation_;
  const auto payload =
      encode_welcome_payload({maximum_payload_, maximum_in_flight_});
  std::copy(payload.begin(), payload.end(), result.payload.begin());
  result.payload_size = payload.size();
  return result;
}

WorkerNegotiator::HelloResult WorkerNegotiator::make_hello() {
  if (hello_sent_ || selected_ || failed_ || supported_.minimum == 0 ||
      supported_.minimum > supported_.maximum) {
    failed_ = true;
    return {.error = FatalReason::invalid_message_order};
  }
  hello_sent_ = true;
  return {.header = common_header(role_, CommonMessageType::hello),
          .payload = encode_hello_payload({supported_})};
}

FatalReason WorkerNegotiator::accept_reply(const PacketView &packet) {
  if (selected_) {
    failed_ = true;
    return FatalReason::duplicate_welcome;
  }
  if (!hello_sent_ || failed_) {
    failed_ = true;
    return FatalReason::invalid_message_order;
  }
  if (packet.header.endpoint_role != role_ ||
      packet.header.correlation_id != 0) {
    failed_ = true;
    return FatalReason::invalid_welcome;
  }
  if (packet.header.message_type ==
      static_cast<std::uint16_t>(CommonMessageType::negotiation_failed)) {
    NegotiationFailedPayload failure{};
    if (packet.header.role_protocol_version != 0 ||
        packet.header.launch_generation != 0 ||
        !decode_negotiation_failed_payload(packet.payload, failure)) {
      failed_ = true;
      return FatalReason::invalid_common_payload;
    }
    failed_ = true;
    return FatalReason::version_negotiation_failed;
  }
  if (packet.header.message_type !=
          static_cast<std::uint16_t>(CommonMessageType::welcome) ||
      packet.header.role_protocol_version < supported_.minimum ||
      packet.header.role_protocol_version > supported_.maximum ||
      packet.header.launch_generation == 0) {
    failed_ = true;
    return FatalReason::invalid_welcome;
  }
  WelcomePayload welcome{};
  if (!decode_welcome_payload(packet.payload, welcome) ||
      welcome.maximum_payload > payload_cap(role_)) {
    failed_ = true;
    return FatalReason::invalid_welcome;
  }
  selected_ = true;
  selected_version_ = packet.header.role_protocol_version;
  generation_ = packet.header.launch_generation;
  maximum_payload_ = welcome.maximum_payload;
  maximum_in_flight_ = welcome.maximum_in_flight;
  return FatalReason::none;
}

FatalReason RequiredEndpointReadiness::observe(EndpointRole role,
                                               std::uint64_t generation) {
  const auto raw = static_cast<std::uint16_t>(role);
  if (raw < 1 || raw > generations_.size() || generation == 0 ||
      generations_[raw - 1] != 0) {
    return FatalReason::invalid_message_order;
  }
  generations_[raw - 1] = generation;
  return FatalReason::none;
}

FatalReason RequiredEndpointReadiness::ready(bool &output) const {
  output = false;
  if (std::any_of(generations_.begin(), generations_.end(),
                  [](std::uint64_t value) { return value == 0; })) {
    return FatalReason::none;
  }
  if (!std::all_of(
          generations_.begin(), generations_.end(),
          [&](std::uint64_t value) { return value == generations_.front(); })) {
    return FatalReason::readiness_generation_mismatch;
  }
  output = true;
  return FatalReason::none;
}

} // namespace omarchy::plugin::wire
