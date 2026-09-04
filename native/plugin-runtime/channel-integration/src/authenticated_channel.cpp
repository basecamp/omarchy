#include "authenticated_channel.hpp"

#include "omarchy/plugin_runtime/broker/broker_schema.hpp"
#include "omarchy/plugin_runtime/surface/render_messages.hpp"

#include <poll.h>
#include <unistd.h>

#include <algorithm>
#include <array>
#include <atomic>
#include <cerrno>
#include <chrono>
#include <limits>
#include <span>
#include <string_view>
#include <utility>
#include <vector>

namespace omarchy::plugin_runtime::channel {
namespace {

constexpr std::uint16_t kControlRoleVersion = 1;
constexpr std::uint32_t kMaximumInFlight = 32;
std::atomic<std::uint64_t> next_channel_origin{1};

std::string_view failure_name(ChannelFailure failure) noexcept {
  switch (failure) {
  case ChannelFailure::launch_failed: return "launch-failed";
  case ChannelFailure::identity_mismatch: return "identity-mismatch";
  case ChannelFailure::peer_failure: return "peer-failure";
  case ChannelFailure::malformed_envelope: return "malformed-envelope";
  case ChannelFailure::negotiation_failed: return "negotiation-failed";
  case ChannelFailure::readiness_failed: return "readiness-failed";
  case ChannelFailure::not_ready: return "not-ready";
  case ChannelFailure::role_version_mismatch: return "role-version-mismatch";
  case ChannelFailure::stale_generation: return "stale-generation";
  case ChannelFailure::deadline_expired: return "deadline-expired";
  case ChannelFailure::none: return "none";
  }
  return "unknown";
}

std::size_t role_index(wire::EndpointRole role) {
  const auto value = static_cast<std::uint16_t>(role);
  return value >= 1 && value <= 3 ? value - 1 : 3;
}

wire::EndpointRole wire_role(launcher::EndpointRole role) {
  switch (role) {
  case launcher::EndpointRole::control:
    return wire::EndpointRole::control;
  case launcher::EndpointRole::broker:
    return wire::EndpointRole::broker;
  case launcher::EndpointRole::render:
    return wire::EndpointRole::render;
  }
  return wire::EndpointRole::control;
}

launcher::EndpointMask launcher_mask(wire::EndpointRole role) {
  switch (role) {
  case wire::EndpointRole::control:
    return launcher::EndpointMask::control;
  case wire::EndpointRole::broker:
    return launcher::EndpointMask::broker;
  case wire::EndpointRole::render:
    return launcher::EndpointMask::render;
  }
  return launcher::EndpointMask::none;
}

bool valid_mask_bits(launcher::EndpointMask mask) {
  const auto bits = static_cast<std::uint8_t>(mask);
  return (bits & ~static_cast<std::uint8_t>(launcher::EndpointMask::all)) == 0;
}

bool mask_subset(launcher::EndpointMask subset,
                 launcher::EndpointMask aggregate) {
  const auto requested = static_cast<std::uint8_t>(subset);
  const auto armed = static_cast<std::uint8_t>(aggregate);
  return requested != 0 && valid_mask_bits(subset) &&
         valid_mask_bits(aggregate) && (requested & armed) == requested;
}

launcher::EndpointRole launcher_role(wire::EndpointRole role) {
  switch (role) {
  case wire::EndpointRole::control:
    return launcher::EndpointRole::control;
  case wire::EndpointRole::broker:
    return launcher::EndpointRole::broker;
  case wire::EndpointRole::render:
    return launcher::EndpointRole::render;
  }
  return launcher::EndpointRole::control;
}

std::uint16_t role_version(wire::EndpointRole role) {
  switch (role) {
  case wire::EndpointRole::control:
    return kControlRoleVersion;
  case wire::EndpointRole::broker:
    return broker::kBrokerRoleVersion;
  case wire::EndpointRole::render:
    return surface::kRenderRoleVersion;
  }
  return 0;
}

const wire::RoleSchemaView *role_schema(wire::EndpointRole role) {
  if (role == wire::EndpointRole::broker)
    return broker::broker_schema_registry().find(role,
                                                 broker::kBrokerRoleVersion);
  if (role == wire::EndpointRole::render) {
    static const auto schema = surface::render_role_schema();
    return &schema;
  }
  return nullptr;
}

bool valid_typed_packet(const wire::PacketView &packet,
                        wire::Direction direction) {
  const auto *schema = role_schema(packet.header.endpoint_role);
  if (schema == nullptr) {
    if (packet.header.endpoint_role != wire::EndpointRole::control)
      return false;
    if (direction == wire::Direction::worker_to_host) {
      if ((packet.header.message_type ==
               wire::kPermissionSnapshotAcceptedMessage ||
           packet.header.message_type ==
               wire::kSettingsSnapshotAcceptedMessage ||
           packet.header.message_type ==
               wire::kPresentationSnapshotAcceptedMessage) &&
          packet.header.correlation_id == 0)
        return packet.payload.empty();
      return packet.header.message_type == wire::kSettingsUpdateMessage &&
             packet.header.correlation_id != 0 && !packet.payload.empty();
    }
    if ((packet.header.message_type == wire::kPermissionSnapshotMessage ||
         packet.header.message_type == wire::kSettingsSnapshotMessage ||
         packet.header.message_type == wire::kPresentationSnapshotMessage) &&
        packet.header.correlation_id == 0)
      return !packet.payload.empty();
    return packet.header.message_type == wire::kSettingsUpdateResultMessage &&
           packet.header.correlation_id != 0 && packet.payload.size() == 1 &&
           (packet.payload.front() == std::byte{0} ||
            packet.payload.front() == std::byte{1});
  }
  const auto type = packet.header.message_type;
  if (type == static_cast<std::uint16_t>(wire::CommonMessageType::cancel))
    return packet.header.correlation_id != 0 && packet.payload.empty();
  if (type ==
      static_cast<std::uint16_t>(wire::CommonMessageType::cancel_result)) {
    wire::CancelOutcome outcome{};
    return packet.header.correlation_id != 0 &&
           wire::decode_cancel_result_payload(packet.payload, outcome);
  }
  if (type ==
      static_cast<std::uint16_t>(wire::CommonMessageType::typed_error)) {
    const bool direction_allowed =
        packet.header.endpoint_role == wire::EndpointRole::broker
            ? direction == wire::Direction::host_to_worker
            : direction == wire::Direction::worker_to_host;
    return direction_allowed && packet.header.correlation_id != 0 &&
           packet.payload.size() >= schema->typed_error_minimum_payload &&
           packet.payload.size() <= schema->typed_error_maximum_payload;
  }
  const auto *rule = wire::find_message(*schema, type);
  if (rule == nullptr || !wire::permits_direction(*rule, direction) ||
      packet.payload.size() < rule->minimum_payload ||
      packet.payload.size() > rule->maximum_payload)
    return false;
  return rule->correlation == wire::CorrelationRule::zero
             ? packet.header.correlation_id == 0
             : packet.header.correlation_id != 0;
}

std::optional<std::uint8_t> descriptor_count(wire::EndpointRole role,
                                             std::uint16_t message_type) {
  if (message_type ==
          static_cast<std::uint16_t>(wire::CommonMessageType::typed_error) ||
      message_type ==
          static_cast<std::uint16_t>(wire::CommonMessageType::cancel) ||
      message_type == static_cast<std::uint16_t>(
                          wire::CommonMessageType::cancel_result))
    return 0;
  if (role == wire::EndpointRole::render)
    return surface::render_descriptor_count(message_type);
  if (role == wire::EndpointRole::control || role == wire::EndpointRole::broker)
    return 0;
  return {};
}

int milliseconds_until(launcher::Deadline deadline) {
  const auto now = std::chrono::steady_clock::now();
  if (now >= deadline)
    return 0;
  const auto remaining = deadline - now;
  return static_cast<int>(std::min<std::int64_t>(
      std::chrono::duration_cast<std::chrono::milliseconds>(remaining).count() +
          1,
      std::numeric_limits<int>::max()));
}

} // namespace

AuthenticatedBrokerChannel::AuthenticatedBrokerChannel(
    std::unique_ptr<launcher::Worker> worker, launcher::LaunchIdentity identity,
    std::shared_ptr<const GenerationAuthority> authority,
    launcher::Deadline opening_deadline)
    : worker_(std::move(worker)), identity_(std::move(identity)),
      authority_(std::move(authority)), opening_deadline_(opening_deadline),
      control_(wire::EndpointRole::control,
               {kControlRoleVersion, kControlRoleVersion}, identity_.generation,
               wire::payload_cap(wire::EndpointRole::control),
               kMaximumInFlight),
      broker_(wire::EndpointRole::broker,
              {broker::kBrokerRoleVersion, broker::kBrokerRoleVersion},
              identity_.generation,
              wire::payload_cap(wire::EndpointRole::broker), kMaximumInFlight),
      render_(wire::EndpointRole::render,
              {surface::kRenderRoleVersion, surface::kRenderRoleVersion},
              identity_.generation,
              wire::payload_cap(wire::EndpointRole::render), kMaximumInFlight),
      origin_(next_channel_origin.fetch_add(1, std::memory_order_relaxed)) {
  if (origin_ == 0)
    origin_ = next_channel_origin.fetch_add(1, std::memory_order_relaxed);
}

AuthenticatedBrokerChannel::~AuthenticatedBrokerChannel() = default;

OpenResult AuthenticatedBrokerChannel::open(
    launcher::Supervisor &supervisor,
    const launcher::TrustedLaunchRequest &request,
    std::shared_ptr<const GenerationAuthority> authority,
    launcher::Deadline deadline) {
  if (authority == nullptr)
    return {.channel = nullptr,
            .failure = ChannelFailure::identity_mismatch,
            .launch_failure = launcher::LaunchFailure::none,
            .detail = "generation authority is absent"};
  if (std::chrono::steady_clock::now() >= deadline)
    return {.channel = nullptr,
            .failure = ChannelFailure::launch_failed,
            .launch_failure = launcher::LaunchFailure::startup_timeout,
            .detail = "authenticated channel deadline expired before launch"};
  auto launched = supervisor.launch(request, deadline);
  if (!launched)
    return {.channel = nullptr,
            .failure = ChannelFailure::launch_failed,
            .launch_failure = launched.failure,
            .detail = std::move(launched.detail)};
  const auto &identity = launched.worker->identity();
  if (identity.plugin_id != request.plugin_id ||
      identity.revision_sha256 != request.revision_sha256 ||
      identity.generation != request.generation ||
      identity.outer_worker_pid <= 0 || identity.outer_uid != getuid() ||
      identity.outer_gid != getgid() || !launched.worker->alive()) {
    launched.worker.reset();
    return {.channel = nullptr,
            .failure = ChannelFailure::identity_mismatch,
            .launch_failure = launcher::LaunchFailure::none,
            .detail = "launched process identity differs from trusted request"};
  }
  if (!authority->is_current(identity)) {
    launched.worker.reset();
    return {.channel = nullptr,
            .failure = ChannelFailure::stale_generation,
            .launch_failure = launcher::LaunchFailure::none,
            .detail = "launched generation is no longer authoritative"};
  }
  if (std::chrono::steady_clock::now() >= deadline) {
    launched.worker.reset();
    return {.channel = nullptr,
            .failure = ChannelFailure::deadline_expired,
            .launch_failure = launcher::LaunchFailure::startup_timeout,
            .detail = "authenticated channel deadline expired before publish"};
  }
  auto channel = std::unique_ptr<AuthenticatedBrokerChannel>(
      new AuthenticatedBrokerChannel(std::move(launched.worker), identity,
                                     std::move(authority), deadline));
  if (std::chrono::steady_clock::now() >= deadline) {
    channel.reset();
    return {.channel = nullptr,
            .failure = ChannelFailure::deadline_expired,
            .launch_failure = launcher::LaunchFailure::startup_timeout,
            .detail = "authenticated channel deadline expired before publish"};
  }
  return {.channel = std::move(channel),
          .failure = ChannelFailure::none,
          .launch_failure = launcher::LaunchFailure::none,
          .detail = {}};
}

bool AuthenticatedBrokerChannel::negotiate(launcher::Deadline deadline) {
  deadline = std::min(deadline, opening_deadline_);
  if (failed() || ready_ || worker_ == nullptr ||
      std::chrono::steady_clock::now() >= deadline)
    return fail(ChannelFailure::negotiation_failed,
                "invalid or repeated channel negotiation");
  std::size_t remaining = negotiated_.size();
  while (remaining != 0) {
    launcher::EndpointMask allowed = launcher::EndpointMask::none;
    for (const auto role :
         {wire::EndpointRole::control, wire::EndpointRole::broker,
          wire::EndpointRole::render}) {
      const auto index = role_index(role);
      if (index >= negotiated_.size())
        return fail(ChannelFailure::negotiation_failed,
                    "channel role table contains an invalid endpoint");
      if (!negotiated_[index])
        allowed = allowed | launcher_mask(role);
    }
    auto message = receive_one(allowed, deadline);
    if (!message)
      return fail(ChannelFailure::peer_failure,
                  "authenticated endpoint HELLO receive failed");
    if (!negotiate_one(std::move(message), deadline))
      return false;
    --remaining;
  }
  bool aggregate_ready = false;
  if (!authority_->is_current(identity_))
    return fail(ChannelFailure::stale_generation,
                "launch generation changed during endpoint negotiation");
  if (std::chrono::steady_clock::now() >= deadline)
    return fail(ChannelFailure::negotiation_failed,
                "aggregate negotiation deadline elapsed before readiness");
  if (readiness_.ready(aggregate_ready) != wire::FatalReason::none ||
      !aggregate_ready || !worker_->alive())
    return fail(ChannelFailure::readiness_failed,
                "required endpoint generations are not jointly ready");
  if (std::chrono::steady_clock::now() >= deadline)
    return fail(ChannelFailure::negotiation_failed,
                "aggregate negotiation deadline elapsed before readiness");
  ready_ = true;
  if (!arm_readiness(launcher::EndpointMask::all, launcher::EndpointMask::none))
    return fail(ChannelFailure::readiness_failed,
                "aggregate channel readiness could not be armed");
  return true;
}

bool AuthenticatedBrokerChannel::negotiate_one(
    launcher::ReceivedMessage message, launcher::Deadline deadline) {
  if (!message.descriptors.empty())
    return fail(ChannelFailure::malformed_envelope,
                "endpoint HELLO carried descriptors");
  const auto role = wire_role(message.role);
  const auto index = role_index(role);
  if (index >= negotiated_.size() || negotiated_[index])
    return fail(ChannelFailure::negotiation_failed,
                "endpoint sent a duplicate HELLO");
  const auto decoded = wire::decode_packet(message.payload, role);
  if (!decoded ||
      decoded.packet.header.envelope_version != wire::kEnvelopeVersion)
    return fail(ChannelFailure::malformed_envelope,
                "endpoint HELLO envelope is malformed");
  auto *selected = negotiator(role);
  const auto negotiated = selected->accept_hello(decoded.packet);
  if (!negotiated)
    return fail(ChannelFailure::negotiation_failed,
                "endpoint HELLO negotiation failed");
  std::array<std::byte, wire::kHeaderSize + 8> encoded{};
  const auto payload =
      std::span(negotiated.payload).first(negotiated.payload_size);
  auto header = negotiated.header;
  header.payload_length = static_cast<std::uint32_t>(payload.size());
  const auto result = wire::encode_packet(header, payload, encoded);
  if (!result)
    return fail(ChannelFailure::malformed_envelope,
                "endpoint negotiation reply could not be encoded");
  const auto reply_bytes = std::span(encoded).first(result.bytes_written);
  for (;;) {
    if (std::chrono::steady_clock::now() >= deadline)
      return fail(ChannelFailure::negotiation_failed,
                  "endpoint negotiation deadline elapsed before WELCOME");
    if (!authority_->is_current(identity_) || worker_ == nullptr ||
        !worker_->alive())
      return fail(ChannelFailure::stale_generation,
                  "binding changed during endpoint negotiation reply");
    if (std::chrono::steady_clock::now() >= deadline)
      return fail(ChannelFailure::negotiation_failed,
                  "endpoint negotiation deadline elapsed before WELCOME");
    const auto sent =
        worker_->try_send(launcher_role(role), reply_bytes,
                          launcher::PacketSizeLimit{reply_bytes.size()});
    if (sent == launcher::SendStatus::complete)
      break;
    if (sent != launcher::SendStatus::would_block ||
        std::chrono::steady_clock::now() >= deadline)
      return fail(ChannelFailure::peer_failure,
                  "endpoint negotiation reply send failed");
    if (!arm_readiness(launcher::EndpointMask::none, launcher_mask(role)))
      return fail(ChannelFailure::readiness_failed,
                  "negotiation write readiness could not be armed");
    pollfd event{.fd = readiness_fd(), .events = POLLIN, .revents = 0};
    int polled = -1;
    do {
      polled = poll(&event, 1, milliseconds_until(deadline));
    } while (polled < 0 && errno == EINTR &&
             std::chrono::steady_clock::now() < deadline);
    if (polled <= 0 || worker_ == nullptr || !worker_->alive())
      return fail(ChannelFailure::peer_failure,
                  "peer exited or deadline elapsed during negotiation reply");
  }
  if (negotiated.kind != wire::NegotiationKind::welcome)
    return fail(ChannelFailure::negotiation_failed,
                "endpoint has no supported role version");
  if (selected->selected_version() != role_version(role) ||
      readiness_.observe(role, identity_.generation) != wire::FatalReason::none)
    return fail(ChannelFailure::readiness_failed,
                "endpoint selected unexpected version or generation");
  negotiated_[index] = true;
  return true;
}

wire::TrustedNegotiator *
AuthenticatedBrokerChannel::negotiator(wire::EndpointRole role) {
  switch (role) {
  case wire::EndpointRole::control:
    return &control_;
  case wire::EndpointRole::broker:
    return &broker_;
  case wire::EndpointRole::render:
    return &render_;
  }
  return nullptr;
}

launcher::ReceivedMessage
AuthenticatedBrokerChannel::receive_one(launcher::EndpointMask lanes,
                                        launcher::Deadline deadline) {
  if (worker_ == nullptr)
    return {.status = launcher::ReceiveStatus::fatal,
            .failure = launcher::ReceiveFailure::io_error};
  if (!arm_readiness(lanes, launcher::EndpointMask::none))
    return {.status = launcher::ReceiveStatus::fatal,
            .failure = launcher::ReceiveFailure::io_error};
  return worker_->receive_any(
      launcher::PacketSizeLimit{wire::kHeaderSize +
                                wire::payload_cap(wire::EndpointRole::broker)},
      deadline, lanes);
}

bool AuthenticatedBrokerChannel::validate_inbound(
    const launcher::ReceivedMessage &message, wire::PacketView &packet) {
  const auto role = wire_role(message.role);
  const auto decoded = wire::decode_packet(message.payload, role);
  if (!decoded ||
      decoded.packet.header.envelope_version != wire::kEnvelopeVersion ||
      decoded.packet.header.role_protocol_version != role_version(role) ||
      decoded.packet.header.launch_generation != identity_.generation ||
      decoded.packet.header.message_type == 0 ||
      sequence_.accept_inbound(role, decoded.packet.header.lane_sequence) !=
          wire::FatalReason::none) {
    fail(ChannelFailure::malformed_envelope,
         "authenticated packet failed binding or replay validation");
    return false;
  }
  if (!valid_typed_packet(decoded.packet, wire::Direction::worker_to_host)) {
    fail(ChannelFailure::malformed_envelope,
         "authenticated packet violates its selected role schema");
    return false;
  }
  const auto expected_descriptors =
      descriptor_count(role, decoded.packet.header.message_type);
  if (!expected_descriptors ||
      message.descriptors.size() != *expected_descriptors) {
    fail(ChannelFailure::malformed_envelope,
         "authenticated packet descriptor count differs from its schema");
    return false;
  }
  if (!authority_->is_current(identity_) || worker_ == nullptr ||
      !worker_->alive()) {
    fail(ChannelFailure::stale_generation,
         "binding changed after authenticated packet receive");
    return false;
  }
  packet = decoded.packet;
  return true;
}

std::optional<PreparedSend> AuthenticatedBrokerChannel::prepare_send(
    wire::EndpointRole role, std::uint16_t message_type,
    std::uint64_t correlation_id, std::span<const std::byte> payload) {
  if (!ready_ || failed() || termination_.attempted() || worker_ == nullptr ||
      message_type == 0 || payload.size() > wire::payload_cap(role))
    return {};
  if (!authority_->is_current(identity_))
    return fail(ChannelFailure::stale_generation,
                "binding changed before trusted packet preparation"),
           std::nullopt;
  const auto expected_descriptors = descriptor_count(role, message_type);
  if (!expected_descriptors)
    return fail(ChannelFailure::malformed_envelope,
                "trusted packet has no descriptor contract"),
           std::nullopt;
  const auto outbound = sequence_.take_outbound(role);
  if (!outbound)
    return fail(ChannelFailure::malformed_envelope,
                "outbound lane sequence is exhausted"),
           std::nullopt;
  std::vector<std::byte> bytes(wire::kHeaderSize + payload.size());
  const wire::EnvelopeHeader header{
      .envelope_version = wire::kEnvelopeVersion,
      .header_size = wire::kHeaderSize,
      .endpoint_role = role,
      .message_type = message_type,
      .role_protocol_version = role_version(role),
      .payload_length = static_cast<std::uint32_t>(payload.size()),
      .launch_generation = identity_.generation,
      .correlation_id = correlation_id,
      .lane_sequence = outbound.value};
  const auto encoded = wire::encode_packet(header, payload, bytes);
  if (!encoded) {
    fail(ChannelFailure::malformed_envelope,
         "trusted packet could not be encoded");
    return {};
  }
  const auto decoded = wire::decode_packet(bytes, role);
  if (!decoded ||
      !valid_typed_packet(decoded.packet, wire::Direction::host_to_worker)) {
    fail(ChannelFailure::malformed_envelope,
         "trusted packet violates its selected role schema");
    return {};
  }
  bytes.resize(encoded.bytes_written);
  return PreparedSend(role, std::move(bytes), origin_, *expected_descriptors);
}

ChannelSendStatus AuthenticatedBrokerChannel::try_send(
    PreparedSend &prepared, launcher::Deadline deadline,
    std::span<const int> borrowed_descriptors) {
  if (!prepared.pending_ || prepared.origin_ != origin_ || worker_ == nullptr)
    return ChannelSendStatus::fatal;
  if (std::chrono::steady_clock::now() >= deadline) {
    prepared.pending_ = false;
    fail(ChannelFailure::deadline_expired,
         "prepared packet deadline elapsed before send");
    return ChannelSendStatus::fatal;
  }
  if (!ready_ || failed() || termination_.attempted() ||
      !authority_->is_current(identity_)) {
    prepared.pending_ = false;
    fail(ChannelFailure::stale_generation,
         "binding changed before prepared packet send");
    return ChannelSendStatus::not_ready;
  }
  if (std::chrono::steady_clock::now() >= deadline) {
    prepared.pending_ = false;
    fail(ChannelFailure::deadline_expired,
         "prepared packet deadline elapsed before send");
    return ChannelSendStatus::fatal;
  }
  if (borrowed_descriptors.size() != prepared.descriptor_count_) {
    prepared.pending_ = false;
    fail(ChannelFailure::malformed_envelope,
         "prepared packet descriptor count changed before send");
    return ChannelSendStatus::fatal;
  }
  const auto status = worker_->try_send(
      launcher_role(prepared.role_), prepared.bytes_,
      launcher::PacketSizeLimit{prepared.bytes_.size()}, borrowed_descriptors);
  if (status == launcher::SendStatus::would_block)
    return ChannelSendStatus::would_block;
  prepared.pending_ = false;
  if (status == launcher::SendStatus::complete)
    return ChannelSendStatus::complete;
  if (status == launcher::SendStatus::peer_closed) {
    fail(ChannelFailure::peer_failure,
         "authenticated endpoint closed during prepared send");
    return ChannelSendStatus::peer_closed;
  }
  fail(ChannelFailure::peer_failure,
       "authenticated endpoint rejected prepared send");
  return ChannelSendStatus::fatal;
}

int AuthenticatedBrokerChannel::readiness_fd() const noexcept {
  return worker_ == nullptr ? -1 : worker_->readiness_fd();
}

bool AuthenticatedBrokerChannel::arm_readiness(
    launcher::EndpointMask read_lanes,
    launcher::EndpointMask blocked_write_lanes) noexcept {
  if (worker_ == nullptr || !valid_mask_bits(read_lanes) ||
      !valid_mask_bits(blocked_write_lanes) ||
      !worker_->set_readiness_interests(
          {.read = read_lanes, .write = blocked_write_lanes}))
    return false;
  armed_reads_ = read_lanes;
  return true;
}

AuthenticatedReceiveResult AuthenticatedBrokerChannel::receive_authenticated(
    launcher::EndpointMask allowed_lanes, launcher::Deadline deadline) {
  return receive_authenticated_impl(allowed_lanes, deadline,
                                    ReceiveMode::blocking);
}

AuthenticatedReceiveResult
AuthenticatedBrokerChannel::try_receive_authenticated(
    launcher::EndpointMask allowed_lanes) {
  return receive_authenticated_impl(allowed_lanes, launcher::Deadline::max(),
                                    ReceiveMode::nonblocking);
}

AuthenticatedReceiveResult
AuthenticatedBrokerChannel::receive_authenticated_impl(
    launcher::EndpointMask allowed_lanes, launcher::Deadline deadline,
    ReceiveMode mode) {
  const bool nonblocking = mode == ReceiveMode::nonblocking;
  if (!ready_ || failed() || termination_.attempted() || worker_ == nullptr) {
    if (!failed() && !termination_.attempted())
      fail(ChannelFailure::not_ready,
           "authenticated receive attempted before aggregate readiness");
    return {.status = AuthenticatedReceiveStatus::not_ready,
            .message = std::nullopt};
  }
  if (!mask_subset(allowed_lanes, armed_reads_)) {
    return {.status = AuthenticatedReceiveStatus::not_ready,
            .message = std::nullopt};
  }
  if (!nonblocking && std::chrono::steady_clock::now() >= deadline)
    return {.status = AuthenticatedReceiveStatus::would_block,
            .message = std::nullopt};
  if (!authority_->is_current(identity_)) {
    fail(ChannelFailure::stale_generation,
         "binding changed before authenticated receive");
    return {.status = AuthenticatedReceiveStatus::fatal,
            .message = std::nullopt};
  }
  if (!worker_->alive()) {
    fail(ChannelFailure::peer_failure,
         "worker exited before authenticated receive");
    return {.status = AuthenticatedReceiveStatus::peer_closed,
            .message = std::nullopt};
  }

  const launcher::PacketSizeLimit maximum{
      wire::kHeaderSize + wire::payload_cap(wire::EndpointRole::broker)};
  auto received = nonblocking
                      ? worker_->try_receive_any(maximum, allowed_lanes)
                      : worker_->receive_any(maximum, deadline, allowed_lanes);
  if (received.status == launcher::ReceiveStatus::would_block)
    return {.status = AuthenticatedReceiveStatus::would_block,
            .message = std::nullopt};
  if (received.status == launcher::ReceiveStatus::peer_closed) {
    fail(ChannelFailure::peer_failure,
         "peer closed during authenticated receive");
    return {.status = AuthenticatedReceiveStatus::peer_closed,
            .message = std::nullopt};
  }
  if (received.status != launcher::ReceiveStatus::message || !received) {
    fail(ChannelFailure::peer_failure,
         "transport failed during authenticated receive");
    return {.status = AuthenticatedReceiveStatus::fatal,
            .message = std::nullopt};
  }

  wire::PacketView packet{};
  if (!validate_inbound(received, packet))
    return {.status = AuthenticatedReceiveStatus::fatal,
            .message = std::nullopt};
  const auto header = packet.header;
  if (received.payload.size() < wire::kHeaderSize) {
    fail(ChannelFailure::malformed_envelope,
         "authenticated packet lost its canonical header boundary");
    return {.status = AuthenticatedReceiveStatus::fatal,
            .message = std::nullopt};
  }
  received.payload.erase(received.payload.begin(),
                         received.payload.begin() + wire::kHeaderSize);
  AuthenticatedMessage owned;
  owned.role = header.endpoint_role;
  owned.message_type = header.message_type;
  owned.correlation_id = header.correlation_id;
  owned.payload = std::move(received.payload);
  owned.descriptors = std::move(received.descriptors);

  // PacketView is invalid after the owning vector move. From here onward only
  // the copied semantic fields and owned payload/descriptors may be inspected.
  if (!nonblocking && std::chrono::steady_clock::now() >= deadline) {
    fail(ChannelFailure::deadline_expired,
         "authenticated receive deadline elapsed before publication");
    return {.status = AuthenticatedReceiveStatus::fatal,
            .message = std::nullopt};
  }
  if (!authority_->is_current(identity_)) {
    fail(ChannelFailure::stale_generation,
         "binding changed before authenticated message publication");
    return {.status = AuthenticatedReceiveStatus::fatal,
            .message = std::nullopt};
  }
  if (worker_ == nullptr || !worker_->alive()) {
    fail(ChannelFailure::peer_failure,
         "worker exited before authenticated message publication");
    return {.status = AuthenticatedReceiveStatus::peer_closed,
            .message = std::nullopt};
  }
  if (!nonblocking && std::chrono::steady_clock::now() >= deadline) {
    fail(ChannelFailure::deadline_expired,
         "authenticated receive deadline elapsed during final authority check");
    return {.status = AuthenticatedReceiveStatus::fatal,
            .message = std::nullopt};
  }
  return {.status = AuthenticatedReceiveStatus::message,
          .message = std::move(owned)};
}

bool AuthenticatedBrokerChannel::ready() const { return ready_ && !failed(); }
bool AuthenticatedBrokerChannel::alive() const {
  return worker_ != nullptr && !failed() && !termination_.attempted() &&
         worker_->alive();
}
bool AuthenticatedBrokerChannel::failed() const {
  return failure_ != ChannelFailure::none;
}
ChannelFailure AuthenticatedBrokerChannel::failure() const { return failure_; }
const std::string &AuthenticatedBrokerChannel::detail() const {
  return detail_;
}
const launcher::LaunchIdentity &AuthenticatedBrokerChannel::identity() const {
  return identity_;
}

bool AuthenticatedBrokerChannel::terminate(
    launcher::Deadline deadline) noexcept {
  if (!termination_.begin())
    return termination_.succeeded();
  ready_ = false;
  termination_.complete(worker_ == nullptr || worker_->terminate(deadline));
  return termination_.succeeded();
}

bool AuthenticatedBrokerChannel::fail(ChannelFailure failure,
                                      std::string failure_detail) {
  if (!failed()) {
    failure_ = failure;
    detail_ = std::move(failure_detail);
  }
  ready_ = false;
  if (worker_ != nullptr) {
    const auto worker_standard_error_bytes =
        worker_->take_standard_error_byte_count();
    if (worker_standard_error_bytes != 0) {
      dprintf(STDERR_FILENO,
              "omarchy-plugin-host: plugin=%s worker-failure=%.*s "
              "untrusted-stderr-bytes=%zu\n",
              identity_.plugin_id.c_str(),
              static_cast<int>(failure_name(failure_).size()),
              failure_name(failure_).data(), worker_standard_error_bytes);
    }
  }
  // Worker destruction transfers its preallocated cleanup job to the launcher
  // reaper. Protocol corruption and peer loss must never synchronously wait on
  // process or resource-scope teardown on the channel/UI thread.
  worker_.reset();
  return false;
}

} // namespace omarchy::plugin_runtime::channel
