#include <arpa/inet.h>
#include <fcntl.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

#include <array>
#include <cerrno>
#include <cstdint>
#include <cstring>
#include <filesystem>
#include <iostream>
#include <optional>
#include <span>
#include <stdexcept>
#include <string>
#include <string_view>
#include <vector>

namespace {

constexpr std::uint32_t kMagic = 0x4f4d504c; // "OMPL"
constexpr std::uint16_t kProtocolVersion = 1;
constexpr std::size_t kHeaderSize = 16;
constexpr std::size_t kMaxPayloadSize = 4096;
constexpr std::size_t kMaxReceivedFds = 253;
constexpr std::size_t kControlBufferSize =
    CMSG_SPACE(sizeof(ucred)) + CMSG_SPACE(sizeof(int) * kMaxReceivedFds);
constexpr int kWorkerFd = 3;

enum class MessageType : std::uint16_t {
  hello = 1,
  welcome = 2,
  request = 3,
  result = 4,
};

struct Frame {
  std::uint16_t version;
  MessageType type;
  std::string payload;
};

struct ReceivedFrame {
  Frame frame;
  ucred credentials;
};

struct AncillaryResult {
  std::optional<ucred> credentials;
  bool duplicate_credentials = false;
  bool unexpected_data = false;
  bool descriptor_close_failed = false;
};

void put_u16(std::span<std::byte> output, std::size_t offset,
             std::uint16_t value) {
  value = htons(value);
  std::memcpy(output.data() + offset, &value, sizeof(value));
}

void put_u32(std::span<std::byte> output, std::size_t offset,
             std::uint32_t value) {
  value = htonl(value);
  std::memcpy(output.data() + offset, &value, sizeof(value));
}

std::uint16_t get_u16(std::span<const std::byte> input, std::size_t offset) {
  std::uint16_t value;
  std::memcpy(&value, input.data() + offset, sizeof(value));
  return ntohs(value);
}

std::uint32_t get_u32(std::span<const std::byte> input, std::size_t offset) {
  std::uint32_t value;
  std::memcpy(&value, input.data() + offset, sizeof(value));
  return ntohl(value);
}

std::vector<std::byte> encode(const Frame &frame) {
  if (frame.payload.size() > kMaxPayloadSize) {
    throw std::runtime_error("payload exceeds protocol limit");
  }

  std::vector<std::byte> output(kHeaderSize + frame.payload.size());
  put_u32(output, 0, kMagic);
  put_u16(output, 4, frame.version);
  put_u16(output, 6, static_cast<std::uint16_t>(frame.type));
  put_u32(output, 8, static_cast<std::uint32_t>(frame.payload.size()));
  put_u32(output, 12, 0); // Reserved flags must be zero in version 1.
  std::memcpy(output.data() + kHeaderSize, frame.payload.data(),
              frame.payload.size());
  return output;
}

Frame decode(std::span<const std::byte> packet) {
  if (packet.size() < kHeaderSize) {
    throw std::runtime_error("truncated frame header");
  }
  if (get_u32(packet, 0) != kMagic) {
    throw std::runtime_error("invalid frame magic");
  }

  const auto payload_size = get_u32(packet, 8);
  if (payload_size > kMaxPayloadSize) {
    throw std::runtime_error("declared payload exceeds protocol limit");
  }
  if (packet.size() != kHeaderSize + payload_size) {
    throw std::runtime_error("frame length does not match packet length");
  }
  if (get_u32(packet, 12) != 0) {
    throw std::runtime_error("unsupported frame flags");
  }

  const auto type_value = get_u16(packet, 6);
  if (type_value < static_cast<std::uint16_t>(MessageType::hello) ||
      type_value > static_cast<std::uint16_t>(MessageType::result)) {
    throw std::runtime_error("unknown message type");
  }

  return Frame{
      .version = get_u16(packet, 4),
      .type = static_cast<MessageType>(type_value),
      .payload = std::string(
          reinterpret_cast<const char *>(packet.data() + kHeaderSize),
          payload_size),
  };
}

void send_frame(int fd, const Frame &frame) {
  const auto packet = encode(frame);
  const auto sent = send(fd, packet.data(), packet.size(), MSG_NOSIGNAL);
  if (sent < 0 || static_cast<std::size_t>(sent) != packet.size()) {
    throw std::runtime_error(std::string("send failed: ") +
                             std::strerror(errno));
  }
}

void send_frame_with_fds(int fd, const Frame &frame,
                         std::span<const int> descriptors) {
  const auto packet = encode(frame);
  std::vector<std::byte> control(CMSG_SPACE(sizeof(int) * descriptors.size()));
  iovec iov{.iov_base = const_cast<std::byte *>(packet.data()),
            .iov_len = packet.size()};
  msghdr message{};
  message.msg_iov = &iov;
  message.msg_iovlen = 1;
  message.msg_control = control.data();
  message.msg_controllen = control.size();

  auto *item = CMSG_FIRSTHDR(&message);
  item->cmsg_level = SOL_SOCKET;
  item->cmsg_type = SCM_RIGHTS;
  item->cmsg_len = CMSG_LEN(sizeof(int) * descriptors.size());
  std::memcpy(CMSG_DATA(item), descriptors.data(),
              sizeof(int) * descriptors.size());

  const auto sent = sendmsg(fd, &message, MSG_NOSIGNAL);
  if (sent < 0 || static_cast<std::size_t>(sent) != packet.size()) {
    throw std::runtime_error(std::string("sendmsg failed: ") +
                             std::strerror(errno));
  }
}

AncillaryResult inspect_and_close_ancillary(msghdr &message) {
  AncillaryResult result;

  for (auto *item = CMSG_FIRSTHDR(&message); item != nullptr;
       item = CMSG_NXTHDR(&message, item)) {
    if (item->cmsg_level == SOL_SOCKET && item->cmsg_type == SCM_RIGHTS) {
      result.unexpected_data = true;
      if (item->cmsg_len < CMSG_LEN(0)) {
        continue;
      }

      const auto bytes = item->cmsg_len - CMSG_LEN(0);
      if (bytes % sizeof(int) != 0) {
        result.unexpected_data = true;
      }
      const auto count = bytes / sizeof(int);
      const auto *descriptors = reinterpret_cast<const int *>(CMSG_DATA(item));
      for (std::size_t index = 0; index < count; ++index) {
        if (close(descriptors[index]) < 0) {
          result.descriptor_close_failed = true;
        }
      }
    } else if (item->cmsg_level == SOL_SOCKET &&
               item->cmsg_type == SCM_CREDENTIALS &&
               item->cmsg_len == CMSG_LEN(sizeof(ucred))) {
      if (result.credentials.has_value()) {
        result.duplicate_credentials = true;
        continue;
      }
      ucred value;
      std::memcpy(&value, CMSG_DATA(item), sizeof(value));
      result.credentials = value;
    } else {
      result.unexpected_data = true;
    }
  }

  return result;
}

ReceivedFrame receive_frame(int fd,
                            std::size_t control_capacity = kControlBufferSize) {
  std::array<std::byte, kHeaderSize + kMaxPayloadSize> packet{};
  std::array<std::byte, kControlBufferSize> control{};
  if (control_capacity > control.size()) {
    throw std::runtime_error("invalid control buffer size");
  }
  iovec iov{.iov_base = packet.data(), .iov_len = packet.size()};
  msghdr message{};
  message.msg_iov = &iov;
  message.msg_iovlen = 1;
  message.msg_control = control.data();
  message.msg_controllen = control_capacity;

  const auto received = recvmsg(fd, &message, MSG_TRUNC | MSG_CMSG_CLOEXEC);
  if (received < 0) {
    throw std::runtime_error(std::string("recvmsg failed: ") +
                             std::strerror(errno));
  }

  // recvmsg may have installed SCM_RIGHTS descriptors in this process even
  // when it also reports MSG_TRUNC or MSG_CTRUNC. Inspect the complete control
  // prefix and close every delivered descriptor before taking any error path.
  const auto ancillary = inspect_and_close_ancillary(message);

  if ((message.msg_flags & MSG_TRUNC) != 0 ||
      static_cast<std::size_t>(received) > packet.size()) {
    throw std::runtime_error("packet exceeds protocol limit");
  }
  if ((message.msg_flags & MSG_CTRUNC) != 0) {
    throw std::runtime_error("ancillary data was truncated");
  }
  if (ancillary.descriptor_close_failed) {
    throw std::runtime_error("failed to close received descriptor");
  }
  if (ancillary.duplicate_credentials) {
    throw std::runtime_error("duplicate kernel credentials");
  }
  if (ancillary.unexpected_data) {
    throw std::runtime_error("unexpected ancillary data");
  }
  if (!ancillary.credentials.has_value()) {
    throw std::runtime_error("kernel credentials missing from packet");
  }

  return ReceivedFrame{
      .frame =
          decode(std::span(packet.data(), static_cast<std::size_t>(received))),
      .credentials = *ancillary.credentials,
  };
}

void require(bool condition, std::string_view message) {
  if (!condition) {
    throw std::runtime_error(std::string(message));
  }
}

int worker_main(int fd, std::string_view claimed_plugin_id) {
  send_frame(fd, Frame{.version = kProtocolVersion,
                       .type = MessageType::hello,
                       .payload = "min=1;max=1"});
  const auto welcome = receive_frame(fd);
  require(welcome.frame.version == kProtocolVersion, "bad selected version");
  require(welcome.frame.type == MessageType::welcome, "expected welcome");

  send_frame(fd,
             Frame{.version = kProtocolVersion,
                   .type = MessageType::request,
                   .payload = "plugin_id=" + std::string(claimed_plugin_id) +
                              ";operation=storage.read"});
  const auto result = receive_frame(fd);
  require(result.frame.type == MessageType::result, "expected result");
  std::cout << result.frame.payload << '\n';
  return 0;
}

std::string executable_path() {
  std::array<char, 4096> path{};
  const auto size = readlink("/proc/self/exe", path.data(), path.size() - 1);
  if (size < 0) {
    throw std::runtime_error("cannot resolve executable path");
  }
  return std::string(path.data(), static_cast<std::size_t>(size));
}

int broker_demo(std::string_view bound_plugin_id,
                std::string_view claimed_plugin_id) {
  int sockets[2];
  if (socketpair(AF_UNIX, SOCK_SEQPACKET | SOCK_CLOEXEC, 0, sockets) < 0) {
    throw std::runtime_error("socketpair failed");
  }
  int enabled = 1;
  if (setsockopt(sockets[0], SOL_SOCKET, SO_PASSCRED, &enabled,
                 sizeof(enabled)) < 0) {
    throw std::runtime_error(std::string("broker SO_PASSCRED failed: ") +
                             std::strerror(errno));
  }
  if (setsockopt(sockets[1], SOL_SOCKET, SO_PASSCRED, &enabled,
                 sizeof(enabled)) < 0) {
    throw std::runtime_error(std::string("worker SO_PASSCRED failed: ") +
                             std::strerror(errno));
  }

  const pid_t child = fork();
  if (child < 0) {
    throw std::runtime_error("fork failed");
  }
  if (child == 0) {
    close(sockets[0]);
    if (sockets[1] != kWorkerFd && dup2(sockets[1], kWorkerFd) < 0) {
      _exit(125);
    }
    if (sockets[1] != kWorkerFd) {
      close(sockets[1]);
    }
    const int flags = fcntl(kWorkerFd, F_GETFD);
    if (flags < 0 || fcntl(kWorkerFd, F_SETFD, flags & ~FD_CLOEXEC) < 0) {
      _exit(125);
    }
    const auto executable = executable_path();
    execl(executable.c_str(), executable.c_str(), "--worker", "3",
          std::string(claimed_plugin_id).c_str(), nullptr);
    _exit(126);
  }

  close(sockets[1]);
  const auto hello = receive_frame(sockets[0]);
  require(hello.credentials.pid == child, "HELLO came from unexpected process");
  require(hello.credentials.uid == getuid(), "HELLO came from unexpected uid");
  require(hello.frame.type == MessageType::hello, "expected HELLO");
  require(hello.frame.version == kProtocolVersion,
          "no common protocol version");
  require(hello.frame.payload == "min=1;max=1", "unsupported version offer");

  send_frame(sockets[0], Frame{.version = kProtocolVersion,
                               .type = MessageType::welcome,
                               .payload = "selected=1"});
  const auto request = receive_frame(sockets[0]);
  require(request.credentials.pid == child,
          "REQUEST came from unexpected process");
  require(request.credentials.uid == getuid(),
          "REQUEST came from unexpected uid");
  require(request.frame.version == kProtocolVersion,
          "version changed midstream");
  require(request.frame.type == MessageType::request, "expected REQUEST");

  // The payload is intentionally untrusted. Authorization uses the identity
  // bound to this endpoint at launch, never a plugin_id supplied in a frame.
  const auto result = "authorized_as=" + std::string(bound_plugin_id) +
                      ";untrusted_payload=" + request.frame.payload;
  send_frame(sockets[0], Frame{.version = kProtocolVersion,
                               .type = MessageType::result,
                               .payload = result});
  close(sockets[0]);

  int status;
  if (waitpid(child, &status, 0) < 0) {
    throw std::runtime_error("waitpid failed");
  }
  require(WIFEXITED(status) && WEXITSTATUS(status) == 0,
          "worker failed during exchange");
  return 0;
}

std::size_t open_descriptor_count() {
  std::size_t count = 0;
  for ([[maybe_unused]] const auto &entry :
       std::filesystem::directory_iterator("/proc/self/fd")) {
    ++count;
  }
  return count;
}

void descriptor_injection_test(bool force_truncation) {
  constexpr int injection_count = 128;
  constexpr std::size_t injected_descriptor_count = 8;

  int sockets[2];
  if (socketpair(AF_UNIX, SOCK_SEQPACKET | SOCK_CLOEXEC, 0, sockets) < 0) {
    throw std::runtime_error("injection socketpair failed");
  }
  int enabled = 1;
  if (setsockopt(sockets[0], SOL_SOCKET, SO_PASSCRED, &enabled,
                 sizeof(enabled)) < 0) {
    throw std::runtime_error("injection SO_PASSCRED failed");
  }

  const pid_t child = fork();
  if (child < 0) {
    throw std::runtime_error("injection fork failed");
  }
  if (child == 0) {
    close(sockets[0]);
    const int descriptor = open("/dev/null", O_RDONLY | O_CLOEXEC);
    if (descriptor < 0) {
      _exit(125);
    }
    const std::array<int, injected_descriptor_count> descriptors = {
        descriptor, descriptor, descriptor, descriptor,
        descriptor, descriptor, descriptor, descriptor};
    const std::span<const int> sent_descriptors =
        force_truncation ? std::span(descriptors)
                         : std::span(descriptors).first(1);
    try {
      for (int iteration = 0; iteration < injection_count; ++iteration) {
        send_frame_with_fds(sockets[1],
                            Frame{.version = kProtocolVersion,
                                  .type = MessageType::request,
                                  .payload = "operation=descriptor.inject"},
                            sent_descriptors);
      }
    } catch (const std::exception &) {
      _exit(126);
    }
    close(descriptor);
    close(sockets[1]);
    _exit(0);
  }

  close(sockets[1]);
  const auto descriptors_before = open_descriptor_count();
  const auto control_capacity =
      force_truncation ? CMSG_SPACE(sizeof(ucred)) + CMSG_SPACE(sizeof(int))
                       : kControlBufferSize;

  for (int iteration = 0; iteration < injection_count; ++iteration) {
    bool rejected = false;
    try {
      (void)receive_frame(sockets[0], control_capacity);
    } catch (const std::runtime_error &error) {
      const std::string_view message(error.what());
      rejected = force_truncation ? message == "ancillary data was truncated"
                                  : message == "unexpected ancillary data";
    }
    require(rejected, "descriptor injection was not rejected as expected");
  }

  const auto descriptors_after = open_descriptor_count();
  require(descriptors_after == descriptors_before,
          "descriptor injection increased broker fd count");
  close(sockets[0]);

  int status;
  if (waitpid(child, &status, 0) < 0) {
    throw std::runtime_error("injection waitpid failed");
  }
  require(WIFEXITED(status) && WEXITSTATUS(status) == 0,
          "descriptor injector failed");
}

int self_test() {
  const auto original = Frame{.version = 1,
                              .type = MessageType::request,
                              .payload = "operation=clock.read"};
  const auto decoded = decode(encode(original));
  require(decoded.version == original.version, "version round trip failed");
  require(decoded.type == original.type, "type round trip failed");
  require(decoded.payload == original.payload, "payload round trip failed");

  bool oversize_rejected = false;
  try {
    (void)encode(Frame{.version = 1,
                       .type = MessageType::request,
                       .payload = std::string(kMaxPayloadSize + 1, 'x')});
  } catch (const std::runtime_error &) {
    oversize_rejected = true;
  }
  require(oversize_rejected, "oversize payload was accepted");

  descriptor_injection_test(false);
  descriptor_injection_test(true);
  return broker_demo("trusted.clock", "forged.admin");
}

} // namespace

int main(int argc, char **argv) {
  try {
    if (argc == 2 && std::string_view(argv[1]) == "--self-test") {
      return self_test();
    }
    if (argc == 4 && std::string_view(argv[1]) == "--worker") {
      return worker_main(std::stoi(argv[2]), argv[3]);
    }
    if (argc == 3) {
      return broker_demo(argv[1], argv[2]);
    }
    std::cerr << "usage: " << argv[0]
              << " BOUND_PLUGIN_ID CLAIMED_PLUGIN_ID\n"
                 "       "
              << argv[0] << " --self-test\n";
    return 2;
  } catch (const std::exception &error) {
    std::cerr << "plugin-channel-spike: " << error.what() << '\n';
    return 1;
  }
}
