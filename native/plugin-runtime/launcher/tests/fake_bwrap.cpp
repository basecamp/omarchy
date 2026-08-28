#include <fcntl.h>
#include <sys/syscall.h>
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

#if FAKE_DUPLICATE_STATUS
  const std::string status =
      "{\"child-pid\":" + std::to_string(getpid()) +
      ",\"child\\u002dpid\":" + std::to_string(getpid()) + "}\n";
#elif FAKE_STRING_STATUS
  const std::string status =
      "{\"child-pid\":\"" + std::to_string(getpid()) + "\"}\n";
#elif FAKE_EXITED_STATUS
  const std::string status =
      "{\"child-pid\":" + std::to_string(getpid()) + ",\"exit-code\":0}\n";
#else
  const std::string status = "{\"future\":{\"ignored\":true},\"child-pid\":" +
                             std::to_string(getpid()) + "}\n";
#endif
  if (write(status_fd, status.data(), status.size()) !=
      static_cast<ssize_t>(status.size())) {
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
