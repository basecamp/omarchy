#pragma once

#include "omarchy/plugin/wire/envelope.hpp"

#include <array>
#include <cstddef>
#include <cstdint>
#include <span>

namespace omarchy::plugin::wire {

struct VersionRange {
  std::uint16_t minimum = 0;
  std::uint16_t maximum = 0;
};

struct HelloPayload {
  VersionRange supported;
};

struct WelcomePayload {
  std::uint32_t maximum_payload = 0;
  std::uint32_t maximum_in_flight = 0;
};

enum class NegotiationFailure : std::uint16_t { no_common_role_version = 1 };

struct NegotiationFailedPayload {
  NegotiationFailure reason = NegotiationFailure::no_common_role_version;
  VersionRange trusted_supported;
};

enum class CancelOutcome : std::uint16_t {
  accepted = 1,
  already_completed = 2,
  unknown = 3,
  not_cancellable = 4,
};

enum class ProtocolErrorReason : std::uint16_t {
  invalid_message = 1,
};

[[nodiscard]] std::array<std::byte, 4>
encode_hello_payload(const HelloPayload &payload);
[[nodiscard]] std::array<std::byte, 8>
encode_welcome_payload(const WelcomePayload &payload);
[[nodiscard]] std::array<std::byte, 6>
encode_negotiation_failed_payload(const NegotiationFailedPayload &payload);
[[nodiscard]] std::array<std::byte, 2>
encode_cancel_result_payload(CancelOutcome outcome);
[[nodiscard]] std::array<std::byte, 2>
encode_protocol_error_payload(ProtocolErrorReason reason);

[[nodiscard]] bool decode_hello_payload(std::span<const std::byte> bytes,
                                        HelloPayload &output);
[[nodiscard]] bool decode_welcome_payload(std::span<const std::byte> bytes,
                                          WelcomePayload &output);
[[nodiscard]] bool
decode_negotiation_failed_payload(std::span<const std::byte> bytes,
                                  NegotiationFailedPayload &output);
[[nodiscard]] bool
decode_cancel_result_payload(std::span<const std::byte> bytes,
                             CancelOutcome &output);
[[nodiscard]] bool
decode_protocol_error_payload(std::span<const std::byte> bytes,
                              ProtocolErrorReason &output);

} // namespace omarchy::plugin::wire
