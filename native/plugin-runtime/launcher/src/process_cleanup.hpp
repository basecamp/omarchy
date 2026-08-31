#pragma once

#include "omarchy/plugin_runtime/launcher/launcher.h"

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdint>
#include <memory>
#include <mutex>
#include <string>
#include <sys/types.h>

namespace omarchy::plugin_runtime::launcher::detail {

struct ReapCompletion;

struct CleanupJob final {
  CleanupJob() = default;
  CleanupJob(const CleanupJob &) = delete;
  CleanupJob &operator=(const CleanupJob &) = delete;
  ~CleanupJob();

  int worker_pidfd = -1;
  int monitor_pidfd = -1;
  pid_t monitor_pid = -1;
  std::string scope;
  std::shared_ptr<ResourceScopeController> resource_scope;
  sandbox::TimeoutPolicy timeouts;
  std::shared_ptr<ReapCompletion> completion;
  bool allow_graceful_exit = true;
  bool scope_attached = false;
  std::chrono::steady_clock::time_point retry_after{};
  std::atomic<CleanupJob *> next = nullptr;
  std::atomic<bool> submitted = false;
};

struct ReapCompletion final {
  ReapCompletion() = default;
  ReapCompletion(const ReapCompletion &) = delete;
  ReapCompletion &operator=(const ReapCompletion &) = delete;
  std::mutex mutex;
  std::condition_variable ready;
  bool completed = false;
  bool succeeded = false;
  std::uint64_t failed_attempts = 0;
};

class ProcessScopeReaper final {
public:
  using WakeWriter = ssize_t (*)(int, const void *, std::size_t);
  explicit ProcessScopeReaper(bool force_start_failure,
                              WakeWriter wake_writer = nullptr);
  ProcessScopeReaper(const ProcessScopeReaper &) = delete;
  ProcessScopeReaper &operator=(const ProcessScopeReaper &) = delete;

  [[nodiscard]] bool start(std::string &error) noexcept;
  void submit(std::unique_ptr<CleanupJob> job) noexcept;

private:
  struct State;
  static void run(std::shared_ptr<State> state) noexcept;

  bool force_start_failure_ = false;
  WakeWriter wake_writer_ = nullptr;
  std::mutex start_mutex_;
  std::shared_ptr<State> state_;
};

void complete_reap(const std::shared_ptr<ReapCompletion> &completion,
                   bool succeeded) noexcept;

} // namespace omarchy::plugin_runtime::launcher::detail
