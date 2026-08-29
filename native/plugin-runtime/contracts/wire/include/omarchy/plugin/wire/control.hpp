#pragma once

#include <cstdint>
#include <cstddef>
#include <span>
#include <string>
#include <utility>
#include <vector>

namespace omarchy::plugin::wire {

inline constexpr std::uint16_t kPermissionSnapshotMessage = 0x0100;
inline constexpr std::uint16_t kPermissionSnapshotAcceptedMessage = 0x0101;
inline constexpr std::uint16_t kSurfaceSelectionMessage = 0x0102;
inline constexpr std::uint16_t kSurfaceSelectionAcceptedMessage = 0x0103;
inline constexpr std::uint16_t kSurfaceBindingMessage = 0x0104;
inline constexpr std::uint16_t kSurfaceBindingAcceptedMessage = 0x0105;

struct SurfaceBinding {
  std::uint64_t id = 0;
  std::uint64_t generation = 0;
  std::string surface;
};

inline std::vector<std::byte>
encode_surface_binding(const SurfaceBinding &binding) {
  if (binding.id == 0 || binding.generation == 0 || binding.surface.empty() ||
      binding.surface.size() > 64)
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
    const auto character = std::to_integer<unsigned char>(input[index]);
    if (!((character >= 'a' && character <= 'z') ||
          (character >= 'A' && character <= 'Z') ||
          (character >= '0' && character <= '9') || character == '-' ||
          character == '_'))
      return false;
    decoded.surface.push_back(static_cast<char>(character));
  }
  binding = std::move(decoded);
  return true;
}

} // namespace omarchy::plugin::wire
