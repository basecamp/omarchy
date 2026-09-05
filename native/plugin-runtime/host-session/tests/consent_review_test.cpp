#include "consent_review.hpp"

#include "manifest_contract.hpp"

#include <algorithm>
#include <array>
#include <fcntl.h>
#include <filesystem>
#include <iostream>
#include <stdexcept>
#include <sys/stat.h>
#include <unistd.h>

namespace host = omarchy::plugin_runtime::host_session;
namespace definitions = omarchy::plugins::definitions;
namespace manifest = omarchy::plugins::manifest;
namespace permissions = omarchy::plugins::permissions;

namespace {
constexpr std::string_view kPlugin = "org.example.consent";

void require(bool condition, std::string_view message) {
  if (!condition)
    throw std::runtime_error(std::string(message));
}

std::string hex(char value) { return std::string(64, value); }

definitions::DynamicScopeRelation
compare_dynamic(const definitions::CapabilityDefinition &,
                std::string_view candidate, std::string_view baseline,
                void *) noexcept {
  if (candidate == baseline)
    return definitions::DynamicScopeRelation::equal;
  if (candidate == "narrow" && baseline == "wide")
    return definitions::DynamicScopeRelation::narrower;
  if (candidate == "wide" && baseline == "narrow")
    return definitions::DynamicScopeRelation::expanded;
  return definitions::DynamicScopeRelation::incomparable;
}

definitions::CapabilityDefinition dynamic_definition(char provider) {
  definitions::CapabilityDefinition definition{
      .canonical_name = definitions::Name("service.demo"),
      .authority_identity = definitions::Name("service.demo.authority"),
      .enforcement_family = definitions::EnforcementFamily::network_fetch,
      .display_category_id = definitions::Name("developer.services"),
      .display_category_label = definitions::Label("Developer services"),
      .scope_schema = definitions::ScopeSchema::https_origins_and_methods,
      .title = definitions::Label("Fetch demo data"),
      .risk_text = definitions::Label("Uses a reviewed adapter"),
      .risk = definitions::RiskLevel::high,
      .revocation = definitions::RevocationPolicy::cancel_inflight,
      .audit = {},
      .adapter = {.adapter_class = definitions::Name("service.demo.adapter"),
                  .contract_digest = definitions::Digest(hex(provider)),
                  .abi_version = 1},
      .operations = {}};
  definition.operations.insert({.name = definitions::Name("read"),
                                .label = definitions::Label("Read demo data")});
  definition.operations.insert({.name = definitions::Name("write"),
                                .label = definitions::Label("Write demo data"),
                                .mutating = true});
  return definition;
}

struct Fixture {
  std::filesystem::path path;
  int root = -1;
  definitions::TrustedDefinitionRegistry definitions;
  std::unique_ptr<host::AuthorityStore> store;
  definitions::DynamicScopeValidator validator{.compare = compare_dynamic};

  Fixture() {
    std::string pattern =
        (std::filesystem::temp_directory_path() / "omarchy-consent-XXXXXX")
            .string();
    pattern.push_back('\0');
    require(::mkdtemp(pattern.data()) != nullptr, "mkdtemp failed");
    path = pattern.data();
    root = ::open(path.c_str(), O_RDONLY | O_DIRECTORY | O_CLOEXEC);
    require(root >= 0, "authority root open failed");
    store = host::AuthorityStore::open(root, ::getuid(),
                                       permissions::PluginId(kPlugin));
    require(store != nullptr, "authority store open failed");
  }

  ~Fixture() {
    store.reset();
    if (root >= 0)
      ::close(root);
    std::error_code ignored;
    std::filesystem::remove_all(path, ignored);
  }
};

manifest::CapabilityRequest builtin_request(bool required,
                                            std::string_view category) {
  return {.capability = "notifications.send",
          .reason = "Show status",
          .canonical_scope =
              "{\"categories\":[\"" + std::string(category) + "\"]}",
          .definition_generation = 0,
          .definition_digest = {},
          .operations = {},
          .required = required};
}

manifest::CapabilityRequest storage_request(bool required,
                                            std::uint64_t quota) {
  return {.capability = "storage.private",
          .reason = "Store plugin state",
          .canonical_scope = "{\"quotaBytes\":" + std::to_string(quota) + "}",
          .definition_generation = 0,
          .definition_digest = {},
          .operations = {},
          .required = required};
}

manifest::CapabilityRequest
dynamic_request(const Fixture &fixture, bool required,
                std::string scope = "wide",
                std::vector<std::string> operations = {"read"}) {
  const auto resolved = fixture.definitions.find("service.demo");
  require(resolved.has_value(), "dynamic definition missing");
  return {.capability = "service.demo",
          .reason = "Read demo status",
          .canonical_scope = std::move(scope),
          .definition_generation = resolved->generation,
          .definition_digest = std::string(resolved->digest.view()),
          .operations = std::move(operations),
          .required = required};
}

host::VerifiedRevision
verified(std::vector<manifest::CapabilityRequest> requests, char revision) {
  manifest::ManifestV2 model;
  model.id = kPlugin;
  model.requests = std::move(requests);
  const auto request_sha256 =
      manifest::requested_capability_fingerprint(model.requests);
  return {.manifest = std::move(model),
          .tree_sha256 = hex(revision),
          .request_sha256 = request_sha256};
}

host::BuiltinConsentDecision builtin_choice(const host::ConsentReview &review,
                                            permissions::UserDecision choice) {
  require(review.builtin_rows.size() == 1 &&
              review.builtin_rows.front().requested,
          "expected one built-in review row");
  const auto &request = *review.builtin_rows.front().requested;
  return {.capability = request.capability,
          .decided_scope = request.scope,
          .decision = choice};
}

host::DynamicConsentDecision dynamic_choice(const host::ConsentReview &review,
                                            permissions::UserDecision choice) {
  require(review.dynamic_rows.size() == 1 &&
              review.dynamic_rows.front().requested,
          "expected one dynamic review row");
  const auto &request = *review.dynamic_rows.front().requested;
  return {.definition = request.definition,
          .operations = request.operations,
          .decided_scope = request.scope,
          .decision = choice};
}

host::ConsentConfirmation
confirmation(const host::ConsentReview &review,
             std::span<const host::BuiltinConsentDecision> builtin,
             std::span<const host::DynamicConsentDecision> dynamic) {
  return {.review_fingerprint = review.fingerprint,
          .decision_fingerprint =
              host::consent_decision_fingerprint(review, builtin, dynamic),
          .actor = permissions::DecisionActor::trusted_ui,
          .confirmed_wall_seconds = 1};
}

void explicit_install_and_denial_guards() {
  Fixture fixture;
  auto candidate = verified({builtin_request(true, "status")}, 'a');
  auto review = host::prepare_consent_review(
      *fixture.store, candidate, fixture.definitions, fixture.validator);
  require(review && review->builtin_rows.size() == 1 &&
              review->builtin_rows[0].delta == host::ConsentDeltaKind::added,
          "install review did not show added permission");

  auto denied = builtin_choice(*review, permissions::UserDecision::deny);
  const std::array denied_choices{denied};
  auto denied_confirmation = confirmation(*review, denied_choices, {});
  require(host::publish_consent_review(
              *fixture.store, *review, denied_confirmation, denied_choices, {},
              fixture.definitions,
              fixture.validator) == host::ConsentResult::required_denied,
          "required denial did not fail explicitly");
  require(fixture.store->read_slots()->sequence == 0 &&
              !fixture.store->read_slots()->candidate,
          "required denial mutated authority");

  auto granted = builtin_choice(*review, permissions::UserDecision::grant);
  const std::array granted_choices{granted};
  auto granted_confirmation = confirmation(*review, granted_choices, {});
  auto spoofed_tree = *review;
  spoofed_tree.verified.tree_sha256 = hex('f');
  require(host::publish_consent_review(
              *fixture.store, spoofed_tree, granted_confirmation,
              granted_choices, {}, fixture.definitions,
              fixture.validator) == host::ConsentResult::invalid_review,
          "review mutation spoofed the verified tree identity");
  auto tampered = granted;
  tampered.decision = permissions::UserDecision::deny;
  const std::array tampered_choices{tampered};
  require(host::publish_consent_review(
              *fixture.store, *review, granted_confirmation, tampered_choices,
              {}, fixture.definitions,
              fixture.validator) == host::ConsentResult::invalid_review,
          "confirmation did not bind exact choices");
  require(host::publish_consent_review(
              *fixture.store, *review, granted_confirmation, granted_choices,
              {}, fixture.definitions,
              fixture.validator) == host::ConsentResult::applied,
          "explicit install consent did not publish");
  require(!host::prepare_consent_review(*fixture.store, candidate,
                                        fixture.definitions, fixture.validator),
          "pending candidate allowed a second review");
}

void optional_partial_spoof_and_invalid_enum() {
  Fixture fixture;
  auto candidate = verified({builtin_request(false, "status")}, 'b');
  auto review = host::prepare_consent_review(
      *fixture.store, candidate, fixture.definitions, fixture.validator);
  require(review.has_value(), "optional review failed");
  auto denied = builtin_choice(*review, permissions::UserDecision::deny);
  const std::array choices{denied};
  require(host::publish_consent_review(
              *fixture.store, *review, confirmation(*review, {}, {}), {}, {},
              fixture.definitions,
              fixture.validator) == host::ConsentResult::incomplete_decisions,
          "partial decision set was accepted");
  const std::array duplicates{denied, denied};
  require(host::publish_consent_review(
              *fixture.store, *review, confirmation(*review, duplicates, {}),
              duplicates, {}, fixture.definitions,
              fixture.validator) == host::ConsentResult::incomplete_decisions,
          "duplicate decision set was accepted");
  auto invalid = denied;
  invalid.decision = static_cast<permissions::UserDecision>(77);
  const std::array invalid_choices{invalid};
  require(host::publish_consent_review(
              *fixture.store, *review,
              confirmation(*review, invalid_choices, {}), invalid_choices, {},
              fixture.definitions,
              fixture.validator) == host::ConsentResult::spoofed_decision,
          "invalid decision enum was accepted");
  auto expanded = denied;
  auto scope = std::get<permissions::TokenScope>(expanded.decided_scope);
  scope.tokens.insert(permissions::ScopeToken("alerts"));
  expanded.decided_scope = std::move(scope);
  expanded.decision = permissions::UserDecision::grant;
  const std::array expanded_choices{expanded};
  require(host::publish_consent_review(
              *fixture.store, *review,
              confirmation(*review, expanded_choices, {}), expanded_choices, {},
              fixture.definitions,
              fixture.validator) == host::ConsentResult::spoofed_decision,
          "expanded built-in scope was accepted");
  require(host::publish_consent_review(
              *fixture.store, *review, confirmation(*review, choices, {}),
              choices, {}, fixture.definitions,
              fixture.validator) == host::ConsentResult::applied,
          "optional denial did not publish exact denied grant");
}

void dynamic_exactness_and_provider_identity() {
  Fixture fixture;
  require(fixture.definitions.install(
              dynamic_definition('d'),
              definitions::DefinitionSource::omarchy_package, 4),
          "dynamic definition install failed");
  auto candidate = verified({dynamic_request(fixture, false)}, 'c');
  auto review = host::prepare_consent_review(
      *fixture.store, candidate, fixture.definitions, fixture.validator);
  require(review && review->dynamic_rows.size() == 1 &&
              review->dynamic_rows[0].trusted_definition &&
              review->dynamic_rows[0]
                      .trusted_definition->adapter.contract_digest ==
                  definitions::Digest(hex('d')),
          "trusted provider identity was not reviewable");
  auto denied = dynamic_choice(*review, permissions::UserDecision::deny);
  denied.decided_scope = definitions::CanonicalScope("narrow");
  const std::array narrowed_denial{denied};
  require(host::publish_consent_review(
              *fixture.store, *review,
              confirmation(*review, {}, narrowed_denial), {}, narrowed_denial,
              fixture.definitions,
              fixture.validator) == host::ConsentResult::spoofed_decision,
          "dynamic denial narrowed authority silently");
  auto changed_operations =
      dynamic_choice(*review, permissions::UserDecision::deny);
  changed_operations.operations = {};
  const std::array changed_denial{changed_operations};
  require(host::publish_consent_review(
              *fixture.store, *review,
              confirmation(*review, {}, changed_denial), {}, changed_denial,
              fixture.definitions,
              fixture.validator) == host::ConsentResult::spoofed_decision,
          "dynamic denial changed operations silently");
  auto invalid = dynamic_choice(*review, permissions::UserDecision::deny);
  invalid.decision = static_cast<permissions::UserDecision>(88);
  const std::array invalid_choices{invalid};
  require(host::publish_consent_review(
              *fixture.store, *review,
              confirmation(*review, {}, invalid_choices), {}, invalid_choices,
              fixture.definitions,
              fixture.validator) == host::ConsentResult::spoofed_decision,
          "invalid dynamic decision enum was accepted");
  auto granted = dynamic_choice(*review, permissions::UserDecision::grant);
  granted.decided_scope = definitions::CanonicalScope("narrow");
  const std::array narrowed_grant{granted};
  require(host::publish_consent_review(
              *fixture.store, *review,
              confirmation(*review, {}, narrowed_grant), {}, narrowed_grant,
              fixture.definitions,
              fixture.validator) == host::ConsentResult::applied,
          "explicit narrowed dynamic grant did not publish");
  auto slots = fixture.store->read_slots();
  permissions::RequestSet no_builtin;
  permissions::ActivationBinding binding{
      .plugin = permissions::PluginId(kPlugin),
      .revision = permissions::Digest(hex('c')),
      .policy_fingerprint = permissions::Digest(
          permissions::policy_request_fingerprint(no_builtin)),
      .generation = 1};
  require(slots && fixture.store->promote_candidate(binding, slots->sequence) ==
                       host::AuthorityMutationResult::applied,
          "narrowed dynamic fixture promotion failed");
  auto narrowed_update =
      verified({dynamic_request(fixture, false, "narrow")}, '6');
  auto narrowed_review = host::prepare_consent_review(
      *fixture.store, narrowed_update, fixture.definitions, fixture.validator);
  require(narrowed_review && narrowed_review->dynamic_rows.size() == 1 &&
              narrowed_review->dynamic_rows[0].delta ==
                  host::ConsentDeltaKind::narrowed &&
              narrowed_review->dynamic_rows[0].previous_request->scope ==
                  definitions::CanonicalScope("wide") &&
              narrowed_review->dynamic_rows[0].previous_grant->scope ==
                  definitions::CanonicalScope("narrow"),
          "narrowed dynamic diff lost prior request/effective grant");
}

void dynamic_grants_require_nonempty_selected_operations() {
  for (const bool required : {false, true}) {
    Fixture fixture;
    require(fixture.definitions.install(
                dynamic_definition('b'),
                definitions::DefinitionSource::omarchy_package, 4),
            "partial dynamic definition install failed");
    auto candidate = verified(
        {dynamic_request(fixture, required, "wide", {"read", "write"})},
        required ? '2' : '1');
    auto review = host::prepare_consent_review(
        *fixture.store, candidate, fixture.definitions, fixture.validator);
    require(review && review->dynamic_rows.size() == 1,
            "partial dynamic review was not prepared");
    auto empty = dynamic_choice(*review, permissions::UserDecision::grant);
    empty.operations = {};
    empty.decided_scope = definitions::CanonicalScope("narrow");
    const std::array empty_choice{empty};
    require(host::publish_consent_review(
                *fixture.store, *review,
                confirmation(*review, {}, empty_choice), {}, empty_choice,
                fixture.definitions, fixture.validator) ==
                host::ConsentResult::spoofed_decision,
            "empty dynamic grant decision was published");

    auto partial = dynamic_choice(*review, permissions::UserDecision::grant);
    partial.operations = {};
    partial.operations.insert(definitions::Name("read"));
    partial.decided_scope = definitions::CanonicalScope("narrow");
    const std::array partial_choice{partial};
    require(host::publish_consent_review(
                *fixture.store, *review,
                confirmation(*review, {}, partial_choice), {}, partial_choice,
                fixture.definitions, fixture.validator) ==
                host::ConsentResult::applied,
            required ? "nonempty partial required grant was rejected"
                     : "nonempty partial optional grant was rejected");
  }
}

void exact_choice_sets_and_ordering() {
  Fixture fixture;
  auto candidate = verified(
      {storage_request(false, 8192), builtin_request(false, "status")}, '7');
  auto review = host::prepare_consent_review(
      *fixture.store, candidate, fixture.definitions, fixture.validator);
  require(review && review->builtin_rows.size() == 2,
          "two-choice review failed");
  std::array<host::BuiltinConsentDecision, 2> choices;
  for (std::size_t index = 0; index < choices.size(); ++index) {
    const auto &request = *review->builtin_rows[index].requested;
    choices[index] = {.capability = request.capability,
                      .decided_scope = request.scope,
                      .decision = permissions::UserDecision::grant};
  }
  auto reversed = choices;
  std::ranges::reverse(reversed);
  require(host::consent_decision_fingerprint(*review, choices, {}) ==
              host::consent_decision_fingerprint(*review, reversed, {}),
          "choice ordering changed canonical confirmation identity");
  auto duplicate = choices;
  duplicate[1] = duplicate[0];
  require(host::publish_consent_review(
              *fixture.store, *review, confirmation(*review, duplicate, {}),
              duplicate, {}, fixture.definitions,
              fixture.validator) == host::ConsentResult::spoofed_decision,
          "same-size duplicate/wrong capability set was accepted");
}

void replay_and_parallel_review_cas() {
  Fixture fixture;
  auto candidate = verified({builtin_request(false, "status")}, '8');
  auto first = host::prepare_consent_review(
      *fixture.store, candidate, fixture.definitions, fixture.validator);
  auto parallel = host::prepare_consent_review(
      *fixture.store, candidate, fixture.definitions, fixture.validator);
  auto choice = builtin_choice(*first, permissions::UserDecision::grant);
  const std::array choices{choice};
  const auto accepted = confirmation(*first, choices, {});
  require(host::publish_consent_review(*fixture.store, *first, accepted,
                                       choices, {}, fixture.definitions,
                                       fixture.validator) ==
              host::ConsentResult::applied,
          "first parallel review did not win CAS");
  require(host::publish_consent_review(*fixture.store, *parallel, accepted,
                                       choices, {}, fixture.definitions,
                                       fixture.validator) ==
              host::ConsentResult::stale_authority,
          "second parallel review was not stale");
  auto slots = fixture.store->read_slots();
  permissions::RequestSet requests =
      permissions::requests_from_manifest(candidate.manifest);
  permissions::ActivationBinding binding{
      .plugin = permissions::PluginId(kPlugin),
      .revision = permissions::Digest(candidate.tree_sha256),
      .policy_fingerprint = permissions::Digest(
          permissions::policy_request_fingerprint(requests)),
      .generation = 1};
  require(slots && fixture.store->discard_candidate(binding, slots->sequence) ==
                       host::AuthorityMutationResult::applied,
          "candidate discard failed");
  auto retried = host::prepare_consent_review(
      *fixture.store, candidate, fixture.definitions, fixture.validator);
  require(retried && retried->candidate_binding.generation == 2 &&
              retried->fingerprint != first->fingerprint,
          "re-review did not bind a new generation/sequence");
  require(host::publish_consent_review(*fixture.store, *retried, accepted,
                                       choices, {}, fixture.definitions,
                                       fixture.validator) ==
              host::ConsentResult::invalid_review,
          "old confirmation replayed after discard/reprepare");
}

void prior_builtin_grant_and_corrupt_active_fail_closed() {
  Fixture fixture;
  auto first = verified({storage_request(false, 8192)}, '0');
  auto review = host::prepare_consent_review(
      *fixture.store, first, fixture.definitions, fixture.validator);
  auto choice = builtin_choice(*review, permissions::UserDecision::grant);
  choice.decided_scope =
      permissions::QuotaScope{.total_bytes = 4096, .item_bytes = 4096};
  const std::array choices{choice};
  require(host::publish_consent_review(
              *fixture.store, *review, confirmation(*review, choices, {}),
              choices, {}, fixture.definitions,
              fixture.validator) == host::ConsentResult::applied,
          "narrowed built-in fixture publication failed");
  auto slots = fixture.store->read_slots();
  permissions::RequestSet requests =
      permissions::requests_from_manifest(first.manifest);
  permissions::ActivationBinding binding{
      .plugin = permissions::PluginId(kPlugin),
      .revision = permissions::Digest(first.tree_sha256),
      .policy_fingerprint = permissions::Digest(
          permissions::policy_request_fingerprint(requests)),
      .generation = 1};
  require(slots && fixture.store->promote_candidate(binding, slots->sequence) ==
                       host::AuthorityMutationResult::applied,
          "narrowed built-in fixture promotion failed");
  auto update = verified({storage_request(false, 8192)}, 'a');
  auto update_review = host::prepare_consent_review(
      *fixture.store, update, fixture.definitions, fixture.validator);
  require(update_review && update_review->builtin_rows.size() == 1 &&
              update_review->builtin_rows[0].previous_request &&
              update_review->builtin_rows[0].previous_grant &&
              std::get<permissions::QuotaScope>(
                  update_review->builtin_rows[0].previous_request->scope)
                      .total_bytes == 8192 &&
              std::get<permissions::QuotaScope>(
                  update_review->builtin_rows[0].previous_grant->scope)
                      .total_bytes == 4096,
          "built-in row confused prior request with effective grant");

  slots = fixture.store->read_slots();
  const auto grant_name =
      "grant-" + std::string(slots->active->snapshot_digest.view());
  require(::fchmodat(fixture.root, grant_name.c_str(), 0644, 0) == 0,
          "active corruption fixture chmod failed");
  require(!host::prepare_consent_review(*fixture.store, update,
                                        fixture.definitions, fixture.validator),
          "untrusted active snapshot produced a consent review");
}

void dynamic_update_requires_fresh_operations_decision() {
  Fixture fixture;
  require(fixture.definitions.install(
              dynamic_definition('e'),
              definitions::DefinitionSource::omarchy_package, 5),
          "dynamic update definition install failed");
  auto first = verified({dynamic_request(fixture, false, "narrow")}, 'f');
  auto first_review = host::prepare_consent_review(
      *fixture.store, first, fixture.definitions, fixture.validator);
  auto first_choice =
      dynamic_choice(*first_review, permissions::UserDecision::grant);
  const std::array first_choices{first_choice};
  require(host::publish_consent_review(
              *fixture.store, *first_review,
              confirmation(*first_review, {}, first_choices), {}, first_choices,
              fixture.definitions,
              fixture.validator) == host::ConsentResult::applied,
          "dynamic update fixture publication failed");
  auto slots = fixture.store->read_slots();
  permissions::RequestSet no_builtin;
  permissions::ActivationBinding binding{
      .plugin = permissions::PluginId(kPlugin),
      .revision = permissions::Digest(hex('f')),
      .policy_fingerprint = permissions::Digest(
          permissions::policy_request_fingerprint(no_builtin)),
      .generation = 1};
  require(slots && fixture.store->promote_candidate(binding, slots->sequence) ==
                       host::AuthorityMutationResult::applied,
          "dynamic update fixture promotion failed");

  const auto expect_delta = [&](manifest::CapabilityRequest request,
                                char revision,
                                host::ConsentDeltaKind expected) {
    auto candidate = verified({std::move(request)}, revision);
    auto review = host::prepare_consent_review(
        *fixture.store, candidate, fixture.definitions, fixture.validator);
    require(review && review->dynamic_rows.size() == 1 &&
                review->dynamic_rows[0].delta == expected,
            "dynamic update delta classification mismatch");
  };
  expect_delta(dynamic_request(fixture, false, "narrow"), '1',
               host::ConsentDeltaKind::unchanged);
  expect_delta(dynamic_request(fixture, false, "wide"), '2',
               host::ConsentDeltaKind::expanded);
  expect_delta(dynamic_request(fixture, false, "other"), '3',
               host::ConsentDeltaKind::incomparable);
  expect_delta(dynamic_request(fixture, true, "narrow"), '4',
               host::ConsentDeltaKind::requirement_changed);

  auto expanded = verified(
      {dynamic_request(fixture, false, "wide", {"write", "read"})}, '9');
  auto review = host::prepare_consent_review(
      *fixture.store, expanded, fixture.definitions, fixture.validator);
  require(review && review->dynamic_rows.size() == 1 &&
              review->dynamic_rows[0].delta ==
                  host::ConsentDeltaKind::operations_changed &&
              review->dynamic_rows[0].previous_request &&
              review->dynamic_rows[0].previous_grant &&
              review->dynamic_rows[0].requested->operations.size() == 2 &&
              review->dynamic_rows[0].previous_request->operations.size() == 1,
          "dynamic operations update was not an exact before/after review");

  fixture.definitions = {};
  require(fixture.definitions.install(
              dynamic_definition('a'),
              definitions::DefinitionSource::omarchy_package, 6),
          "replacement dynamic definition install failed");
  expect_delta(dynamic_request(fixture, false, "narrow"), '5',
               host::ConsentDeltaKind::definition_changed);
}

void update_diff_reorder_stale_and_zero_permission() {
  Fixture fixture;
  auto first = verified({builtin_request(false, "status")}, 'd');
  auto first_review = host::prepare_consent_review(
      *fixture.store, first, fixture.definitions, fixture.validator);
  auto first_choice =
      builtin_choice(*first_review, permissions::UserDecision::grant);
  const std::array first_choices{first_choice};
  require(host::publish_consent_review(
              *fixture.store, *first_review,
              confirmation(*first_review, first_choices, {}), first_choices, {},
              fixture.definitions,
              fixture.validator) == host::ConsentResult::applied,
          "update fixture candidate failed");
  auto slots = fixture.store->read_slots();
  auto snapshot = fixture.store->read_authority_view();
  require(slots && snapshot && slots->candidate,
          "candidate missing before promotion");
  const permissions::ActivationBinding binding{
      .plugin = permissions::PluginId(kPlugin),
      .revision = permissions::Digest(hex('d')),
      .policy_fingerprint =
          permissions::Digest(permissions::policy_request_fingerprint(
              permissions::requests_from_manifest(first.manifest))),
      .generation = 1};
  require(fixture.store->promote_candidate(binding, slots->sequence) ==
              host::AuthorityMutationResult::applied,
          "fixture promotion failed");

  auto removal = verified({}, 'e');
  auto stale_review = host::prepare_consent_review(
      *fixture.store, removal, fixture.definitions, fixture.validator);
  require(stale_review && stale_review->builtin_rows.size() == 1 &&
              !stale_review->builtin_rows[0].requested &&
              stale_review->builtin_rows[0].previous_request &&
              stale_review->builtin_rows[0].previous_grant,
          "removal diff lost exact prior request/grant");
  auto zero_confirmation = confirmation(*stale_review, {}, {});
  require(host::publish_consent_review(
              *fixture.store, *stale_review, zero_confirmation, {}, {},
              fixture.definitions,
              fixture.validator) == host::ConsentResult::applied,
          "confirmed zero-permission update did not publish");
  require(host::publish_consent_review(
              *fixture.store, *stale_review, zero_confirmation, {}, {},
              fixture.definitions,
              fixture.validator) == host::ConsentResult::stale_authority,
          "review replay after CAS was not stale");
}

} // namespace

int main() {
  try {
    explicit_install_and_denial_guards();
    optional_partial_spoof_and_invalid_enum();
    dynamic_exactness_and_provider_identity();
    dynamic_grants_require_nonempty_selected_operations();
    exact_choice_sets_and_ordering();
    replay_and_parallel_review_cas();
    prior_builtin_grant_and_corrupt_active_fail_closed();
    dynamic_update_requires_fresh_operations_decision();
    update_diff_reorder_stale_and_zero_permission();
    std::cout << "consent review tests passed\n";
    return 0;
  } catch (const std::exception &error) {
    std::cerr << "consent review test failed: " << error.what() << '\n';
    return 1;
  }
}
