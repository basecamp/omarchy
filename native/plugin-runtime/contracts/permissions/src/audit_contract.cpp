#include "permission_contract.hpp"

#include "canonical_identity_encoding.hpp"

#include <bit>

namespace omarchy::plugins::permissions {

using detail::append_text;
using detail::append_u16;
using detail::append_u32;
using detail::append_u64;
using detail::append_u8;
using detail::canonical_digest;
using detail::canonical_id;
using detail::domain;
using detail::fingerprint;
using detail::require;

bool valid_audit_producer(AuditProducer producer) {
  return static_cast<std::uint8_t>(producer) <=
         static_cast<std::uint8_t>(AuditProducer::surface_host);
}

void validate_audit_draft(const AuditDraft &draft) {
  require(canonical_id(draft.plugin.view()) &&
              canonical_digest(draft.revision) && draft.generation > 0,
          "invalid audit identity");
  require(static_cast<std::uint8_t>(draft.event) <=
                  static_cast<std::uint8_t>(AuditEvent::operation_completed) &&
              static_cast<std::uint8_t>(draft.outcome) <=
                  static_cast<std::uint8_t>(AuditOutcome::failed) &&
              static_cast<std::uint8_t>(draft.decision) <=
                  static_cast<std::uint8_t>(GrantDecisionCode::gesture_used),
          "invalid audit enumeration");
  const CapabilityDefinition *operation_definition = nullptr;
  if (draft.operation.has_value()) {
    operation_definition = find_operation(*draft.operation);
    require(operation_definition != nullptr, "unknown audit operation");
  }
  if (draft.capability.has_value()) {
    require(find_capability(*draft.capability) != nullptr,
            "unknown audit capability");
  }
  if (operation_definition != nullptr && draft.capability.has_value()) {
    require(operation_definition->key == *draft.capability,
            "audit operation and capability disagree");
  }
  if (draft.dynamic_operation.has_value()) {
    const auto &dynamic = *draft.dynamic_operation;
    require(!draft.operation.has_value() && !draft.capability.has_value() &&
                canonical_id(dynamic.capability.view()) &&
                dynamic.definition_generation > 0 &&
                canonical_digest(dynamic.definition_digest) &&
                canonical_id(dynamic.operation.view()) &&
                dynamic.grant_epoch > 0,
            "invalid dynamic audit identity");
  }
  if (draft.dynamic_attempt.has_value()) {
    require(!draft.operation.has_value() && !draft.capability.has_value() &&
                !draft.dynamic_operation.has_value() &&
                canonical_digest(draft.dynamic_attempt->opaque_digest),
            "invalid dynamic audit attempt identity");
  }
  switch (draft.event) {
  case AuditEvent::grant_changed:
    require(draft.capability.has_value() && !draft.operation.has_value() &&
                !draft.dynamic_operation.has_value() &&
                !draft.dynamic_attempt.has_value(),
            "grant audit event has invalid fields");
    break;
  case AuditEvent::capability_revoked:
    require((((draft.capability.has_value() && !draft.operation.has_value()) !=
              draft.dynamic_operation.has_value())) &&
                !draft.dynamic_attempt.has_value() && draft.correlation == 0,
            "revocation audit event has invalid fields");
    break;
  case AuditEvent::operation_decided:
  case AuditEvent::operation_completed:
  case AuditEvent::handle_issued:
  case AuditEvent::handle_denied:
    require(
        static_cast<unsigned>(draft.operation.has_value() &&
                              draft.capability.has_value()) +
                    static_cast<unsigned>(draft.dynamic_operation.has_value()) +
                    static_cast<unsigned>(draft.dynamic_attempt.has_value()) ==
                1 &&
            draft.correlation > 0,
        "operation audit event has invalid fields");
    break;
  case AuditEvent::worker_started:
  case AuditEvent::worker_health:
  case AuditEvent::worker_crashed:
  case AuditEvent::worker_stopped:
  case AuditEvent::worker_disabled:
    require(!draft.operation.has_value() && !draft.capability.has_value() &&
                !draft.dynamic_operation.has_value() &&
                !draft.dynamic_attempt.has_value() && draft.correlation == 0,
            "worker audit event has invalid fields");
    break;
  }
  FixedSet<AuditMetric, 8> metrics;
  for (const auto &metadata : draft.metadata.values()) {
    require(
        static_cast<std::uint8_t>(metadata.metric) <=
                static_cast<std::uint8_t>(AuditMetric::retry_after_seconds) &&
            metadata.value >= 0,
        "invalid audit metric");
    require(metrics.insert(metadata.metric), "duplicate audit metric");
  }
}

std::string audit_record_fingerprint(const AuditRecord &record) {
  require(record.sequence > 0 && canonical_id(record.plugin.view()) &&
              canonical_digest(record.revision),
          "invalid audit record identity");
  require(valid_audit_producer(record.producer), "invalid audit producer");
  validate_audit_draft(record);
  std::string bytes = domain("OMARCHY-PLUGIN-AUDIT-V1\0");
  append_u64(bytes, record.sequence);
  append_u64(bytes, record.wall_seconds);
  append_u64(bytes, record.monotonic_ns);
  append_u8(bytes, static_cast<std::uint8_t>(record.producer));
  append_u8(bytes, static_cast<std::uint8_t>(record.event));
  append_u8(bytes, static_cast<std::uint8_t>(record.outcome));
  append_text(bytes, record.plugin.view());
  append_text(bytes, record.revision.view());
  append_u64(bytes, record.generation);
  append_u64(bytes, record.correlation);
  append_u16(bytes, record.operation.has_value()
                        ? static_cast<std::uint16_t>(*record.operation)
                        : 0);
  if (record.capability.has_value()) {
    append_text(bytes, record.capability->id.view());
    append_u16(bytes, record.capability->version);
  } else {
    append_text(bytes, "-");
    append_u16(bytes, 0);
  }
  if (record.dynamic_operation.has_value()) {
    append_text(bytes, record.dynamic_operation->capability.view());
    append_u32(bytes, record.dynamic_operation->definition_generation);
    append_text(bytes, record.dynamic_operation->definition_digest.view());
    append_text(bytes, record.dynamic_operation->operation.view());
    append_u64(bytes, record.dynamic_operation->grant_epoch);
  }
  if (record.dynamic_attempt.has_value())
    append_text(bytes, record.dynamic_attempt->opaque_digest.view());
  append_u8(bytes, static_cast<std::uint8_t>(record.decision));
  append_u8(bytes, static_cast<std::uint8_t>(record.metadata.size()));
  for (std::uint8_t value = 0;
       value <= static_cast<std::uint8_t>(AuditMetric::retry_after_seconds);
       ++value) {
    const auto metric = static_cast<AuditMetric>(value);
    const auto found = std::find_if(
        record.metadata.values().begin(), record.metadata.values().end(),
        [metric](const AuditMetadata &item) { return item.metric == metric; });
    if (found == record.metadata.values().end())
      continue;
    append_u8(bytes, value);
    append_u64(bytes, std::bit_cast<std::uint64_t>(found->value));
  }
  return fingerprint(std::move(bytes));
}

} // namespace omarchy::plugins::permissions
