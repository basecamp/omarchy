#include "process_cleanup.hpp"
#include "omarchy/plugin_runtime/launcher/termination_state.h"

#include <poll.h>
#include <sched.h>
#include <signal.h>
#include <sys/eventfd.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

#include <cerrno>
#include <chrono>
#include <cstdint>
#include <limits>
#include <thread>

namespace omarchy::plugin_runtime::launcher::detail {
namespace {

void close_owned(int &descriptor) noexcept {
  if (descriptor >= 0) close(descriptor);
  descriptor = -1;
}

void signal_pidfd(int descriptor) noexcept {
  if (descriptor >= 0)
    static_cast<void>(
        syscall(SYS_pidfd_send_signal, descriptor, SIGKILL, nullptr, 0));
}

[[nodiscard]] bool wait_pidfd(int descriptor,
                              std::chrono::milliseconds timeout) noexcept {
  if (descriptor < 0 || timeout.count() < 0 ||
      timeout.count() > std::numeric_limits<int>::max())
    return false;
  pollfd polled{.fd = descriptor, .events = POLLIN, .revents = 0};
  const int result = poll(&polled, 1, static_cast<int>(timeout.count()));
  return result == 1 && pidfd_has_exited(polled.revents);
}

[[nodiscard]] bool reap_child(pid_t process, int pidfd,
                              std::chrono::milliseconds timeout) noexcept {
  if (process <= 0 || timeout.count() < 0) return false;
  const auto deadline = std::chrono::steady_clock::now() + timeout;
  if (pidfd >= 0 && !wait_pidfd(pidfd, timeout)) return false;
  if (pidfd < 0) static_cast<void>(kill(process, SIGKILL));
  while (true) {
    int status = 0;
    const pid_t waited = waitpid(process, &status, WNOHANG);
    if (waited == process || (waited < 0 && errno == ECHILD)) return true;
    if (waited < 0 && errno != EINTR) return false;
    if (std::chrono::steady_clock::now() >= deadline) return false;
    sched_yield();
  }
}

[[nodiscard]] std::chrono::milliseconds
remaining(std::chrono::steady_clock::time_point deadline) noexcept {
  const auto duration = deadline - std::chrono::steady_clock::now();
  if (duration <= std::chrono::steady_clock::duration::zero())
    return std::chrono::milliseconds::zero();
  return std::chrono::duration_cast<std::chrono::milliseconds>(
      duration + std::chrono::milliseconds(1));
}

[[nodiscard]] bool execute(CleanupJob &job) noexcept {
  const auto graceful = std::chrono::seconds(
      job.allow_graceful_exit ? job.timeouts.graceful_shutdown_seconds : 0);
  bool worker_exited =
      job.worker_pidfd < 0 || wait_pidfd(job.worker_pidfd, graceful);
  if (!worker_exited)
    signal_pidfd(job.worker_pidfd);
  const auto forced_deadline =
      std::chrono::steady_clock::now() +
      std::chrono::seconds(job.timeouts.forced_teardown_seconds);
  bool scope_terminated = true;
  if (job.scope_attached && job.resource_scope) {
    std::string cleanup_error;
    scope_terminated = job.resource_scope->terminate_scope(
        job.scope, forced_deadline, cleanup_error);
  }
  if (!worker_exited) {
    worker_exited = wait_pidfd(job.worker_pidfd, remaining(forced_deadline));
  }
  signal_pidfd(job.monitor_pidfd);
  const bool monitor_reaped =
      job.monitor_pid <= 0 ||
      reap_child(job.monitor_pid, job.monitor_pidfd,
                 remaining(forced_deadline));
  return worker_exited && monitor_reaped && scope_terminated;
}

} // namespace

CleanupJob::~CleanupJob() {
  close_owned(worker_pidfd);
  close_owned(monitor_pidfd);
}

void complete_reap(const std::shared_ptr<ReapCompletion> &completion,
                   bool succeeded) noexcept {
  if (!completion) return;
  {
    std::lock_guard lock(completion->mutex);
    completion->completed = true;
    completion->succeeded = succeeded;
    if (!succeeded)
      ++completion->failed_attempts;
  }
  completion->ready.notify_all();
}

struct ProcessScopeReaper::State {
  ~State() {
    if (event >= 0) close(event);
  }
  int event = -1;
  std::atomic<CleanupJob *> pending = nullptr;
  std::atomic<unsigned> active_pushers = 0;
  std::atomic<bool> wake_failed = false;
  WakeWriter wake_writer = nullptr;
};

ProcessScopeReaper::ProcessScopeReaper(bool force_start_failure,
                                       WakeWriter wake_writer)
    : force_start_failure_(force_start_failure),
      wake_writer_(wake_writer != nullptr ? wake_writer : ::write) {}

bool ProcessScopeReaper::start(std::string &error) noexcept {
  std::lock_guard lock(start_mutex_);
  if (state_) {
    if (state_->wake_failed.load()) {
      error = "process reaper wake invariant failed";
      return false;
    }
    return true;
  }
  if (force_start_failure_) {
    error = "process reaper startup was rejected";
    return false;
  }
  try {
    auto state = std::make_shared<State>();
    state->event = eventfd(0, EFD_CLOEXEC | EFD_NONBLOCK);
    if (state->event < 0) {
      error = "cannot create process reaper event descriptor";
      return false;
    }
    state->wake_writer = wake_writer_;
    std::thread([state] { run(std::move(state)); }).detach();
    state_ = std::move(state);
    return true;
  } catch (const std::exception &exception) {
    error = std::string("cannot start process reaper: ") + exception.what();
    return false;
  }
}

void ProcessScopeReaper::submit(std::unique_ptr<CleanupJob> job) noexcept {
  if (!job || !state_ || job->submitted.exchange(true)) return;
  CleanupJob *submitted = job.release();
  state_->active_pushers.fetch_add(1);
  CleanupJob *head = state_->pending.load();
  do {
    submitted->next.store(head, std::memory_order_relaxed);
  } while (!state_->pending.compare_exchange_weak(
      head, submitted));
  state_->active_pushers.fetch_sub(1);
  const std::uint64_t one = 1;
  ssize_t result = -1;
  do {
    result = state_->wake_writer(state_->event, &one, sizeof(one));
  } while (result < 0 && errno == EINTR);
  if (result != static_cast<ssize_t>(sizeof(one)) &&
      !(result < 0 && errno == EAGAIN))
    state_->wake_failed.store(true);
}

void ProcessScopeReaper::run(std::shared_ptr<State> state) noexcept {
  CleanupJob *delayed = nullptr;
  for (;;) {
    pollfd ready{.fd = state->event, .events = POLLIN, .revents = 0};
    if (poll(&ready, 1, 10) < 0 && errno == EINTR) continue;
    std::uint64_t count = 0;
    while (read(state->event, &count, sizeof(count)) < 0 && errno == EINTR) {}
    CleanupJob *jobs = state->pending.exchange(nullptr);
    while (state->active_pushers.load() != 0)
      std::this_thread::yield();
    CleanupJob *waiting = nullptr;
    const auto now = std::chrono::steady_clock::now();
    while (delayed) {
      CleanupJob *job = delayed;
      delayed = job->next.load(std::memory_order_relaxed);
      if (job->retry_after <= now) {
        job->next.store(jobs, std::memory_order_relaxed);
        jobs = job;
      } else {
        job->next.store(waiting, std::memory_order_relaxed);
        waiting = job;
      }
    }
    delayed = waiting;
    CleanupJob *ordered = nullptr;
    while (jobs) {
      CleanupJob *next = jobs->next.load(std::memory_order_relaxed);
      jobs->next.store(ordered, std::memory_order_relaxed);
      ordered = jobs;
      jobs = next;
    }
    while (ordered) {
      std::unique_ptr<CleanupJob> job(ordered);
      ordered = job->next.load(std::memory_order_relaxed);
      if (execute(*job)) {
        complete_reap(job->completion, true);
      } else {
        complete_reap(job->completion, false);
        job->retry_after =
            std::chrono::steady_clock::now() + std::chrono::milliseconds(100);
        job->next.store(delayed, std::memory_order_relaxed);
        delayed = job.release();
      }
    }
  }
}

} // namespace omarchy::plugin_runtime::launcher::detail
