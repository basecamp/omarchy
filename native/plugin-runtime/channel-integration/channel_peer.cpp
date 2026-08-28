#include "omarchy/plugin/wire/common.hpp"
#include "omarchy/plugin/wire/state.hpp"
#include "omarchy/plugin_runtime/broker/broker_schema.hpp"
#include "omarchy/plugin_runtime/surface/render_messages.hpp"

#include <fcntl.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <unistd.h>

#include <array>
#include <cerrno>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <fstream>
#include <span>
#include <string>
#include <string_view>
#include <vector>

namespace wire = omarchy::plugin::wire;
namespace broker = omarchy::plugin_runtime::broker;
namespace surface = omarchy::plugin_runtime::surface;

namespace {
[[noreturn]] void fail() { _exit(120); }

std::string mode() {
  if (const char *value = getenv("D1_MODE"); value != nullptr) {
    return value;
  }
  std::ifstream input("/plugin/d1-mode");
  std::string value;
  input >> value;
  return value;
}

void send_bytes(int descriptor, std::span<const std::byte> bytes,
                unsigned descriptor_count = 0) {
  iovec vector{.iov_base = const_cast<std::byte *>(bytes.data()),
               .iov_len = bytes.size()};
  alignas(cmsghdr) std::array<std::byte, CMSG_SPACE(24 * sizeof(int))>
      control{};
  msghdr message{};
  message.msg_iov = &vector;
  message.msg_iovlen = 1;
  std::array<int, 24> injected{};
  injected.fill(-1);
  if (descriptor_count > injected.size()) {
    fail();
  }
  if (descriptor_count != 0) {
    for (unsigned index = 0; index < descriptor_count; ++index) {
      injected[index] = open("/dev/null", O_RDONLY | O_CLOEXEC);
      if (injected[index] < 0) {
        fail();
      }
    }
    message.msg_control = control.data();
    message.msg_controllen = CMSG_SPACE(descriptor_count * sizeof(int));
    auto *header = CMSG_FIRSTHDR(&message);
    header->cmsg_level = SOL_SOCKET;
    header->cmsg_type = SCM_RIGHTS;
    header->cmsg_len = CMSG_LEN(descriptor_count * sizeof(int));
    __builtin_memcpy(CMSG_DATA(header), injected.data(),
                     descriptor_count * sizeof(int));
  }
  const ssize_t sent = sendmsg(descriptor, &message, MSG_NOSIGNAL);
  for (const int value : injected) {
    if (value >= 0) {
      close(value);
    }
  }
  if (sent != static_cast<ssize_t>(bytes.size())) {
    fail();
  }
}

std::vector<std::byte> receive_bytes(int descriptor) {
  std::vector<std::byte> bytes(128);
  const ssize_t count = recv(descriptor, bytes.data(), bytes.size(), 0);
  if (count <= 0) {
    fail();
  }
  bytes.resize(static_cast<std::size_t>(count));
  return bytes;
}

std::uint16_t version(wire::EndpointRole role) {
  if (role == wire::EndpointRole::broker) {
    return broker::kBrokerRoleVersion;
  }
  if (role == wire::EndpointRole::render) {
    return surface::kRenderRoleVersion;
  }
  return 1;
}

std::vector<std::byte> packet(const wire::EnvelopeHeader &header,
                              std::span<const std::byte> payload) {
  std::vector<std::byte> bytes(wire::kHeaderSize + payload.size());
  auto adjusted = header;
  adjusted.payload_length = static_cast<std::uint32_t>(payload.size());
  const auto result = wire::encode_packet(adjusted, payload, bytes);
  if (!result) {
    fail();
  }
  return bytes;
}

std::uint64_t negotiate(int descriptor, wire::EndpointRole role,
                        std::string_view current_mode) {
  const auto supported =
      current_mode == "bad-version" && role == wire::EndpointRole::control
          ? wire::VersionRange{2, 2}
          : wire::VersionRange{version(role), version(role)};
  wire::WorkerNegotiator negotiator(role, supported);
  const auto hello = negotiator.make_hello();
  if (!hello) {
    fail();
  }
  const auto bytes = packet(hello.header, hello.payload);
  if (current_mode == "descendant" && role == wire::EndpointRole::control) {
    const pid_t child = fork();
    if (child < 0) {
      fail();
    }
    if (child == 0) {
      send_bytes(descriptor, bytes);
      _exit(0);
    }
    int status = 0;
    waitpid(child, &status, 0);
    pause();
  }
  const bool inject =
      role == wire::EndpointRole::control &&
      (current_mode == "descriptor" || current_mode == "descriptor-flood");
  send_bytes(descriptor, bytes,
             inject && current_mode == "descriptor-flood" ? 24U
             : inject                                     ? 1U
                                                          : 0U);
  const auto reply = receive_bytes(descriptor);
  const auto decoded = wire::decode_packet(reply, role);
  if (!decoded ||
      negotiator.accept_reply(decoded.packet) != wire::FatalReason::none) {
    fail();
  }
  if (!negotiator.selected()) {
    _exit(0);
  }
  return negotiator.launch_generation();
}

void put16(std::span<std::byte> output, std::size_t offset,
           std::uint16_t value) {
  output[offset] = static_cast<std::byte>(value >> 8U);
  output[offset + 1] = static_cast<std::byte>(value);
}

void put64(std::span<std::byte> output, std::size_t offset,
           std::uint64_t value) {
  for (std::size_t index = 0; index < 8; ++index) {
    output[offset + index] =
        static_cast<std::byte>(value >> ((7U - index) * 8U));
  }
}

void send_broker_request(std::uint64_t generation, std::string_view current) {
  std::array<std::byte, 24> payload{};
  const auto type = static_cast<std::uint16_t>(
      broker::permissions::OperationId::storage_read);
  put16(payload, 0, type);
  put16(payload, 2, 16);
  put64(payload, 8, 4096);
  put64(payload, 16, 1024);
  wire::EnvelopeHeader header{
      .endpoint_role = wire::EndpointRole::broker,
      .message_type = type,
      .role_protocol_version =
          static_cast<std::uint16_t>(current == "bad-role-version" ? 2 : 1),
      .launch_generation = current == "stale" ? generation + 1 : generation,
      .correlation_id = 1};
  const auto bytes = packet(header, payload);
  send_bytes(4, bytes);
  std::byte ignored{};
  while (recv(4, &ignored, 1, 0) < 0 && errno == EINTR) {
  }
}
} // namespace

int main() {
  const std::string current = mode();
  if (current == "transport-max") {
    std::vector<std::byte> received(
        wire::kHeaderSize + wire::payload_cap(wire::EndpointRole::broker));
    const ssize_t count = recv(4, received.data(), received.size(), 0);
    if (count != static_cast<ssize_t>(received.size())) {
      fail();
    }
    const std::array<std::byte, 1> acknowledgement{std::byte{0x5a}};
    send_bytes(3, acknowledgement);
    pause();
  }
  if (current == "transport-saturation") {
    pause();
  }
  const auto control_generation =
      negotiate(3, wire::EndpointRole::control, current);
  if (current == "peer-loss") {
    return 0;
  }
  if (current == "pre-ready") {
    send_broker_request(control_generation, current);
    return 0;
  }
  if (current == "wrong-role") {
    static_cast<void>(negotiate(4, wire::EndpointRole::control, current));
    return 0;
  }
  const auto broker_generation =
      negotiate(4, wire::EndpointRole::broker, current);
  static_cast<void>(negotiate(5, wire::EndpointRole::render, current));
  if (current == "ready-loss") {
    return 0;
  }
  send_broker_request(broker_generation, current);
  return 0;
}
