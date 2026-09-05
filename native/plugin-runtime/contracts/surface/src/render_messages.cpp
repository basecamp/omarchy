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

constexpr std::array<wire::MessageRule, 11> kWireRules{{
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
    {static_cast<std::uint16_t>(RenderMessageType::input_regions),
     wire::DirectionMask::worker_to_host, wire::CorrelationRule::zero,
     wire::MessageSemantic::event, 288, 288},
    {static_cast<std::uint16_t>(RenderMessageType::input),
     wire::DirectionMask::host_to_worker, wire::CorrelationRule::zero,
     wire::MessageSemantic::one_way, 32, 204},
    {static_cast<std::uint16_t>(RenderMessageType::surface_intent),
     wire::DirectionMask::worker_to_host, wire::CorrelationRule::zero,
     wire::MessageSemantic::event, 176, 176},
}};

constexpr std::array<DescriptorRule, 11> kDescriptorRules{{
    {static_cast<std::uint16_t>(RenderMessageType::profile_offer), 0},
    {static_cast<std::uint16_t>(RenderMessageType::profile_select), 0},
    {static_cast<std::uint16_t>(RenderMessageType::surface_allocate), 1},
    {static_cast<std::uint16_t>(RenderMessageType::surface_allocated), 0},
    {static_cast<std::uint16_t>(RenderMessageType::surface_release), 0},
    {static_cast<std::uint16_t>(RenderMessageType::surface_suspend), 0},
    {static_cast<std::uint16_t>(RenderMessageType::surface_resume), 0},
    {static_cast<std::uint16_t>(RenderMessageType::frame_ready), 0},
    {static_cast<std::uint16_t>(RenderMessageType::input_regions), 0},
    {static_cast<std::uint16_t>(RenderMessageType::input), 0},
    {static_cast<std::uint16_t>(RenderMessageType::surface_intent), 0},
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

std::array<std::byte, 288>
encode_input_region_update(const InputRegionUpdate &payload) {
  std::array<std::byte, 288> output{};
  put<std::uint64_t>(output, 0, payload.surface.id);
  put<std::uint64_t>(output, 8, payload.surface.generation);
  put<std::uint64_t>(output, 16, payload.generation);
  put<std::uint32_t>(output, 24, payload.count);
  for (std::size_t index = 0;
       index < std::min<std::size_t>(payload.count, payload.regions.size());
       ++index) {
    const auto offset = 32 + index * 16;
    put<std::int32_t>(output, offset, payload.regions[index].x);
    put<std::int32_t>(output, offset + 4, payload.regions[index].y);
    put<std::uint32_t>(output, offset + 8, payload.regions[index].width);
    put<std::uint32_t>(output, offset + 12, payload.regions[index].height);
  }
  return output;
}

bool decode_input_region_update(std::span<const std::byte> bytes,
                                InputRegionUpdate &output) {
  if (bytes.size() != 288 || get<std::uint32_t>(bytes, 28) != 0)
    return false;
  InputRegionUpdate decoded{
      .surface = {.id = get<std::uint64_t>(bytes, 0),
                  .generation = get<std::uint64_t>(bytes, 8)},
      .generation = get<std::uint64_t>(bytes, 16),
      .count = get<std::uint32_t>(bytes, 24)};
  if (decoded.surface.id == 0 || decoded.surface.generation == 0 ||
      decoded.generation == 0 || decoded.count > decoded.regions.size())
    return false;
  for (std::size_t index = 0; index < decoded.regions.size(); ++index) {
    const auto offset = 32 + index * 16;
    const TransportedInputRegion region{
        .x = get<std::int32_t>(bytes, offset),
        .y = get<std::int32_t>(bytes, offset + 4),
        .width = get<std::uint32_t>(bytes, offset + 8),
        .height = get<std::uint32_t>(bytes, offset + 12)};
    if (index < decoded.count) {
      if (region.width == 0 || region.height == 0) return false;
      decoded.regions[index] = region;
    } else if (region != TransportedInputRegion{}) {
      return false;
    }
  }
  output = decoded;
  return true;
}

namespace {
enum class EncodedInputKind : std::uint32_t {
  pointer_motion = 1,
  pointer_button = 2,
  wheel = 3,
  key = 4,
  text_commit = 5,
  touch_frame = 6,
  focus_changed = 7,
  cancel = 8,
};

template <typename T>
void append(std::vector<std::byte> &output, T value) {
  const auto offset = output.size();
  output.resize(offset + sizeof(T));
  put<T>(output, offset, value);
}

void append_point(std::vector<std::byte> &output, InputPoint point) {
  append(output, point.x_q16);
  append(output, point.y_q16);
}
} // namespace

std::optional<std::vector<std::byte>>
encode_input_event(const InputEvent &payload) {
  if (payload.surface.id == 0 || payload.surface.generation == 0 ||
      payload.sequence == 0 ||
      validate_input_shape(payload.payload) != InputValidation::accepted)
    return std::nullopt;
  std::vector<std::byte> output(32);
  put<std::uint64_t>(output, 0, payload.surface.id);
  put<std::uint64_t>(output, 8, payload.surface.generation);
  put<std::uint64_t>(output, 16, payload.sequence);
  std::visit(
      [&](const auto &event) {
        using Event = std::decay_t<decltype(event)>;
        EncodedInputKind kind;
        if constexpr (std::is_same_v<Event, PointerMotion>) {
          kind = EncodedInputKind::pointer_motion;
          append_point(output, event.position);
          append(output, event.buttons);
          append(output, event.modifiers);
        } else if constexpr (std::is_same_v<Event, PointerButton>) {
          kind = EncodedInputKind::pointer_button;
          append_point(output, event.position);
          append(output, event.button);
          append(output, static_cast<std::uint32_t>(event.state));
          append(output, event.buttons);
          append(output, event.modifiers);
        } else if constexpr (std::is_same_v<Event, Wheel>) {
          kind = EncodedInputKind::wheel;
          append_point(output, event.position);
          append(output, std::bit_cast<std::uint32_t>(event.pixel_delta_x_q16));
          append(output, std::bit_cast<std::uint32_t>(event.pixel_delta_y_q16));
          append(output, std::bit_cast<std::uint32_t>(event.angle_delta_x));
          append(output, std::bit_cast<std::uint32_t>(event.angle_delta_y));
          append(output, static_cast<std::uint32_t>(event.phase));
          append(output, event.buttons);
          append(output, event.modifiers);
          append(output, static_cast<std::uint32_t>(event.inverted));
        } else if constexpr (std::is_same_v<Event, Key>) {
          kind = EncodedInputKind::key;
          append(output, event.key);
          append(output, event.native_scan_code);
          append(output, event.modifiers);
          append(output, static_cast<std::uint32_t>(event.state));
          append(output, static_cast<std::uint32_t>(event.auto_repeat));
          append(output, static_cast<std::uint32_t>(event.text.size()));
          output.insert(output.end(),
                        reinterpret_cast<const std::byte *>(event.text.data()),
                        reinterpret_cast<const std::byte *>(event.text.data() +
                                                            event.text.size()));
        } else if constexpr (std::is_same_v<Event, TextCommit>) {
          kind = EncodedInputKind::text_commit;
          append(output, std::bit_cast<std::uint32_t>(event.replacement_start));
          append(output, event.replacement_length);
          append(output, static_cast<std::uint32_t>(event.text.size()));
          output.insert(output.end(),
                        reinterpret_cast<const std::byte *>(event.text.data()),
                        reinterpret_cast<const std::byte *>(event.text.data() +
                                                            event.text.size()));
        } else if constexpr (std::is_same_v<Event, TouchFrame>) {
          kind = EncodedInputKind::touch_frame;
          append(output, static_cast<std::uint32_t>(event.phase));
          append(output, event.count);
          append(output, event.modifiers);
          for (std::size_t index = 0; index < event.count; ++index) {
            append(output, event.points[index].id);
            append(output,
                   static_cast<std::uint32_t>(event.points[index].state));
            append_point(output, event.points[index].position);
          }
        } else if constexpr (std::is_same_v<Event, FocusChanged>) {
          kind = EncodedInputKind::focus_changed;
          append(output, static_cast<std::uint32_t>(event.focused));
        } else {
          kind = EncodedInputKind::cancel;
        }
        put<std::uint32_t>(output, 24, static_cast<std::uint32_t>(kind));
      },
      payload.payload);
  return output;
}

bool decode_input_event(std::span<const std::byte> bytes, InputEvent &output) {
  if (bytes.size() < 32 || bytes.size() > 204 ||
      get<std::uint32_t>(bytes, 28) != 0)
    return false;
  InputEvent decoded{.surface = {.id = get<std::uint64_t>(bytes, 0),
                                 .generation = get<std::uint64_t>(bytes, 8)},
                     .sequence = get<std::uint64_t>(bytes, 16),
                     .payload = Cancel{}};
  if (decoded.surface.id == 0 || decoded.surface.generation == 0 ||
      decoded.sequence == 0)
    return false;
  const auto kind = static_cast<EncodedInputKind>(get<std::uint32_t>(bytes, 24));
  const auto u32 = [&](std::size_t offset) {
    return get<std::uint32_t>(bytes, offset);
  };
  const auto point = [&](std::size_t offset) {
    return InputPoint{.x_q16 = u32(offset), .y_q16 = u32(offset + 4)};
  };
  if (kind == EncodedInputKind::pointer_motion && bytes.size() == 48) {
    decoded.payload = PointerMotion{.position = point(32),
                                    .buttons = u32(40),
                                    .modifiers = u32(44)};
  } else if (kind == EncodedInputKind::pointer_button && bytes.size() == 56) {
    decoded.payload = PointerButton{
        .position = point(32),
        .button = u32(40),
        .state = static_cast<ButtonState>(u32(44)),
        .buttons = u32(48),
        .modifiers = u32(52)};
  } else if (kind == EncodedInputKind::wheel && bytes.size() == 72) {
    decoded.payload = Wheel{
        .position = point(32),
        .pixel_delta_x_q16 = std::bit_cast<std::int32_t>(u32(40)),
        .pixel_delta_y_q16 = std::bit_cast<std::int32_t>(u32(44)),
        .angle_delta_x = std::bit_cast<std::int32_t>(u32(48)),
        .angle_delta_y = std::bit_cast<std::int32_t>(u32(52)),
        .phase = static_cast<WheelPhase>(u32(56)),
        .buttons = u32(60),
        .modifiers = u32(64),
        .inverted = u32(68) == 1};
    if (u32(68) > 1)
      return false;
  } else if (kind == EncodedInputKind::key && bytes.size() >= 56 &&
             bytes.size() == 56 + u32(52) && u32(52) <= kMaximumInputTextBytes &&
             u32(48) <= 1) {
    decoded.payload = Key{
        .key = u32(32),
        .native_scan_code = u32(36),
        .modifiers = u32(40),
        .state = static_cast<ButtonState>(u32(44)),
        .auto_repeat = u32(48) == 1,
        .text = std::string(reinterpret_cast<const char *>(bytes.data() + 56),
                            u32(52))};
  } else if (kind == EncodedInputKind::text_commit && bytes.size() >= 44 &&
             bytes.size() == 44 + u32(40) && u32(40) <= kMaximumInputTextBytes) {
    decoded.payload = TextCommit{
        .text = std::string(reinterpret_cast<const char *>(bytes.data() + 44),
                            u32(40)),
        .replacement_start = std::bit_cast<std::int32_t>(u32(32)),
        .replacement_length = u32(36)};
  } else if (kind == EncodedInputKind::touch_frame && bytes.size() >= 44 &&
             u32(36) <= kMaximumTouchPoints &&
             bytes.size() == 44 + static_cast<std::size_t>(u32(36)) * 16) {
    TouchFrame frame{.phase = static_cast<TouchFramePhase>(u32(32)),
                     .count = u32(36),
                     .modifiers = u32(40)};
    for (std::size_t index = 0; index < frame.count; ++index) {
      const auto offset = 44 + index * 16;
      frame.points[index] = {
          .id = u32(offset),
          .state = static_cast<TouchPointState>(u32(offset + 4)),
          .position = point(offset + 8)};
    }
    decoded.payload = frame;
  } else if (kind == EncodedInputKind::focus_changed && bytes.size() == 36 &&
             u32(32) <= 1) {
    decoded.payload = FocusChanged{.focused = u32(32) == 1};
  } else if (kind == EncodedInputKind::cancel && bytes.size() == 32) {
    decoded.payload = Cancel{};
  } else {
    return false;
  }
  if (validate_input_shape(decoded.payload) != InputValidation::accepted)
    return false;
  output = std::move(decoded);
  return true;
}

std::array<std::byte, 176>
encode_surface_intent(const SurfaceIntentRequest &payload) {
  std::array<std::byte, 176> output{};
  if (payload.requested_output.size() > 128 ||
      std::ranges::any_of(payload.requested_output, [](const char value) {
        const auto byte = static_cast<unsigned char>(value);
        return byte < 0x21 || byte > 0x7e;
      }))
    return output;
  put<std::uint64_t>(output, 0, payload.source.id);
  put<std::uint64_t>(output, 8, payload.source.generation);
  put<std::uint64_t>(output, 16, payload.target.id);
  put<std::uint64_t>(output, 24, payload.target.generation);
  put<std::uint64_t>(output, 32, payload.input_sequence);
  put<std::uint32_t>(output, 40, static_cast<std::uint32_t>(payload.action));
  put<std::uint16_t>(output, 44,
                     static_cast<std::uint16_t>(payload.requested_output.size()));
  std::ranges::transform(payload.requested_output, output.begin() + 48,
                         [](const char value) {
                           return static_cast<std::byte>(value);
                         });
  return output;
}

bool decode_surface_intent(std::span<const std::byte> bytes,
                           SurfaceIntentRequest &output) {
  if (bytes.size() != 176 || get<std::uint16_t>(bytes, 46) != 0)
    return false;
  const auto output_size = get<std::uint16_t>(bytes, 44);
  if (output_size > 128 ||
      std::ranges::any_of(bytes.subspan(48, output_size), [](std::byte value) {
        const auto byte = std::to_integer<unsigned char>(value);
        return byte < 0x21 || byte > 0x7e;
      }) ||
      std::ranges::any_of(bytes.subspan(48 + output_size),
                          [](std::byte value) { return value != std::byte{0}; }))
    return false;
  const auto action =
      static_cast<SurfaceIntentAction>(get<std::uint32_t>(bytes, 40));
  if (action != SurfaceIntentAction::open &&
      action != SurfaceIntentAction::toggle &&
      action != SurfaceIntentAction::dismiss)
    return false;
  output = {
      .source = {.id = get<std::uint64_t>(bytes, 0),
                 .generation = get<std::uint64_t>(bytes, 8)},
      .target = {.id = get<std::uint64_t>(bytes, 16),
                 .generation = get<std::uint64_t>(bytes, 24)},
      .input_sequence = get<std::uint64_t>(bytes, 32),
      .action = action,
      .requested_output = std::string(
          reinterpret_cast<const char *>(bytes.data() + 48), output_size)};
  if (output.source.id == 0 || output.source.generation == 0 ||
      output.target.id == 0 || output.target.generation == 0)
    return false;
  if (action == SurfaceIntentAction::dismiss)
    return output.source == output.target && output.input_sequence == 0 &&
           output.requested_output.empty();
  return output.input_sequence != 0;
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
