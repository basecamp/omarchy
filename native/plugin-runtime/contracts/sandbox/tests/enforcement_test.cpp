#include "omarchy/plugin_runtime/sandbox/policy.h"

#include <fcntl.h>
#include <linux/memfd.h>
#include <poll.h>
#include <seccomp.h>
#include <signal.h>
#include <sys/socket.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

#include <array>
#include <cerrno>
#include <chrono>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>
#include <string_view>
#include <thread>
#include <vector>

namespace sandbox = omarchy::plugin_runtime::sandbox;

namespace {
class ScratchTree {
public:
  ScratchTree() {
    std::array<char, 64> pattern{};
    std::strcpy(pattern.data(), "/tmp/omarchy-sandbox-contract.XXXXXX");
    char *created = mkdtemp(pattern.data());
    if (created == nullptr) {
      throw std::runtime_error("mkdtemp failed");
    }
    root_ = created;
    std::filesystem::create_directories(revision());
    std::filesystem::create_directories(state());
    std::ofstream(revision() / "fixture") << "revision\n";
    std::ofstream(root_ / "host-secret") << "secret\n";
  }

  ~ScratchTree() { std::filesystem::remove_all(root_); }

  [[nodiscard]] std::filesystem::path revision() const {
    return root_ / "revision";
  }
  [[nodiscard]] std::filesystem::path state() const { return root_ / "state"; }
  [[nodiscard]] std::filesystem::path state_result() const {
    return state() / "persisted";
  }

private:
  std::filesystem::path root_;
};

[[noreturn]] void child_fail(std::string_view message) {
  const std::string output =
      "sandbox enforcement child: " + std::string(message) + ": " +
      std::strerror(errno) + "\n";
  const ssize_t ignored = write(STDERR_FILENO, output.data(), output.size());
  static_cast<void>(ignored);
  _exit(126);
}

int open_directory(const std::filesystem::path &path) {
  const int descriptor = open(path.c_str(), O_RDONLY | O_DIRECTORY | O_CLOEXEC);
  if (descriptor < 0) {
    throw std::runtime_error("open directory failed");
  }
  return descriptor;
}

int create_seccomp_filter(const sandbox::SeccompPolicy &policy) {
  const int descriptor = static_cast<int>(
      syscall(SYS_memfd_create, "omarchy-plugin-seccomp", MFD_CLOEXEC));
  if (descriptor < 0) {
    throw std::runtime_error("memfd_create failed");
  }
  scmp_filter_ctx context = seccomp_init(SCMP_ACT_ERRNO(policy.denied_errno));
  if (context == nullptr) {
    close(descriptor);
    throw std::runtime_error("seccomp_init failed");
  }
  const int clone3_number = seccomp_syscall_resolve_name("clone3");
  if (clone3_number != __NR_SCMP_ERROR &&
      seccomp_rule_add(context, SCMP_ACT_ERRNO(policy.clone3_errno),
                       clone3_number, 0) < 0) {
    seccomp_release(context);
    close(descriptor);
    throw std::runtime_error("cannot compile clone3 compatibility denial");
  }
  for (const std::string &name : policy.launch_allowlist) {
    if (name == "clone") {
      const int syscall_number = seccomp_syscall_resolve_name(name.c_str());
      const std::uint64_t mask = policy.thread_clone.required_flags |
                                 policy.thread_clone.forbidden_flags;
      const int result =
          seccomp_rule_add(context, SCMP_ACT_ALLOW, syscall_number, 1,
                           SCMP_A0(SCMP_CMP_MASKED_EQ, mask,
                                   policy.thread_clone.required_flags));
      if (syscall_number == __NR_SCMP_ERROR || result < 0) {
        seccomp_release(context);
        close(descriptor);
        throw std::runtime_error("cannot compile restricted clone rule");
      }
      continue;
    }
    const int syscall_number = seccomp_syscall_resolve_name(name.c_str());
    if (syscall_number == __NR_SCMP_ERROR ||
        seccomp_rule_add(context, SCMP_ACT_ALLOW, syscall_number, 0) < 0) {
      seccomp_release(context);
      close(descriptor);
      throw std::runtime_error("cannot compile seccomp allowlist entry: " +
                               name);
    }
  }
  if (seccomp_export_bpf(context, descriptor) < 0 ||
      lseek(descriptor, 0, SEEK_SET) < 0) {
    seccomp_release(context);
    close(descriptor);
    throw std::runtime_error("cannot export seccomp filter");
  }
  seccomp_release(context);
  return descriptor;
}

struct Pipe {
  std::array<int, 2> descriptors{};
  Pipe() {
    if (pipe2(descriptors.data(), O_CLOEXEC) < 0) {
      throw std::runtime_error("pipe2 failed");
    }
  }
  ~Pipe() {
    close(descriptors.at(0));
    close(descriptors.at(1));
  }
};

struct Channel {
  std::array<int, 2> descriptors{};
  Channel() {
    if (socketpair(AF_UNIX, SOCK_SEQPACKET | SOCK_CLOEXEC, 0,
                   descriptors.data()) < 0) {
      throw std::runtime_error("socketpair failed");
    }
  }
  ~Channel() {
    close(descriptors.at(0));
    close(descriptors.at(1));
  }
};

std::vector<char *> pointers(std::vector<std::string> &strings) {
  std::vector<char *> result;
  result.reserve(strings.size() + 1);
  for (std::string &value : strings) {
    result.push_back(value.data());
  }
  result.push_back(nullptr);
  return result;
}

void relocate_and_exec(const sandbox::SandboxPlan &plan,
                       const std::array<int, 8> &sources) {
  std::array<int, 8> staged{};
  int minimum = 64;
  for (std::size_t index = 0; index < sources.size(); ++index) {
    staged.at(index) = fcntl(sources.at(index), F_DUPFD_CLOEXEC, minimum);
    if (staged.at(index) < 0) {
      child_fail("descriptor staging failed");
    }
    minimum = staged.at(index) + 1;
  }
  for (std::size_t index = 0; index < staged.size(); ++index) {
    if (dup2(staged.at(index), plan.launcher_descriptors.at(index)) < 0) {
      child_fail("descriptor relocation failed");
    }
  }
  if (syscall(SYS_close_range, 11U, ~0U, 0U) < 0) {
    child_fail("descriptor closure failed");
  }

  std::vector<std::string> arguments = plan.argv;
  std::vector<std::string> environment = plan.pre_bwrap_environment;
  std::vector<char *> argument_pointers = pointers(arguments);
  std::vector<char *> environment_pointers = pointers(environment);
  execve("/usr/bin/bwrap", argument_pointers.data(),
         environment_pointers.data());
  child_fail("bwrap exec failed");
}

int bounded_wait(pid_t child) {
  const int pidfd = static_cast<int>(syscall(SYS_pidfd_open, child, 0));
  if (pidfd >= 0) {
    pollfd descriptor{.fd = pidfd, .events = POLLIN, .revents = 0};
    const int ready = poll(&descriptor, 1, 10000);
    if (ready != 1 || descriptor.revents != POLLIN) {
      static_cast<void>(
          syscall(SYS_pidfd_send_signal, pidfd, SIGKILL, nullptr, 0));
    }
    close(pidfd);
  } else {
    // This is a direct-child test fixture, so the unreaped PID cannot have been
    // recycled. Production launch requires pidfd acquisition before release.
    static_cast<void>(kill(child, SIGKILL));
  }

  int status = 0;
  for (unsigned attempt = 0; attempt < 100; ++attempt) {
    const pid_t waited = waitpid(child, &status, WNOHANG);
    if (waited == child) {
      return status;
    }
    if (waited < 0) {
      return -1;
    }
    std::this_thread::sleep_for(std::chrono::milliseconds(10));
  }
  static_cast<void>(kill(child, SIGKILL));
  for (unsigned attempt = 0; attempt < 100; ++attempt) {
    const pid_t waited = waitpid(child, &status, WNOHANG);
    if (waited == child) {
      return status;
    }
    if (waited < 0) {
      return -1;
    }
    std::this_thread::sleep_for(std::chrono::milliseconds(10));
  }
  return -1;
}
} // namespace

int main() {
  if (access("/usr/bin/bwrap", X_OK) < 0) {
    std::cerr << "bubblewrap unavailable; enforcement probe skipped\n";
    return 77;
  }

  try {
    ScratchTree scratch;
    const sandbox::SandboxPlan plan =
        sandbox::build_test_plan_for_worker(SANDBOX_PROBE_PATH);
    Channel control;
    Channel broker;
    Channel render;
    Pipe status;
    Pipe barrier;
    const int seccomp = create_seccomp_filter(plan.seccomp);
    const int revision = open_directory(scratch.revision());
    const int state = open_directory(scratch.state());

    const std::array<int, 8> sources = {control.descriptors.at(1),
                                        broker.descriptors.at(1),
                                        render.descriptors.at(1),
                                        status.descriptors.at(1),
                                        barrier.descriptors.at(0),
                                        seccomp,
                                        revision,
                                        state};
    const pid_t child = fork();
    if (child < 0) {
      throw std::runtime_error("fork failed");
    }
    if (child == 0) {
      relocate_and_exec(plan, sources);
    }

    close(control.descriptors.at(1));
    control.descriptors.at(1) = -1;
    close(broker.descriptors.at(1));
    broker.descriptors.at(1) = -1;
    close(render.descriptors.at(1));
    render.descriptors.at(1) = -1;
    close(status.descriptors.at(1));
    status.descriptors.at(1) = -1;
    close(barrier.descriptors.at(0));
    barrier.descriptors.at(0) = -1;
    close(seccomp);
    close(revision);
    close(state);
    if (write(barrier.descriptors.at(1), "x", 1) != 1) {
      close(barrier.descriptors.at(1));
      barrier.descriptors.at(1) = -1;
      static_cast<void>(bounded_wait(child));
      throw std::runtime_error("barrier release failed");
    }
    close(barrier.descriptors.at(1));
    barrier.descriptors.at(1) = -1;

    const int status_value = bounded_wait(child);
    if (status_value < 0 || !WIFEXITED(status_value) ||
        WEXITSTATUS(status_value) != 0) {
      std::cerr << "sandboxed denial probe failed status=" << status_value
                << '\n';
      return 1;
    }
    if (!std::filesystem::exists(scratch.state_result())) {
      std::cerr << "private state write did not persist through its dedicated "
                   "mount\n";
      return 1;
    }
    return 0;
  } catch (const std::exception &error) {
    std::cerr << "sandbox enforcement test: " << error.what() << '\n';
    return 1;
  }
}
