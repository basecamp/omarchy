#include "omarchy/plugin_runtime/sandbox/policy.h"
#include "omarchy/plugin_runtime/runtime_paths.hpp"

#include <algorithm>
#include <array>
#include <cerrno>
#include <filesystem>
#include <stdexcept>

#include <linux/sched.h>

namespace omarchy::plugin_runtime::sandbox {
namespace {
using namespace std::literals;

constexpr std::string_view qt_qml_source_root = "/usr/lib/qt6/qml";
constexpr std::string_view qt_qml_import_root = "/runtime/qml";

constexpr std::array qml_files{"libqmlplugin.so"sv, "plugins.qmltypes"sv,
                               "qmldir"sv};
constexpr std::array models_files{"libmodelsplugin.so"sv,
                                  "plugins.qmltypes"sv, "qmldir"sv};
constexpr std::array worker_script_files{"libworkerscriptplugin.so"sv,
                                         "plugins.qmltypes"sv, "qmldir"sv};
constexpr std::array quick_files{"libqtquick2plugin.so"sv,
                                 "plugins.qmltypes"sv, "qmldir"sv};
constexpr std::array shapes_files{"libqmlshapesplugin.so"sv,
                                  "plugins.qmltypes"sv, "qmldir"sv};
constexpr std::array layouts_files{"libqquicklayoutsplugin.so"sv,
                                   "plugins.qmltypes"sv, "qmldir"sv};
constexpr std::array effects_files{"libeffectsplugin.so"sv,
                                   "plugins.qmltypes"sv, "qmldir"sv};

constexpr std::array qml_trees{
    TrustedQmlResourceTree{"QtQml", qml_files, false},
    TrustedQmlResourceTree{"QtQml/Models", models_files, true},
    TrustedQmlResourceTree{"QtQml/WorkerScript", worker_script_files, true},
};
constexpr std::array quick_trees{
    TrustedQmlResourceTree{"QtQuick", quick_files, false}};
constexpr std::array shapes_trees{
    TrustedQmlResourceTree{"QtQuick/Shapes", shapes_files, true}};
constexpr std::array layouts_trees{
    TrustedQmlResourceTree{"QtQuick/Layouts", layouts_files, false}};
constexpr std::array effects_trees{
    TrustedQmlResourceTree{"QtQuick/Effects", effects_files, false}};

constexpr std::array qt_qml_modules{
    TrustedQmlModule{"QtQml", R"(
      import QtQml
      QtObject {}
    )",
                     qml_trees},
    TrustedQmlModule{"QtQuick", R"(
      import QtQuick
      Item {}
    )",
                     quick_trees},
    TrustedQmlModule{"QtQuick.Shapes", R"(
      import QtQuick
      import QtQuick.Shapes
      Shape { ShapePath { PathSvg { path: "M 0 0 L 1 1" } } }
    )",
                     shapes_trees},
    TrustedQmlModule{"QtQuick.Layouts", R"(
      import QtQuick
      import QtQuick.Layouts
      RowLayout { Rectangle { Layout.preferredWidth: 1 } }
    )",
                     layouts_trees},
    TrustedQmlModule{"QtQuick.Effects", R"(
      import QtQuick
      import QtQuick.Effects
      MultiEffect { source: Rectangle { width: 1; height: 1 } }
    )",
                     effects_trees},
};

const std::vector<std::string> qt_qml_files = [] {
  std::vector<std::string> result;
  for (const auto &module : qt_qml_modules) {
    for (const auto &tree : module.trees) {
      for (const auto file : tree.files)
        result.emplace_back(std::string(tree.path) + "/" + std::string(file));
    }
  }
  return result;
}();

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
  launch.emplace_back("fork");
  launch.emplace_back("vfork");

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

SandboxPlan build_plan_for_worker(std::string worker_path) {
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
  append(plan.argv, "--dir", "/runtime");
  append(plan.argv, "--dir", std::string(qt_qml_import_root));
  for (const auto &module : qt_qml_modules) {
    for (const auto &tree : module.trees)
      append(plan.argv, "--dir",
             std::string(qt_qml_import_root) + "/" + std::string(tree.path));
  }
  for (const auto &relative : qt_qml_files) {
    append(plan.argv, "--ro-bind",
           std::string(qt_qml_source_root) + "/" + relative);
    plan.argv.push_back(std::string(qt_qml_import_root) + "/" + relative);
  }
  append(plan.argv, "--tmpfs", std::string(qt_qml_source_root));
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
  append(plan.argv, "--ro-bind", std::move(worker_path));
  plan.argv.push_back("/runtime/worker");
  append(plan.argv, "--ro-bind-fd", fd_string(fd.revision));
  plan.argv.push_back("/plugin");
  append(plan.argv, "--bind-fd", fd_string(fd.private_state));
  plan.argv.push_back("/state");
  append(plan.argv, "--size", std::to_string(resources.scratch_max_bytes));
  append(plan.argv, "--tmpfs", "/tmp");
  append(plan.argv, "--dir", "/tmp/cache");
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

} // namespace

SandboxPlan build_plan() {
  return build_plan_for_worker(std::string(kPackagedWorkerPath));
}

std::string_view trusted_qml_import_root() { return qt_qml_import_root; }

const std::vector<std::string> &trusted_qml_files() { return qt_qml_files; }

std::span<const TrustedQmlModule> trusted_qml_modules() {
  return qt_qml_modules;
}

bool trusted_qml_public_module(std::string_view module) {
  return std::ranges::find(qt_qml_modules, module, &TrustedQmlModule::uri) !=
         qt_qml_modules.end();
}

bool trusted_qml_resource(std::string_view relative) {
  if (std::ranges::find(qt_qml_files, relative) != qt_qml_files.end())
    return true;
  for (const auto &module : qt_qml_modules) {
    for (const auto &tree : module.trees) {
      if (relative.starts_with(tree.path) && relative.size() > tree.path.size() &&
          relative[tree.path.size()] == '/' &&
          (tree.recursive_resources ||
           relative.find('/', tree.path.size() + 1) == relative.npos))
        return true;
    }
  }
  return false;
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
