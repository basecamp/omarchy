#include "worker_channel.hpp"

#include "omarchy/plugin_runtime/surface/render_messages.hpp"

#include <fcntl.h>
#include <sys/socket.h>
#include <unistd.h>

#include <array>
#include <cerrno>
#include <cstring>
#include <limits>
#include <utility>

namespace omarchy::plugin_runtime::worker {
namespace {

void close_all(std::vector<int> &descriptors) {
  for (const int descriptor : descriptors) {
    if (descriptor >= 0)
      close(descriptor);
  }
  descriptors.clear();
}

std::uint8_t expected_descriptors(wire::EndpointRole role,
                                  std::uint16_t message_type) {
  if (message_type < 0x0100)
    return 0;
  if (role != wire::EndpointRole::render)
    return 0;
  return surface::render_descriptor_count(message_type).value_or(0xff);
}

} // namespace

ReceivedPacket::ReceivedPacket() = default;
ReceivedPacket::~ReceivedPacket() { close_descriptors(); }
ReceivedPacket::ReceivedPacket(ReceivedPacket &&other) noexcept
    : header(other.header), payload(std::move(other.payload)),
      descriptors(std::move(other.descriptors)), failure(other.failure),
      detail(std::move(other.detail)) {
  other.descriptors.clear();
}
ReceivedPacket &ReceivedPacket::operator=(ReceivedPacket &&other) noexcept {
  if (this != &other) {
    close_descriptors();
    header = other.header;
    payload = std::move(other.payload);
    descriptors = std::move(other.descriptors);
    failure = other.failure;
    detail = std::move(other.detail);
    other.descriptors.clear();
  }
  return *this;
}

int ReceivedPacket::take_only_descriptor() {
  if (descriptors.size() != 1)
    return -1;
  const int descriptor = descriptors.front();
  descriptors.clear();
  return descriptor;
}

void ReceivedPacket::close_descriptors() { close_all(descriptors); }

struct WorkerEndpoint::Impl {
  Impl(int endpoint_descriptor, wire::EndpointRole endpoint_role,
       std::uint16_t role_version)
      : descriptor(endpoint_descriptor), role(endpoint_role),
        negotiator(endpoint_role,
                   {.minimum = role_version, .maximum = role_version}) {
    if (descriptor < 0 || role_version == 0 || fcntl(descriptor, F_GETFD) < 0) {
      error = "endpoint descriptor is invalid";
      return;
    }
    socklen_t size = sizeof(peer);
    if (getsockopt(descriptor, SOL_SOCKET, SO_PEERCRED, &peer, &size) != 0 ||
        size != sizeof(peer)) {
      error = "cannot capture inherited SO_PEERCRED baseline: " +
              std::string(std::strerror(errno));
      return;
    }
    const int enabled = 1;
    if (setsockopt(descriptor, SOL_SOCKET, SO_PASSCRED, &enabled,
                   sizeof(enabled)) != 0) {
      error = "cannot require SCM_CREDENTIALS";
      return;
    }
    valid = true;
  }

  int descriptor = -1;
  wire::EndpointRole role;
  wire::WorkerNegotiator negotiator;
  ucred peer{};
  bool valid = false;
  std::string error;
};

WorkerEndpoint::WorkerEndpoint(int descriptor, wire::EndpointRole role,
                               std::uint16_t role_version)
    : implementation_(std::make_unique<Impl>(descriptor, role, role_version)) {}

WorkerEndpoint::~WorkerEndpoint() = default;

bool WorkerEndpoint::valid() const { return implementation_->valid; }
int WorkerEndpoint::descriptor() const { return implementation_->descriptor; }
wire::EndpointRole WorkerEndpoint::role() const {
  return implementation_->role;
}
std::uint64_t WorkerEndpoint::generation() const {
  return implementation_->negotiator.launch_generation();
}
std::uint16_t WorkerEndpoint::selected_version() const {
  return implementation_->negotiator.selected_version();
}
std::uint32_t WorkerEndpoint::maximum_payload() const {
  return implementation_->negotiator.maximum_payload();
}
std::uint32_t WorkerEndpoint::maximum_in_flight() const {
  return implementation_->negotiator.maximum_in_flight();
}
bool WorkerEndpoint::selected() const {
  return implementation_->negotiator.selected();
}
const std::string &WorkerEndpoint::last_error() const {
  return implementation_->error;
}

bool WorkerEndpoint::send_hello() {
  if (!valid())
    return false;
  const auto hello = implementation_->negotiator.make_hello();
  if (!hello) {
    implementation_->error = "cannot construct HELLO";
    return false;
  }
  std::array<std::byte, wire::kHeaderSize + 4> packet{};
  auto header = hello.header;
  header.payload_length = static_cast<std::uint32_t>(hello.payload.size());
  const auto encoded = wire::encode_packet(header, hello.payload, packet);
  if (!encoded ||
      ::send(implementation_->descriptor, packet.data(), encoded.bytes_written,
             MSG_NOSIGNAL) != static_cast<ssize_t>(encoded.bytes_written)) {
    implementation_->error = "cannot send HELLO";
    return false;
  }
  return true;
}

ReceivedPacket WorkerEndpoint::receive() {
  ReceivedPacket output;
  if (!valid()) {
    output.failure = ChannelFailure::invalid_descriptor;
    output.detail = implementation_->error;
    return output;
  }
  std::vector<std::byte> packet(wire::kHeaderSize +
                                wire::payload_cap(implementation_->role));
  std::array<std::byte, CMSG_SPACE(sizeof(ucred)) + CMSG_SPACE(sizeof(int) * 4)>
      ancillary{};
  iovec vector{.iov_base = packet.data(), .iov_len = packet.size()};
  msghdr message{.msg_name = nullptr,
                 .msg_namelen = 0,
                 .msg_iov = &vector,
                 .msg_iovlen = 1,
                 .msg_control = ancillary.data(),
                 .msg_controllen = ancillary.size(),
                 .msg_flags = 0};
  const auto received =
      recvmsg(implementation_->descriptor, &message, MSG_CMSG_CLOEXEC);
  if (received <= 0) {
    output.failure = ChannelFailure::io_error;
    output.detail = received == 0 ? "endpoint closed" : std::strerror(errno);
    return output;
  }
  bool credential_seen = false;
  ucred credential{};
  bool ancillary_valid = true;
  for (cmsghdr *header = CMSG_FIRSTHDR(&message); header != nullptr;
       header = CMSG_NXTHDR(&message, header)) {
    if (header->cmsg_level == SOL_SOCKET &&
        header->cmsg_type == SCM_CREDENTIALS &&
        header->cmsg_len == CMSG_LEN(sizeof(ucred)) && !credential_seen) {
      std::memcpy(&credential, CMSG_DATA(header), sizeof(credential));
      credential_seen = true;
    } else if (header->cmsg_level == SOL_SOCKET &&
               header->cmsg_type == SCM_RIGHTS &&
               header->cmsg_len >= CMSG_LEN(sizeof(int)) &&
               (header->cmsg_len - CMSG_LEN(0)) % sizeof(int) == 0) {
      const auto count = (header->cmsg_len - CMSG_LEN(0)) / sizeof(int);
      const auto *descriptors =
          reinterpret_cast<const int *>(CMSG_DATA(header));
      for (std::size_t index = 0; index < count; ++index)
        output.descriptors.push_back(descriptors[index]);
    } else {
      ancillary_valid = false;
    }
  }
  if ((message.msg_flags & (MSG_TRUNC | MSG_CTRUNC)) != 0) {
    output.failure = ChannelFailure::truncated;
    output.detail = "packet or ancillary data truncated";
    return output;
  }
  if (!ancillary_valid || !credential_seen) {
    output.failure = ChannelFailure::malformed_ancillary;
    output.detail = "credentials are missing, duplicate, or malformed";
    return output;
  }
  const auto &baseline = implementation_->peer;
  const bool pid_matches =
      baseline.pid == 0 ? credential.pid == 0 : credential.pid == baseline.pid;
  if (!pid_matches || credential.uid != baseline.uid ||
      credential.gid != baseline.gid) {
    output.failure = ChannelFailure::credential_mismatch;
    output.detail = "SCM_CREDENTIALS differ from inherited endpoint baseline";
    return output;
  }
  packet.resize(static_cast<std::size_t>(received));
  const auto decoded = wire::decode_packet(packet, implementation_->role);
  if (!decoded) {
    output.failure = ChannelFailure::malformed_envelope;
    output.detail = "outer envelope validation failed";
    return output;
  }
  const auto descriptor_count = expected_descriptors(
      implementation_->role, decoded.packet.header.message_type);
  if (descriptor_count == 0xff ||
      output.descriptors.size() != descriptor_count) {
    output.failure = ChannelFailure::descriptor_mismatch;
    output.detail = "message descriptor cardinality is invalid";
    return output;
  }
  output.header = decoded.packet.header;
  output.payload.assign(decoded.packet.payload.begin(),
                        decoded.packet.payload.end());
  return output;
}

bool WorkerEndpoint::accept_welcome(const ReceivedPacket &packet) {
  if (!packet || !packet.descriptors.empty()) {
    implementation_->error = "WELCOME packet was not valid";
    return false;
  }
  const wire::PacketView view{.header = packet.header,
                              .payload = packet.payload};
  const auto result = implementation_->negotiator.accept_reply(view);
  if (result != wire::FatalReason::none) {
    implementation_->error = "WELCOME negotiation failed";
    return false;
  }
  return true;
}

bool WorkerEndpoint::send(std::uint16_t message_type,
                          std::span<const std::byte> payload,
                          std::uint64_t correlation_id) {
  if (!selected() || payload.size() > wire::payload_cap(role())) {
    implementation_->error = "cannot send before negotiation or above cap";
    return false;
  }
  wire::EnvelopeHeader header{
      .endpoint_role = role(),
      .message_type = message_type,
      .role_protocol_version = selected_version(),
      .payload_length = static_cast<std::uint32_t>(payload.size()),
      .launch_generation = generation(),
      .correlation_id = correlation_id,
  };
  std::vector<std::byte> packet(wire::kHeaderSize + payload.size());
  const auto encoded = wire::encode_packet(header, payload, packet);
  if (!encoded ||
      ::send(descriptor(), packet.data(), encoded.bytes_written,
             MSG_NOSIGNAL) != static_cast<ssize_t>(encoded.bytes_written)) {
    implementation_->error = "endpoint send failed";
    return false;
  }
  return true;
}

} // namespace omarchy::plugin_runtime::worker
