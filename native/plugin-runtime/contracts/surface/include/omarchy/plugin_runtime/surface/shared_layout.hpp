#pragma once

#include "omarchy/plugin_runtime/surface/profile.hpp"

#include <array>
#include <cstddef>
#include <cstdint>
#include <optional>
#include <span>

namespace omarchy::plugin_runtime::surface {

inline constexpr std::uint64_t kSlotHeaderSize = 128;
inline constexpr std::uint64_t kSlotPixelOffset = 4096;
inline constexpr std::uint32_t kSlotCount = 2;

struct SurfaceKey {
  std::uint64_t id;
  std::uint64_t generation;

  constexpr bool operator==(const SurfaceKey &) const = default;
};

struct TrustedAllocation {
  SurfaceKey surface;
  std::uint32_t logical_width;
  std::uint32_t logical_height;
  std::uint32_t pixel_width;
  std::uint32_t pixel_height;
  std::uint32_t dpr_numerator;
  std::uint32_t dpr_denominator;
  std::uint32_t stride;
  std::uint32_t pixel_format;
  std::uint64_t frame_bytes;
  std::uint64_t page_size;
  std::uint64_t slot_extent;
  std::uint64_t mapping_bytes;

  constexpr bool operator==(const TrustedAllocation &) const = default;
};

struct DecodedSlotHeader {
  std::uint64_t sequence;
  std::uint64_t frame_sequence;
  TrustedAllocation allocation;
  std::uint32_t damage_count;
};

[[nodiscard]] std::optional<TrustedAllocation>
make_allocation(SurfaceKey surface, std::uint32_t logical_width,
                std::uint32_t logical_height, std::uint32_t pixel_width,
                std::uint32_t pixel_height, std::uint32_t dpr_numerator,
                std::uint32_t dpr_denominator, std::uint64_t page_size);

[[nodiscard]] std::optional<std::uint64_t>
slot_base(const TrustedAllocation &allocation, std::uint32_t slot);

[[nodiscard]] bool
allocation_is_consistent(const TrustedAllocation &allocation);

[[nodiscard]] bool encode_slot_header(std::span<std::byte> destination,
                                      const TrustedAllocation &allocation,
                                      std::uint64_t sequence,
                                      std::uint64_t frame_sequence);

[[nodiscard]] std::optional<DecodedSlotHeader>
decode_slot_header(std::span<const std::byte> source);

[[nodiscard]] bool
header_matches_allocation(const DecodedSlotHeader &header,
                          const TrustedAllocation &allocation);

} // namespace omarchy::plugin_runtime::surface
