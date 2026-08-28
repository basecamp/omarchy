#pragma once

#include "omarchy/plugin/wire/role_registry.hpp"
#include "omarchy/plugin_runtime/surface/input.hpp"
#include "omarchy/plugin_runtime/surface/profile.hpp"

#include <array>
#include <cstddef>
#include <cstdint>
#include <optional>
#include <span>

namespace omarchy::plugin_runtime::surface {

inline constexpr std::uint16_t kRenderRoleVersion = 1;

enum class RenderMessageType : std::uint16_t {
  profile_offer = 0x2000,
  profile_select = 0x2001,
  surface_allocate = 0x2010,
  surface_allocated = 0x2011,
  surface_release = 0x2012,
  surface_suspend = 0x2013,
  surface_resume = 0x2014,
  frame_ready = 0x2020,
  input = 0x2030,
  focus = 0x2031,
};

enum class RenderErrorReason : std::uint16_t {
  unsupported_profile = 1,
  invalid_allocation = 2,
  resource_limit = 3,
  stale_surface = 4,
};

struct DescriptorRule {
  std::uint16_t message_type;
  std::uint8_t exact_count;
};

struct FrameReady {
  SurfaceKey surface;
  std::uint32_t slot;
  std::uint64_t slot_sequence;
  std::uint64_t frame_sequence;
};

struct RenderTypedError {
  RenderErrorReason reason;
  std::uint16_t failed_message_type;
  SurfaceKey surface;
};

[[nodiscard]] std::span<const omarchy::plugin::wire::MessageRule>
render_wire_rules();
[[nodiscard]] omarchy::plugin::wire::RoleSchemaView render_role_schema();
[[nodiscard]] std::optional<std::uint8_t>
render_descriptor_count(std::uint16_t message_type);

[[nodiscard]] std::array<std::byte, 24>
encode_profile_offer(const ProfileOffer &payload);
[[nodiscard]] bool decode_profile_offer(std::span<const std::byte> bytes,
                                        ProfileOffer &output);
[[nodiscard]] std::array<std::byte, 8>
encode_profile_selection(const ProfileSelection &payload);
[[nodiscard]] bool decode_profile_selection(std::span<const std::byte> bytes,
                                            ProfileSelection &output);

[[nodiscard]] std::array<std::byte, 96>
encode_surface_allocation(const TrustedAllocation &allocation);
[[nodiscard]] bool decode_surface_allocation(std::span<const std::byte> bytes,
                                             std::uint64_t trusted_page_size,
                                             TrustedAllocation &output);
[[nodiscard]] std::array<std::byte, 16> encode_surface_key(SurfaceKey surface);
[[nodiscard]] bool decode_surface_key(std::span<const std::byte> bytes,
                                      SurfaceKey &output);

[[nodiscard]] std::array<std::byte, 40>
encode_frame_ready(const FrameReady &payload);
[[nodiscard]] bool decode_frame_ready(std::span<const std::byte> bytes,
                                      FrameReady &output);
[[nodiscard]] std::array<std::byte, 56>
encode_input_event(const InputEvent &payload);
[[nodiscard]] bool decode_input_event(std::span<const std::byte> bytes,
                                      InputEvent &output);
[[nodiscard]] std::array<std::byte, 32>
encode_focus_event(const FocusEvent &payload);
[[nodiscard]] bool decode_focus_event(std::span<const std::byte> bytes,
                                      FocusEvent &output);
[[nodiscard]] std::array<std::byte, 24>
encode_render_error(const RenderTypedError &payload);
[[nodiscard]] bool decode_render_error(std::span<const std::byte> bytes,
                                       RenderTypedError &output);

} // namespace omarchy::plugin_runtime::surface
