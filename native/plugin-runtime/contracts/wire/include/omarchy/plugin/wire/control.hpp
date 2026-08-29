#pragma once

#include <cstdint>

namespace omarchy::plugin::wire {

inline constexpr std::uint16_t kPermissionSnapshotMessage = 0x0100;
inline constexpr std::uint16_t kPermissionSnapshotAcceptedMessage = 0x0101;
inline constexpr std::uint16_t kSurfaceSelectionMessage = 0x0102;
inline constexpr std::uint16_t kSurfaceSelectionAcceptedMessage = 0x0103;

} // namespace omarchy::plugin::wire
