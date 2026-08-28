#include "render_session.hpp"

#include "omarchy/plugin_runtime/surface/render_messages.hpp"

#include <unistd.h>

#include <algorithm>
#include <array>
#include <limits>
#include <utility>

namespace omarchy::plugin_runtime::render_session {
namespace {

const wire::RoleSchemaRegistryView &schemas() {
  static const std::array values{surface::render_role_schema()};
  static const wire::RoleSchemaRegistryView registry(values);
  return registry;
}

} // namespace

HostRenderSession::HostRenderSession(std::uint64_t launch_generation,
                                     surface::TrustedFrameSink &sink,
                                     PacketSender &sender)
    : generation_(launch_generation), sink_(sink), sender_(sender) {}

HostRenderSession::~HostRenderSession() {
  if (phase_ != Phase::idle && phase_ != Phase::failed &&
      phase_ != Phase::disconnected)
    close();
}

bool HostRenderSession::start(const surface::TrustedAllocation &allocation) {
  if (phase_ != Phase::idle || generation_ == 0 ||
      allocation.surface.generation != generation_ ||
      !surface::allocation_is_consistent(allocation))
    return fail("invalid or duplicate render-session start");
  auto region = surface::HostFrameRegion::create(allocation);
  auto consumer = surface::FrameConsumer::create(allocation);
  if (!region || !consumer || !sink_.configure(allocation))
    return fail("trusted frame allocation or sink configuration failed");
  endpoint_ = std::make_unique<wire::SelectedEndpointState<8>>(
      wire::EndpointRole::render, surface::kRenderRoleVersion, generation_,
      wire::payload_cap(wire::EndpointRole::render), 4, schemas());
  if (endpoint_->failed())
    return fail("render endpoint state could not initialize");
  allocation_ = allocation;
  region_ = std::move(region);
  consumer_ = std::move(consumer);
  const auto offer =
      surface::encode_profile_offer(surface::software_profile_offer());
  phase_ = Phase::awaiting_profile;
  return send(
      static_cast<std::uint16_t>(surface::RenderMessageType::profile_offer),
      offer, 1);
}

bool HostRenderSession::send(std::uint16_t message_type,
                             std::span<const std::byte> payload,
                             std::uint64_t correlation,
                             std::span<const int> descriptors) {
  if (!endpoint_ || phase_ == Phase::failed || phase_ == Phase::disconnected ||
      descriptors.size() > 1)
    return fail("render send attempted outside an active session");
  const wire::PacketView packet{
      .header = {.endpoint_role = wire::EndpointRole::render,
                 .message_type = message_type,
                 .role_protocol_version = surface::kRenderRoleVersion,
                 .flags = 0,
                 .payload_length = static_cast<std::uint32_t>(payload.size()),
                 .launch_generation = generation_,
                 .correlation_id = correlation},
      .payload = payload};
  if (!endpoint_->accept(packet, wire::Direction::host_to_worker) ||
      !sender_.send(packet.header, payload, descriptors))
    return fail("render packet validation or transport send failed");
  return true;
}

bool HostRenderSession::receive(std::span<const std::byte> encoded_packet) {
  if (!endpoint_ || phase_ == Phase::failed || phase_ == Phase::disconnected ||
      encoded_packet.size() >
          wire::kHeaderSize + wire::payload_cap(wire::EndpointRole::render))
    return fail("render packet is unavailable or above the endpoint cap");
  const auto decoded =
      wire::decode_packet(encoded_packet, wire::EndpointRole::render);
  if (!decoded)
    return fail("malformed render envelope");
  if (!endpoint_->accept(decoded.packet, wire::Direction::worker_to_host))
    return fail("render packet violated the selected endpoint state");
  return handle(decoded.packet);
}

bool HostRenderSession::handle(const wire::PacketView &packet) {
  const auto type =
      static_cast<surface::RenderMessageType>(packet.header.message_type);
  if (phase_ == Phase::awaiting_profile &&
      type == surface::RenderMessageType::profile_select) {
    surface::ProfileSelection selection{};
    if (!surface::decode_profile_selection(packet.payload, selection) ||
        selection.version != surface::kSoftwareProfileVersion || !allocation_ ||
        !region_)
      return fail("worker selected an unsupported render profile");
    const auto payload = surface::encode_surface_allocation(*allocation_);
    const int descriptor = region_->duplicate_worker_fd();
    if (descriptor < 0)
      return fail("frame-region descriptor duplication failed");
    const std::array descriptors{descriptor};
    phase_ = Phase::awaiting_allocation;
    const bool sent = send(static_cast<std::uint16_t>(
                               surface::RenderMessageType::surface_allocate),
                           payload, 2, descriptors);
    ::close(descriptor);
    return sent;
  }
  if (phase_ == Phase::awaiting_allocation &&
      type == surface::RenderMessageType::surface_allocated) {
    surface::SurfaceKey key{};
    if (!allocation_ || !surface::decode_surface_key(packet.payload, key) ||
        key != allocation_->surface)
      return fail("worker acknowledged a stale surface allocation");
    phase_ = Phase::active;
    return true;
  }
  if (phase_ == Phase::active &&
      type == surface::RenderMessageType::frame_ready) {
    surface::FrameReady ready{};
    if (!allocation_ || !region_ || !consumer_ ||
        !surface::decode_frame_ready(packet.payload, ready))
      return fail("worker sent a malformed frame notification");
    const auto started = std::chrono::steady_clock::now();
    const auto consumed = consumer_->consume(region_->host_mapping(), ready);
    if (consumed == surface::ConsumeResult::stale_surface ||
        consumed == surface::ConsumeResult::invalid_sequence ||
        consumed == surface::ConsumeResult::stale_frame ||
        consumed == surface::ConsumeResult::concurrent_write ||
        consumed == surface::ConsumeResult::consumer_busy) {
      ++statistics_.rejected_frames;
      return false;
    }
    if (consumed != surface::ConsumeResult::accepted)
      return fail("untrusted frame region failed bounded validation");
    const auto *frame = consumer_->last_frame();
    if (frame == nullptr || frame->surface != allocation_->surface ||
        !sink_.present(frame->surface, frame->frame_sequence, frame->pixels))
      return fail("trusted bridge rejected the copied frame");
    const auto elapsed = std::chrono::steady_clock::now() - started;
    ++statistics_.accepted_frames;
    statistics_.copied_bytes += frame->pixels.size();
    statistics_.total_copy_time += elapsed;
    statistics_.maximum_copy_time =
        std::max(statistics_.maximum_copy_time,
                 std::chrono::duration_cast<std::chrono::nanoseconds>(elapsed));
    return true;
  }
  return fail("render packet arrived in the wrong lifecycle phase");
}

bool HostRenderSession::fail(std::string detail, bool peer_loss) {
  if (phase_ != Phase::failed && phase_ != Phase::disconnected) {
    failure_detail_ = std::move(detail);
    sink_.disconnect();
    consumer_.reset();
    region_.reset();
    endpoint_.reset();
    phase_ = peer_loss ? Phase::disconnected : Phase::failed;
  }
  return false;
}

void HostRenderSession::peer_lost() {
  static_cast<void>(fail("worker render peer was lost", true));
}

void HostRenderSession::close() {
  if (phase_ == Phase::idle || phase_ == Phase::failed ||
      phase_ == Phase::disconnected)
    return;
  if (allocation_ &&
      (phase_ == Phase::awaiting_allocation || phase_ == Phase::active)) {
    const auto payload = surface::encode_surface_key(allocation_->surface);
    static_cast<void>(send(
        static_cast<std::uint16_t>(surface::RenderMessageType::surface_release),
        payload, 0));
  }
  sink_.disconnect();
  consumer_.reset();
  region_.reset();
  endpoint_.reset();
  if (phase_ != Phase::failed) {
    phase_ = Phase::disconnected;
    failure_detail_ = "render session closed";
  }
}

Phase HostRenderSession::phase() const { return phase_; }

const Statistics &HostRenderSession::statistics() const { return statistics_; }

const std::string &HostRenderSession::failure_detail() const {
  return failure_detail_;
}

const surface::TrustedAllocation *HostRenderSession::allocation() const {
  return allocation_ ? &*allocation_ : nullptr;
}

} // namespace omarchy::plugin_runtime::render_session
