#pragma once

#include <cstdint>
#include <string>
#include <string_view>
#include <vector>

namespace omarchy::plugin_runtime::sandbox {

struct DescriptorPolicy {
  int control = 3;
  int broker = 4;
  int render = 5;
  int status = 6;
  int barrier = 7;
  int seccomp = 8;
  int revision = 9;
  int private_state = 10;
};

struct ResourcePolicy {
  std::uint64_t memory_high_bytes = 384ULL * 1024ULL * 1024ULL;
  std::uint64_t memory_max_bytes = 512ULL * 1024ULL * 1024ULL;
  std::uint64_t scratch_max_bytes = 64ULL * 1024ULL * 1024ULL;
  std::uint64_t runtime_max_bytes = 16ULL * 1024ULL * 1024ULL;
  unsigned tasks_max = 16;
  unsigned cpu_quota_percent = 50;
  unsigned cpu_weight = 20;
  unsigned io_weight = 10;
  unsigned open_files_max = 64;
  std::uint64_t file_size_max_bytes = 64ULL * 1024ULL * 1024ULL;
  std::uint64_t core_size_max_bytes = 0;
  std::uint64_t output_burst_bytes = 64ULL * 1024ULL;
  std::uint64_t output_bytes_per_second = 4096;
};

struct TimeoutPolicy {
  unsigned launch_seconds = 5;
  unsigned hello_seconds = 3;
  unsigned request_seconds = 30;
  unsigned graceful_shutdown_seconds = 1;
  unsigned forced_teardown_seconds = 2;
  unsigned restart_window_seconds = 60;
  unsigned restart_burst = 3;
  unsigned restart_backoff_initial_seconds = 1;
  unsigned restart_backoff_max_seconds = 30;
  unsigned restart_stable_reset_seconds = 300;
  unsigned host_restart_window_seconds = 60;
  unsigned host_restart_burst = 5;
};

struct ProcessPolicy {
  bool worker_is_pid_one = true;
  bool descendants_permitted = false;
  bool require_no_new_privileges = true;
  bool bind_reported_pidfd_before_barrier_release = true;
  bool poll_pidfd_with_every_receive = true;
  bool recheck_pidfd_after_receive = true;
  bool signal_only_through_pidfd = true;
  bool kill_complete_generation_cgroup = true;
  bool reap_with_bounded_nonblocking_wait = true;
  bool invalidate_generation_before_cleanup = true;
  bool standard_input_is_dev_null = true;
  bool standard_output_is_bounded_pipe = true;
  bool standard_error_is_bounded_pipe = true;
  bool role_descriptors_are_close_on_exec = true;
  std::string transient_scope_prefix = "app-omarchy-plugin-worker-";
  std::vector<std::string> teardown_order = {
      "stop-accepting-messages",   "invalidate-generation-handles",
      "request-graceful-shutdown", "pidfd-sigkill-on-deadline",
      "kill-generation-cgroup",    "bounded-reap",
      "remove-runtime-scratch"};
};

struct ClonePolicy {
  std::uint64_t required_flags;
  std::uint64_t forbidden_flags;
};

struct SeccompPolicy {
  int denied_errno;
  int clone3_errno;
  std::vector<std::string> launch_allowlist;
  std::vector<std::string> steady_state_allowlist;
  ClonePolicy thread_clone;
};

struct SandboxPlan {
  DescriptorPolicy descriptors;
  std::vector<std::string> argv;
  std::vector<std::string> pre_bwrap_environment;
  std::vector<std::string> worker_environment;
  std::vector<int> worker_descriptors;
  std::vector<int> launcher_descriptors;
  std::vector<std::string> transient_scope_properties;
  ResourcePolicy resources;
  TimeoutPolicy timeouts;
  ProcessPolicy process;
  SeccompPolicy seccomp;
};

SandboxPlan build_plan();
SandboxPlan build_test_plan_for_worker(std::string worker_path);
bool contains_argument_pair(const SandboxPlan &plan, std::string_view option,
                            std::string_view value);

} // namespace omarchy::plugin_runtime::sandbox
