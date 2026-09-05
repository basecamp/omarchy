#include "capability_definition.hpp"

#include <array>
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

DynamicScopeRelation compare_scope(const CapabilityDefinition &,
                                   std::string_view candidate,
                                   std::string_view baseline, void *) noexcept {
  if (candidate == baseline) return DynamicScopeRelation::equal;
  if (candidate == "narrow" && baseline == "wide")
    return DynamicScopeRelation::narrower;
  if (candidate == "wide" && baseline == "narrow")
    return DynamicScopeRelation::expanded;
  return DynamicScopeRelation::incomparable;
}

CapabilityDefinition network_fetch() {
  CapabilityDefinition definition{
      .canonical_name = Name("network.fetch"),
      .authority_identity = Name("network.fetch.https-v1"),
      .enforcement_family = EnforcementFamily::network_fetch,
      .display_category_id = Name("developer.services"),
      .display_category_label = Label("Developer services"),
      .scope_schema = ScopeSchema::https_origins_and_methods,
      .title = Label("Fetch data from selected HTTPS origins"),
      .risk_text = Label("Sends bounded requests to explicitly selected origins and methods"),
      .risk = RiskLevel::high,
      .revocation = RevocationPolicy::cancel_inflight,
      .audit = {},
      .adapter = {.adapter_class = Name("bounded-https-fetch"),
                  .contract_digest = digest('a'),
                  .abi_version = 1},
      .operations = {},
  };
  definition.operations.insert({.name = Name("notifications.list"),
                                .label = Label("List notifications")});
  definition.operations.insert({.name = Name("notifications.mark-read"),
                                .label = Label("Mark a notification read"),
                                .mutating = true});
  return definition;
}

CapabilityDefinition open_uri() {
  CapabilityDefinition definition{
      .canonical_name = Name("external.open-uri.https"),
      .authority_identity = Name("external.open-uri.https-v1"),
      .enforcement_family = EnforcementFamily::external_open_uri,
      .display_category_id = Name("desktop.actions"),
      .display_category_label = Label("Desktop actions"),
      .scope_schema = ScopeSchema::https_origins_after_gesture,
      .title = Label("Open selected HTTPS sites"),
      .risk_text = Label("Opens a user-visible HTTPS address after one fresh gesture"),
      .risk = RiskLevel::moderate,
      .revocation = RevocationPolicy::deny_new,
      .audit = {},
      .adapter = {.adapter_class = Name("desktop-open-uri"),
                  .contract_digest = digest('b'),
                  .abi_version = 1},
      .operations = {},
  };
  definition.operations.insert({.name = Name("open"),
                                .label = Label("Open link"),
                                .mutating = true,
                                .requires_fresh_gesture = true});
  return definition;
}

} // namespace

void capability_definition_loader_tests();
void dynamic_activation_tests();
void permissions_extensibility_contract_tests();

int main() {
  TrustedDefinitionRegistry registry;
  const auto fetch_definition = network_fetch();
  require(registry.install(fetch_definition, DefinitionSource::omarchy_package, 4),
          "trusted network-fetch definition was rejected");
  require(registry.install(open_uri(), DefinitionSource::local_admin, 2),
          "trusted open-URI definition was rejected");
  require(registry.size() == 2, "registry count changed");

  const auto installed = registry.find("network.fetch");
  require(installed && installed->generation == 4 &&
              installed->definition->adapter.adapter_class.view() == "bounded-https-fetch",
          "installed adapter definition did not resolve");
  require(registry.resolve({.canonical_name = Name("network.fetch"),
                            .definition_generation = 4,
                            .definition_digest = installed->digest}).has_value(),
          "exact plugin capability reference did not resolve");
  require(!registry.resolve({.canonical_name = Name("network.fetch"),
                             .definition_generation = 3,
                             .definition_digest = installed->digest}).has_value(),
          "stale definition generation resolved");
  require(!registry.resolve({.canonical_name = Name("network.fetch"),
                             .definition_generation = 4,
                             .definition_digest = digest('f')}).has_value(),
          "wrong adapter-definition digest resolved");
  require(!registry.find("plugin.proposed-capability"),
          "unknown publisher-defined capability resolved");

  DynamicRequest request{
      .definition = {.canonical_name = Name("network.fetch"),
                     .definition_generation = 4,
                     .definition_digest = installed->digest},
      .operations = {},
      .scope = CanonicalScope("wide"),
      .required = true,
  };
  request.operations.insert(Name("notifications.list"));
  DynamicGrant grant{.definition = request.definition,
                     .operations = {},
                     .scope = CanonicalScope("narrow"),
                     .state = permissions::GrantState::granted,
                     .epoch = 9};
  grant.operations.insert(Name("notifications.list"));
  require(authorize_dynamic_operation(
              registry, request, grant, "notifications.list",
              "narrow", installed->definition->adapter,
              {.compare = compare_scope}, false).allowed(),
          "manifest reference did not reach its exact granted adapter operation");
  require(authorize_dynamic_operation(
              registry, request, grant, "notifications.mark-read",
              "narrow", installed->definition->adapter,
              {.compare = compare_scope}, false).decision ==
              DynamicDecision::operation_undeclared,
          "manifest gained an unrequested dynamic operation");
  auto revoked = grant;
  revoked.state = permissions::GrantState::revoked;
  require(authorize_dynamic_operation(
              registry, request, revoked, "notifications.list",
              "narrow", installed->definition->adapter,
              {.compare = compare_scope}, false).decision ==
              DynamicDecision::revoked,
          "revoked dynamic grant reached its adapter");
  auto substituted = installed->definition->adapter;
  substituted.contract_digest = digest('e');
  require(authorize_dynamic_operation(
              registry, request, grant, "notifications.list", "narrow",
              substituted, {.compare = compare_scope}, false).decision ==
              DynamicDecision::adapter_mismatch,
          "adapter substitution retained dynamic authority");
  require(authorize_dynamic_operation(
              registry, request, grant, "notifications.list", "wide",
              installed->definition->adapter, {.compare = compare_scope},
              false).decision == DynamicDecision::scope_expanded,
          "dynamic demand expanded its granted scope");

  const std::string dynamic_manifest =
      "{\"schemaVersion\":2,\"id\":\"org.example.dynamic\","
      "\"name\":\"Dynamic\",\"version\":\"1\","
      "\"runtime\":{\"apiVersion\":1,\"qml\":\"Main.qml\"},"
      "\"surfaces\":{},\"permissions\":{\"required\":[{"
      "\"capability\":\"network.fetch\",\"definitionGeneration\":4,"
      "\"definitionDigest\":\"" + std::string(installed->digest.view()) +
      "\",\"operations\":[\"notifications.list\"],"
      "\"origins\":[\"https://status.example.com\"],\"reason\":\"status\"}],"
      "\"optional\":[]}}";
  const auto parsed_manifest =
      omarchy::plugins::manifest::parse_manifest_v2(dynamic_manifest);
  const auto parsed_request =
      dynamic_request_from_manifest(parsed_manifest.requests.front(), registry);
  require(parsed_request && parsed_request->definition.definition_generation == 4 &&
              parsed_request->operations.contains(Name("notifications.list")),
          "schema-v2 dynamic reference did not resolve into activation request");
  auto untrusted_operation = parsed_manifest.requests.front();
  untrusted_operation.operations.push_back("admin");
  require(!dynamic_request_from_manifest(untrusted_operation, registry),
          "manifest requested an operation absent from its pinned definition");
  auto stale_manifest_reference = parsed_manifest.requests.front();
  ++stale_manifest_reference.definition_generation;
  require(!dynamic_request_from_manifest(stale_manifest_reference, registry),
          "manifest update retained a stale definition generation");

  auto alias = fetch_definition;
  alias.canonical_name = Name("internet.read-safe");
  require(!registry.install(alias, DefinitionSource::local_admin, 1),
          "alias laundered an existing authority identity");
  alias.authority_identity = Name("internet.read-safe-v1");
  require(!registry.install(alias, DefinitionSource::local_admin, 1),
          "duplicate adapter operation binding was laundered under an alias");

  auto dishonest_open = open_uri();
  dishonest_open.canonical_name = Name("external.open-uri.no-gesture");
  dishonest_open.authority_identity = Name("external.open-uri.no-gesture-v1");
  auto operation = *dishonest_open.operations.values().begin();
  dishonest_open.operations = {};
  operation.requires_fresh_gesture = false;
  dishonest_open.operations.insert(operation);
  require(!valid_definition(dishonest_open),
          "external URI definition removed the gesture rule");

  auto remote_read = fetch_definition;
  remote_read.enforcement_family = EnforcementFamily::remote_account_read;
  remote_read.scope_schema = ScopeSchema::selected_remote_account;
  require(valid_definition(remote_read),
          "remote-account read rejected its selected-account scope");
  remote_read.scope_schema = ScopeSchema::https_origins_and_methods;
  require(!valid_definition(remote_read),
          "remote-account read was mislabeled as network-fetch scope");

  auto device_observe = fetch_definition;
  device_observe.enforcement_family = EnforcementFamily::device_observe;
  device_observe.scope_schema = ScopeSchema::selected_device_fields;
  require(valid_definition(device_observe),
          "device observation rejected its selected-field scope");
  device_observe.scope_schema = ScopeSchema::selected_remote_account;
  require(!valid_definition(device_observe),
          "device observation accepted a remote-account scope");

  auto media = fetch_definition;
  media.enforcement_family = EnforcementFamily::media_play_stream;
  media.scope_schema = ScopeSchema::activation_source_handles_and_controls;
  require(valid_definition(media),
          "media playback rejected its activation-bound handle scope");
  media.scope_schema = ScopeSchema::https_origins_and_methods;
  require(!valid_definition(media),
          "media playback accepted an HTTPS stream-origin scope");

  const auto contract = semantic_contract_digest("request=a;response=b");
  require(contract == semantic_contract_digest("request=a;response=b") &&
              contract != semantic_contract_digest("request=a;response=c"),
          "semantic contract digest is not deterministic and content-bound");
  require(canonical_identifier(std::string(128, 'a')) &&
              !canonical_identifier(std::string(129, 'a')),
          "canonical identifier did not enforce its exact 128-byte bound");

  capability_definition_loader_tests();
  dynamic_activation_tests();
  permissions_extensibility_contract_tests();
  return 0;
}
