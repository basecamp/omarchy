#include "omarchy/plugin_runtime/broker/broker_core.hpp"

#include <cstddef>
#include <cstdint>
#include <memory>
#include <stdexcept>
#include <string>
#include <string_view>
#include <vector>

namespace {

namespace broker = omarchy::plugin_runtime::broker;
namespace permissions = omarchy::plugins::permissions;
namespace wire = omarchy::plugin::wire;

void require(bool condition, std::string_view message) {
  if (!condition) {
    throw std::runtime_error(std::string(message));
  }
}

permissions::Digest digest(char value) {
  return permissions::Digest(std::string(64, value));
}

permissions::CapabilityKey key(std::string_view id) {
  return {.id = permissions::CapabilityId(id), .version = 1};
}

permissions::TokenScope token_scope(std::string_view token) {
  permissions::TokenScope scope;
  require(scope.tokens.insert(permissions::ScopeToken(token)),
          "token fixture duplicated");
  return scope;
}

permissions::ResourceScope resource_scope(std::uint32_t resource,
                                          permissions::OperationId operation) {
  permissions::ResourceScope scope;
  require(scope.resources.insert(resource), "resource fixture duplicated");
  require(scope.operations.insert(operation), "operation fixture duplicated");
  return scope;
}

struct AuthorityFixture {
  permissions::RequestSet requests;
  permissions::GrantSet grants;
  permissions::ActivationBinding binding;

  AuthorityFixture() {
    requests.push_back({.capability = key("storage.private"),
                        .scope = permissions::QuotaScope{4096, 1024},
                        .required = true});
    requests.push_back({.capability = key("notifications.send"),
                        .scope = token_scope("timer"),
                        .required = false});
    requests.push_back(
        {.capability = key("service.fake-status"),
         .scope = resource_scope(1, permissions::OperationId::fake_status_list),
         .required = false});
    grants.push_back({.capability = key("storage.private"),
                      .scope = permissions::QuotaScope{2048, 512},
                      .state = permissions::GrantState::granted,
                      .epoch = 4});
    grants.push_back({.capability = key("notifications.send"),
                      .scope = token_scope("timer"),
                      .state = permissions::GrantState::denied,
                      .epoch = 2});
    grants.push_back(
        {.capability = key("service.fake-status"),
         .scope = resource_scope(1, permissions::OperationId::fake_status_list),
         .state = permissions::GrantState::granted,
         .epoch = 6});
    binding = {.plugin = permissions::PluginId("org.example.timer"),
               .revision = digest('a'),
               .policy_fingerprint = permissions::Digest(
                   permissions::policy_request_fingerprint(requests)),
               .generation = 9};
  }
};

void put16(std::vector<std::byte> &bytes, std::size_t offset,
           std::uint16_t value) {
  bytes[offset] = static_cast<std::byte>(value >> 8U);
  bytes[offset + 1] = static_cast<std::byte>(value);
}

void put32(std::vector<std::byte> &bytes, std::size_t offset,
           std::uint32_t value) {
  for (std::size_t index = 0; index < 4; ++index) {
    bytes[offset + index] =
        static_cast<std::byte>(value >> ((3U - index) * 8U));
  }
}

void put64(std::vector<std::byte> &bytes, std::size_t offset,
           std::uint64_t value) {
  for (std::size_t index = 0; index < 8; ++index) {
    bytes[offset + index] =
        static_cast<std::byte>(value >> ((7U - index) * 8U));
  }
}

std::vector<std::byte> quota_request(permissions::OperationId operation,
                                     std::uint64_t total, std::uint64_t item,
                                     std::span<const std::byte> body = {}) {
  std::vector<std::byte> bytes(24 + body.size());
  put16(bytes, 0, static_cast<std::uint16_t>(operation));
  put16(bytes, 2, 16);
  put32(bytes, 4, body.size());
  put64(bytes, 8, total);
  put64(bytes, 16, item);
  std::copy(body.begin(), body.end(), bytes.begin() + 24);
  return bytes;
}

std::vector<std::byte> token_request(permissions::OperationId operation,
                                     std::string_view token) {
  std::vector<std::byte> bytes(10 + token.size());
  put16(bytes, 0, static_cast<std::uint16_t>(operation));
  put16(bytes, 2, 2 + token.size());
  put32(bytes, 4, 0);
  put16(bytes, 8, token.size());
  for (std::size_t index = 0; index < token.size(); ++index) {
    bytes[10 + index] = static_cast<std::byte>(token[index]);
  }
  return bytes;
}

std::vector<std::byte> resource_request(permissions::OperationId operation,
                                        std::uint32_t resource) {
  std::vector<std::byte> bytes(16);
  put16(bytes, 0, static_cast<std::uint16_t>(operation));
  put16(bytes, 2, 8);
  put32(bytes, 4, 0);
  put32(bytes, 8, resource);
  put16(bytes, 12, static_cast<std::uint16_t>(operation));
  put16(bytes, 14, 0);
  return bytes;
}

wire::PacketView request_packet(permissions::OperationId operation,
                                std::uint64_t correlation,
                                std::span<const std::byte> payload,
                                std::uint64_t generation = 9) {
  return {
      .header = {.endpoint_role = wire::EndpointRole::broker,
                 .message_type = static_cast<std::uint16_t>(operation),
                 .role_protocol_version = broker::kBrokerRoleVersion,
                 .payload_length = static_cast<std::uint32_t>(payload.size()),
                 .launch_generation = generation,
                 .correlation_id = correlation},
      .payload = payload};
}

wire::PacketView result_packet(std::uint64_t correlation,
                               std::span<const std::byte> payload = {}) {
  return {
      .header = {.endpoint_role = wire::EndpointRole::broker,
                 .message_type = broker::kBrokerResultMessage,
                 .role_protocol_version = broker::kBrokerRoleVersion,
                 .payload_length = static_cast<std::uint32_t>(payload.size()),
                 .launch_generation = 9,
                 .correlation_id = correlation},
      .payload = payload};
}

wire::PacketView error_packet(std::uint64_t correlation,
                              std::span<const std::byte> payload) {
  return {
      .header = {.endpoint_role = wire::EndpointRole::broker,
                 .message_type = static_cast<std::uint16_t>(
                     wire::CommonMessageType::typed_error),
                 .role_protocol_version = broker::kBrokerRoleVersion,
                 .payload_length = static_cast<std::uint32_t>(payload.size()),
                 .launch_generation = 9,
                 .correlation_id = correlation},
      .payload = payload};
}

wire::PacketView cancel_packet(std::uint64_t correlation) {
  return {.header = {.endpoint_role = wire::EndpointRole::broker,
                     .message_type = static_cast<std::uint16_t>(
                         wire::CommonMessageType::cancel),
                     .role_protocol_version = broker::kBrokerRoleVersion,
                     .payload_length = 0,
                     .launch_generation = 9,
                     .correlation_id = correlation},
          .payload = {}};
}

wire::PacketView cancel_result_packet(std::uint64_t correlation,
                                      std::span<const std::byte> payload) {
  return {
      .header = {.endpoint_role = wire::EndpointRole::broker,
                 .message_type = static_cast<std::uint16_t>(
                     wire::CommonMessageType::cancel_result),
                 .role_protocol_version = broker::kBrokerRoleVersion,
                 .payload_length = static_cast<std::uint32_t>(payload.size()),
                 .launch_generation = 9,
                 .correlation_id = correlation},
      .payload = payload};
}

struct ProviderProbe {
  static broker::ProviderResult
  dispatch(const broker::AuthorizedRequest &request, std::span<std::byte>,
           void *context) noexcept {
    auto &probe = *static_cast<ProviderProbe *>(context);
    ++probe.calls;
    probe.correlation = request.correlation;
    probe.operation = request.operation;
    probe.plugin = std::string(request.binding.plugin.view());
    probe.payload_size = request.payload.size();
    probe.grant_epoch = request.grant_epoch;
    return {.status = probe.result, .bytes_written = probe.response_bytes};
  }

  static bool cancel(std::uint64_t correlation, void *context) noexcept {
    auto &probe = *static_cast<ProviderProbe *>(context);
    ++probe.cancels;
    probe.cancelled_correlation = correlation;
    return true;
  }

  int calls = 0;
  int cancels = 0;
  std::uint64_t correlation = 0;
  permissions::OperationId operation{};
  std::string plugin;
  std::size_t payload_size = 0;
  std::uint64_t grant_epoch = 0;
  std::uint64_t cancelled_correlation = 0;
  std::size_t response_bytes = 0;
  broker::ProviderStatus result = broker::ProviderStatus::completed;
};

struct ReentryProbe {
  using Core = broker::BrokerCore<4, 1>;

  static broker::ProviderResult dispatch(const broker::AuthorizedRequest &,
                                         std::span<std::byte>,
                                         void *context) noexcept {
    auto &probe = *static_cast<ReentryProbe *>(context);
    probe.nested = probe.core->dispatch(probe.packet, 100).outcome;
    probe.terminal = probe.core->accept_terminal(result_packet(51));
    probe.revocation_busy =
        probe.core->revoke(key("storage.private")).core_busy;
    return {.status = broker::ProviderStatus::completed, .bytes_written = 0};
  }

  static bool cancel(std::uint64_t, void *) noexcept { return false; }

  Core *core = nullptr;
  wire::PacketView packet{};
  broker::DispatchOutcome nested = broker::DispatchOutcome::core_failed;
  broker::TerminalResult terminal = broker::TerminalResult::core_failed;
  bool revocation_busy = false;
};

broker::ProviderRegistry<1> temporary_registry(ProviderProbe &probe) {
  broker::ProviderRegistry<1> registry;
  require(registry.add({.operation = permissions::OperationId::storage_read,
                        .dispatch = ProviderProbe::dispatch,
                        .cancel = ProviderProbe::cancel,
                        .context = &probe}),
          "temporary provider registry setup failed");
  return registry;
}

} // namespace

int main() {
  using permissions::OperationId;
  require(broker::broker_schema_registry().validate() ==
              wire::FatalReason::none,
          "broker role schema is invalid");

  AuthorityFixture fixture;
  permissions::PermissionAuthority authority(fixture.binding, fixture.requests,
                                             fixture.grants);
  ProviderProbe probe;
  broker::ProviderRegistry<2> providers;
  require(providers.add({.operation = OperationId::storage_read,
                         .dispatch = ProviderProbe::dispatch,
                         .cancel = ProviderProbe::cancel,
                         .context = &probe}),
          "provider registration failed");
  require(!providers.add({.operation = OperationId::storage_read,
                          .dispatch = ProviderProbe::dispatch,
                          .cancel = ProviderProbe::cancel,
                          .context = &probe}),
          "duplicate provider was registered");

  broker::BrokerCore<4, 2> core(fixture.binding, authority, providers, 4);
  const std::array body{std::byte{0xaa}, std::byte{0xbb}};
  const auto read = quota_request(OperationId::storage_read, 512, 128, body);
  broker::DecodedBrokerRequest decoded_request{};
  require(broker::decode_broker_request(
              static_cast<std::uint16_t>(OperationId::storage_read), read,
              decoded_request) == broker::BrokerDecodeResult::accepted &&
              decoded_request.operation == OperationId::storage_read &&
              decoded_request.provider_payload.size() == body.size(),
          "exact quota request did not decode");
  auto zero_quota = read;
  put64(zero_quota, 8, 0);
  require(broker::decode_broker_request(
              static_cast<std::uint16_t>(OperationId::storage_read), zero_quota,
              decoded_request) == broker::BrokerDecodeResult::malformed_demand,
          "zero quota demand was decoded");
  require(broker::decode_broker_request(0xffff, read, decoded_request) ==
              broker::BrokerDecodeResult::unknown_operation,
          "unknown operation entered the broker codec");
  auto oversized = quota_request(OperationId::storage_read, 512, 128);
  oversized.resize(broker::kBrokerRequestHeaderBytes + 16 +
                   broker::kMaximumProviderPayloadBytes + 1);
  put32(oversized, 4, broker::kMaximumProviderPayloadBytes + 1);
  require(broker::decode_broker_request(
              static_cast<std::uint16_t>(OperationId::storage_read), oversized,
              decoded_request) == broker::BrokerDecodeResult::payload_too_large,
          "oversized provider payload was decoded");
  const auto admitted =
      core.dispatch(request_packet(OperationId::storage_read, 11, read), 100);
  require(admitted.outcome == broker::DispatchOutcome::dispatched &&
              admitted.decision.allowed() && probe.calls == 1 &&
              probe.correlation == 11 &&
              probe.operation == OperationId::storage_read &&
              probe.plugin == "org.example.timer" && probe.payload_size == 2 &&
              probe.grant_epoch == 4 && core.in_flight() == 1,
          "authorized request did not reach exact provider context");
  require(core.accept_terminal(result_packet(11)) ==
                  broker::TerminalResult::accepted &&
              core.in_flight() == 0,
          "valid broker result did not retire request");

  const auto notification =
      token_request(OperationId::notification_send, "timer");
  const auto denied = core.dispatch(
      request_packet(OperationId::notification_send, 12, notification), 100);
  require(denied.outcome == broker::DispatchOutcome::denied &&
              denied.decision.code ==
                  permissions::GrantDecisionCode::explicitly_denied &&
              probe.calls == 1,
          "denied request reached a provider");
  const auto denied_bytes = broker::encode_broker_error(
      {.failed_operation = OperationId::notification_send,
       .reason = broker::BrokerErrorReason::denied,
       .decision = denied.decision.code});
  require(core.accept_terminal(error_packet(12, denied_bytes)) ==
              broker::TerminalResult::accepted,
          "exact typed denial did not retire request");

  const auto write = quota_request(OperationId::storage_write, 64, 64);
  const auto unavailable =
      core.dispatch(request_packet(OperationId::storage_write, 13, write), 100);
  require(unavailable.outcome ==
                  broker::DispatchOutcome::provider_unavailable &&
              unavailable.decision.allowed() && probe.calls == 1,
          "unregistered provider gained dispatch authority");
  probe.result = broker::ProviderStatus::pending;
  require(
      core.dispatch(request_packet(OperationId::storage_read, 15, read), 100)
              .outcome == broker::DispatchOutcome::pending,
      "cancellable request setup failed");
  require(core.accept_cancel(cancel_packet(15)) ==
                  broker::CancelResult::provider_notified &&
              probe.cancels == 1 && probe.cancelled_correlation == 15,
          "authenticated cancellation did not reach exact provider");
  require(core.accept_cancel(cancel_packet(15)) ==
                  broker::CancelResult::provider_notified &&
              probe.cancels == 1,
          "duplicate cancel repeated its provider side effect");
  const auto cancel_result =
      wire::encode_cancel_result_payload(wire::CancelOutcome::accepted);
  require(core.accept_terminal(result_packet(15)) ==
                  broker::TerminalResult::accepted &&
              core.in_flight() == 2 &&
              core.accept_cancel(cancel_packet(15)) ==
                  broker::CancelResult::provider_notified &&
              probe.cancels == 1 &&
              core.accept_cancel_result(cancel_result_packet(
                  15, cancel_result)) == broker::CancelResult::accepted &&
              core.in_flight() == 1 &&
              core.accept_cancel(cancel_packet(15)) ==
                  broker::CancelResult::unknown &&
              probe.cancels == 1,
          "terminal-before-cancel-result ordering did not retain then retire");
  probe.result = broker::ProviderStatus::completed;
  require(
      core.dispatch(request_packet(OperationId::storage_read, 17, read), 100)
                  .outcome == broker::DispatchOutcome::dispatched &&
          core.accept_cancel(cancel_packet(17)) ==
              broker::CancelResult::unsupported &&
          probe.cancels == 1,
      "completed provider work was treated as actively cancellable");
  const auto not_cancellable =
      wire::encode_cancel_result_payload(wire::CancelOutcome::not_cancellable);
  require(core.accept_cancel_result(cancel_result_packet(
              17, not_cancellable)) == broker::CancelResult::accepted &&
              core.accept_terminal(result_packet(17)) ==
                  broker::TerminalResult::accepted,
          "non-cancellable result ordering did not retire completed work");
  probe.result = broker::ProviderStatus::pending;
  require(
      core.dispatch(request_packet(OperationId::storage_read, 16, read), 100)
              .outcome == broker::DispatchOutcome::pending,
      "revocation active-provider setup failed");
  probe.result = broker::ProviderStatus::completed;
  const auto revocation = core.revoke(key("storage.private"));
  require(revocation.accepted && revocation.new_epoch == 5 &&
              revocation.cancel_count == 1 &&
              revocation.cancel_correlations[0] == 16 &&
              !revocation.restart_worker,
          "live revocation did not identify exact cancellable operation");
  require(!core.revoke(key("audio.play-cue")).accepted,
          "missing grant was treated as revocable authority");
  const auto revoked =
      core.dispatch(request_packet(OperationId::storage_read, 14, read), 100);
  require(revoked.outcome == broker::DispatchOutcome::denied &&
              revoked.decision.code ==
                  permissions::GrantDecisionCode::revoked &&
              probe.calls == 4,
          "revoked capability reached its provider");
  const auto revoked_bytes = broker::encode_broker_error(
      {.failed_operation = OperationId::storage_read,
       .reason = broker::BrokerErrorReason::denied,
       .decision = revoked.decision.code});
  require(core.accept_terminal(error_packet(14, revoked_bytes)) ==
              broker::TerminalResult::accepted,
          "revocation denial did not retire exact request");
  require(core.accept_cancel(cancel_packet(16)) ==
                  broker::CancelResult::provider_notified &&
              probe.cancels == 2 &&
              core.accept_terminal(result_packet(16)) ==
                  broker::TerminalResult::accepted &&
              core.accept_terminal(result_packet(16)) ==
                  broker::TerminalResult::protocol_fatal &&
              core.failed() && core.revoke(key("storage.private")).core_failed,
          "duplicate terminal escaped B3 during cancellation race");

  auto crossed_fixture = std::make_unique<AuthorityFixture>();
  auto crossed_authority = std::make_unique<permissions::PermissionAuthority>(
      crossed_fixture->binding, crossed_fixture->requests,
      crossed_fixture->grants);
  auto crossed = std::make_unique<broker::BrokerCore<4, 2>>(
      crossed_fixture->binding, *crossed_authority, providers, 4);
  require(crossed->dispatch(request_packet(OperationId::storage_read, 21, read),
                            100)
                  .outcome == broker::DispatchOutcome::dispatched,
          "crossed-error request setup failed");
  const auto wrong_error = broker::encode_broker_error(
      {.failed_operation = OperationId::storage_write,
       .reason = broker::BrokerErrorReason::provider_failed,
       .decision = permissions::GrantDecisionCode::allowed});
  require(crossed->accept_terminal(error_packet(21, wrong_error)) ==
                  broker::TerminalResult::mismatched_operation &&
              crossed->failed(),
          "typed error crossed operation identity");

  auto forged_fixture = std::make_unique<AuthorityFixture>();
  auto forged_authority = std::make_unique<permissions::PermissionAuthority>(
      forged_fixture->binding, forged_fixture->requests,
      forged_fixture->grants);
  auto forged = std::make_unique<broker::BrokerCore<2, 2>>(
      forged_fixture->binding, *forged_authority, providers, 2);
  require(
      forged->dispatch(request_packet(OperationId::storage_read, 31, read, 10),
                       100)
                  .outcome == broker::DispatchOutcome::protocol_fatal &&
          probe.calls == 5 && forged->failed(),
      "worker-controlled generation reached provider dispatch");

  auto malformed_fixture = std::make_unique<AuthorityFixture>();
  auto malformed_authority = std::make_unique<permissions::PermissionAuthority>(
      malformed_fixture->binding, malformed_fixture->requests,
      malformed_fixture->grants);
  auto malformed = std::make_unique<broker::BrokerCore<2, 2>>(
      malformed_fixture->binding, *malformed_authority, providers, 2);
  auto confused = read;
  put16(confused, 0, static_cast<std::uint16_t>(OperationId::storage_write));
  require(
      malformed->dispatch(
                   request_packet(OperationId::storage_read, 41, confused), 100)
                  .outcome == broker::DispatchOutcome::malformed &&
          malformed->failed() && probe.calls == 5,
      "payload operation overrode envelope operation");

  auto bad_error = denied_bytes;
  bad_error[7] = std::byte{1};
  broker::BrokerTypedError decoded_error{};
  require(!broker::decode_broker_error(bad_error, decoded_error),
          "typed error reserved bytes were accepted");

  auto reentry_fixture = std::make_unique<AuthorityFixture>();
  auto reentry_authority = std::make_unique<permissions::PermissionAuthority>(
      reentry_fixture->binding, reentry_fixture->requests,
      reentry_fixture->grants);
  ReentryProbe reentry_probe;
  broker::ProviderRegistry<1> reentry_providers;
  require(reentry_providers.add({.operation = OperationId::storage_read,
                                 .dispatch = ReentryProbe::dispatch,
                                 .cancel = ReentryProbe::cancel,
                                 .context = &reentry_probe}),
          "reentry provider registration failed");
  auto reentry_core = std::make_unique<ReentryProbe::Core>(
      reentry_fixture->binding, *reentry_authority, reentry_providers, 4);
  reentry_probe.core = reentry_core.get();
  reentry_probe.packet = request_packet(OperationId::storage_read, 52, read);
  require(
      reentry_core->dispatch(
                      request_packet(OperationId::storage_read, 51, read), 100)
                  .outcome == broker::DispatchOutcome::dispatched &&
          reentry_probe.nested == broker::DispatchOutcome::core_busy &&
          reentry_probe.terminal == broker::TerminalResult::core_busy &&
          reentry_probe.revocation_busy && reentry_core->in_flight() == 1 &&
          reentry_core->accept_terminal(result_packet(51)) ==
              broker::TerminalResult::accepted,
      "provider reentry changed broker request state");

  auto denied_terminal_fixture = std::make_unique<AuthorityFixture>();
  auto denied_terminal_authority =
      std::make_unique<permissions::PermissionAuthority>(
          denied_terminal_fixture->binding, denied_terminal_fixture->requests,
          denied_terminal_fixture->grants);
  auto denied_terminal = std::make_unique<broker::BrokerCore<2, 2>>(
      denied_terminal_fixture->binding, *denied_terminal_authority, providers,
      2);
  require(denied_terminal
                      ->dispatch(request_packet(OperationId::notification_send,
                                                61, notification),
                                 100)
                      .outcome == broker::DispatchOutcome::denied &&
              denied_terminal->accept_terminal(result_packet(61)) ==
                  broker::TerminalResult::mismatched_operation &&
              denied_terminal->failed(),
          "successful result relabeled an authorization denial");

  auto allowed_error_fixture = std::make_unique<AuthorityFixture>();
  auto allowed_error_authority =
      std::make_unique<permissions::PermissionAuthority>(
          allowed_error_fixture->binding, allowed_error_fixture->requests,
          allowed_error_fixture->grants);
  auto allowed_error = std::make_unique<broker::BrokerCore<2, 2>>(
      allowed_error_fixture->binding, *allowed_error_authority, providers, 2);
  require(allowed_error
                  ->dispatch(
                      request_packet(OperationId::storage_read, 62, read), 100)
                  .outcome == broker::DispatchOutcome::dispatched,
          "allowed-error setup failed");
  const auto false_denial = broker::encode_broker_error(
      {.failed_operation = OperationId::storage_read,
       .reason = broker::BrokerErrorReason::denied,
       .decision = permissions::GrantDecisionCode::explicitly_denied});
  require(allowed_error->accept_terminal(error_packet(62, false_denial)) ==
                  broker::TerminalResult::mismatched_operation &&
              allowed_error->failed(),
          "typed error relabeled an authorized provider operation as denied");

  auto response_bound_fixture = std::make_unique<AuthorityFixture>();
  auto response_bound_authority =
      std::make_unique<permissions::PermissionAuthority>(
          response_bound_fixture->binding, response_bound_fixture->requests,
          response_bound_fixture->grants);
  auto response_bound = std::make_unique<broker::BrokerCore<2, 2>>(
      response_bound_fixture->binding, *response_bound_authority, providers, 2);
  std::array<std::byte, 2> short_response{};
  probe.response_bytes = short_response.size() + 1;
  require(
      response_bound
              ->dispatch(request_packet(OperationId::storage_read, 71, read),
                         100, short_response)
              .outcome == broker::DispatchOutcome::provider_failed,
      "provider response exceeded its trusted caller buffer");
  probe.response_bytes = 0;

  auto invalid_status_fixture = std::make_unique<AuthorityFixture>();
  auto invalid_status_authority =
      std::make_unique<permissions::PermissionAuthority>(
          invalid_status_fixture->binding, invalid_status_fixture->requests,
          invalid_status_fixture->grants);
  ProviderProbe invalid_status_probe;
  invalid_status_probe.result = static_cast<broker::ProviderStatus>(255);
  broker::ProviderRegistry<1> invalid_status_providers;
  require(invalid_status_providers.add(
              {.operation = OperationId::storage_read,
               .dispatch = ProviderProbe::dispatch,
               .cancel = ProviderProbe::cancel,
               .context = &invalid_status_probe}),
          "invalid-status provider registration failed");
  auto invalid_status_core = std::make_unique<broker::BrokerCore<2, 1>>(
      invalid_status_fixture->binding, *invalid_status_authority,
      invalid_status_providers, 2);
  require(invalid_status_core
                  ->dispatch(
                      request_packet(OperationId::storage_read, 72, read), 100)
                  .outcome == broker::DispatchOutcome::provider_failed &&
              invalid_status_core->revoke(key("storage.private")).cancel_count ==
                  0,
          "unknown provider status became successful active work");

  ProviderProbe uncancellable_probe;
  uncancellable_probe.result = broker::ProviderStatus::pending;
  broker::ProviderRegistry<1> uncancellable_providers;
  require(!uncancellable_providers.add(
              {.operation = OperationId::storage_read,
               .dispatch = ProviderProbe::dispatch,
               .cancel = nullptr,
               .context = &uncancellable_probe}) &&
              uncancellable_probe.calls == 0,
          "uncancellable provider was registered or invoked");

  auto gesture_fixture = std::make_unique<AuthorityFixture>();
  auto gesture_authority = std::make_unique<permissions::PermissionAuthority>(
      gesture_fixture->binding, gesture_fixture->requests,
      gesture_fixture->grants);
  ProviderProbe gesture_probe;
  broker::ProviderRegistry<1> gesture_providers;
  require(gesture_providers.add({.operation = OperationId::fake_status_list,
                                 .dispatch = ProviderProbe::dispatch,
                                 .cancel = ProviderProbe::cancel,
                                 .context = &gesture_probe}),
          "gesture provider registration failed");
  auto gesture_core = std::make_unique<broker::BrokerCore<8, 1>>(
      gesture_fixture->binding, *gesture_authority, gesture_providers, 8);
  const auto fake = resource_request(OperationId::fake_status_list, 1);
  auto finish_gesture_denial = [&](std::uint64_t correlation,
                                   permissions::GrantDecisionCode decision) {
    const auto bytes = broker::encode_broker_error(
        {.failed_operation = OperationId::fake_status_list,
         .reason = broker::BrokerErrorReason::denied,
         .decision = decision});
    require(gesture_core->accept_terminal(error_packet(correlation, bytes)) ==
                broker::TerminalResult::accepted,
            "gesture denial did not retire exact request");
  };
  const auto missing = gesture_core->dispatch(
      request_packet(OperationId::fake_status_list, 91, fake), 100);
  require(missing.outcome == broker::DispatchOutcome::denied &&
              missing.decision.code ==
                  permissions::GrantDecisionCode::gesture_missing &&
              gesture_probe.calls == 0,
          "missing gesture reached provider");
  finish_gesture_denial(91, missing.decision.code);

  permissions::GestureProof gesture{
      .id = {},
      .plugin = permissions::PluginId("org.example.timer"),
      .generation = 9,
      .surface = 1,
      .operation = OperationId::fake_status_list,
      .expires_monotonic_ns = 200,
      .consumed = false};
  gesture.id.bytes[0] = std::byte{1};
  auto expired = gesture;
  expired.expires_monotonic_ns = 100;
  const auto expired_result = gesture_core->dispatch(
      request_packet(OperationId::fake_status_list, 92, fake), 100, {},
      &expired);
  require(expired_result.decision.code ==
                  permissions::GrantDecisionCode::gesture_expired &&
              !expired.consumed && gesture_probe.calls == 0,
          "expired gesture was consumed or dispatched");
  finish_gesture_denial(92, expired_result.decision.code);

  auto wrong_generation = gesture;
  wrong_generation.generation = 10;
  const auto wrong_generation_result = gesture_core->dispatch(
      request_packet(OperationId::fake_status_list, 93, fake), 100, {},
      &wrong_generation);
  require(wrong_generation_result.decision.code ==
                  permissions::GrantDecisionCode::gesture_wrong_binding &&
              !wrong_generation.consumed,
          "wrong-generation gesture was consumed");
  finish_gesture_denial(93, wrong_generation_result.decision.code);

  auto wrong_operation = gesture;
  wrong_operation.operation = OperationId::fake_status_acknowledge;
  const auto wrong_operation_result = gesture_core->dispatch(
      request_packet(OperationId::fake_status_list, 94, fake), 100, {},
      &wrong_operation);
  require(wrong_operation_result.decision.code ==
                  permissions::GrantDecisionCode::gesture_wrong_binding &&
              !wrong_operation.consumed,
          "wrong-operation gesture was consumed");
  finish_gesture_denial(94, wrong_operation_result.decision.code);

  auto used = gesture;
  used.consumed = true;
  const auto used_result = gesture_core->dispatch(
      request_packet(OperationId::fake_status_list, 95, fake), 100, {}, &used);
  require(used_result.decision.code ==
                  permissions::GrantDecisionCode::gesture_used &&
              gesture_probe.calls == 0,
          "used gesture reached provider");
  finish_gesture_denial(95, used_result.decision.code);

  const auto allowed_gesture = gesture_core->dispatch(
      request_packet(OperationId::fake_status_list, 96, fake), 100, {},
      &gesture);
  require(allowed_gesture.outcome == broker::DispatchOutcome::dispatched &&
              allowed_gesture.decision.allowed() && gesture.consumed &&
              gesture_probe.calls == 1 &&
              gesture_core->accept_terminal(result_packet(96)) ==
                  broker::TerminalResult::accepted,
          "valid single-use gesture did not dispatch exactly once");
  const auto replayed_gesture = gesture_core->dispatch(
      request_packet(OperationId::fake_status_list, 97, fake), 100, {},
      &gesture);
  require(replayed_gesture.decision.code ==
                  permissions::GrantDecisionCode::gesture_used &&
              gesture_probe.calls == 1,
          "gesture replay reached provider");
  finish_gesture_denial(97, replayed_gesture.decision.code);

  auto duplicate_fixture = std::make_unique<AuthorityFixture>();
  auto duplicate_authority = std::make_unique<permissions::PermissionAuthority>(
      duplicate_fixture->binding, duplicate_fixture->requests,
      duplicate_fixture->grants);
  ProviderProbe duplicate_probe;
  broker::ProviderRegistry<2> duplicate_providers;
  require(
      duplicate_providers.add({.operation = OperationId::storage_read,
                               .dispatch = ProviderProbe::dispatch,
                               .cancel = ProviderProbe::cancel,
                               .context = &duplicate_probe}) &&
          duplicate_providers.add({.operation = OperationId::fake_status_list,
                                   .dispatch = ProviderProbe::dispatch,
                                   .cancel = ProviderProbe::cancel,
                                   .context = &duplicate_probe}),
      "duplicate-correlation providers failed");
  auto duplicate_core = std::make_unique<broker::BrokerCore<2, 2>>(
      duplicate_fixture->binding, *duplicate_authority, duplicate_providers, 2);
  require(duplicate_core
                  ->dispatch(
                      request_packet(OperationId::storage_read, 98, read), 100)
                  .outcome == broker::DispatchOutcome::dispatched,
          "duplicate-correlation setup failed");
  auto untouched_gesture = gesture;
  untouched_gesture.consumed = false;
  require(duplicate_core
                      ->dispatch(request_packet(OperationId::fake_status_list,
                                                98, fake),
                                 100, {}, &untouched_gesture)
                      .outcome == broker::DispatchOutcome::protocol_fatal &&
              !untouched_gesture.consumed && duplicate_probe.calls == 1,
          "duplicate correlation consumed gesture or reached provider");

  auto temporary_fixture = std::make_unique<AuthorityFixture>();
  auto temporary_authority = std::make_unique<permissions::PermissionAuthority>(
      temporary_fixture->binding, temporary_fixture->requests,
      temporary_fixture->grants);
  auto temporary_core = std::make_unique<broker::BrokerCore<2, 1>>(
      temporary_fixture->binding, *temporary_authority,
      temporary_registry(probe), 2);
  require(
      temporary_core
                  ->dispatch(
                      request_packet(OperationId::storage_read, 81, read), 100)
                  .outcome == broker::DispatchOutcome::dispatched &&
          temporary_core->accept_terminal(result_packet(81)) ==
              broker::TerminalResult::accepted &&
          temporary_core->accept_terminal(result_packet(81)) ==
              broker::TerminalResult::protocol_fatal &&
          temporary_core->failed(),
      "temporary registry lifetime or unmatched-terminal denial failed");

  auto stale_fixture = std::make_unique<AuthorityFixture>();
  auto stale_authority = std::make_unique<permissions::PermissionAuthority>(
      stale_fixture->binding, stale_fixture->requests, stale_fixture->grants);
  auto stale_core = std::make_unique<broker::BrokerCore<2, 1>>(
      stale_fixture->binding, *stale_authority, temporary_registry(probe), 2);
  require(stale_core
                  ->dispatch(
                      request_packet(OperationId::storage_read, 82, read), 100)
                  .outcome == broker::DispatchOutcome::dispatched,
          "stale terminal setup failed");
  auto stale_terminal = result_packet(82);
  stale_terminal.header.launch_generation = 10;
  require(stale_core->accept_terminal(stale_terminal) ==
                  broker::TerminalResult::protocol_fatal &&
              stale_core->failed(),
          "stale-generation terminal bypassed B3");

  auto wrong_role_fixture = std::make_unique<AuthorityFixture>();
  auto wrong_role_authority =
      std::make_unique<permissions::PermissionAuthority>(
          wrong_role_fixture->binding, wrong_role_fixture->requests,
          wrong_role_fixture->grants);
  auto wrong_role_core = std::make_unique<broker::BrokerCore<2, 1>>(
      wrong_role_fixture->binding, *wrong_role_authority,
      temporary_registry(probe), 2);
  require(wrong_role_core
                  ->dispatch(
                      request_packet(OperationId::storage_read, 83, read), 100)
                  .outcome == broker::DispatchOutcome::dispatched,
          "wrong-role terminal setup failed");
  auto wrong_role_terminal = result_packet(83);
  wrong_role_terminal.header.endpoint_role = wire::EndpointRole::render;
  require(wrong_role_core->accept_terminal(wrong_role_terminal) ==
                  broker::TerminalResult::protocol_fatal &&
              wrong_role_core->failed(),
          "wrong-role terminal bypassed B3");
}
