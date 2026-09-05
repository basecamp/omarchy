#include "test.hpp"

#include "omarchy/plugin/wire/state.hpp"
#include "omarchy/plugin_runtime/surface/profile.hpp"
#include "omarchy/plugin_runtime/surface/render_messages.hpp"

#include <array>
#include <cstddef>
#include <cstdint>
#include <string>

using namespace omarchy::plugin_runtime::surface;

int main() {
  require(valid_surface_name("barWidget") &&
              valid_surface_name(std::string(64, 'X')) &&
              !valid_surface_name("") &&
              !valid_surface_name("Panel.Widget") &&
              !valid_surface_name(std::string("bad\0name", 8)) &&
              !valid_surface_name(std::string(65, 'a')),
          "wire-safe surface-name contract changed");
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
          "render schema rejected by bridge profile");
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
  const auto *intent_rule = wire::find_message(
      schema, static_cast<std::uint16_t>(RenderMessageType::surface_intent));
  require(intent_rule &&
              intent_rule->directions == wire::DirectionMask::worker_to_host &&
              intent_rule->semantic == wire::MessageSemantic::event &&
              intent_rule->correlation == wire::CorrelationRule::zero &&
              render_descriptor_count(intent_rule->message_type) == 0,
          "surface intent authority contract changed");

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

  InputRegionUpdate regions{.surface = allocation->surface,
                            .generation = 3,
                            .regions = {{{.x = 20, .y = 30,
                                          .width = 80, .height = 40}}},
                            .count = 1};
  const auto region_bytes = encode_input_region_update(regions);
  InputRegionUpdate decoded_regions{};
  require(decode_input_region_update(region_bytes, decoded_regions) &&
              decoded_regions.surface == regions.surface &&
              decoded_regions.generation == 3 &&
              decoded_regions.count == 1 &&
              decoded_regions.regions[0] == regions.regions[0],
          "input-region update round trip failed");
  auto malformed_regions = region_bytes;
  malformed_regions[31] = std::byte{1};
  require(!decode_input_region_update(malformed_regions, decoded_regions),
          "input-region reserved field accepted");
  regions.count = kMaximumTransportedInputRegions + 1;
  require(!decode_input_region_update(encode_input_region_update(regions),
                                      decoded_regions),
          "excessive input-region count accepted");

  const InputEvent input{.surface = allocation->surface,
                         .sequence = 10,
                         .payload = PointerMotion{
                             .position = {.x_q16 = 1U << 16,
                                          .y_q16 = 2U << 16}}};
  const auto input_bytes = encode_input_event(input);
  InputEvent decoded_input{};
  require(input_bytes && decode_input_event(*input_bytes, decoded_input) &&
              decoded_input == input,
          "input event round trip failed");
  auto bad_input = input_bytes;
  (*bad_input)[27] = std::byte{99};
  require(!decode_input_event(*bad_input, decoded_input),
          "unknown wire input kind accepted");

  const InputEvent focus{.surface = allocation->surface,
                         .sequence = 11,
                         .payload = FocusChanged{.focused = true}};
  const auto focus_bytes = encode_input_event(focus);
  InputEvent decoded_focus{};
  require(focus_bytes && decode_input_event(*focus_bytes, decoded_focus) &&
              decoded_focus == focus,
          "focus event round trip failed");
  auto bad_focus = focus_bytes;
  (*bad_focus)[35] = std::byte{2};
  require(!decode_input_event(*bad_focus, decoded_focus),
          "focus reserved byte accepted");

  InputEvent key{.surface = allocation->surface,
                 .sequence = 12,
                 .payload = Key{.key = 65,
                                .native_scan_code = 30,
                                .state = ButtonState::pressed,
                                .text = "a"}};
  auto key_bytes = encode_input_event(key);
  require(key_bytes && decode_input_event(*key_bytes, decoded_input) &&
              decoded_input == key,
          "key/text event round trip failed");
  key_bytes->back() = std::byte{0xc0};
  require(!decode_input_event(*key_bytes, decoded_input),
          "malformed UTF-8 became a typed key event");
  std::get<Key>(key.payload).text = std::string("\xed\xa0\x80", 3);
  require(!encode_input_event(key),
          "surrogate UTF-8 was serialized");

  InputEvent invalid_mask{
      .surface = allocation->surface,
      .sequence = 13,
      .payload = PointerMotion{.position = {}, .buttons = 0x20}};
  require(!encode_input_event(invalid_mask),
          "unsupported pointer mask was serialized");
  auto malformed_mask = input_bytes;
  (*malformed_mask)[43] = std::byte{0x20};
  require(!decode_input_event(*malformed_mask, decoded_input),
          "unsupported pointer mask became a typed event");

  TouchFrame maximum{.phase = TouchFramePhase::begin,
                     .count = kMaximumTouchPoints};
  for (std::uint32_t index = 0; index < maximum.count; ++index)
    maximum.points[index] = {.id = index,
                             .state = TouchPointState::pressed,
                             .position = {index << 16, index << 16}};
  const InputEvent maximum_touch{.surface = allocation->surface,
                                 .sequence = 14,
                                 .payload = maximum};
  const auto maximum_bytes = encode_input_event(maximum_touch);
  require(maximum_bytes && maximum_bytes->size() == 204 &&
              decode_input_event(*maximum_bytes, decoded_input) &&
              decoded_input == maximum_touch,
          "maximum atomic touch frame was not representable");
  maximum.points[1].id = maximum.points[0].id;
  require(!encode_input_event({.surface = allocation->surface,
                               .sequence = 15,
                               .payload = maximum}),
          "duplicate touch IDs were serialized");

  const InputEvent invalid_replacement{
      .surface = allocation->surface,
      .sequence = 16,
      .payload = TextCommit{
          .text = "x",
          .replacement_start = kMaximumTextReplacementOffset + 1}};
  require(!encode_input_event(invalid_replacement),
          "oversized text replacement was serialized");

  const SurfaceIntentRequest intent{
      .source = allocation->surface,
      .target = {.id = 23, .generation = allocation->surface.generation},
      .input_sequence = 12,
      .action = SurfaceIntentAction::toggle,
      .requested_output = "DP-1"};
  const auto intent_bytes = encode_surface_intent(intent);
  SurfaceIntentRequest decoded_intent{};
  require(decode_surface_intent(intent_bytes, decoded_intent) &&
              decoded_intent == intent,
          "surface intent round trip failed");
  auto bad_intent = intent_bytes;
  bad_intent[47] = std::byte{1};
  require(!decode_surface_intent(bad_intent, decoded_intent),
          "surface intent reserved field accepted");
  bad_intent = intent_bytes;
  bad_intent[43] = std::byte{9};
  require(!decode_surface_intent(bad_intent, decoded_intent),
          "unknown surface intent action accepted");
  auto invalid_output_intent = intent;
  invalid_output_intent.requested_output = std::string(129, 'x');
  require(!decode_surface_intent(encode_surface_intent(invalid_output_intent),
                                 decoded_intent),
          "oversized surface output hint was serialized");
  const SurfaceIntentRequest dismiss_intent{
      .source = allocation->surface,
      .target = allocation->surface,
      .input_sequence = 0,
      .action = SurfaceIntentAction::dismiss,
      .requested_output = {}};
  const auto dismiss_bytes = encode_surface_intent(dismiss_intent);
  require(decode_surface_intent(dismiss_bytes, decoded_intent) &&
              decoded_intent == dismiss_intent,
          "gesture-free self-dismiss did not round trip");
  auto forged_dismiss = dismiss_bytes;
  forged_dismiss[32] = std::byte{1};
  require(!decode_surface_intent(forged_dismiss, decoded_intent),
          "self-dismiss accepted a forged gesture sequence");

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
      "bridge rejected render profile request");
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
  require(endpoint.accept(selection_packet, wire::Direction::worker_to_host)
                  .action == wire::SessionAction::terminal_received,
          "bridge rejected render profile terminal");
}
