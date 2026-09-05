#pragma once

#include <cstdint>
#include <optional>
#include <span>

namespace omarchy::plugin_runtime::surface {

inline constexpr std::uint32_t kSoftwareProfileVersion = 1;
inline constexpr std::uint32_t kRgba8888Premultiplied = 1;
inline constexpr std::uint32_t kMaximumPixelDimension = 4096;
inline constexpr std::uint64_t kMaximumFrameBytes = 64ULL * 1024ULL * 1024ULL;

struct ProfileOffer {
  std::uint32_t version;
  std::uint32_t maximum_pixel_dimension;
  std::uint64_t maximum_frame_bytes;
  bool full_frame_only;
  bool shader_effects;
  bool particles;
};

struct ProfileSelection {
  std::uint32_t version;
  std::uint32_t pixel_format;
};

[[nodiscard]] constexpr ProfileOffer software_profile_offer() {
  return {.version = kSoftwareProfileVersion,
          .maximum_pixel_dimension = kMaximumPixelDimension,
          .maximum_frame_bytes = kMaximumFrameBytes,
          .full_frame_only = true,
          .shader_effects = false,
          .particles = false};
}

[[nodiscard]] std::optional<ProfileSelection>
select_software_profile(std::span<const std::uint32_t> offered_versions);

} // namespace omarchy::plugin_runtime::surface
