#include "omarchy/plugin_runtime/launcher/launcher.h"
#include "omarchy/plugin_runtime/launcher/termination_state.h"
#include "omarchy/plugin_runtime/test_support/test_support.h"
#include "../src/process_cleanup.hpp"

#include <fcntl.h>
#include <poll.h>
#include <sys/epoll.h>
#include <sys/syscall.h>
#include <sys/stat.h>
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

template <typename Predicate>
bool wait_until(Predicate predicate, std::chrono::milliseconds timeout) {
  const auto deadline = std::chrono::steady_clock::now() + timeout;
  while (!predicate() && std::chrono::steady_clock::now() < deadline)
    std::this_thread::yield();
  return predicate();
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

  AttachResult attach(std::string_view unit, pid_t monitor_pid,
                      pid_t worker_pid, const sandbox::SandboxPlan &plan,
                      launcher::Deadline deadline,
                      std::string &error) override {
    attach_deadline = deadline;
    if (!attach_succeeds) {
      error = "synthetic scope attachment rejected";
      return {};
    }
    require(unit.starts_with("app-omarchy-plugin-worker-"),
            "scope name escaped the trusted prefix");
    require(monitor_pid > 0 && worker_pid > 0,
            "scope received an invalid process identity");
    require(plan.worker_descriptors == std::vector<int>({3, 4, 5}) &&
                plan.launcher_descriptors ==
                    std::vector<int>({3, 4, 5, 6, 7, 8, 9, 10}),
            "launcher did not consume the B5 descriptor contract");
    require(plan.resources.memory_max_bytes == 512ULL * 1024ULL * 1024ULL &&
                plan.resources.tasks_max == 16,
            "launcher did not consume the B5 resource/deadline contract");
    attached = true;
    attached_before_release = true;
    scope.assign(unit);
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

  void kill(std::string_view unit, launcher::Deadline) noexcept override {
    if (unit == scope) {
      ++kill_count;
    }
  }

  void remove(std::string_view unit,
              launcher::Deadline deadline) noexcept override {
    if (unit == scope) {
      if (remove_delay > 0ms)
        std::this_thread::sleep_until(std::min(
            deadline, std::chrono::steady_clock::now() + remove_delay));
      ++remove_count;
    }
  }

  bool available = true;
  bool attach_succeeds = true;
  bool attached = false;
  bool attached_before_release = false;
  std::atomic<unsigned> kill_count = 0;
  std::atomic<unsigned> remove_count = 0;
  std::chrono::milliseconds probe_delay{};
  std::chrono::milliseconds cleanup_setup_delay{};
  std::chrono::milliseconds attach_delay{};
  std::chrono::milliseconds remove_delay{};
  std::optional<launcher::Deadline> probe_deadline;
  std::optional<launcher::Deadline> cleanup_deadline;
  std::optional<launcher::Deadline> attach_deadline;
  std::string scope;
  bool cleanup_prepared = false;
};

class LegacyOnlyController : public launcher::ResourceScopeController {
public:
  void kill(std::string_view, launcher::Deadline) noexcept override {}
  void remove(std::string_view, launcher::Deadline) noexcept override {}
};

static_assert(std::is_abstract_v<LegacyOnlyController>,
              "legacy-only controllers must not enter the launch path");

class BlockingCleanupScope final : public launcher::ResourceScopeController {
public:
  bool probe(launcher::Deadline, std::string &) override { return true; }
  bool prepare_cleanup(launcher::Deadline, std::string &) override {
    return true;
  }
  AttachResult attach(std::string_view, pid_t, pid_t,
                      const sandbox::SandboxPlan &, launcher::Deadline,
                      std::string &) override {
    return {.attached = true, .cleanup_required = true};
  }
  void kill(std::string_view, launcher::Deadline) noexcept override {}
  void remove(std::string_view, launcher::Deadline) noexcept override {
    const unsigned current = entered.fetch_add(1) + 1;
    if (current == 1) {
      std::unique_lock lock(mutex);
      ready.notify_all();
      ready.wait(lock, [&] { return released; });
    }
    completed.fetch_add(1);
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
  AttachResult attach(std::string_view, pid_t, pid_t,
                      const sandbox::SandboxPlan &, launcher::Deadline,
                      std::string &) override {
    return {.attached = true, .cleanup_required = true};
  }
  void kill(std::string_view, launcher::Deadline) noexcept override {}
  void remove(std::string_view, launcher::Deadline deadline) noexcept override {
    if (calls.fetch_add(1) == 0)
      std::this_thread::sleep_until(
          std::min(deadline, std::chrono::steady_clock::now() + 50ms));
    completed.fetch_add(1);
  }
  std::atomic<unsigned> calls = 0;
  std::atomic<unsigned> completed = 0;
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
  const auto message =
      worker.receive(launcher::EndpointRole::control, sizeof(Probe), 2s);
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

void deadline_and_async_cleanup_test(LaunchFixture &fixture) {
  auto rejected_scope = std::make_shared<FakeScope>();
  rejected_scope->attach_succeeds = false;
  auto rejected_supervisor = launcher::Supervisor::forTestOnly(
      FAKE_BWRAP_PATH, PROBE_PATH, rejected_scope);
  const auto pre_call_rejected = rejected_supervisor.launch(fixture.request());
  require(pre_call_rejected.failure ==
              launcher::LaunchFailure::resource_scope_failed &&
              rejected_scope->remove_count == 0,
          "pre-call scope rejection acquired or cleaned nonexistent authority");

  auto scope = std::make_shared<FakeScope>();
  scope->remove_delay = 150ms;
  auto supervisor =
      launcher::Supervisor::forTestOnly(FAKE_BWRAP_PATH, PROBE_PATH, scope);
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
  require(wait_until([&] { return scope->remove_count.load() == 1; }, 2s),
          "asynchronous Worker cleanup did not remove its scope exactly once");

  auto delayed_setup_scope = std::make_shared<FakeScope>();
  delayed_setup_scope->cleanup_setup_delay = 1s;
  auto delayed_setup = launcher::Supervisor::forTestOnly(
      FAKE_BWRAP_PATH, PROBE_PATH, delayed_setup_scope);
  const auto setup_deadline = std::chrono::steady_clock::now() + 30ms;
  const auto setup_rejected =
      delayed_setup.launch(fixture.request(), setup_deadline);
  require(setup_rejected.failure == launcher::LaunchFailure::startup_timeout &&
              !delayed_setup_scope->cleanup_prepared &&
              !delayed_setup_scope->attach_deadline.has_value() &&
              delayed_setup_scope->remove_count == 0,
          "cleanup transport setup was delayed until after process authority");

  auto expiring_scope = std::make_shared<FakeScope>();
  expiring_scope->probe_delay = 10ms;
  expiring_scope->attach_delay = 1s;
  expiring_scope->remove_delay = 150ms;
  auto expiring = launcher::Supervisor::forTestOnly(
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
              [&] { return expiring_scope->remove_count.load() == 1; }, 2s),
          "timed-out attachment did not receive asynchronous cleanup");

  sandbox::SandboxPlan relative_plan = sandbox::build_test_plan_for_worker(
      PROBE_PATH);
  FakeScope relative_scope;
  relative_scope.attach_delay = 20ms;
  launcher::ResourceScopeController &relative_controller = relative_scope;
  std::string relative_error;
  const auto relative_result = relative_controller.attach(
      "app-omarchy-plugin-worker-relative.scope", getpid(), getpid(),
      relative_plan, 1ms, relative_error);
  require(!relative_result.attached && relative_result.cleanup_required,
          "relative attach adapter discarded ambiguous cleanup authority");
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
    job->scope_attached = true;
    reaper.submit(std::move(job));
  }
  require(wait_until([&] { return scope->completed == 2; }, 500ms),
          "bounded cleanup call stalled later cleanup authority");
}

void reaper_capacity_and_startup_test(LaunchFixture &fixture) {
  auto failed_scope = std::make_shared<FakeScope>();
  auto failed = launcher::Supervisor::forTestOnly(
      FAKE_BWRAP_PATH, PROBE_PATH, failed_scope, true);
  const auto rejected = failed.launch(fixture.request());
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
      launcher::Supervisor::forTestOnly(FAKE_BWRAP_PATH, PROBE_PATH, scope);
  auto launched = supervisor.launch(fixture.request());
  require(static_cast<bool>(launched),
          "owned-descriptor transport worker did not launch");
  pollfd readiness{.fd = launched.worker->readiness_fd(),
                   .events = POLLIN,
                   .revents = 0};
  require(readiness.fd >= 0 && poll(&readiness, 1, 2000) == 1 &&
              (readiness.revents & POLLIN) != 0,
          "aggregate readiness did not expose a queued endpoint packet");
  const auto probe_message = launched.worker->receive(
      launcher::EndpointRole::control, sizeof(Probe), 2s);
  require(probe_message &&
              decode<Probe>(probe_message.payload).pid ==
                  launched.worker->identity().outer_worker_pid,
          "fake transport probe did not retain its bound outer identity");

  auto descriptor_message = launched.worker->receive_any(
      16, std::chrono::steady_clock::now() + 2s);
  require(descriptor_message &&
              descriptor_message.role == launcher::EndpointRole::broker &&
              descriptor_message.descriptors.size() == 1 &&
              (fcntl(descriptor_message.descriptors.front().get(), F_GETFD) &
               FD_CLOEXEC) != 0,
          "valid inbound SCM_RIGHTS was not returned as owned CLOEXEC state");
  const auto descriptors_before = open_descriptor_count();
  auto malformed = launched.worker->receive(
      launcher::EndpointRole::render, 16,
      std::chrono::steady_clock::now() + 2s);
  require(malformed.failure == launcher::ReceiveFailure::truncated &&
              malformed.descriptors.empty() &&
              open_descriptor_count() == descriptors_before,
          "truncated ancillary data leaked a received descriptor");

  const std::array acknowledgement{std::byte{1}};
  require(launched.worker->try_send(launcher::EndpointRole::control,
                                    acknowledgement) ==
                  launcher::SendStatus::complete &&
              launched.worker->terminate(2s) &&
              launched.worker->terminate(
                  std::chrono::steady_clock::now()) &&
              launched.worker->terminate(),
          "owned-descriptor fixture did not tear down cleanly");
}

void pidfd_priority_test(LaunchFixture &fixture) {
  auto scope = std::make_shared<FakeScope>();
  auto supervisor =
      launcher::Supervisor::forTestOnly(FAKE_BWRAP_PATH, PROBE_PATH, scope);
  auto launched = supervisor.launch(fixture.request());
  require(static_cast<bool>(launched), "pidfd-priority worker did not launch");
  const std::array acknowledgement{std::byte{1}};
  require(launched.worker->try_send(launcher::EndpointRole::control,
                                    acknowledgement) ==
              launcher::SendStatus::complete,
          "pidfd-priority worker did not receive its exit trigger");
  require(wait_until([&] { return !launched.worker->alive(); }, 2s),
          "pidfd-priority worker did not exit");
  const auto result = launched.worker->receive_any(
      sizeof(Probe), std::chrono::steady_clock::now() + 2s);
  require(result.status == launcher::ReceiveStatus::peer_closed &&
              result.failure == launcher::ReceiveFailure::worker_exited &&
              result.payload.empty() && result.descriptors.empty(),
          "queued endpoint data won over authoritative pidfd exit readiness");
  require(launched.worker->try_send(launcher::EndpointRole::control,
                                    acknowledgement) ==
              launcher::SendStatus::peer_closed,
          "closed worker transport was not reported as peer_closed");
  require(launched.worker->terminate() && scope->remove_count == 1,
          "pidfd-priority worker did not clean up exactly once");
}

void readiness_control_failure_test(LaunchFixture &fixture) {
  auto scope = std::make_shared<FakeScope>();
  auto supervisor =
      launcher::Supervisor::forTestOnly(FAKE_BWRAP_PATH, PROBE_PATH, scope);
  auto launched = supervisor.launch(fixture.request());
  require(static_cast<bool>(launched),
          "readiness-control failure worker did not launch");
  const int borrowed_readiness = launched.worker->readiness_fd();
  require(borrowed_readiness >= 0 && close(borrowed_readiness) == 0,
          "cannot inject aggregate epoll control failure");
  require(!launched.worker->set_readiness_interests(
              {.read = launcher::EndpointMask::all,
               .write = launcher::EndpointMask::broker}) &&
              !launched.worker->alive() && launched.worker->terminate(2s) &&
              scope->remove_count == 1,
          "epoll control failure retained partial transport authority");
}

void contract_test() {
  pidfd_reap_state_test();
  auto scope = std::make_shared<FakeScope>();
  auto supervisor =
      launcher::Supervisor::forTestOnly(FAKE_BWRAP_PATH, PROBE_PATH, scope);
  LaunchFixture fixture;

  auto invalid = fixture.request();
  invalid.plugin_id = "../forged";
  require(supervisor.launch(invalid).failure ==
              launcher::LaunchFailure::invalid_trusted_record,
          "plugin-controlled identity syntax reached process launch");
  invalid = fixture.request();
  invalid.plugin_id = "1.invalid";
  require(supervisor.launch(invalid).failure ==
              launcher::LaunchFailure::invalid_trusted_record,
          "non-letter plugin identity reached process launch");
  invalid = fixture.request();
  invalid.generation = 0;
  require(supervisor.launch(invalid).failure ==
              launcher::LaunchFailure::invalid_trusted_record,
          "zero generation reached process launch");

  auto unavailable_scope = std::make_shared<FakeScope>();
  unavailable_scope->available = false;
  auto unavailable = launcher::Supervisor::forTestOnly(
      FAKE_BWRAP_PATH, PROBE_PATH, unavailable_scope);
  require(unavailable.launch(fixture.request()).failure ==
              launcher::LaunchFailure::missing_kernel_prerequisite,
          "launch proceeded without a resource controller");

  auto duplicate = launcher::Supervisor::forTestOnly(
      DUPLICATE_STATUS_BWRAP_PATH, PROBE_PATH, std::make_shared<FakeScope>());
  const auto duplicate_result = duplicate.launch(fixture.request());
  if (duplicate_result.failure !=
      launcher::LaunchFailure::status_protocol_failed) {
    std::cerr << "duplicate status failure="
              << static_cast<int>(duplicate_result.failure)
              << " detail=" << duplicate_result.detail << '\n';
  }
  require(duplicate_result.failure ==
              launcher::LaunchFailure::status_protocol_failed,
          "escaped duplicate authoritative status key was accepted");

  auto string_status = launcher::Supervisor::forTestOnly(
      STRING_STATUS_BWRAP_PATH, PROBE_PATH, std::make_shared<FakeScope>());
  require(string_status.launch(fixture.request()).failure ==
              launcher::LaunchFailure::status_protocol_failed,
          "string child PID was accepted as authoritative status");

  auto exited_status = launcher::Supervisor::forTestOnly(
      EXITED_STATUS_BWRAP_PATH, PROBE_PATH, std::make_shared<FakeScope>());
  require(exited_status.launch(fixture.request()).failure ==
              launcher::LaunchFailure::worker_exited_early,
          "combined child/exit status lost its early-exit authority");

  const auto invalid_executable = fixture.tree.root() / "invalid-bwrap";
  std::ofstream(invalid_executable) << "not an executable format\n";
  require(chmod(invalid_executable.c_str(), 0700) == 0,
          "cannot prepare exec-error fixture");
  auto exec_error = launcher::Supervisor::forTestOnly(
      invalid_executable.string(), PROBE_PATH, std::make_shared<FakeScope>());
  const auto failed_exec = exec_error.launch(fixture.request());
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
  auto supervisor = launcher::Supervisor::forTestOnly(
      FAKE_BWRAP_PATH, MALICIOUS_PROBE_PATH, scope);
  LaunchFixture fixture;
  auto launched = supervisor.launch(fixture.request());
  require(static_cast<bool>(launched) && scope->attached,
          "synthetic malicious worker launch failed");
  require(
      launched.worker->receive(static_cast<launcher::EndpointRole>(99), 16, 0ms)
              .failure == launcher::ReceiveFailure::invalid_role,
      "unknown trusted endpoint role reached polling");

  const auto allowed = launcher::EndpointMask::control |
                       launcher::EndpointMask::render;
  require(launched.worker->set_receive_mask(allowed),
          "cannot arm the allowed endpoint readiness mask");
  const auto control = launched.worker->receive_any(
      sizeof(Claim), std::chrono::steady_clock::now() + 2s, allowed);
  require(static_cast<bool>(control) &&
              control.role == launcher::EndpointRole::control &&
              decode<Claim>(control.payload).claimed_pid ==
                  launched.worker->identity().outer_worker_pid,
          "bound worker message was not accepted");
  const auto render = launched.worker->receive_any(
      sizeof(Claim), std::chrono::steady_clock::now() + 2s, allowed);
  require(static_cast<bool>(render) &&
              render.role == launcher::EndpointRole::render,
          "disabled broker lane starved an allowed render packet");

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
                      .failure == launcher::ReceiveFailure::timeout &&
              launched.worker
                      ->receive_any(0, std::chrono::steady_clock::now(),
                                    launcher::EndpointMask::broker)
                      .failure == launcher::ReceiveFailure::invalid_role,
          "invalid or narrowed receive changed sticky read interests");
  const auto masked_legacy = launched.worker->receive(
      launcher::EndpointRole::broker, sizeof(Claim),
      std::chrono::steady_clock::now() + 10ms);
  require(masked_legacy.failure == launcher::ReceiveFailure::invalid_role,
          "legacy lane receive bypassed the active endpoint mask");
  pollfd disabled_broker{.fd = launched.worker->readiness_fd(),
                         .events = POLLIN,
                         .revents = 0};
  require(poll(&disabled_broker, 1, 0) == 0,
          "disabled queued broker traffic kept aggregate readiness armed");
  require(launched.worker->set_receive_mask(launcher::EndpointMask::broker),
          "cannot re-arm broker readiness");
  disabled_broker.revents = 0;
  require(poll(&disabled_broker, 1, 1000) == 1 &&
              (disabled_broker.revents & POLLIN) != 0,
          "re-enabled broker traffic did not become readable");
  const auto descendant = launched.worker->receive(
      launcher::EndpointRole::broker, sizeof(Claim), 2s);
  require(descendant.failure == launcher::ReceiveFailure::credential_mismatch,
          "forked inherited-endpoint holder passed kernel PID binding");
  const auto maximum_broker =
      launched.worker->receive(launcher::EndpointRole::broker, 40 + 65536, 2s);
  require(static_cast<bool>(maximum_broker) &&
              maximum_broker.payload.size() == 40 + 65536,
          "legal maximum broker envelope was rejected by the raw channel");
  constexpr std::size_t v1_broker_maximum = 40 + 65536;
  constexpr std::size_t v2_broker_maximum = 48 + 65536;
  require(launched.worker
                  ->receive(launcher::EndpointRole::broker,
                            launcher::PacketSizeLimit{v2_broker_maximum},
                            std::chrono::steady_clock::now())
                  .failure == launcher::ReceiveFailure::timeout &&
              launched.worker
                      ->receive(
                          launcher::EndpointRole::broker,
                          launcher::PacketSizeLimit{v2_broker_maximum + 1},
                          std::chrono::steady_clock::now())
                      .failure == launcher::ReceiveFailure::invalid_role,
          "canonical receive did not accept v2 maximum and reject +1");
  std::vector<std::byte> v1_packet(v1_broker_maximum, std::byte{0x31});
  std::vector<std::byte> v2_packet(v2_broker_maximum, std::byte{0x32});
  std::vector<std::byte> v2_oversized(v2_broker_maximum + 1,
                                      std::byte{0x33});
  require(launched.worker->try_send(launcher::EndpointRole::broker,
                                    v1_packet) ==
                  launcher::SendStatus::complete &&
              launched.worker->try_send(
                  launcher::EndpointRole::broker, v2_packet,
                  launcher::PacketSizeLimit{v2_broker_maximum}) ==
                  launcher::SendStatus::complete,
          "exact v1/v2 transport packet maxima were rejected");
  require(launched.worker->try_send(
              launcher::EndpointRole::broker,
              std::span(v1_packet).first(v1_broker_maximum),
              launcher::PacketSizeLimit{v1_broker_maximum - 1}) ==
                  launcher::SendStatus::fatal &&
              launched.worker->try_send(
                  launcher::EndpointRole::broker,
                  std::span(v2_packet).first(v1_broker_maximum + 1)) ==
                  launcher::SendStatus::fatal &&
              launched.worker->try_send(
                  launcher::EndpointRole::broker, v2_oversized,
                  launcher::PacketSizeLimit{v2_broker_maximum}) ==
                  launcher::SendStatus::fatal &&
              launched.worker->try_send(
                  launcher::EndpointRole::broker, std::span(v1_packet).first(1),
                  launcher::PacketSizeLimit{v2_broker_maximum + 1}) ==
                  launcher::SendStatus::fatal,
          "packet-limit +1 input escaped v1/v2 transport bounds");
  const std::array acknowledgement{std::byte{1}};
  support::UniqueFd passed(open("/dev/null", O_RDONLY | O_CLOEXEC));
  const std::array one{passed.get()};
  launcher::SendStatus saturated = launcher::SendStatus::complete;
  for (std::size_t attempts = 0;
       attempts < 100000 && saturated == launcher::SendStatus::complete;
       ++attempts) {
    saturated = launched.worker->try_send(launcher::EndpointRole::broker,
                                          acknowledgement, one);
  }
  require(saturated == launcher::SendStatus::would_block && passed &&
              fcntl(passed.get(), F_GETFD) >= 0,
          "backpressure was not typed and atomic for borrowed SCM_RIGHTS");
  require(
      launched.worker->send(launcher::EndpointRole::control, acknowledgement),
      "descriptor-free launcher send failed");
  require(passed && launched.worker->send_with_descriptors(
                        launcher::EndpointRole::control, acknowledgement, one),
          "single descriptor launcher send failed");
  std::array<int, 17> excess{};
  excess.fill(passed.get());
  require(launched.worker->try_send(launcher::EndpointRole::control,
                                    acknowledgement, excess) ==
                  launcher::SendStatus::fatal &&
              fcntl(passed.get(), F_GETFD) >= 0,
          "excess descriptors were sent or caller ownership was consumed");
  require(launched.worker->set_receive_mask(launcher::EndpointMask::render),
          "cannot arm render lane for descriptor report");
  const auto descriptor_report = launched.worker->receive(
      launcher::EndpointRole::render, sizeof(DescriptorReport), 2s);
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
  require(active_worker.terminate() && scope->remove_count == 1,
          "bounded normal teardown failed");
}

void bwrap_test() {
  if (access(BWRAP_PATH, X_OK) < 0) {
    std::cerr << "Bubblewrap unavailable; launcher integration skipped\n";
    std::exit(77);
  }
  auto scope = std::make_shared<FakeScope>();
  auto supervisor =
      launcher::Supervisor::forTestOnly(BWRAP_PATH, PROBE_PATH, scope);
  LaunchFixture fixture;
  auto launched = supervisor.launch(fixture.request());
  if (!launched &&
      (launched.detail.find("Operation not permitted") != std::string::npos ||
       launched.detail.find("SO_PASSCRED") != std::string::npos)) {
    std::cerr << "Outer sandbox denied kernel launch proof; skipped\n";
    std::exit(77);
  }
  require(static_cast<bool>(launched) && scope->attached_before_release,
          "real Bubblewrap launch failed before barrier-bound scope attach");
  validate_probe(*launched.worker);
  const auto injection =
      launched.worker->receive(launcher::EndpointRole::broker, 16, 2s);
  require(injection && injection.descriptors.size() == 1 &&
              (fcntl(injection.descriptors.front().get(), F_GETFD) &
               FD_CLOEXEC) != 0,
          "worker-originated descriptor was not safely owned and cloexec");
  const auto descriptors_before = open_descriptor_count();
  const auto truncated_ancillary =
      launched.worker->receive(launcher::EndpointRole::render, 16, 2s);
  const auto descriptors_after = open_descriptor_count();
  require(truncated_ancillary.failure == launcher::ReceiveFailure::truncated &&
              descriptors_after == descriptors_before,
          "MSG_CTRUNC leaked a delivered SCM_RIGHTS descriptor");
  const std::array acknowledgement{std::byte{1}};
  require(
      launched.worker->send(launcher::EndpointRole::control, acknowledgement) &&
          launched.worker->terminate() && scope->remove_count == 1,
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
  auto supervisor = launcher::Supervisor::forTestOnly(
      BWRAP_PATH, PROBE_PATH,
      launcher::make_systemd_resource_scope_controller());
  LaunchFixture fixture;
  auto launched = supervisor.launch(fixture.request());
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
          "systemd did not realize the B5 cgroup ceilings");
  const auto io_weight = cgroup_root / "io.weight";
  if (std::filesystem::exists(io_weight)) {
    require(read_one_line(io_weight) == "default 10",
            "systemd did not realize B5 IOWeight");
  } else {
    std::cerr << "io controller is not delegated on this host; IOWeight "
                 "enforcement remains a VM gate\n";
  }

  const auto injection =
      launched.worker->receive(launcher::EndpointRole::broker, 16, 2s);
  require(injection && injection.descriptors.size() == 1,
          "systemd-scoped worker descriptor transfer was not owned");
  const std::array acknowledgement{std::byte{1}};
  require(
      launched.worker->send(launcher::EndpointRole::control, acknowledgement) &&
          launched.worker->terminate(),
      "systemd-scoped worker did not tear down within bounds");
}
} // namespace

int main(int argc, char **argv) {
  if (argc != 2) {
    return 64;
  }
  const std::string_view mode(argv[1]);
  if (mode == "contract") {
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
