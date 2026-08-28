#include "render_input_transport.hpp"

#include <array>
#include <utility>

namespace omarchy::plugin_runtime::bridge {

AuthenticatedInputTransport::AuthenticatedInputTransport(
    std::uint64_t launch_generation, std::shared_ptr<RenderPacketSink> sink)
    : generation_(launch_generation), sink_(std::move(sink)),
      endpoint_(
          wire::EndpointRole::render, surface::kRenderRoleVersion,
          launch_generation, wire::payload_cap(wire::EndpointRole::render), 1,
          []() -> const wire::RoleSchemaRegistryView & {
            static const std::array schemas{surface::render_role_schema()};
            static const wire::RoleSchemaRegistryView registry(schemas);
            return registry;
          }()) {
  if (launch_generation == 0 || sink_ == nullptr || endpoint_.failed()) {
    connected_ = false;
    failed_ = true;
  }
}

bool AuthenticatedInputTransport::send(std::uint16_t message_type,
                                       std::span<const std::byte> payload) {
  if (!connected_ || failed_)
    return false;
  const wire::PacketView packet{
      .header = {.endpoint_role = wire::EndpointRole::render,
                 .message_type = message_type,
                 .role_protocol_version = surface::kRenderRoleVersion,
                 .flags = 0,
                 .payload_length = static_cast<std::uint32_t>(payload.size()),
                 .launch_generation = generation_,
                 .correlation_id = 0},
      .payload = payload};
  const auto accepted =
      endpoint_.accept(packet, wire::Direction::host_to_worker);
  if (!accepted || accepted.action != wire::SessionAction::one_way_received ||
      !sink_->send(packet.header, payload)) {
    failed_ = true;
    connected_ = false;
    return false;
  }
  return true;
}

bool AuthenticatedInputTransport::submit(const surface::InputEvent &event) {
  const auto payload = surface::encode_input_event(event);
  return send(static_cast<std::uint16_t>(surface::RenderMessageType::input),
              payload);
}

bool AuthenticatedInputTransport::submit_focus(
    const surface::FocusEvent &event) {
  const auto payload = surface::encode_focus_event(event);
  return send(static_cast<std::uint16_t>(surface::RenderMessageType::focus),
              payload);
}

void AuthenticatedInputTransport::disconnect() { connected_ = false; }

bool AuthenticatedInputTransport::connected() const { return connected_; }

bool AuthenticatedInputTransport::failed() const { return failed_; }

} // namespace omarchy::plugin_runtime::bridge
