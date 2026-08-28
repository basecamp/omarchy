#include "omarchy/plugin_runtime/surface/render_messages.hpp"

#include <algorithm>
#include <bit>
#include <cstring>

namespace omarchy::plugin_runtime::surface {
namespace {

namespace wire = omarchy::plugin::wire;

constexpr std::uint32_t kFullFrameOnly = 1U << 0U;
constexpr std::uint32_t kSoftwareSceneGraph = 1U << 1U;
constexpr std::uint32_t kRequiredProfileFlags =
    kFullFrameOnly | kSoftwareSceneGraph;

constexpr std::array<wire::MessageRule, 10> kWireRules{{
    {static_cast<std::uint16_t>(RenderMessageType::profile_offer),
     wire::DirectionMask::host_to_worker, wire::CorrelationRule::nonzero,
     wire::MessageSemantic::request, 24, 24},
    {static_cast<std::uint16_t>(RenderMessageType::profile_select),
     wire::DirectionMask::worker_to_host, wire::CorrelationRule::nonzero,
     wire::MessageSemantic::terminal, 8, 8},
    {static_cast<std::uint16_t>(RenderMessageType::surface_allocate),
     wire::DirectionMask::host_to_worker, wire::CorrelationRule::nonzero,
     wire::MessageSemantic::request, 96, 96},
    {static_cast<std::uint16_t>(RenderMessageType::surface_allocated),
     wire::DirectionMask::worker_to_host, wire::CorrelationRule::nonzero,
     wire::MessageSemantic::terminal, 16, 16},
    {static_cast<std::uint16_t>(RenderMessageType::surface_release),
     wire::DirectionMask::host_to_worker, wire::CorrelationRule::zero,
     wire::MessageSemantic::one_way, 16, 16},
    {static_cast<std::uint16_t>(RenderMessageType::surface_suspend),
     wire::DirectionMask::host_to_worker, wire::CorrelationRule::zero,
     wire::MessageSemantic::one_way, 16, 16},
    {static_cast<std::uint16_t>(RenderMessageType::surface_resume),
     wire::DirectionMask::host_to_worker, wire::CorrelationRule::zero,
     wire::MessageSemantic::one_way, 16, 16},
    {static_cast<std::uint16_t>(RenderMessageType::frame_ready),
     wire::DirectionMask::worker_to_host, wire::CorrelationRule::zero,
     wire::MessageSemantic::event, 40, 40},
    {static_cast<std::uint16_t>(RenderMessageType::input),
     wire::DirectionMask::host_to_worker, wire::CorrelationRule::zero,
     wire::MessageSemantic::one_way, 56, 56},
    {static_cast<std::uint16_t>(RenderMessageType::focus),
     wire::DirectionMask::host_to_worker, wire::CorrelationRule::zero,
     wire::MessageSemantic::one_way, 32, 32},
}};

constexpr std::array<DescriptorRule, 10> kDescriptorRules{{
    {static_cast<std::uint16_t>(RenderMessageType::profile_offer), 0},
    {static_cast<std::uint16_t>(RenderMessageType::profile_select), 0},
    {static_cast<std::uint16_t>(RenderMessageType::surface_allocate), 1},
    {static_cast<std::uint16_t>(RenderMessageType::surface_allocated), 0},
    {static_cast<std::uint16_t>(RenderMessageType::surface_release), 0},
    {static_cast<std::uint16_t>(RenderMessageType::surface_suspend), 0},
    {static_cast<std::uint16_t>(RenderMessageType::surface_resume), 0},
    {static_cast<std::uint16_t>(RenderMessageType::frame_ready), 0},
    {static_cast<std::uint16_t>(RenderMessageType::input), 0},
    {static_cast<std::uint16_t>(RenderMessageType::focus), 0},
}};

constexpr std::uint32_t swap32(std::uint32_t value) {
  return ((value & 0x000000ffU) << 24U) | ((value & 0x0000ff00U) << 8U) |
         ((value & 0x00ff0000U) >> 8U) | ((value & 0xff000000U) >> 24U);
}

constexpr std::uint64_t swap64(std::uint64_t value) {
  return (static_cast<std::uint64_t>(swap32(static_cast<std::uint32_t>(value)))
          << 32U) |
         swap32(static_cast<std::uint32_t>(value >> 32U));
}

constexpr std::uint16_t swap16(std::uint16_t value) {
  return static_cast<std::uint16_t>((value << 8U) | (value >> 8U));
}

template <typename T> constexpr T network(T value) {
  if constexpr (std::endian::native == std::endian::big) {
    return value;
  } else if constexpr (sizeof(T) == 2) {
    return static_cast<T>(swap16(static_cast<std::uint16_t>(value)));
  } else if constexpr (sizeof(T) == 4) {
    return static_cast<T>(swap32(static_cast<std::uint32_t>(value)));
  } else {
    return static_cast<T>(swap64(static_cast<std::uint64_t>(value)));
  }
}

template <typename T>
void put(std::span<std::byte> output, std::size_t offset, T value) {
  const T encoded = network(value);
  std::memcpy(output.data() + offset, &encoded, sizeof(encoded));
}

template <typename T>
T get(std::span<const std::byte> input, std::size_t offset) {
  T encoded{};
  std::memcpy(&encoded, input.data() + offset, sizeof(encoded));
  return network(encoded);
}

template <std::size_t Size>
bool exact_zero_tail(std::span<const std::byte> bytes, std::size_t offset) {
  return bytes.size() == Size &&
         std::ranges::all_of(bytes.subspan(offset), [](std::byte value) {
           return value == std::byte{0};
         });
}

bool valid_render_error(RenderErrorReason reason) {
  switch (reason) {
  case RenderErrorReason::unsupported_profile:
  case RenderErrorReason::invalid_allocation:
  case RenderErrorReason::resource_limit:
  case RenderErrorReason::stale_surface:
    return true;
  }
  return false;
}

} // namespace

std::span<const wire::MessageRule> render_wire_rules() { return kWireRules; }

wire::RoleSchemaView render_role_schema() {
  return {.role = wire::EndpointRole::render,
          .version = kRenderRoleVersion,
          .messages = kWireRules,
          .typed_error_minimum_payload = 24,
          .typed_error_maximum_payload = 24};
}

std::optional<std::uint8_t>
render_descriptor_count(std::uint16_t message_type) {
  const auto match = std::ranges::find_if(
      kDescriptorRules, [message_type](const DescriptorRule &rule) {
        return rule.message_type == message_type;
      });
  if (match == kDescriptorRules.end()) {
    return std::nullopt;
  }
  return match->exact_count;
}

std::array<std::byte, 24> encode_profile_offer(const ProfileOffer &payload) {
  std::array<std::byte, 24> output{};
  put<std::uint32_t>(output, 0, payload.version);
  put<std::uint32_t>(output, 4, kRgba8888Premultiplied);
  put<std::uint32_t>(output, 8, payload.maximum_pixel_dimension);
  put<std::uint32_t>(output, 12, kRequiredProfileFlags);
  put<std::uint64_t>(output, 16, payload.maximum_frame_bytes);
  return output;
}

bool decode_profile_offer(std::span<const std::byte> bytes,
                          ProfileOffer &output) {
  if (bytes.size() != 24 ||
      get<std::uint32_t>(bytes, 4) != kRgba8888Premultiplied ||
      get<std::uint32_t>(bytes, 12) != kRequiredProfileFlags) {
    return false;
  }
  output = {.version = get<std::uint32_t>(bytes, 0),
            .maximum_pixel_dimension = get<std::uint32_t>(bytes, 8),
            .maximum_frame_bytes = get<std::uint64_t>(bytes, 16),
            .full_frame_only = true,
            .shader_effects = false,
            .particles = false};
  return output.version == kSoftwareProfileVersion &&
         output.maximum_pixel_dimension <= kMaximumPixelDimension &&
         output.maximum_pixel_dimension != 0 &&
         output.maximum_frame_bytes <= kMaximumFrameBytes &&
         output.maximum_frame_bytes != 0;
}

std::array<std::byte, 8>
encode_profile_selection(const ProfileSelection &payload) {
  std::array<std::byte, 8> output{};
  put<std::uint32_t>(output, 0, payload.version);
  put<std::uint32_t>(output, 4, payload.pixel_format);
  return output;
}

bool decode_profile_selection(std::span<const std::byte> bytes,
                              ProfileSelection &output) {
  if (bytes.size() != 8) {
    return false;
  }
  output = {.version = get<std::uint32_t>(bytes, 0),
            .pixel_format = get<std::uint32_t>(bytes, 4)};
  return output.version == kSoftwareProfileVersion &&
         output.pixel_format == kRgba8888Premultiplied;
}

std::array<std::byte, 96>
encode_surface_allocation(const TrustedAllocation &allocation) {
  std::array<std::byte, 96> output{};
  put<std::uint64_t>(output, 0, allocation.surface.id);
  put<std::uint64_t>(output, 8, allocation.surface.generation);
  put<std::uint32_t>(output, 16, kSoftwareProfileVersion);
  put<std::uint32_t>(output, 20, allocation.pixel_format);
  put<std::uint32_t>(output, 24, allocation.logical_width);
  put<std::uint32_t>(output, 28, allocation.logical_height);
  put<std::uint32_t>(output, 32, allocation.pixel_width);
  put<std::uint32_t>(output, 36, allocation.pixel_height);
  put<std::uint32_t>(output, 40, allocation.dpr_numerator);
  put<std::uint32_t>(output, 44, allocation.dpr_denominator);
  put<std::uint32_t>(output, 48, allocation.stride);
  put<std::uint32_t>(output, 52, kSlotCount);
  put<std::uint32_t>(output, 56, static_cast<std::uint32_t>(kSlotHeaderSize));
  put<std::uint64_t>(output, 64, allocation.frame_bytes);
  put<std::uint64_t>(output, 72, kSlotPixelOffset);
  put<std::uint64_t>(output, 80, allocation.slot_extent);
  put<std::uint64_t>(output, 88, allocation.mapping_bytes);
  return output;
}

bool decode_surface_allocation(std::span<const std::byte> bytes,
                               std::uint64_t trusted_page_size,
                               TrustedAllocation &output) {
  if (bytes.size() != 96 ||
      get<std::uint32_t>(bytes, 16) != kSoftwareProfileVersion ||
      get<std::uint32_t>(bytes, 20) != kRgba8888Premultiplied ||
      get<std::uint32_t>(bytes, 52) != kSlotCount ||
      get<std::uint32_t>(bytes, 56) != kSlotHeaderSize ||
      get<std::uint32_t>(bytes, 60) != 0 ||
      get<std::uint64_t>(bytes, 72) != kSlotPixelOffset) {
    return false;
  }
  const auto allocation = make_allocation(
      {.id = get<std::uint64_t>(bytes, 0),
       .generation = get<std::uint64_t>(bytes, 8)},
      get<std::uint32_t>(bytes, 24), get<std::uint32_t>(bytes, 28),
      get<std::uint32_t>(bytes, 32), get<std::uint32_t>(bytes, 36),
      get<std::uint32_t>(bytes, 40), get<std::uint32_t>(bytes, 44),
      trusted_page_size);
  if (!allocation || allocation->stride != get<std::uint32_t>(bytes, 48) ||
      allocation->frame_bytes != get<std::uint64_t>(bytes, 64) ||
      allocation->slot_extent != get<std::uint64_t>(bytes, 80) ||
      allocation->mapping_bytes != get<std::uint64_t>(bytes, 88)) {
    return false;
  }
  output = *allocation;
  return true;
}

std::array<std::byte, 16> encode_surface_key(SurfaceKey surface) {
  std::array<std::byte, 16> output{};
  put<std::uint64_t>(output, 0, surface.id);
  put<std::uint64_t>(output, 8, surface.generation);
  return output;
}

bool decode_surface_key(std::span<const std::byte> bytes, SurfaceKey &output) {
  if (bytes.size() != 16) {
    return false;
  }
  output = {.id = get<std::uint64_t>(bytes, 0),
            .generation = get<std::uint64_t>(bytes, 8)};
  return output.id != 0 && output.generation != 0;
}

std::array<std::byte, 40> encode_frame_ready(const FrameReady &payload) {
  std::array<std::byte, 40> output{};
  put<std::uint64_t>(output, 0, payload.surface.id);
  put<std::uint64_t>(output, 8, payload.surface.generation);
  put<std::uint32_t>(output, 16, payload.slot);
  put<std::uint64_t>(output, 24, payload.slot_sequence);
  put<std::uint64_t>(output, 32, payload.frame_sequence);
  return output;
}

bool decode_frame_ready(std::span<const std::byte> bytes, FrameReady &output) {
  if (bytes.size() != 40 || get<std::uint32_t>(bytes, 20) != 0) {
    return false;
  }
  output = {.surface = {.id = get<std::uint64_t>(bytes, 0),
                        .generation = get<std::uint64_t>(bytes, 8)},
            .slot = get<std::uint32_t>(bytes, 16),
            .slot_sequence = get<std::uint64_t>(bytes, 24),
            .frame_sequence = get<std::uint64_t>(bytes, 32)};
  return output.surface.id != 0 && output.surface.generation != 0 &&
         output.slot < kSlotCount && output.slot_sequence >= 2 &&
         (output.slot_sequence & 1U) == 0 && output.frame_sequence != 0;
}

std::array<std::byte, 56> encode_input_event(const InputEvent &payload) {
  std::array<std::byte, 56> output{};
  put<std::uint64_t>(output, 0, payload.surface.id);
  put<std::uint64_t>(output, 8, payload.surface.generation);
  put<std::uint64_t>(output, 16, payload.sequence);
  put<std::uint32_t>(output, 24, static_cast<std::uint32_t>(payload.kind));
  put<std::uint32_t>(output, 28, payload.x_q16);
  put<std::uint32_t>(output, 32, payload.y_q16);
  put<std::uint32_t>(output, 36,
                     std::bit_cast<std::uint32_t>(payload.delta_x_q16));
  put<std::uint32_t>(output, 40,
                     std::bit_cast<std::uint32_t>(payload.delta_y_q16));
  put<std::uint32_t>(output, 44, payload.code);
  put<std::uint32_t>(output, 48, payload.state);
  put<std::uint32_t>(output, 52, payload.active_touch_points);
  return output;
}

bool decode_input_event(std::span<const std::byte> bytes, InputEvent &output) {
  if (bytes.size() != 56) {
    return false;
  }
  const auto kind = get<std::uint32_t>(bytes, 24);
  if (kind > static_cast<std::uint32_t>(InputKind::touch)) {
    return false;
  }
  output = {
      .surface = {.id = get<std::uint64_t>(bytes, 0),
                  .generation = get<std::uint64_t>(bytes, 8)},
      .sequence = get<std::uint64_t>(bytes, 16),
      .kind = static_cast<InputKind>(kind),
      .x_q16 = get<std::uint32_t>(bytes, 28),
      .y_q16 = get<std::uint32_t>(bytes, 32),
      .delta_x_q16 = std::bit_cast<std::int32_t>(get<std::uint32_t>(bytes, 36)),
      .delta_y_q16 = std::bit_cast<std::int32_t>(get<std::uint32_t>(bytes, 40)),
      .code = get<std::uint32_t>(bytes, 44),
      .state = get<std::uint32_t>(bytes, 48),
      .active_touch_points = get<std::uint32_t>(bytes, 52),
  };
  return output.surface.id != 0 && output.surface.generation != 0 &&
         output.sequence != 0;
}

std::array<std::byte, 32> encode_focus_event(const FocusEvent &payload) {
  std::array<std::byte, 32> output{};
  put<std::uint64_t>(output, 0, payload.surface.id);
  put<std::uint64_t>(output, 8, payload.surface.generation);
  put<std::uint64_t>(output, 16, payload.sequence);
  output[24] = payload.focused ? std::byte{1} : std::byte{0};
  return output;
}

bool decode_focus_event(std::span<const std::byte> bytes, FocusEvent &output) {
  if (bytes.size() != 32 ||
      (bytes[24] != std::byte{0} && bytes[24] != std::byte{1}) ||
      !exact_zero_tail<32>(bytes, 25)) {
    return false;
  }
  output = {.surface = {.id = get<std::uint64_t>(bytes, 0),
                        .generation = get<std::uint64_t>(bytes, 8)},
            .sequence = get<std::uint64_t>(bytes, 16),
            .focused = bytes[24] == std::byte{1}};
  return output.surface.id != 0 && output.surface.generation != 0 &&
         output.sequence != 0;
}

std::array<std::byte, 24> encode_render_error(const RenderTypedError &payload) {
  std::array<std::byte, 24> output{};
  put<std::uint16_t>(output, 0, static_cast<std::uint16_t>(payload.reason));
  put<std::uint16_t>(output, 2, payload.failed_message_type);
  put<std::uint64_t>(output, 8, payload.surface.id);
  put<std::uint64_t>(output, 16, payload.surface.generation);
  return output;
}

bool decode_render_error(std::span<const std::byte> bytes,
                         RenderTypedError &output) {
  if (bytes.size() != 24 || get<std::uint32_t>(bytes, 4) != 0) {
    return false;
  }
  output = {.reason =
                static_cast<RenderErrorReason>(get<std::uint16_t>(bytes, 0)),
            .failed_message_type = get<std::uint16_t>(bytes, 2),
            .surface = {.id = get<std::uint64_t>(bytes, 8),
                        .generation = get<std::uint64_t>(bytes, 16)}};
  const bool profile_error =
      output.reason == RenderErrorReason::unsupported_profile &&
      output.failed_message_type ==
          static_cast<std::uint16_t>(RenderMessageType::profile_offer) &&
      output.surface.id == 0 && output.surface.generation == 0;
  const bool surface_error =
      output.reason != RenderErrorReason::unsupported_profile &&
      output.failed_message_type ==
          static_cast<std::uint16_t>(RenderMessageType::surface_allocate) &&
      output.surface.id != 0 && output.surface.generation != 0;
  return valid_render_error(output.reason) && (profile_error || surface_error);
}

} // namespace omarchy::plugin_runtime::surface
