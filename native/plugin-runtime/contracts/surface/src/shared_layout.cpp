#include "omarchy/plugin_runtime/surface/shared_layout.hpp"

#include "omarchy/plugin_runtime/surface/checked_math.hpp"

#include <algorithm>
#include <bit>
#include <cstring>
#include <limits>
#include <numeric>

namespace omarchy::plugin_runtime::surface {
namespace {

constexpr std::size_t kSequenceOffset = 0;
constexpr std::size_t kFrameSequenceOffset = 8;
constexpr std::size_t kSurfaceIdOffset = 16;
constexpr std::size_t kSurfaceGenerationOffset = 24;
constexpr std::size_t kProfileVersionOffset = 32;
constexpr std::size_t kHeaderSizeOffset = 36;
constexpr std::size_t kLogicalWidthOffset = 40;
constexpr std::size_t kLogicalHeightOffset = 44;
constexpr std::size_t kPixelWidthOffset = 48;
constexpr std::size_t kPixelHeightOffset = 52;
constexpr std::size_t kDprNumeratorOffset = 56;
constexpr std::size_t kDprDenominatorOffset = 60;
constexpr std::size_t kStrideOffset = 64;
constexpr std::size_t kPixelFormatOffset = 68;
constexpr std::size_t kDamageCountOffset = 72;
constexpr std::size_t kReservedOffset = 76;
constexpr std::size_t kPayloadLengthOffset = 80;
constexpr std::size_t kReservedTailOffset = 88;

constexpr std::uint32_t to_network32(std::uint32_t value) {
  if constexpr (std::endian::native == std::endian::little) {
    return ((value & 0x000000ffU) << 24U) | ((value & 0x0000ff00U) << 8U) |
           ((value & 0x00ff0000U) >> 8U) | ((value & 0xff000000U) >> 24U);
  }
  return value;
}

constexpr std::uint64_t to_network64(std::uint64_t value) {
  if constexpr (std::endian::native == std::endian::little) {
    return (static_cast<std::uint64_t>(
                to_network32(static_cast<std::uint32_t>(value)))
            << 32U) |
           to_network32(static_cast<std::uint32_t>(value >> 32U));
  }
  return value;
}

void put32(std::span<std::byte> output, std::size_t offset,
           std::uint32_t value) {
  const auto encoded = to_network32(value);
  std::memcpy(output.data() + offset, &encoded, sizeof(encoded));
}

void put64(std::span<std::byte> output, std::size_t offset,
           std::uint64_t value) {
  const auto encoded = to_network64(value);
  std::memcpy(output.data() + offset, &encoded, sizeof(encoded));
}

std::uint32_t get32(std::span<const std::byte> input, std::size_t offset) {
  std::uint32_t encoded = 0;
  std::memcpy(&encoded, input.data() + offset, sizeof(encoded));
  return to_network32(encoded);
}

std::uint64_t get64(std::span<const std::byte> input, std::size_t offset) {
  std::uint64_t encoded = 0;
  std::memcpy(&encoded, input.data() + offset, sizeof(encoded));
  return to_network64(encoded);
}

std::optional<std::uint32_t> expected_pixels(std::uint32_t logical,
                                             std::uint32_t numerator,
                                             std::uint32_t denominator) {
  const auto product = checked_multiply<std::uint64_t>(logical, numerator);
  if (!product) {
    return std::nullopt;
  }
  const auto rounded = checked_add(*product, std::uint64_t{denominator - 1});
  if (!rounded) {
    return std::nullopt;
  }
  return checked_cast<std::uint32_t>(*rounded / denominator);
}

} // namespace

std::optional<TrustedAllocation>
make_allocation(SurfaceKey surface, std::uint32_t logical_width,
                std::uint32_t logical_height, std::uint32_t pixel_width,
                std::uint32_t pixel_height, std::uint32_t dpr_numerator,
                std::uint32_t dpr_denominator, std::uint64_t page_size) {
  if (surface.id == 0 || surface.generation == 0 || logical_width == 0 ||
      logical_height == 0 || pixel_width == 0 || pixel_height == 0 ||
      logical_width > kMaximumPixelDimension ||
      logical_height > kMaximumPixelDimension ||
      pixel_width > kMaximumPixelDimension ||
      pixel_height > kMaximumPixelDimension || dpr_numerator == 0 ||
      dpr_denominator == 0 || std::gcd(dpr_numerator, dpr_denominator) != 1 ||
      page_size < alignof(std::uint64_t)) {
    return std::nullopt;
  }
  const auto expected_width =
      expected_pixels(logical_width, dpr_numerator, dpr_denominator);
  const auto expected_height =
      expected_pixels(logical_height, dpr_numerator, dpr_denominator);
  if (!expected_width || !expected_height || *expected_width != pixel_width ||
      *expected_height != pixel_height) {
    return std::nullopt;
  }
  const auto stride64 = checked_multiply<std::uint64_t>(pixel_width, 4);
  if (!stride64) {
    return std::nullopt;
  }
  const auto stride = checked_cast<std::uint32_t>(*stride64);
  const auto frame_bytes =
      checked_multiply<std::uint64_t>(*stride64, pixel_height);
  if (!stride || !frame_bytes || *frame_bytes > kMaximumFrameBytes) {
    return std::nullopt;
  }
  const auto slot_end = checked_add(kSlotPixelOffset, *frame_bytes);
  const auto extent =
      slot_end ? checked_align_up(*slot_end, page_size) : std::nullopt;
  const auto mapping =
      extent ? checked_multiply(*extent, std::uint64_t{kSlotCount})
             : std::nullopt;
  if (!extent || !mapping) {
    return std::nullopt;
  }
  return TrustedAllocation{
      .surface = surface,
      .logical_width = logical_width,
      .logical_height = logical_height,
      .pixel_width = pixel_width,
      .pixel_height = pixel_height,
      .dpr_numerator = dpr_numerator,
      .dpr_denominator = dpr_denominator,
      .stride = *stride,
      .pixel_format = kRgba8888Premultiplied,
      .frame_bytes = *frame_bytes,
      .page_size = page_size,
      .slot_extent = *extent,
      .mapping_bytes = *mapping,
  };
}

bool allocation_is_consistent(const TrustedAllocation &allocation) {
  const auto expected = make_allocation(
      allocation.surface, allocation.logical_width, allocation.logical_height,
      allocation.pixel_width, allocation.pixel_height, allocation.dpr_numerator,
      allocation.dpr_denominator, allocation.page_size);
  return expected && *expected == allocation;
}

std::optional<std::uint64_t> slot_base(const TrustedAllocation &allocation,
                                       std::uint32_t slot) {
  if (slot >= kSlotCount) {
    return std::nullopt;
  }
  return checked_multiply<std::uint64_t>(allocation.slot_extent, slot);
}

bool encode_slot_header(std::span<std::byte> destination,
                        const TrustedAllocation &allocation,
                        std::uint64_t sequence, std::uint64_t frame_sequence) {
  if (destination.size() < kSlotHeaderSize || sequence == 0 ||
      frame_sequence == 0) {
    return false;
  }
  std::ranges::fill(destination.first(kSlotHeaderSize), std::byte{0});
  std::memcpy(destination.data() + kSequenceOffset, &sequence,
              sizeof(sequence));
  put64(destination, kFrameSequenceOffset, frame_sequence);
  put64(destination, kSurfaceIdOffset, allocation.surface.id);
  put64(destination, kSurfaceGenerationOffset, allocation.surface.generation);
  put32(destination, kProfileVersionOffset, kSoftwareProfileVersion);
  put32(destination, kHeaderSizeOffset,
        static_cast<std::uint32_t>(kSlotHeaderSize));
  put32(destination, kLogicalWidthOffset, allocation.logical_width);
  put32(destination, kLogicalHeightOffset, allocation.logical_height);
  put32(destination, kPixelWidthOffset, allocation.pixel_width);
  put32(destination, kPixelHeightOffset, allocation.pixel_height);
  put32(destination, kDprNumeratorOffset, allocation.dpr_numerator);
  put32(destination, kDprDenominatorOffset, allocation.dpr_denominator);
  put32(destination, kStrideOffset, allocation.stride);
  put32(destination, kPixelFormatOffset, allocation.pixel_format);
  put32(destination, kDamageCountOffset, 0);
  put32(destination, kReservedOffset, 0);
  put64(destination, kPayloadLengthOffset, allocation.frame_bytes);
  return true;
}

std::optional<DecodedSlotHeader>
decode_slot_header(std::span<const std::byte> source) {
  if (source.size() < kSlotHeaderSize) {
    return std::nullopt;
  }
  std::uint64_t sequence = 0;
  std::memcpy(&sequence, source.data() + kSequenceOffset, sizeof(sequence));
  if (get32(source, kProfileVersionOffset) != kSoftwareProfileVersion ||
      get32(source, kHeaderSizeOffset) != kSlotHeaderSize ||
      get32(source, kReservedOffset) != 0 ||
      std::ranges::any_of(
          source.subspan(kReservedTailOffset,
                         kSlotHeaderSize - kReservedTailOffset),
          [](std::byte value) { return value != std::byte{0}; })) {
    return std::nullopt;
  }
  TrustedAllocation allocation{
      .surface = {.id = get64(source, kSurfaceIdOffset),
                  .generation = get64(source, kSurfaceGenerationOffset)},
      .logical_width = get32(source, kLogicalWidthOffset),
      .logical_height = get32(source, kLogicalHeightOffset),
      .pixel_width = get32(source, kPixelWidthOffset),
      .pixel_height = get32(source, kPixelHeightOffset),
      .dpr_numerator = get32(source, kDprNumeratorOffset),
      .dpr_denominator = get32(source, kDprDenominatorOffset),
      .stride = get32(source, kStrideOffset),
      .pixel_format = get32(source, kPixelFormatOffset),
      .frame_bytes = get64(source, kPayloadLengthOffset),
      .page_size = 0,
      .slot_extent = 0,
      .mapping_bytes = 0,
  };
  return DecodedSlotHeader{.sequence = sequence,
                           .frame_sequence =
                               get64(source, kFrameSequenceOffset),
                           .allocation = allocation,
                           .damage_count = get32(source, kDamageCountOffset)};
}

bool header_matches_allocation(const DecodedSlotHeader &header,
                               const TrustedAllocation &allocation) {
  const auto &candidate = header.allocation;
  return header.sequence != 0 && (header.sequence & 1U) == 0 &&
         header.frame_sequence != 0 && header.damage_count == 0 &&
         candidate.surface == allocation.surface &&
         candidate.logical_width == allocation.logical_width &&
         candidate.logical_height == allocation.logical_height &&
         candidate.pixel_width == allocation.pixel_width &&
         candidate.pixel_height == allocation.pixel_height &&
         candidate.dpr_numerator == allocation.dpr_numerator &&
         candidate.dpr_denominator == allocation.dpr_denominator &&
         candidate.stride == allocation.stride &&
         candidate.pixel_format == allocation.pixel_format &&
         candidate.frame_bytes == allocation.frame_bytes;
}

} // namespace omarchy::plugin_runtime::surface
