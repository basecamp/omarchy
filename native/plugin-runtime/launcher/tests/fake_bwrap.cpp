#include <fcntl.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

#include <array>
#include <cerrno>
#include <charconv>
#include <cstdlib>
#include <cstring>
#include <string>
#include <string_view>

namespace {
[[noreturn]] void fail() { _exit(125); }

int integer(std::string_view value) {
  int output = -1;
  const auto result =
      std::from_chars(value.data(), value.data() + value.size(), output);
  if (result.ec != std::errc{} || result.ptr != value.data() + value.size() ||
      output < 0) {
    fail();
  }
  return output;
}
} // namespace

int main(int argc, char **argv) {
  if (argc < 1 || argv[0] == nullptr)
    fail();
  const std::string_view invocation(argv[0]);
  const auto separator = invocation.find_last_of('/');
  const auto mode = invocation.substr(
      separator == std::string_view::npos ? 0 : separator + 1);
  int status_fd = -1;
  int barrier_fd = -1;
  std::string worker;
  for (int index = 1; index < argc; ++index) {
    const std::string_view argument(argv[index]);
    if (argument == "--json-status-fd" && index + 1 < argc) {
      status_fd = integer(argv[++index]);
    } else if (argument == "--block-fd" && index + 1 < argc) {
      barrier_fd = integer(argv[++index]);
    } else if (argument == "--ro-bind" && index + 2 < argc &&
               std::string_view(argv[index + 2]) == "/runtime/worker") {
      worker = argv[index + 1];
      index += 2;
    }
  }
  if (status_fd < 0 || barrier_fd < 0 || worker.empty()) {
    fail();
  }

  pid_t worker_pid = getpid();
  if (mode == "omarchy-plugin-fake-bwrap") {
    worker_pid = fork();
    if (worker_pid < 0) {
      fail();
    }
  }

  if (worker_pid == 0) {
    std::byte byte{};
    ssize_t count = -1;
    do {
      count = read(barrier_fd, &byte, sizeof(byte));
    } while (count < 0 && errno == EINTR);
    if (count != 0) {
      fail();
    }
    if (syscall(SYS_close_range, 6U, ~0U, 0U) < 0) {
      fail();
    }
    std::array<char *, 2> arguments{worker.data(), nullptr};
    std::array<char *, 3> environment{const_cast<char *>("PATH=/usr/bin"),
                                      const_cast<char *>("PWD=/"), nullptr};
    execve(worker.c_str(), arguments.data(), environment.data());
    fail();
  }

  std::string status;
  if (mode == "omarchy-plugin-fake-bwrap") {
    status = "{\"future\":{\"ignored\":true},\"child-pid\":" +
             std::to_string(worker_pid) + "}\n";
  } else if (mode == "omarchy-plugin-duplicate-status-bwrap") {
    status = "{\"child-pid\":" + std::to_string(getpid()) +
             ",\"child\\u002dpid\":" + std::to_string(getpid()) + "}\n";
  } else if (mode == "omarchy-plugin-string-status-bwrap") {
    status = "{\"child-pid\":\"" + std::to_string(getpid()) + "\"}\n";
  } else if (mode == "omarchy-plugin-exited-status-bwrap") {
    status =
        "{\"child-pid\":" + std::to_string(getpid()) + ",\"exit-code\":0}\n";
  } else {
    fail();
  }
  if (write(status_fd, status.data(), status.size()) !=
      static_cast<ssize_t>(status.size())) {
    fail();
  }

  if (mode == "omarchy-plugin-fake-bwrap") {
    if (syscall(SYS_close_range, 3U, ~0U, 0U) < 0) {
      fail();
    }
    int status_value = 0;
    pid_t waited = -1;
    do {
      waited = waitpid(worker_pid, &status_value, 0);
    } while (waited < 0 && errno == EINTR);
    if (waited != worker_pid) {
      fail();
    }
    if (WIFEXITED(status_value)) {
      _exit(WEXITSTATUS(status_value));
    }
    if (WIFSIGNALED(status_value)) {
      _exit(128 + WTERMSIG(status_value));
    }
    fail();
  }

  std::byte byte{};
  ssize_t count = -1;
  do {
    count = read(barrier_fd, &byte, sizeof(byte));
  } while (count < 0 && errno == EINTR);
  if (count != 0) {
    fail();
  }
  if (syscall(SYS_close_range, 6U, ~0U, 0U) < 0) {
    fail();
  }
  std::array<char *, 2> arguments{worker.data(), nullptr};
  std::array<char *, 3> environment{const_cast<char *>("PATH=/usr/bin"),
                                    const_cast<char *>("PWD=/"), nullptr};
  execve(worker.c_str(), arguments.data(), environment.data());
  fail();
}
