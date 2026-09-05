#include <arpa/inet.h>
#include <fcntl.h>
#include <sys/prctl.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <unistd.h>

#include <array>
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <cstdlib>
#include <fstream>
#include <span>
#include <string>
#include <thread>
#include <vector>

namespace {
constexpr std::uint32_t kMagic = 0x4f505256;
constexpr std::size_t kHeader = 20;

std::uint32_t u32(const std::byte *bytes) {
  std::uint32_t value = 0;
  for (int index = 0; index < 4; ++index)
    value = (value << 8) | std::to_integer<unsigned char>(bytes[index]);
  return value;
}
std::uint64_t u64(const std::byte *bytes) {
  std::uint64_t value = 0;
  for (int index = 0; index < 8; ++index)
    value = (value << 8) | std::to_integer<unsigned char>(bytes[index]);
  return value;
}
void put32(std::vector<std::byte> &bytes, std::uint32_t value) {
  for (int shift = 24; shift >= 0; shift -= 8)
    bytes.push_back(static_cast<std::byte>(value >> shift));
}
void put64(std::vector<std::byte> &bytes, std::uint64_t value) {
  for (int shift = 56; shift >= 0; shift -= 8)
    bytes.push_back(static_cast<std::byte>(value >> shift));
}
std::string argument(int argc, char **argv) {
  return argc >= 2 ? argv[1] : "echo";
}
bool isolated_descriptor_table(int inherited_fd) {
  struct stat null_metadata {};
  if (::stat("/dev/null", &null_metadata) < 0)
    return false;
  for (int fd = STDIN_FILENO; fd <= STDERR_FILENO; ++fd) {
    struct stat metadata {};
    if (::fstat(fd, &metadata) < 0 || !S_ISCHR(metadata.st_mode) ||
        metadata.st_rdev != null_metadata.st_rdev)
      return false;
  }
  struct stat channel {};
  errno = 0;
  return ::fstat(3, &channel) == 0 && S_ISSOCK(channel.st_mode) &&
         ::fcntl(inherited_fd, F_GETFD) < 0 && errno == EBADF &&
         ::prctl(PR_GET_NO_NEW_PRIVS, 0, 0, 0, 0) == 1;
}
} // namespace

int main(int argc, char **argv) {
  const auto mode = argument(argc, argv);
  pid_t descendant = -1;
  if (mode == "marker" && argc == 3) {
    std::ofstream marker(argv[2]);
    marker << ::getpid() << '\n';
  }
  std::array<std::byte, 1024 * 1024 + 1024> request{};
  while (true) {
    iovec request_part{.iov_base = request.data(), .iov_len = request.size()};
    msghdr request_message{};
    request_message.msg_iov = &request_part;
    request_message.msg_iovlen = 1;
    const auto count = ::recvmsg(3, &request_message, 0);
    if (count <= 0)
      return 0;
    if (static_cast<std::size_t>(count) < kHeader || u32(request.data()) != kMagic)
      return 2;
    if (mode == "crash")
      return 3;
    if (mode == "late")
      std::this_thread::sleep_for(std::chrono::milliseconds(250));
    const auto correlation = u64(request.data() + 8);
    std::string payload;
    if (mode == "pid")
      payload = std::to_string(::getpid());
    else if (mode == "descendant") {
      if (descendant <= 0) {
        descendant = ::fork();
        if (descendant < 0)
          return 5;
        if (descendant == 0) {
          ::close(3);
          while (true)
            ::pause();
        }
      }
      payload = std::to_string(::getpid()) + "|" +
                std::to_string(descendant);
    }
    else if (mode == "environment")
      payload = std::string(::getenv("PATH") ? ::getenv("PATH") : "") + "|" +
                (::getenv("HOME") ? ::getenv("HOME") : "");
    else if (mode == "inherited-environment")
      payload =
          std::string(::getenv("HYPRLAND_INSTANCE_SIGNATURE")
                          ? ::getenv("HYPRLAND_INSTANCE_SIGNATURE")
                          : "") +
          "|" +
          (::getenv("XDG_RUNTIME_DIR") ? ::getenv("XDG_RUNTIME_DIR") : "");
    else if (mode == "isolation" && argc == 3)
      payload = isolated_descriptor_table(std::atoi(argv[2])) ? "isolated"
                                                              : "leaked";
    else
      payload = "ok";
    std::vector<std::byte> response;
    put32(response, mode == "malformed" ? 0U : kMagic);
    response.push_back(std::byte{1});
    response.push_back(std::byte{2});
    response.push_back(std::byte{0});
    response.push_back(std::byte{0});
    put64(response, mode == "wrong-correlation" ? correlation + 1 : correlation);
    put32(response, static_cast<std::uint32_t>(payload.size() + 1));
    response.push_back(std::byte{0});
    const auto raw = std::as_bytes(std::span(payload.data(), payload.size()));
    response.insert(response.end(), raw.begin(), raw.end());
    if (mode == "truncated")
      response.resize(10);
    if (mode == "oversized")
      response.resize(1024 * 1024, std::byte{0});
    iovec response_part{.iov_base = response.data(), .iov_len = response.size()};
    msghdr response_message{};
    response_message.msg_iov = &response_part;
    response_message.msg_iovlen = 1;
    if (::sendmsg(3, &response_message, MSG_NOSIGNAL) !=
        static_cast<ssize_t>(response.size()))
      return 4;
  }
}
