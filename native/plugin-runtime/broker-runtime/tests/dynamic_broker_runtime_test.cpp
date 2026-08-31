#include "broker_runtime.hpp"
#include "dynamic_broker_runtime.hpp"

#include <array>
#include <memory>
#include <stdexcept>
#include <vector>

using namespace omarchy::plugin_runtime;
namespace definitions = omarchy::plugins::definitions;
namespace permissions = omarchy::plugins::permissions;
namespace broker = omarchy::plugin_runtime::broker;
namespace policy = omarchy::plugin_runtime::policy;
namespace providers = omarchy::plugin_runtime::providers;
namespace wire = omarchy::plugin::wire;

namespace {
struct FakeGestureClock final : runtime::DynamicGestureClock {
  std::uint64_t now = 100;
  std::uint64_t now_nanoseconds() const override { return now; }
};
struct RejectingAuditSink final : omarchy::plugins::audit::AuditSink {
  omarchy::plugins::audit::AppendResult
  append(permissions::AuditProducer, permissions::AuditDraft) override {
    return {{omarchy::plugins::audit::ErrorCode::invalid_argument,
             "injected audit rejection"},
            std::nullopt};
  }
};
struct RejectFirstRecordingAudit final : omarchy::plugins::audit::AuditSink {
  std::vector<permissions::AuditDraft> attempts;
  omarchy::plugins::audit::BoundedAuditLog backing;

  omarchy::plugins::audit::AppendResult
  append(permissions::AuditProducer producer,
         permissions::AuditDraft draft) override {
    attempts.push_back(draft);
    if (attempts.size() == 1)
      return {{omarchy::plugins::audit::ErrorCode::invalid_argument,
               "injected first audit rejection"},
              std::nullopt};
    return backing.append(producer, std::move(draft));
  }
};
void require(bool value, const char *message) {
  if (!value)
    throw std::runtime_error(message);
}
permissions::Digest digest(char value) {
  return permissions::Digest(std::string(64, value));
}
definitions::DynamicScopeRelation
exact(const definitions::CapabilityDefinition &, std::string_view a,
      std::string_view b, void *) noexcept {
  return a == b ? definitions::DynamicScopeRelation::equal
                : definitions::DynamicScopeRelation::incomparable;
}
bool echo(const definitions::AuthorizedDynamicRequest &request,
          std::span<std::byte> response, std::size_t &written,
          void *) noexcept {
  if (request.authorization.grant_epoch == 0 ||
      response.size() < request.payload.size())
    return false;
  std::ranges::copy(request.payload, response.begin());
  written = request.payload.size();
  return true;
}
runtime::DynamicRoute route_for(const definitions::DynamicRevisionGrant &grant,
                                const definitions::AdapterBinding &adapter) {
  return {.grant = grant,
          .adapter = {.binding = adapter, .dispatch = echo, .context = nullptr},
          .scope_validator = {.compare = exact}};
}
std::size_t encode_invocation(const definitions::DynamicInvocation &invocation,
                              std::span<std::byte> output) {
  std::size_t written = 0;
  require(definitions::encode_dynamic_invocation(invocation, output, written),
          "dynamic invocation encode");
  return written;
}
void put16(std::vector<std::byte> &bytes, std::size_t offset,
           std::uint16_t value) {
  bytes[offset] = static_cast<std::byte>(value >> 8U);
  bytes[offset + 1] = static_cast<std::byte>(value);
}
void put32(std::vector<std::byte> &bytes, std::size_t offset,
           std::uint32_t value) {
  for (std::size_t index = 0; index < 4; ++index)
    bytes[offset + index] =
        static_cast<std::byte>(value >> ((3U - index) * 8U));
}
void put64(std::vector<std::byte> &bytes, std::size_t offset,
           std::uint64_t value) {
  for (std::size_t index = 0; index < 8; ++index)
    bytes[offset + index] =
        static_cast<std::byte>(value >> ((7U - index) * 8U));
}
std::vector<std::byte> quota_request(permissions::OperationId operation,
                                     std::uint64_t total, std::uint64_t item) {
  std::vector<std::byte> bytes(24);
  put16(bytes, 0, static_cast<std::uint16_t>(operation));
  put16(bytes, 2, 16);
  put32(bytes, 4, 0);
  put64(bytes, 8, total);
  put64(bytes, 16, item);
  return bytes;
}
} // namespace

int main() {
  auto gesture_clock = std::make_shared<FakeGestureClock>();
  runtime::DynamicGestureLatch gesture_latch(gesture_clock);
  const permissions::ActivationBinding gesture_binding{
      .plugin = permissions::PluginId("fixture.gesture"),
      .revision = digest('1'),
      .policy_fingerprint = digest('2'),
      .generation = 7};
  const definitions::DynamicInvocation::GestureClaim gesture_claim{
      .surface_id = 3, .surface_generation = 7, .input_sequence = 11};
  require(gesture_latch.arm(gesture_binding, gesture_claim), "gesture arm");
  auto other_plugin = gesture_binding;
  other_plugin.plugin = permissions::PluginId("fixture.other");
  require(!gesture_latch.consume(other_plugin, gesture_claim),
          "cross-plugin gesture accepted");
  require(!gesture_latch.consume(gesture_binding, gesture_claim),
          "cross-plugin probe retained gesture eligibility");
  require(gesture_latch.arm(gesture_binding, gesture_claim), "gesture rearm");
  auto other_surface = gesture_claim;
  ++other_surface.surface_id;
  require(!gesture_latch.consume(gesture_binding, other_surface),
          "cross-surface gesture accepted");
  require(!gesture_latch.consume(gesture_binding, gesture_claim),
          "cross-surface probe retained gesture eligibility");
  require(gesture_latch.arm(gesture_binding, gesture_claim), "gesture rearm");
  require(gesture_latch.consume(gesture_binding, gesture_claim).has_value(),
          "exact gesture rejected");
  require(!gesture_latch.consume(gesture_binding, gesture_claim),
          "gesture replay accepted");
  require(gesture_latch.arm(gesture_binding, gesture_claim), "gesture rearm");
  gesture_clock->now += 5'000'000'001ULL;
  require(!gesture_latch.consume(gesture_binding, gesture_claim),
          "expired gesture accepted");
  auto stale_sequence = gesture_claim;
  --stale_sequence.input_sequence;
  gesture_clock->now = 200;
  require(gesture_latch.arm(gesture_binding, gesture_claim) &&
              !gesture_latch.arm(gesture_binding, stale_sequence),
          "non-monotonic gesture sequence accepted");
  gesture_latch.clear();
  omarchy::plugins::audit::BoundedAuditLog audit;
  omarchy::plugins::audit::BoundedAuditLog builtin_audit;
  policy::GrantSnapshot snapshot;
  snapshot.binding = {.plugin = permissions::PluginId("fixture.builtin"),
                      .revision = digest('3'),
                      .policy_fingerprint = digest('4'),
                      .generation = 9};
  const permissions::CapabilityKey storage{
      permissions::CapabilityId("storage.private"), 1};
  const permissions::QuotaScope storage_scope{4096, 1024};
  snapshot.requests.push_back(
      {.capability = storage, .scope = storage_scope, .required = true});
  snapshot.binding.policy_fingerprint = permissions::Digest(
      permissions::policy_request_fingerprint(snapshot.requests));
  snapshot.grants.push_back({.capability = storage,
                             .scope = storage_scope,
                             .state = permissions::GrantState::granted,
                             .epoch = 4});
  runtime::AuditedBrokerRuntime builtin_runtime(
      snapshot, providers::ProviderConfiguration{}, builtin_audit);
  const auto builtin_payload =
      quota_request(permissions::OperationId::storage_read,
                    storage_scope.total_bytes, storage_scope.item_bytes);
  wire::PacketView builtin_packet{
      .header = {.endpoint_role = wire::EndpointRole::broker,
                 .message_type = static_cast<std::uint16_t>(
                     permissions::OperationId::storage_read),
                 .role_protocol_version = broker::kBrokerRoleVersion,
                 .payload_length =
                     static_cast<std::uint32_t>(builtin_payload.size()),
                 .launch_generation = snapshot.binding.generation,
                 .correlation_id = 1},
      .payload = builtin_payload};
  std::array<std::byte, 8> builtin_output{};
  const auto unavailable =
      builtin_runtime.dispatch(builtin_packet, 100, builtin_output);
  require(unavailable.outcome == broker::DispatchOutcome::provider_failed,
          "built-in failed provider did not preserve a terminal reply");
  const auto error = broker::encode_broker_error(
      {.failed_operation = permissions::OperationId::storage_read,
       .reason = broker::BrokerErrorReason::provider_failed,
       .decision = permissions::GrantDecisionCode::allowed});
  const wire::PacketView cancel{
      .header = {.endpoint_role = wire::EndpointRole::broker,
                 .message_type = static_cast<std::uint16_t>(
                     wire::CommonMessageType::cancel),
                 .role_protocol_version = broker::kBrokerRoleVersion,
                 .payload_length = 0,
                 .launch_generation = snapshot.binding.generation,
                 .correlation_id = 1},
      .payload = {}};
  require(builtin_runtime.accept_cancel(cancel) ==
              broker::CancelResult::unsupported,
          "built-in cancellation fixture was not retained");
  const wire::PacketView terminal{
      .header = {.endpoint_role = wire::EndpointRole::broker,
                 .message_type = static_cast<std::uint16_t>(
                     wire::CommonMessageType::typed_error),
                 .role_protocol_version = broker::kBrokerRoleVersion,
                 .payload_length = static_cast<std::uint32_t>(error.size()),
                 .launch_generation = snapshot.binding.generation,
                 .correlation_id = 1},
      .payload = error};
  require(builtin_runtime.accept_terminal(terminal) ==
              broker::TerminalResult::accepted,
          "built-in terminal result was rejected");
  const auto builtin_operation_records = builtin_audit.query({});
  require(builtin_operation_records.records.size() == 2 &&
              builtin_operation_records.records[0].event ==
                  permissions::AuditEvent::operation_decided &&
              builtin_operation_records.records[1].event ==
                  permissions::AuditEvent::operation_completed,
          "built-in operation did not audit exactly decided then completed");
  require(builtin_runtime.accept_terminal(terminal) !=
              broker::TerminalResult::accepted,
          "duplicate built-in terminal was accepted");
  const auto after_duplicate_terminal = builtin_audit.query({});
  require(after_duplicate_terminal.records.size() == 2,
          "duplicate terminal emitted a second operation completion");

  RejectFirstRecordingAudit rejected_decision_audit;
  runtime::AuditedBrokerRuntime rejected_decision_runtime(
      snapshot, providers::ProviderConfiguration{}, rejected_decision_audit);
  require(
      rejected_decision_runtime.dispatch(builtin_packet, 100, builtin_output)
              .outcome == broker::DispatchOutcome::core_failed,
      "rejected decision audit did not fail stop dispatch");
  (void)rejected_decision_runtime.shutdown();
  require(rejected_decision_audit.attempts.size() == 1 &&
              rejected_decision_audit.attempts[0].event ==
                  permissions::AuditEvent::operation_decided,
          "failed decision audit left an orphan completion for shutdown");

  omarchy::plugins::audit::BoundedAuditLog revocation_audit;
  runtime::AuditedBrokerRuntime revocation_runtime(
      snapshot, providers::ProviderConfiguration{}, revocation_audit);
  const policy::Revocation revoke{
      .sequence = 1,
      .slot = policy::RevisionSlot::active,
      .grant = {.capability = storage,
                .scope = storage_scope,
                .state = permissions::GrantState::revoked,
                .epoch = 5},
      .action = permissions::RevocationMode::cancel_inflight,
      .fingerprint = "fixture"};
  require(revocation_runtime.apply_revocation(revoke).status ==
              runtime::RuntimeStatus::accepted,
          "active snapshot revocation rejected");
  require(revocation_runtime.revision().grants[0].state ==
                  permissions::GrantState::revoked &&
              revocation_runtime.revision().grants[0].epoch == 5,
          "revocation did not replace the immutable activation snapshot");
  require(revocation_runtime.apply_revocation(revoke).status ==
              runtime::RuntimeStatus::binding_mismatch,
          "replayed revocation accepted");
  const auto builtin_records = revocation_audit.query({});
  require(!builtin_records.records.empty() &&
              builtin_records.records.back().event ==
                  permissions::AuditEvent::capability_revoked,
          "built-in revocation was not audited before publication");

  definitions::CapabilityDefinition definition{
      .canonical_name = definitions::Name("fixture.echo"),
      .authority_identity = definitions::Name("fixture.echo-v1"),
      .enforcement_family = definitions::EnforcementFamily::network_fetch,
      .display_category_id = definitions::Name("fixture"),
      .display_category_label = definitions::Label("Fixture"),
      .scope_schema = definitions::ScopeSchema::https_origins_and_methods,
      .title = definitions::Label("Echo"),
      .risk_text = definitions::Label("Echo bounded bytes"),
      .risk = definitions::RiskLevel::low,
      .revocation = definitions::RevocationPolicy::restart_worker,
      .audit = {},
      .adapter = {.adapter_class = definitions::Name("fixture-adapter"),
                  .contract_digest = digest('a'),
                  .abi_version = 1},
      .operations = {}};
  definition.operations.insert(
      {.name = definitions::Name("echo"), .label = definitions::Label("Echo")});
  definitions::TrustedDefinitionRegistry registry;
  require(registry.install(definition,
                           definitions::DefinitionSource::omarchy_package, 1),
          "install");
  const auto resolved = registry.find("fixture.echo");
  require(resolved.has_value(), "resolve");
  definitions::DynamicRevisionGrant grant{
      .binding = {.plugin = permissions::PluginId("fixture.plugin"),
                  .revision = digest('b'),
                  .policy_fingerprint = digest('c'),
                  .generation = 2},
      .request = {.definition = {.canonical_name =
                                     definitions::Name("fixture.echo"),
                                 .definition_generation = 1,
                                 .definition_digest = resolved->digest},
                  .operations = {},
                  .scope = definitions::CanonicalScope("exact"),
                  .required = true},
      .grant = {
          .definition = {.canonical_name = definitions::Name("fixture.echo"),
                         .definition_generation = 1,
                         .definition_digest = resolved->digest},
          .operations = {},
          .scope = definitions::CanonicalScope("exact"),
          .state = permissions::GrantState::granted,
          .epoch = 4}};
  grant.request.operations.insert(definitions::Name("echo"));
  grant.grant.operations.insert(definitions::Name("echo"));
  omarchy::plugins::audit::BoundedAuditLog empty_audit;
  runtime::DynamicBrokerRuntime empty_runtime(registry, {}, empty_audit);
  require(empty_runtime.empty() &&
              !empty_runtime.accepts_binding(grant.binding),
          "empty dynamic runtime claimed activation authority");
  auto empty_update = grant;
  empty_update.grant.state = permissions::GrantState::revoked;
  ++empty_update.grant.epoch;
  require(empty_runtime.apply_reconstructed_revocation(empty_update).status ==
              runtime::DynamicRevocationStatus::binding_mismatch,
          "empty dynamic runtime accepted a reconstructed update");
  const auto route = route_for(grant, definition.adapter);
  runtime::DynamicBrokerRuntime runtime(registry, {route}, audit);
  require(runtime.accepts_binding(grant.binding),
          "dynamic runtime rejected its exact binding");
  auto other_binding = grant.binding;
  ++other_binding.generation;
  require(!runtime.accepts_binding(other_binding),
          "dynamic runtime accepted a foreign binding");
  bool rejected_duplicate = false;
  try {
    runtime::DynamicBrokerRuntime duplicate(registry, {route, route}, audit);
    (void)duplicate;
  } catch (...) {
    rejected_duplicate = true;
  }
  require(rejected_duplicate, "duplicate exact dynamic route was accepted");
  bool rejected_mixed = false;
  try {
    auto foreign_grant = grant;
    ++foreign_grant.binding.generation;
    runtime::DynamicBrokerRuntime mixed(
        registry, {route, route_for(foreign_grant, definition.adapter)}, audit);
    (void)mixed;
  } catch (...) {
    rejected_mixed = true;
  }
  require(rejected_mixed, "mixed dynamic activation bindings were accepted");
  const std::array payload{std::byte{7}};
  definitions::DynamicInvocation invocation{
      .definition = grant.request.definition,
      .operation = definitions::Name("echo"),
      .demand_scope = definitions::CanonicalScope("exact"),
      .gesture = {},
      .payload = payload};
  std::array<std::byte, definitions::kMaximumDynamicEnvelopeBytes> encoded{};
  std::size_t size = encode_invocation(invocation, encoded);
  wire::PacketView packet{
      .header = {.endpoint_role = wire::EndpointRole::broker,
                 .message_type = broker::kDynamicInvokeMessage,
                 .role_protocol_version = broker::kBrokerRoleVersion,
                 .payload_length = static_cast<std::uint32_t>(size),
                 .launch_generation = 2,
                 .correlation_id = 9},
      .payload = std::span(encoded).first(size)};
  std::array<std::byte, 8> output{};
  const auto empty_denial =
      empty_runtime.dispatch(packet, grant.binding, output);
  require(empty_denial.outcome == definitions::DynamicDispatchResult::denied &&
              empty_denial.decision ==
                  definitions::DynamicDecision::unknown_definition &&
              empty_audit.query({}).records.empty(),
          "empty dynamic runtime manufactured dispatch authority");
  auto result = runtime.dispatch(packet, grant.binding, output);
  require(result.outcome == definitions::DynamicDispatchResult::dispatched &&
              output[0] == std::byte{7},
          "dispatch");
  require(runtime.dispatch(packet, grant.binding, output).outcome ==
              definitions::DynamicDispatchResult::malformed,
          "correlation replay produced a second terminal decision");
  const auto first_audit = audit.query({});
  require(first_audit.records.size() == 2 &&
              first_audit.records[0].event ==
                  permissions::AuditEvent::operation_decided &&
              first_audit.records[1].event ==
                  permissions::AuditEvent::operation_completed,
          "dynamic dispatch did not produce decision then exactly one terminal "
          "audit");
  auto wrong_binding = grant.binding;
  ++wrong_binding.generation;
  packet.header.correlation_id = 10;
  result = runtime.dispatch(packet, wrong_binding, output);
  require(result.outcome == definitions::DynamicDispatchResult::denied,
          "unauthenticated activation reached adapter");
  auto unknown_invocation = invocation;
  unknown_invocation.definition.canonical_name =
      definitions::Name("plugin.supplied-name");
  unknown_invocation.definition.definition_digest = digest('f');
  size = encode_invocation(unknown_invocation, encoded);
  packet.payload = std::span(encoded).first(size);
  packet.header.payload_length = static_cast<std::uint32_t>(size);
  packet.header.correlation_id = 11;
  const auto unknown = runtime.dispatch(packet, grant.binding, output);
  require(unknown.outcome == definitions::DynamicDispatchResult::denied &&
              unknown.decision ==
                  definitions::DynamicDecision::unknown_definition,
          "unknown dynamic definition did not fail closed");
  const auto unknown_audit = audit.query({});
  require(unknown_audit.records.size() >= 2 &&
              !unknown_audit.records[unknown_audit.records.size() - 2]
                   .dynamic_operation &&
              unknown_audit.records[unknown_audit.records.size() - 2]
                  .dynamic_attempt &&
              unknown_audit.records.back().dynamic_attempt &&
              unknown_audit.records[unknown_audit.records.size() - 2].event ==
                  permissions::AuditEvent::operation_decided &&
              unknown_audit.records.back().event ==
                  permissions::AuditEvent::operation_completed,
          "unknown dynamic denial exposed a spoofable audit identity");
  auto unknown_operation = invocation;
  unknown_operation.operation = definitions::Name("plugin.spoofed-operation");
  size = encode_invocation(unknown_operation, encoded);
  packet.payload = std::span(encoded).first(size);
  packet.header.payload_length = static_cast<std::uint32_t>(size);
  packet.header.correlation_id = 12;
  const auto operation_denial = runtime.dispatch(packet, grant.binding, output);
  const auto operation_audit = audit.query({});
  require(operation_denial.outcome ==
                  definitions::DynamicDispatchResult::denied &&
              operation_denial.decision ==
                  definitions::DynamicDecision::operation_undeclared &&
              operation_audit.records.size() >= 2 &&
              !operation_audit.records[operation_audit.records.size() - 2]
                   .dynamic_operation &&
              operation_audit.records[operation_audit.records.size() - 2]
                  .dynamic_attempt &&
              operation_audit.records.back().dynamic_attempt,
          "unresolved operation was promoted into trusted audit identity");
  size = encode_invocation(invocation, encoded);
  packet.payload = std::span(encoded).first(size);
  packet.header.payload_length = static_cast<std::uint32_t>(size);
  auto revoked = grant;
  revoked.grant.state = permissions::GrantState::revoked;
  revoked.grant.epoch = 5;
  const auto typed_revocation = runtime.apply_reconstructed_revocation(revoked);
  require(typed_revocation.status ==
                  runtime::DynamicRevocationStatus::accepted &&
              typed_revocation.restart_worker,
          "typed dynamic revocation lost restart-worker policy");
  const auto revoke_audit = audit.query({});
  require(!revoke_audit.records.empty() &&
              revoke_audit.records.back().event ==
                  permissions::AuditEvent::capability_revoked &&
              revoke_audit.records.back().dynamic_operation->grant_epoch == 5,
          "dynamic revocation was not durable before publication");
  packet.header.correlation_id = 13;
  result = runtime.dispatch(packet, grant.binding, output);
  require(result.outcome == definitions::DynamicDispatchResult::denied &&
              result.decision == definitions::DynamicDecision::revoked,
          "revoked dispatch");
  for (std::uint64_t correlation = 14; correlation < 80; ++correlation) {
    packet.header.correlation_id = correlation;
    require(runtime.dispatch(packet, grant.binding, output).outcome ==
                definitions::DynamicDispatchResult::denied,
            "monotonic dynamic dispatcher exhausted after a fixed call count");
  }
  RejectingAuditSink failure_audit;
  runtime::DynamicBrokerRuntime failing_runtime(registry, {route},
                                                failure_audit);
  packet.header.correlation_id = 100;
  result = failing_runtime.dispatch(packet, grant.binding, output);
  require(result.outcome == definitions::DynamicDispatchResult::adapter_failed,
          "terminal audit failure was not fail-stop");
  packet.header.correlation_id = 101;
  require(failing_runtime.dispatch(packet, grant.binding, output).outcome ==
              definitions::DynamicDispatchResult::malformed,
          "runtime continued after terminal audit failure");
}
