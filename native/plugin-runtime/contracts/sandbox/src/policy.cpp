#include "omarchy/plugin_runtime/sandbox/policy.h"

#include <cerrno>
#include <filesystem>
#include <stdexcept>

#include <linux/sched.h>

namespace omarchy::plugin_runtime::sandbox {
namespace {

void append(std::vector<std::string> &arguments, std::string option,
            std::string value) {
  arguments.push_back(std::move(option));
  arguments.push_back(std::move(value));
}

std::string fd_string(int descriptor) {
  if (descriptor < 3) {
    throw std::invalid_argument(
        "sandbox descriptors must not overlap standard streams");
  }
  return std::to_string(descriptor);
}

void validate_worker_path(std::string_view worker_path) {
  if (worker_path.empty() ||
      !std::filesystem::path(worker_path).is_absolute()) {
    throw std::invalid_argument("worker path must be absolute");
  }
  const std::filesystem::path path(worker_path);
  if (path.lexically_normal() != path) {
    throw std::invalid_argument("worker path must be lexically normalized");
  }
}

std::vector<std::string> common_syscalls() {
  return {
      "access",
      "arch_prctl",
      "brk",
      "chdir",
      "clock_getres",
      "clock_gettime",
      "clock_nanosleep",
      "close",
      "close_range",
      "dup",
      "dup2",
      "dup3",
      "epoll_create1",
      "epoll_ctl",
      "epoll_pwait",
      "epoll_pwait2",
      "eventfd2",
      "exit",
      "exit_group",
      "faccessat2",
      "fallocate",
      "fcntl",
      "fdatasync",
      "fstat",
      "fsync",
      "ftruncate",
      "futex",
      "futex_waitv",
      "getcwd",
      "getdents64",
      "getegid",
      "geteuid",
      "getgid",
      "getpeername",
      "getpid",
      "getppid",
      "getrandom",
      "getresgid",
      "getresuid",
      "getsockname",
      "getsockopt",
      "gettid",
      "getuid",
      "inotify_add_watch",
      "inotify_init1",
      "inotify_rm_watch",
      "ioctl",
      "lseek",
      "madvise",
      "membarrier",
      "mincore",
      "mkdirat",
      "mmap",
      "mprotect",
      "mremap",
      "munmap",
      "nanosleep",
      "newfstatat",
      "openat",
      "openat2",
      "pipe2",
      "poll",
      "ppoll",
      "prctl",
      "pread64",
      "prlimit64",
      "pselect6",
      "pwrite64",
      "read",
      "readlink",
      "readlinkat",
      "recvfrom",
      "recvmmsg",
      "recvmsg",
      "renameat2",
      "restart_syscall",
      "rseq",
      "rt_sigaction",
      "rt_sigprocmask",
      "rt_sigreturn",
      "sched_getaffinity",
      "sched_yield",
      "sendmmsg",
      "sendmsg",
      "sendto",
      "set_robust_list",
      "set_tid_address",
      "setsockopt",
      "sigaltstack",
      "statx",
      "symlinkat",
      "tgkill",
      "timerfd_create",
      "timerfd_gettime",
      "timerfd_settime",
      "uname",
      "unlinkat",
      "write",
      "writev",
  };
}

SeccompPolicy seccomp_policy() {
  auto launch = common_syscalls();
  launch.emplace_back("execve");
  launch.emplace_back("execveat");
  launch.emplace_back("clone");

  auto steady = common_syscalls();
  steady.emplace_back("clone");

  constexpr std::uint64_t required = CLONE_VM | CLONE_SIGHAND | CLONE_THREAD;
  constexpr std::uint64_t forbidden =
      CLONE_NEWCGROUP | CLONE_NEWIPC | CLONE_NEWNET | CLONE_NEWNS |
      CLONE_NEWPID | CLONE_NEWTIME | CLONE_NEWUSER | CLONE_NEWUTS | CLONE_VFORK;
  return {.denied_errno = EPERM,
          .clone3_errno = ENOSYS,
          .launch_allowlist = std::move(launch),
          .steady_state_allowlist = std::move(steady),
          .thread_clone = {.required_flags = required,
                           .forbidden_flags = forbidden}};
}

} // namespace

SandboxPlan build_test_plan_for_worker(std::string worker_path) {
  validate_worker_path(worker_path);
  SandboxPlan plan;
  const auto &fd = plan.descriptors;
  plan.pre_bwrap_environment = {"PATH=/usr/bin", "PWD=/"};
  plan.worker_environment = {
      "HOME=/home/plugin",
      "LANG=C.UTF-8",
      "LC_ALL=C.UTF-8",
      "PATH=/runtime",
      "PWD=/plugin",
      "QT_QPA_PLATFORM=offscreen",
      "QSG_RHI_BACKEND=software",
      "XDG_CACHE_HOME=/tmp/cache",
      "XDG_CONFIG_HOME=/state/config",
      "XDG_DATA_HOME=/state/data",
      "XDG_RUNTIME_DIR=/run/plugin",
  };
  plan.worker_descriptors = {fd.control, fd.broker, fd.render};
  plan.launcher_descriptors = {fd.control,  fd.broker,       fd.render,
                               fd.status,   fd.barrier,      fd.seccomp,
                               fd.revision, fd.private_state};
  plan.seccomp = seccomp_policy();

  const auto &resources = plan.resources;
  plan.transient_scope_properties = {
      "MemoryHigh=" + std::to_string(resources.memory_high_bytes),
      "MemoryMax=" + std::to_string(resources.memory_max_bytes),
      "TasksMax=" + std::to_string(resources.tasks_max),
      "CPUQuota=" + std::to_string(resources.cpu_quota_percent) + "%",
      "CPUWeight=" + std::to_string(resources.cpu_weight),
      "IOWeight=" + std::to_string(resources.io_weight),
      "LimitNOFILE=" + std::to_string(resources.open_files_max),
      "LimitFSIZE=" + std::to_string(resources.file_size_max_bytes),
      "LimitCORE=" + std::to_string(resources.core_size_max_bytes),
      "OOMPolicy=kill",
      "KillMode=control-group",
  };

  plan.argv = {"/usr/bin/bwrap",
               "--unshare-user",
               "--unshare-pid",
               "--unshare-ipc",
               "--unshare-uts",
               "--unshare-net",
               "--unshare-cgroup",
               "--disable-userns",
               "--assert-userns-disabled",
               "--uid",
               "0",
               "--gid",
               "0",
               "--new-session",
               "--die-with-parent",
               "--as-pid-1",
               "--cap-drop",
               "ALL",
               "--hostname",
               "omarchy-plugin",
               "--clearenv"};

  for (const std::string &entry : plan.worker_environment) {
    const auto separator = entry.find('=');
    append(plan.argv, "--setenv", entry.substr(0, separator));
    plan.argv.push_back(entry.substr(separator + 1));
  }

  append(plan.argv, "--json-status-fd", fd_string(fd.status));
  append(plan.argv, "--block-fd", fd_string(fd.barrier));
  append(plan.argv, "--seccomp", fd_string(fd.seccomp));
  append(plan.argv, "--proc", "/proc");
  append(plan.argv, "--dev", "/dev");
  append(plan.argv, "--dir", "/usr");
  append(plan.argv, "--ro-bind", "/usr/lib");
  plan.argv.push_back("/usr/lib");
  append(plan.argv, "--symlink", "usr/lib");
  plan.argv.push_back("/lib");
  append(plan.argv, "--symlink", "usr/lib");
  plan.argv.push_back("/lib64");
  append(plan.argv, "--ro-bind-try", "/usr/share/fonts");
  plan.argv.push_back("/usr/share/fonts");
  append(plan.argv, "--ro-bind-try", "/usr/share/fontconfig");
  plan.argv.push_back("/usr/share/fontconfig");
  append(plan.argv, "--ro-bind-try", "/etc/fonts");
  plan.argv.push_back("/etc/fonts");
  append(plan.argv, "--ro-bind-try", "/etc/ld.so.cache");
  plan.argv.push_back("/etc/ld.so.cache");
  append(plan.argv, "--ro-bind-try", "/etc/localtime");
  plan.argv.push_back("/etc/localtime");
  append(plan.argv, "--dir", "/runtime");
  append(plan.argv, "--ro-bind", std::move(worker_path));
  plan.argv.push_back("/runtime/worker");
  append(plan.argv, "--ro-bind-fd", fd_string(fd.revision));
  plan.argv.push_back("/plugin");
  append(plan.argv, "--bind-fd", fd_string(fd.private_state));
  plan.argv.push_back("/state");
  append(plan.argv, "--size", std::to_string(resources.scratch_max_bytes));
  append(plan.argv, "--tmpfs", "/tmp");
  append(plan.argv, "--size", std::to_string(resources.runtime_max_bytes));
  append(plan.argv, "--tmpfs", "/run");
  append(plan.argv, "--dir", "/run/plugin");
  append(plan.argv, "--chmod", "0700");
  plan.argv.push_back("/run/plugin");
  append(plan.argv, "--tmpfs", "/home");
  append(plan.argv, "--dir", "/home/plugin");
  append(plan.argv, "--chmod", "0700");
  plan.argv.push_back("/home/plugin");
  append(plan.argv, "--chdir", "/plugin");
  plan.argv.push_back("--");
  plan.argv.push_back("/runtime/worker");
  return plan;
}

SandboxPlan build_plan() {
  return build_test_plan_for_worker(
      "/usr/lib/omarchy/plugin-runtime/omarchy-plugin-qml-worker");
}

bool contains_argument_pair(const SandboxPlan &plan, std::string_view option,
                            std::string_view value) {
  for (std::size_t index = 0; index + 1 < plan.argv.size(); ++index) {
    if (plan.argv.at(index) == option && plan.argv.at(index + 1) == value) {
      return true;
    }
  }
  return false;
}

} // namespace omarchy::plugin_runtime::sandbox
