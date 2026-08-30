#include "authority_store.hpp"

#include "manifest_contract.hpp"

#include <filesystem>
#include <fcntl.h>
#include <iostream>
#include <stdexcept>
#include <sys/wait.h>
#include <sys/stat.h>
#include <thread>
#include <unistd.h>

namespace host = omarchy::plugin_runtime::host_session;
namespace policy = omarchy::plugin_runtime::policy;
namespace permissions = omarchy::plugins::permissions;
namespace definitions = omarchy::plugins::definitions;
namespace manifest = omarchy::plugins::manifest;

namespace {
constexpr std::string_view kPlugin = "org.example.authority";

std::string hex(char value) { return std::string(64, value); }

definitions::DynamicScopeRelation compare_dynamic(
    const definitions::CapabilityDefinition &, std::string_view candidate,
    std::string_view baseline, void *) noexcept {
  if (candidate == baseline)
    return definitions::DynamicScopeRelation::equal;
  if (candidate == "narrow" && baseline == "wide")
    return definitions::DynamicScopeRelation::narrower;
  return definitions::DynamicScopeRelation::incomparable;
}

definitions::CapabilityDefinition dynamic_definition(
    std::string_view name, std::string_view operation, char digest_byte) {
  definitions::CapabilityDefinition definition{
      .canonical_name = definitions::Name(name),
      .authority_identity = definitions::Name(std::string(name) + ".authority"),
      .enforcement_family = definitions::EnforcementFamily::network_fetch,
      .display_category_id = definitions::Name("developer.services"),
      .display_category_label = definitions::Label("Developer services"),
      .scope_schema = definitions::ScopeSchema::https_origins_and_methods,
      .title = definitions::Label("Fetch selected data"),
      .risk_text = definitions::Label("Uses an exact reviewed adapter"),
      .risk = definitions::RiskLevel::high,
      .revocation = definitions::RevocationPolicy::cancel_inflight,
      .audit = {},
      .adapter = {.adapter_class =
                      definitions::Name(std::string(name) + ".adapter"),
                  .implementation_digest =
                      definitions::Digest(hex(digest_byte)),
                  .abi_version = 1},
      .operations = {}};
  definition.operations.insert(
      {.name = definitions::Name(operation),
       .label = definitions::Label("Read selected data")});
  return definition;
}

void require(bool condition, std::string_view message) {
  if (!condition)
    throw std::runtime_error(std::string(message));
}

struct Fixture {
  std::filesystem::path path;
  int root = -1;
  definitions::TrustedDefinitionRegistry definitions;
  std::unique_ptr<host::AuthorityStore> store;

  explicit Fixture(bool open_store = true) {
    std::string pattern =
        (std::filesystem::temp_directory_path() / "omarchy-authority-XXXXXX")
            .string();
    pattern.push_back('\0');
    char *created = ::mkdtemp(pattern.data());
    require(created != nullptr, "mkdtemp failed");
    path = created;
    root = ::open(created, O_RDONLY | O_DIRECTORY | O_CLOEXEC);
    require(root >= 0, "authority root open failed");
    if (open_store) {
      store = host::AuthorityStore::open(
          root, ::getuid(), permissions::PluginId(kPlugin));
      require(store != nullptr, "authority store open failed");
    }
  }

  ~Fixture() {
    store.reset();
    if (root >= 0)
      ::close(root);
    std::error_code ignored;
    std::filesystem::remove_all(path, ignored);
  }
};

struct Review {
  host::VerifiedRevision verified;
  policy::GrantSnapshot snapshot;
};

Review review(std::uint64_t generation, char revision = 'a',
              bool required = true,
              permissions::GrantState state = permissions::GrantState::granted) {
  manifest::ManifestV2 manifest;
  manifest.id = kPlugin;
  manifest.requests.push_back({.capability = "notifications.send",
                               .reason = "status",
                               .canonical_scope =
                                   "{\"categories\":[\"status\"]}",
                               .definition_generation = 0,
                               .definition_digest = {},
                               .operations = {},
                               .required = required});
  policy::GrantSnapshot snapshot;
  snapshot.requests = permissions::requests_from_manifest(manifest);
  snapshot.binding = {
      .plugin = permissions::PluginId(kPlugin),
      .revision = permissions::Digest(hex(revision)),
      .policy_fingerprint = permissions::Digest(
          permissions::policy_request_fingerprint(snapshot.requests)),
      .generation = generation};
  snapshot.source_request_fingerprint = permissions::Digest(
      manifest::requested_capability_fingerprint(manifest.requests));
  snapshot.grants.push_back({.capability = snapshot.requests[0].capability,
                             .scope = snapshot.requests[0].scope,
                             .state = state,
                             .epoch = generation});
  return {.verified = {.manifest = std::move(manifest),
                       .tree_sha256 = hex(revision),
                       .request_sha256 = std::string(
                           snapshot.source_request_fingerprint.view())},
          .snapshot = std::move(snapshot)};
}

Review dynamic_review(Fixture &fixture, std::uint64_t generation,
                      permissions::GrantState state =
                          permissions::GrantState::granted) {
  require(fixture.definitions.install(
              dynamic_definition("zeta.fetch", "zeta.read", 'd'),
              definitions::DefinitionSource::omarchy_package, 2) &&
              fixture.definitions.install(
                  dynamic_definition("alpha.fetch", "alpha.read", 'e'),
                  definitions::DefinitionSource::omarchy_package, 3),
          "dynamic definitions failed to install");
  manifest::ManifestV2 manifest;
  manifest.id = kPlugin;
  for (const auto pair : {std::pair{"zeta.fetch", "zeta.read"},
                          std::pair{"alpha.fetch", "alpha.read"}}) {
    const auto installed = fixture.definitions.find(pair.first);
    require(installed.has_value(), "dynamic definition lookup failed");
    manifest.requests.push_back(
        {.capability = pair.first,
         .reason = "status",
         .canonical_scope = "wide",
         .definition_generation = installed->generation,
         .definition_digest = std::string(installed->digest.view()),
         .operations = {pair.second},
         .required = true});
  }
  policy::GrantSnapshot snapshot;
  snapshot.requests = permissions::requests_from_manifest(manifest);
  snapshot.binding = {
      .plugin = permissions::PluginId(kPlugin),
      .revision = permissions::Digest(hex('d')),
      .policy_fingerprint = permissions::Digest(
          permissions::policy_request_fingerprint(snapshot.requests)),
      .generation = generation};
  snapshot.source_request_fingerprint = permissions::Digest(
      manifest::requested_capability_fingerprint(manifest.requests));
  for (const auto &manifest_request : manifest.requests) {
    auto request = definitions::dynamic_request_from_manifest(
        manifest_request, fixture.definitions);
    require(request.has_value(), "dynamic manifest request did not resolve");
    definitions::DynamicGrant grant{
        .definition = request->definition,
        .operations = request->operations,
        .scope = definitions::CanonicalScope("narrow"),
        .state = state,
        .epoch = generation};
    snapshot.dynamic_grants.push_back(
        {.binding = snapshot.binding,
         .request = std::move(*request),
         .grant = std::move(grant)});
  }
  std::ranges::sort(snapshot.dynamic_grants, {}, [](const auto &grant) {
    return grant.request.definition.canonical_name;
  });
  return {.verified = {.manifest = std::move(manifest),
                       .tree_sha256 = hex('d'),
                       .request_sha256 = std::string(
                           snapshot.source_request_fingerprint.view())},
          .snapshot = std::move(snapshot)};
}

std::string active_record(const host::AuthoritySlots &slots) {
  require(slots.active.has_value(), "active slot missing");
  return "grant-" + std::string(slots.active->snapshot_digest.view());
}

void roundtrip_and_lifecycle() {
  Fixture fixture;
  auto slots = fixture.store->read_slots();
  require(slots && slots->sequence == 0 &&
              slots->generation_high_watermark == 0,
          "initial slots were not empty");

  auto first = review(1);
  const auto first_publish =
      fixture.store->publish_candidate(first.verified, first.snapshot, 0,
                                       fixture.definitions, {});
  require(first_publish == host::AuthorityMutationResult::applied,
          "candidate publication failed: " +
              std::to_string(static_cast<int>(first_publish)));
  require(!fixture.store->resolve(kPlugin, hex('a')),
          "unpromoted candidate resolved as active authority");
  require(fixture.store->promote_candidate(first.snapshot.binding, 1) ==
              host::AuthorityMutationResult::applied,
          "candidate promotion failed");
  auto resolved = fixture.store->resolve(kPlugin, hex('a'));
  require(resolved && resolved->binding == first.snapshot.binding,
          "active exact grant did not round trip");
  require(!fixture.store->resolve("org.example.other", hex('a')),
          "store crossed its immutable plugin identity");

  auto second = review(2, 'b', false, permissions::GrantState::denied);
  require(fixture.store->publish_candidate(second.verified, second.snapshot, 1,
                                            fixture.definitions, {}) ==
              host::AuthorityMutationResult::stale_sequence,
          "stale optimistic sequence mutated authority");
  require(fixture.store->publish_candidate(second.verified, second.snapshot, 2,
                                            fixture.definitions, {}) ==
              host::AuthorityMutationResult::applied,
          "second candidate publication failed");
  require(fixture.store->discard_candidate(second.snapshot.binding, 3) ==
              host::AuthorityMutationResult::applied,
          "candidate discard failed");
  slots = fixture.store->read_slots();
  require(slots && slots->generation_high_watermark == 2 &&
              !slots->candidate,
          "discard lost generation high watermark");
  require(fixture.store->publish_candidate(second.verified, second.snapshot, 4,
                                            fixture.definitions, {}) ==
              host::AuthorityMutationResult::invalid,
          "discarded generation was reused");
}

void live_activation_binding_and_revocation() {
  Fixture fixture;
  auto first = review(1);
  require(fixture.store->publish_candidate(first.verified, first.snapshot, 0,
                                            fixture.definitions, {}) ==
                  host::AuthorityMutationResult::applied &&
              fixture.store->promote_candidate(first.snapshot.binding, 1) ==
                  host::AuthorityMutationResult::applied,
          "live binding fixture activation failed");

  auto live =
      std::make_shared<host::LiveGenerationState>(first.snapshot.binding);
  auto wrong_binding = first.snapshot.binding;
  wrong_binding.revision = permissions::Digest(hex('f'));
  auto wrong_live = std::make_shared<host::LiveGenerationState>(wrong_binding);
  require(!fixture.store->bind_live_activation(first.snapshot.binding, {}),
          "null live state was accepted");
  require(!fixture.store->bind_live_activation(wrong_binding, wrong_live),
          "non-active binding was accepted as live");
  require(!fixture.store->bind_live_activation(first.snapshot.binding,
                                                wrong_live),
          "live state with a different binding was accepted");
  require(fixture.store->bind_live_activation(first.snapshot.binding, live) &&
              fixture.store->bind_live_activation(first.snapshot.binding,
                                                  live) &&
              live->current(first.snapshot.binding),
          "same live pointer was not an idempotent exact binding");

  auto replacement =
      std::make_shared<host::LiveGenerationState>(first.snapshot.binding);
  require(fixture.store->bind_live_activation(first.snapshot.binding,
                                              replacement) &&
              !live->current(first.snapshot.binding) &&
              replacement->current(first.snapshot.binding),
          "new live binding did not revoke the prior state");

  auto second = review(2, 'b');
  require(fixture.store->publish_candidate(second.verified, second.snapshot, 2,
                                            fixture.definitions, {}) ==
                  host::AuthorityMutationResult::applied &&
              replacement->current(first.snapshot.binding),
          "candidate publication revoked the active live state");
  require(fixture.store->discard_candidate(second.snapshot.binding, 3) ==
                  host::AuthorityMutationResult::applied &&
              replacement->current(first.snapshot.binding),
          "candidate discard revoked the active live state");

  auto third = review(3, 'c');
  require(fixture.store->publish_candidate(third.verified, third.snapshot, 4,
                                            fixture.definitions, {}) ==
              host::AuthorityMutationResult::applied,
          "replacement candidate publication failed");
  require(fixture.store->promote_candidate(third.snapshot.binding, 5) ==
                  host::AuthorityMutationResult::applied &&
              !replacement->current(first.snapshot.binding),
          "promotion did not revoke the prior live activation");

  auto promoted =
      std::make_shared<host::LiveGenerationState>(third.snapshot.binding);
  require(fixture.store->bind_live_activation(third.snapshot.binding,
                                              promoted),
          "promoted active binding was not accepted as live");
  fixture.store.reset();
  require(!promoted->current(third.snapshot.binding),
          "authority store destruction did not revoke its live activation");
}

void promotion_revokes_before_failed_replacement() {
  Fixture fixture;
  auto first = review(1);
  require(fixture.store->publish_candidate(first.verified, first.snapshot, 0,
                                            fixture.definitions, {}) ==
                  host::AuthorityMutationResult::applied &&
              fixture.store->promote_candidate(first.snapshot.binding, 1) ==
                  host::AuthorityMutationResult::applied,
          "failed replacement fixture activation failed");
  auto live =
      std::make_shared<host::LiveGenerationState>(first.snapshot.binding);
  require(fixture.store->bind_live_activation(first.snapshot.binding, live),
          "failed replacement fixture live bind failed");
  auto second = review(2, 'b');
  require(fixture.store->publish_candidate(second.verified, second.snapshot, 2,
                                            fixture.definitions, {}) ==
              host::AuthorityMutationResult::applied,
          "failed replacement fixture candidate publication failed");
  require(::chmod(fixture.path.c_str(), 0500) == 0,
          "authority root permission mutation failed");
  const auto promoted =
      fixture.store->promote_candidate(second.snapshot.binding, 3);
  require(::chmod(fixture.path.c_str(), 0700) == 0,
          "authority root permission restore failed");
  require(promoted == host::AuthorityMutationResult::io_error &&
              !live->current(first.snapshot.binding),
          "failed durable replacement did not revoke live authority first");
  const auto slots = fixture.store->read_slots();
  require(slots && slots->active &&
              slots->active->generation == first.snapshot.binding.generation,
          "failed replacement changed the durable active authority");
}

void exact_builtin_revoke_rebases_and_invalidates_candidate() {
  Fixture fixture;
  auto first = review(1);
  require(fixture.store->publish_candidate(first.verified, first.snapshot, 0,
                                            fixture.definitions, {}) ==
                  host::AuthorityMutationResult::applied &&
              fixture.store->promote_candidate(first.snapshot.binding, 1) ==
                  host::AuthorityMutationResult::applied,
          "revoke fixture activation failed");
  auto live =
      std::make_shared<host::LiveGenerationState>(first.snapshot.binding);
  require(fixture.store->bind_live_activation(first.snapshot.binding, live),
          "revoke fixture live bind failed");

  auto pending = review(2, 'b', false);
  require(fixture.store->publish_candidate(pending.verified, pending.snapshot,
                                            2, fixture.definitions, {}) ==
              host::AuthorityMutationResult::applied,
          "revoke fixture pending candidate failed");
  const auto revoked = host::AuthorityStoreTestAccess::revoke_active(
      *fixture.store, first.snapshot.grants[0].capability, 3);
  require(revoked.status == host::AuthorityMutationResult::applied &&
              revoked.binding && revoked.binding->generation == 3 &&
              revoked.binding->revision == first.snapshot.binding.revision &&
              !revoked.activatable &&
              !live->current(first.snapshot.binding),
          "exact required revoke did not advance and fence authority");
  const auto view = fixture.store->read_authority_view();
  auto revoked_live = std::make_shared<host::LiveGenerationState>(
      *revoked.binding);
  require(view && view->active && !view->authority_slots.candidate &&
              view->authority_slots.generation_high_watermark == 3 &&
              view->active->binding == *revoked.binding &&
              view->active->grants[0].state ==
                  permissions::GrantState::revoked &&
              view->active->grants[0].epoch == 3 &&
              !fixture.store->resolve(kPlugin, hex('a')) &&
              !fixture.store->bind_live_activation(*revoked.binding,
                                                   revoked_live),
          "required revoked authority was not durable and nonactivatable");
  require(host::AuthorityStoreTestAccess::revoke_active(
              *fixture.store, first.snapshot.grants[0].capability, 4)
              .status == host::AuthorityMutationResult::invalid,
          "already revoked capability was revoked twice");

  Fixture optional;
  auto optional_value = review(1, 'a', false);
  require(optional.store->publish_candidate(optional_value.verified,
                                             optional_value.snapshot, 0,
                                             optional.definitions, {}) ==
                  host::AuthorityMutationResult::applied &&
              optional.store->promote_candidate(optional_value.snapshot.binding,
                                                 1) ==
                  host::AuthorityMutationResult::applied,
          "optional revoke fixture activation failed");
  const auto stale = host::AuthorityStoreTestAccess::revoke_active(
      *optional.store, optional_value.snapshot.grants[0].capability, 1);
  require(stale.status == host::AuthorityMutationResult::stale_sequence,
          "stale revoke sequence mutated authority");
  const auto result = host::AuthorityStoreTestAccess::revoke_active(
      *optional.store, optional_value.snapshot.grants[0].capability, 2);
  const auto resolved = optional.store->resolve(kPlugin, hex('a'));
  require(result.status == host::AuthorityMutationResult::applied &&
              result.activatable && resolved &&
              resolved->binding.generation == 2 &&
              resolved->grants[0].state ==
                  permissions::GrantState::revoked,
          "optional revoke did not remain activatable");
}

void exact_dynamic_revoke_rebases_every_epoch() {
  Fixture fixture;
  auto value = dynamic_review(fixture, 1);
  const auto validator =
      definitions::DynamicScopeValidator{.compare = compare_dynamic};
  require(fixture.store->publish_candidate(value.verified, value.snapshot, 0,
                                            fixture.definitions, validator) ==
                  host::AuthorityMutationResult::applied &&
              fixture.store->promote_candidate(value.snapshot.binding, 1) ==
                  host::AuthorityMutationResult::applied,
          "dynamic revoke fixture activation failed");
  const auto target = value.snapshot.dynamic_grants[0];
  const auto result = host::AuthorityStoreTestAccess::revoke_active(
      *fixture.store, target.request.definition, 2);
  const auto view = fixture.store->read_authority_view();
  require(result.status == host::AuthorityMutationResult::applied &&
              !result.activatable && view && view->active &&
              view->active->binding.generation == 2 &&
              view->active->dynamic_grants.size() == 2,
          "dynamic required revoke did not persist next generation");
  for (std::size_t index = 0;
       index < view->active->dynamic_grants.size(); ++index) {
    const auto &dynamic = view->active->dynamic_grants[index];
    require(dynamic.binding == view->active->binding &&
                dynamic.grant.epoch == 2 &&
                dynamic.grant.scope ==
                    value.snapshot.dynamic_grants[index].grant.scope &&
                dynamic.grant.operations ==
                    value.snapshot.dynamic_grants[index].grant.operations,
            "dynamic revoke did not preserve scope/ops and rebase authority");
  }
  require(view->active->dynamic_grants[0].grant.state ==
              permissions::GrantState::revoked &&
              view->active->dynamic_grants[1].grant.state ==
                  permissions::GrantState::granted,
          "dynamic revoke changed the wrong whole capability");
}

void revoke_io_failures_poison_after_effect_fence() {
  Fixture fixture;
  auto value = review(1, 'a', false);
  require(fixture.store->publish_candidate(value.verified, value.snapshot, 0,
                                            fixture.definitions, {}) ==
                  host::AuthorityMutationResult::applied &&
              fixture.store->promote_candidate(value.snapshot.binding, 1) ==
                  host::AuthorityMutationResult::applied,
          "poison fixture activation failed");
  auto live =
      std::make_shared<host::LiveGenerationState>(value.snapshot.binding);
  require(fixture.store->bind_live_activation(value.snapshot.binding, live),
          "poison fixture live bind failed");
  require(::chmod(fixture.path.c_str(), 0500) == 0,
          "poison fixture permission mutation failed");
  const auto result = host::AuthorityStoreTestAccess::revoke_active(
      *fixture.store, value.snapshot.grants[0].capability, 2);
  require(::chmod(fixture.path.c_str(), 0700) == 0,
          "poison fixture permission restore failed");
  require(result.status == host::AuthorityMutationResult::io_error &&
              !live->current(value.snapshot.binding) &&
              !fixture.store->read_slots() &&
              !fixture.store->resolve(kPlugin, hex('a')) &&
              !fixture.store->bind_live_activation(value.snapshot.binding,
                                                   live) &&
              fixture.store
                      ->publish_candidate(value.verified, value.snapshot, 2,
                                          fixture.definitions, {}) ==
                  host::AuthorityMutationResult::poisoned,
          "post-fence revoke failure did not poison all activation paths");
}

void crash_orphan_retry_and_cleanup() {
  Fixture fixture;
  auto first = review(1);
  require(fixture.store->publish_candidate(first.verified, first.snapshot, 0,
                                            fixture.definitions, {}) ==
              host::AuthorityMutationResult::applied,
          "orphan fixture publication failed");
  const auto orphan_record = "grant-" + std::string(
      fixture.store->read_slots()->candidate->snapshot_digest.view());
  fixture.store.reset();
  require(::unlinkat(fixture.root, "slots", 0) == 0,
          "simulated pre-pointer crash failed");
  fixture.store = host::AuthorityStore::open(
      fixture.root, ::getuid(), permissions::PluginId(kPlugin));
  require(fixture.store &&
              fixture.store->publish_candidate(first.verified, first.snapshot, 0,
                                                fixture.definitions, {}) ==
                  host::AuthorityMutationResult::applied,
          "byte-identical orphan record was not reusable");
  require(::faccessat(fixture.root, orphan_record.c_str(), F_OK, 0) == 0,
          "reused orphan record disappeared");
  const auto candidate_record = orphan_record;
  require(fixture.store->discard_candidate(first.snapshot.binding, 1) ==
              host::AuthorityMutationResult::applied,
          "orphan candidate discard failed");
  require(::faccessat(fixture.root, candidate_record.c_str(), F_OK, 0) < 0 &&
              errno == ENOENT,
          "normal discard leaked superseded immutable record");
}

void concurrency_fork_and_umask() {
  Fixture fixture;
  auto left = review(1, 'a');
  auto right = review(1, 'b');
  host::AuthorityMutationResult left_result{};
  host::AuthorityMutationResult right_result{};
  std::thread one([&] {
    left_result = fixture.store->publish_candidate(
        left.verified, left.snapshot, 0, fixture.definitions, {});
  });
  std::thread two([&] {
    right_result = fixture.store->publish_candidate(
        right.verified, right.snapshot, 0, fixture.definitions, {});
  });
  one.join();
  two.join();
  const int applied =
      (left_result == host::AuthorityMutationResult::applied) +
      (right_result == host::AuthorityMutationResult::applied);
  require(applied == 1,
          "same-object stale CAS did not serialize to exactly one mutation");

  const auto child = ::fork();
  require(child >= 0, "fork failed");
  if (child == 0) {
    const bool rejected = !fixture.store->read_slots() &&
                          !fixture.store->resolve(kPlugin, hex('a')) &&
                          !fixture.store->root_identity();
    ::_exit(rejected ? 0 : 1);
  }
  int status = 0;
  require(::waitpid(child, &status, 0) == child && WIFEXITED(status) &&
              WEXITSTATUS(status) == 0,
          "forked child retained authority owner access");
  require(fixture.store->read_slots().has_value(),
          "parent authority stopped after fork rejection");

  Fixture hostile_umask(false);
  const auto old_umask = ::umask(0777);
  hostile_umask.store = host::AuthorityStore::open(
      hostile_umask.root, ::getuid(), permissions::PluginId(kPlugin));
  auto value = review(1);
  const bool published =
      hostile_umask.store &&
      hostile_umask.store->publish_candidate(
          value.verified, value.snapshot, 0, hostile_umask.definitions, {}) ==
          host::AuthorityMutationResult::applied;
  ::umask(old_umask);
  require(published, "hostile umask created unreadable authority files");
}

void required_denial_cannot_promote() {
  Fixture fixture;
  auto denied = review(1, 'c', true, permissions::GrantState::denied);
  require(fixture.store->publish_candidate(denied.verified, denied.snapshot, 0,
                                            fixture.definitions, {}) ==
              host::AuthorityMutationResult::applied,
          "denied candidate publication failed");
  require(fixture.store->promote_candidate(denied.snapshot.binding, 1) ==
              host::AuthorityMutationResult::invalid,
          "required denial promoted");
}

void incomplete_and_mismatched_reviews_fail() {
  Fixture fixture;
  auto value = review(1);
  value.snapshot.grants = {};
  require(fixture.store->publish_candidate(value.verified, value.snapshot, 0,
                                            fixture.definitions, {}) ==
              host::AuthorityMutationResult::invalid,
          "missing explicit built-in decision persisted");
  value = review(1);
  value.verified.request_sha256 = hex('f');
  require(fixture.store->publish_candidate(value.verified, value.snapshot, 0,
                                            fixture.definitions, {}) ==
              host::AuthorityMutationResult::invalid,
          "mismatched verified request identity persisted");
  value = review(1);
  value.verified.tree_sha256 = hex('f');
  require(fixture.store->publish_candidate(value.verified, value.snapshot, 0,
                                            fixture.definitions, {}) ==
              host::AuthorityMutationResult::invalid,
          "mismatched verified tree identity persisted");
}

void dynamic_completeness_and_restart() {
  Fixture fixture;
  auto value = dynamic_review(fixture, 1);
  const auto validator =
      definitions::DynamicScopeValidator{.compare = compare_dynamic};
  auto malformed = value.snapshot;
  malformed.dynamic_grants.pop_back();
  require(fixture.store->publish_candidate(value.verified, malformed, 0,
                                            fixture.definitions, validator) ==
              host::AuthorityMutationResult::invalid,
          "omitted dynamic decision persisted");
  malformed = value.snapshot;
  malformed.dynamic_grants.push_back(malformed.dynamic_grants.back());
  require(fixture.store->publish_candidate(value.verified, malformed, 0,
                                            fixture.definitions, validator) ==
              host::AuthorityMutationResult::invalid,
          "duplicate dynamic decision persisted");
  malformed = value.snapshot;
  malformed.dynamic_grants[0].binding.generation = 2;
  require(fixture.store->publish_candidate(value.verified, malformed, 0,
                                            fixture.definitions, validator) ==
              host::AuthorityMutationResult::invalid,
          "wrong dynamic binding persisted");
  malformed = value.snapshot;
  malformed.dynamic_grants[0].grant.state =
      static_cast<permissions::GrantState>(255);
  require(fixture.store->publish_candidate(value.verified, malformed, 0,
                                            fixture.definitions, validator) ==
              host::AuthorityMutationResult::invalid,
          "invalid dynamic state persisted");
  auto changed_manifest = value.verified;
  changed_manifest.manifest.requests[0].operations[0] = "unreviewed.operation";
  require(fixture.store->publish_candidate(changed_manifest, value.snapshot, 0,
                                            fixture.definitions, validator) ==
              host::AuthorityMutationResult::invalid,
          "dynamic operation mutation hidden by source fingerprint persisted");
  malformed = value.snapshot;
  malformed.dynamic_grants[0].grant.scope =
      definitions::CanonicalScope("incomparable");
  require(fixture.store->publish_candidate(value.verified, malformed, 0,
                                            fixture.definitions, validator) ==
              host::AuthorityMutationResult::invalid,
          "incomparable dynamic grant scope persisted");
  require(fixture.store->publish_candidate(value.verified, value.snapshot, 0,
                                            fixture.definitions, validator) ==
              host::AuthorityMutationResult::applied,
          "complete reordered dynamic review did not publish");
  require(fixture.store->promote_candidate(value.snapshot.binding, 1) ==
              host::AuthorityMutationResult::applied,
          "complete dynamic review did not promote");
  fixture.store.reset();
  fixture.store = host::AuthorityStore::open(
      fixture.root, ::getuid(), permissions::PluginId(kPlugin));
  require(fixture.store && fixture.store->resolve(kPlugin, hex('d')),
          "dynamic exact grant did not survive authority restart");

  Fixture denied_fixture;
  auto denied = dynamic_review(denied_fixture, 1,
                               permissions::GrantState::denied);
  require(denied_fixture.store->publish_candidate(
              denied.verified, denied.snapshot, 0, denied_fixture.definitions,
              validator) == host::AuthorityMutationResult::applied,
          "required dynamic denial did not persist for review");
  require(denied_fixture.store->promote_candidate(denied.snapshot.binding, 1) ==
              host::AuthorityMutationResult::invalid,
          "required dynamic denial promoted");
}

void corrupt_records_fail_closed() {
  for (int mode = 0; mode < 3; ++mode) {
    Fixture fixture;
    auto value = review(1);
    require(fixture.store->publish_candidate(value.verified, value.snapshot, 0,
                                              fixture.definitions, {}) ==
                host::AuthorityMutationResult::applied &&
                fixture.store->promote_candidate(value.snapshot.binding, 1) ==
                    host::AuthorityMutationResult::applied,
            "corruption fixture setup failed");
    const auto name = active_record(*fixture.store->read_slots());
    if (mode == 0) {
      int file = ::openat(fixture.root, name.c_str(), O_WRONLY | O_TRUNC);
      require(file >= 0 && ::write(file, "x", 1) == 1, "truncate failed");
      ::close(file);
    } else if (mode == 1) {
      require(::fchmodat(fixture.root, name.c_str(), 0644, 0) == 0,
              "mode mutation failed");
    } else {
      require(::linkat(fixture.root, name.c_str(), fixture.root, "extra", 0) == 0,
              "hardlink mutation failed");
    }
    require(!fixture.store->resolve(kPlugin, hex('a')),
            "corrupt or untrusted record resolved");
  }
}

void root_lock_and_slots_metadata() {
  Fixture fixture(false);
  require(!host::AuthorityStore::open(
              fixture.root, ::getuid() + 1, permissions::PluginId(kPlugin)),
          "wrong expected uid opened authority root");
  fixture.store = host::AuthorityStore::open(
      fixture.root, ::getuid(), permissions::PluginId(kPlugin));
  require(fixture.store != nullptr, "primary store open failed");
  struct stat root_metadata {};
  const auto root_identity = fixture.store->root_identity();
  require(::fstat(fixture.root, &root_metadata) == 0 && root_identity &&
              root_identity->device ==
                  static_cast<std::uint64_t>(root_metadata.st_dev) &&
              root_identity->inode ==
                  static_cast<std::uint64_t>(root_metadata.st_ino),
          "authority store did not report its exact root identity");
  require(!host::AuthorityStore::open(
              fixture.root, ::getuid(), permissions::PluginId(kPlugin)),
          "second owner acquired nonblocking lifetime lock");

  Fixture malformed;
  int slots = ::openat(malformed.root, "slots",
                       O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0600);
  require(slots >= 0, "zero slots create failed");
  ::close(slots);
  require(!malformed.store->read_slots(),
          "present zero-byte slots reset authority to initial state");

  Fixture symlink_slots;
  require(::symlinkat("missing", symlink_slots.root, "slots") == 0,
          "slots symlink create failed");
  require(!symlink_slots.store->read_slots(),
          "symlink slots record was followed");

  Fixture special(false);
  require(::mkfifoat(special.root, ".authority.lock", 0600) == 0,
          "special lock create failed");
  require(!host::AuthorityStore::open(
              special.root, ::getuid(), permissions::PluginId(kPlugin)),
          "special lock file opened as authority lock");
}
} // namespace

int main() {
  try {
    roundtrip_and_lifecycle();
    live_activation_binding_and_revocation();
    promotion_revokes_before_failed_replacement();
    exact_builtin_revoke_rebases_and_invalidates_candidate();
    exact_dynamic_revoke_rebases_every_epoch();
    revoke_io_failures_poison_after_effect_fence();
    crash_orphan_retry_and_cleanup();
    concurrency_fork_and_umask();
    required_denial_cannot_promote();
    incomplete_and_mismatched_reviews_fail();
    dynamic_completeness_and_restart();
    corrupt_records_fail_closed();
    root_lock_and_slots_metadata();
  } catch (const std::exception &error) {
    std::cerr << error.what() << '\n';
    return 1;
  }
  return 0;
}
