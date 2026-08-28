#include "headless_slice.hpp"

#include "audit_store.hpp"
#include "omarchy/plugin_runtime/sandbox/policy.h"

#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

#include <chrono>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <memory>
#include <stdexcept>
#include <string>
#include <string_view>
#include <vector>

namespace {
using namespace std::chrono_literals;
namespace audit = omarchy::plugins::audit;
namespace channel = omarchy::plugin_runtime::channel;
namespace headless = omarchy::plugin_runtime::headless;
namespace health = omarchy::plugin_runtime::health;
namespace launcher = omarchy::plugin_runtime::launcher;
namespace permissions = omarchy::plugins::permissions;
namespace sandbox = omarchy::plugin_runtime::sandbox;

void require(bool condition, std::string_view message) {
  if (!condition)
    throw std::runtime_error(std::string(message));
}

class Descriptor {
public:
  explicit Descriptor(int value = -1) : value_(value) {}
  Descriptor(const Descriptor &) = delete;
  Descriptor &operator=(const Descriptor &) = delete;
  ~Descriptor() {
    if (value_ >= 0)
      close(value_);
  }
  [[nodiscard]] int get() const { return value_; }

private:
  int value_;
};

class TemporaryFixture {
public:
  TemporaryFixture() {
    std::string pattern = "/tmp/omarchy-headless-XXXXXX";
    char *created = mkdtemp(pattern.data());
    require(created != nullptr, "cannot create headless fixture");
    root_ = created;
    revision_ = root_ / "revision";
    state_ = root_ / "state";
    std::filesystem::create_directories(revision_);
    std::filesystem::create_directories(state_);
    std::ofstream(revision_ / "d1-mode") << "valid\n";
    require(chmod((revision_ / "d1-mode").c_str(), 0444) == 0 &&
                chmod(revision_.c_str(), 0555) == 0,
            "cannot freeze headless revision");
    revision_fd_ = std::make_unique<Descriptor>(
        open(revision_.c_str(), O_RDONLY | O_DIRECTORY | O_CLOEXEC));
    state_fd_ = std::make_unique<Descriptor>(
        open(state_.c_str(), O_RDONLY | O_DIRECTORY | O_CLOEXEC));
    require(revision_fd_->get() >= 0 && state_fd_->get() >= 0,
            "cannot open headless fixture descriptors");
  }
  ~TemporaryFixture() {
    revision_fd_.reset();
    state_fd_.reset();
    (void)chmod(revision_.c_str(), 0755);
    std::error_code ignored;
    std::filesystem::remove_all(root_, ignored);
  }
  [[nodiscard]] launcher::TrustedLaunchRequest request() const {
    return {.plugin_id = "org.omarchy_headless",
            .revision_sha256 = std::string(64, 'e'),
            .generation = 81,
            .revision_directory_fd = revision_fd_->get(),
            .private_state_directory_fd = state_fd_->get()};
  }
  [[nodiscard]] permissions::ActivationBinding binding() const {
    return {.plugin = permissions::PluginId("org.omarchy_headless"),
            .revision = permissions::Digest(std::string(64, 'e')),
            .policy_fingerprint = permissions::Digest(std::string(64, 'f')),
            .generation = 81};
  }
  [[nodiscard]] std::filesystem::path audit_path() const {
    return root_ / "audit";
  }

private:
  std::filesystem::path root_;
  std::filesystem::path revision_;
  std::filesystem::path state_;
  std::unique_ptr<Descriptor> revision_fd_;
  std::unique_ptr<Descriptor> state_fd_;
};

class Scope final : public launcher::ResourceScopeController {
public:
  bool probe(std::string &) override { return true; }
  bool attach(std::string_view, pid_t monitor_pid, pid_t worker_pid,
              const sandbox::SandboxPlan &plan,
              std::chrono::milliseconds timeout, std::string &) override {
    attached = monitor_pid > 0 && worker_pid > 0 && timeout == 5s &&
               plan.worker_descriptors == std::vector<int>({3, 4, 5});
    return attached;
  }
  void kill(std::string_view) noexcept override { ++kills; }
  void remove(std::string_view) noexcept override { ++removes; }
  bool attached = false;
  unsigned kills = 0;
  unsigned removes = 0;
};

class Authority final : public channel::GenerationAuthority {
public:
  bool is_current(const launcher::LaunchIdentity &identity) const noexcept override {
    return current && identity.plugin_id == "org.omarchy_headless" &&
           identity.revision_sha256 == std::string(64, 'e') &&
           identity.generation == 81;
  }
  bool current = true;
};

class NoAuthorityDispatcher final : public channel::BrokerDispatcher {
public:
  bool accepts(const launcher::LaunchIdentity &) const noexcept override {
    return false;
  }
  bool dispatch(const omarchy::plugin::wire::PacketView &packet) override {
    ++calls;
    generation = packet.header.launch_generation;
    return true;
  }
  unsigned calls = 0;
  std::uint64_t generation = 0;
};

health::HealthPolicy policy() {
  health::HealthPolicy value;
  value.maximum_workers = 1;
  value.maximum_requests_per_worker = 1;
  value.maximum_requests_global = 1;
  value.maximum_request_bytes = 128;
  value.memory_max_bytes = 1024;
  value.scratch_max_bytes = 256;
  value.tasks_max = 2;
  return value;
}

void run(std::string bwrap) {
  TemporaryFixture fixture;
  auto scope = std::make_shared<Scope>();
  auto authority = std::make_shared<Authority>();
  auto dispatcher = std::make_shared<NoAuthorityDispatcher>();
  auto launcher = launcher::Supervisor::forTestOnly(
      std::move(bwrap), CHANNEL_PEER_PATH, scope);
  audit::AuditStore audit_store(fixture.audit_path(), {.maximum_records = 64});
  health::HealthSupervisor health_supervisor(policy(), audit_store);

  auto mismatched = fixture.binding();
  mismatched.generation++;
  auto rejected = headless::Session::start(
      launcher, fixture.request(), mismatched, health_supervisor, dispatcher,
      authority, 10, 2s);
  require(!rejected && rejected.failure == headless::StartFailure::invalid_binding &&
              health_supervisor.worker_count() == 0 && !scope->attached,
          "mismatched binding reached worker launch");

  auto started = headless::Session::start(
      launcher, fixture.request(), fixture.binding(), health_supervisor,
      dispatcher, authority, 10, 2s);
  if (!started) {
    throw std::runtime_error("headless start failure " +
                             std::to_string(static_cast<int>(started.failure)) +
                             ": " + started.detail);
  }
  require(started && started.session->active() && scope->attached &&
              health_supervisor.worker_count() == 1 &&
              health_supervisor.request_count() == 0 &&
              health_supervisor.surface_count() == 0,
          "headless worker did not become healthy and ready");
  require(started.session->dispatch_one(11, 2s) ==
                  channel::DispatchStatus::dispatched &&
              dispatcher->calls == 1 && dispatcher->generation == 81 &&
              health_supervisor.request_count() == 0,
          "authenticated request did not traverse the bounded health gate");
  require(started.session->observe_resources({.memory_bytes = 512,
                                               .scratch_bytes = 128,
                                               .tasks = 1},
                                              12) == health::Status::accepted &&
              started.session->stop() == health::Status::accepted &&
              !started.session->active() &&
              health_supervisor.worker_count() == 0 && scope->removes == 1,
          "headless worker did not remain bounded and terminate cleanly");

  audit::Query query;
  query.plugin = fixture.binding().plugin;
  const auto audit = audit_store.query(query);
  require(audit.status.ok() && !audit.records.empty(),
          "headless lifecycle did not leave a durable audit trail");
  for (const auto &record : audit.records) {
    require(!record.capability.has_value() && !record.operation.has_value(),
            "headless supervisor audit disclosed or invented authority");
  }

  auto revoked = headless::Session::start(
      launcher, fixture.request(), fixture.binding(), health_supervisor,
      dispatcher, authority, 20, 2s);
  require(static_cast<bool>(revoked), "revocation fixture did not start");
  authority->current = false;
  require(revoked.session->dispatch_one(21, 2s) ==
                  channel::DispatchStatus::fatal &&
              !revoked.session->active() &&
              health_supervisor.worker_count() == 0 && scope->removes == 2,
          "live generation revocation did not fail closed and clean health state");
  authority->current = true;

  auto exceeded = headless::Session::start(
      launcher, fixture.request(), fixture.binding(), health_supervisor,
      dispatcher, authority, 30, 2s);
  require(static_cast<bool>(exceeded),
          "resource-limit fixture did not start");
  const auto exceeded_status =
      exceeded.session->observe_resources({.memory_bytes = 1025,
                                           .scratch_bytes = 0,
                                           .tasks = 1},
                                          31);
  require(exceeded_status == health::Status::backoff &&
              !exceeded.session->active() &&
              health_supervisor.worker_count() == 0 && scope->removes == 3,
          "resource excess did not synchronously tear down the worker");
}

} // namespace

int main(int argc, char **argv) {
  try {
    require(argc == 2, "expected fake or bwrap mode");
    const std::string_view mode(argv[1]);
    if (mode == "fake") {
      run(FAKE_BWRAP_PATH);
    } else if (mode == "bwrap") {
      run(BWRAP_PATH);
    } else {
      require(false, "unknown mode");
    }
    std::cout << "headless slice: PASS\n";
    return 0;
  } catch (const std::exception &error) {
    std::cerr << error.what() << '\n';
    return 1;
  }
}
