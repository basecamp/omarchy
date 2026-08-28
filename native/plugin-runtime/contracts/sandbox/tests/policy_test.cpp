#include "omarchy/plugin_runtime/sandbox/policy.h"

#include <algorithm>
#include <cstdlib>
#include <iostream>
#include <stdexcept>
#include <string>
#include <string_view>
#include <vector>

#include <linux/sched.h>

using omarchy::plugin_runtime::sandbox::build_plan;
using omarchy::plugin_runtime::sandbox::build_test_plan_for_worker;
using omarchy::plugin_runtime::sandbox::contains_argument_pair;
using omarchy::plugin_runtime::sandbox::SandboxPlan;

namespace {
[[noreturn]] void fail(std::string_view message) {
  std::cerr << message << '\n';
  std::exit(1);
}

void require(bool condition, std::string_view message) {
  if (!condition) {
    fail(message);
  }
}

bool contains(const std::vector<std::string> &values,
              std::string_view expected) {
  return std::ranges::find(values, expected) != values.end();
}

void verify_namespaces(const SandboxPlan &plan) {
  for (std::string_view argument :
       {"--unshare-user", "--unshare-pid", "--unshare-ipc", "--unshare-uts",
        "--unshare-net", "--unshare-cgroup", "--disable-userns",
        "--assert-userns-disabled", "--new-session", "--die-with-parent",
        "--as-pid-1"}) {
    require(contains(plan.argv, argument),
            "required namespace/lifetime control missing");
  }
  require(contains_argument_pair(plan, "--cap-drop", "ALL"),
          "ambient capabilities are not dropped");
}

void verify_environment(const SandboxPlan &plan) {
  require(plan.pre_bwrap_environment ==
              std::vector<std::string>({"PATH=/usr/bin", "PWD=/"}),
          "pre-bwrap environment is not minimal");
  require(contains(plan.argv, "--clearenv"),
          "worker inherits the manager environment");
  require(contains(plan.worker_environment, "QT_QPA_PLATFORM=offscreen"),
          "offscreen Qt platform is not pinned");
  require(contains(plan.worker_environment, "QSG_RHI_BACKEND=software"),
          "software renderer is not pinned");
  require(contains(plan.worker_environment, "HOME=/home/plugin"),
          "worker does not receive a private home");
  for (std::string_view forbidden :
       {"DISPLAY=", "WAYLAND_DISPLAY=", "DBUS_SESSION_BUS_ADDRESS=",
        "SSH_AUTH_SOCK=", "GNUPGHOME=", "XAUTHORITY="}) {
    require(std::ranges::none_of(plan.worker_environment,
                                 [forbidden](const std::string &value) {
                                   return value.starts_with(forbidden);
                                 }),
            "forbidden ambient authority is in the worker environment");
  }
}

void verify_mounts(const SandboxPlan &plan, std::string_view worker) {
  require(contains_argument_pair(plan, "--ro-bind", "/usr/lib"),
          "runtime libraries are not read-only");
  require(contains_argument_pair(plan, "--symlink", "usr/lib"),
          "dynamic loader compatibility link is absent");
  require(contains_argument_pair(plan, "--ro-bind", worker),
          "worker executable is not read-only");
  require(contains_argument_pair(plan, "--ro-bind-fd", "9"),
          "revision is not mounted from a trusted fd");
  require(contains_argument_pair(plan, "--bind-fd", "10"),
          "private state is not mounted from a trusted fd");
  require(contains_argument_pair(plan, "--tmpfs", "/tmp"),
          "scratch is not private tmpfs");
  require(contains_argument_pair(plan, "--tmpfs", "/run"),
          "runtime directory is not private tmpfs");
  require(contains_argument_pair(plan, "--tmpfs", "/home"),
          "home is not private tmpfs");
  require(!contains_argument_pair(plan, "--ro-bind", "/usr"),
          "the complete host /usr tree is exposed");
  require(!contains_argument_pair(plan, "--bind", "/"),
          "the host root is exposed");
  for (std::string_view forbidden :
       {"/run/user", "/home", "/sys", "/dev/dri", "/dev/input", "/etc/ssh"}) {
    require(std::ranges::none_of(plan.argv,
                                 [forbidden](const std::string &value) {
                                   return value == forbidden &&
                                          forbidden != "/home";
                                 }),
            "forbidden host mount is present");
  }
}

void verify_descriptors(const SandboxPlan &plan) {
  require(plan.descriptors.control == 3 && plan.descriptors.broker == 4 &&
              plan.descriptors.render == 5 && plan.descriptors.status == 6 &&
              plan.descriptors.barrier == 7 && plan.descriptors.seccomp == 8 &&
              plan.descriptors.revision == 9 &&
              plan.descriptors.private_state == 10,
          "named descriptor ABI changed");
  require(plan.worker_descriptors == std::vector<int>({3, 4, 5}),
          "worker nonstandard descriptor ABI changed");
  require(plan.launcher_descriptors ==
              std::vector<int>({3, 4, 5, 6, 7, 8, 9, 10}),
          "launcher descriptor allowlist changed");
  require(contains_argument_pair(plan, "--json-status-fd", "6"),
          "status fd is not fixed");
  require(contains_argument_pair(plan, "--block-fd", "7"),
          "startup barrier fd is not fixed");
  require(contains_argument_pair(plan, "--seccomp", "8"),
          "seccomp fd is not fixed");
}

void verify_resources(const SandboxPlan &plan) {
  require(plan.resources.memory_high_bytes < plan.resources.memory_max_bytes,
          "memory high must precede memory max");
  require(plan.resources.tasks_max == 16 &&
              plan.resources.cpu_quota_percent == 50,
          "process or CPU ceiling changed");
  require(plan.resources.open_files_max == 64 &&
              plan.resources.file_size_max_bytes == 64 * 1024 * 1024 &&
              plan.resources.core_size_max_bytes == 0,
          "descriptor, file-size, or core-dump ceiling changed");
  require(contains(plan.transient_scope_properties, "OOMPolicy=kill"),
          "OOM does not kill the worker generation");
  require(contains(plan.transient_scope_properties, "KillMode=control-group"),
          "teardown does not cover the complete worker cgroup");
  require(plan.timeouts.launch_seconds == 5 &&
              plan.timeouts.hello_seconds == 3 &&
              plan.timeouts.graceful_shutdown_seconds == 1 &&
              plan.timeouts.forced_teardown_seconds == 2,
          "bounded launch or teardown timing changed");
  require(plan.timeouts.restart_burst == 3 &&
              plan.timeouts.restart_window_seconds == 60 &&
              plan.timeouts.restart_backoff_max_seconds == 30,
          "restart ceiling changed");
  require(plan.timeouts.host_restart_burst == 5 &&
              plan.timeouts.host_restart_window_seconds == 60,
          "graphical-session host restart ceiling changed");
  require(plan.resources.output_burst_bytes == 64 * 1024 &&
              plan.resources.output_bytes_per_second == 4096,
          "captured output ceiling changed");
  require(plan.process.standard_input_is_dev_null &&
              plan.process.standard_output_is_bounded_pipe &&
              plan.process.standard_error_is_bounded_pipe,
          "standard streams expose ambient input or unbounded output");
}

void verify_lifecycle(const SandboxPlan &plan) {
  require(plan.process.worker_is_pid_one && !plan.process.descendants_permitted,
          "initial worker process model permits unsupervised descendants");
  require(plan.process.require_no_new_privileges &&
              plan.process.role_descriptors_are_close_on_exec,
          "privilege or descriptor inheritance can survive exec");
  require(plan.process.bind_reported_pidfd_before_barrier_release &&
              plan.process.poll_pidfd_with_every_receive &&
              plan.process.recheck_pidfd_after_receive &&
              plan.process.signal_only_through_pidfd,
          "worker identity is not bound to a live retained pidfd");
  require(plan.process.invalidate_generation_before_cleanup &&
              plan.process.kill_complete_generation_cgroup &&
              plan.process.reap_with_bounded_nonblocking_wait,
          "teardown can leave a valid generation or process tree behind");
  require(plan.process.teardown_order ==
              std::vector<std::string>(
                  {"stop-accepting-messages", "invalidate-generation-handles",
                   "request-graceful-shutdown", "pidfd-sigkill-on-deadline",
                   "kill-generation-cgroup", "bounded-reap",
                   "remove-runtime-scratch"}),
          "fail-closed teardown ordering changed");
}

void verify_seccomp(const SandboxPlan &plan) {
  require(plan.seccomp.denied_errno == EPERM, "seccomp default is not EPERM");
  require(plan.seccomp.clone3_errno == ENOSYS,
          "clone3 must report ENOSYS so libc falls back to restricted clone");
  for (std::string_view forbidden :
       {"bpf", "io_uring_setup", "keyctl", "memfd_create", "mount",
        "open_by_handle_at", "perf_event_open", "ptrace", "reboot", "socket",
        "swapoff", "swapon", "unshare", "userfaultfd"}) {
    require(!contains(plan.seccomp.launch_allowlist, forbidden),
            "dangerous syscall is allowed at launch");
    require(!contains(plan.seccomp.steady_state_allowlist, forbidden),
            "dangerous syscall is allowed at steady state");
  }
  require(contains(plan.seccomp.launch_allowlist, "execve"),
          "launch filter cannot start the worker");
  require(!contains(plan.seccomp.steady_state_allowlist, "execve") &&
              !contains(plan.seccomp.steady_state_allowlist, "execveat"),
          "steady-state worker can execute bundled code");
  require(!contains(plan.seccomp.steady_state_allowlist, "clone3"),
          "unfilterable clone3 is allowed");
  require((plan.seccomp.thread_clone.required_flags &
           (CLONE_VM | CLONE_SIGHAND | CLONE_THREAD)) ==
              (CLONE_VM | CLONE_SIGHAND | CLONE_THREAD),
          "clone rule does not require thread semantics");
  require((plan.seccomp.thread_clone.forbidden_flags & CLONE_NEWUSER) != 0,
          "clone rule permits a nested user namespace");
}
} // namespace

int main() {
  constexpr std::string_view worker =
      "/usr/lib/omarchy/plugin-runtime/omarchy-plugin-qml-worker";
  const SandboxPlan plan = build_plan();
  require(plan.argv.front() == "/usr/bin/bwrap" &&
              plan.argv.back() == "/runtime/worker",
          "launcher or worker path is not pinned");
  verify_namespaces(plan);
  verify_environment(plan);
  verify_mounts(plan, worker);
  verify_descriptors(plan);
  verify_resources(plan);
  verify_lifecycle(plan);
  verify_seccomp(plan);

  bool rejected_relative = false;
  try {
    static_cast<void>(build_test_plan_for_worker("relative-worker"));
  } catch (const std::invalid_argument &) {
    rejected_relative = true;
  }
  require(rejected_relative, "relative worker path was accepted");

  bool rejected_noncanonical = false;
  try {
    static_cast<void>(build_test_plan_for_worker("/tmp/../worker"));
  } catch (const std::invalid_argument &) {
    rejected_noncanonical = true;
  }
  require(rejected_noncanonical, "noncanonical worker path was accepted");
  return 0;
}
