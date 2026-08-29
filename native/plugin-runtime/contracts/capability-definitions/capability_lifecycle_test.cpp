#include "capability_lifecycle.hpp"

#include <array>
#include <stdexcept>
#include <string>

namespace {
using namespace omarchy::plugins::definitions;
namespace permissions = omarchy::plugins::permissions;
void require(bool value, std::string_view message) {
  if (!value) throw std::runtime_error(std::string(message));
}
Digest digest(char value) { return Digest(std::string(64, value)); }
CapabilityDefinition fixture() {
  CapabilityDefinition value{
      .canonical_name = Name("local.my-harness"),
      .authority_identity = Name("local.my-harness-v1"),
      .enforcement_family = EnforcementFamily::cli_harness,
      .display_category_id = Name("local.automation"),
      .display_category_label = Label("Local automation"),
      .scope_schema = ScopeSchema::exact_cli_profile,
      .title = Label("Use My Harness"),
      .risk_text = Label("Uses one bounded administrator-installed harness"),
      .risk = RiskLevel::high,
      .revocation = RevocationPolicy::cancel_inflight,
      .audit = {},
      .adapter = {.adapter_class = Name("fake-bounded-harness"),
                  .implementation_digest = digest('d'), .abi_version = 1},
      .operations = {}};
  value.operations.insert({.name = Name("status"), .label = Label("Read status")});
  return value;
}
} // namespace

void capability_lifecycle_tests() {
  TrustedDefinitionRegistry registry;
  auto definition = fixture();
  require(assess_definition_install(registry, definition, 1, {}).decision ==
              DefinitionChangeDecision::installable,
          "fresh administrator definition was not installable");
  require(registry.install(definition, DefinitionSource::local_admin, 1),
          "fixture definition failed to install");
  const auto installed = registry.find("local.my-harness");
  const std::array dependencies{DefinitionDependency{
      .plugin = permissions::PluginId("org.example.dashboard"),
      .revision = digest('a'),
      .reference = {.canonical_name = Name("local.my-harness"),
                    .definition_generation = 1,
                    .definition_digest = installed->digest},
      .required = true}};
  require(assess_definition_install(registry, definition, 1, dependencies).decision ==
              DefinitionChangeDecision::unchanged,
          "identical definition required review");
  auto upgraded = definition;
  upgraded.risk_text = Label("Changed authority description");
  const auto blocked = assess_definition_install(registry, upgraded, 2, dependencies);
  require(blocked.decision == DefinitionChangeDecision::blocked_by_dependents &&
              blocked.dependents.size() == 1,
          "definition upgrade did not list and block its dependent plugin");
  require(assess_definition_install(registry, upgraded, 2, {}).decision ==
              DefinitionChangeDecision::requires_plugin_review,
          "unreferenced replacement bypassed the review boundary");
  require(assess_definition_removal(registry, "local.my-harness", dependencies)
                  .decision == DefinitionChangeDecision::blocked_by_dependents,
          "definition removal ignored a pinned dependent");
  require(assess_definition_removal(registry, "local.my-harness", {})
                  .decision == DefinitionChangeDecision::installable,
          "unused definition could not be removed");
}
