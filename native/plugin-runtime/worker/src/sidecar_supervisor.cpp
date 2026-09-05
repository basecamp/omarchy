#include "sidecar_supervisor.hpp"

#include <fcntl.h>
#include <signal.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

#include <array>
#include <cerrno>
#include <chrono>
#include <cstring>
#include <thread>

namespace omarchy::plugin_runtime::worker {
namespace {

[[nodiscard]] bool write_exec_error(int descriptor, int error) noexcept {
  const auto *bytes = reinterpret_cast<const std::byte *>(&error);
  std::size_t written = 0;
  while (written < sizeof(error)) {
    const ssize_t count =
        write(descriptor, bytes + written, sizeof(error) - written);
    if (count < 0 && errno == EINTR)
      continue;
    if (count <= 0)
      return false;
    written += static_cast<std::size_t>(count);
  }
  return true;
}

[[noreturn]] void run_sidecar(
    const plugins::manifest::Runtime::Sidecar &sidecar, int error_fd) {
  if (syscall(SYS_close_range, 3U, static_cast<unsigned>(error_fd - 1), 0U) <
          0 ||
      syscall(SYS_close_range, static_cast<unsigned>(error_fd + 1), ~0U,
              0U) < 0) {
    const int saved = errno;
    if (!write_exec_error(error_fd, saved))
      _exit(127);
    _exit(126);
  }
  const std::string executable = "/plugin/" + sidecar.command.front();
  std::vector<std::string> arguments = sidecar.command;
  arguments.front() = executable;
  std::vector<char *> pointers;
  pointers.reserve(arguments.size() + 1);
  for (auto &argument : arguments)
    pointers.push_back(argument.data());
  pointers.push_back(nullptr);
  execve(executable.c_str(), pointers.data(), ::environ);
  const int saved = errno;
  if (!write_exec_error(error_fd, saved))
    _exit(127);
  _exit(126);
}

bool reap(pid_t pid, int options, int &status) {
  for (;;) {
    const pid_t result = waitpid(pid, &status, options);
    if (result == pid || (result < 0 && errno == ECHILD))
      return true;
    if (result == 0)
      return false;
    if (errno != EINTR)
      return false;
  }
}

} // namespace

SidecarSupervisor::~SidecarSupervisor() { terminate(); }

bool SidecarSupervisor::start(
    const std::vector<plugins::manifest::Runtime::Sidecar> &sidecars,
    std::string &error) {
  if (!children_.empty()) {
    error = "sidecars already started";
    return false;
  }
  for (const auto &sidecar : sidecars) {
    std::array<int, 2> descriptors{};
    if (pipe2(descriptors.data(), O_CLOEXEC) < 0) {
      error = "cannot create sidecar exec handshake";
      terminate();
      return false;
    }
    const pid_t pid = fork();
    if (pid < 0) {
      close(descriptors[0]);
      close(descriptors[1]);
      error = "cannot fork declared sidecar";
      terminate();
      return false;
    }
    if (pid == 0) {
      close(descriptors[0]);
      run_sidecar(sidecar, descriptors[1]);
    }
    close(descriptors[1]);
    int exec_error = 0;
    ssize_t count = -1;
    do {
      count = read(descriptors[0], &exec_error, sizeof(exec_error));
    } while (count < 0 && errno == EINTR);
    close(descriptors[0]);
    if (count != 0) {
      int status = 0;
      static_cast<void>(reap(pid, 0, status));
      error = count == sizeof(exec_error)
                  ? "cannot execute declared sidecar: " +
                        std::string(std::strerror(exec_error))
                  : "invalid sidecar exec handshake";
      terminate();
      return false;
    }
    children_.push_back({.name = sidecar.name, .pid = pid});
  }
  return true;
}

bool SidecarSupervisor::healthy(std::string &error) {
  for (auto &child : children_) {
    if (child.pid <= 0)
      continue;
    int status = 0;
    const pid_t result = waitpid(child.pid, &status, WNOHANG);
    if (result == 0)
      continue;
    if (result == child.pid || (result < 0 && errno == ECHILD)) {
      child.pid = -1;
      error = "declared sidecar exited: " + child.name;
      return false;
    }
    if (result < 0 && errno != EINTR) {
      error = "cannot inspect declared sidecar: " + child.name;
      return false;
    }
  }
  return true;
}

void SidecarSupervisor::terminate() noexcept {
  for (const auto &child : children_) {
    if (child.pid > 0)
      static_cast<void>(kill(child.pid, SIGTERM));
  }
  const auto deadline = std::chrono::steady_clock::now() +
                        std::chrono::milliseconds(250);
  for (auto &child : children_) {
    if (child.pid <= 0)
      continue;
    int status = 0;
    while (!reap(child.pid, WNOHANG, status) &&
           std::chrono::steady_clock::now() < deadline) {
      std::this_thread::yield();
    }
    if (!reap(child.pid, WNOHANG, status)) {
      static_cast<void>(kill(child.pid, SIGKILL));
      static_cast<void>(reap(child.pid, 0, status));
    }
    child.pid = -1;
  }
  children_.clear();
}

} // namespace omarchy::plugin_runtime::worker
