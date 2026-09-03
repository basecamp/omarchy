#pragma once

#include "omarchy/plugin/wire/surface_name.hpp"

#include <cstddef>
#include <cstdint>
#include <optional>
#include <string_view>

namespace omarchy::plugin::wire {

inline constexpr std::uint16_t kPermissionSnapshotMessage = 0x0100;
inline constexpr std::uint16_t kPermissionSnapshotAcceptedMessage = 0x0101;
inline constexpr std::uint16_t kSettingsSnapshotMessage = 0x0102;
inline constexpr std::uint16_t kSettingsSnapshotAcceptedMessage = 0x0103;
inline constexpr std::uint16_t kSettingsUpdateMessage = 0x0104;
inline constexpr std::uint16_t kSettingsUpdateResultMessage = 0x0105;

struct SurfaceBinding {
  std::uint64_t id = 0;
  std::uint64_t generation = 0;
};

// Both trusted endpoints derive surface identity from the verified manifest's
// canonical surface_names order. Keeping that rule here prevents either side
// from acquiring an independent name-to-key assignment authority.
inline std::optional<SurfaceBinding>
manifest_surface_binding(std::string_view surface, std::size_t index,
                         std::uint64_t generation) {
  if (!valid_surface_name(surface) || index >= kMaximumPluginSurfaces ||
      generation == 0)
    return std::nullopt;
  return SurfaceBinding{.id = index + 1, .generation = generation};
}

} // namespace omarchy::plugin::wire
