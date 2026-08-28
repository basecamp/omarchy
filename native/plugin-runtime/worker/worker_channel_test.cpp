#include "worker_channel.hpp"

#include "omarchy/plugin/wire/common.hpp"
#include "omarchy/plugin_runtime/surface/render_messages.hpp"

#include <fcntl.h>
#include <linux/memfd.h>
#include <sys/socket.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

#include <array>
#include <cerrno>
#include <cstdint>
#include <cstring>
#include <iostream>
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
          "host did not receive exact HELLO");
  const auto decoded = wire::decode_packet(hello, endpoint.role());
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

void valid_and_descriptor_paths() {
  Pair pair;
  worker::WorkerEndpoint endpoint(pair.worker, wire::EndpointRole::render, 1);
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
      .correlation_id = 1};
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
      .correlation_id = 2};
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
  worker::WorkerEndpoint endpoint(pair.worker, wire::EndpointRole::render, 1);
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
      .correlation_id = 1};
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
    worker::WorkerEndpoint endpoint(pair.worker, wire::EndpointRole::render, 1);
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
    worker::WorkerEndpoint endpoint(pair.worker, wire::EndpointRole::render, 1);
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
  worker::WorkerEndpoint endpoint(pair.worker, wire::EndpointRole::render, 1);
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

} // namespace

int main() {
  try {
    valid_and_descriptor_paths();
    injected_descriptor_cleanup();
    role_and_credential_rejection();
    oversized_datagram_rejection();
    std::cout << "plugin worker channel: ok\n";
    return 0;
  } catch (const std::exception &error) {
    std::cerr << "plugin worker channel: " << error.what() << '\n';
    return 1;
  }
}
