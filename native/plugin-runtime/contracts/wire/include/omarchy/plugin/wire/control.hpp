#pragma once

#include "omarchy/plugin/wire/surface_name.hpp"

#include <cstddef>
#include <cstdint>
#include <optional>
#include <span>
#include <string>
#include <utility>
#include <vector>

namespace omarchy::plugin::wire {

inline constexpr std::uint16_t kPermissionSnapshotMessage = 0x0100;
inline constexpr std::uint16_t kPermissionSnapshotAcceptedMessage = 0x0101;
inline constexpr std::uint16_t kSurfaceSelectionMessage = 0x0102;
inline constexpr std::uint16_t kSurfaceSelectionAcceptedMessage = 0x0103;
inline constexpr std::uint16_t kSurfaceOpenMessage = 0x0106;
inline constexpr std::uint16_t kSurfaceOpenAcceptedMessage = 0x0107;

struct SurfaceBinding {
  std::uint64_t id = 0;
  std::uint64_t generation = 0;
  std::string surface;
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
  return SurfaceBinding{.id = index + 1,
                        .generation = generation,
                        .surface = std::string(surface)};
}

inline std::vector<std::byte>
encode_surface_binding(const SurfaceBinding &binding) {
  if (binding.id == 0 || binding.generation == 0 ||
      !valid_surface_name(binding.surface))
    return {};
  std::vector<std::byte> output(17 + binding.surface.size());
  for (std::size_t index = 0; index < 8; ++index) {
    output[index] =
        std::byte((binding.id >> ((7 - index) * 8)) & 0xffU);
    output[8 + index] =
        std::byte((binding.generation >> ((7 - index) * 8)) & 0xffU);
  }
  output[16] = std::byte(binding.surface.size());
  for (std::size_t index = 0; index < binding.surface.size(); ++index)
    output[17 + index] = std::byte(binding.surface[index]);
  return output;
}

inline bool decode_surface_binding(std::span<const std::byte> input,
                                   SurfaceBinding &binding) {
  if (input.size() < 18 || input.size() !=
                               17 + std::to_integer<std::size_t>(input[16]))
    return false;
  SurfaceBinding decoded;
  for (std::size_t index = 0; index < 8; ++index) {
    decoded.id = (decoded.id << 8) |
                 std::to_integer<std::uint8_t>(input[index]);
    decoded.generation =
        (decoded.generation << 8) |
        std::to_integer<std::uint8_t>(input[8 + index]);
  }
  if (decoded.id == 0 || decoded.generation == 0)
    return false;
  decoded.surface.reserve(input.size() - 17);
  for (std::size_t index = 17; index < input.size(); ++index) {
    decoded.surface.push_back(
        static_cast<char>(std::to_integer<unsigned char>(input[index])));
  }
  if (!valid_surface_name(decoded.surface))
    return false;
  binding = std::move(decoded);
  return true;
}

} // namespace omarchy::plugin::wire
