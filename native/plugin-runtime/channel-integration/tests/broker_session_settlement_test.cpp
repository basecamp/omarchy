#include "audit_store.hpp"
#include "broker_session_settlement_p.hpp"
#include "omarchy/plugin_runtime/broker/broker_codec.hpp"

#include <deque>
#include <fcntl.h>
#include <iostream>
#include <stdexcept>
#include <unistd.h>

namespace channel = omarchy::plugin_runtime::channel;
namespace session = omarchy::plugin_runtime::host_session;
namespace runtime = omarchy::plugin_runtime::runtime;
namespace permissions = omarchy::plugins::permissions;
namespace definitions = omarchy::plugins::definitions;
namespace providers = omarchy::plugin_runtime::providers;
namespace broker = omarchy::plugin_runtime::broker;
namespace audit = omarchy::plugins::audit;
namespace wire = omarchy::plugin::wire;
namespace policy = omarchy::plugin_runtime::policy;
namespace launcher = omarchy::plugin_runtime::launcher;

namespace {
using namespace std::chrono_literals;
void require(bool value, const char *message) {
  if (!value)
    throw std::runtime_error(message);
}
permissions::Digest digest(char value) {
  return permissions::Digest(std::string(64, value));
}
permissions::TokenScope tokens() {
  permissions::TokenScope value;
  require(value.tokens.insert(permissions::ScopeToken("timer")),
          "duplicate token fixture");
  return value;
}
policy::GrantSnapshot revision(permissions::GrantState state) {
  policy::GrantSnapshot value;
  value.binding = {.plugin = permissions::PluginId("settlement.fixture"),
                   .revision = digest('a'),
                   .policy_fingerprint = digest('b'),
                   .generation = 7};
  value.requests.push_back(
      {.capability = {.id = permissions::CapabilityId("audio.play-cue"),
                      .version = 1},
       .scope = tokens(),
       .required = false});
  value.binding.policy_fingerprint = permissions::Digest(
      permissions::policy_request_fingerprint(value.requests));
  value.grants.push_back({.capability = value.requests[0].capability,
                          .scope = tokens(),
                          .state = state,
                          .epoch = 1});
  return value;
}
void put16(std::vector<std::byte> &bytes, std::size_t at, std::uint16_t value) {
  bytes[at] = static_cast<std::byte>(value >> 8U);
  bytes[at + 1] = static_cast<std::byte>(value);
}
void put32(std::vector<std::byte> &bytes, std::size_t at, std::uint32_t value) {
  for (std::size_t index = 0; index < 4; ++index)
    bytes[at + index] = static_cast<std::byte>(value >> ((3U - index) * 8U));
}
std::vector<std::byte> payload() {
  constexpr std::string_view token = "timer";
  std::vector<std::byte> bytes(10 + token.size());
  put16(bytes, 0,
        static_cast<std::uint16_t>(permissions::OperationId::audio_play_cue));
  put16(bytes, 2, static_cast<std::uint16_t>(2 + token.size()));
  put32(bytes, 4, 0);
  put16(bytes, 8, static_cast<std::uint16_t>(token.size()));
  for (std::size_t index = 0; index < token.size(); ++index)
    bytes[10 + index] = static_cast<std::byte>(token[index]);
  return bytes;
}
bool play(std::string_view cue, void *) noexcept { return cue == "timer"; }
providers::ProviderConfiguration provider_configuration() {
  providers::ProviderConfiguration configuration;
  configuration.audio.play = play;
  return configuration;
}
class Authority final : public session::DispatchAuthority {
  class Lease final : public session::DispatchAuthorityLease {
    bool current_at_effect() const noexcept override { return true; }
  };
  std::unique_ptr<session::DispatchAuthorityLease>
  acquire(const permissions::ActivationBinding &, std::uint64_t,
          const wire::PacketView &) override {
    return std::make_unique<Lease>();
  }
  bool fence_builtin(const policy::Revocation &) noexcept override {
    return true;
  }
  bool
  fence_dynamic(const definitions::DynamicRevisionGrant &) noexcept override {
    return true;
  }
};
struct TransportState {
  std::deque<channel::ChannelSendStatus> sends;
  std::vector<std::byte> bytes;
  std::uint16_t message_type = 0;
  std::uint64_t correlation = 0;
  unsigned prepares = 0;
  unsigned attempts = 0;
  bool throw_prepare = false;
  bool reject_prepare = false;
  bool throw_send = false;
  bool prepared = false;
  unsigned sleep_microseconds = 0;
  unsigned prepare_sleep_microseconds = 0;
};
class FakeTransport final : public channel::BrokerReplyTransport {
public:
  explicit FakeTransport(std::shared_ptr<TransportState> state)
      : state_(std::move(state)) {}
  bool prepare(std::uint16_t message_type, std::uint64_t correlation,
               std::span<const std::byte> bytes) override {
    ++state_->prepares;
    if (state_->throw_prepare)
      throw std::runtime_error("prepare");
    if (state_->prepare_sleep_microseconds != 0)
      usleep(state_->prepare_sleep_microseconds);
    if (state_->reject_prepare)
      return false;
    if (state_->prepared)
      return false;
    state_->prepared = true;
    state_->message_type = message_type;
    state_->correlation = correlation;
    state_->bytes.assign(bytes.begin(), bytes.end());
    return true;
  }
  channel::ChannelSendStatus try_send(launcher::Deadline) override {
    ++state_->attempts;
    if (state_->throw_send)
      throw std::runtime_error("send");
    if (state_->sleep_microseconds != 0)
      usleep(state_->sleep_microseconds);
    const auto result = state_->sends.empty()
                            ? channel::ChannelSendStatus::complete
                            : state_->sends.front();
    if (!state_->sends.empty())
      state_->sends.pop_front();
    if (result != channel::ChannelSendStatus::would_block)
      state_->prepared = false;
    return result;
  }
  void clear() noexcept override { state_->prepared = false; }

private:
  std::shared_ptr<TransportState> state_;
};
struct Fixture {
  audit::BoundedAuditLog log;
  policy::GrantSnapshot snapshot;
  runtime::AuditedBrokerRuntime builtin;
  definitions::TrustedDefinitionRegistry registry;
  runtime::DynamicBrokerRuntime dynamic;
  Authority authority;
  session::StructuredBroker broker;
  std::shared_ptr<TransportState> transport =
      std::make_shared<TransportState>();
  channel::BrokerSessionSettlement settlement;
  explicit Fixture(permissions::GrantState state =
                       permissions::GrantState::granted)
      : snapshot(revision(state)),
        builtin(snapshot, provider_configuration(), log),
        dynamic(registry, {}, log),
        broker(snapshot.binding, 19, builtin, dynamic, authority),
        settlement(std::make_unique<FakeTransport>(transport), broker,
                   std::move(*broker.take_admission().admission)) {}
  channel::AuthenticatedMessage message(std::uint64_t correlation = 1) {
    channel::AuthenticatedMessage value;
    value.role = wire::EndpointRole::broker;
    value.message_type =
        static_cast<std::uint16_t>(permissions::OperationId::audio_play_cue);
    value.correlation_id = correlation;
    value.payload = payload();
    return value;
  }
};
template <typename Function> void with_fixture(Function &&run) {
  auto fixture = std::make_unique<Fixture>();
  run(*fixture);
}
std::size_t completed_count(Fixture &fixture) {
  const auto completed =
      fixture.log.query({.plugin = std::nullopt,
                         .event = permissions::AuditEvent::operation_completed,
                         .maximum_results = audit::kHardMaximumRecords});
  require(completed.status.ok(), "completion audit query failed");
  return completed.records.size();
}
permissions::AuditOutcome only_completed_outcome(Fixture &fixture) {
  const auto completed =
      fixture.log.query({.plugin = std::nullopt,
                         .event = permissions::AuditEvent::operation_completed,
                         .maximum_results = audit::kHardMaximumRecords});
  require(completed.status.ok() && completed.records.size() == 1,
          "expected exactly one completion audit");
  return completed.records.front().outcome;
}
void test_retry_then_commit_once() {
  with_fixture([](Fixture &fixture) {
    fixture.transport->sends = {channel::ChannelSendStatus::would_block,
                                channel::ChannelSendStatus::complete};
    const auto deadline = std::chrono::steady_clock::now() + 2s;
    require(fixture.settlement.dispatch(fixture.message(), deadline) ==
                channel::BrokerSettlementStatus::would_block,
            "reply did not retain would-block transaction");
    const auto exact = fixture.transport->bytes;
    require(fixture.settlement.pending() &&
                fixture.transport->message_type ==
                    broker::kBrokerResultMessage &&
                fixture.transport->correlation == 1 &&
                fixture.transport->bytes.empty() &&
                fixture.settlement.read_lanes() ==
                    (launcher::EndpointMask::control |
                     launcher::EndpointMask::render) &&
                fixture.settlement.write_lanes() ==
                    launcher::EndpointMask::broker &&
                fixture.settlement.flush(deadline) ==
                    channel::BrokerSettlementStatus::complete &&
                fixture.transport->prepares == 1 &&
                fixture.transport->attempts == 2 &&
                fixture.transport->bytes == exact,
            "retry changed reply bytes, masks, or exact-once send");
    require(completed_count(fixture) == 1,
            "kernel completion was not committed exactly once");
    require(only_completed_outcome(fixture) ==
                permissions::AuditOutcome::allowed,
            "sent reply was not audited as allowed");
    require(fixture.settlement.flush(deadline) ==
                    channel::BrokerSettlementStatus::complete &&
                fixture.settlement.abort() &&
                fixture.settlement.flush(deadline) ==
                    channel::BrokerSettlementStatus::fatal &&
                fixture.settlement.dispatch(fixture.message(2), deadline) ==
                    channel::BrokerSettlementStatus::fatal &&
                fixture.transport->prepares == 1 &&
                fixture.transport->attempts == 2 &&
                completed_count(fixture) == 1,
            "settled reply could be retried or committed twice");
  });
}
void test_denied_reply_keeps_request_identity() {
  auto fixture = std::make_unique<Fixture>(permissions::GrantState::denied);
  const auto deadline = std::chrono::steady_clock::now() + 2s;
  require(fixture->settlement.dispatch(fixture->message(29), deadline) ==
              channel::BrokerSettlementStatus::complete &&
              fixture->transport->prepares == 1 &&
              fixture->transport->attempts == 1 &&
              fixture->transport->message_type ==
                  static_cast<std::uint16_t>(
                      wire::CommonMessageType::typed_error) &&
              fixture->transport->correlation == 29,
          "denied broker reply lost its exact type or correlation");
  broker::BrokerTypedError error{};
  require(broker::decode_broker_error(fixture->transport->bytes, error),
          "denied reply did not contain a typed broker error");
  require(error.failed_operation ==
                  permissions::OperationId::audio_play_cue &&
              error.reason == broker::BrokerErrorReason::denied &&
              error.decision ==
                  permissions::GrantDecisionCode::explicitly_denied,
          "denied reply did not preserve the broker denial decision");
}
void test_abort_paths_are_terminal() {
  for (const auto failure : {channel::ChannelSendStatus::peer_closed,
                             channel::ChannelSendStatus::fatal}) {
    with_fixture([failure](Fixture &fixture) {
      fixture.transport->sends = {failure};
      require(
          fixture.settlement.dispatch(fixture.message(),
                                      std::chrono::steady_clock::now() + 2s) ==
                  channel::BrokerSettlementStatus::fatal &&
              fixture.settlement.failed() &&
              fixture.settlement.read_lanes() == launcher::EndpointMask::none &&
              completed_count(fixture) == 1 && !fixture.settlement.abort() &&
              completed_count(fixture) == 1 &&
              only_completed_outcome(fixture) ==
                  permissions::AuditOutcome::cancelled,
          "terminal transport failure retained settlement authority");
    });
  }
  const auto deadline = std::chrono::steady_clock::now() + 2s;
  with_fixture([deadline](Fixture &duplicate) {
    duplicate.transport->sends = {channel::ChannelSendStatus::would_block};
    require(duplicate.settlement.dispatch(duplicate.message(), deadline) ==
                    channel::BrokerSettlementStatus::would_block &&
                duplicate.settlement.dispatch(duplicate.message(2), deadline) ==
                    channel::BrokerSettlementStatus::fatal &&
                !duplicate.settlement.pending() &&
                duplicate.settlement.flush(deadline) ==
                    channel::BrokerSettlementStatus::fatal &&
                completed_count(duplicate) == 1,
            "duplicate pending dispatch orphaned or revived its transaction");
    require(only_completed_outcome(duplicate) ==
                permissions::AuditOutcome::cancelled,
            "duplicate pending dispatch was not audited as cancelled");
  });

  with_fixture([deadline](Fixture &clean) {
    clean.transport->sends = {channel::ChannelSendStatus::would_block};
    require(clean.settlement.dispatch(clean.message(), deadline) ==
                    channel::BrokerSettlementStatus::would_block &&
                clean.settlement.abort() && !clean.settlement.pending() &&
                clean.settlement.flush(deadline) ==
                    channel::BrokerSettlementStatus::fatal &&
                clean.settlement.dispatch(clean.message(2), deadline) ==
                    channel::BrokerSettlementStatus::fatal &&
                completed_count(clean) == 1,
            "clean revoke abort retained or duplicated settlement authority");
    require(only_completed_outcome(clean) ==
                permissions::AuditOutcome::cancelled,
            "clean revoke was not audited as cancelled");
  });
}
void test_deadline_and_exceptions_fail_closed() {
  const auto deadline = std::chrono::steady_clock::now() + 2s;
  with_fixture([&](Fixture &fixture) {
    fixture.transport->sends = {channel::ChannelSendStatus::would_block};
    require(fixture.settlement.dispatch(fixture.message(), deadline) ==
                    channel::BrokerSettlementStatus::would_block &&
                fixture.settlement.flush(std::chrono::steady_clock::now()) ==
                    channel::BrokerSettlementStatus::fatal &&
                fixture.settlement.failed() &&
                only_completed_outcome(fixture) ==
                    permissions::AuditOutcome::cancelled,
            "expired retry retained settlement authority");
  });
  with_fixture([&](Fixture &fixture) {
    fixture.transport->throw_prepare = true;
    require(fixture.settlement.dispatch(fixture.message(), deadline) ==
                    channel::BrokerSettlementStatus::fatal &&
                fixture.settlement.failed() && !fixture.transport->prepared &&
                only_completed_outcome(fixture) ==
                    permissions::AuditOutcome::cancelled,
            "throwing preparation did not abort exactly once");
  });
  with_fixture([&](Fixture &fixture) {
    fixture.transport->reject_prepare = true;
    require(fixture.settlement.dispatch(fixture.message(), deadline) ==
                    channel::BrokerSettlementStatus::fatal &&
                fixture.settlement.failed() &&
                only_completed_outcome(fixture) ==
                    permissions::AuditOutcome::cancelled,
            "false preparation did not abort exactly once");
  });
  with_fixture([&](Fixture &fixture) {
    fixture.transport->prepare_sleep_microseconds = 20'000;
    require(fixture.settlement.dispatch(
                fixture.message(), std::chrono::steady_clock::now() + 5ms) ==
                    channel::BrokerSettlementStatus::fatal &&
                fixture.settlement.failed() && !fixture.transport->prepared &&
                only_completed_outcome(fixture) ==
                    permissions::AuditOutcome::cancelled,
            "deadline crossing in preparation retained settlement authority");
  });
  with_fixture([&](Fixture &fixture) {
    fixture.transport->throw_send = true;
    require(fixture.settlement.dispatch(fixture.message(), deadline) ==
                    channel::BrokerSettlementStatus::fatal &&
                fixture.settlement.failed() && !fixture.transport->prepared &&
                only_completed_outcome(fixture) ==
                    permissions::AuditOutcome::cancelled,
            "throwing send escaped or skipped exact abort");
  });
  with_fixture([&](Fixture &fixture) {
    fixture.transport->sleep_microseconds = 20'000;
    require(fixture.settlement.dispatch(
                fixture.message(), std::chrono::steady_clock::now() + 5ms) ==
                    channel::BrokerSettlementStatus::fatal &&
                fixture.settlement.failed() &&
                only_completed_outcome(fixture) ==
                    permissions::AuditOutcome::allowed,
            "post-kernel deadline skipped commit-before-fail-stop");
  });
  with_fixture([&](Fixture &fixture) {
    auto message = fixture.message();
    message.descriptors.emplace_back(open("/dev/null", O_RDONLY | O_CLOEXEC));
    require(message.descriptors.front() &&
                fixture.settlement.dispatch(std::move(message), deadline) ==
                    channel::BrokerSettlementStatus::fatal &&
                fixture.transport->prepares == 0 &&
                completed_count(fixture) == 0,
            "descriptor-bearing broker request reached admission or dispatch");
  });
}
} // namespace
int main() {
  try {
    test_retry_then_commit_once();
    test_denied_reply_keeps_request_identity();
    test_abort_paths_are_terminal();
    test_deadline_and_exceptions_fail_closed();
    return 0;
  } catch (const std::exception &error) {
    std::cerr << error.what() << '\n';
    return 1;
  }
}
