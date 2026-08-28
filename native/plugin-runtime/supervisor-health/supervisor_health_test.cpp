#include "supervisor_health.hpp"

#include <cstdlib>
#include <filesystem>
#include <iostream>
#include <memory>
#include <stdexcept>
#include <string>
#include <string_view>
#include <unistd.h>

namespace {

namespace audit = omarchy::plugins::audit;
namespace health = omarchy::plugin_runtime::health;
namespace launcher = omarchy::plugin_runtime::launcher;
namespace permissions = omarchy::plugins::permissions;

void require(bool condition, std::string_view message) {
  if (!condition)
    throw std::runtime_error(std::string(message));
}

class TemporaryDirectory {
public:
  TemporaryDirectory() {
    std::string pattern = "/tmp/omarchy-health-XXXXXX";
    char *created = ::mkdtemp(pattern.data());
    if (created == nullptr)
      throw std::runtime_error("mkdtemp failed");
    path_ = created;
  }
  ~TemporaryDirectory() {
    std::error_code error;
    std::filesystem::permissions(path_, std::filesystem::perms::owner_all,
                                 std::filesystem::perm_options::add, error);
    std::filesystem::remove_all(path_, error);
  }
  const std::filesystem::path &path() const { return path_; }

private:
  std::filesystem::path path_;
};

permissions::Digest digest(char value) {
  return permissions::Digest(std::string(64, value));
}

permissions::ActivationBinding binding(std::string_view plugin,
                                       std::uint64_t generation,
                                       char revision = 'a') {
  return {.plugin = permissions::PluginId(plugin),
          .revision = digest(revision),
          .policy_fingerprint = digest('f'),
          .generation = generation};
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
  const launcher::LaunchIdentity &identity() const override {
    return identity_;
  }
  bool alive() const override { return probe_->alive; }
  bool terminate() override {
    ++probe_->terminations;
    probe_->alive = false;
    return probe_->terminate_result;
  }

private:
  launcher::LaunchIdentity identity_;
  std::shared_ptr<Probe> probe_;
};

std::unique_ptr<health::WorkerControl>
worker(const permissions::ActivationBinding &binding,
       const std::shared_ptr<Probe> &probe) {
  return std::make_unique<FakeWorker>(binding, probe);
}

health::HealthPolicy test_policy() {
  health::HealthPolicy policy;
  policy.maximum_workers = 2;
  policy.maximum_requests_per_worker = 1;
  policy.maximum_requests_global = 1;
  policy.maximum_surfaces_per_worker = 1;
  policy.maximum_surfaces_global = 1;
  policy.maximum_request_bytes = 128;
  policy.maximum_request_starts_per_window = 3;
  policy.request_rate_window_seconds = 5;
  policy.memory_max_bytes = 1024;
  policy.scratch_max_bytes = 256;
  policy.tasks_max = 2;
  policy.hello_timeout_seconds = 2;
  policy.request_timeout_seconds = 3;
  policy.restart_window_seconds = 20;
  policy.restart_burst = 3;
  policy.restart_backoff_initial_seconds = 1;
  policy.restart_backoff_max_seconds = 4;
  policy.stable_reset_seconds = 30;
  return policy;
}

void limits_timeout_cleanup_and_crash_loop() {
  TemporaryDirectory temporary;
  audit::AuditStore store(temporary.path() / "audit", {.maximum_records = 128});
  health::HealthSupervisor supervisor(test_policy(), store);
  const auto first = binding("org.example.health", 1);
  auto first_probe = std::make_shared<Probe>();
  require(supervisor.adopt(worker(first, first_probe), first, 10) ==
                  health::Status::accepted &&
              supervisor.admit_request(first, 1, 10, 10) ==
                  health::Status::not_ready &&
              supervisor.ready(first, 11) == health::Status::accepted,
          "startup health gate failed");
  require(
      supervisor.admit_request(first, 7, 128, 11) == health::Status::accepted &&
          supervisor.admit_request(first, 7, 1, 11) ==
              health::Status::duplicate &&
          supervisor.admit_request(first, 8, 1, 11) ==
              health::Status::limit_exceeded &&
          supervisor.admit_request(first, 9, 129, 11) ==
              health::Status::denied &&
          supervisor.open_surface(first, {10, 1}) == health::Status::accepted &&
          supervisor.open_surface(first, {10, 1}) ==
              health::Status::duplicate &&
          supervisor.open_surface(first, {10, 2}) ==
              health::Status::stale_generation &&
          supervisor.close_surface(first, {10, 2}) ==
              health::Status::stale_generation &&
          supervisor.close_surface(first, {99, 1}) == health::Status::denied &&
          supervisor.open_surface(first, {11, 1}) ==
              health::Status::limit_exceeded,
      "per-generation request or surface limits failed");

  const auto second_plugin = binding("org.example.second", 1, 'b');
  auto second_probe = std::make_shared<Probe>();
  require(supervisor.adopt(worker(second_plugin, second_probe), second_plugin,
                           11) == health::Status::accepted &&
              supervisor.ready(second_plugin, 11) == health::Status::accepted &&
              supervisor.admit_request(second_plugin, 1, 1, 11) ==
                  health::Status::limit_exceeded &&
              supervisor.open_surface(second_plugin, {20, 1}) ==
                  health::Status::limit_exceeded,
          "global request or surface limits failed");
  require(supervisor.stop(second_plugin) == health::Status::accepted,
          "bounded normal stop failed");

  supervisor.tick(15);
  require(first_probe->terminations == 1 && supervisor.worker_count() == 0 &&
              supervisor.request_count() == 0 &&
              supervisor.surface_count() == 0 &&
              supervisor.complete_request(first, 7) ==
                  health::Status::stale_generation &&
              supervisor.restart_decision(first.plugin, first.revision, 15)
                      .status == health::Status::backoff,
          "request timeout retained stale generation state");

  const auto second = binding("org.example.health", 2);
  auto crash_probe = std::make_shared<Probe>();
  require(supervisor.adopt(worker(second, crash_probe), second, 16) ==
                  health::Status::accepted &&
              supervisor.ready(second, 16) == health::Status::accepted,
          "first bounded restart was denied");
  crash_probe->alive = false;
  require(supervisor.worker_exited(second, 17) == health::Status::backoff &&
              supervisor.restart_decision(second.plugin, second.revision, 18)
                      .status == health::Status::backoff,
          "second crash did not increase backoff");

  const auto third = binding("org.example.health", 3);
  auto timeout_probe = std::make_shared<Probe>();
  require(supervisor.adopt(worker(third, timeout_probe), third, 19) ==
              health::Status::accepted,
          "second bounded restart was denied");
  supervisor.tick(22);
  require(timeout_probe->terminations == 1 &&
              supervisor.restart_decision(third.plugin, third.revision, 30)
                      .status == health::Status::disabled,
          "crash burst did not disable the exact revision");

  const auto new_revision = binding("org.example.health", 4, 'c');
  auto new_probe = std::make_shared<Probe>();
  require(supervisor.adopt(worker(new_revision, new_probe), new_revision, 30) ==
                  health::Status::accepted &&
              supervisor.ready(new_revision, 30) == health::Status::accepted &&
              supervisor.observe_resources(new_revision, {1025, 0, 1}, 31) ==
                  health::Status::backoff &&
              new_probe->terminations == 1,
          "resource excess did not tear down without disabling new revision");

  const auto records = store.query({});
  require(records.status.ok() && records.records.size() >= 12,
          "supervisor lifecycle was not authoritatively audited");
  bool saw_disabled = false;
  bool saw_crash = false;
  for (const auto &record : records.records) {
    saw_disabled = saw_disabled ||
                   record.event == permissions::AuditEvent::worker_disabled;
    saw_crash =
        saw_crash || record.event == permissions::AuditEvent::worker_crashed;
    require(!record.operation && !record.capability && record.correlation == 0,
            "supervisor audit fabricated broker authority fields");
  }
  require(saw_disabled && saw_crash,
          "crash and disable states are absent from the audit");

  health::HealthSupervisor recovered(test_policy(), store);
  require(recovered.restart_decision(new_revision.plugin, new_revision.revision,
                                     100)
                      .status == health::Status::disabled &&
              recovered
                      .restart_decision(second_plugin.plugin,
                                        second_plugin.revision, 100)
                      .status == health::Status::accepted,
          "recovery resurrected unresolved authority or disabled a clean stop");
}

void identity_audit_and_teardown_fail_closed() {
  TemporaryDirectory temporary;
  const auto audit_path = temporary.path() / "audit";
  audit::AuditStore store(audit_path, {.maximum_records = 32});
  health::HealthSupervisor supervisor(test_policy(), store);
  const auto expected = binding("org.example.identity", 1);
  const auto forged = binding("org.example.forged", 1);
  auto forged_probe = std::make_shared<Probe>();
  require(supervisor.adopt(worker(forged, forged_probe), expected, 1) ==
                  health::Status::denied &&
              forged_probe->terminations == 1,
          "forged launcher identity was adopted");

  auto failing_probe = std::make_shared<Probe>();
  failing_probe->terminate_result = false;
  require(supervisor.adopt(worker(expected, failing_probe), expected, 1) ==
                  health::Status::accepted &&
              supervisor.ready(expected, 1) == health::Status::accepted &&
              supervisor.stop(expected) == health::Status::teardown_failed &&
              supervisor.worker_count() == 0 && supervisor.failed(),
          "failed teardown retained a live authority slot");

  const auto replacement = binding("org.example.replacement", 1, 'e');
  auto replacement_probe = std::make_shared<Probe>();
  require(
      supervisor.adopt(worker(replacement, replacement_probe), replacement,
                       2) == health::Status::audit_failed &&
          replacement_probe->terminations == 1 &&
          failing_probe->terminations == 1 &&
          supervisor
                  .restart_decision(replacement.plugin, replacement.revision, 2)
                  .status == health::Status::audit_failed,
      "uncertain teardown allowed replacement authority");

  const auto audit_failure_path = temporary.path() / "audit-failure";
  audit::AuditStore audit_failure_store(audit_failure_path,
                                        {.maximum_records = 32});
  health::HealthSupervisor audit_failure_supervisor(test_policy(),
                                                    audit_failure_store);
  const auto audit_failure_binding = binding("org.example.audit", 1, 'd');
  auto audit_failure_probe = std::make_shared<Probe>();
  std::filesystem::permissions(audit_failure_path,
                               std::filesystem::perms::owner_all |
                                   std::filesystem::perms::group_read,
                               std::filesystem::perm_options::replace);
  require(audit_failure_supervisor.adopt(
              worker(audit_failure_binding, audit_failure_probe),
              audit_failure_binding, 2) == health::Status::audit_failed &&
              audit_failure_probe->terminations == 1 &&
              audit_failure_supervisor.failed() &&
              audit_failure_supervisor.worker_count() == 0,
          "audit failure admitted or retained a worker");
}

void candidate_is_health_checked_without_early_authority() {
  TemporaryDirectory temporary;
  audit::AuditStore store(temporary.path() / "audit", {.maximum_records = 32});
  health::HealthSupervisor supervisor(test_policy(), store);
  const auto active = binding("org.example.transition", 1, 'a');
  const auto candidate = binding("org.example.transition", 2, 'b');
  auto active_probe = std::make_shared<Probe>();
  auto candidate_probe = std::make_shared<Probe>();
  require(supervisor.adopt(worker(active, active_probe), active, 1) ==
                  health::Status::accepted &&
              supervisor.ready(active, 1) == health::Status::accepted &&
              supervisor.open_surface(active, {1, 1}) ==
                  health::Status::accepted &&
              supervisor.admit_request(active, 7, 1, 1) ==
                  health::Status::accepted &&
              supervisor.adopt_candidate(worker(candidate, candidate_probe),
                                         candidate,
                                         1) == health::Status::accepted &&
              supervisor.ready(candidate, 1) == health::Status::accepted &&
              supervisor.open_surface(candidate, {2, 2}) ==
                  health::Status::not_ready &&
              supervisor.admit_request(candidate, 8, 1, 1) ==
                  health::Status::not_ready,
          "healthy candidate received authority before promotion");
  require(supervisor.promote_candidate(candidate) == health::Status::accepted &&
              active_probe->terminations == 1 &&
              candidate_probe->terminations == 0 &&
              supervisor.request_count() == 0 &&
              supervisor.surface_count() == 0 &&
              supervisor.admit_request(active, 9, 1, 2) ==
                  health::Status::stale_generation &&
              supervisor.admit_request(candidate, 9, 1, 2) ==
                  health::Status::accepted,
          "candidate promotion retained old-generation authority");
}

void sequential_rate_flood_and_clock_regression() {
  TemporaryDirectory temporary;
  audit::AuditStore store(temporary.path() / "audit", {.maximum_records = 64});
  health::HealthSupervisor supervisor(test_policy(), store);
  const auto active = binding("org.example.rate", 1);
  auto probe = std::make_shared<Probe>();
  require(supervisor.adopt(worker(active, probe), active, 10) ==
                  health::Status::accepted &&
              supervisor.ready(active, 10) == health::Status::accepted,
          "rate fixture did not become ready");
  for (std::uint64_t correlation = 1; correlation <= 3; ++correlation) {
    require(supervisor.admit_request(active, correlation, 1, 10) ==
                    health::Status::accepted &&
                supervisor.complete_request(active, correlation) ==
                    health::Status::accepted,
            "in-budget sequential request was denied");
  }
  require(supervisor.request_count() == 0 &&
              supervisor.admit_request(active, 4, 1, 10) ==
                  health::Status::backoff &&
              probe->terminations == 1 && supervisor.worker_count() == 0,
          "sequential request flood bypassed the per-binding rate window");

  const auto regressed = binding("org.example.clock", 1, 'd');
  auto clock_probe = std::make_shared<Probe>();
  require(supervisor.adopt(worker(regressed, clock_probe), regressed, 20) ==
                  health::Status::accepted &&
              supervisor.ready(regressed, 20) == health::Status::accepted &&
              supervisor.admit_request(regressed, 1, 1, 19) ==
                  health::Status::backoff &&
              clock_probe->terminations == 1,
          "request-rate clock regression did not fail closed");

  const auto records = store.query({});
  std::size_t failed_health = 0;
  for (const auto &record : records.records) {
    if (record.event == permissions::AuditEvent::worker_health &&
        record.outcome == permissions::AuditOutcome::failed)
      ++failed_health;
  }
  require(records.status.ok() && failed_health >= 2,
          "rate and clock teardowns were not authoritatively audited");
}

} // namespace

int main() {
  try {
    limits_timeout_cleanup_and_crash_loop();
    identity_audit_and_teardown_fail_closed();
    candidate_is_health_checked_without_early_authority();
    sequential_rate_flood_and_clock_regression();
  } catch (const std::exception &error) {
    std::cerr << "FAIL: " << error.what() << '\n';
    return 1;
  }
  std::cout << "supervisor health tests passed\n";
  return 0;
}
