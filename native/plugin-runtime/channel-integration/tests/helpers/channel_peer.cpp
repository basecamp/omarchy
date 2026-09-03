#include "omarchy/plugin/wire/common.hpp"
#include "omarchy/plugin/wire/control.hpp"
#include "omarchy/plugin/wire/permission_snapshot.hpp"
#include "omarchy/plugin/wire/state.hpp"
#include "omarchy/plugin_runtime/broker/broker_schema.hpp"
#include "omarchy/plugin_runtime/surface/render_messages.hpp"

#include <fcntl.h>
#include <signal.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <unistd.h>

#include <algorithm>
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
  if (const char *value = getenv("OMARCHY_PLUGIN_TEST_WORKER_MODE");
      value != nullptr) {
    return value;
  }
  std::ifstream input("/plugin/worker-mode");
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

std::vector<std::byte> receive_bytes(int descriptor,
                                     std::size_t capacity = 128) {
  std::vector<std::byte> bytes(capacity);
  const ssize_t count = recv(descriptor, bytes.data(), bytes.size(), MSG_TRUNC);
  if (count <= 0 || static_cast<std::size_t>(count) > bytes.size()) {
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

void put32(std::span<std::byte> output, std::size_t offset,
           std::uint32_t value) {
  for (std::size_t index = 0; index < 4; ++index)
    output[offset + index] =
        static_cast<std::byte>(value >> ((3U - index) * 8U));
}

void put64(std::span<std::byte> output, std::size_t offset,
           std::uint64_t value) {
  for (std::size_t index = 0; index < 8; ++index) {
    output[offset + index] =
        static_cast<std::byte>(value >> ((7U - index) * 8U));
  }
}

std::vector<std::byte> audio_request(std::uint64_t generation,
                                     std::uint64_t correlation,
                                     wire::SessionSequence &sequence) {
  constexpr std::string_view token = "timer";
  std::vector<std::byte> payload(10 + token.size());
  const auto operation = static_cast<std::uint16_t>(
      broker::permissions::OperationId::audio_play_cue);
  put16(payload, 0, operation);
  put16(payload, 2, static_cast<std::uint16_t>(2 + token.size()));
  payload[4] = std::byte{};
  payload[5] = std::byte{};
  payload[6] = std::byte{};
  payload[7] = std::byte{};
  put16(payload, 8, static_cast<std::uint16_t>(token.size()));
  for (std::size_t index = 0; index < token.size(); ++index)
    payload[10 + index] = static_cast<std::byte>(token[index]);
  const auto outbound = sequence.take_outbound(wire::EndpointRole::broker);
  if (!outbound)
    fail();
  return packet({.envelope_version = wire::kEnvelopeVersion,
                 .header_size = wire::kHeaderSize,
                 .endpoint_role = wire::EndpointRole::broker,
                 .message_type = operation,
                 .role_protocol_version = broker::kBrokerRoleVersion,
                 .launch_generation = generation,
                 .correlation_id = correlation,
                 .lane_sequence = outbound.value},
                payload);
}

std::vector<std::byte> notification_request(std::uint64_t generation,
                                            std::uint64_t correlation,
                                            wire::SessionSequence &sequence) {
  constexpr std::string_view category = "timer";
  constexpr std::array provider{std::byte{0}, std::byte{1}, std::byte{0},
                                std::byte{2}, std::byte{'T'}, std::byte{'O'},
                                std::byte{'K'}};
  std::vector<std::byte> payload(10 + category.size() + provider.size());
  const auto operation = static_cast<std::uint16_t>(
      broker::permissions::OperationId::notification_send);
  put16(payload, 0, operation);
  put16(payload, 2, static_cast<std::uint16_t>(2 + category.size()));
  put32(payload, 4, static_cast<std::uint32_t>(provider.size()));
  put16(payload, 8, static_cast<std::uint16_t>(category.size()));
  for (std::size_t index = 0; index < category.size(); ++index)
    payload[10 + index] = static_cast<std::byte>(category[index]);
  std::copy(provider.begin(), provider.end(),
            payload.begin() + 10 + category.size());
  const auto outbound = sequence.take_outbound(wire::EndpointRole::broker);
  if (!outbound)
    fail();
  return packet({.envelope_version = wire::kEnvelopeVersion,
                 .header_size = wire::kHeaderSize,
                 .endpoint_role = wire::EndpointRole::broker,
                 .message_type = operation,
                 .role_protocol_version = broker::kBrokerRoleVersion,
                 .launch_generation = generation,
                 .correlation_id = correlation,
                 .lane_sequence = outbound.value},
                payload);
}

void validate_empty_broker_reply(std::span<const std::byte> bytes,
                                 std::uint64_t generation,
                                 std::uint64_t correlation,
                                 wire::SessionSequence &sequence) {
  const auto decoded = wire::decode_packet(bytes, wire::EndpointRole::broker);
  if (!decoded ||
      sequence.accept_inbound(wire::EndpointRole::broker,
                              decoded.packet.header.lane_sequence) !=
          wire::FatalReason::none ||
      decoded.packet.header.message_type != broker::kBrokerResultMessage ||
      decoded.packet.header.role_protocol_version !=
          broker::kBrokerRoleVersion ||
      decoded.packet.header.correlation_id != correlation ||
      decoded.packet.header.launch_generation != generation ||
      !decoded.packet.payload.empty())
    fail();
}

std::string validate_dynamic_reply(std::span<const std::byte> bytes,
                                   std::uint64_t generation,
                                   std::uint64_t correlation,
                                   wire::SessionSequence &sequence) {
  const auto decoded = wire::decode_packet(bytes, wire::EndpointRole::broker);
  if (!decoded ||
      sequence.accept_inbound(wire::EndpointRole::broker,
                              decoded.packet.header.lane_sequence) !=
          wire::FatalReason::none ||
      decoded.packet.header.message_type != broker::kBrokerResultMessage ||
      decoded.packet.header.role_protocol_version !=
          broker::kBrokerRoleVersion ||
      decoded.packet.header.correlation_id != correlation ||
      decoded.packet.header.launch_generation != generation ||
      decoded.packet.payload.empty())
    fail();
  return {reinterpret_cast<const char *>(decoded.packet.payload.data()),
          decoded.packet.payload.size()};
}

void send_session_signal(int descriptor, wire::EndpointRole role,
                         std::uint16_t type, std::uint64_t generation,
                         std::span<const std::byte> payload,
                         wire::SessionSequence &sequence) {
  const auto outbound = sequence.take_outbound(role);
  if (!outbound)
    fail();
  send_bytes(descriptor, packet({.envelope_version = wire::kEnvelopeVersion,
                                 .header_size = wire::kHeaderSize,
                                 .endpoint_role = role,
                                 .message_type = type,
                                 .role_protocol_version = version(role),
                                 .launch_generation = generation,
                                 .correlation_id = 0,
                                 .lane_sequence = outbound.value},
                                payload));
}

[[noreturn]] void wait_forever();

bool accept_startup_settings(std::uint64_t generation,
                             wire::SessionSequence &sequence) {
  const auto bytes = receive_bytes(
      3, wire::kHeaderSize + wire::payload_cap(wire::EndpointRole::control));
  const auto decoded = wire::decode_packet(bytes, wire::EndpointRole::control);
  if (!decoded ||
      sequence.accept_inbound(wire::EndpointRole::control,
                              decoded.packet.header.lane_sequence) !=
          wire::FatalReason::none ||
      decoded.packet.header.message_type != wire::kSettingsSnapshotMessage ||
      decoded.packet.header.role_protocol_version !=
          version(wire::EndpointRole::control) ||
      decoded.packet.header.launch_generation != generation ||
      decoded.packet.header.correlation_id != 0 ||
      decoded.packet.payload.empty())
    fail();

  const auto outbound = sequence.take_outbound(wire::EndpointRole::control);
  if (!outbound)
    fail();
  send_bytes(3, packet({.envelope_version = wire::kEnvelopeVersion,
                        .header_size = wire::kHeaderSize,
                        .endpoint_role = wire::EndpointRole::control,
                        .message_type = wire::kSettingsSnapshotAcceptedMessage,
                        .role_protocol_version =
                            version(wire::EndpointRole::control),
                        .launch_generation = generation,
                        .correlation_id = 0,
                        .lane_sequence = outbound.value},
                       {}));
  return true;
}

bool accept_startup_permissions(std::uint64_t generation,
                                std::string_view current,
                                wire::SessionSequence &sequence) {
  const auto bytes = receive_bytes(
      3, wire::kHeaderSize +
             wire::permission_snapshot::kMaximumPayloadBytes);
  const auto decoded = wire::decode_packet(bytes, wire::EndpointRole::control);
  wire::permission_snapshot::PermissionSnapshot snapshot;
  if (!decoded ||
      sequence.accept_inbound(wire::EndpointRole::control,
                              decoded.packet.header.lane_sequence) !=
          wire::FatalReason::none ||
      decoded.packet.header.message_type != wire::kPermissionSnapshotMessage ||
      decoded.packet.header.role_protocol_version !=
          version(wire::EndpointRole::control) ||
      decoded.packet.header.launch_generation != generation ||
      decoded.packet.header.correlation_id != 0 ||
      !wire::permission_snapshot::decode(decoded.packet.payload, snapshot))
    fail();

  if (current == "session-startup-authority-loss") {
    const char *state = getenv("OMARCHY_PLUGIN_TEST_STATE_FD");
    if (state == nullptr || std::string_view(state) != "6")
      fail();
    const int marker = openat(6, "startup-snapshot-received",
                              O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0600);
    if (marker < 0 || close(marker) < 0)
      fail();
    for (;;) {
      const int release = openat(6, "release-startup-ack",
                                 O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
      if (release >= 0) {
        if (close(release) < 0)
          fail();
        break;
      }
      if (errno != ENOENT)
        fail();
      usleep(1000);
    }
  }
  if (current == "session-startup-missing")
    wait_forever();
  if (current == "session-startup-peer-loss")
    return false;

  const auto outbound = sequence.take_outbound(wire::EndpointRole::control);
  if (!outbound)
    fail();
  const bool wrong_generation =
      current == "session-startup-wrong-generation";
  const bool wrong_type = current == "session-startup-wrong-type";
  const bool wrong_correlation =
      current == "session-startup-wrong-correlation";
  const std::array<std::byte, 1> malformed_payload{std::byte{1}};
  const auto payload = current == "session-startup-payload"
                           ? std::span<const std::byte>(malformed_payload)
                           : std::span<const std::byte>{};
  const auto acknowledgement = packet(
      {.envelope_version = wire::kEnvelopeVersion,
       .header_size = wire::kHeaderSize,
       .endpoint_role = wire::EndpointRole::control,
       .message_type = wrong_type ? std::uint16_t{0xffffU}
                                  : wire::kPermissionSnapshotAcceptedMessage,
       .role_protocol_version = version(wire::EndpointRole::control),
       .launch_generation = wrong_generation ? generation + 1 : generation,
       .correlation_id = wrong_correlation ? 1U : 0U,
       .lane_sequence = outbound.value},
      payload);
  send_bytes(3, acknowledgement,
             current == "session-startup-descriptor" ? 1U : 0U);
  if (current.starts_with("session-startup-"))
    wait_forever();
  return true;
}

[[noreturn]] void wait_forever() {
  for (;;)
    pause();
}

[[noreturn]] void session_happy(std::uint64_t generation,
                                wire::SessionSequence &sequence) {
  send_bytes(4, audio_request(generation, 1, sequence));
  validate_empty_broker_reply(receive_bytes(4), generation, 1, sequence);
  const auto frame =
      surface::encode_frame_ready({.surface = {.id = 1, .generation = 1},
                                   .slot = 0,
                                   .slot_sequence = 2,
                                   .frame_sequence = 1});
  send_session_signal(
      5, wire::EndpointRole::render,
      static_cast<std::uint16_t>(surface::RenderMessageType::frame_ready),
      generation, frame, sequence);
  wait_forever();
}

[[noreturn]] void session_replay(std::uint64_t generation,
                                 wire::SessionSequence &sequence) {
  const auto request = audio_request(generation, 1, sequence);
  send_bytes(4, request);
  validate_empty_broker_reply(receive_bytes(4), generation, 1, sequence);
  send_bytes(4, request);
  wait_forever();
}

[[noreturn]] void session_notification(std::uint64_t generation,
                                       wire::SessionSequence &sequence) {
  // The first activation exercises the optional provider. Its G+1 replacement
  // after revocation must remain alive without attempting the revoked effect.
  if (generation == 1) {
    send_bytes(4, notification_request(generation, 1, sequence));
    validate_empty_broker_reply(receive_bytes(4), generation, 1, sequence);
  }
  wait_forever();
}

std::vector<std::byte> dynamic_request(std::uint64_t generation,
                                       std::uint64_t correlation,
                                       wire::SessionSequence &sequence) {
  const int request =
      openat(6, "dynamic-request", O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
  std::vector<std::byte> payload(64 * 1024);
  const auto count =
      request < 0 ? -1 : read(request, payload.data(), payload.size());
  if (request >= 0)
    close(request);
  if (count <= 0 || static_cast<std::size_t>(count) == payload.size())
    fail();
  payload.resize(static_cast<std::size_t>(count));
  const auto outbound = sequence.take_outbound(wire::EndpointRole::broker);
  if (!outbound)
    fail();
  return packet({.envelope_version = wire::kEnvelopeVersion,
                 .header_size = wire::kHeaderSize,
                 .endpoint_role = wire::EndpointRole::broker,
                 .message_type = broker::kDynamicInvokeMessage,
                 .role_protocol_version = broker::kBrokerRoleVersion,
                 .launch_generation = generation,
                 .correlation_id = correlation,
                 .lane_sequence = outbound.value},
                payload);
}

[[noreturn]] void session_provider(std::uint64_t generation,
                                   wire::SessionSequence &sequence) {
  send_bytes(4, dynamic_request(generation, 81, sequence));
  const auto first =
      validate_dynamic_reply(receive_bytes(4), generation, 81, sequence);
  send_bytes(4, dynamic_request(generation, 82, sequence));
  const auto second =
      validate_dynamic_reply(receive_bytes(4), generation, 82, sequence);
  if (first != second)
    fail();
  const int result = openat(6, "provider-replies",
                            O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0600);
  const std::string report = "81 " + first + "\n82 " + second + "\n";
  if (result < 0 ||
      write(result, report.data(), report.size()) !=
          static_cast<ssize_t>(report.size()) ||
      close(result) < 0)
    fail();
  wait_forever();
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
      .envelope_version = wire::kEnvelopeVersion,
      .header_size = wire::kHeaderSize,
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
  } else if (current == "unsupported-envelope-version-after-ready") {
    transmitted[4] = std::byte{0};
    transmitted[5] = std::byte{1};
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
  std::byte ignored{};
  while (recv(4, &ignored, 1, 0) < 0 && errno == EINTR) {
  }
}

void send_multi_lane(std::uint64_t generation,
                     wire::SessionSequence &sequence) {
  std::array<std::byte, 24> broker_payload{};
  const auto operation = static_cast<std::uint16_t>(
      broker::permissions::OperationId::storage_read);
  put16(broker_payload, 0, operation);
  put16(broker_payload, 2, 16);
  put64(broker_payload, 8, 4096);
  put64(broker_payload, 16, 1024);
  const auto broker_sequence =
      sequence.take_outbound(wire::EndpointRole::broker);
  if (!broker_sequence)
    fail();
  send_bytes(4, packet({.envelope_version = wire::kEnvelopeVersion,
                        .header_size = wire::kHeaderSize,
                        .endpoint_role = wire::EndpointRole::broker,
                        .message_type = operation,
                        .role_protocol_version = broker::kBrokerRoleVersion,
                        .launch_generation = generation,
                        .correlation_id = 1,
                        .lane_sequence = broker_sequence.value},
                       broker_payload));

  std::array<std::byte, 40> render_payload{};
  const auto render_sequence =
      sequence.take_outbound(wire::EndpointRole::render);
  if (!render_sequence)
    fail();
  send_bytes(5, packet({.envelope_version = wire::kEnvelopeVersion,
                        .header_size = wire::kHeaderSize,
                        .endpoint_role = wire::EndpointRole::render,
                        .message_type = static_cast<std::uint16_t>(
                            surface::RenderMessageType::frame_ready),
                        .role_protocol_version = surface::kRenderRoleVersion,
                        .launch_generation = generation,
                        .correlation_id = 0,
                        .lane_sequence = render_sequence.value},
                       render_payload));
  pause();
}

[[noreturn]] void send_render_typed_error(
    std::uint64_t generation, wire::SessionSequence &sequence) {
  const surface::SurfaceKey key{.id = 1, .generation = generation};
  const auto payload = surface::encode_render_error(
      {.reason = surface::RenderErrorReason::invalid_allocation,
       .failed_message_type = static_cast<std::uint16_t>(
           surface::RenderMessageType::surface_allocate),
       .surface = key});
  const auto outbound = sequence.take_outbound(wire::EndpointRole::render);
  if (!outbound)
    fail();
  send_bytes(5, packet({.envelope_version = wire::kEnvelopeVersion,
                        .header_size = wire::kHeaderSize,
                        .endpoint_role = wire::EndpointRole::render,
                        .message_type = static_cast<std::uint16_t>(
                            wire::CommonMessageType::typed_error),
                        .role_protocol_version = surface::kRenderRoleVersion,
                        .launch_generation = generation,
                        .correlation_id = 1,
                        .lane_sequence = outbound.value},
                       payload));
  wait_forever();
}
} // namespace

int main() {
  const std::string current = mode();
  wire::SessionSequence sequence;
  sigset_t ready_loss_signal{};
  if (current == "ready-loss" || current == "stderr-ready-loss" ||
      current == "host-saturation") {
    if (sigemptyset(&ready_loss_signal) != 0 ||
        sigaddset(&ready_loss_signal, SIGUSR1) != 0 ||
        sigprocmask(SIG_BLOCK, &ready_loss_signal, nullptr) != 0) {
      fail();
    }
  }
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
  if (current == "ready-loss" || current == "stderr-ready-loss") {
    if (current == "stderr-ready-loss") {
      std::string diagnostic =
          "sidecar secret: omarchy-plugin-qml-worker: forged fatal\n"
          "omarchy-plugin-qml-worker: file:///plugin/Service.qml:239:5: "
          "QML-forged fatal\n";
      diagnostic.resize(9000, 'x');
      if (write(STDERR_FILENO, diagnostic.data(), diagnostic.size()) !=
          static_cast<ssize_t>(diagnostic.size()))
        fail();
    }
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
    const int flags = fcntl(4, F_GETFL);
    if (flags < 0 || fcntl(4, F_SETFL, flags | O_NONBLOCK) < 0)
      fail();
    std::array<std::byte, 8192> drained{};
    while (recv(4, drained.data(), drained.size(), 0) > 0) {
    }
    pause();
  }
  if (current.starts_with("session-")) {
    if (!accept_startup_settings(control_generation, sequence) ||
        !accept_startup_permissions(control_generation, current, sequence))
      return 0;
  }
  if (current == "session-idle")
    wait_forever();
  if (current == "session-happy")
    session_happy(broker_generation, sequence);
  if (current == "session-replay")
    session_replay(broker_generation, sequence);
  if (current == "session-notification")
    session_notification(broker_generation, sequence);
  if (current == "session-provider")
    session_provider(broker_generation, sequence);
  if (current == "multi-lane")
    send_multi_lane(broker_generation, sequence);
  if (current == "render-typed-error")
    send_render_typed_error(broker_generation, sequence);
  send_broker_request(broker_generation, current, sequence);
  return 0;
}
