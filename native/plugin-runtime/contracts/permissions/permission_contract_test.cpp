#include "permission_contract.hpp"

#include <functional>
#include <iostream>
#include <stdexcept>
#include <string>

namespace {

using namespace omarchy::plugins::permissions;

void require(bool condition, std::string_view message) {
  if (!condition)
    throw std::runtime_error(std::string(message));
}

void reject(const std::function<void()> &operation, std::string_view message) {
  bool rejected = false;
  try {
    operation();
  } catch (const std::runtime_error &) {
    rejected = true;
  }
  require(rejected, message);
}

Digest digest(char value) { return Digest(std::string(64, value)); }

TokenScope tokens(std::initializer_list<std::string_view> values) {
  TokenScope result;
  for (auto value : values)
    require(result.tokens.insert(ScopeToken(value)), "duplicate token");
  return result;
}

ResourceScope resources(std::initializer_list<std::uint32_t> values,
                        std::initializer_list<OperationId> operations) {
  ResourceScope result;
  for (auto value : values)
    require(result.resources.insert(value), "duplicate resource");
  for (auto operation : operations)
    require(result.operations.insert(operation), "duplicate operation");
  return result;
}

CapabilityKey key(std::string_view id) { return {CapabilityId(id), 1}; }

void bounded_collection_contract() {
  ScopeToken reassigned("longer-value");
  reassigned.assign("short");
  require(reassigned == ScopeToken("short"),
          "bounded string retained prior bytes in canonical comparison");
  FixedVector<int, 2> values;
  values.push_back(1);
  reject([&] { (void)values[1]; }, "fixed vector exposed unused capacity");
  values.push_back(2);
  reject([&] { values.push_back(3); }, "fixed vector exceeded capacity");
  reject([] { ScopeToken invalid(""); }, "empty scope token was accepted");
}

void registry_and_scope_contract() {
  const auto registry = capability_registry();
  require(registry.size() == 4, "unexpected registry size");
  require(static_cast<std::uint16_t>(OperationId::storage_read) == 0x0101 &&
              static_cast<std::uint16_t>(
                  OperationId::fake_status_acknowledge) == 0x0402,
          "operation identifier golden changed");
  for (const auto &definition : registry) {
    require(definition.key.id.view().find("command") ==
                    std::string_view::npos &&
                definition.key.id.view().find("filesystem") ==
                    std::string_view::npos &&
                definition.key.id.view() != "network",
            "generic authority entered capability registry");
  }
  FixedSet<CapabilityKey, 8> registry_keys;
  FixedSet<OperationId, 16> registry_operations;
  for (const auto &definition : registry) {
    require(registry_keys.insert(definition.key),
            "duplicate capability registry key");
    for (std::size_t index = 0; index < definition.operation_count; ++index)
      require(registry_operations.insert(definition.operations[index]),
              "operation belongs to multiple capabilities");
  }

  const Scope small_quota = QuotaScope{1024, 256};
  const Scope large_quota = QuotaScope{4096, 1024};
  const Scope crossed_quota = QuotaScope{2048, 2048};
  require(compare_scope(small_quota, large_quota) == ScopeRelation::narrower,
          "quota narrowing was not detected");
  require(compare_scope(large_quota, small_quota) == ScopeRelation::expanded,
          "quota expansion was not detected");
  require(compare_scope(crossed_quota, large_quota) ==
              ScopeRelation::incomparable,
          "crossed quota was comparable");

  const Scope one = tokens({"timer"});
  const Scope two = tokens({"alerts", "timer"});
  require(compare_scope(one, two) == ScopeRelation::narrower &&
              compare_scope(two, one) == ScopeRelation::expanded,
          "token-set relation failed");
  TokenScope empty_token;
  require(empty_token.tokens.insert(ScopeToken{}),
          "empty-token fixture insertion failed");
  require(!valid_scope(*find_capability(key("notifications.send")),
                       Scope(empty_token)),
          "default-constructed empty token was accepted");
  require(!valid_scope(*find_capability(key("service.fake-status")),
                       Scope(resources({0}, {OperationId::fake_status_list}))),
          "zero resource identifier was accepted");

  HttpScope internet;
  internet.schemes.insert(ScopeToken("https"));
  internet.hosts.insert(ScopeToken("status.example.com"));
  internet.methods.insert(ScopeToken("GET"));
  internet.ports.insert(443);
  HttpScope loopback = internet;
  loopback.allow_loopback = true;
  require(compare_scope(Scope(internet), Scope(loopback)) ==
              ScopeRelation::narrower,
          "loopback authority was not explicit expansion");
  loopback.allow_unix_socket = true;
  CapabilityDefinition http_definition{.key = key("http.request"),
                                       .scope_kind = ScopeKind::http,
                                       .operations = {},
                                       .operation_count = 0,
                                       .gesture = GestureRule::none,
                                       .revocation = RevocationMode::deny_new};
  require(!valid_scope(http_definition, Scope(loopback)),
          "Unix-socket HTTP escape was accepted");
}

RequestSet baseline_requests() {
  RequestSet requests;
  requests.push_back({.capability = key("storage.private"),
                      .scope = QuotaScope{4096, 1024},
                      .required = true});
  requests.push_back({.capability = key("notifications.send"),
                      .scope = tokens({"alerts", "timer"}),
                      .required = false});
  requests.push_back({.capability = key("audio.play-cue"),
                      .scope = tokens({"complete"}),
                      .required = false});
  return requests;
}

void fingerprint_and_decision_contract() {
  auto requests = baseline_requests();
  const auto fingerprint = policy_request_fingerprint(requests);
  require(fingerprint == POLICY_FINGERPRINT_GOLDEN,
          "policy request fingerprint mismatch: " + fingerprint);
  RequestSet reordered;
  reordered.push_back(requests[2]);
  reordered.push_back(requests[0]);
  reordered.push_back(requests[1]);
  require(policy_request_fingerprint(reordered) == fingerprint,
          "request order changed policy fingerprint");
  auto expanded = baseline_requests();
  expanded[0].scope = QuotaScope{8192, 1024};
  require(policy_request_fingerprint(expanded) != fingerprint,
          "expanded request preserved fingerprint");
  auto duplicate = baseline_requests();
  duplicate.push_back(duplicate[0]);
  reject([&] { validate_requests(duplicate); },
         "duplicate request was accepted");

  UserDecisionRecord decision{
      .sequence = 1,
      .plugin = PluginId("org.example.timer"),
      .revision = digest('a'),
      .source_request_fingerprint = digest('b'),
      .policy_request_fingerprint = Digest(fingerprint),
      .capability = key("storage.private"),
      .requested_scope = QuotaScope{4096, 1024},
      .decided_scope = QuotaScope{2048, 512},
      .decision = UserDecision::grant,
      .actor = DecisionActor::interactive_cli,
      .decided_wall_seconds = 100,
  };
  validate_decision(decision);
  decision.decided_scope = QuotaScope{8192, 1024};
  reject([&] { validate_decision(decision); },
         "user decision expanded publisher request");
  decision.decision = UserDecision::deny;
  decision.decided_scope = QuotaScope{2048, 512};
  reject([&] { validate_decision(decision); },
         "denial recorded a misleading narrowed scope");
}

GrantSet baseline_grants() {
  GrantSet grants;
  grants.push_back({.capability = key("storage.private"),
                    .scope = QuotaScope{4096, 1024},
                    .state = GrantState::granted,
                    .epoch = 7});
  grants.push_back({.capability = key("notifications.send"),
                    .scope = tokens({"alerts", "timer"}),
                    .state = GrantState::denied,
                    .epoch = 3});
  grants.push_back({.capability = key("audio.play-cue"),
                    .scope = tokens({"complete"}),
                    .state = GrantState::granted,
                    .epoch = 2});
  return grants;
}

void delta_contract() {
  const auto old_requests = baseline_requests();
  const auto old_grants = baseline_grants();
  RequestSet next;
  next.push_back({.capability = key("storage.private"),
                  .scope = QuotaScope{2048, 512},
                  .required = true});
  next.push_back({.capability = key("notifications.send"),
                  .scope = tokens({"alerts", "errors", "timer"}),
                  .required = false});
  next.push_back({.capability = key("audio.play-cue"),
                  .scope = tokens({"complete"}),
                  .required = true});
  next.push_back({.capability = key("service.fake-status"),
                  .scope = resources({1}, {OperationId::fake_status_list}),
                  .required = false});
  const auto delta = compute_update_delta(old_requests, old_grants, next);
  require(delta.size() == 4, "delta count mismatch");
  require(delta[0].kind == DeltaKind::narrowed &&
              delta[0].inherited_grant.has_value() &&
              delta[0].inherited_grant->scope == next[0].scope,
          "narrowed grant was not safely inherited");
  require(delta[1].kind == DeltaKind::expanded &&
              !delta[1].inherited_grant.has_value(),
          "expanded grant was inherited");
  require(delta[2].kind == DeltaKind::requirement_changed &&
              !delta[2].inherited_grant.has_value(),
          "requiredness change was inherited");
  require(delta[3].kind == DeltaKind::added &&
              !delta[3].inherited_grant.has_value(),
          "new capability was inherited");

  const auto identical =
      compute_update_delta(old_requests, old_grants, old_requests);
  require(identical.size() == 3 && identical[0].kind == DeltaKind::unchanged &&
              identical[0].inherited_grant == old_grants[0] &&
              identical[1].inherited_grant == old_grants[1],
          "unchanged grant or denial was not inherited");

  auto incomparable = old_requests;
  incomparable[0].scope = QuotaScope{2048, 2048};
  const auto incomparable_delta =
      compute_update_delta(old_requests, old_grants, incomparable);
  require(incomparable_delta[0].kind == DeltaKind::incomparable &&
              !incomparable_delta[0].inherited_grant.has_value(),
          "incomparable request inherited authority");

  auto narrowed_beyond_grant = old_requests;
  narrowed_beyond_grant[0].scope = QuotaScope{2048, 512};
  auto narrow_grants = old_grants;
  narrow_grants[0].scope = QuotaScope{1024, 1024};
  const auto no_inheritance =
      compute_update_delta(old_requests, narrow_grants, narrowed_beyond_grant);
  require(no_inheritance[0].kind == DeltaKind::narrowed &&
              !no_inheritance[0].inherited_grant.has_value(),
          "new request outside old grant inherited authority");

  auto corrupt_grants = old_grants;
  corrupt_grants[0].scope = QuotaScope{8192, 1024};
  reject(
      [&] { compute_update_delta(old_requests, corrupt_grants, old_requests); },
      "delta accepted an old grant broader than its request");

  RequestSet removed;
  removed.push_back(old_requests[0]);
  const auto removal = compute_update_delta(old_requests, old_grants, removed);
  require(removal.size() == 3 && removal[1].kind == DeltaKind::removed &&
              removal[2].kind == DeltaKind::removed,
          "removed capabilities were not revoked by delta");

  const auto grants_fingerprint = grant_fingerprint(
      PluginId("org.example.timer"), digest('a'), digest('b'), old_grants);
  require(grants_fingerprint == GRANT_FINGERPRINT_GOLDEN,
          "grant fingerprint mismatch: " + grants_fingerprint);
}

ActivationBinding binding(std::uint64_t generation = 9) {
  return {.plugin = PluginId("org.example.timer"),
          .revision = digest('a'),
          .policy_fingerprint = digest('b'),
          .generation = generation};
}

ActivationBinding binding_for(const RequestSet &requests,
                              std::uint64_t generation = 9) {
  auto result = binding(generation);
  result.policy_fingerprint = Digest(policy_request_fingerprint(requests));
  return result;
}

void authority_and_handle_contract() {
  RequestSet requests;
  requests.push_back({.capability = key("storage.private"),
                      .scope = QuotaScope{4096, 1024},
                      .required = true});
  requests.push_back(
      {.capability = key("service.fake-status"),
       .scope = resources({1, 2}, {OperationId::fake_status_list,
                                   OperationId::fake_status_acknowledge}),
       .required = false});
  requests.push_back({.capability = key("notifications.send"),
                      .scope = tokens({"timer"}),
                      .required = false});
  requests.push_back({.capability = key("audio.play-cue"),
                      .scope = tokens({"complete"}),
                      .required = false});
  GrantSet grants;
  grants.push_back({.capability = key("storage.private"),
                    .scope = QuotaScope{2048, 512},
                    .state = GrantState::granted,
                    .epoch = 4});
  grants.push_back({.capability = key("service.fake-status"),
                    .scope = resources({1}, {OperationId::fake_status_list}),
                    .state = GrantState::granted,
                    .epoch = 5});
  grants.push_back({.capability = key("notifications.send"),
                    .scope = tokens({"timer"}),
                    .state = GrantState::denied,
                    .epoch = 2});
  const auto active = binding_for(requests);
  PermissionAuthority authority(active, requests, grants);
  reject(
      [&] {
        auto wrong_binding = active;
        wrong_binding.policy_fingerprint = digest('c');
        (void)PermissionAuthority(wrong_binding, requests, grants);
      },
      "authority accepted a policy fingerprint mismatch");
  reject(
      [&] {
        auto expanded_grants = grants;
        expanded_grants[0].scope = QuotaScope{8192, 1024};
        (void)PermissionAuthority(active, requests, expanded_grants);
      },
      "authority accepted a grant exceeding the request");
  require(authority
              .authorize(OperationId::storage_read, QuotaScope{1024, 256},
                         active, 10)
              .allowed(),
          "granted in-scope operation was denied");
  require(authority
                  .authorize(OperationId::storage_write, QuotaScope{4096, 1024},
                             active, 10)
                  .code == GrantDecisionCode::outside_scope,
          "expanded operation scope was allowed");
  require(authority
                  .authorize(OperationId::notification_send, tokens({"timer"}),
                             active, 10)
                  .code == GrantDecisionCode::explicitly_denied,
          "explicit denial was not enforced");
  require(authority
                  .authorize(OperationId::audio_play_cue, tokens({"complete"}),
                             active, 10)
                  .code == GrantDecisionCode::ungranted,
          "declared capability without a grant was allowed");
  require(authority
                  .authorize(static_cast<OperationId>(0xffff), NoScope{},
                             active, 10)
                  .code == GrantDecisionCode::unknown_operation,
          "unknown operation was allowed");
  require(authority
                  .authorize(OperationId::storage_read, QuotaScope{1, 1},
                             binding_for(requests, 10), 10)
                  .code == GrantDecisionCode::activation_mismatch,
          "wrong generation was allowed");

  const Scope fake_demand = resources({1}, {OperationId::fake_status_list});
  require(
      authority
              .authorize(OperationId::fake_status_list, fake_demand, active, 10)
              .code == GrantDecisionCode::gesture_missing,
      "gesture capability ran without proof");
  const Scope confused_demand =
      resources({1}, {OperationId::fake_status_acknowledge});
  require(authority
                  .authorize(OperationId::fake_status_list, confused_demand,
                             active, 10)
                  .code == GrantDecisionCode::outside_scope,
          "resource demand crossed its operation binding");
  GestureProof gesture{.id = {},
                       .plugin = PluginId("org.example.timer"),
                       .generation = 9,
                       .surface = 1,
                       .operation = OperationId::fake_status_list,
                       .expires_monotonic_ns = 20,
                       .consumed = false};
  gesture.id.bytes[0] = std::byte{1};
  auto null_gesture = gesture;
  null_gesture.id = {};
  require(authority
                  .authorize(OperationId::fake_status_list, fake_demand, active,
                             10, &null_gesture)
                  .code == GrantDecisionCode::gesture_wrong_binding,
          "null gesture identifier was accepted");
  auto expired_gesture = gesture;
  expired_gesture.expires_monotonic_ns = 10;
  require(authority
                  .authorize(OperationId::fake_status_list, fake_demand, active,
                             10, &expired_gesture)
                  .code == GrantDecisionCode::gesture_expired,
          "expired gesture was accepted");
  auto wrong_gesture = gesture;
  wrong_gesture.surface = 0;
  require(authority
                  .authorize(OperationId::fake_status_list, fake_demand, active,
                             10, &wrong_gesture)
                  .code == GrantDecisionCode::gesture_wrong_binding,
          "wrongly bound gesture was accepted");
  require(authority
                  .authorize(OperationId::fake_status_list, fake_demand, active,
                             10, &gesture)
                  .allowed() &&
              gesture.consumed,
          "valid gesture proof was denied or not consumed");
  require(authority
                  .authorize(OperationId::fake_status_list, fake_demand, active,
                             10, &gesture)
                  .code == GrantDecisionCode::gesture_used,
          "gesture proof replay was accepted");

  HandleTable<2> handles;
  HandleId first{};
  first.bytes[0] = std::byte{1};
  HandleRecord record{.id = first,
                      .plugin = PluginId("org.example.timer"),
                      .revision = digest('a'),
                      .policy_fingerprint = active.policy_fingerprint,
                      .generation = 9,
                      .operation = OperationId::storage_read,
                      .scope = QuotaScope{1024, 256},
                      .grant_epoch = 4,
                      .expires_monotonic_ns = 100};
  auto invalid_record = record;
  invalid_record.id = {};
  require(handles.issue(invalid_record) == HandleDecision::invalid,
          "null handle identifier was issued");
  require(handles.issue(record) == HandleDecision::allowed &&
              handles.issue(record) == HandleDecision::duplicate,
          "handle duplicate contract failed");
  HandleId unknown{};
  unknown.bytes[0] = std::byte{9};
  require(handles.resolve(unknown, active, OperationId::storage_read,
                          QuotaScope{1, 1}, 4, 1) == HandleDecision::unknown,
          "unknown handle was accepted");
  require(handles.resolve(first, active, OperationId::storage_read,
                          QuotaScope{512, 128}, 4,
                          50) == HandleDecision::allowed,
          "valid handle was denied");
  require(handles.resolve(first, active, OperationId::storage_write,
                          QuotaScope{512, 128}, 4,
                          50) == HandleDecision::wrong_operation,
          "handle crossed operation boundary");
  auto wrong_plugin = active;
  wrong_plugin.plugin = PluginId("org.example.other");
  require(handles.resolve(first, wrong_plugin, OperationId::storage_read,
                          QuotaScope{512, 128}, 4,
                          50) == HandleDecision::wrong_plugin,
          "handle crossed plugin boundary");
  auto wrong_revision = active;
  wrong_revision.revision = digest('c');
  require(handles.resolve(first, wrong_revision, OperationId::storage_read,
                          QuotaScope{512, 128}, 4,
                          50) == HandleDecision::wrong_revision,
          "handle crossed revision boundary");
  require(handles.resolve(first, binding_for(requests, 10),
                          OperationId::storage_read, QuotaScope{512, 128}, 4,
                          50) == HandleDecision::wrong_generation,
          "handle crossed generation boundary");
  auto wrong_policy = active;
  wrong_policy.policy_fingerprint = digest('c');
  require(handles.resolve(first, wrong_policy, OperationId::storage_read,
                          QuotaScope{512, 128}, 4,
                          50) == HandleDecision::wrong_policy,
          "handle crossed policy boundary");
  require(handles.resolve(first, active, OperationId::storage_read,
                          QuotaScope{512, 128}, 5,
                          50) == HandleDecision::stale_grant,
          "handle survived grant epoch change");
  require(handles.resolve(first, active, OperationId::storage_read,
                          QuotaScope{512, 128}, 4,
                          100) == HandleDecision::expired,
          "expired handle was accepted");
  require(handles.resolve(first, active, OperationId::storage_read,
                          QuotaScope{2048, 512}, 4,
                          50) == HandleDecision::outside_scope,
          "handle expanded its issued scope");
  require(handles.resolve(first, active, OperationId::storage_read,
                          QuotaScope{0, 0}, 4,
                          50) == HandleDecision::outside_scope,
          "handle accepted an invalid demand scope");
  auto second = record;
  second.id.bytes[0] = std::byte{2};
  auto third = record;
  third.id.bytes[0] = std::byte{3};
  require(handles.issue(second) == HandleDecision::allowed &&
              handles.issue(third) == HandleDecision::table_full,
          "handle table capacity was not enforced");

  const auto epoch = authority.revoke(key("storage.private"));
  require(epoch == 5 && authority
                                .authorize(OperationId::storage_read,
                                           QuotaScope{1, 1}, active, 10)
                                .code == GrantDecisionCode::revoked,
          "live revocation did not deny immediately");
}

void audit_contract() {
  AuditDraft draft{.event = AuditEvent::operation_decided,
                   .outcome = AuditOutcome::denied,
                   .plugin = PluginId("org.example.timer"),
                   .revision = digest('a'),
                   .generation = 9,
                   .correlation = 42,
                   .operation = OperationId::storage_write,
                   .capability = key("storage.private"),
                   .decision = GrantDecisionCode::outside_scope,
                   .metadata = {}};
  draft.metadata.push_back(
      {.metric = AuditMetric::request_bytes, .value = 128});
  auto invalid_draft = draft;
  invalid_draft.capability = key("notifications.send");
  reject([&] { validate_audit_draft(invalid_draft); },
         "audit accepted mismatched operation and capability");
  invalid_draft = draft;
  invalid_draft.metadata[0].value = -1;
  reject([&] { validate_audit_draft(invalid_draft); },
         "audit accepted a negative metric");
  invalid_draft = draft;
  invalid_draft.metadata.push_back(
      {.metric = AuditMetric::request_bytes, .value = 1});
  reject([&] { validate_audit_draft(invalid_draft); },
         "audit accepted duplicate metrics");
  reject(
      [&] {
        AuditLog<1> invalid_log;
        invalid_log.append(static_cast<AuditProducer>(255), draft, 1, 1);
      },
      "audit accepted an unknown producer");
  AuditLog<2> log;
  const auto &first = log.append(AuditProducer::broker, draft, 1000, 2000);
  const auto fingerprint = audit_record_fingerprint(first);
  require(fingerprint == AUDIT_FINGERPRINT_GOLDEN,
          "audit fingerprint mismatch: " + fingerprint);
  log.append(AuditProducer::supervisor, draft, 1001, 2001);
  log.append(AuditProducer::lifecycle, draft, 1002, 2002);
  require(log.size() == 2 && log.oldest(0).sequence == 2 &&
              log.oldest(1).sequence == 3,
          "bounded audit retention order failed");
  for (int index = 0; index < 7; ++index)
    draft.metadata.push_back(
        {.metric = AuditMetric::item_count, .value = index});
  reject(
      [&] {
        draft.metadata.push_back(
            {.metric = AuditMetric::item_count, .value = 9});
      },
      "audit metadata exceeded fixed bound");
}

} // namespace

int main() {
  try {
    bounded_collection_contract();
    registry_and_scope_contract();
    fingerprint_and_decision_contract();
    delta_contract();
    authority_and_handle_contract();
    audit_contract();
    std::cout << "capability, grant, handle, and audit contract: PASS\n";
    return 0;
  } catch (const std::exception &error) {
    std::cerr << "permission-contract-test: " << error.what() << '\n';
    return 1;
  }
}
