#include "structured_broker.hpp"

#include "audit_store.hpp"
#include "omarchy/plugin_runtime/broker/broker_schema.hpp"

#include <array>
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdlib>
#include <functional>
#include <iostream>
#include <stdexcept>
#include <string_view>
#include <thread>
#include <type_traits>
#include <vector>

using namespace omarchy::plugin_runtime;
using namespace omarchy::plugin_runtime::host_session;
namespace audit = omarchy::plugins::audit;
namespace broker = omarchy::plugin_runtime::broker;
namespace definitions = omarchy::plugins::definitions;
namespace permissions = omarchy::plugins::permissions;
namespace providers = omarchy::plugin_runtime::providers;
namespace runtime = omarchy::plugin_runtime::runtime;
namespace wire = omarchy::plugin::wire;

namespace {

static_assert(!std::is_copy_constructible_v<AdmittedBrokerRequest>);
static_assert(!std::is_copy_assignable_v<AdmittedBrokerRequest>);
static_assert(std::is_move_constructible_v<AdmittedBrokerRequest>);
static_assert(!std::is_copy_constructible_v<BrokerTransaction>);
static_assert(!std::is_copy_assignable_v<BrokerTransaction>);
static_assert(std::is_move_constructible_v<BrokerTransaction>);
static_assert(!std::is_move_assignable_v<BrokerTransaction>);
static_assert(!std::is_copy_constructible_v<StructuredBroker>);
static_assert(!std::is_copy_assignable_v<StructuredBroker>);
static_assert(!std::is_move_constructible_v<StructuredBroker>);
static_assert(!std::is_move_assignable_v<StructuredBroker>);
static_assert(!std::is_default_constructible_v<AuthenticatedBrokerAdmission>);

void require(bool condition, std::string_view message) {
  if (!condition)
    throw std::runtime_error(std::string(message));
}

AuthenticatedBrokerAdmission extract_admission(StructuredBroker &broker_mux) {
  auto extracted = broker_mux.take_admission();
  require(static_cast<bool>(extracted),
          "broker did not provide its one admission authority");
  return std::move(*extracted.admission);
}

permissions::Digest digest(char value) {
  return permissions::Digest(std::string(64, value));
}

permissions::TokenScope tokens(std::string_view token) {
  permissions::TokenScope scope;
  require(scope.tokens.insert(permissions::ScopeToken(token)),
          "duplicate token fixture");
  return scope;
}

permissions::ActivationBinding binding() {
  permissions::RequestSet requests;
  requests.push_back(
      {.capability = {.id = permissions::CapabilityId("audio.play-cue"),
                      .version = 1},
       .scope = tokens("complete"),
       .required = true});
  requests.push_back(
      {.capability = {.id = permissions::CapabilityId("notifications.send"),
                      .version = 1},
       .scope = tokens("timer"),
       .required = false});
  return {.plugin = permissions::PluginId("fixture.plugin"),
          .revision = digest('a'),
          .policy_fingerprint = permissions::Digest(
              permissions::policy_request_fingerprint(requests)),
          .generation = 7};
}

policy::GrantSnapshot builtin_snapshot() {
  policy::GrantSnapshot snapshot;
  snapshot.binding = binding();
  const permissions::CapabilityKey audio{
      .id = permissions::CapabilityId("audio.play-cue"), .version = 1};
  const permissions::CapabilityKey notification{
      .id = permissions::CapabilityId("notifications.send"), .version = 1};
  snapshot.requests.push_back(
      {.capability = audio, .scope = tokens("complete"), .required = true});
  snapshot.requests.push_back({.capability = notification,
                               .scope = tokens("timer"),
                               .required = false});
  snapshot.binding.policy_fingerprint = permissions::Digest(
      permissions::policy_request_fingerprint(snapshot.requests));
  snapshot.grants.push_back({.capability = audio,
                             .scope = tokens("complete"),
                             .state = permissions::GrantState::granted,
                             .epoch = 4});
  snapshot.grants.push_back({.capability = notification,
                             .scope = tokens("timer"),
                             .state = permissions::GrantState::denied,
                             .epoch = 3});
  return snapshot;
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

std::vector<std::byte> token_request(permissions::OperationId operation,
                                     std::string_view token) {
  std::vector<std::byte> bytes(10 + token.size());
  put16(bytes, 0, static_cast<std::uint16_t>(operation));
  put16(bytes, 2, static_cast<std::uint16_t>(2 + token.size()));
  put32(bytes, 4, 0);
  put16(bytes, 8, static_cast<std::uint16_t>(token.size()));
  for (std::size_t index = 0; index < token.size(); ++index)
    bytes[10 + index] = static_cast<std::byte>(token[index]);
  return bytes;
}

AuthenticatedBrokerRequestView
request(std::uint16_t type, std::uint64_t correlation,
        std::span<const std::byte> payload) {
  return {.message_type = type,
          .correlation_id = correlation,
          .payload = payload};
}

struct AudioProbe {
  std::mutex mutex;
  std::condition_variable condition;
  std::size_t calls = 0;
  bool block = false;
  bool entered = false;
  bool released = false;
  std::function<void()> reenter;
};

bool play(std::string_view cue, void *context) noexcept {
  auto &probe = *static_cast<AudioProbe *>(context);
  std::unique_lock lock(probe.mutex);
  ++probe.calls;
  probe.entered = true;
  probe.condition.notify_all();
  const auto reenter = probe.reenter;
  lock.unlock();
  if (reenter)
    reenter();
  lock.lock();
  if (probe.block)
    probe.condition.wait(lock, [&] { return probe.released; });
  return cue == "complete";
}

definitions::DynamicScopeRelation
exact_scope(const definitions::CapabilityDefinition &, std::string_view left,
            std::string_view right, void *) noexcept {
  return left == right ? definitions::DynamicScopeRelation::equal
                       : definitions::DynamicScopeRelation::incomparable;
}

struct DynamicProbe {
  std::size_t calls = 0;
  bool oversize = false;
};

bool dynamic_dispatch(const definitions::AuthorizedDynamicRequest &request,
                      std::span<std::byte> response, std::size_t &written,
                      void *context) noexcept {
  auto &probe = *static_cast<DynamicProbe *>(context);
  ++probe.calls;
  if (probe.oversize) {
    written = response.size() + 1;
    return true;
  }
  if (response.size() < request.payload.size())
    return false;
  std::ranges::copy(request.payload, response.begin());
  written = request.payload.size();
  return true;
}

struct DynamicFixture {
  definitions::TrustedDefinitionRegistry registry;
  definitions::DynamicRevisionGrant grant;
  runtime::DynamicRoute route;
  DynamicProbe probe;

  explicit DynamicFixture(definitions::RevocationPolicy revocation =
                              definitions::RevocationPolicy::cancel_inflight) {
    definitions::CapabilityDefinition definition{
        .canonical_name = definitions::Name("fixture.echo"),
        .authority_identity = definitions::Name("fixture.echo-v1"),
        .enforcement_family = definitions::EnforcementFamily::network_fetch,
        .display_category_id = definitions::Name("fixture"),
        .display_category_label = definitions::Label("Fixture"),
        .scope_schema = definitions::ScopeSchema::https_origins_and_methods,
        .title = definitions::Label("Echo"),
        .risk_text = definitions::Label("Bounded echo"),
        .risk = definitions::RiskLevel::low,
        .revocation = revocation,
        .audit = {},
        .adapter = {.adapter_class = definitions::Name("fixture-adapter"),
                    .contract_digest = digest('d'),
                    .abi_version = 1},
        .operations = {}};
    require(definition.operations.insert({.name = definitions::Name("echo"),
                                          .label = definitions::Label("Echo")}),
            "dynamic operation fixture failed");
    require(registry.install(definition,
                             definitions::DefinitionSource::omarchy_package, 1),
            "dynamic definition fixture failed");
    const auto resolved = registry.find("fixture.echo");
    require(resolved.has_value(), "dynamic definition did not resolve");
    const definitions::CapabilityReference reference{
        .canonical_name = definitions::Name("fixture.echo"),
        .definition_generation = 1,
        .definition_digest = resolved->digest};
    grant = {.binding = binding(),
             .request = {.definition = reference,
                         .operations = {},
                         .scope = definitions::CanonicalScope("exact"),
                         .required = true},
             .grant = {.definition = reference,
                       .operations = {},
                       .scope = definitions::CanonicalScope("exact"),
                       .state = permissions::GrantState::granted,
                       .epoch = 6}};
    require(grant.request.operations.insert(definitions::Name("echo")) &&
                grant.grant.operations.insert(definitions::Name("echo")),
            "dynamic grant operation fixture failed");
    route = {.grant = grant,
             .adapter = {.binding = definition.adapter,
                         .dispatch = dynamic_dispatch,
                         .context = &probe},
             .scope_validator = {.compare = exact_scope, .context = nullptr}};
  }

  std::vector<std::byte> invocation(std::span<const std::byte> body) const {
    const definitions::DynamicInvocation value{
        .definition = grant.request.definition,
        .operation = definitions::Name("echo"),
        .demand_scope = definitions::CanonicalScope("exact"),
        .gesture = std::nullopt,
        .payload = body};
    std::vector<std::byte> encoded(definitions::kMaximumDynamicEnvelopeBytes);
    std::size_t written = 0;
    require(definitions::encode_dynamic_invocation(value, encoded, written),
            "dynamic invocation encoding failed");
    encoded.resize(written);
    return encoded;
  }
};

class TestAuthority final : public DispatchAuthority {
public:
  TestAuthority(permissions::ActivationBinding binding,
                std::uint64_t session_nonce)
      : binding_(std::move(binding)), session_nonce_(session_nonce) {}

  class Lease final : public DispatchAuthorityLease {
  public:
    explicit Lease(TestAuthority &authority) : authority_(authority) {}
    ~Lease() override {
      std::lock_guard lock(authority_.mutex_);
      --authority_.active_;
      authority_.condition_.notify_all();
    }
    bool current_at_effect() const noexcept override {
      std::lock_guard lock(authority_.mutex_);
      return authority_.accepting_;
    }

  private:
    TestAuthority &authority_;
  };

  std::unique_ptr<DispatchAuthorityLease>
  acquire(const permissions::ActivationBinding &binding,
          std::uint64_t session_nonce, const wire::PacketView &) override {
    std::lock_guard lock(mutex_);
    if (throw_on_acquire_)
      throw std::runtime_error("injected authority failure");
    if (!accepting_ || binding != binding_ || session_nonce != session_nonce_)
      return {};
    ++active_;
    return std::make_unique<Lease>(*this);
  }

  bool fence_builtin(const policy::Revocation &) noexcept override {
    std::unique_lock lock(mutex_);
    accepting_ = false;
    condition_.wait(lock, [&] { return active_ == 0; });
    return true;
  }

  bool
  fence_dynamic(const definitions::DynamicRevisionGrant &) noexcept override {
    std::unique_lock lock(mutex_);
    if (reject_dynamic_fence_)
      return false;
    accepting_ = false;
    condition_.wait(lock, [&] { return active_ == 0; });
    return true;
  }

  void throw_on_acquire(bool value) noexcept { throw_on_acquire_ = value; }
  void reject_dynamic_fence(bool value) noexcept {
    reject_dynamic_fence_ = value;
  }

private:
  permissions::ActivationBinding binding_;
  std::uint64_t session_nonce_ = 0;
  std::mutex mutex_;
  std::condition_variable condition_;
  std::size_t active_ = 0;
  bool accepting_ = true;
  bool throw_on_acquire_ = false;
  bool reject_dynamic_fence_ = false;
};

class ThrowingAudit final : public audit::AuditSink {
public:
  explicit ThrowingAudit(std::size_t throw_on) : throw_on_(throw_on) {}

  audit::AppendResult append(permissions::AuditProducer producer,
                             permissions::AuditDraft draft) override {
    if (++calls_ == throw_on_)
      throw std::runtime_error("injected audit failure");
    return backing_.append(producer, std::move(draft));
  }

private:
  std::size_t throw_on_ = 0;
  std::size_t calls_ = 0;
  audit::BoundedAuditLog backing_;
};

struct RuntimeFixture {
  static constexpr std::uint64_t session_nonce = 19;
  audit::BoundedAuditLog audit_log;
  AudioProbe audio_probe;
  DynamicFixture dynamic_fixture;
  policy::GrantSnapshot snapshot = builtin_snapshot();
  runtime::AuditedBrokerRuntime builtin;
  runtime::DynamicBrokerRuntime dynamic;
  TestAuthority authority;
  StructuredBroker broker_mux;
  AuthenticatedBrokerAdmission admission;

  explicit RuntimeFixture(definitions::RevocationPolicy dynamic_revocation =
                              definitions::RevocationPolicy::cancel_inflight)
      : dynamic_fixture(dynamic_revocation),
        builtin(snapshot,
                providers::ProviderConfiguration{
                    .binding = {},
                    .storage_epoch = 0,
                    .notification_epoch = 0,
                    .audio_epoch = 0,
                    .storage = {},
                    .notification = {},
                    .audio = {.play = play, .context = &audio_probe}},
                audit_log),
        dynamic(dynamic_fixture.registry, {dynamic_fixture.route}, audit_log),
        authority(snapshot.binding, session_nonce),
        broker_mux(snapshot.binding, session_nonce, builtin, dynamic,
                   authority),
        admission(extract_admission(broker_mux)) {}

  BrokerTransaction dispatch(AuthenticatedBrokerRequestView value,
                             std::span<std::byte> response) {
    auto admitted = admission.admit(value);
    require(static_cast<bool>(admitted), "valid request was not admitted");
    return broker_mux.dispatch(std::move(*admitted.request), 100, response);
  }
};

struct ThrowingRuntimeFixture {
  static constexpr std::uint64_t session_nonce = 29;
  ThrowingAudit audit_sink;
  AudioProbe audio_probe;
  DynamicFixture dynamic_fixture;
  policy::GrantSnapshot snapshot = builtin_snapshot();
  runtime::AuditedBrokerRuntime builtin;
  runtime::DynamicBrokerRuntime dynamic;
  TestAuthority authority;
  StructuredBroker broker_mux;
  AuthenticatedBrokerAdmission admission;

  explicit ThrowingRuntimeFixture(std::size_t throw_on)
      : audit_sink(throw_on),
        builtin(snapshot,
                providers::ProviderConfiguration{
                    .binding = {},
                    .storage_epoch = 0,
                    .notification_epoch = 0,
                    .audio_epoch = 0,
                    .storage = {},
                    .notification = {},
                    .audio = {.play = play, .context = &audio_probe}},
                audit_sink),
        dynamic(dynamic_fixture.registry, {dynamic_fixture.route}, audit_sink),
        authority(snapshot.binding, session_nonce),
        broker_mux(snapshot.binding, session_nonce, builtin, dynamic,
                   authority),
        admission(extract_admission(broker_mux)) {}

  BrokerTransaction dispatch(AuthenticatedBrokerRequestView value,
                             std::span<std::byte> response) {
    auto admitted = admission.admit(value);
    require(static_cast<bool>(admitted),
            "throwing-runtime request was not admitted");
    return broker_mux.dispatch(std::move(*admitted.request), 100, response);
  }
};

void test_constructor_validates_dynamic_binding() {
  audit::BoundedAuditLog audit_log;
  AudioProbe audio_probe;
  DynamicFixture dynamic_fixture;
  auto snapshot = builtin_snapshot();
  runtime::AuditedBrokerRuntime builtin(
      snapshot,
      providers::ProviderConfiguration{
          .binding = {},
          .storage_epoch = 0,
          .notification_epoch = 0,
          .audio_epoch = 0,
          .storage = {},
          .notification = {},
          .audio = {.play = play, .context = &audio_probe}},
      audit_log);
  runtime::DynamicBrokerRuntime empty_dynamic(dynamic_fixture.registry, {},
                                              audit_log);
  TestAuthority empty_authority(snapshot.binding, 41);
  StructuredBroker builtin_only(snapshot.binding, 41, builtin, empty_dynamic,
                                empty_authority);
  require(static_cast<bool>(builtin_only.take_admission()),
          "built-in-only broker did not admit its channel");

  auto foreign_route = dynamic_fixture.route;
  ++foreign_route.grant.binding.generation;
  runtime::DynamicBrokerRuntime foreign_dynamic(dynamic_fixture.registry,
                                                {foreign_route}, audit_log);
  TestAuthority foreign_authority(snapshot.binding, 42);
  bool rejected = false;
  try {
    StructuredBroker mismatched(snapshot.binding, 42, builtin, foreign_dynamic,
                                foreign_authority);
    (void)mismatched;
  } catch (const std::invalid_argument &) {
    rejected = true;
  }
  require(rejected,
          "nonempty mismatched dynamic runtime reached admission extraction");
}

void test_typed_dynamic_revocation_results() {
  {
    RuntimeFixture fixture;
    auto revoked = fixture.dynamic_fixture.grant;
    revoked.grant.state = permissions::GrantState::revoked;
    ++revoked.grant.epoch;
    const auto result = fixture.broker_mux.apply_dynamic_update(revoked);
    require(result.status == runtime::DynamicRevocationStatus::accepted &&
                !result.restart_worker,
            "cancel-inflight dynamic revocation lost its typed result");
  }
  {
    RuntimeFixture fixture(definitions::RevocationPolicy::restart_worker);
    auto revoked = fixture.dynamic_fixture.grant;
    revoked.grant.state = permissions::GrantState::revoked;
    ++revoked.grant.epoch;
    const auto result = fixture.broker_mux.apply_dynamic_update(revoked);
    require(result.status == runtime::DynamicRevocationStatus::accepted &&
                result.restart_worker,
            "restart-worker dynamic revocation lost its typed result");
  }
  {
    RuntimeFixture fixture;
    fixture.authority.reject_dynamic_fence(true);
    auto revoked = fixture.dynamic_fixture.grant;
    revoked.grant.state = permissions::GrantState::revoked;
    ++revoked.grant.epoch;
    const auto rejected = fixture.broker_mux.apply_dynamic_update(revoked);
    require(rejected.status ==
                runtime::DynamicRevocationStatus::binding_mismatch,
            "dynamic fence rejection did not preserve typed status");
    const std::array body{std::byte{0x61}};
    const auto invocation = fixture.dynamic_fixture.invocation(body);
    std::array<std::byte, 64> response{};
    auto transaction = fixture.dispatch(
        request(broker::kDynamicInvokeMessage, 1, invocation), response);
    require(transaction.state() == TransactionState::reply &&
                transaction.reply_kind() == ReplyKind::result &&
                fixture.broker_mux.commit_sent(std::move(transaction)),
            "dynamic fence rejection changed broker or route state");
  }
}

void test_admission_is_exact_and_destructive() {
  RuntimeFixture fixture;
  const auto second = fixture.broker_mux.take_admission();
  require(!second &&
              second.failure == AdmissionExtractionFailure::already_extracted,
          "broker minted a second replay watermark authority");
  const auto denied_payload =
      token_request(permissions::OperationId::notification_send, "timer");
  const auto value = request(
      static_cast<std::uint16_t>(permissions::OperationId::notification_send),
      1, denied_payload);
  auto admitted = fixture.admission.admit(value);
  require(static_cast<bool>(admitted), "first correlation was rejected");
  const std::array dynamic_body{std::byte{0x23}};
  const auto dynamic_payload = fixture.dynamic_fixture.invocation(dynamic_body);
  require(
      fixture.admission
              .admit(request(broker::kDynamicInvokeMessage, 1, dynamic_payload))
              .failure == AdmissionFailure::replay,
      "one correlation watermark was not shared across broker routes");
  require(fixture.admission.admit(value).failure == AdmissionFailure::replay,
          "replayed correlation was admitted");
  std::array<std::byte, 64> response{};
  auto first =
      fixture.broker_mux.dispatch(std::move(*admitted.request), 100, response);
  require(first.state() == TransactionState::reply &&
              first.reply_kind() == ReplyKind::denied,
          "first admitted request did not dispatch");
  auto moved_replay =
      fixture.broker_mux.dispatch(std::move(*admitted.request), 100, response);
  require(moved_replay.state() == TransactionState::fatal &&
              moved_replay.fatal() == DispatchFatal::admission_reused &&
              moved_replay.provider_response_bytes() == 0,
          "moved-from admitted request remained usable");
  require(fixture.broker_mux.abort_send(std::move(first)),
          "test denial transaction did not abort cleanly");

  RuntimeFixture foreign;
  auto crossed = foreign.admission.admit(request(
      static_cast<std::uint16_t>(permissions::OperationId::notification_send),
      2, denied_payload));
  require(static_cast<bool>(crossed), "cross-binding fixture was not admitted");
  auto rejected =
      fixture.broker_mux.dispatch(std::move(*crossed.request), 100, response);
  require(rejected.fatal() == DispatchFatal::identity_mismatch,
          "same-identity foreign admission was accepted");
  auto accepted =
      foreign.broker_mux.dispatch(std::move(*crossed.request), 100, response);
  require(accepted.state() == TransactionState::reply &&
              foreign.broker_mux.commit_sent(std::move(accepted)),
          "foreign rejection consumed the legitimate admission");

}

void test_authenticated_semantics_are_privately_stamped() {
  RuntimeFixture fixture;
  require(fixture.broker_mux.accepts(fixture.snapshot.binding, 19) &&
              !fixture.broker_mux.accepts(fixture.snapshot.binding, 20),
          "structured broker did not bind the exact session nonce");
  auto foreign = fixture.snapshot.binding;
  ++foreign.generation;
  require(!fixture.broker_mux.accepts(foreign, 19),
          "structured broker accepted a foreign activation binding");

  const auto payload =
      token_request(permissions::OperationId::notification_send, "timer");
  auto admitted = fixture.admission.admit(
      {.message_type = static_cast<std::uint16_t>(
           permissions::OperationId::notification_send),
       .correlation_id = 1,
       .payload = payload});
  require(admitted &&
              fixture.admission
                      .admit(request(broker::kDynamicInvokeMessage, 1, {}))
                      .failure == AdmissionFailure::replay,
          "semantic admission did not share its opaque replay watermark");
  std::array<std::byte, 64> response{};
  auto transaction =
      fixture.broker_mux.dispatch(std::move(*admitted.request), 100, response);
  require(transaction.state() == TransactionState::reply &&
              transaction.reply_kind() == ReplyKind::denied &&
              fixture.broker_mux.abort_send(std::move(transaction)),
          "privately stamped semantic request did not dispatch");

  RuntimeFixture invalid;
  std::vector<std::byte> oversized(
      wire::payload_cap(wire::EndpointRole::broker) + 1);
  require(
      invalid.admission
                  .admit(
                      {.message_type = 0, .correlation_id = 1, .payload = {}})
                  .failure == AdmissionFailure::invalid_message_type &&
          invalid.admission
                  .admit(
                      {.message_type = broker::kDynamicInvokeMessage,
                       .correlation_id = 0,
                       .payload = {}})
                  .failure == AdmissionFailure::invalid_correlation &&
          invalid.admission
                  .admit(
                      {.message_type = broker::kDynamicInvokeMessage,
                       .correlation_id = 1,
                       .payload = oversized})
                  .failure == AdmissionFailure::malformed_length,
      "semantic admission accepted zero or oversized authority fields");

  RuntimeFixture failed;
  failed.authority.throw_on_acquire(true);
  auto failed_request = failed.admission.admit(
      {.message_type = broker::kDynamicInvokeMessage,
       .correlation_id = 1,
       .payload = {}});
  auto fatal =
      failed.broker_mux.dispatch(std::move(*failed_request.request), 100,
                                 response);
  require(fatal.state() == TransactionState::fatal &&
              !failed.broker_mux.accepts(failed.snapshot.binding,
                                         RuntimeFixture::session_nonce),
          "fail-stopped broker retained composition authority");
}

void test_reply_is_owned_and_committed_only_after_send() {
  RuntimeFixture fixture;
  std::array<std::byte, 64> response{};
  const auto allowed_payload =
      token_request(permissions::OperationId::audio_play_cue, "complete");
  auto transaction =
      fixture.dispatch(request(static_cast<std::uint16_t>(
                                  permissions::OperationId::audio_play_cue),
                              1, allowed_payload),
                       response);
  require(transaction.state() == TransactionState::reply &&
              transaction.reply_kind() == ReplyKind::result &&
              transaction.message_type() == broker::kBrokerResultMessage &&
              transaction.provider_response_bytes() == 0 &&
              !transaction.settled() && fixture.audio_probe.calls == 1,
          "allowed reply transaction has inconsistent state");
  response.fill(std::byte{0xff});
  require(transaction.wire_payload().empty(),
          "zero-byte provider reply did not remain independently owned");
  require(fixture.broker_mux.commit_sent(std::move(transaction)) &&
              transaction.settled() &&
              !fixture.broker_mux.commit_sent(std::move(transaction)),
          "reply commit was not destructive and one-use");
}

void test_request_move_owns_payload_and_invalidates_source() {
  RuntimeFixture fixture;
  std::array<std::byte, 64> response{};
  auto request_payload =
      token_request(permissions::OperationId::audio_play_cue, "complete");
  auto admitted = fixture.admission.admit(request(
      static_cast<std::uint16_t>(permissions::OperationId::audio_play_cue), 1,
      request_payload));
  require(static_cast<bool>(admitted), "owned request was not admitted");
  AdmittedBrokerRequest moved(std::move(*admitted.request));
  request_payload.assign(request_payload.size(), std::byte{0xff});
  const auto moved_from =
      fixture.broker_mux.dispatch(std::move(*admitted.request), 100, response);
  require(moved_from.fatal() == DispatchFatal::admission_reused,
          "moved-from admission remained usable");
  auto transaction =
      fixture.broker_mux.dispatch(std::move(moved), 100, response);
  require(transaction.state() == TransactionState::reply &&
              transaction.reply_kind() == ReplyKind::result &&
              fixture.broker_mux.commit_sent(std::move(transaction)),
          "admitted request did not own its exact payload bytes");
}

void test_transaction_move_and_foreign_settlement_are_destructive() {
  {
    RuntimeFixture fixture;
    std::array<std::byte, 64> response{};
    const auto payload =
        token_request(permissions::OperationId::audio_play_cue, "complete");
    auto original =
        fixture.dispatch(request(static_cast<std::uint16_t>(
                                    permissions::OperationId::audio_play_cue),
                                1, payload),
                         response);
    BrokerTransaction moved(std::move(original));
    require(original.settled() &&
                !fixture.broker_mux.commit_sent(std::move(original)) &&
                fixture.broker_mux.commit_sent(std::move(moved)),
            "transaction move did not transfer one-use settlement authority");
  }

  const auto payload =
      token_request(permissions::OperationId::audio_play_cue, "complete");
  {
    RuntimeFixture owner;
    RuntimeFixture foreign;
    std::array<std::byte, 64> owner_response{};
    std::array<std::byte, 64> foreign_response{};
    auto transaction =
        owner.dispatch(request(static_cast<std::uint16_t>(
                                  permissions::OperationId::audio_play_cue),
                              1, payload),
                       owner_response);
    require(!foreign.broker_mux.commit_sent(std::move(transaction)) &&
                !transaction.settled() && !owner.builtin.failed() &&
                !foreign.builtin.failed(),
            "foreign commit consumed a transaction or touched a runtime");
    require(owner.broker_mux.commit_sent(std::move(transaction)),
            "foreign commit rejection consumed the legitimate transaction");
    auto foreign_transaction =
        foreign.dispatch(request(static_cast<std::uint16_t>(
                                    permissions::OperationId::audio_play_cue),
                                1, payload),
                         foreign_response);
    require(foreign_transaction.state() == TransactionState::reply &&
                foreign.broker_mux.commit_sent(std::move(foreign_transaction)),
            "foreign commit rejection corrupted the foreign broker");
  }
  {
    RuntimeFixture owner;
    RuntimeFixture foreign;
    std::array<std::byte, 64> owner_response{};
    std::array<std::byte, 64> foreign_response{};
    auto transaction =
        owner.dispatch(request(static_cast<std::uint16_t>(
                                  permissions::OperationId::audio_play_cue),
                              1, payload),
                       owner_response);
    require(!foreign.broker_mux.abort_send(std::move(transaction)) &&
                !transaction.settled() && !owner.builtin.failed() &&
                !foreign.builtin.failed(),
            "foreign abort consumed a transaction or touched a runtime");
    require(owner.broker_mux.commit_sent(std::move(transaction)),
            "foreign abort rejection consumed the legitimate transaction");
    auto foreign_transaction =
        foreign.dispatch(request(static_cast<std::uint16_t>(
                                    permissions::OperationId::audio_play_cue),
                                1, payload),
                         foreign_response);
    require(foreign_transaction.state() == TransactionState::reply &&
                foreign.broker_mux.commit_sent(std::move(foreign_transaction)),
            "foreign abort rejection corrupted the foreign broker");
  }
}

void test_send_failure_aborts_without_fake_terminal() {
  RuntimeFixture fixture;
  std::array<std::byte, 64> response{};
  const auto allowed_payload =
      token_request(permissions::OperationId::audio_play_cue, "complete");
  auto transaction =
      fixture.dispatch(request(static_cast<std::uint16_t>(
                                  permissions::OperationId::audio_play_cue),
                              1, allowed_payload),
                       response);
  require(transaction.state() == TransactionState::reply &&
              !transaction.settled(),
          "send-failure fixture did not prepare a reply");
  require(fixture.broker_mux.abort_send(std::move(transaction)) &&
              transaction.settled() &&
              !fixture.broker_mux.abort_send(std::move(transaction)),
          "send failure did not fail-stop the built-in runtime once");
  auto next = fixture.admission.admit(request(
      static_cast<std::uint16_t>(permissions::OperationId::audio_play_cue), 2,
      allowed_payload));
  require(static_cast<bool>(next), "post-abort admission fixture failed");
  const auto failed =
      fixture.broker_mux.dispatch(std::move(*next.request), 100, response);
  require(failed.fatal() == DispatchFatal::runtime_failed,
          "runtime continued after an unsent provider effect");
}

void test_dynamic_operation_and_oversize_are_bounded() {
  RuntimeFixture fixture;
  const std::array body{std::byte{0x45}};
  auto invocation = fixture.dynamic_fixture.invocation(body);
  std::array<std::byte, 8> response{};
  auto result = fixture.dispatch(
      request(broker::kDynamicInvokeMessage, 1, invocation), response);
  require(result.state() == TransactionState::reply &&
              result.reply_kind() == ReplyKind::result &&
              result.provider_response_bytes() == 1 &&
              result.wire_payload().size() == 1 &&
              result.wire_payload()[0] == body[0],
          "dynamic operation did not produce an owned exact reply");
  require(fixture.broker_mux.commit_sent(std::move(result)),
          "dynamic result did not settle after confirmed send");

  fixture.dynamic_fixture.probe.oversize = true;
  invocation = fixture.dynamic_fixture.invocation(body);
  auto oversized_result = fixture.dispatch(
      request(broker::kDynamicInvokeMessage, 2, invocation), response);
  require(oversized_result.state() == TransactionState::reply &&
              oversized_result.reply_kind() == ReplyKind::provider_failed &&
              oversized_result.provider_response_bytes() == 0 &&
              oversized_result.wire_payload().size() ==
                  broker::kBrokerErrorBytes,
          "oversize dynamic adapter leaked an out-of-range byte count");
}

void test_dynamic_send_failure_fail_stops_without_later_effect() {
  RuntimeFixture fixture;
  const std::array body{std::byte{0x46}};
  const auto invocation = fixture.dynamic_fixture.invocation(body);
  std::array<std::byte, 8> response{};
  auto transaction = fixture.dispatch(
      request(broker::kDynamicInvokeMessage, 1, invocation), response);
  require(transaction.state() == TransactionState::reply &&
              fixture.dynamic_fixture.probe.calls == 1 &&
              !fixture.broker_mux.abort_send(std::move(transaction)) &&
              transaction.settled() &&
              !fixture.broker_mux.accepts(fixture.snapshot.binding,
                                          RuntimeFixture::session_nonce),
          "unsent dynamic effect did not fail-stop broker composition");
  auto after_abort = fixture.admission.admit(
      request(broker::kDynamicInvokeMessage, 2, invocation));
  require(static_cast<bool>(after_abort),
          "dynamic abort fixture could not admit the follow-up request");
  const auto failed = fixture.broker_mux.dispatch(
      std::move(*after_abort.request), 100, response);
  require(failed.fatal() == DispatchFatal::runtime_failed &&
              fixture.dynamic_fixture.probe.calls == 1,
          "dynamic abort failure allowed a later adapter effect");
}

void test_runtime_audit_exceptions_fail_closed() {
  const auto payload =
      token_request(permissions::OperationId::audio_play_cue, "complete");
  {
    ThrowingRuntimeFixture fixture(2);
    std::array<std::byte, 64> response{};
    auto transaction =
        fixture.dispatch(request(static_cast<std::uint16_t>(
                                    permissions::OperationId::audio_play_cue),
                                1, payload),
                         response);
    require(transaction.state() == TransactionState::reply &&
                !fixture.broker_mux.commit_sent(std::move(transaction)) &&
                transaction.settled(),
            "throwing terminal audit escaped or remained replayable");
    auto after_failure =
        fixture.dispatch(request(static_cast<std::uint16_t>(
                                    permissions::OperationId::audio_play_cue),
                                2, payload),
                         response);
    require(after_failure.fatal() == DispatchFatal::runtime_failed &&
                fixture.audio_probe.calls == 1,
            "terminal audit failure allowed a further provider effect");
  }
  {
    ThrowingRuntimeFixture fixture(1);
    std::array<std::byte, 64> response{};
    const std::array body{std::byte{0x31}};
    const auto invocation = fixture.dynamic_fixture.invocation(body);
    auto failed = fixture.dispatch(
        request(broker::kDynamicInvokeMessage, 1, invocation), response);
    require(failed.fatal() == DispatchFatal::runtime_failed &&
                fixture.dynamic_fixture.probe.calls == 0,
            "throwing dynamic audit escaped or reached its adapter");
    auto replay = fixture.dispatch(
        request(broker::kDynamicInvokeMessage, 2, invocation), response);
    require(replay.fatal() == DispatchFatal::runtime_failed &&
                fixture.dynamic_fixture.probe.calls == 0,
            "dynamic audit failure allowed a later adapter effect");
  }
  {
    ThrowingRuntimeFixture fixture(2);
    std::array<std::byte, 64> response{};
    auto transaction =
        fixture.dispatch(request(static_cast<std::uint16_t>(
                                    permissions::OperationId::audio_play_cue),
                                1, payload),
                         response);
    require(transaction.state() == TransactionState::reply &&
                !fixture.broker_mux.abort_send(std::move(transaction)) &&
                transaction.settled(),
            "throwing shutdown audit escaped or remained replayable");
    auto after_failure =
        fixture.dispatch(request(static_cast<std::uint16_t>(
                                    permissions::OperationId::audio_play_cue),
                                2, payload),
                         response);
    require(after_failure.fatal() == DispatchFatal::runtime_failed &&
                fixture.audio_probe.calls == 1,
            "shutdown audit failure allowed a further provider effect");
  }
  {
    ThrowingRuntimeFixture fixture(1);
    auto revoked = fixture.dynamic_fixture.grant;
    revoked.grant.state = permissions::GrantState::revoked;
    ++revoked.grant.epoch;
    require(fixture.broker_mux.apply_dynamic_update(revoked).status ==
                runtime::DynamicRevocationStatus::audit_failed,
            "throwing dynamic update audit escaped the broker seam");
    require(fixture.broker_mux.apply_dynamic_update(revoked).status ==
                runtime::DynamicRevocationStatus::failed,
            "failed dynamic broker did not return typed failed status");
    std::array<std::byte, 64> response{};
    const std::array body{std::byte{0x32}};
    const auto invocation = fixture.dynamic_fixture.invocation(body);
    const auto after_failure = fixture.dispatch(
        request(broker::kDynamicInvokeMessage, 1, invocation), response);
    require(after_failure.fatal() == DispatchFatal::runtime_failed &&
                fixture.dynamic_fixture.probe.calls == 0,
            "dynamic update audit failure allowed an adapter effect");
  }
  {
    RuntimeFixture fixture;
    auto foreign = fixture.dynamic_fixture.grant;
    ++foreign.binding.generation;
    foreign.grant.state = permissions::GrantState::revoked;
    ++foreign.grant.epoch;
    require(fixture.broker_mux.apply_dynamic_update(foreign).status ==
                runtime::DynamicRevocationStatus::binding_mismatch,
            "foreign dynamic binding was accepted");
    std::array<std::byte, 64> response{};
    const std::array body{std::byte{0x33}};
    const auto invocation = fixture.dynamic_fixture.invocation(body);
    const auto after_failure = fixture.dispatch(
        request(broker::kDynamicInvokeMessage, 1, invocation), response);
    require(after_failure.fatal() == DispatchFatal::runtime_failed &&
                fixture.dynamic_fixture.probe.calls == 0,
            "dynamic binding mismatch did not fail closed");
  }
}

void test_authority_exception_fails_closed_before_provider_effect() {
  RuntimeFixture fixture;
  fixture.authority.throw_on_acquire(true);
  std::array<std::byte, 64> response{};
  const auto payload =
      token_request(permissions::OperationId::audio_play_cue, "complete");
  const auto failed =
      fixture.dispatch(request(static_cast<std::uint16_t>(
                                  permissions::OperationId::audio_play_cue),
                              1, payload),
                       response);
  require(failed.fatal() == DispatchFatal::runtime_failed &&
              fixture.audio_probe.calls == 0 && fixture.builtin.failed(),
          "authority exception did not fail-stop before provider effect");
  fixture.authority.throw_on_acquire(false);
  const auto after_failure =
      fixture.dispatch(request(static_cast<std::uint16_t>(
                                  permissions::OperationId::audio_play_cue),
                              2, payload),
                       response);
  require(after_failure.fatal() == DispatchFatal::runtime_failed &&
              fixture.audio_probe.calls == 0,
          "authority exception left the broker reusable");
}

void test_invalid_builtin_authority_is_rejected() {
  auto zero = builtin_snapshot();
  zero.grants[0].epoch = 0;
  audit::BoundedAuditLog zero_audit;
  bool rejected = false;
  try {
    runtime::AuditedBrokerRuntime invalid(
        zero, providers::ProviderConfiguration{}, zero_audit);
    (void)invalid;
  } catch (...) {
    rejected = true;
  }
  require(rejected, "zero-epoch built-in authority was accepted");

  auto duplicate = builtin_snapshot();
  duplicate.grants.push_back(duplicate.grants[0]);
  audit::BoundedAuditLog duplicate_audit;
  rejected = false;
  try {
    runtime::AuditedBrokerRuntime invalid(
        duplicate, providers::ProviderConfiguration{}, duplicate_audit);
    (void)invalid;
  } catch (...) {
    rejected = true;
  }
  require(rejected, "duplicate built-in authority was accepted");
}

void test_dispatch_lease_serializes_revocation() {
  RuntimeFixture fixture;
  fixture.audio_probe.block = true;
  const auto request_payload =
      token_request(permissions::OperationId::audio_play_cue, "complete");
  const auto request_view = request(
      static_cast<std::uint16_t>(permissions::OperationId::audio_play_cue), 1,
      request_payload);
  auto admitted = fixture.admission.admit(request_view);
  require(static_cast<bool>(admitted), "lease fixture admission failed");
  std::array<std::byte, 64> response{};
  std::optional<BrokerTransaction> dispatch_result;
  std::thread dispatch_thread([&] {
    dispatch_result.emplace(fixture.broker_mux.dispatch(
        std::move(*admitted.request), 100, response));
  });
  {
    std::unique_lock lock(fixture.audio_probe.mutex);
    require(fixture.audio_probe.condition.wait_for(
                lock, std::chrono::seconds(2),
                [&] { return fixture.audio_probe.entered; }),
            "provider did not enter for revocation race");
  }

  const auto current = fixture.snapshot.grants[0];
  const policy::Revocation revocation{
      .sequence = 1,
      .slot = policy::RevisionSlot::active,
      .grant = {.capability = current.capability,
                .scope = current.scope,
                .state = permissions::GrantState::revoked,
                .epoch = current.epoch + 1},
      .action = permissions::RevocationMode::deny_new,
      .fingerprint = "race"};
  std::atomic<bool> revocation_returned = false;
  std::atomic<bool> revocation_started = false;
  runtime::RevocationResult revocation_result;
  std::thread revocation_thread([&] {
    revocation_started = true;
    revocation_result = fixture.broker_mux.apply_builtin_revocation(revocation);
    revocation_returned = true;
  });
  while (!revocation_started.load())
    std::this_thread::yield();
  std::this_thread::sleep_for(std::chrono::milliseconds(20));
  require(!revocation_returned.load(),
          "revocation landed between authorization and provider effect");
  {
    std::lock_guard lock(fixture.audio_probe.mutex);
    fixture.audio_probe.released = true;
  }
  fixture.audio_probe.condition.notify_all();
  dispatch_thread.join();
  revocation_thread.join();
  require(dispatch_result.has_value() &&
              dispatch_result->state() == TransactionState::reply &&
              dispatch_result->reply_kind() == ReplyKind::result &&
              revocation_result.status == runtime::RuntimeStatus::accepted,
          "dispatch lease did not release into ordered revocation");
  require(fixture.broker_mux.commit_sent(std::move(*dispatch_result)),
          "leased dispatch did not settle after send");
}

void test_provider_reentry_fails_without_deadlock() {
  RuntimeFixture fixture;
  std::array<std::byte, 64> outer_response{};
  std::array<std::byte, 64> inner_response{};
  const auto payload =
      token_request(permissions::OperationId::audio_play_cue, "complete");
  auto outer_admitted = fixture.admission.admit(request(
      static_cast<std::uint16_t>(permissions::OperationId::audio_play_cue), 1,
      payload));
  auto inner_admitted = fixture.admission.admit(request(
      static_cast<std::uint16_t>(permissions::OperationId::audio_play_cue), 2,
      payload));
  require(static_cast<bool>(outer_admitted) &&
              static_cast<bool>(inner_admitted),
          "reentry requests were not admitted in sequence");
  std::optional<BrokerTransaction> inner_result;
  fixture.audio_probe.reenter = [&] {
    inner_result.emplace(fixture.broker_mux.dispatch(
        std::move(*inner_admitted.request), 100, inner_response));
  };
  auto outer = fixture.broker_mux.dispatch(std::move(*outer_admitted.request),
                                           100, outer_response);
  require(inner_result.has_value() &&
              inner_result->fatal() == DispatchFatal::runtime_failed &&
              outer.state() == TransactionState::reply &&
              outer.reply_kind() == ReplyKind::result,
          "provider reentry deadlocked or escaped runtime busy guard");
  require(fixture.broker_mux.commit_sent(std::move(outer)),
          "outer reentry transaction did not commit");
}

void test_provider_revocation_reentry_is_rejected_without_waiting() {
  RuntimeFixture fixture;
  const auto current = fixture.snapshot.grants[0];
  const policy::Revocation revocation{
      .sequence = 1,
      .slot = policy::RevisionSlot::active,
      .grant = {.capability = current.capability,
                .scope = current.scope,
                .state = permissions::GrantState::revoked,
                .epoch = current.epoch + 1},
      .action = permissions::RevocationMode::deny_new,
      .fingerprint = "provider-reentry"};
  runtime::RevocationResult nested;
  bool returned = false;
  fixture.audio_probe.reenter = [&] {
    nested = fixture.broker_mux.apply_builtin_revocation(revocation);
    returned = true;
  };
  std::array<std::byte, 64> response{};
  const auto payload =
      token_request(permissions::OperationId::audio_play_cue, "complete");
  const auto started = std::chrono::steady_clock::now();
  auto transaction =
      fixture.dispatch(request(static_cast<std::uint16_t>(
                                  permissions::OperationId::audio_play_cue),
                              1, payload),
                       response);
  require(returned &&
              nested.status == runtime::RuntimeStatus::binding_mismatch &&
              std::chrono::steady_clock::now() - started <
                  std::chrono::milliseconds(100) &&
              transaction.state() == TransactionState::reply,
          "provider-thread revocation waited on its own dispatch lease");
  require(fixture.broker_mux.commit_sent(std::move(transaction)),
          "rejected nested revocation corrupted the outer dispatch");
}

void test_provider_dynamic_update_reentry_is_rejected_without_waiting() {
  RuntimeFixture fixture;
  auto updated = fixture.dynamic_fixture.grant;
  updated.grant.state = permissions::GrantState::revoked;
  ++updated.grant.epoch;
  runtime::DynamicRevocationResult nested_result;
  bool returned = false;
  fixture.audio_probe.reenter = [&] {
    nested_result = fixture.broker_mux.apply_dynamic_update(updated);
    returned = true;
  };
  std::array<std::byte, 64> response{};
  const auto payload =
      token_request(permissions::OperationId::audio_play_cue, "complete");
  const auto started = std::chrono::steady_clock::now();
  auto transaction =
      fixture.dispatch(request(static_cast<std::uint16_t>(
                                  permissions::OperationId::audio_play_cue),
                              1, payload),
                       response);
  require(returned &&
              nested_result.status ==
                  runtime::DynamicRevocationStatus::binding_mismatch &&
              std::chrono::steady_clock::now() - started <
                  std::chrono::milliseconds(100) &&
              transaction.state() == TransactionState::reply,
          "provider-thread dynamic update waited on its own dispatch lease");
  require(fixture.broker_mux.commit_sent(std::move(transaction)),
          "rejected nested dynamic update corrupted the outer dispatch");

  const std::array body{std::byte{0x51}};
  const auto invocation = fixture.dynamic_fixture.invocation(body);
  auto dynamic_result = fixture.dispatch(
      request(broker::kDynamicInvokeMessage, 2, invocation), response);
  require(dynamic_result.state() == TransactionState::reply &&
              dynamic_result.reply_kind() == ReplyKind::result &&
              fixture.broker_mux.commit_sent(std::move(dynamic_result)),
          "rejected nested dynamic update altered authority or route state");
}

void test_revocation_mode_is_preserved() {
  RuntimeFixture fixture;
  const auto current = fixture.snapshot.grants[0];
  const policy::Revocation revocation{
      .sequence = 1,
      .slot = policy::RevisionSlot::active,
      .grant = {.capability = current.capability,
                .scope = current.scope,
                .state = permissions::GrantState::revoked,
                .epoch = current.epoch + 1},
      .action = permissions::RevocationMode::deny_new,
      .fingerprint = "fixture"};
  const auto result = fixture.broker_mux.apply_builtin_revocation(revocation);
  require(result.status == runtime::RuntimeStatus::accepted &&
              !result.restart_worker && result.cancelled_count == 0,
          "deny-new revocation mode was not preserved");
}

} // namespace

int main() {
  try {
    test_constructor_validates_dynamic_binding();
    test_typed_dynamic_revocation_results();
    test_admission_is_exact_and_destructive();
    test_authenticated_semantics_are_privately_stamped();
    test_reply_is_owned_and_committed_only_after_send();
    test_request_move_owns_payload_and_invalidates_source();
    test_transaction_move_and_foreign_settlement_are_destructive();
    test_send_failure_aborts_without_fake_terminal();
    test_dynamic_operation_and_oversize_are_bounded();
    test_dynamic_send_failure_fail_stops_without_later_effect();
    test_runtime_audit_exceptions_fail_closed();
    test_authority_exception_fails_closed_before_provider_effect();
    test_invalid_builtin_authority_is_rejected();
    test_dispatch_lease_serializes_revocation();
    test_provider_reentry_fails_without_deadlock();
    test_provider_revocation_reentry_is_rejected_without_waiting();
    test_provider_dynamic_update_reentry_is_rejected_without_waiting();
    test_revocation_mode_is_preserved();
    std::cout << "structured broker composition tests passed\n";
    return EXIT_SUCCESS;
  } catch (const std::exception &error) {
    std::cerr << "structured broker composition test failed: " << error.what()
              << '\n';
    return EXIT_FAILURE;
  }
}
