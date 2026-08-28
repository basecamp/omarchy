#include "broker_runtime.hpp"

#include "omarchy/plugin_runtime/broker/broker_schema.hpp"

#include <algorithm>
#include <array>
#include <cstdlib>
#include <filesystem>
#include <iostream>
#include <stdexcept>
#include <string>
#include <string_view>
#include <vector>

namespace {

namespace audit = omarchy::plugins::audit;
namespace broker = omarchy::plugin_runtime::broker;
namespace grant = omarchy::plugins::grants;
namespace permissions = omarchy::plugins::permissions;
namespace providers = omarchy::plugin_runtime::providers;
namespace runtime = omarchy::plugin_runtime::runtime;
namespace wire = omarchy::plugin::wire;

void require(bool condition, std::string_view message) {
  if (!condition)
    throw std::runtime_error(std::string(message));
}

class TemporaryDirectory {
public:
  TemporaryDirectory() {
    std::string pattern = "/tmp/omarchy-broker-runtime-XXXXXX";
    char *created = ::mkdtemp(pattern.data());
    if (created == nullptr)
      throw std::runtime_error("mkdtemp failed");
    path_ = created;
  }
  ~TemporaryDirectory() {
    std::error_code error;
    std::filesystem::remove_all(path_, error);
  }
  const std::filesystem::path &path() const { return path_; }

private:
  std::filesystem::path path_;
};

permissions::Digest digest(char value) {
  return permissions::Digest(std::string(64, value));
}

permissions::CapabilityKey key(std::string_view id) {
  return {.id = permissions::CapabilityId(id), .version = 1};
}

permissions::TokenScope token(std::string_view value) {
  permissions::TokenScope result;
  require(result.tokens.insert(permissions::ScopeToken(value)),
          "token fixture");
  return result;
}

permissions::QuotaScope quota() { return {4096, 1024}; }

permissions::ResourceScope resource(permissions::OperationId operation) {
  permissions::ResourceScope result;
  require(result.resources.insert(1), "resource fixture");
  require(result.operations.insert(operation), "resource operation fixture");
  return result;
}

grant::RevisionGrants revision() {
  grant::RevisionGrants result;
  result.binding.plugin = permissions::PluginId("org.example.secure");
  result.binding.revision = digest('a');
  result.binding.generation = 11;
  result.source_request_fingerprint = digest('c');
  result.requests.push_back({key("storage.private"), quota(), true});
  result.requests.push_back({key("notifications.send"), token("timer"), false});
  result.requests.push_back(
      {key("service.fake-status"),
       resource(permissions::OperationId::fake_status_list), false});
  result.grants.push_back(
      {key("storage.private"), quota(), permissions::GrantState::granted, 4});
  result.grants.push_back({key("notifications.send"), token("timer"),
                           permissions::GrantState::denied, 2});
  result.grants.push_back({key("service.fake-status"),
                           resource(permissions::OperationId::fake_status_list),
                           permissions::GrantState::granted, 7});
  result.binding.policy_fingerprint = permissions::Digest(
      permissions::policy_request_fingerprint(result.requests));
  return result;
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

void put64(std::vector<std::byte> &bytes, std::size_t offset,
           std::uint64_t value) {
  for (std::size_t index = 0; index < 8; ++index)
    bytes[offset + index] =
        static_cast<std::byte>(value >> ((7U - index) * 8U));
}

std::vector<std::byte> storage_write_request(std::string_view secret) {
  std::vector<std::byte> body(7 + secret.size());
  put16(body, 0, 1);
  put32(body, 2, static_cast<std::uint32_t>(secret.size()));
  body[6] = std::byte{'k'};
  std::transform(secret.begin(), secret.end(), body.begin() + 7,
                 [](char value) { return static_cast<std::byte>(value); });
  std::vector<std::byte> request(24 + body.size());
  put16(request, 0,
        static_cast<std::uint16_t>(permissions::OperationId::storage_write));
  put16(request, 2, 16);
  put32(request, 4, static_cast<std::uint32_t>(body.size()));
  put64(request, 8, 4096);
  put64(request, 16, 1024);
  std::copy(body.begin(), body.end(), request.begin() + 24);
  return request;
}

std::vector<std::byte> notification_request() {
  constexpr std::string_view title = "secret-title";
  constexpr std::string_view body = "secret-body";
  std::vector<std::byte> provider(4 + title.size() + body.size());
  put16(provider, 0, static_cast<std::uint16_t>(title.size()));
  put16(provider, 2, static_cast<std::uint16_t>(body.size()));
  std::transform(title.begin(), title.end(), provider.begin() + 4,
                 [](char value) { return static_cast<std::byte>(value); });
  std::transform(body.begin(), body.end(), provider.begin() + 4 + title.size(),
                 [](char value) { return static_cast<std::byte>(value); });
  std::vector<std::byte> request(10 + 5 + provider.size());
  put16(
      request, 0,
      static_cast<std::uint16_t>(permissions::OperationId::notification_send));
  put16(request, 2, 7);
  put32(request, 4, static_cast<std::uint32_t>(provider.size()));
  put16(request, 8, 5);
  for (std::size_t index = 0; index < 5; ++index)
    request[10 + index] = static_cast<std::byte>("timer"[index]);
  std::copy(provider.begin(), provider.end(), request.begin() + 15);
  return request;
}

std::vector<std::byte> fake_list_request() {
  std::vector<std::byte> request(16);
  put16(request, 0,
        static_cast<std::uint16_t>(permissions::OperationId::fake_status_list));
  put16(request, 2, 8);
  put32(request, 4, 0);
  put32(request, 8, 1);
  put16(request, 12,
        static_cast<std::uint16_t>(permissions::OperationId::fake_status_list));
  put16(request, 14, 0);
  return request;
}

wire::PacketView request_packet(permissions::OperationId operation,
                                std::uint64_t correlation,
                                std::span<const std::byte> payload) {
  return {
      .header = {.endpoint_role = wire::EndpointRole::broker,
                 .message_type = static_cast<std::uint16_t>(operation),
                 .role_protocol_version = broker::kBrokerRoleVersion,
                 .payload_length = static_cast<std::uint32_t>(payload.size()),
                 .launch_generation = 11,
                 .correlation_id = correlation},
      .payload = payload};
}

wire::PacketView terminal_packet(std::uint64_t correlation) {
  return {.header = {.endpoint_role = wire::EndpointRole::broker,
                     .message_type = broker::kBrokerResultMessage,
                     .role_protocol_version = broker::kBrokerRoleVersion,
                     .payload_length = 0,
                     .launch_generation = 11,
                     .correlation_id = correlation},
          .payload = {}};
}

wire::PacketView cancel_packet(std::uint64_t correlation) {
  return {.header = {.endpoint_role = wire::EndpointRole::broker,
                     .message_type = static_cast<std::uint16_t>(
                         wire::CommonMessageType::cancel),
                     .role_protocol_version = broker::kBrokerRoleVersion,
                     .payload_length = 0,
                     .launch_generation = 11,
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
                 .launch_generation = 11,
                 .correlation_id = correlation},
      .payload = payload};
}

struct Backend {
  static bool write(std::string_view, std::span<const std::byte>,
                    void *opaque) noexcept {
    auto &self = *static_cast<Backend *>(opaque);
    const auto records = self.audit_store->query({});
    self.admitted_before_effect =
        records.status.ok() && !records.records.empty() &&
        records.records.back().outcome == permissions::AuditOutcome::allowed;
    ++self.writes;
    return true;
  }
  static bool notify(std::string_view, std::string_view, std::string_view,
                     void *opaque) noexcept {
    ++static_cast<Backend *>(opaque)->notifications;
    return true;
  }
  audit::AuditStore *audit_store = nullptr;
  int writes = 0;
  int notifications = 0;
  bool admitted_before_effect = false;
};

providers::ProviderConfiguration configuration(Backend &backend) {
  providers::ProviderConfiguration result;
  result.storage.write = Backend::write;
  result.storage.context = &backend;
  result.storage.maximum_total_bytes = 4096;
  result.storage.maximum_item_bytes = 1024;
  result.notification.send = Backend::notify;
  result.notification.context = &backend;
  return result;
}

permissions::HandleId handle(char value) {
  permissions::HandleId result;
  result.bytes.fill(static_cast<std::byte>(value));
  return result;
}

void test_authority_audit_handles_revocation_and_recovery() {
  TemporaryDirectory temporary;
  audit::AuditStore store(temporary.path() / "audit", {.maximum_records = 128});
  Backend backend{.audit_store = &store};
  auto active = revision();
  runtime::AuditedBrokerRuntime broker_runtime(active, configuration(backend),
                                               store);

  constexpr std::string_view secret = "never-export-this-value";
  const auto write = storage_write_request(secret);
  const auto dispatched = broker_runtime.dispatch(
      request_packet(permissions::OperationId::storage_write, 41, write), 100);
  require(dispatched.outcome == broker::DispatchOutcome::dispatched &&
              backend.writes == 1 && backend.admitted_before_effect,
          "effect ran without durable audit admission");

  const auto expanded = broker_runtime.issue_handle(
      handle('x'), 41, permissions::OperationId::storage_write,
      permissions::QuotaScope{8192, 2048}, 1000);
  require(expanded.status == runtime::RuntimeStatus::denied,
          "handle expanded beyond the authorized request demand");

  const auto issued = broker_runtime.issue_handle(
      handle('h'), 41, permissions::OperationId::storage_write, quota(), 1000);
  require(issued.status == runtime::RuntimeStatus::accepted &&
              broker_runtime
                      .resolve_handle(handle('h'), 71,
                                      permissions::OperationId::storage_write,
                                      quota(), 200)
                      .decision == permissions::HandleDecision::allowed,
          "authorized handle was not bound to the live grant");
  require(broker_runtime.accept_terminal(terminal_packet(41)) ==
              broker::TerminalResult::accepted,
          "authorized request terminal was rejected");
  require(broker_runtime
                  .resolve_handle(handle('f'), 72,
                                  permissions::OperationId::storage_write,
                                  quota(), 200)
                  .decision == permissions::HandleDecision::unknown,
          "forged handle did not fail closed");

  const auto denied_payload = notification_request();
  const auto denied = broker_runtime.dispatch(
      request_packet(permissions::OperationId::notification_send, 42,
                     denied_payload),
      100);
  require(denied.outcome == broker::DispatchOutcome::denied &&
              backend.notifications == 0,
          "denied provider effect escaped authority");

  const auto fake = fake_list_request();
  permissions::GestureProof gesture{
      .id = {},
      .plugin = active.binding.plugin,
      .generation = active.binding.generation,
      .surface = 1,
      .operation = permissions::OperationId::fake_status_list,
      .expires_monotonic_ns = 1000,
      .consumed = false};
  gesture.id.bytes.fill(std::byte{'g'});
  const auto pending = broker_runtime.dispatch(
      request_packet(permissions::OperationId::fake_status_list, 43, fake), 100,
      {}, &gesture);
  require(pending.outcome == broker::DispatchOutcome::pending &&
              broker_runtime.accept_cancel(cancel_packet(43)) ==
                  broker::CancelResult::provider_notified &&
              broker_runtime.accept_terminal(terminal_packet(43)) ==
                  broker::TerminalResult::accepted,
          "audited asynchronous cancellation was not accepted");
  const auto cancel_result =
      wire::encode_cancel_result_payload(wire::CancelOutcome::accepted);
  require(broker_runtime.accept_cancel_result(cancel_result_packet(
              43, cancel_result)) == broker::CancelResult::accepted,
          "cancel acknowledgement did not release the correlation");

  grant::RevocationResult revocation{
      .mutation_sequence = 8,
      .target = grant::TargetRevision::active,
      .grant = {key("storage.private"), quota(),
                permissions::GrantState::revoked, 5},
      .action = permissions::RevocationMode::cancel_inflight,
      .grant_fingerprint = "unused-by-runtime"};
  const auto revoked = broker_runtime.apply_revocation(revocation);
  require(revoked.status == runtime::RuntimeStatus::accepted &&
              broker_runtime
                      .resolve_handle(handle('h'), 73,
                                      permissions::OperationId::storage_write,
                                      quota(), 200)
                      .decision == permissions::HandleDecision::stale_grant,
          "revocation did not stale the exact issued epoch");
  require(broker_runtime.apply_revocation(revocation).status ==
              runtime::RuntimeStatus::binding_mismatch,
          "replayed revocation was accepted");

  const auto records = store.query({});
  require(records.status.ok() && records.records.size() >= 7,
          "authoritative events were not retained");
  std::string exported;
  require(store.export_tsv({}, exported).ok() &&
              exported.find(secret) == std::string::npos &&
              exported.find("secret-title") == std::string::npos,
          "audit export disclosed provider payload");

  active.grants.values()[0] = revocation.grant;
  audit::AuditStore recovered_store(temporary.path() / "audit",
                                    {.maximum_records = 128});
  Backend recovered_backend{.audit_store = &recovered_store};
  runtime::AuditedBrokerRuntime recovered(
      active, configuration(recovered_backend), recovered_store);
  const auto after_restart = recovered.dispatch(
      request_packet(permissions::OperationId::storage_write, 51, write), 300);
  require(after_restart.outcome == broker::DispatchOutcome::denied &&
              recovered_backend.writes == 0 &&
              recovered
                      .resolve_handle(handle('h'), 74,
                                      permissions::OperationId::storage_write,
                                      quota(), 300)
                      .decision == permissions::HandleDecision::unknown,
          "recovery resurrected revoked authority or an ephemeral handle");
}

void test_audit_failure_prevents_effect() {
  TemporaryDirectory temporary;
  const auto audit_path = temporary.path() / "audit";
  audit::AuditStore store(audit_path, {.maximum_records = 16});
  require(store.recover().ok(), "audit failure fixture setup");
  Backend backend{.audit_store = &store};
  runtime::AuditedBrokerRuntime broker_runtime(revision(),
                                               configuration(backend), store);
  std::filesystem::permissions(audit_path,
                               std::filesystem::perms::owner_all |
                                   std::filesystem::perms::group_read,
                               std::filesystem::perm_options::replace);
  const auto write = storage_write_request("blocked-secret");
  const auto result = broker_runtime.dispatch(
      request_packet(permissions::OperationId::storage_write, 61, write), 100);
  require(result.outcome == broker::DispatchOutcome::core_failed &&
              backend.writes == 0 && broker_runtime.failed(),
          "audit admission failure did not poison before effect");
}

void test_poisoned_runtime_cannot_resolve_existing_handle() {
  TemporaryDirectory temporary;
  const auto audit_path = temporary.path() / "audit";
  audit::AuditStore store(audit_path, {.maximum_records = 16});
  Backend backend{.audit_store = &store};
  runtime::AuditedBrokerRuntime broker_runtime(revision(),
                                               configuration(backend), store);
  const auto write = storage_write_request("before-poison");
  require(broker_runtime
                  .dispatch(request_packet(
                                permissions::OperationId::storage_write, 81,
                                write),
                            100)
                  .outcome == broker::DispatchOutcome::dispatched &&
              broker_runtime
                      .issue_handle(handle('p'), 81,
                                    permissions::OperationId::storage_write,
                                    quota(), 1000)
                      .status == runtime::RuntimeStatus::accepted,
          "poison fixture could not issue an initially valid handle");

  std::filesystem::permissions(audit_path,
                               std::filesystem::perms::owner_all |
                                   std::filesystem::perms::group_read,
                               std::filesystem::perm_options::replace);
  require(broker_runtime
                  .dispatch(request_packet(
                                permissions::OperationId::storage_write, 82,
                                write),
                            100)
                  .outcome == broker::DispatchOutcome::core_failed &&
              broker_runtime.failed(),
          "audit failure did not poison handle fixture");
  const auto resolved = broker_runtime.resolve_handle(
      handle('p'), 83, permissions::OperationId::storage_write, quota(), 200);
  require(resolved.status == runtime::RuntimeStatus::audit_failed &&
              resolved.decision == permissions::HandleDecision::invalid,
          "poisoned runtime continued resolving an existing authority handle");
}

} // namespace

int main() {
  try {
    test_authority_audit_handles_revocation_and_recovery();
    test_audit_failure_prevents_effect();
    test_poisoned_runtime_cannot_resolve_existing_handle();
  } catch (const std::exception &error) {
    std::cerr << "FAIL: " << error.what() << '\n';
    return 1;
  }
  std::cout << "broker runtime integration tests passed\n";
  return 0;
}
