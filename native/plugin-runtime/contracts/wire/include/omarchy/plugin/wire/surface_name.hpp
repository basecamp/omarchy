#pragma once

#include <cstddef>
#include <string_view>

namespace omarchy::plugin::wire {

inline constexpr std::size_t kMaximumSurfaceNameBytes = 64;
inline constexpr std::size_t kMaximumPluginSurfaces = 8;

[[nodiscard]] inline constexpr bool
valid_surface_name(std::string_view value) noexcept {
  if (value.empty() || value.size() > kMaximumSurfaceNameBytes)
    return false;
  for (const unsigned char character : value) {
    if (!((character >= 'a' && character <= 'z') ||
          (character >= 'A' && character <= 'Z') ||
          (character >= '0' && character <= '9') || character == '-' ||
          character == '_'))
      return false;
  }
  return true;
}

} // namespace omarchy::plugin::wire
