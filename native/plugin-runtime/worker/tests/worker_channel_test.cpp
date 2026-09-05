#include "worker_channel.hpp"
#include "startup_state.hpp"

#include "omarchy/plugin/wire/common.hpp"
#include "omarchy/plugin_runtime/surface/render_messages.hpp"

#include <fcntl.h>
#include <linux/memfd.h>
#include <sys/socket.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

#include <algorithm>
#include <array>
#include <cerrno>
#include <cstdint>
#include <cstring>
#include <iostream>
#include <limits>
#include <optional>
#include <span>
#include <stdexcept>
#include <vector>

namespace {

namespace surface = omarchy::plugin_runtime::surface;
namespace worker = omarchy::plugin_runtime::worker;
namespace wire = omarchy::plugin::wire;

void require(bool condition, const char *message) {
  if (!condition)
    throw std::runtime_error(message);
}

void startup_state_is_one_way() {
  worker::StartupState loaded;
  require(!loaded.loading() && !loaded.loaded() && !loaded.terminal(),
          "startup state did not begin awaiting its snapshot");
  require(loaded.begin_loading() && loaded.loading() &&
              !loaded.begin_loading(),
          "duplicate snapshot entered the QML load phase");
  require(loaded.finish_loading() && loaded.loaded() &&
              !loaded.finish_loading() && !loaded.begin_loading(),
          "loaded QML accepted another startup transition");
  require(loaded.terminate() && loaded.terminal() && !loaded.terminate(),
          "terminal startup was not idempotent");

  worker::StartupState failed_load;
  require(failed_load.begin_loading() && failed_load.terminate() &&
              failed_load.terminal() && !failed_load.finish_loading() &&
              !failed_load.begin_loading(),
          "failed QML load recovered or accepted another snapshot");
}

struct Pair {
  int worker = -1;
  int host = -1;
  Pair() {
    std::array<int, 2> descriptors{};
    require(socketpair(AF_UNIX, SOCK_SEQPACKET | SOCK_CLOEXEC, 0,
                       descriptors.data()) == 0,
            "socketpair failed");
    worker = descriptors[0];
    host = descriptors[1];
  }
  ~Pair() {
    close(worker);
    close(host);
  }
};

bool send_packet(int descriptor, const wire::EnvelopeHeader &header,
                 std::span<const std::byte> payload,
                 std::optional<int> passed_descriptor = std::nullopt) {
  std::vector<std::byte> packet(wire::kHeaderSize + payload.size());
  const auto encoded = wire::encode_packet(header, payload, packet);
  if (!encoded)
    return false;
  iovec vector{.iov_base = packet.data(), .iov_len = encoded.bytes_written};
  std::array<std::byte, CMSG_SPACE(sizeof(int))> ancillary{};
  msghdr message{.msg_name = nullptr,
                 .msg_namelen = 0,
                 .msg_iov = &vector,
                 .msg_iovlen = 1,
                 .msg_control = nullptr,
                 .msg_controllen = 0,
                 .msg_flags = 0};
  if (passed_descriptor) {
    message.msg_control = ancillary.data();
    message.msg_controllen = ancillary.size();
    auto *control = CMSG_FIRSTHDR(&message);
    control->cmsg_level = SOL_SOCKET;
    control->cmsg_type = SCM_RIGHTS;
    control->cmsg_len = CMSG_LEN(sizeof(int));
    std::memcpy(CMSG_DATA(control), &*passed_descriptor, sizeof(int));
    message.msg_controllen = ancillary.size();
  }
  return sendmsg(descriptor, &message, MSG_NOSIGNAL) ==
         static_cast<ssize_t>(encoded.bytes_written);
}

wire::EnvelopeHeader welcome_header(wire::EndpointRole role) {
  return {.endpoint_role = role,
          .message_type =
              static_cast<std::uint16_t>(wire::CommonMessageType::welcome),
          .role_protocol_version = 1,
          .payload_length = 8,
          .launch_generation = 77,
          .correlation_id = 0};
}

void handshake(worker::WorkerEndpoint &endpoint, int host) {
  if (!endpoint.valid())
    throw std::runtime_error("worker endpoint baseline failed: " +
                             endpoint.last_error());
  if (!endpoint.send_hello())
    throw std::runtime_error("worker HELLO failed: " + endpoint.last_error());
  std::array<std::byte, wire::kHeaderSize + 4> hello{};
  const auto received = recv(host, hello.data(), hello.size(), 0);
  require(received == static_cast<ssize_t>(hello.size()),
          "host did not receive an exact HELLO");
  const auto decoded = wire::decode_packet(
      std::span<const std::byte>(hello).first(static_cast<std::size_t>(received)),
      endpoint.role());
  require(decoded &&
              decoded.packet.header.message_type ==
                  static_cast<std::uint16_t>(wire::CommonMessageType::hello),
          "worker HELLO envelope is malformed");
  const auto payload = wire::encode_welcome_payload(
      {.maximum_payload = wire::payload_cap(endpoint.role()),
       .maximum_in_flight = 8});
  require(send_packet(host, welcome_header(endpoint.role()), payload),
          "host WELCOME send failed");
  const auto welcome = endpoint.receive();
  require(static_cast<bool>(welcome) && endpoint.accept_welcome(welcome) &&
              endpoint.selected() && endpoint.generation() == 77 &&
              endpoint.maximum_in_flight() == 8,
          "worker WELCOME negotiation failed");
}

constexpr std::uint64_t lane_value(wire::EndpointRole role,
                                   std::uint64_t counter) {
  return (counter << 2U) | static_cast<std::uint16_t>(role);
}

void valid_and_descriptor_paths() {
  Pair pair;
  wire::SessionSequence sequence;
  worker::WorkerEndpoint endpoint(pair.worker, wire::EndpointRole::render, 1,
                                  sequence);
  handshake(endpoint, pair.host);
  const auto offer =
      surface::encode_profile_offer(surface::software_profile_offer());
  wire::EnvelopeHeader offer_header{
      .endpoint_role = wire::EndpointRole::render,
      .message_type =
          static_cast<std::uint16_t>(surface::RenderMessageType::profile_offer),
      .role_protocol_version = 1,
      .payload_length = static_cast<std::uint32_t>(offer.size()),
      .launch_generation = 77,
      .correlation_id = 1,
      .lane_sequence = lane_value(wire::EndpointRole::render, 1)};
  require(send_packet(pair.host, offer_header, offer),
          "profile offer send failed");
  auto received = endpoint.receive();
  require(static_cast<bool>(received) &&
              received.payload.size() == offer.size() &&
              received.descriptors.empty(),
          "valid descriptor-free profile offer rejected");

  const auto page_size = sysconf(_SC_PAGESIZE);
  const auto allocation =
      surface::make_allocation({.id = 5, .generation = 77}, 16, 16, 16, 16, 1,
                               1, static_cast<std::uint64_t>(page_size));
  require(allocation.has_value(), "allocation fixture failed");
  const auto allocation_payload =
      surface::encode_surface_allocation(*allocation);
  wire::EnvelopeHeader allocation_header{
      .endpoint_role = wire::EndpointRole::render,
      .message_type = static_cast<std::uint16_t>(
          surface::RenderMessageType::surface_allocate),
      .role_protocol_version = 1,
      .payload_length = static_cast<std::uint32_t>(allocation_payload.size()),
      .launch_generation = 77,
      .correlation_id = 2,
      .lane_sequence = lane_value(wire::EndpointRole::render, 2)};
  const int memory =
      static_cast<int>(syscall(SYS_memfd_create, "channel-test", MFD_CLOEXEC));
  require(memory >= 0 && send_packet(pair.host, allocation_header,
                                     allocation_payload, memory),
          "allocation descriptor send failed");
  auto allocated = endpoint.receive();
  require(static_cast<bool>(allocated) && allocated.descriptors.size() == 1,
          "exact allocation descriptor was rejected");
  const int transferred = allocated.take_only_descriptor();
  require(transferred >= 0, "allocation descriptor transfer failed");
  close(transferred);
  close(memory);
}

void injected_descriptor_cleanup() {
  Pair pair;
  wire::SessionSequence sequence;
  worker::WorkerEndpoint endpoint(pair.worker, wire::EndpointRole::render, 1,
                                  sequence);
  handshake(endpoint, pair.host);
  const auto offer =
      surface::encode_profile_offer(surface::software_profile_offer());
  wire::EnvelopeHeader header{
      .endpoint_role = wire::EndpointRole::render,
      .message_type =
          static_cast<std::uint16_t>(surface::RenderMessageType::profile_offer),
      .role_protocol_version = 1,
      .payload_length = static_cast<std::uint32_t>(offer.size()),
      .launch_generation = 77,
      .correlation_id = 1,
      .lane_sequence = lane_value(wire::EndpointRole::render, 1)};
  const int memory =
      static_cast<int>(syscall(SYS_memfd_create, "injected-test", MFD_CLOEXEC));
  require(memory >= 0 && send_packet(pair.host, header, offer, memory),
          "injected descriptor send failed");
  int quarantined = -1;
  {
    auto rejected = endpoint.receive();
    require(!rejected &&
                rejected.failure ==
                    worker::ChannelFailure::descriptor_mismatch &&
                rejected.descriptors.size() == 1,
            "descriptor injection did not fail closed");
    quarantined = rejected.descriptors.front();
  }
  errno = 0;
  require(fcntl(quarantined, F_GETFD) < 0 && errno == EBADF,
          "rejected descriptor was not closed before teardown");
  close(memory);
}

void role_and_credential_rejection() {
  {
    Pair pair;
    wire::SessionSequence sequence;
    worker::WorkerEndpoint endpoint(pair.worker, wire::EndpointRole::render, 1,
                                    sequence);
    require(endpoint.send_hello(), "HELLO failed");
    std::array<std::byte, wire::kHeaderSize + 4> hello{};
    require(recv(pair.host, hello.data(), hello.size(), 0) ==
                static_cast<ssize_t>(hello.size()),
            "HELLO drain failed");
    const auto payload = wire::encode_welcome_payload(
        {.maximum_payload = wire::payload_cap(wire::EndpointRole::render),
         .maximum_in_flight = 8});
    auto wrong = welcome_header(wire::EndpointRole::control);
    require(send_packet(pair.host, wrong, payload), "role swap send failed");
    const auto rejected = endpoint.receive();
    require(!rejected &&
                rejected.failure == worker::ChannelFailure::malformed_envelope,
            "endpoint role substitution was accepted");
  }
  {
    Pair pair;
    wire::SessionSequence sequence;
    worker::WorkerEndpoint endpoint(pair.worker, wire::EndpointRole::render, 1,
                                    sequence);
    require(endpoint.send_hello(), "HELLO failed");
    std::array<std::byte, wire::kHeaderSize + 4> hello{};
    require(recv(pair.host, hello.data(), hello.size(), 0) ==
                static_cast<ssize_t>(hello.size()),
            "HELLO drain failed");
    const auto payload = wire::encode_welcome_payload(
        {.maximum_payload = wire::payload_cap(wire::EndpointRole::render),
         .maximum_in_flight = 8});
    const auto header = welcome_header(wire::EndpointRole::render);
    const pid_t child = fork();
    require(child >= 0, "credential test fork failed");
    if (child == 0)
      _exit(send_packet(pair.host, header, payload) ? 0 : 10);
    int status = 0;
    require(waitpid(child, &status, 0) == child && WIFEXITED(status) &&
                WEXITSTATUS(status) == 0,
            "descendant packet send failed");
    const auto rejected = endpoint.receive();
    require(!rejected &&
                rejected.failure == worker::ChannelFailure::credential_mismatch,
            "sender inconsistent with inherited credential baseline accepted");
  }
}

void oversized_datagram_rejection() {
  Pair pair;
  wire::SessionSequence sequence;
  worker::WorkerEndpoint endpoint(pair.worker, wire::EndpointRole::render, 1,
                                  sequence);
  handshake(endpoint, pair.host);
  std::vector<std::byte> oversized(
      wire::kHeaderSize + wire::payload_cap(wire::EndpointRole::render) + 1,
      std::byte{0x5a});
  require(send(pair.host, oversized.data(), oversized.size(), MSG_NOSIGNAL) ==
              static_cast<ssize_t>(oversized.size()),
          "oversized datagram send failed");
  const auto rejected = endpoint.receive();
  require(!rejected && rejected.failure == worker::ChannelFailure::truncated,
          "oversized datagram did not fail before parsing or allocation");
}

void pending_input_probe() {
  Pair pair;
  wire::SessionSequence sequence;
  worker::WorkerEndpoint endpoint(pair.worker, wire::EndpointRole::broker, 1,
                                  sequence);
  handshake(endpoint, pair.host);
  require(!endpoint.has_pending_input(),
          "empty broker endpoint reported pending input");
  wire::EnvelopeHeader header{
      .endpoint_role = wire::EndpointRole::broker,
      .message_type = 0x5000,
      .role_protocol_version = 1,
      .payload_length = 0,
      .launch_generation = 77,
      .correlation_id = 9,
      .lane_sequence = lane_value(wire::EndpointRole::broker, 1)};
  require(send_packet(pair.host, header, {}) && endpoint.has_pending_input(),
          "host broker reply was not observable by the level-triggered readiness recheck");
  const auto received = endpoint.receive();
  require(received && received.header.correlation_id == 9 &&
              !endpoint.has_pending_input(),
          "level-triggered readiness recheck consumed or retained the broker reply");
}

wire::EnvelopeHeader data_header(wire::EndpointRole role,
                                 std::uint64_t sequence,
                                 std::uint64_t correlation = 0) {
  return {.endpoint_role = role,
          .message_type = static_cast<std::uint16_t>(
              wire::CommonMessageType::protocol_error),
          .role_protocol_version = 1,
          .payload_length = 0,
          .launch_generation = 77,
          .correlation_id = correlation,
          .lane_sequence = sequence};
}

wire::EnvelopeHeader receive_header(int descriptor, wire::EndpointRole role) {
  std::array<std::byte, wire::kHeaderSize> packet{};
  const auto received = recv(descriptor, packet.data(), packet.size(), 0);
  require(received == static_cast<ssize_t>(packet.size()),
          "host did not receive an exact packet");
  const auto decoded = wire::decode_packet(packet, role);
  require(static_cast<bool>(decoded), "worker emitted malformed packet");
  return decoded.packet.header;
}

void lane_tagged_sequence_paths() {
  Pair control_pair;
  Pair broker_pair;
  Pair render_pair;
  wire::SessionSequence sequence;
  worker::WorkerEndpoint control(control_pair.worker,
                                 wire::EndpointRole::control, 1, sequence);
  worker::WorkerEndpoint broker(broker_pair.worker, wire::EndpointRole::broker,
                                1, sequence);
  worker::WorkerEndpoint render(render_pair.worker, wire::EndpointRole::render,
                                1, sequence);
  handshake(control, control_pair.host);
  handshake(broker, broker_pair.host);
  handshake(render, render_pair.host);

  const auto type = static_cast<std::uint16_t>(
      wire::CommonMessageType::protocol_error);
  require(control.send(type, {}, 1) && broker.send(type, {}, 2) &&
              render.send(type, {}, 3),
          "cross-lane sends failed");
  require(receive_header(control_pair.host, wire::EndpointRole::control)
                  .lane_sequence ==
              lane_value(wire::EndpointRole::control, 1) &&
              receive_header(broker_pair.host, wire::EndpointRole::broker)
                      .lane_sequence ==
                  lane_value(wire::EndpointRole::broker, 1) &&
              receive_header(render_pair.host, wire::EndpointRole::render)
                      .lane_sequence ==
                  lane_value(wire::EndpointRole::render, 1),
          "outbound sequences were not uniquely lane tagged");

  require(send_packet(
              render_pair.host,
              data_header(wire::EndpointRole::render,
                          lane_value(wire::EndpointRole::render, 2)), {}) &&
              static_cast<bool>(render.receive()) &&
              send_packet(
                  broker_pair.host,
                  data_header(wire::EndpointRole::broker,
                              lane_value(wire::EndpointRole::broker, 1)), {}) &&
              static_cast<bool>(broker.receive()),
          "independent lanes imposed a false global arrival order");
  require(send_packet(
              control_pair.host,
              data_header(wire::EndpointRole::control,
                          lane_value(wire::EndpointRole::control, 3)), {}) &&
              static_cast<bool>(control.receive()),
          "same-lane counter gap was rejected");
  require(send_packet(broker_pair.host,
                      data_header(wire::EndpointRole::broker,
                                  lane_value(wire::EndpointRole::broker, 1)),
                      {}),
          "replay fixture send failed");
  const auto replayed = broker.receive();
  require(!replayed &&
              replayed.failure == worker::ChannelFailure::sequence_failed,
          "equal same-lane sequence was accepted");

  Pair lower_pair;
  wire::SessionSequence lower_sequence;
  worker::WorkerEndpoint lower(lower_pair.worker, wire::EndpointRole::render, 1,
                               lower_sequence);
  handshake(lower, lower_pair.host);
  require(send_packet(
              lower_pair.host,
              data_header(wire::EndpointRole::render,
                          lane_value(wire::EndpointRole::render, 3)), {}) &&
              static_cast<bool>(lower.receive()) &&
              send_packet(
                  lower_pair.host,
                  data_header(wire::EndpointRole::render,
                              lane_value(wire::EndpointRole::render, 2)), {}),
          "lower same-lane fixture failed");
  const auto lowered = lower.receive();
  require(!lowered &&
              lowered.failure == worker::ChannelFailure::sequence_failed,
          "lower same-lane sequence was accepted");

  Pair transplant_pair;
  wire::SessionSequence transplant_sequence;
  worker::WorkerEndpoint transplant(transplant_pair.worker,
                                    wire::EndpointRole::control, 1,
                                    transplant_sequence);
  handshake(transplant, transplant_pair.host);
  require(send_packet(
              transplant_pair.host,
              data_header(wire::EndpointRole::broker,
                          lane_value(wire::EndpointRole::broker, 1)), {}),
          "role transplant fixture send failed");
  const auto role_rejected = transplant.receive();
  require(!role_rejected && role_rejected.failure ==
                                worker::ChannelFailure::malformed_envelope,
          "packet transplanted to another authenticated socket was accepted");

  Pair wrong_tag_pair;
  wire::SessionSequence wrong_tag_sequence;
  worker::WorkerEndpoint wrong_tag(wrong_tag_pair.worker,
                                   wire::EndpointRole::control, 1,
                                   wrong_tag_sequence);
  handshake(wrong_tag, wrong_tag_pair.host);
  auto wrong_tag_header = data_header(
      wire::EndpointRole::broker,
      lane_value(wire::EndpointRole::broker, 1));
  std::array<std::byte, wire::kHeaderSize> wrong_tag_packet{};
  require(static_cast<bool>(
              wire::encode_packet(wrong_tag_header, {}, wrong_tag_packet)),
          "wrong-tag fixture encode failed");
  wrong_tag_packet[9] = std::byte{1};
  require(send(wrong_tag_pair.host, wrong_tag_packet.data(),
               wrong_tag_packet.size(), MSG_NOSIGNAL) ==
              static_cast<ssize_t>(wrong_tag_packet.size()),
          "wrong-tag fixture send failed");
  const auto tag_rejected = wrong_tag.receive();
  require(!tag_rejected &&
              tag_rejected.failure ==
                  worker::ChannelFailure::malformed_envelope,
          "sequence tag from another lane was accepted");
}

void transport_send_failure_consumes_only_its_lane() {
  wire::SessionSequence sequence;
  Pair failed_pair;
  worker::WorkerEndpoint failed(failed_pair.worker,
                                wire::EndpointRole::control, 1, sequence);
  handshake(failed, failed_pair.host);
  require(close(failed_pair.host) == 0, "failed-send peer close failed");
  failed_pair.host = -1;
  const auto type = static_cast<std::uint16_t>(
      wire::CommonMessageType::protocol_error);
  require(!failed.send(type, {}, 1),
          "closed transport unexpectedly accepted a send");

  Pair control_pair;
  worker::WorkerEndpoint control(control_pair.worker,
                                 wire::EndpointRole::control, 1, sequence);
  handshake(control, control_pair.host);
  require(control.send(type, {}, 2) &&
              receive_header(control_pair.host, wire::EndpointRole::control)
                      .lane_sequence ==
                  lane_value(wire::EndpointRole::control, 2),
          "transport failure did not consume exactly one control value");

  Pair broker_pair;
  worker::WorkerEndpoint broker(broker_pair.worker, wire::EndpointRole::broker,
                                1, sequence);
  handshake(broker, broker_pair.host);
  require(broker.send(type, {}, 3) &&
              receive_header(broker_pair.host, wire::EndpointRole::broker)
                      .lane_sequence ==
                  lane_value(wire::EndpointRole::broker, 1),
          "control transport failure advanced an unrelated lane");
}

void zero_max_and_fd_cleanup() {
  {
    Pair pair;
    wire::SessionSequence sequence;
    worker::WorkerEndpoint endpoint(pair.worker, wire::EndpointRole::broker, 1,
                                    sequence);
    handshake(endpoint, pair.host);
    auto header = data_header(wire::EndpointRole::broker,
                              lane_value(wire::EndpointRole::broker, 1));
    std::array<std::byte, wire::kHeaderSize> packet{};
    require(static_cast<bool>(wire::encode_packet(header, {}, packet)),
            "zero-sequence fixture encode failed");
    std::fill(packet.begin() + 40, packet.end(), std::byte{0});
    require(send(pair.host, packet.data(), packet.size(), MSG_NOSIGNAL) ==
                static_cast<ssize_t>(packet.size()),
            "zero-sequence fixture send failed");
    const auto rejected = endpoint.receive();
    require(!rejected &&
                rejected.failure == worker::ChannelFailure::malformed_envelope,
            "post-ready sequence zero was accepted");
  }
  {
    Pair pair;
    wire::SessionSequence maximum(
        std::numeric_limits<std::uint64_t>::max() >> 2U);
    worker::WorkerEndpoint endpoint(pair.worker, wire::EndpointRole::render, 1,
                                    maximum);
    handshake(endpoint, pair.host);
    const auto type = static_cast<std::uint16_t>(
        wire::CommonMessageType::protocol_error);
    require(endpoint.send(type, {}, 0) &&
                receive_header(pair.host, wire::EndpointRole::render)
                        .lane_sequence ==
                    std::numeric_limits<std::uint64_t>::max() &&
                !endpoint.send(type, {}, 0),
            "outbound UINT64_MAX did not exhaust without wrapping");
  }
  {
    Pair pair;
    wire::SessionSequence sequence;
    worker::WorkerEndpoint endpoint(pair.worker, wire::EndpointRole::render, 1,
                                    sequence);
    handshake(endpoint, pair.host);
    require(send_packet(pair.host,
                        data_header(wire::EndpointRole::render,
                                    lane_value(wire::EndpointRole::render, 2)),
                        {}) &&
                static_cast<bool>(endpoint.receive()),
            "FD replay high-water fixture failed");
    auto allocation = data_header(
        wire::EndpointRole::render,
        lane_value(wire::EndpointRole::render, 1));
    allocation.message_type = static_cast<std::uint16_t>(
        surface::RenderMessageType::surface_allocate);
    const int memory = static_cast<int>(
        syscall(SYS_memfd_create, "sequence-fd-test", MFD_CLOEXEC));
    require(memory >= 0 && send_packet(pair.host, allocation, {}, memory),
            "FD replay fixture send failed");
    int quarantined = -1;
    {
      auto rejected = endpoint.receive();
      require(!rejected &&
                  rejected.failure == worker::ChannelFailure::sequence_failed &&
                  rejected.descriptors.size() == 1,
              "replayed packet with FD was accepted");
      quarantined = rejected.descriptors.front();
    }
    errno = 0;
    require(fcntl(quarantined, F_GETFD) < 0 && errno == EBADF,
            "FD on sequence failure was not closed");
    close(memory);
  }
}

} // namespace

int main() {
  try {
    startup_state_is_one_way();
    valid_and_descriptor_paths();
    injected_descriptor_cleanup();
    role_and_credential_rejection();
    oversized_datagram_rejection();
    pending_input_probe();
    lane_tagged_sequence_paths();
    transport_send_failure_consumes_only_its_lane();
    zero_max_and_fd_cleanup();
    std::cout << "plugin worker channel: ok\n";
    return 0;
  } catch (const std::exception &error) {
    std::cerr << "plugin worker channel: " << error.what() << '\n';
    return 1;
  }
}
