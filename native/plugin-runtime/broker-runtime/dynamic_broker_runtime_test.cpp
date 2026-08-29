#include "dynamic_broker_runtime.hpp"

#include <array>
#include <stdexcept>

using namespace omarchy::plugin_runtime;
namespace definitions = omarchy::plugins::definitions;
namespace permissions = omarchy::plugins::permissions;
namespace broker = omarchy::plugin_runtime::broker;
namespace wire = omarchy::plugin::wire;

namespace {
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
      .adapter = {.binding = definition.adapter, .dispatch = echo},
      .scope_validator = {.compare = exact}}});
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
  auto wrong_binding = grant.binding; ++wrong_binding.generation;
  result = runtime.dispatch(packet, wrong_binding, output);
  require(result.outcome == definitions::DynamicDispatchResult::stale_activation,
          "unauthenticated activation reached adapter");
  auto revoked = grant; revoked.grant.state = permissions::GrantState::revoked; revoked.grant.epoch = 5;
  require(runtime.apply_reconstructed_update(revoked), "revoke update");
  result = runtime.dispatch(packet, grant.binding, output);
  require(result.outcome == definitions::DynamicDispatchResult::denied &&
              result.decision == definitions::DynamicDecision::revoked, "revoked dispatch");
}
