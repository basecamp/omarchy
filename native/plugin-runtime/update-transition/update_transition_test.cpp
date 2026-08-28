#include "update_transition.hpp"

#include "manifest_contract.hpp"
#include "omarchy/plugin_runtime/broker/broker_schema.hpp"

#include <algorithm>
#include <array>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <memory>
#include <stdexcept>
#include <string>
#include <string_view>
#include <unistd.h>
#include <vector>

namespace {

namespace audit = omarchy::plugins::audit;
namespace broker = omarchy::plugin_runtime::broker;
namespace grant = omarchy::plugins::grants;
namespace health = omarchy::plugin_runtime::health;
namespace lifecycle = omarchy::plugins::lifecycle;
namespace manifest = omarchy::plugins::manifest;
namespace permissions = omarchy::plugins::permissions;
namespace providers = omarchy::plugin_runtime::providers;
namespace runtime = omarchy::plugin_runtime::runtime;
namespace transition = omarchy::plugin_runtime::transition;
namespace wire = omarchy::plugin::wire;

void require(bool condition, std::string_view message) {
  if (!condition)
    throw std::runtime_error(std::string(message));
}

class TemporaryDirectory {
public:
  TemporaryDirectory() {
    std::string pattern = "/tmp/omarchy-transition-XXXXXX";
    char *created = ::mkdtemp(pattern.data());
    if (created == nullptr)
      throw std::runtime_error("mkdtemp failed");
    path_ = created;
  }
  ~TemporaryDirectory() {
    std::error_code error;
    for (auto iterator = std::filesystem::recursive_directory_iterator(
             path_, std::filesystem::directory_options::skip_permission_denied,
             error);
         iterator != std::filesystem::recursive_directory_iterator();
         iterator.increment(error)) {
      std::filesystem::permissions(iterator->path(),
                                   std::filesystem::perms::owner_all,
                                   std::filesystem::perm_options::add, error);
      error.clear();
    }
    std::filesystem::permissions(path_, std::filesystem::perms::owner_all,
                                 std::filesystem::perm_options::add, error);
    std::filesystem::remove_all(path_, error);
  }
  const std::filesystem::path &path() const { return path_; }

private:
  std::filesystem::path path_;
};

std::string read_file(const std::filesystem::path &path) {
  std::ifstream input(path, std::ios::binary);
  require(input.good(), "fixture file is unavailable");
  return {std::istreambuf_iterator<char>(input), {}};
}

void write_file(const std::filesystem::path &path, std::string_view bytes) {
  std::ofstream output(path, std::ios::binary | std::ios::trunc);
  require(output.good(), "cannot write fixture file");
  output << bytes;
  require(output.good(), "cannot finish fixture file");
}

std::filesystem::path source(const std::filesystem::path &temporary,
                             std::string_view name, bool expanded) {
  const auto root = temporary / std::string(name);
  const auto plugin = root / "plugin";
  std::filesystem::create_directories(root);
  std::filesystem::copy(MANIFEST_V2_FIXTURE_ROOT, plugin,
                        std::filesystem::copy_options::recursive);
  std::ofstream(plugin / "ui/Status.qml", std::ios::app)
      << "\n// " << name << '\n';
  if (expanded) {
    auto bytes = read_file(plugin / "manifest.json");
    const auto quota = bytes.find("1048576");
    require(quota != std::string::npos, "quota fixture changed");
    bytes.replace(quota, 7, "2097152");
    const auto optional = bytes.find("\"optional\": [");
    require(optional != std::string::npos, "optional fixture changed");
    const auto insertion =
        optional + std::string_view("\"optional\": [").size();
    bytes.insert(insertion,
                 R"(
      {
        "capability": "service.fake-status",
        "resourceIds": [1],
        "operations": ["list", "acknowledge"],
        "reason": "Show trusted test status"
      },)");
    write_file(plugin / "manifest.json", bytes);
  }
  return root;
}

manifest::ContentIdentity identity(const std::filesystem::path &root) {
  const auto plugin = root / "plugin";
  const auto parsed =
      manifest::parse_manifest_v2(read_file(plugin / "manifest.json"));
  return manifest::identify_tree(plugin, parsed);
}

const grant::PluginGrants &only_plugin(const grant::StoreState &state) {
  require(state.plugins.size() == 1, "expected one plugin grant record");
  return state.plugins.front();
}

grant::RequestBundle bundle(const grant::RevisionGrants &revision) {
  return grant::make_bundle(2, revision.binding.plugin,
                            revision.binding.revision,
                            revision.source_request_fingerprint,
                            revision.binding.generation, revision.requests);
}

permissions::CapabilityKey key(std::string_view id) {
  return {.id = permissions::CapabilityId(id), .version = 1};
}

struct Probe {
  bool alive = true;
  bool terminate_result = true;
  int terminations = 0;
};

class FakeWorker final : public health::WorkerControl {
public:
  FakeWorker(const permissions::ActivationBinding &binding,
             std::shared_ptr<Probe> probe)
      : probe_(std::move(probe)) {
    identity_.plugin_id = std::string(binding.plugin.view());
    identity_.revision_sha256 = std::string(binding.revision.view());
    identity_.generation = binding.generation;
    identity_.outer_worker_pid = 100;
  }
  const omarchy::plugin_runtime::launcher::LaunchIdentity &
  identity() const override {
    return identity_;
  }
  bool alive() const override { return probe_->alive; }
  bool terminate() override {
    ++probe_->terminations;
    if (probe_->terminate_result)
      probe_->alive = false;
    return probe_->terminate_result;
  }

private:
  omarchy::plugin_runtime::launcher::LaunchIdentity identity_;
  std::shared_ptr<Probe> probe_;
};

std::unique_ptr<health::WorkerControl>
worker(const permissions::ActivationBinding &binding,
       const std::shared_ptr<Probe> &probe) {
  return std::make_unique<FakeWorker>(binding, probe);
}

providers::ProviderConfiguration
configuration(const grant::RevisionGrants &revision) {
  providers::ProviderConfiguration result;
  result.binding = revision.binding;
  return result;
}

std::shared_ptr<runtime::AuditedBrokerRuntime>
broker_runtime(const grant::RevisionGrants &revision,
               audit::AuditStore &audit_store) {
  return std::make_shared<runtime::AuditedBrokerRuntime>(
      revision, configuration(revision), audit_store);
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

std::vector<std::byte>
storage_write_request(const permissions::QuotaScope &scope) {
  constexpr std::string_view value = "state";
  std::vector<std::byte> body(7 + value.size());
  put16(body, 0, 1);
  put32(body, 2, value.size());
  body[6] = std::byte{'k'};
  std::transform(value.begin(), value.end(), body.begin() + 7,
                 [](char byte) { return static_cast<std::byte>(byte); });
  std::vector<std::byte> request(24 + body.size());
  put16(request, 0,
        static_cast<std::uint16_t>(permissions::OperationId::storage_write));
  put16(request, 2, 16);
  put32(request, 4, body.size());
  put64(request, 8, scope.total_bytes);
  put64(request, 16, scope.item_bytes);
  std::copy(body.begin(), body.end(), request.begin() + 24);
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

wire::PacketView packet(permissions::OperationId operation,
                        std::uint64_t generation, std::uint64_t correlation,
                        std::span<const std::byte> payload) {
  return {
      .header = {.endpoint_role = wire::EndpointRole::broker,
                 .message_type = static_cast<std::uint16_t>(operation),
                 .role_protocol_version = broker::kBrokerRoleVersion,
                 .payload_length = static_cast<std::uint32_t>(payload.size()),
                 .launch_generation = generation,
                 .correlation_id = correlation},
      .payload = payload};
}

permissions::HandleId handle() {
  permissions::HandleId result;
  result.bytes.fill(std::byte{'h'});
  return result;
}

grant::RevisionGrants
install_initial(lifecycle::LifecycleManager &manager,
                const std::filesystem::path &root,
                const manifest::ContentIdentity &content) {
  const auto staged = manager.stage(root, "plugin", content.tree_sha256);
  require(staged.result.ok() && staged.binding &&
              staged.permission_review_required,
          "initial revision did not stage for review");
  const auto state = manager.grants().read();
  const auto request = bundle(*only_plugin(state).candidate);
  const auto preview =
      manager.grants().preview(request, key("storage.private"));
  (void)manager.grants().decide(request, key("storage.private"), std::nullopt,
                                permissions::UserDecision::grant,
                                permissions::DecisionActor::trusted_ui, 1,
                                preview.expected_mutation_sequence);
  require(manager.enable(permissions::PluginId("org.example.status")).ok(),
          "initial reviewed revision did not activate");
  return *only_plugin(manager.grants().read()).active;
}

void expanding_update_and_live_revocation() {
  TemporaryDirectory temporary;
  lifecycle::LifecycleManager lifecycle(temporary.path() / "revisions",
                                        temporary.path() / "grants");
  audit::AuditStore audit_store(temporary.path() / "audit",
                                {.maximum_records = 256});
  health::HealthSupervisor health({}, audit_store);
  const auto initial_root = source(temporary.path(), "initial", false);
  const auto initial_identity = identity(initial_root);
  const auto initial =
      install_initial(lifecycle, initial_root, initial_identity);
  transition::UpdateTransition update(
      lifecycle, health, permissions::PluginId("org.example.status"));
  auto old_probe = std::make_shared<Probe>();
  require(update
              .bind_active(worker(initial.binding, old_probe),
                           broker_runtime(initial, audit_store), 10)
              .ok(),
          "initial live session did not bind exactly");
  require(health.admit_request(initial.binding, 900, 10, 10) ==
                  health::Status::accepted &&
              health.open_surface(initial.binding, {77, 1}) ==
                  health::Status::accepted,
          "old generation resource fixture failed");

  const auto expanded_root = source(temporary.path(), "expanded", true);
  const auto expanded_identity = identity(expanded_root);
  const auto staged =
      update.stage(expanded_root, "plugin", expanded_identity.tree_sha256);
  require(staged.result.ok(),
          "permission-expanding stage failed: " + staged.result.detail);
  require(staged.binding.has_value(), "staged expansion has no binding");
  require(staged.permission_review_required,
          "permission expansion did not require review");
  require(lifecycle.revisions().current()->active.revision_sha256 ==
              initial_identity.tree_sha256,
          "permission expansion replaced the active revision");
  require(old_probe->terminations == 0,
          "permission expansion terminated the old worker");

  auto premature_probe = std::make_shared<Probe>();
  const auto premature_state = lifecycle.grants().read();
  const auto premature = *only_plugin(premature_state).candidate;
  require(update.prepare_candidate(worker(premature.binding, premature_probe),
                                   broker_runtime(premature, audit_store), 11)
                      .status == transition::Status::denied &&
              premature_probe->terminations == 1,
          "unreviewed candidate crossed the health gate");

  require(update.decide_candidate(key("storage.private"), std::nullopt,
                                  permissions::UserDecision::grant, 2)
                  .ok() &&
              update
                  .decide_candidate(key("service.fake-status"), std::nullopt,
                                    permissions::UserDecision::grant, 3)
                  .ok(),
          "trusted candidate decisions failed");
  auto stale_grant_probe = std::make_shared<Probe>();
  require(update.prepare_candidate(worker(premature.binding, stale_grant_probe),
                                   broker_runtime(premature, audit_store), 12)
                      .status == transition::Status::stale &&
              stale_grant_probe->terminations == 1,
          "candidate runtime with stale grant epochs was admitted");
  const auto reviewed = *only_plugin(lifecycle.grants().read()).candidate;
  auto candidate_probe = std::make_shared<Probe>();
  require(update.prepare_candidate(worker(reviewed.binding, candidate_probe),
                                   broker_runtime(reviewed, audit_store), 12)
                  .ok() &&
              update.activate().status == transition::Status::denied &&
              lifecycle.revisions().current()->active.revision_sha256 ==
                  initial_identity.tree_sha256 &&
              health.admit_request(reviewed.binding, 901, 1, 12) ==
                  health::Status::not_ready &&
              update.candidate_ready(12).ok(),
          "candidate activation bypassed explicit review or health");
  const auto activation_fault = update.activate(
      omarchy::plugins::store::FaultPoint::activate_after_write);
  require(!activation_fault.ok() && old_probe->terminations == 0 &&
              lifecycle.revisions().current()->active.revision_sha256 ==
                  initial_identity.tree_sha256 &&
              health.request_count() == 1 && health.surface_count() == 1,
          "failed activation did not preserve old healthy authority");
  require(update.activate().ok(),
          "healthy reviewed candidate did not activate");
  require(old_probe->terminations == 1 && candidate_probe->terminations == 0 &&
              lifecycle.revisions().current()->active.revision_sha256 ==
                  expanded_identity.tree_sha256 &&
              health.worker_count() == 1 && health.request_count() == 0 &&
              health.surface_count() == 0 &&
              health.admit_request(initial.binding, 902, 1, 13) ==
                  health::Status::stale_generation &&
              health.admit_request(reviewed.binding, 902, 1, 13) ==
                  health::Status::accepted,
          "atomic promotion retained old channel/request/surface authority");
  require(health.complete_request(reviewed.binding, 902) ==
              health::Status::accepted,
          "new generation request cleanup failed");

  auto active = update.active_runtime();
  require(active && active->add_fake_status(1, 7, "bounded"),
          "active broker fixture setup failed");
  permissions::GestureProof gesture{
      .id = {},
      .plugin = reviewed.binding.plugin,
      .generation = reviewed.binding.generation,
      .surface = 1,
      .operation = permissions::OperationId::fake_status_list,
      .expires_monotonic_ns = 1000,
      .consumed = false};
  gesture.id.bytes.fill(std::byte{'g'});
  const auto fake = fake_list_request();
  require(active->dispatch(packet(permissions::OperationId::fake_status_list,
                                  reviewed.binding.generation, 41, fake),
                           100, {}, &gesture)
                  .outcome == broker::DispatchOutcome::pending,
          "revocation fixture did not create in-flight work");
  const auto fake_revoked = update.revoke(key("service.fake-status"));
  require(fake_revoked.status == runtime::RuntimeStatus::accepted &&
              fake_revoked.cancelled_count == 1 &&
              fake_revoked.cancelled[0] == 41 && !fake_revoked.restart_worker,
          "live revocation did not cancel exact in-flight work");
  permissions::GestureProof second_gesture = gesture;
  second_gesture.id.bytes.fill(std::byte{'j'});
  second_gesture.consumed = false;
  require(active->dispatch(packet(permissions::OperationId::fake_status_list,
                                  reviewed.binding.generation, 42, fake),
                           100, {}, &second_gesture)
                  .outcome == broker::DispatchOutcome::denied,
          "revocation admitted a new operation");

  const auto storage_grant =
      std::find_if(reviewed.grants.values().begin(),
                   reviewed.grants.values().end(), [](const auto &record) {
                     return record.capability == key("storage.private");
                   });
  require(storage_grant != reviewed.grants.values().end(),
          "reviewed storage grant is absent");
  const auto storage_scope =
      std::get<permissions::QuotaScope>(storage_grant->scope);
  const auto storage = storage_write_request(storage_scope);
  const auto storage_dispatch =
      active->dispatch(packet(permissions::OperationId::storage_write,
                              reviewed.binding.generation, 50, storage),
                       100);
  require(storage_dispatch.outcome == broker::DispatchOutcome::provider_failed,
          "storage fixture did not reach its bound provider");
  const auto issued = active->issue_handle(
      handle(), 50, permissions::OperationId::storage_write, storage_scope,
      1000);
  require(issued.status == runtime::RuntimeStatus::accepted,
          "handle revocation fixture did not issue a live handle");
  const auto storage_revoked = update.revoke(key("storage.private"));
  require(storage_revoked.status == runtime::RuntimeStatus::accepted &&
              active->resolve_handle(handle(), 60,
                                     permissions::OperationId::storage_write,
                                     storage_scope, 200)
                      .decision == permissions::HandleDecision::stale_grant,
          "revocation did not stale an issued handle");

  const auto records = audit_store.query({});
  require(records.status.ok(), "revocation audit query failed");
  std::size_t revoked_sequence = 0;
  std::size_t cancelled_sequence = 0;
  for (const auto &record : records.records) {
    if (record.event == permissions::AuditEvent::capability_revoked &&
        record.capability &&
        record.capability->id.view() == "service.fake-status")
      revoked_sequence = record.sequence;
    if (record.event == permissions::AuditEvent::operation_decided &&
        record.correlation == 41 &&
        record.outcome == permissions::AuditOutcome::cancelled)
      cancelled_sequence = record.sequence;
  }
  require(revoked_sequence > 0 && cancelled_sequence > revoked_sequence,
          "revocation effect preceded its authoritative audit admission");
}

void promotion_failure_rolls_back_without_authority() {
  TemporaryDirectory temporary;
  lifecycle::LifecycleManager lifecycle(temporary.path() / "revisions",
                                        temporary.path() / "grants");
  audit::AuditStore audit_store(temporary.path() / "audit",
                                {.maximum_records = 128});
  health::HealthSupervisor health({}, audit_store);
  const auto initial_root = source(temporary.path(), "rollback-initial", false);
  const auto initial_identity = identity(initial_root);
  const auto initial =
      install_initial(lifecycle, initial_root, initial_identity);
  transition::UpdateTransition update(
      lifecycle, health, permissions::PluginId("org.example.status"));
  auto old_probe = std::make_shared<Probe>();
  old_probe->terminate_result = false;
  require(update
              .bind_active(worker(initial.binding, old_probe),
                           broker_runtime(initial, audit_store), 10)
              .ok(),
          "rollback fixture could not bind old authority");
  require(health.admit_request(initial.binding, 700, 1, 10) ==
                  health::Status::accepted &&
              health.open_surface(initial.binding, {70, 1}) ==
                  health::Status::accepted,
          "rollback fixture could not track old resources");

  const auto expanded_root =
      source(temporary.path(), "rollback-expanded", true);
  const auto expanded_identity = identity(expanded_root);
  const auto staged =
      update.stage(expanded_root, "plugin", expanded_identity.tree_sha256);
  require(staged.result.ok() && staged.binding,
          "rollback candidate did not stage");
  require(update.decide_candidate(key("storage.private"), std::nullopt,
                                  permissions::UserDecision::grant, 2)
                  .ok() &&
              update
                  .decide_candidate(key("service.fake-status"), std::nullopt,
                                    permissions::UserDecision::grant, 3)
                  .ok(),
          "rollback candidate review failed");
  const auto candidate = *only_plugin(lifecycle.grants().read()).candidate;
  auto candidate_probe = std::make_shared<Probe>();
  require(update.prepare_candidate(worker(candidate.binding, candidate_probe),
                                   broker_runtime(candidate, audit_store), 11)
                  .ok() &&
              update.candidate_ready(11).ok(),
          "rollback candidate did not become healthy");

  const auto activated = update.activate();
  const auto rolled_back = lifecycle.revisions().current();
  require(
      activated.status == transition::Status::health_failed && rolled_back &&
          rolled_back->active.revision_sha256 == initial_identity.tree_sha256 &&
          rolled_back->active.generation > candidate.binding.generation &&
          !update.active_binding() && !update.active_runtime() &&
          candidate_probe->terminations == 1 && old_probe->terminations == 1 &&
          old_probe->alive && health.failed() && health.worker_count() == 0 &&
          health.request_count() == 0 && health.surface_count() == 0 &&
          health.admit_request(initial.binding, 701, 1, 12) ==
              health::Status::stale_generation &&
          health.admit_request(candidate.binding, 702, 1, 12) ==
              health::Status::stale_generation,
      "promotion failure retained authority or failed fresh-generation "
      "rollback");
}

} // namespace

int main() {
  try {
    expanding_update_and_live_revocation();
    promotion_failure_rolls_back_without_authority();
  } catch (const std::exception &error) {
    std::cerr << "update transition test failed: " << error.what() << '\n';
    return EXIT_FAILURE;
  }
  std::cout << "update transition tests passed\n";
  return EXIT_SUCCESS;
}
