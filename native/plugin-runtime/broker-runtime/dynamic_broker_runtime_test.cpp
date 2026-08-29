#include "dynamic_broker_runtime.hpp"
#include "broker_runtime.hpp"

#include <array>
#include <stdexcept>

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
void require(bool value, const char *message) { if (!value) throw std::runtime_error(message); }
permissions::Digest digest(char value) { return permissions::Digest(std::string(64, value)); }
definitions::DynamicScopeRelation exact(const definitions::CapabilityDefinition &,
                                        std::string_view a, std::string_view b,
                                        void *) noexcept {
  return a == b ? definitions::DynamicScopeRelation::equal
                : definitions::DynamicScopeRelation::incomparable;
}
bool echo(const definitions::AuthorizedDynamicRequest &request,
          std::span<std::byte> response, std::size_t &written,
          void *) noexcept {
  if (request.authorization.grant_epoch == 0 || response.size() < request.payload.size()) return false;
  std::ranges::copy(request.payload, response.begin()); written = request.payload.size(); return true;
}
}

int main() {
  FakeGestureClock gesture_clock;
  runtime::DynamicGestureLatch gesture_latch(gesture_clock);
  const permissions::ActivationBinding gesture_binding{
      .plugin = permissions::PluginId("fixture.gesture"),
      .revision = digest('1'), .policy_fingerprint = digest('2'),
      .generation = 7};
  const definitions::DynamicInvocation::GestureClaim gesture_claim{
      .surface_id = 3, .surface_generation = 7, .input_sequence = 11};
  require(gesture_latch.arm(gesture_binding, gesture_claim), "gesture arm");
  auto other_plugin = gesture_binding;
  other_plugin.plugin = permissions::PluginId("fixture.other");
  require(!gesture_latch.consume(other_plugin, gesture_claim),
          "cross-plugin gesture accepted");
  auto other_surface = gesture_claim;
  ++other_surface.surface_id;
  require(!gesture_latch.consume(gesture_binding, other_surface),
          "cross-surface gesture accepted");
  require(gesture_latch.consume(gesture_binding, gesture_claim),
          "exact gesture rejected after spoof attempts");
  require(!gesture_latch.consume(gesture_binding, gesture_claim),
          "gesture replay accepted");
  require(gesture_latch.arm(gesture_binding, gesture_claim), "gesture rearm");
  gesture_clock.now += 5'000'000'001ULL;
  require(!gesture_latch.consume(gesture_binding, gesture_claim),
          "expired gesture accepted");
  auto stale_sequence = gesture_claim;
  --stale_sequence.input_sequence;
  gesture_clock.now = 200;
  require(gesture_latch.arm(gesture_binding, gesture_claim) &&
              !gesture_latch.arm(gesture_binding, stale_sequence),
          "non-monotonic gesture sequence accepted");
  gesture_latch.clear();
  omarchy::plugins::audit::BoundedAuditLog audit;
  omarchy::plugins::audit::BoundedAuditLog builtin_audit;
  policy::GrantSnapshot snapshot;
  snapshot.binding = {
      .plugin = permissions::PluginId("fixture.builtin"),
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
  snapshot.grants.push_back(
      {.capability = storage,
       .scope = storage_scope,
       .state = permissions::GrantState::granted,
       .epoch = 4});
  runtime::AuditedBrokerRuntime builtin_runtime(
      snapshot, providers::ProviderConfiguration{}, builtin_audit);
  const policy::Revocation revoke{
      .sequence = 1,
      .slot = policy::RevisionSlot::active,
      .grant = {.capability = storage,
                .scope = storage_scope,
                .state = permissions::GrantState::revoked,
                .epoch = 5},
      .action = permissions::RevocationMode::cancel_inflight,
      .fingerprint = "fixture"};
  require(builtin_runtime.apply_revocation(revoke).status ==
              runtime::RuntimeStatus::accepted,
          "active snapshot revocation rejected");
  require(builtin_runtime.revision().grants[0].state ==
                  permissions::GrantState::revoked &&
              builtin_runtime.revision().grants[0].epoch == 5,
          "revocation did not replace the immutable activation snapshot");
  require(builtin_runtime.apply_revocation(revoke).status ==
              runtime::RuntimeStatus::binding_mismatch,
          "replayed revocation accepted");
  const auto builtin_records = builtin_audit.query({});
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
      .title = definitions::Label("Echo"), .risk_text = definitions::Label("Echo bounded bytes"),
      .risk = definitions::RiskLevel::low,
      .revocation = definitions::RevocationPolicy::cancel_inflight,
      .audit = {},
      .adapter = {.adapter_class = definitions::Name("fixture-adapter"),
                  .implementation_digest = digest('a'), .abi_version = 1},
      .operations = {}};
  definition.operations.insert({.name = definitions::Name("echo"), .label = definitions::Label("Echo")});
  definitions::TrustedDefinitionRegistry registry;
  require(registry.install(definition, definitions::DefinitionSource::omarchy_package, 1), "install");
  const auto resolved = registry.find("fixture.echo"); require(resolved.has_value(), "resolve");
  definitions::DynamicRevisionGrant grant{
      .binding = {.plugin = permissions::PluginId("fixture.plugin"), .revision = digest('b'),
                  .policy_fingerprint = digest('c'), .generation = 2},
      .request = {.definition = {.canonical_name = definitions::Name("fixture.echo"),
                                 .definition_generation = 1, .definition_digest = resolved->digest},
                  .operations = {}, .scope = definitions::CanonicalScope("exact"), .required = true},
      .grant = {.definition = {.canonical_name = definitions::Name("fixture.echo"),
                               .definition_generation = 1, .definition_digest = resolved->digest},
                .operations = {},
                .scope = definitions::CanonicalScope("exact"),
                .state = permissions::GrantState::granted, .epoch = 4}};
  grant.request.operations.insert(definitions::Name("echo"));
  grant.grant.operations.insert(definitions::Name("echo"));
  runtime::DynamicBrokerRuntime runtime(registry, {{.grant = grant,
      .adapter = {.binding = definition.adapter, .dispatch = echo, .context = nullptr},
      .scope_validator = {.compare = exact}}}, audit);
  const std::array payload{std::byte{7}};
  definitions::DynamicInvocation invocation{.definition = grant.request.definition,
      .operation = definitions::Name("echo"), .demand_scope = definitions::CanonicalScope("exact"),
                                            .gesture = {}, .payload = payload};
  std::array<std::byte, definitions::kMaximumDynamicEnvelopeBytes> encoded{};
  std::size_t size = 0; require(definitions::encode_dynamic_invocation(invocation, encoded, size), "encode");
  wire::PacketView packet{.header = {.endpoint_role = wire::EndpointRole::broker,
      .message_type = broker::kDynamicInvokeMessage, .role_protocol_version = broker::kBrokerRoleVersion,
      .payload_length = static_cast<std::uint32_t>(size), .launch_generation = 2, .correlation_id = 9},
      .payload = std::span(encoded).first(size)};
  std::array<std::byte, 8> output{};
  auto result = runtime.dispatch(packet, grant.binding, output);
  require(result.outcome == definitions::DynamicDispatchResult::dispatched && output[0] == std::byte{7}, "dispatch");
  require(runtime.dispatch(packet, grant.binding, output).outcome ==
              definitions::DynamicDispatchResult::malformed,
          "correlation replay produced a second terminal decision");
  const auto first_audit = audit.query({});
  require(first_audit.records.size() == 2 &&
              first_audit.records[0].event == permissions::AuditEvent::operation_decided &&
              first_audit.records[1].event == permissions::AuditEvent::operation_completed,
          "dynamic dispatch did not produce decision then exactly one terminal audit");
  auto wrong_binding = grant.binding; ++wrong_binding.generation;
  packet.header.correlation_id = 10;
  result = runtime.dispatch(packet, wrong_binding, output);
  require(result.outcome == definitions::DynamicDispatchResult::denied,
          "unauthenticated activation reached adapter");
  auto revoked = grant; revoked.grant.state = permissions::GrantState::revoked; revoked.grant.epoch = 5;
  require(runtime.apply_reconstructed_update(revoked), "revoke update");
  const auto revoke_audit = audit.query({});
  require(!revoke_audit.records.empty() &&
              revoke_audit.records.back().event ==
                  permissions::AuditEvent::capability_revoked &&
              revoke_audit.records.back().dynamic_operation->grant_epoch == 5,
          "dynamic revocation was not durable before publication");
  packet.header.correlation_id = 11;
  result = runtime.dispatch(packet, grant.binding, output);
  require(result.outcome == definitions::DynamicDispatchResult::denied &&
              result.decision == definitions::DynamicDecision::revoked, "revoked dispatch");
  for (std::uint64_t correlation = 12; correlation < 80; ++correlation) {
    packet.header.correlation_id = correlation;
    require(runtime.dispatch(packet, grant.binding, output).outcome ==
                definitions::DynamicDispatchResult::denied,
            "monotonic dynamic dispatcher exhausted after a fixed call count");
  }
  RejectingAuditSink failure_audit;
  runtime::DynamicBrokerRuntime failing_runtime(registry, {{.grant = grant,
      .adapter = {.binding = definition.adapter, .dispatch = echo,
                  .context = nullptr},
      .scope_validator = {.compare = exact}}}, failure_audit);
  packet.header.correlation_id = 100;
  result = failing_runtime.dispatch(packet, grant.binding, output);
  require(result.outcome == definitions::DynamicDispatchResult::adapter_failed,
          "terminal audit failure was not fail-stop");
  packet.header.correlation_id = 101;
  require(failing_runtime.dispatch(packet, grant.binding, output).outcome ==
              definitions::DynamicDispatchResult::malformed,
          "runtime continued after terminal audit failure");
}
