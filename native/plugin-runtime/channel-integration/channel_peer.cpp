#include "omarchy/plugin/wire/common.hpp"
#include "omarchy/plugin/wire/control.hpp"
#include "omarchy/plugin/wire/state.hpp"
#include "omarchy/plugin_runtime/broker/broker_schema.hpp"
#include "omarchy/plugin_runtime/surface/render_messages.hpp"

#include <fcntl.h>
#include <signal.h>
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
  std::vector<std::byte> bytes(wire::header_size(header.envelope_version) +
                               payload.size());
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
  wire::WorkerNegotiator negotiator(role, supported, wire::kEnvelopeVersionV2);
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

void send_broker_request(std::uint64_t generation, std::string_view current,
                         wire::SessionSequence &sequence) {
  std::array<std::byte, 24> payload{};
  const auto type = static_cast<std::uint16_t>(
      broker::permissions::OperationId::storage_read);
  put16(payload, 0, type);
  put16(payload, 2, 16);
  put64(payload, 8, 4096);
  put64(payload, 16, 1024);
  wire::EnvelopeHeader header{
      .envelope_version = wire::kEnvelopeVersionV2,
      .header_size = wire::kHeaderSizeV2,
      .endpoint_role = wire::EndpointRole::broker,
      .message_type = type,
      .role_protocol_version =
          static_cast<std::uint16_t>(current == "bad-role-version" ? 2 : 1),
      .launch_generation = current == "stale" ? generation + 1 : generation,
      .correlation_id = 1};
  const auto outbound = sequence.take_outbound(wire::EndpointRole::broker);
  if (!outbound)
    fail();
  header.lane_sequence = outbound.value;
  const auto bytes = packet(header, payload);
  auto transmitted = bytes;
  if (current == "wrong-sequence-tag") {
    transmitted.at(47) = static_cast<std::byte>(
        (std::to_integer<unsigned>(transmitted.at(47)) & ~0x3U) | 0x1U);
  } else if (current == "v1-after-ready") {
    header.envelope_version = wire::kEnvelopeVersionV1;
    header.header_size = wire::kHeaderSizeV1;
    header.lane_sequence = 0;
    transmitted = packet(header, payload);
  } else if (current == "unknown-message") {
    header.message_type = 0x4ffe;
    transmitted = packet(header, payload);
  } else if (current == "wrong-direction") {
    header.message_type = broker::kBrokerResultMessage;
    transmitted = packet(header, payload);
  } else if (current == "inbound-typed-error") {
    header.message_type =
        static_cast<std::uint16_t>(wire::CommonMessageType::typed_error);
    transmitted = packet(header, std::span(payload).first(8));
  } else if (current == "short-payload") {
    transmitted = packet(header, std::span(payload).first(23));
  } else if (current == "zero-correlation") {
    header.correlation_id = 0;
    transmitted = packet(header, payload);
  }
  send_bytes(4, transmitted, current == "post-ready-descriptor" ? 1U : 0U);
  if (current == "replay")
    send_bytes(4, transmitted);
  if (current == "reply-allowed" || current == "reply-denied") {
    const auto reply = receive_bytes(4);
    const auto decoded = wire::decode_packet(reply, wire::EndpointRole::broker);
    const auto expected =
        current == "reply-allowed"
            ? broker::kBrokerResultMessage
            : static_cast<std::uint16_t>(wire::CommonMessageType::typed_error);
    if (!decoded ||
        decoded.packet.header.envelope_version != wire::kEnvelopeVersionV2 ||
        sequence.accept_inbound(wire::EndpointRole::broker,
                                decoded.packet.header.lane_sequence) !=
            wire::FatalReason::none ||
        decoded.packet.header.message_type != expected ||
        decoded.packet.header.correlation_id != 1 ||
        decoded.packet.header.launch_generation != generation)
      fail();
    if (current == "reply-denied") {
      broker::BrokerTypedError error{};
      if (!broker::decode_broker_error(decoded.packet.payload, error) ||
          error.failed_operation !=
              broker::permissions::OperationId::storage_read)
        fail();
    }
    return;
  }
  std::byte ignored{};
  while (recv(4, &ignored, 1, 0) < 0 && errno == EINTR) {
  }
}

void send_control_ack(std::uint64_t generation,
                      wire::SessionSequence &sequence) {
  const auto outbound = sequence.take_outbound(wire::EndpointRole::control);
  if (!outbound)
    fail();
  const auto bytes =
      packet({.envelope_version = wire::kEnvelopeVersionV2,
              .header_size = wire::kHeaderSizeV2,
              .endpoint_role = wire::EndpointRole::control,
              .message_type = wire::kSurfaceSelectionAcceptedMessage,
              .role_protocol_version = 1,
              .launch_generation = generation,
              .correlation_id = 0,
              .lane_sequence = outbound.value},
             {});
  send_bytes(3, bytes);
  pause();
}
} // namespace

int main() {
  const std::string current = mode();
  wire::SessionSequence sequence;
  sigset_t ready_loss_signal{};
  if (current == "ready-loss" || current == "host-saturation") {
    if (sigemptyset(&ready_loss_signal) != 0 ||
        sigaddset(&ready_loss_signal, SIGUSR1) != 0 ||
        sigprocmask(SIG_BLOCK, &ready_loss_signal, nullptr) != 0) {
      fail();
    }
  }
  if (current == "transport-max") {
    std::vector<std::byte> received(
        wire::kHeaderSizeV2 + wire::payload_cap(wire::EndpointRole::broker));
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
  std::uint64_t control_generation = 0;
  std::uint64_t broker_generation = 0;
  if (current == "reverse-order") {
    static_cast<void>(negotiate(5, wire::EndpointRole::render, current));
    broker_generation = negotiate(4, wire::EndpointRole::broker, current);
    control_generation = negotiate(3, wire::EndpointRole::control, current);
  } else {
    control_generation = negotiate(3, wire::EndpointRole::control, current);
  }
  if (current == "peer-loss") {
    return 0;
  }
  if (current == "pre-ready") {
    send_broker_request(control_generation, current, sequence);
    return 0;
  }
  if (current == "wrong-role") {
    static_cast<void>(negotiate(4, wire::EndpointRole::control, current));
    return 0;
  }
  if (current != "reverse-order") {
    broker_generation = negotiate(4, wire::EndpointRole::broker, current);
    static_cast<void>(negotiate(5, wire::EndpointRole::render, current));
  }
  if (current == "ready-loss") {
    int received_signal = 0;
    if (sigwait(&ready_loss_signal, &received_signal) != 0 ||
        received_signal != SIGUSR1) {
      fail();
    }
    return 0;
  }
  if (current == "host-saturation") {
    int received_signal = 0;
    if (sigwait(&ready_loss_signal, &received_signal) != 0 ||
        received_signal != SIGUSR1)
      fail();
    const int flags = fcntl(3, F_GETFL);
    if (flags < 0 || fcntl(3, F_SETFL, flags | O_NONBLOCK) < 0)
      fail();
    std::array<std::byte, 8192> drained{};
    while (recv(3, drained.data(), drained.size(), 0) > 0) {
    }
    pause();
  }
  if (current == "wrong-control-ack")
    send_control_ack(control_generation, sequence);
  send_broker_request(broker_generation, current, sequence);
  return 0;
}
