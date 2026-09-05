#include "omarchy/plugin_runtime/launcher/launcher.h"
#include "omarchy/plugin_runtime/launcher/test_supervisor.h"
#include "omarchy/plugin_runtime/launcher/termination_state.h"
#include "omarchy/plugin_runtime/test_support/test_support.h"
#include "../src/process_cleanup.hpp"

#include <fcntl.h>
#include <poll.h>
#include <sys/epoll.h>
#include <sys/socket.h>
#include <sys/syscall.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <unistd.h>

#include <algorithm>
#include <array>
#include <atomic>
#include <cerrno>
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <memory>
#include <span>
#include <string>
#include <string_view>
#include <thread>
#include <type_traits>

namespace launcher = omarchy::plugin_runtime::launcher;
namespace sandbox = omarchy::plugin_runtime::sandbox;
namespace support = omarchy::plugin_runtime::test_support;

namespace {
using namespace std::chrono_literals;

struct Probe {
  std::uint32_t magic;
  std::int32_t pid;
  std::uint32_t uid;
  std::uint32_t gid;
  std::uint32_t descriptor_mask;
  std::uint32_t no_new_privileges;
  std::uint64_t open_files_max;
  std::uint64_t file_size_max;
  std::uint64_t core_size_max;
};

struct Claim {
  std::uint32_t magic;
  std::int32_t claimed_pid;
};

struct DescriptorReport {
  std::uint32_t count;
  std::uint32_t close_on_exec;
};

[[noreturn]] void fail(std::string_view message) {
  std::cerr << message << '\n';
  std::exit(1);
}

void require(bool condition, std::string_view message) {
  if (!condition) {
    fail(message);
  }
}

launcher::Deadline deadline_after(std::chrono::milliseconds duration) {
  return std::chrono::steady_clock::now() + duration;
}

template <typename Predicate>
bool wait_until(Predicate predicate, std::chrono::milliseconds timeout) {
  const auto deadline = std::chrono::steady_clock::now() + timeout;
  while (!predicate() && std::chrono::steady_clock::now() < deadline)
    std::this_thread::yield();
  return predicate();
}

bool await_readable_lanes(launcher::Worker &worker,
                          launcher::EndpointMask expected) {
  const auto deadline = std::chrono::steady_clock::now() + 2s;
  const auto expected_bits = static_cast<std::uint8_t>(expected);
  std::uint8_t observed = 0;
  while ((observed & expected_bits) != expected_bits &&
         std::chrono::steady_clock::now() < deadline) {
    std::array<epoll_event, 3> events{};
    const auto remaining = std::chrono::duration_cast<std::chrono::milliseconds>(
        deadline - std::chrono::steady_clock::now());
    const int timeout = static_cast<int>(
        std::max<std::chrono::milliseconds::rep>(1, remaining.count()));
    const int count =
        epoll_wait(worker.readiness_fd(), events.data(), events.size(), timeout);
    if (count < 0 && errno == EINTR) continue;
    if (count <= 0) break;
    for (int index = 0; index < count; ++index) {
      if ((events[index].events & EPOLLIN) != 0 && events[index].data.u64 < 3) {
        observed |= static_cast<std::uint8_t>(1U << events[index].data.u64);
      }
    }
  }
  return (observed & expected_bits) == expected_bits;
}

std::size_t open_descriptor_count() {
  std::size_t count = 0;
  for (const auto &entry :
       std::filesystem::directory_iterator("/proc/self/fd")) {
    (void)entry;
    ++count;
  }
  return count;
}

enum class WakeFault { none, interrupt_once, saturated, failed };
std::atomic<WakeFault> wake_fault = WakeFault::none;
std::atomic<unsigned> wake_calls = 0;

ssize_t injected_wake(int descriptor, const void *bytes,
                      std::size_t size) {
  const unsigned call = wake_calls.fetch_add(1);
  if (wake_fault == WakeFault::interrupt_once && call == 0) {
    errno = EINTR;
    return -1;
  }
  if (wake_fault == WakeFault::saturated) {
    errno = EAGAIN;
    return -1;
  }
  if (wake_fault == WakeFault::failed) {
    errno = EIO;
    return -1;
  }
  return write(descriptor, bytes, size);
}

template <typename Value> Value decode(std::span<const std::byte> bytes) {
  require(bytes.size() == sizeof(Value), "probe payload size changed");
  Value value{};
  std::memcpy(&value, bytes.data(), sizeof(value));
  return value;
}

class FakeScope final : public launcher::ResourceScopeController {
public:
  bool probe(launcher::Deadline deadline, std::string &error) override {
    probe_deadline = deadline;
    if (probe_delay > 0ms) {
      const auto remaining = deadline - std::chrono::steady_clock::now();
      if (remaining <= probe_delay) {
        std::this_thread::sleep_until(deadline);
        error = "synthetic preflight deadline expired";
        return false;
      }
      std::this_thread::sleep_for(probe_delay);
    }
    if (!available) error = "synthetic resource controller unavailable";
    return available;
  }

  bool prepare_cleanup(launcher::Deadline deadline,
                       std::string &error) override {
    cleanup_deadline = deadline;
    if (cleanup_setup_delay > 0ms) {
      const auto remaining = deadline - std::chrono::steady_clock::now();
      if (remaining <= cleanup_setup_delay) {
        std::this_thread::sleep_until(deadline);
        error = "synthetic cleanup setup deadline expired";
        return false;
      }
      std::this_thread::sleep_for(cleanup_setup_delay);
    }
    cleanup_prepared = true;
    return true;
  }

  AttachResult attach_validated(const launcher::ProcessScopeRequest &request,
                                launcher::Deadline deadline,
                                std::string &error) override {
    attach_deadline = deadline;
    if (!attach_succeeds) {
      error = "synthetic scope attachment rejected";
      return {};
    }
    require(request.unit.starts_with("app-omarchy-plugin-worker-"),
            "scope name escaped the trusted prefix");
    require(request.description == "Omarchy sandboxed plugin worker",
            "worker scope description changed");
    require(request.pids.size() == 2 && request.pids[0] > 0 &&
                request.pids[1] > 0 && request.pids[0] != request.pids[1],
            "scope received an invalid process identity");
    require(request.resources.memory_high_bytes ==
                    384ULL * 1024ULL * 1024ULL &&
                request.resources.memory_max_bytes ==
                    512ULL * 1024ULL * 1024ULL &&
                request.resources.tasks_max == 16 &&
                request.resources.cpu_quota_per_second_usec == 500000 &&
                request.resources.cpu_weight == 20 &&
                request.resources.io_weight == 10,
            "launcher did not consume the process-scope resource/deadline contract");
    attached = true;
    attached_before_release = true;
    scope.assign(request.unit);
    description.assign(request.description);
    pids.assign(request.pids.begin(), request.pids.end());
    if (attach_delay > 0ms) {
      const auto remaining = deadline - std::chrono::steady_clock::now();
      if (remaining <= attach_delay) {
        std::this_thread::sleep_until(deadline);
        error = "synthetic attachment deadline expired";
        return {.attached = false, .cleanup_required = true};
      }
      std::this_thread::sleep_for(attach_delay);
    }
    return {.attached = std::chrono::steady_clock::now() < deadline,
            .cleanup_required = true};
  }

  bool terminate_scope_validated(std::string_view unit,
                                  launcher::Deadline deadline,
                                  std::string &error) noexcept override {
    if (unit == scope) {
      if (remove_delay > 0ms)
        std::this_thread::sleep_until(std::min(
            deadline, std::chrono::steady_clock::now() + remove_delay));
      const bool succeeds = termination_succeeds.load();
      ++termination_count;
      if (!succeeds)
        error = "synthetic confirmed termination failed";
      return succeeds && std::chrono::steady_clock::now() < deadline;
    }
    const bool succeeds = termination_succeeds.load();
    if (!succeeds)
      error = "synthetic confirmed termination failed";
    return succeeds && std::chrono::steady_clock::now() < deadline;
  }

  bool available = true;
  bool attach_succeeds = true;
  bool attached = false;
  bool attached_before_release = false;
  std::atomic<bool> termination_succeeds = true;
  std::atomic<unsigned> termination_count = 0;
  std::chrono::milliseconds probe_delay{};
  std::chrono::milliseconds cleanup_setup_delay{};
  std::chrono::milliseconds attach_delay{};
  std::chrono::milliseconds remove_delay{};
  std::optional<launcher::Deadline> probe_deadline;
  std::optional<launcher::Deadline> cleanup_deadline;
  std::optional<launcher::Deadline> attach_deadline;
  std::string scope;
  std::string description;
  std::vector<pid_t> pids;
  bool cleanup_prepared = false;
};

class IncompleteController : public launcher::ResourceScopeController {
};

static_assert(std::is_abstract_v<IncompleteController>,
              "incomplete controllers must not enter the launch path");

class ScopeRequestProbe final : public launcher::ResourceScopeController {
public:
  bool probe(launcher::Deadline, std::string &) override { return true; }
  bool prepare_cleanup(launcher::Deadline, std::string &) override {
    return true;
  }
  AttachResult attach_validated(const launcher::ProcessScopeRequest &request,
                                launcher::Deadline deadline,
                                std::string &) override {
    ++attach_calls;
    unit.assign(request.unit);
    description.assign(request.description);
    pids.assign(request.pids.begin(), request.pids.end());
    resources = request.resources;
    attach_deadline = deadline;
    return attach_result;
  }
  bool terminate_scope_validated(std::string_view requested,
                                  launcher::Deadline,
                                  std::string &error) noexcept override {
    if (requested == unit) ++termination_calls;
    if (!termination_succeeds)
      error = "synthetic partial scope cleanup";
    return termination_succeeds;
  }

  AttachResult attach_result{.attached = true, .cleanup_required = true};
  unsigned attach_calls = 0;
  unsigned termination_calls = 0;
  bool termination_succeeds = true;
  std::string unit;
  std::string description;
  std::vector<pid_t> pids;
  launcher::ProcessResourceCeilings resources;
  std::optional<launcher::Deadline> attach_deadline;
};

class BlockingCleanupScope final : public launcher::ResourceScopeController {
public:
  bool probe(launcher::Deadline, std::string &) override { return true; }
  bool prepare_cleanup(launcher::Deadline, std::string &) override {
    return true;
  }
  AttachResult attach_validated(const launcher::ProcessScopeRequest &,
                                launcher::Deadline,
                                std::string &) override {
    return {.attached = true, .cleanup_required = true};
  }
  bool terminate_scope_validated(std::string_view, launcher::Deadline,
                                  std::string &) noexcept override {
    const unsigned current = entered.fetch_add(1) + 1;
    if (current == 1) {
      std::unique_lock lock(mutex);
      ready.notify_all();
      ready.wait(lock, [&] { return released; });
    }
    completed.fetch_add(1);
    return true;
  }

  std::mutex mutex;
  std::condition_variable ready;
  bool released = false;
  std::atomic<unsigned> entered = 0;
  std::atomic<unsigned> completed = 0;
};

class DeadlineCleanupScope final : public launcher::ResourceScopeController {
public:
  bool probe(launcher::Deadline, std::string &) override { return true; }
  bool prepare_cleanup(launcher::Deadline, std::string &) override {
    return true;
  }
  AttachResult attach_validated(const launcher::ProcessScopeRequest &,
                                launcher::Deadline,
                                std::string &) override {
    return {.attached = true, .cleanup_required = true};
  }
  bool terminate_scope_validated(std::string_view,
                                  launcher::Deadline deadline,
                                  std::string &error) noexcept override {
    if (calls.fetch_add(1) == 0)
      std::this_thread::sleep_until(
          std::min(deadline, std::chrono::steady_clock::now() + 50ms));
    completed.fetch_add(1);
    if (std::chrono::steady_clock::now() >= deadline) {
      error = "synthetic confirmed termination deadline expired";
      return false;
    }
    return true;
  }
  std::atomic<unsigned> calls = 0;
  std::atomic<unsigned> completed = 0;
};

class FailingCleanupScope final : public launcher::ResourceScopeController {
public:
  enum class Failure { bus_loss, partial_cleanup, timeout };
  explicit FailingCleanupScope(Failure selected) : failure(selected) {}
  bool probe(launcher::Deadline, std::string &) override { return true; }
  bool prepare_cleanup(launcher::Deadline, std::string &) override {
    return true;
  }
  AttachResult attach_validated(const launcher::ProcessScopeRequest &,
                                launcher::Deadline,
                                std::string &) override {
    return {.attached = true, .cleanup_required = true};
  }
  bool terminate_scope_validated(std::string_view,
                                  launcher::Deadline deadline,
                                  std::string &error) noexcept override {
    ++calls;
    if (recover)
      return true;
    if (failure == Failure::timeout)
      std::this_thread::sleep_until(deadline);
    if (failure == Failure::bus_loss)
      error = "synthetic cleanup bus lost";
    else if (failure == Failure::partial_cleanup)
      error = "synthetic cgroup remained populated";
    else
      error = "synthetic confirmed termination deadline expired";
    return false;
  }
  Failure failure;
  std::atomic<bool> recover = false;
  std::atomic<unsigned> calls = 0;
};

struct LaunchFixture {
  LaunchFixture() {
    require(chmod(tree.revision().c_str(), 0555) == 0,
            "cannot make synthetic revision immutable");
    revision.reset(
        open(tree.revision().c_str(), O_RDONLY | O_DIRECTORY | O_CLOEXEC));
    state.reset(
        open(tree.private_state().c_str(), O_RDONLY | O_DIRECTORY | O_CLOEXEC));
    require(revision && state, "cannot open synthetic launch directories");
  }

  ~LaunchFixture() { static_cast<void>(chmod(tree.revision().c_str(), 0755)); }

  [[nodiscard]] launcher::TrustedLaunchRequest request() const {
    return {.plugin_id = "org.omarchy_fixture",
            .revision_sha256 = std::string(64, 'a'),
            .generation = 17,
            .revision_directory_fd = revision.get(),
            .private_state_directory_fd = state.get()};
  }

  support::SyntheticResourceTree tree;
  support::UniqueFd revision;
  support::UniqueFd state;
};

void validate_probe(launcher::Worker &worker) {
  const auto message = worker.receive(
      launcher::EndpointRole::control, launcher::PacketSizeLimit{sizeof(Probe)},
      deadline_after(2s));
  require(static_cast<bool>(message), "bound worker control packet failed");
  const Probe probe = decode<Probe>(message.payload);
  require(probe.magic == 0x43575037 && probe.pid == 1 && probe.uid == 0 &&
              probe.gid == 0 && probe.descriptor_mask == 0x3f &&
              probe.no_new_privileges == 1 && probe.open_files_max == 64 &&
              probe.file_size_max == 64ULL * 1024ULL * 1024ULL &&
              probe.core_size_max == 0,
          "worker identity, exact FD set, NNP, or rlimit contract changed");
}

void pidfd_reap_state_test() {
  const pid_t child = fork();
  require(child >= 0, "cannot fork pidfd reap-state fixture");
  if (child == 0) {
    _exit(0);
  }
  support::UniqueFd pidfd(
      static_cast<int>(syscall(SYS_pidfd_open, child, 0)));
  require(static_cast<bool>(pidfd),
          "cannot open pidfd reap-state fixture");
  pollfd before{.fd = pidfd.get(), .events = POLLIN, .revents = 0};
  require(poll(&before, 1, 2000) == 1 &&
              launcher::pidfd_has_exited(before.revents),
          "pidfd did not report child exit before reap");
  int status = 0;
  require(waitpid(child, &status, 0) == child,
          "cannot reap pidfd state fixture");
  pollfd after{.fd = pidfd.get(), .events = POLLIN, .revents = 0};
  require(poll(&after, 1, 0) == 1 &&
              after.revents == (POLLIN | POLLHUP) &&
              launcher::pidfd_has_exited(after.revents),
          "reaped pidfd POLLIN|POLLHUP was not accepted as exited");
  require(!launcher::pidfd_has_exited(POLLHUP) &&
              !launcher::pidfd_has_exited(POLLIN | POLLERR) &&
              !launcher::pidfd_has_exited(POLLIN | POLLNVAL),
          "unexpected pidfd events were accepted as an exit certificate");
}

launcher::ProcessResourceCeilings scope_resources() {
  return {.memory_high_bytes = 1024,
          .memory_max_bytes = 2048,
          .tasks_max = 8,
          .cpu_quota_per_second_usec = 250000,
          .cpu_weight = 50,
          .io_weight = 25};
}

void generic_process_scope_request_test() {
  ScopeRequestProbe scope;
  const std::array<pid_t, 3> processes{101, 202, 303};
  const auto deadline = deadline_after(5s);
  std::string error;
  const launcher::ProcessScopeRequest request{
      .unit = "app-omarchy-plugin-provider-example.scope",
      .description = "Omarchy trusted plugin provider",
      .pids = processes,
      .resources = scope_resources()};
  const auto attached = scope.attach(request, deadline, error);
  require(attached.attached && attached.cleanup_required && error.empty() &&
              scope.attach_calls == 1 && scope.attach_deadline == deadline &&
              scope.unit == request.unit &&
              scope.description == request.description &&
              scope.pids == std::vector<pid_t>(processes.begin(),
                                               processes.end()) &&
              scope.resources.memory_high_bytes == 1024 &&
              scope.resources.memory_max_bytes == 2048 &&
              scope.resources.tasks_max == 8 &&
              scope.resources.cpu_quota_per_second_usec == 250000 &&
              scope.resources.cpu_weight == 50 &&
              scope.resources.io_weight == 25,
          "generic scope request did not preserve exact processes/resources");
  std::string termination_error = "stale caller text";
  require(scope.terminate_scope(request.unit, deadline, termination_error) &&
              scope.termination_calls == 1 && termination_error.empty(),
          "generic scope cleanup did not retain its exact unit identity");

  ScopeRequestProbe boundary;
  std::string boundary_error;
  auto boundary_request = request;
  boundary_request.resources.memory_high_bytes =
      launcher::kMaximumProcessScopeMemoryBytes;
  boundary_request.resources.memory_max_bytes =
      launcher::kMaximumProcessScopeMemoryBytes;
  boundary_request.resources.tasks_max = launcher::kMaximumProcessScopeTasks;
  boundary_request.resources.cpu_quota_per_second_usec =
      launcher::kMaximumProcessScopeCpuQuotaUsec;
  require(boundary.attach(boundary_request, deadline_after(5s),
                          boundary_error)
                  .attached &&
              boundary.attach_calls == 1 && boundary_error.empty(),
          "exact generic resource ceiling boundary was rejected");

  const auto rejected_without_call = [&](std::span<const pid_t> pids,
                                         std::string_view expected) {
    ScopeRequestProbe rejected;
    std::string rejected_error;
    auto candidate = request;
    candidate.pids = pids;
    const auto result = rejected.attach(candidate, deadline, rejected_error);
    require(!result.attached && !result.cleanup_required &&
                rejected.attach_calls == 0 &&
                rejected_error.find(expected) != std::string::npos,
            "invalid generic scope request reached the resource manager");
  };
  rejected_without_call({}, "PID count");
  const std::array<pid_t, 2> invalid{101, -1};
  rejected_without_call(invalid, "invalid or duplicate");
  const std::array<pid_t, 2> zero{101, 0};
  rejected_without_call(zero, "invalid or duplicate");
  const std::array<pid_t, 2> duplicate{101, 101};
  rejected_without_call(duplicate, "invalid or duplicate");

  ScopeRequestProbe invalid_resources;
  std::string resource_error;
  auto bad_resources = request;
  bad_resources.resources.memory_high_bytes =
      bad_resources.resources.memory_max_bytes + 1;
  const auto resource_result = invalid_resources.attach(
      bad_resources, deadline_after(5s), resource_error);
  require(!resource_result.attached && !resource_result.cleanup_required &&
              invalid_resources.attach_calls == 0 &&
              resource_error.find("resource ceilings") != std::string::npos,
          "invalid generic resource ceilings reached the resource manager");
  const auto rejects_resource = [&](auto mutation) {
    ScopeRequestProbe rejected;
    std::string rejected_error;
    auto candidate = boundary_request;
    mutation(candidate.resources);
    const auto result = rejected.attach(candidate, deadline_after(5s),
                                        rejected_error);
    require(!result.attached && !result.cleanup_required &&
                rejected.attach_calls == 0 &&
                rejected_error.find("resource ceilings") != std::string::npos,
            "resource hard maximum was not enforced before the backend");
  };
  rejects_resource([](auto &resources) {
    resources.memory_max_bytes =
        launcher::kMaximumProcessScopeMemoryBytes + 1;
  });
  rejects_resource([](auto &resources) {
    resources.tasks_max = launcher::kMaximumProcessScopeTasks + 1;
  });
  rejects_resource([](auto &resources) {
    resources.cpu_quota_per_second_usec =
        launcher::kMaximumProcessScopeCpuQuotaUsec + 1;
  });

  ScopeRequestProbe expired;
  std::string expired_error;
  const auto expired_result = expired.attach(
      request, std::chrono::steady_clock::now(), expired_error);
  require(!expired_result.attached && !expired_result.cleanup_required &&
              expired.attach_calls == 0 &&
              expired_error.find("deadline") != std::string::npos,
          "expired generic scope request acquired cleanup authority");

  ScopeRequestProbe attempted;
  attempted.attach_result = {.attached = false, .cleanup_required = true};
  std::string attempted_error;
  const auto attempted_result = attempted.attach(
      request, deadline_after(5s), attempted_error);
  require(!attempted_result.attached && attempted_result.cleanup_required &&
              attempted.attach_calls == 1,
          "attempted generic attach lost fail-stop cleanup authority");
  std::string cleanup_error;
  require(attempted.terminate_scope(request.unit, deadline_after(5s),
                                    cleanup_error) &&
              attempted.termination_calls == 1,
          "failed generic attach could not perform exact cleanup");

  ScopeRequestProbe partial_cleanup;
  partial_cleanup.unit = std::string(request.unit);
  partial_cleanup.termination_succeeds = false;
  std::string partial_error;
  require(!partial_cleanup.terminate_scope(request.unit, deadline_after(5s),
                                           partial_error) &&
              partial_cleanup.termination_calls == 1 &&
              partial_error.find("partial") != std::string::npos,
          "partial generic cleanup was reported as confirmed termination");
  ScopeRequestProbe invalid_cleanup;
  std::string invalid_cleanup_error;
  require(!invalid_cleanup.terminate_scope(
              "ssh.service", deadline_after(5s), invalid_cleanup_error) &&
              invalid_cleanup.termination_calls == 0 &&
              invalid_cleanup_error.find("identity") != std::string::npos,
          "non-scope cleanup identity reached the resource manager");

  FakeScope worker_scope;
  std::string worker_error;
  const auto worker_deadline = deadline_after(5s);
  const auto worker_result = worker_scope.attach(
      "app-omarchy-plugin-worker-test.scope", 404, 505,
      sandbox::build_plan(), worker_deadline, worker_error);
  require(worker_result.attached && worker_result.cleanup_required &&
              worker_error.empty() &&
              worker_scope.pids == std::vector<pid_t>({404, 505}) &&
              worker_scope.description == "Omarchy sandboxed plugin worker" &&
              worker_scope.attach_deadline == worker_deadline,
          "worker scope adapter changed established scope behavior");
}

void deadline_and_async_cleanup_test(LaunchFixture &fixture) {
  auto rejected_scope = std::make_shared<FakeScope>();
  rejected_scope->attach_succeeds = false;
  auto rejected_supervisor = launcher::test_support::make_supervisor(
      FAKE_BWRAP_PATH, PROBE_PATH, rejected_scope);
  const auto pre_call_rejected =
      rejected_supervisor.launch(fixture.request(), deadline_after(5s));
  require(pre_call_rejected.failure ==
              launcher::LaunchFailure::resource_scope_failed &&
              rejected_scope->termination_count == 0,
          "pre-call scope rejection acquired or cleaned nonexistent authority");

  auto scope = std::make_shared<FakeScope>();
  scope->remove_delay = 150ms;
  auto supervisor =
      launcher::test_support::make_supervisor(FAKE_BWRAP_PATH, PROBE_PATH,
                                              scope);
  const auto launch_deadline = std::chrono::steady_clock::now() + 5s;
  auto launched = supervisor.launch(fixture.request(), launch_deadline);
  require(static_cast<bool>(launched) && scope->probe_deadline == launch_deadline &&
              scope->cleanup_deadline == launch_deadline &&
              scope->cleanup_prepared &&
              scope->attach_deadline == launch_deadline,
          "one absolute deadline was not preserved through cleanup setup/attach");
  const auto destroy_started = std::chrono::steady_clock::now();
  launched.worker.reset();
  require(std::chrono::steady_clock::now() - destroy_started < 50ms,
          "Worker destructor blocked on process/scope cleanup");
  require(wait_until([&] { return scope->termination_count.load() == 1; }, 2s),
          "asynchronous Worker cleanup did not remove its scope exactly once");

  auto delayed_setup_scope = std::make_shared<FakeScope>();
  delayed_setup_scope->cleanup_setup_delay = 1s;
  auto delayed_setup = launcher::test_support::make_supervisor(
      FAKE_BWRAP_PATH, PROBE_PATH, delayed_setup_scope);
  const auto setup_deadline = std::chrono::steady_clock::now() + 30ms;
  const auto setup_rejected =
      delayed_setup.launch(fixture.request(), setup_deadline);
  require(setup_rejected.failure == launcher::LaunchFailure::startup_timeout &&
              !delayed_setup_scope->cleanup_prepared &&
              !delayed_setup_scope->attach_deadline.has_value() &&
              delayed_setup_scope->termination_count == 0,
          "cleanup transport setup was delayed until after process authority");

  auto expiring_scope = std::make_shared<FakeScope>();
  expiring_scope->probe_delay = 10ms;
  expiring_scope->attach_delay = 1s;
  expiring_scope->remove_delay = 150ms;
  auto expiring = launcher::test_support::make_supervisor(
      FAKE_BWRAP_PATH, PROBE_PATH, expiring_scope);
  const auto aggregate_deadline = std::chrono::steady_clock::now() + 40ms;
  const auto launch_started = std::chrono::steady_clock::now();
  const auto rejected = expiring.launch(fixture.request(), aggregate_deadline);
  const auto launch_elapsed = std::chrono::steady_clock::now() - launch_started;
  require(rejected.failure == launcher::LaunchFailure::startup_timeout &&
              expiring_scope->probe_deadline == aggregate_deadline &&
              expiring_scope->attach_deadline == aggregate_deadline,
          "preflight/status/attach reset or misclassified the launch deadline");
  require(launch_elapsed < 100ms,
          "failed-launch cleanup blocked the absolute deadline return path");
  require(wait_until(
              [&] { return expiring_scope->termination_count.load() == 1; }, 2s),
          "timed-out attachment did not receive asynchronous cleanup");

  auto retry_scope = std::make_shared<FakeScope>();
  retry_scope->termination_succeeds = false;
  auto retry_supervisor = launcher::test_support::make_supervisor(
      FAKE_BWRAP_PATH, PROBE_PATH, retry_scope);
  auto retry_worker =
      retry_supervisor.launch(fixture.request(), deadline_after(5s));
  require(static_cast<bool>(retry_worker),
          "cleanup-retry worker did not launch");
  require(!retry_worker.worker->terminate(deadline_after(2s)) &&
              retry_scope->termination_count == 1,
          "unconfirmed worker cleanup was reported successful");
  retry_scope->termination_succeeds = true;
  require(retry_worker.worker->terminate(deadline_after(2s)) &&
              retry_worker.worker->terminate(deadline_after(2s)) &&
              retry_scope->termination_count == 2,
          "Worker::terminate did not retry retained cleanup exactly once");

  auto abandoned_scope = std::make_shared<FakeScope>();
  abandoned_scope->termination_succeeds = false;
  auto abandoned_supervisor = launcher::test_support::make_supervisor(
      FAKE_BWRAP_PATH, PROBE_PATH, abandoned_scope);
  auto abandoned_worker =
      abandoned_supervisor.launch(fixture.request(), deadline_after(5s));
  require(static_cast<bool>(abandoned_worker),
          "destructor cleanup fixture did not launch");
  abandoned_worker.worker.reset();
  require(wait_until(
              [&] { return abandoned_scope->termination_count.load() >= 1; },
              2s),
          "worker destruction did not start autonomous cleanup");
  const auto abandoned_failures = abandoned_scope->termination_count.load();
  abandoned_scope->termination_succeeds = true;
  require(wait_until(
              [&] {
                return abandoned_scope->termination_count.load() >
                       abandoned_failures;
              },
              2s),
          "worker destruction dropped cleanup authority after failure");
  const auto abandoned_clean = abandoned_scope->termination_count.load();
  std::this_thread::sleep_for(150ms);
  require(abandoned_scope->termination_count == abandoned_clean,
          "confirmed destructor cleanup remained queued");

  auto failed_launch_scope = std::make_shared<FakeScope>();
  failed_launch_scope->attach_delay = 100ms;
  failed_launch_scope->termination_succeeds = false;
  auto failed_launch_supervisor = launcher::test_support::make_supervisor(
      FAKE_BWRAP_PATH, PROBE_PATH, failed_launch_scope);
  const auto failed_launch = failed_launch_supervisor.launch(
      fixture.request(), deadline_after(20ms));
  require(!failed_launch &&
              wait_until(
                  [&] {
                    return failed_launch_scope->termination_count.load() >= 1;
                  },
                  2s),
          "failed launch did not retain autonomous cleanup authority");
  const auto failed_launch_attempts =
      failed_launch_scope->termination_count.load();
  failed_launch_scope->termination_succeeds = true;
  require(wait_until(
              [&] {
                return failed_launch_scope->termination_count.load() >
                       failed_launch_attempts;
              },
              2s),
          "failed launch cleanup was not retried after reconnection");

}

void reaper_wake_and_cleanup_deadline_test() {
  using launcher::detail::CleanupJob;
  using launcher::detail::ProcessScopeReaper;
  const auto exercise = [](WakeFault fault, bool poisons_reaper) {
    wake_fault = fault;
    wake_calls = 0;
    ProcessScopeReaper reaper(false, injected_wake);
    std::string error;
    require(reaper.start(error), "cannot start injected-wake reaper");
    auto completion = std::make_shared<launcher::detail::ReapCompletion>();
    auto job = std::make_unique<CleanupJob>();
    job->completion = completion;
    reaper.submit(std::move(job));
    require(wait_until(
                [&] {
                  std::lock_guard lock(completion->mutex);
                  return completion->completed;
                },
                2s),
            "injected notifier result stranded published cleanup authority");
    std::string restart_error;
    require(reaper.start(restart_error) != poisons_reaper,
            "notifier invariant failure did not produce exact fail-stop state");
  };
  exercise(WakeFault::interrupt_once, false);
  require(wake_calls >= 2, "EINTR notifier write was not retried");
  exercise(WakeFault::saturated, false);
  exercise(WakeFault::failed, true);
  wake_fault = WakeFault::none;

  auto scope = std::make_shared<DeadlineCleanupScope>();
  ProcessScopeReaper reaper(false);
  std::string error;
  require(reaper.start(error), "cannot start cleanup-deadline reaper");
  for (unsigned index = 0; index < 2; ++index) {
    auto job = std::make_unique<CleanupJob>();
    job->resource_scope = scope;
    job->scope = "app-omarchy-plugin-worker-deadline.scope";
    job->scope_attached = true;
    reaper.submit(std::move(job));
  }
  require(wait_until([&] { return scope->completed == 2; }, 500ms),
          "bounded cleanup call stalled later cleanup authority");

  for (const auto failure : {FailingCleanupScope::Failure::bus_loss,
                             FailingCleanupScope::Failure::partial_cleanup,
                             FailingCleanupScope::Failure::timeout}) {
    auto failed_scope = std::make_shared<FailingCleanupScope>(failure);
    auto completion = std::make_shared<launcher::detail::ReapCompletion>();
    auto job = std::make_unique<CleanupJob>();
    job->resource_scope = failed_scope;
    job->scope = "app-omarchy-plugin-worker-failed-cleanup.scope";
    job->scope_attached = true;
    job->completion = completion;
    job->timeouts.forced_teardown_seconds = 1;
    reaper.submit(std::move(job));
    require(wait_until(
                [&] {
                  std::lock_guard lock(completion->mutex);
                  return completion->failed_attempts >= 1;
                },
                2s),
            "failed confirmed cleanup did not complete observably");
    {
      std::lock_guard lock(completion->mutex);
      require(!completion->succeeded && failed_scope->calls == 1,
              "bus-loss, timeout, or partial cleanup was reported clean");
    }
    failed_scope->recover = true;
    require(wait_until(
                [&] {
                  std::lock_guard retry_lock(completion->mutex);
                  return completion->succeeded;
                },
                500ms),
            "autonomous reconnected cleanup retry did not complete");
    std::lock_guard retry_lock(completion->mutex);
    require(completion->succeeded && failed_scope->calls == 2,
            "confirmed cleanup retry retained fail-stop authority");
  }

  auto aggregate_scope = std::make_shared<FailingCleanupScope>(
      FailingCleanupScope::Failure::timeout);
  auto aggregate_completion =
      std::make_shared<launcher::detail::ReapCompletion>();
  const pid_t stuck_monitor = fork();
  require(stuck_monitor >= 0, "cannot fork aggregate cleanup fixture");
  if (stuck_monitor == 0) {
    for (;;)
      pause();
  }
  const int stuck_pidfd =
      static_cast<int>(syscall(SYS_pidfd_open, stuck_monitor, 0));
  require(stuck_pidfd >= 0, "cannot open aggregate cleanup pidfd");
  auto aggregate_job = std::make_unique<CleanupJob>();
  aggregate_job->resource_scope = aggregate_scope;
  aggregate_job->scope = "app-omarchy-plugin-worker-aggregate.scope";
  aggregate_job->scope_attached = true;
  aggregate_job->monitor_pid = stuck_monitor;
  aggregate_job->monitor_pidfd = stuck_pidfd;
  aggregate_job->completion = aggregate_completion;
  aggregate_job->timeouts.forced_teardown_seconds = 1;
  const auto aggregate_started = std::chrono::steady_clock::now();
  reaper.submit(std::move(aggregate_job));
  require(wait_until(
              [&] {
                std::lock_guard lock(aggregate_completion->mutex);
                return aggregate_completion->failed_attempts >= 1;
              },
              1600ms) &&
              std::chrono::steady_clock::now() - aggregate_started < 1500ms,
          "forced cleanup reset its deadline between scope and process reap");
  aggregate_scope->recover = true;
  require(wait_until(
              [&] {
                std::lock_guard lock(aggregate_completion->mutex);
                return aggregate_completion->succeeded;
              },
              2s),
          "aggregate-deadline cleanup did not recover autonomously");
}

void nonblocking_bus_connection_test() {
  support::SyntheticResourceTree tree;
  const auto socket_path = tree.root() / "hung-bus";
  support::UniqueFd listener(
      socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0));
  require(static_cast<bool>(listener),
          "cannot create private hung bus listener");
  sockaddr_un address{};
  address.sun_family = AF_UNIX;
  require(socket_path.string().size() < sizeof(address.sun_path),
          "private hung bus path is too long");
  std::memcpy(address.sun_path, socket_path.c_str(),
              socket_path.string().size() + 1);
  require(bind(listener.get(), reinterpret_cast<sockaddr *>(&address),
               sizeof(address)) == 0 &&
              listen(listener.get(), 2) == 0,
          "cannot bind private hung bus listener");

  std::atomic<unsigned> accepted = 0;
  std::atomic<unsigned> closed = 0;
  std::thread server([&] {
    for (unsigned attempt = 0; attempt < 2; ++attempt) {
      support::UniqueFd peer(
          accept4(listener.get(), nullptr, nullptr, SOCK_CLOEXEC));
      if (!peer)
        return;
      accepted.fetch_add(1);
      const auto deadline = std::chrono::steady_clock::now() + 2s;
      while (std::chrono::steady_clock::now() < deadline) {
        pollfd event{.fd = peer.get(), .events = POLLIN, .revents = 0};
        if (poll(&event, 1, 50) <= 0)
          continue;
        std::array<std::byte, 64> bytes{};
        const ssize_t received = recv(peer.get(), bytes.data(), bytes.size(), 0);
        if (received == 0) {
          closed.fetch_add(1);
          break;
        }
        if (received < 0 && errno != EINTR)
          break;
      }
    }
  });

  const std::string bus_address = "unix:path=" + socket_path.string();
  for (unsigned attempt = 0; attempt < 2; ++attempt) {
    std::string error;
    const auto started = std::chrono::steady_clock::now();
    require(!launcher::test_support::connect_bus(
                bus_address, started + 60ms, error) &&
                std::chrono::steady_clock::now() - started < 150ms &&
                error == "bus connection deadline expired",
            "hung private bus attempt escaped its exact deadline");
  }
  server.join();
  require(accepted == 2 && closed == 2,
          "expired bus attempt was retained or blocked a fresh reconnect");
}

void reaper_capacity_and_startup_test(LaunchFixture &fixture) {
  auto failed_scope = std::make_shared<FakeScope>();
  auto failed = launcher::test_support::make_supervisor(
      FAKE_BWRAP_PATH, PROBE_PATH, failed_scope, true);
  const auto rejected = failed.launch(fixture.request(), deadline_after(5s));
  require(rejected.failure ==
              launcher::LaunchFailure::resource_scope_unavailable &&
              !failed_scope->probe_deadline.has_value(),
          "reaper startup failure did not reject launch before process authority");

  using launcher::detail::CleanupJob;
  using launcher::detail::ProcessScopeReaper;
  constexpr std::size_t job_count = 5000;
  auto scope = std::make_shared<BlockingCleanupScope>();
  ProcessScopeReaper reaper(false);
  std::string error;
  require(reaper.start(error), "cannot start cleanup-capacity fixture");
  std::vector<std::unique_ptr<CleanupJob>> jobs;
  jobs.reserve(job_count);
  for (std::size_t index = 0; index < job_count; ++index) {
    auto job = std::make_unique<CleanupJob>();
    job->resource_scope = scope;
    job->scope = "app-omarchy-plugin-worker-capacity.scope";
    job->scope_attached = true;
    jobs.push_back(std::move(job));
  }
  reaper.submit(std::move(jobs.front()));
  {
    std::unique_lock lock(scope->mutex);
    require(scope->ready.wait_for(lock, 2s,
                                  [&] { return scope->entered == 1; }),
            "cleanup worker did not enter its paused first job");
  }
  constexpr std::size_t producer_count = 8;
  std::array<std::thread, producer_count> producers;
  for (std::size_t producer = 0; producer < producer_count; ++producer) {
    producers[producer] = std::thread([&, producer] {
      for (std::size_t index = 1 + producer; index < job_count;
           index += producer_count)
        reaper.submit(std::move(jobs[index]));
    });
  }
  for (auto &producer : producers) producer.join();
  {
    std::lock_guard lock(scope->mutex);
    scope->released = true;
  }
  scope->ready.notify_all();
  require(wait_until([&] { return scope->completed == job_count; }, 5s),
          "intrusive cleanup queue lost or duplicated a submission above the old cap");
}

void owned_descriptor_transport_test(LaunchFixture &fixture) {
  auto scope = std::make_shared<FakeScope>();
  auto supervisor =
      launcher::test_support::make_supervisor(FAKE_BWRAP_PATH, PROBE_PATH,
                                              scope);
  auto launched = supervisor.launch(fixture.request(), deadline_after(5s));
  require(static_cast<bool>(launched),
          "owned-descriptor transport worker did not launch");
  pollfd readiness{.fd = launched.worker->readiness_fd(),
                   .events = POLLIN,
                   .revents = 0};
  require(readiness.fd >= 0 && poll(&readiness, 1, 2000) == 1 &&
              (readiness.revents & POLLIN) != 0,
          "aggregate readiness did not expose a queued endpoint packet");
  const auto probe_message = launched.worker->receive(
      launcher::EndpointRole::control, launcher::PacketSizeLimit{sizeof(Probe)},
      deadline_after(2s));
  require(probe_message &&
              decode<Probe>(probe_message.payload).pid ==
                  launched.worker->identity().outer_worker_pid,
          "fake transport probe did not retain its bound outer identity");

  auto descriptor_message = launched.worker->receive_any(
      launcher::PacketSizeLimit{16}, deadline_after(2s));
  require(descriptor_message &&
              descriptor_message.role == launcher::EndpointRole::broker &&
              descriptor_message.descriptors.size() == 1 &&
              (fcntl(descriptor_message.descriptors.front().get(), F_GETFD) &
               FD_CLOEXEC) != 0,
          "valid inbound SCM_RIGHTS was not returned as owned CLOEXEC state");
  const auto descriptors_before = open_descriptor_count();
  auto malformed = launched.worker->receive(
      launcher::EndpointRole::render, launcher::PacketSizeLimit{16},
      deadline_after(2s));
  require(malformed.failure == launcher::ReceiveFailure::truncated &&
              malformed.descriptors.empty() &&
              open_descriptor_count() == descriptors_before,
          "truncated ancillary data leaked a received descriptor");

  const std::array acknowledgement{std::byte{1}};
  std::array<int, launcher::kMaximumTransportDescriptors> exact_descriptors{};
  exact_descriptors.fill(descriptor_message.descriptors.front().get());
  std::array<int, launcher::kMaximumTransportDescriptors + 1>
      oversized_descriptors{};
  oversized_descriptors.fill(descriptor_message.descriptors.front().get());
  require(launched.worker->try_send(launcher::EndpointRole::broker,
                                    acknowledgement,
                                    launcher::PacketSizeLimit{1},
                                    exact_descriptors) ==
                  launcher::SendStatus::complete &&
              launched.worker->try_send(launcher::EndpointRole::broker,
                                        acknowledgement,
                                        launcher::PacketSizeLimit{1},
                                        oversized_descriptors) ==
                  launcher::SendStatus::fatal,
          "SCM_RIGHTS transport descriptor hard bound changed");
  require(launched.worker->try_send(launcher::EndpointRole::control,
                                    acknowledgement,
                                    launcher::PacketSizeLimit{1}) ==
                  launcher::SendStatus::complete &&
              launched.worker->terminate(deadline_after(2s)) &&
              launched.worker->terminate(
                  std::chrono::steady_clock::now()) &&
              launched.worker->terminate(deadline_after(2s)),
          "owned-descriptor fixture did not tear down cleanly");
}

void pidfd_priority_test(LaunchFixture &fixture) {
  auto scope = std::make_shared<FakeScope>();
  auto supervisor =
      launcher::test_support::make_supervisor(FAKE_BWRAP_PATH, PROBE_PATH,
                                              scope);
  auto launched = supervisor.launch(fixture.request(), deadline_after(5s));
  require(static_cast<bool>(launched), "pidfd-priority worker did not launch");
  const std::array acknowledgement{std::byte{1}};
  require(launched.worker->try_send(launcher::EndpointRole::control,
                                    acknowledgement,
                                    launcher::PacketSizeLimit{1}) ==
              launcher::SendStatus::complete,
          "pidfd-priority worker did not receive its exit trigger");
  require(wait_until([&] { return !launched.worker->alive(); }, 2s),
          "pidfd-priority worker did not exit");
  const auto result = launched.worker->receive_any(
      launcher::PacketSizeLimit{sizeof(Probe)}, deadline_after(2s));
  require(result.status == launcher::ReceiveStatus::peer_closed &&
              result.failure == launcher::ReceiveFailure::worker_exited &&
              result.payload.empty() && result.descriptors.empty(),
          "queued endpoint data won over authoritative pidfd exit readiness");
  require(launched.worker->try_send(launcher::EndpointRole::control,
                                    acknowledgement,
                                    launcher::PacketSizeLimit{1}) ==
              launcher::SendStatus::peer_closed,
          "closed worker transport was not reported as peer_closed");
  require(launched.worker->terminate(deadline_after(5s)) &&
              scope->termination_count == 1,
          "pidfd-priority worker did not clean up exactly once");
}

void readiness_control_failure_test(LaunchFixture &fixture) {
  auto scope = std::make_shared<FakeScope>();
  auto supervisor =
      launcher::test_support::make_supervisor(FAKE_BWRAP_PATH, PROBE_PATH,
                                              scope);
  auto launched = supervisor.launch(fixture.request(), deadline_after(5s));
  require(static_cast<bool>(launched),
          "readiness-control failure worker did not launch");
  const int borrowed_readiness = launched.worker->readiness_fd();
  require(borrowed_readiness >= 0 && close(borrowed_readiness) == 0,
          "cannot inject aggregate epoll control failure");
  require(!launched.worker->set_readiness_interests(
              {.read = launcher::EndpointMask::all,
               .write = launcher::EndpointMask::broker}) &&
              !launched.worker->alive() &&
              launched.worker->terminate(deadline_after(2s)) &&
              scope->termination_count == 1,
          "epoll control failure retained partial transport authority");
}

void fake_bwrap_alias_test() {
  struct stat source{};
  require(lstat(FAKE_BWRAP_PATH, &source) == 0 &&
              S_ISREG(source.st_mode) && !S_ISLNK(source.st_mode) &&
              source.st_uid == geteuid(),
          "fake bwrap source is not a regular owned executable");
  for (const char *alias : {DUPLICATE_STATUS_BWRAP_PATH,
                            STRING_STATUS_BWRAP_PATH,
                            EXITED_STATUS_BWRAP_PATH}) {
    struct stat metadata{};
    require(lstat(alias, &metadata) == 0 && S_ISREG(metadata.st_mode) &&
                !S_ISLNK(metadata.st_mode) && metadata.st_dev == source.st_dev &&
                metadata.st_ino == source.st_ino &&
                metadata.st_uid == source.st_uid &&
                metadata.st_mode == source.st_mode,
            "fake bwrap alias is not the exact regular hardlink");
  }
}

void contract_test() {
  pidfd_reap_state_test();
  fake_bwrap_alias_test();
  auto scope = std::make_shared<FakeScope>();
  auto supervisor =
      launcher::test_support::make_supervisor(FAKE_BWRAP_PATH, PROBE_PATH,
                                              scope);
  LaunchFixture fixture;

  auto invalid = fixture.request();
  invalid.plugin_id = "../forged";
  require(supervisor.launch(invalid, deadline_after(5s)).failure ==
              launcher::LaunchFailure::invalid_trusted_record,
          "plugin-controlled identity syntax reached process launch");
  invalid = fixture.request();
  invalid.plugin_id = "1.invalid";
  require(supervisor.launch(invalid, deadline_after(5s)).failure ==
              launcher::LaunchFailure::invalid_trusted_record,
          "non-letter plugin identity reached process launch");
  invalid = fixture.request();
  invalid.generation = 0;
  require(supervisor.launch(invalid, deadline_after(5s)).failure ==
              launcher::LaunchFailure::invalid_trusted_record,
          "zero generation reached process launch");

  auto unavailable_scope = std::make_shared<FakeScope>();
  unavailable_scope->available = false;
  auto unavailable = launcher::test_support::make_supervisor(
      FAKE_BWRAP_PATH, PROBE_PATH, unavailable_scope);
  require(unavailable.launch(fixture.request(), deadline_after(5s)).failure ==
              launcher::LaunchFailure::missing_kernel_prerequisite,
          "launch proceeded without a resource controller");

  auto duplicate = launcher::test_support::make_supervisor(
      DUPLICATE_STATUS_BWRAP_PATH, PROBE_PATH, std::make_shared<FakeScope>());
  const auto duplicate_result =
      duplicate.launch(fixture.request(), deadline_after(5s));
  if (duplicate_result.failure !=
      launcher::LaunchFailure::status_protocol_failed) {
    std::cerr << "duplicate status failure="
              << static_cast<int>(duplicate_result.failure)
              << " detail=" << duplicate_result.detail << '\n';
  }
  require(duplicate_result.failure ==
              launcher::LaunchFailure::status_protocol_failed,
          "escaped duplicate authoritative status key was accepted");

  auto string_status = launcher::test_support::make_supervisor(
      STRING_STATUS_BWRAP_PATH, PROBE_PATH, std::make_shared<FakeScope>());
  require(string_status.launch(fixture.request(), deadline_after(5s)).failure ==
              launcher::LaunchFailure::status_protocol_failed,
          "string child PID was accepted as authoritative status");

  auto exited_status = launcher::test_support::make_supervisor(
      EXITED_STATUS_BWRAP_PATH, PROBE_PATH, std::make_shared<FakeScope>());
  require(exited_status.launch(fixture.request(), deadline_after(5s)).failure ==
              launcher::LaunchFailure::worker_exited_early,
          "combined child/exit status lost its early-exit authority");

  const auto invalid_executable = fixture.tree.root() / "invalid-bwrap";
  std::ofstream(invalid_executable) << "not an executable format\n";
  require(chmod(invalid_executable.c_str(), 0700) == 0,
          "cannot prepare exec-error fixture");
  auto exec_error = launcher::test_support::make_supervisor(
      invalid_executable.string(), PROBE_PATH, std::make_shared<FakeScope>());
  const auto failed_exec =
      exec_error.launch(fixture.request(), deadline_after(5s));
  require(failed_exec.failure == launcher::LaunchFailure::exec_failed,
          "exec-error handshake did not distinguish execve failure");

  owned_descriptor_transport_test(fixture);
  pidfd_priority_test(fixture);
  readiness_control_failure_test(fixture);
  deadline_and_async_cleanup_test(fixture);
  reaper_wake_and_cleanup_deadline_test();
  reaper_capacity_and_startup_test(fixture);
}

void malicious_test() {
  auto scope = std::make_shared<FakeScope>();
  auto supervisor = launcher::test_support::make_supervisor(
      FAKE_BWRAP_PATH, MALICIOUS_PROBE_PATH, scope);
  LaunchFixture fixture;
  auto launched = supervisor.launch(fixture.request(), deadline_after(5s));
  require(static_cast<bool>(launched) && scope->attached,
          "synthetic malicious worker launch failed");
  require(
      launched.worker
              ->receive(static_cast<launcher::EndpointRole>(99),
                        launcher::PacketSizeLimit{16},
                        std::chrono::steady_clock::now())
              .failure == launcher::ReceiveFailure::invalid_role,
      "unknown trusted endpoint role reached polling");

  const auto allowed = launcher::EndpointMask::control |
                       launcher::EndpointMask::render;
  require(launched.worker->set_readiness_interests(
              {.read = allowed, .write = launcher::EndpointMask::none}),
          "cannot arm the allowed endpoint readiness mask");
  require(await_readable_lanes(*launched.worker, allowed),
          "allowed endpoint lanes did not both become readable");
  const auto control = launched.worker->try_receive_any(
      launcher::PacketSizeLimit{sizeof(Claim)}, allowed);
  require(static_cast<bool>(control) &&
              control.role == launcher::EndpointRole::control &&
              decode<Claim>(control.payload).claimed_pid ==
                  launched.worker->identity().outer_worker_pid,
          "nonblocking receive lost the fair first ready lane");
  require(await_readable_lanes(*launched.worker,
                               launcher::EndpointMask::render),
          "render lane was not readable after the fair first receive");
  const auto render = launched.worker->try_receive_any(
      launcher::PacketSizeLimit{sizeof(Claim)}, allowed);
  require(static_cast<bool>(render) &&
              render.role == launcher::EndpointRole::render,
          "nonblocking receive did not consume exactly one fair ready lane");
  const auto empty = launched.worker->try_receive_any(
      launcher::PacketSizeLimit{sizeof(Claim)}, allowed);
  require(empty.status == launcher::ReceiveStatus::would_block &&
              empty.failure == launcher::ReceiveFailure::none &&
              empty.payload.empty() && empty.descriptors.empty(),
          "empty nonblocking receive blocked, consumed, or reported timeout");

  require(launched.worker->set_readiness_interests(
              {.read = allowed, .write = launcher::EndpointMask::broker}),
          "cannot arm broker write readiness independently of reads");
  epoll_event ready{};
  require(epoll_wait(launched.worker->readiness_fd(), &ready, 1, 1000) == 1 &&
              ready.data.u64 == 1 && (ready.events & EPOLLOUT) != 0 &&
              (ready.events & EPOLLIN) == 0,
          "masked broker read did not expose only its requested write wake");
  require(launched.worker->set_readiness_interests(
              {.read = allowed, .write = launcher::EndpointMask::control}),
          "cannot update aggregate write readiness");
  ready = {};
  require(epoll_wait(launched.worker->readiness_fd(), &ready, 1, 1000) == 1 &&
              ready.data.u64 == 0 && (ready.events & EPOLLOUT) != 0,
          "readiness update kept the prior writable lane armed");
  require(launched.worker->set_readiness_interests(
              {.read = allowed, .write = launcher::EndpointMask::none}),
          "cannot disarm aggregate write readiness");
  require(launched.worker
                  ->receive_any(
                      launcher::PacketSizeLimit{0},
                      std::chrono::steady_clock::now(), allowed)
                  .failure == launcher::ReceiveFailure::invalid_role &&
              launched.worker
                      ->receive_any(
                          launcher::PacketSizeLimit{
                              launcher::kTransportPacketHardLimit + 1},
                          std::chrono::steady_clock::now(), allowed)
                      .failure == launcher::ReceiveFailure::invalid_role &&
              launched.worker
                      ->receive_any(launcher::PacketSizeLimit{sizeof(Claim)},
                                    std::chrono::steady_clock::now(),
                                    launcher::EndpointMask::broker)
                      .failure == launcher::ReceiveFailure::invalid_role &&
              launched.worker
                      ->receive_any(launcher::PacketSizeLimit{sizeof(Claim)},
                                    std::chrono::steady_clock::now())
                      .failure == launcher::ReceiveFailure::timeout,
          "invalid or narrowed receive changed sticky read interests");
  const auto masked = launched.worker->receive(
      launcher::EndpointRole::broker,
      launcher::PacketSizeLimit{sizeof(Claim)}, deadline_after(10ms));
  require(masked.failure == launcher::ReceiveFailure::invalid_role,
          "lane receive bypassed the active endpoint mask");
  pollfd disabled_broker{.fd = launched.worker->readiness_fd(),
                         .events = POLLIN,
                         .revents = 0};
  require(poll(&disabled_broker, 1, 0) == 0,
          "disabled queued broker traffic kept aggregate readiness armed");
  require(launched.worker->set_readiness_interests(
              {.read = launcher::EndpointMask::broker,
               .write = launcher::EndpointMask::none}),
          "cannot re-arm broker readiness");
  disabled_broker.revents = 0;
  require(poll(&disabled_broker, 1, 1000) == 1 &&
              (disabled_broker.revents & POLLIN) != 0,
          "re-enabled broker traffic did not become readable");
  const auto descendant = launched.worker->receive(
      launcher::EndpointRole::broker,
      launcher::PacketSizeLimit{sizeof(Claim)}, deadline_after(2s));
  require(descendant.failure == launcher::ReceiveFailure::credential_mismatch,
          "forked inherited-endpoint holder passed kernel PID binding");
  constexpr std::size_t probe_broker_datagram_size = 40 + 65536;
  const auto maximum_broker = launched.worker->receive(
      launcher::EndpointRole::broker,
      launcher::PacketSizeLimit{launcher::kTransportPacketHardLimit},
      deadline_after(2s));
  require(static_cast<bool>(maximum_broker) &&
              maximum_broker.payload.size() == probe_broker_datagram_size,
          "legal broker datagram was rejected by the raw channel");
  require(launched.worker
                  ->receive(launcher::EndpointRole::broker,
                            launcher::PacketSizeLimit{
                                launcher::kTransportPacketHardLimit},
                            std::chrono::steady_clock::now())
                  .failure == launcher::ReceiveFailure::timeout &&
              launched.worker
                      ->receive(
                          launcher::EndpointRole::broker,
                          launcher::PacketSizeLimit{
                              launcher::kTransportPacketHardLimit + 1},
                          std::chrono::steady_clock::now())
                      .failure == launcher::ReceiveFailure::invalid_role,
          "canonical receive did not accept the transport maximum and reject +1");
  std::vector<std::byte> maximum_packet(launcher::kTransportPacketHardLimit,
                                        std::byte{0x32});
  std::vector<std::byte> oversized_packet(
      launcher::kTransportPacketHardLimit + 1, std::byte{0x33});
  require(launched.worker->try_send(
              launcher::EndpointRole::broker, maximum_packet,
              launcher::PacketSizeLimit{launcher::kTransportPacketHardLimit}) ==
                  launcher::SendStatus::complete,
          "exact transport packet maximum was rejected");
  require(launched.worker->try_send(
              launcher::EndpointRole::broker,
              std::span(maximum_packet),
              launcher::PacketSizeLimit{
                  launcher::kTransportPacketHardLimit - 1}) ==
                  launcher::SendStatus::fatal &&
              launched.worker->try_send(
                  launcher::EndpointRole::broker, oversized_packet,
                  launcher::PacketSizeLimit{
                      launcher::kTransportPacketHardLimit}) ==
                  launcher::SendStatus::fatal &&
              launched.worker->try_send(
                  launcher::EndpointRole::broker,
                  std::span(maximum_packet).first(1),
                  launcher::PacketSizeLimit{
                      launcher::kTransportPacketHardLimit + 1}) ==
                  launcher::SendStatus::fatal,
          "packet input escaped the explicit transport bounds");
  const std::array acknowledgement{std::byte{1}};
  support::UniqueFd passed(open("/dev/null", O_RDONLY | O_CLOEXEC));
  const std::array one{passed.get()};
  launcher::SendStatus saturated = launcher::SendStatus::complete;
  for (std::size_t attempts = 0;
       attempts < 100000 && saturated == launcher::SendStatus::complete;
       ++attempts) {
    saturated = launched.worker->try_send(launcher::EndpointRole::broker,
                                          acknowledgement,
                                          launcher::PacketSizeLimit{1}, one);
  }
  require(saturated == launcher::SendStatus::would_block && passed &&
              fcntl(passed.get(), F_GETFD) >= 0,
          "backpressure was not typed and atomic for borrowed SCM_RIGHTS");
  require(launched.worker->try_send(launcher::EndpointRole::control,
                                    acknowledgement,
                                    launcher::PacketSizeLimit{1}) ==
              launcher::SendStatus::complete,
      "descriptor-free launcher send failed");
  require(passed &&
              launched.worker->try_send(launcher::EndpointRole::control,
                                        acknowledgement,
                                        launcher::PacketSizeLimit{1}, one) ==
                  launcher::SendStatus::complete,
          "single descriptor launcher send failed");
  std::array<int, 17> excess{};
  excess.fill(passed.get());
  require(launched.worker->try_send(launcher::EndpointRole::control,
                                    acknowledgement,
                                    launcher::PacketSizeLimit{1}, excess) ==
                  launcher::SendStatus::fatal &&
              fcntl(passed.get(), F_GETFD) >= 0,
          "excess descriptors were sent or caller ownership was consumed");
  require(launched.worker->set_readiness_interests(
              {.read = launcher::EndpointMask::render,
               .write = launcher::EndpointMask::none}),
          "cannot arm render lane for descriptor report");
  const auto descriptor_report = launched.worker->receive(
      launcher::EndpointRole::render,
      launcher::PacketSizeLimit{sizeof(DescriptorReport)}, deadline_after(2s));
  require(static_cast<bool>(descriptor_report),
          "worker descriptor report was not received");
  const auto report = decode<DescriptorReport>(descriptor_report.payload);
  require(report.count == 1 && report.close_on_exec == 1,
          "worker did not receive exactly one close-on-exec descriptor");
  require(launched.worker->set_readiness_interests(
              {.read = launcher::EndpointMask::none,
               .write = launcher::EndpointMask::none}),
          "cannot disarm all endpoint readiness");
  pollfd exit_readiness{.fd = launched.worker->readiness_fd(),
                        .events = POLLIN,
                        .revents = 0};
  require(poll(&exit_readiness, 1, 2000) == 1 &&
              (exit_readiness.revents & POLLIN) != 0 &&
              launched.worker
                      ->receive_any(
                          launcher::PacketSizeLimit{1},
                          std::chrono::steady_clock::now() + 2s,
                          launcher::EndpointMask::none)
                      .failure == launcher::ReceiveFailure::worker_exited,
          "endpoint disarm also disabled authoritative pidfd readiness");

  launcher::Worker active_worker(std::move(*launched.worker));
  require(launched.worker
                  ->receive_any(launcher::PacketSizeLimit{1},
                                std::chrono::steady_clock::now())
                  .failure == launcher::ReceiveFailure::invalid_role &&
              launched.worker->try_send(launcher::EndpointRole::control,
                                        acknowledgement,
                                        launcher::PacketSizeLimit{1}) ==
                  launcher::SendStatus::peer_closed,
          "moved-from worker retained transport authority");
  require(active_worker.terminate(deadline_after(5s)) &&
              scope->termination_count == 1,
          "bounded normal teardown failed");
}

void bwrap_test() {
  if (access(BWRAP_PATH, X_OK) < 0) {
    std::cerr << "Bubblewrap unavailable; launcher integration skipped\n";
    std::exit(77);
  }
  auto scope = std::make_shared<FakeScope>();
  auto supervisor = launcher::test_support::make_supervisor(
      BWRAP_PATH, PROBE_PATH, scope);
  LaunchFixture fixture;
  auto launched = supervisor.launch(fixture.request(), deadline_after(5s));
  if (!launched &&
      (launched.detail.find("Operation not permitted") != std::string::npos ||
       launched.detail.find("SO_PASSCRED") != std::string::npos)) {
    std::cerr << "Outer sandbox denied kernel launch proof; skipped\n";
    std::exit(77);
  }
  require(static_cast<bool>(launched) && scope->attached_before_release,
          "real Bubblewrap launch failed before barrier-bound scope attach");
  validate_probe(*launched.worker);
  const auto injection = launched.worker->receive(
      launcher::EndpointRole::broker, launcher::PacketSizeLimit{16},
      deadline_after(2s));
  require(injection && injection.descriptors.size() == 1 &&
              (fcntl(injection.descriptors.front().get(), F_GETFD) &
               FD_CLOEXEC) != 0,
          "worker-originated descriptor was not safely owned and cloexec");
  const auto descriptors_before = open_descriptor_count();
  const auto truncated_ancillary =
      launched.worker->receive(launcher::EndpointRole::render,
                               launcher::PacketSizeLimit{16},
                               deadline_after(2s));
  const auto descriptors_after = open_descriptor_count();
  require(truncated_ancillary.failure == launcher::ReceiveFailure::truncated &&
              descriptors_after == descriptors_before,
          "MSG_CTRUNC leaked a delivered SCM_RIGHTS descriptor");
  const std::array acknowledgement{std::byte{1}};
  require(launched.worker->try_send(launcher::EndpointRole::control,
                                    acknowledgement,
                                    launcher::PacketSizeLimit{1}) ==
                  launcher::SendStatus::complete &&
              launched.worker->terminate(deadline_after(5s)) &&
              scope->termination_count == 1,
      "real Bubblewrap worker did not tear down within bounds");
}

std::string read_one_line(const std::filesystem::path &path) {
  std::ifstream stream(path);
  std::string line;
  std::getline(stream, line);
  if (!stream && !stream.eof()) {
    fail("cannot read enforced cgroup value: " + path.string());
  }
  return line;
}

void systemd_scope_test() {
  if (access(BWRAP_PATH, X_OK) < 0) {
    std::cerr << "Bubblewrap unavailable; systemd scope test skipped\n";
    std::exit(77);
  }
  const auto descriptors_before = support::open_fd_set();
  auto resource_scope = launcher::make_systemd_resource_scope_controller();
  auto supervisor = launcher::test_support::make_supervisor(
      BWRAP_PATH, PROBE_PATH, resource_scope);
  LaunchFixture fixture;
  auto launched = supervisor.launch(fixture.request(), deadline_after(5s));
  if (!launched &&
      (launched.failure == launcher::LaunchFailure::resource_scope_failed ||
       launched.failure ==
           launcher::LaunchFailure::missing_kernel_prerequisite)) {
    std::cerr << "systemd user scope unavailable: " << launched.detail << '\n';
    std::exit(77);
  }
  require(static_cast<bool>(launched),
          "real systemd-scoped Bubblewrap launch failed");
  validate_probe(*launched.worker);

  const auto cgroup_file =
      std::filesystem::path("/proc") /
      std::to_string(launched.worker->identity().outer_worker_pid) / "cgroup";
  const std::string cgroup_record = read_one_line(cgroup_file);
  const auto separator = cgroup_record.find("::");
  require(separator != std::string::npos,
          "worker did not enter a unified cgroup");
  const std::string cgroup_path = cgroup_record.substr(separator + 2);
  require(cgroup_path.find("app-omarchy-plugin-worker-") != std::string::npos,
          "worker was released outside its generation scope");
  const std::filesystem::path cgroup_root =
      std::filesystem::path("/sys/fs/cgroup") /
      cgroup_path.substr(cgroup_path.starts_with('/') ? 1 : 0);
  require(read_one_line(cgroup_root / "memory.high") == "402653184" &&
              read_one_line(cgroup_root / "memory.max") == "536870912" &&
              read_one_line(cgroup_root / "pids.max") == "16" &&
              read_one_line(cgroup_root / "cpu.weight") == "20" &&
              read_one_line(cgroup_root / "cpu.max").starts_with("50000 "),
          "systemd did not realize the process-scope cgroup ceilings");
  const auto io_weight = cgroup_root / "io.weight";
  if (std::filesystem::exists(io_weight)) {
    require(read_one_line(io_weight) == "default 10",
            "systemd did not realize process-scope IOWeight");
  } else {
    std::cerr << "io controller is not delegated on this host; IOWeight "
                 "enforcement remains a VM gate\n";
  }

  const auto injection = launched.worker->receive(
      launcher::EndpointRole::broker, launcher::PacketSizeLimit{16},
      deadline_after(2s));
  require(injection && injection.descriptors.size() == 1,
          "systemd-scoped worker descriptor transfer was not owned");
  const std::array acknowledgement{std::byte{1}};
  require(launched.worker->try_send(launcher::EndpointRole::control,
                                    acknowledgement,
                                    launcher::PacketSizeLimit{1}) ==
                  launcher::SendStatus::complete &&
              launched.worker->terminate(deadline_after(5s)),
      "systemd-scoped worker did not tear down within bounds");

  std::vector<int> bus_sockets;
  for (const int descriptor : support::open_fd_set()) {
    if (std::ranges::find(descriptors_before, descriptor) !=
        descriptors_before.end())
      continue;
    int type = 0;
    socklen_t size = sizeof(type);
    if (getsockopt(descriptor, SOL_SOCKET, SO_TYPE, &type, &size) == 0 &&
        type == SOCK_STREAM)
      bus_sockets.push_back(descriptor);
  }
  require(bus_sockets.size() >= 2,
          "systemd controller did not retain independent primary and cleanup buses");
  // probe() opens the primary bus before prepare_cleanup() opens its independent
  // cleanup bus, so the lower exact descriptor is the primary connection.
  require(shutdown(*std::ranges::min_element(bus_sockets), SHUT_RDWR) == 0,
          "cannot disconnect retained primary systemd bus");

  auto reconnected =
      supervisor.launch(fixture.request(), deadline_after(5s));
  require(static_cast<bool>(reconnected),
          "disconnected primary systemd bus did not reconnect for attachment");
  validate_probe(*reconnected.worker);
  require(reconnected.worker->try_send(launcher::EndpointRole::control,
                                       acknowledgement,
                                       launcher::PacketSizeLimit{1}) ==
                  launcher::SendStatus::complete &&
              reconnected.worker->terminate(deadline_after(5s)),
          "reconnected primary bus launch did not clean its exact scope");
}
} // namespace

int main(int argc, char **argv) {
  if (argc != 2) {
    return 64;
  }
  const std::string_view mode(argv[1]);
  if (mode == "scope") {
    generic_process_scope_request_test();
    reaper_wake_and_cleanup_deadline_test();
    nonblocking_bus_connection_test();
  } else if (mode == "contract") {
    contract_test();
  } else if (mode == "malicious") {
    malicious_test();
  } else if (mode == "bwrap") {
    bwrap_test();
  } else if (mode == "systemd") {
    systemd_scope_test();
  } else {
    return 64;
  }
  return 0;
}
