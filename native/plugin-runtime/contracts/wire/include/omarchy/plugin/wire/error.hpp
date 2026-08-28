#pragma once

#include <cstdint>

namespace omarchy::plugin::wire {

enum class FatalReason : std::uint16_t {
  none = 0,
  output_too_small,
  payload_not_representable,
  packet_too_short,
  invalid_magic,
  unsupported_envelope_version,
  invalid_header_size,
  nonzero_flags,
  nonzero_reserved,
  endpoint_role_mismatch,
  payload_cap_exceeded,
  packet_length_mismatch,
  invalid_common_payload,
  invalid_message_order,
  duplicate_hello,
  version_negotiation_failed,
  invalid_welcome,
  duplicate_welcome,
  readiness_generation_mismatch,
  unsupported_role_version,
  stale_generation,
  unknown_message_type,
  invalid_direction,
  invalid_correlation,
  correlation_reused,
  maximum_in_flight_exceeded,
  unmatched_terminal,
  unmatched_cancel_result,
  duplicate_terminal,
  duplicate_cancel_result,
  invalid_role_schema,
};

enum class Issue : std::uint8_t {
  malformed_envelope,
  identity_or_transport_failure,
  invalid_state,
  unknown_schema,
  known_operation_denial,
  known_operation_failure,
  provider_unavailable,
  cancellation_outcome,
};

enum class FailureDisposition : std::uint8_t { fatal, recoverable };

[[nodiscard]] constexpr FailureDisposition classify(Issue issue) {
  switch (issue) {
  case Issue::known_operation_denial:
  case Issue::known_operation_failure:
  case Issue::provider_unavailable:
  case Issue::cancellation_outcome:
    return FailureDisposition::recoverable;
  case Issue::malformed_envelope:
  case Issue::identity_or_transport_failure:
  case Issue::invalid_state:
  case Issue::unknown_schema:
    return FailureDisposition::fatal;
  }
  return FailureDisposition::fatal;
}

} // namespace omarchy::plugin::wire
