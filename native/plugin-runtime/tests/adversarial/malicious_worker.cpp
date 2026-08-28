#include <arpa/inet.h>
#include <dirent.h>
#include <fcntl.h>
#include <signal.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <unistd.h>

#include <array>
#include <algorithm>
#include <cerrno>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <cstdlib>
#include <fstream>
#include <set>
#include <span>
#include <string>
#include <string_view>
#include <vector>

extern char **environ;

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

std::array<std::byte, kHeaderSize>
request(std::uint16_t role, std::uint64_t generation,
        std::uint32_t claimed_payload = 0) {
  std::array<std::byte, kHeaderSize> bytes{};
  put32(bytes, 0, 0x4f4d504c);
  put16(bytes, 4, 1);
  put16(bytes, 6, kHeaderSize);
  put16(bytes, 8, role);
  put16(bytes, 10, 0x1100);
  put16(bytes, 12, 1);
  put32(bytes, 16, claimed_payload);
  put64(bytes, 24, generation);
  put64(bytes, 32, 1);
  return bytes;
}

bool send_attack(std::span<const std::byte> bytes, int passed_fd = -1) {
  iovec payload{.iov_base = const_cast<std::byte *>(bytes.data()),
                .iov_len = bytes.size()};
  alignas(cmsghdr) std::array<std::byte, CMSG_SPACE(sizeof(int))> ancillary{};
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

struct SandboxProbe {
  std::uint32_t magic = 0x53425831;
  std::uint32_t descriptor_mask = 0;
  std::uint32_t exact_descriptors = 0;
  std::uint32_t exact_environment = 0;
  std::uint32_t host_home_absent = 0;
  std::uint32_t bus_socket_absent = 0;
  std::uint32_t wayland_socket_absent = 0;
  std::uint32_t network_denied = 0;
  std::uint32_t descendant_denied = 0;
  std::uint32_t revision_write_denied = 0;
};

int sandbox_probe() {
  SandboxProbe probe;
  DIR *directory = opendir("/proc/self/fd");
  if (directory == nullptr) {
    return 80;
  }
  const int enumeration_fd = dirfd(directory);
  std::set<int> descriptors;
  while (const dirent *entry = readdir(directory)) {
    char *end = nullptr;
    const long value = std::strtol(entry->d_name, &end, 10);
    if (*entry->d_name != '\0' && end != nullptr && *end == '\0' &&
        value != enumeration_fd && value >= 0) {
      descriptors.insert(static_cast<int>(value));
      if (value < 32) {
        probe.descriptor_mask |= 1U << static_cast<unsigned>(value);
      }
    }
  }
  closedir(directory);
  probe.exact_descriptors = descriptors == std::set<int>({0, 1, 2, 3, 4, 5});

  std::vector<std::string> expected = {
      "HOME=/home/plugin",       "LANG=C.UTF-8",
      "LC_ALL=C.UTF-8",         "PATH=/runtime",
      "PWD=/plugin",            "QT_QPA_PLATFORM=offscreen",
      "QSG_RHI_BACKEND=software", "XDG_CACHE_HOME=/tmp/cache",
      "XDG_CONFIG_HOME=/state/config", "XDG_DATA_HOME=/state/data",
      "XDG_RUNTIME_DIR=/run/plugin",
  };
  std::vector<std::string> actual;
  for (char **entry = environ; *entry != nullptr; ++entry) {
    actual.emplace_back(*entry);
  }
  std::sort(expected.begin(), expected.end());
  std::sort(actual.begin(), actual.end());
  probe.exact_environment = actual == expected;

  std::ifstream fixture("/plugin/fixture");
  std::string host_home;
  std::string bus_socket;
  std::string wayland_socket;
  std::getline(fixture, host_home);
  std::getline(fixture, bus_socket);
  std::getline(fixture, wayland_socket);
  errno = 0;
  probe.host_home_absent = !host_home.empty() &&
                           access(host_home.c_str(), F_OK) < 0 &&
                           errno == ENOENT;
  errno = 0;
  probe.bus_socket_absent = !bus_socket.empty() &&
                            access(bus_socket.c_str(), F_OK) < 0 &&
                            errno == ENOENT;
  errno = 0;
  probe.wayland_socket_absent = !wayland_socket.empty() &&
                                access(wayland_socket.c_str(), F_OK) < 0 &&
                                errno == ENOENT;

  errno = 0;
  const int network = socket(AF_INET, SOCK_STREAM | SOCK_CLOEXEC, 0);
  probe.network_denied = network < 0 && errno == EPERM;
  if (network >= 0) {
    close(network);
  }
  errno = 0;
  const pid_t descendant = fork();
  probe.descendant_denied = descendant < 0 && errno == EPERM;
  if (descendant == 0) {
    _exit(81);
  }
  if (descendant > 0) {
    kill(descendant, SIGKILL);
    waitpid(descendant, nullptr, 0);
  }
  errno = 0;
  const int revision_write = open("/plugin/fixture", O_WRONLY | O_CLOEXEC);
  probe.revision_write_denied =
      revision_write < 0 && (errno == EROFS || errno == EACCES);
  if (revision_write >= 0) {
    close(revision_write);
  }
  if (send(3, &probe, sizeof(probe), MSG_NOSIGNAL) != sizeof(probe)) {
    return 82;
  }
  std::byte acknowledgement{};
  return recv(3, &acknowledgement, sizeof(acknowledgement), 0) == 1 ? 0 : 83;
}

} // namespace

int main(int argc, char **argv) {
  if (argc == 1) {
    return sandbox_probe();
  }
  if (argc != 2) {
    return 64;
  }
  const std::string_view attack(argv[1]);
  if (attack == "role-swap") {
    return send_attack(request(2, kGeneration)) ? 0 : 65;
  }
  if (attack == "stale-generation") {
    return send_attack(request(1, kGeneration + 1)) ? 0 : 66;
  }
  if (attack == "oversized") {
    return send_attack(request(1, kGeneration, 4097)) ? 0 : 67;
  }
  if (attack == "descriptor-injection") {
    const int descriptor = open("/dev/null", O_RDONLY | O_CLOEXEC);
    if (descriptor < 0) {
      return 68;
    }
    const bool sent = send_attack(request(1, kGeneration), descriptor);
    close(descriptor);
    return sent ? 0 : 69;
  }
  if (attack == "descriptor-flood") {
    std::array<int, 8> descriptors{};
    for (int &descriptor : descriptors) {
      descriptor = open("/dev/null", O_RDONLY | O_CLOEXEC);
      if (descriptor < 0) {
        return 75;
      }
    }
    iovec payload{.iov_base = nullptr, .iov_len = 0};
    const auto bytes = request(1, kGeneration);
    payload.iov_base = const_cast<std::byte *>(bytes.data());
    payload.iov_len = bytes.size();
    alignas(cmsghdr)
        std::array<std::byte, CMSG_SPACE(sizeof(int) * 8)> ancillary{};
    msghdr message{};
    message.msg_iov = &payload;
    message.msg_iovlen = 1;
    message.msg_control = ancillary.data();
    message.msg_controllen = ancillary.size();
    cmsghdr *header = CMSG_FIRSTHDR(&message);
    header->cmsg_level = SOL_SOCKET;
    header->cmsg_type = SCM_RIGHTS;
    header->cmsg_len = CMSG_LEN(sizeof(int) * descriptors.size());
    std::memcpy(CMSG_DATA(header), descriptors.data(), sizeof(descriptors));
    const bool sent = sendmsg(3, &message, MSG_NOSIGNAL) ==
                      static_cast<ssize_t>(bytes.size());
    for (const int descriptor : descriptors) {
      close(descriptor);
    }
    return sent ? 0 : 76;
  }
  if (attack == "descendant") {
    const pid_t child = fork();
    if (child < 0) {
      return 70;
    }
    if (child == 0) {
      _exit(send_attack(request(1, kGeneration)) ? 0 : 71);
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
  if (attack == "sandbox-denials") {
    return sandbox_probe();
  }
  return 74;
}
