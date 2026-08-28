#include <arpa/inet.h>
#include <fcntl.h>
#include <signal.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <unistd.h>

#include <array>
#include <cerrno>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <span>
#include <string_view>

namespace {

constexpr std::uint64_t kGeneration = 0x1020304050607080ULL;
constexpr std::size_t kHeaderSize = 40;

void put16(std::span<std::byte> output, std::size_t offset,
           std::uint16_t value) {
  output[offset] = static_cast<std::byte>(value >> 8U);
  output[offset + 1] = static_cast<std::byte>(value);
}

void put32(std::span<std::byte> output, std::size_t offset,
           std::uint32_t value) {
  put16(output, offset, static_cast<std::uint16_t>(value >> 16U));
  put16(output, offset + 2, static_cast<std::uint16_t>(value));
}

void put64(std::span<std::byte> output, std::size_t offset,
           std::uint64_t value) {
  put32(output, offset, static_cast<std::uint32_t>(value >> 32U));
  put32(output, offset + 4, static_cast<std::uint32_t>(value));
}

std::array<std::byte, kHeaderSize + 4>
hello(std::uint16_t role, std::uint64_t generation,
      std::uint32_t claimed_payload = 4) {
  std::array<std::byte, kHeaderSize + 4> bytes{};
  put32(bytes, 0, 0x4f4d504c);
  put16(bytes, 4, 1);
  put16(bytes, 6, kHeaderSize);
  put16(bytes, 8, role);
  put16(bytes, 10, 1);
  put16(bytes, 12, 1);
  put32(bytes, 16, claimed_payload);
  put64(bytes, 24, generation);
  put16(bytes, 40, 1);
  put16(bytes, 42, 1);
  return bytes;
}

bool send_attack(std::span<const std::byte> bytes, int passed_fd = -1) {
  iovec payload{.iov_base = const_cast<std::byte *>(bytes.data()),
                .iov_len = bytes.size()};
  std::array<std::byte, CMSG_SPACE(sizeof(int))> ancillary{};
  msghdr message{};
  message.msg_iov = &payload;
  message.msg_iovlen = 1;
  if (passed_fd >= 0) {
    message.msg_control = ancillary.data();
    message.msg_controllen = ancillary.size();
    cmsghdr *header = CMSG_FIRSTHDR(&message);
    header->cmsg_level = SOL_SOCKET;
    header->cmsg_type = SCM_RIGHTS;
    header->cmsg_len = CMSG_LEN(sizeof(int));
    std::memcpy(CMSG_DATA(header), &passed_fd, sizeof(passed_fd));
  }
  return sendmsg(3, &message, MSG_NOSIGNAL) ==
         static_cast<ssize_t>(bytes.size());
}

} // namespace

int main(int argc, char **argv) {
  if (argc != 2) {
    return 64;
  }
  const std::string_view attack(argv[1]);
  if (attack == "role-swap") {
    return send_attack(hello(2, kGeneration)) ? 0 : 65;
  }
  if (attack == "stale-generation") {
    return send_attack(hello(1, kGeneration + 1)) ? 0 : 66;
  }
  if (attack == "oversized") {
    return send_attack(hello(1, kGeneration, 4097)) ? 0 : 67;
  }
  if (attack == "descriptor-injection") {
    const int descriptor = open("/dev/null", O_RDONLY | O_CLOEXEC);
    if (descriptor < 0) {
      return 68;
    }
    const bool sent = send_attack(hello(1, kGeneration), descriptor);
    close(descriptor);
    return sent ? 0 : 69;
  }
  if (attack == "descendant") {
    const pid_t child = fork();
    if (child < 0) {
      return 70;
    }
    if (child == 0) {
      _exit(send_attack(hello(1, kGeneration)) ? 0 : 71);
    }
    int status = 0;
    return waitpid(child, &status, 0) == child && WIFEXITED(status) &&
                   WEXITSTATUS(status) == 0
               ? 0
               : 72;
  }
  if (attack == "crash") {
    raise(SIGABRT);
    return 73;
  }
  if (attack == "hang") {
    for (;;) {
      pause();
    }
  }
  return 74;
}
