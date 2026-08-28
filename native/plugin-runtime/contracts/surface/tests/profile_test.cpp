#include "test.hpp"

#include "omarchy/plugin/wire/state.hpp"
#include "omarchy/plugin_runtime/surface/profile.hpp"
#include "omarchy/plugin_runtime/surface/render_messages.hpp"
#include "omarchy/plugin_runtime/surface/render_request_table.hpp"

#include <array>
#include <cstddef>
#include <cstdint>

using namespace omarchy::plugin_runtime::surface;

int main() {
  const auto offer = software_profile_offer();
  require(offer.full_frame_only && !offer.shader_effects && !offer.particles,
          "software limitations were silently broadened");
  constexpr std::array<std::uint32_t, 2> supported{9, kSoftwareProfileVersion};
  const auto selection = select_software_profile(supported);
  require(selection && selection->version == kSoftwareProfileVersion &&
              selection->pixel_format == kRgba8888Premultiplied,
          "supported profile negotiation failed");
  constexpr std::array<std::uint32_t, 2> unsupported{2, 3};
  require(!select_software_profile(unsupported),
          "unsupported profile silently downgraded");

  namespace wire = omarchy::plugin::wire;
  const auto schema = render_role_schema();
  const std::array schemas{schema};
  const wire::RoleSchemaRegistryView registry(schemas);
  require(registry.validate() == wire::FatalReason::none,
          "render schema rejected by B3");
  const auto *allocation_rule = wire::find_message(
      schema, static_cast<std::uint16_t>(RenderMessageType::surface_allocate));
  require(allocation_rule &&
              allocation_rule->semantic == wire::MessageSemantic::request &&
              allocation_rule->correlation == wire::CorrelationRule::nonzero &&
              render_descriptor_count(allocation_rule->message_type) == 1,
          "surface allocation descriptor contract changed");
  const auto *frame_rule = wire::find_message(
      schema, static_cast<std::uint16_t>(RenderMessageType::frame_ready));
  require(frame_rule && frame_rule->semantic == wire::MessageSemantic::event &&
              frame_rule->correlation == wire::CorrelationRule::zero &&
              render_descriptor_count(frame_rule->message_type) == 0,
          "frame-ready authority contract changed");

  const auto offer_bytes = encode_profile_offer(offer);
  require(offer_bytes[0] == std::byte{0} && offer_bytes[3] == std::byte{1} &&
              offer_bytes[15] == std::byte{3},
          "profile offer network golden changed");
  ProfileOffer decoded_offer{};
  require(decode_profile_offer(offer_bytes, decoded_offer) &&
              decoded_offer.version == offer.version,
          "profile offer round trip failed");
  auto bad_offer = offer_bytes;
  bad_offer[15] = std::byte{7};
  require(!decode_profile_offer(bad_offer, decoded_offer),
          "unknown profile flags accepted");

  const auto allocation =
      make_allocation({.id = 22, .generation = 3}, 8, 4, 8, 4, 1, 1, 4096);
  require(allocation.has_value(), "allocation fixture failed");
  const auto allocation_bytes = encode_surface_allocation(*allocation);
  TrustedAllocation decoded_allocation{};
  require(
      decode_surface_allocation(allocation_bytes, 4096, decoded_allocation) &&
          decoded_allocation == *allocation,
      "surface allocation round trip failed");
  auto bad_allocation = allocation_bytes;
  bad_allocation[63] = std::byte{1};
  require(!decode_surface_allocation(bad_allocation, 4096, decoded_allocation),
          "surface allocation reserved field accepted");

  const FrameReady frame{.surface = allocation->surface,
                         .slot = 1,
                         .slot_sequence = 4,
                         .frame_sequence = 9};
  const auto frame_bytes = encode_frame_ready(frame);
  FrameReady decoded_frame{};
  require(decode_frame_ready(frame_bytes, decoded_frame) &&
              decoded_frame.surface == frame.surface &&
              decoded_frame.slot == frame.slot &&
              decoded_frame.slot_sequence == frame.slot_sequence &&
              decoded_frame.frame_sequence == frame.frame_sequence,
          "frame-ready round trip failed");

  const InputEvent input{.surface = allocation->surface,
                         .sequence = 10,
                         .kind = InputKind::pointer_motion,
                         .x_q16 = 1U << 16,
                         .y_q16 = 2U << 16,
                         .delta_x_q16 = -(1 << 16),
                         .delta_y_q16 = 1 << 16,
                         .code = 0,
                         .state = 0,
                         .active_touch_points = 0};
  const auto input_bytes = encode_input_event(input);
  InputEvent decoded_input{};
  require(decode_input_event(input_bytes, decoded_input) &&
              decoded_input.delta_x_q16 == input.delta_x_q16 &&
              decoded_input.kind == input.kind,
          "input event round trip failed");
  auto bad_input = input_bytes;
  bad_input[27] = std::byte{99};
  require(!decode_input_event(bad_input, decoded_input),
          "unknown wire input kind accepted");

  const FocusEvent focus{
      .surface = allocation->surface, .sequence = 11, .focused = true};
  const auto focus_bytes = encode_focus_event(focus);
  FocusEvent decoded_focus{};
  require(decode_focus_event(focus_bytes, decoded_focus) &&
              decoded_focus.focused,
          "focus event round trip failed");
  auto bad_focus = focus_bytes;
  bad_focus[31] = std::byte{1};
  require(!decode_focus_event(bad_focus, decoded_focus),
          "focus reserved byte accepted");

  const RenderTypedError error{
      .reason = RenderErrorReason::invalid_allocation,
      .failed_message_type =
          static_cast<std::uint16_t>(RenderMessageType::surface_allocate),
      .surface = allocation->surface};
  const auto error_bytes = encode_render_error(error);
  RenderTypedError decoded_error{};
  require(decode_render_error(error_bytes, decoded_error) &&
              decoded_error.reason == error.reason,
          "render typed error round trip failed");
  auto nonrequest_error = error_bytes;
  nonrequest_error[2] = std::byte{0x20};
  nonrequest_error[3] = std::byte{0x20};
  require(!decode_render_error(nonrequest_error, decoded_error),
          "typed error named a non-request message");

  RenderRequestTable<2> pending;
  require(pending.begin(RenderMessageType::profile_offer, 55) ==
                  RenderPairResult::accepted &&
              pending.begin(RenderMessageType::surface_allocate, 56,
                            allocation->surface) == RenderPairResult::accepted,
          "valid render requests were not recorded");
  require(pending.begin(RenderMessageType::profile_offer, 55) ==
                  RenderPairResult::duplicate_correlation &&
              pending.begin(RenderMessageType::profile_offer, 57) ==
                  RenderPairResult::capacity_exhausted &&
              pending.begin(RenderMessageType::profile_offer, 0) ==
                  RenderPairResult::zero_correlation &&
              pending.begin(RenderMessageType::surface_allocated, 57,
                            allocation->surface) ==
                  RenderPairResult::invalid_request &&
              pending.size() == 2,
          "render pending-table bounds changed");
  require(
      pending.validate_terminal(RenderMessageType::surface_allocated, 55) ==
              RenderPairResult::mismatched_terminal &&
          pending.validate_terminal(RenderMessageType::profile_select, 56) ==
              RenderPairResult::mismatched_terminal &&
          pending.size() == 2,
      "crossed render terminals consumed pending requests");
  require(pending.validate_terminal(
              RenderMessageType::surface_allocated, 56,
              {.id = allocation->surface.id, .generation = 99}) ==
                  RenderPairResult::mismatched_surface &&
              pending.size() == 2,
          "wrong-surface terminal consumed a pending request");
  const RenderTypedError wrong_error{
      .reason = RenderErrorReason::unsupported_profile,
      .failed_message_type =
          static_cast<std::uint16_t>(RenderMessageType::profile_offer),
      .surface = {}};
  require(pending.validate_error(wrong_error, 56) ==
                  RenderPairResult::mismatched_terminal &&
              pending.size() == 2,
          "error for another request consumed a pending request");
  require(pending.validate_terminal(RenderMessageType::profile_select, 55) ==
                  RenderPairResult::accepted &&
              pending.complete(55) == RenderPairResult::accepted &&
              pending.validate_error(error, 56) == RenderPairResult::accepted &&
              pending.complete(56) == RenderPairResult::accepted &&
              pending.size() == 0,
          "exact render terminal pairing failed");
  require(pending.complete(56) == RenderPairResult::unknown_correlation,
          "completed render request was retired twice");

  wire::SelectedEndpointState<4> endpoint(
      wire::EndpointRole::render, kRenderRoleVersion, 7,
      wire::payload_cap(wire::EndpointRole::render), 4, registry);
  wire::PacketView offer_packet{
      .header = {.endpoint_role = wire::EndpointRole::render,
                 .message_type = static_cast<std::uint16_t>(
                     RenderMessageType::profile_offer),
                 .role_protocol_version = kRenderRoleVersion,
                 .payload_length = offer_bytes.size(),
                 .launch_generation = 7,
                 .correlation_id = 55},
      .payload = offer_bytes};
  require(
      endpoint.accept(offer_packet, wire::Direction::host_to_worker).action ==
          wire::SessionAction::request_admitted,
      "B3 rejected B4 profile request");
  RenderRequestTable<4> endpoint_pending;
  require(endpoint_pending.begin(RenderMessageType::profile_offer, 55) ==
              RenderPairResult::accepted,
          "render pairing adapter rejected B3 request");
  const auto selection_bytes = encode_profile_selection(*selection);
  wire::PacketView selection_packet{
      .header = {.endpoint_role = wire::EndpointRole::render,
                 .message_type = static_cast<std::uint16_t>(
                     RenderMessageType::profile_select),
                 .role_protocol_version = kRenderRoleVersion,
                 .payload_length = selection_bytes.size(),
                 .launch_generation = 7,
                 .correlation_id = 55},
      .payload = selection_bytes};
  require(endpoint_pending.validate_terminal(RenderMessageType::profile_select,
                                             55) == RenderPairResult::accepted,
          "render pairing adapter rejected exact terminal before B3");
  require(endpoint.accept(selection_packet, wire::Direction::worker_to_host)
                  .action == wire::SessionAction::terminal_received,
          "B3 rejected B4 profile terminal");
  require(endpoint_pending.complete(55) == RenderPairResult::accepted,
          "render pairing adapter did not retire accepted B3 terminal");
}
