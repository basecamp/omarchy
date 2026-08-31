#include "capability_definition.hpp"

#include <stdexcept>
#include <string>

namespace {
using namespace omarchy::plugins::definitions;
namespace permissions = omarchy::plugins::permissions;

void require(bool condition, std::string_view message) {
  if (!condition)
    throw std::runtime_error(std::string(message));
}

Digest digest(char value) { return Digest(std::string(64, value)); }

DynamicScopeRelation exact_profile(const CapabilityDefinition &,
                                   std::string_view candidate,
                                   std::string_view baseline, void *) noexcept {
  return candidate == baseline ? DynamicScopeRelation::equal
                               : DynamicScopeRelation::expanded;
}

CapabilityDefinition bounded_harness() {
  CapabilityDefinition definition{
      .canonical_name = Name("bash.my-harness"),
      .authority_identity = Name("local.my-harness-v1"),
      .enforcement_family = EnforcementFamily::cli_harness,
      .display_category_id = Name("local.automation"),
      .display_category_label = Label("Local automation"),
      .scope_schema = ScopeSchema::exact_cli_profile,
      .title = Label("Use My Harness"),
      .risk_text = Label("Runs selected fake harness operations with bounded arguments"),
      .risk = RiskLevel::high,
      .revocation = RevocationPolicy::cancel_inflight,
      .audit = {},
      .adapter = {.adapter_class = Name("fake-bounded-harness"),
                  .contract_digest = digest('d'),
                  .abi_version = 1},
      .operations = {},
  };
  definition.operations.insert({.name = Name("status"),
                                .label = Label("Read harness status")});
  definition.operations.insert({.name = Name("drive"),
                                .label = Label("Drive the harness"),
                                .mutating = true,
                                .requires_fresh_gesture = true});
  return definition;
}
} // namespace

void permissions_extensibility_contract_tests() {
  TrustedDefinitionRegistry registry;

  // A plugin-authored name has no authority until a trusted administrator has
  // independently installed a definition and its reviewed adapter exists.
  require(!registry.find("bash.my-harness"),
          "an unknown plugin-declared name created authority");
  const auto unknown_manifest = omarchy::plugins::manifest::parse_manifest_v2(
      "{\"schemaVersion\":2,\"id\":\"org.example.proposal\","
      "\"name\":\"Proposal\",\"version\":\"1\",\"runtime\":{"
      "\"apiVersion\":1,\"qml\":\"Main.qml\"},\"surfaces\":{},"
      "\"permissions\":{\"required\":[],\"optional\":[{"
      "\"capability\":\"bash.my-harness\",\"definitionGeneration\":1,"
      "\"definitionDigest\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\","
      "\"operations\":[\"status\"],\"profile\":\"my-harness-v1\","
      "\"reason\":\"Show status when the administrator installs the integration\"}]}}"
  );
  require(!dynamic_request_from_manifest(unknown_manifest.requests.front(),
                                         registry),
          "a plugin manifest or bundled proposal self-installed a definition");
  const auto definition = bounded_harness();
  require(registry.install(definition, DefinitionSource::local_admin, 1),
          "the administrator-installed bounded definition was rejected");
  const auto installed = registry.find("bash.my-harness");
  require(installed.has_value(), "the administrator definition was not visible");

  DynamicRequest optional{
      .definition = {.canonical_name = Name("bash.my-harness"),
                     .definition_generation = 1,
                     .definition_digest = installed->digest},
      .operations = {},
      .scope = CanonicalScope("profile=my-harness-v1"),
      .required = false,
  };
  optional.operations.insert(Name("status"));
  DynamicGrant grant{.definition = optional.definition,
                     .operations = {},
                     .scope = optional.scope,
                     .state = permissions::GrantState::denied,
                     .epoch = 1};
  grant.operations.insert(Name("status"));
  const DynamicScopeValidator validator{.compare = exact_profile};

  const auto decide = [&](const DynamicRequest &request,
                          const DynamicGrant &candidate,
                          std::string_view operation,
                          std::string_view scope) {
    return authorize_dynamic_operation(registry, request, candidate, operation,
                                       scope, definition.adapter, validator,
                                       false)
        .decision;
  };

  // This is the same host-derived state QML uses to hide/disable an optional
  // feature. It is deliberately not an authorization token.
  require(decide(optional, grant, "status", optional.scope.view()) ==
              DynamicDecision::denied,
          "a denied optional permission became available");
  grant.state = permissions::GrantState::granted;
  ++grant.epoch;
  require(decide(optional, grant, "status", optional.scope.view()) ==
              DynamicDecision::allowed,
          "a runtime grant did not enable the declared optional operation");
  grant.state = permissions::GrantState::revoked;
  ++grant.epoch;
  require(decide(optional, grant, "status", optional.scope.view()) ==
              DynamicDecision::revoked,
          "runtime revocation did not remove optional authority");

  auto operation_expansion = optional;
  operation_expansion.operations.insert(Name("drive"));
  grant.state = permissions::GrantState::granted;
  require(decide(operation_expansion, grant, "drive",
                 operation_expansion.scope.view()) ==
              DynamicDecision::operation_ungranted,
          "a manifest operation expansion inherited an old grant");
  auto scope_expansion = grant;
  scope_expansion.state = permissions::GrantState::granted;
  scope_expansion.scope = CanonicalScope("profile=anything");
  require(decide(optional, scope_expansion, "status", optional.scope.view()) ==
              DynamicDecision::scope_expanded,
          "a changed custom profile inherited an old grant");

  auto required = optional;
  required.required = true;
  grant.state = permissions::GrantState::revoked;
  require(decide(required, grant, "status", required.scope.view()) ==
              DynamicDecision::revoked,
          "revoked required authority remained callable");

  // Definition upgrades are review boundaries too. A plugin cannot silently
  // follow generation 2 or a different adapter digest using its generation-1
  // manifest reference and grant.
  require(!registry.resolve({.canonical_name = Name("bash.my-harness"),
                             .definition_generation = 2,
                             .definition_digest = installed->digest}),
          "a definition generation expansion resolved without review");
  auto substituted = definition.adapter;
  substituted.contract_digest = digest('x');
  grant.state = permissions::GrantState::granted;
  require(authorize_dynamic_operation(
              registry, optional, grant, "status", optional.scope.view(),
              substituted, validator, false)
              .decision == DynamicDecision::adapter_mismatch,
          "a plugin-selected adapter escaped the trusted definition");
}
