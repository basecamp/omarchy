#include "dynamic_broker_runtime.hpp"

#include <array>
#include <filesystem>
#include <stdexcept>
#include <sys/stat.h>
#include <unistd.h>

using namespace omarchy::plugin_runtime;
namespace definitions = omarchy::plugins::definitions;
namespace permissions = omarchy::plugins::permissions;
namespace broker = omarchy::plugin_runtime::broker;
namespace wire = omarchy::plugin::wire;

namespace {
struct EffectContext { const char *make_audit_unsafe = nullptr; };
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
          void *opaque) noexcept {
  if (request.authorization.grant_epoch == 0 || response.size() < request.payload.size()) return false;
  const auto *context = static_cast<EffectContext *>(opaque);
  if (context != nullptr && context->make_audit_unsafe != nullptr)
    (void)chmod(context->make_audit_unsafe, 0750);
  std::ranges::copy(request.payload, response.begin()); written = request.payload.size(); return true;
}
}

int main() {
  std::array<char, 64> audit_template{};
  const auto prefix = std::string("/tmp/omarchy-dynamic-audit.XXXXXX");
  std::ranges::copy(prefix, audit_template.begin());
  const auto *audit_root = mkdtemp(audit_template.data());
  require(audit_root != nullptr, "audit temporary directory");
  struct Cleanup { std::filesystem::path path; ~Cleanup() { std::filesystem::remove_all(path); } } cleanup{audit_root};
  omarchy::plugins::audit::AuditStore audit(
      std::filesystem::path(audit_root) / "store", {});
  require(audit.recover().ok(), "audit recover");
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
  EffectContext effect;
  runtime::DynamicBrokerRuntime runtime(registry, {{.grant = grant,
      .adapter = {.binding = definition.adapter, .dispatch = echo, .context = &effect},
      .scope_validator = {.compare = exact}}}, audit);
  const std::array payload{std::byte{7}};
  definitions::DynamicInvocation invocation{.definition = grant.request.definition,
      .operation = definitions::Name("echo"), .demand_scope = definitions::CanonicalScope("exact"),
      .payload = payload};
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
  const auto failure_root = std::filesystem::path(audit_root) / "failure-store";
  omarchy::plugins::audit::AuditStore failure_audit(failure_root, {});
  require(failure_audit.recover().ok(), "failure audit recover");
  EffectContext failing_effect{.make_audit_unsafe = failure_root.c_str()};
  runtime::DynamicBrokerRuntime failing_runtime(registry, {{.grant = grant,
      .adapter = {.binding = definition.adapter, .dispatch = echo,
                  .context = &failing_effect},
      .scope_validator = {.compare = exact}}}, failure_audit);
  packet.header.correlation_id = 100;
  result = failing_runtime.dispatch(packet, grant.binding, output);
  require(result.outcome == definitions::DynamicDispatchResult::adapter_failed,
          "terminal audit failure was not fail-stop");
  packet.header.correlation_id = 101;
  require(failing_runtime.dispatch(packet, grant.binding, output).outcome ==
              definitions::DynamicDispatchResult::malformed,
          "runtime continued after terminal audit failure");
  (void)chmod(failure_root.c_str(), 0700);
}
