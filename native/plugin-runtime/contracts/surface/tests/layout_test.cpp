#include "test.hpp"

#include "omarchy/plugin_runtime/surface/checked_math.hpp"
#include "omarchy/plugin_runtime/surface/shared_layout.hpp"

#include <array>
#include <cstddef>
#include <cstdint>
#include <limits>

using namespace omarchy::plugin_runtime::surface;

int main() {
  const auto allocation =
      make_allocation({.id = 0x0102030405060708ULL, .generation = 9}, 320, 96,
                      320, 96, 1, 1, 4096);
  require(allocation.has_value(), "ordinary allocation rejected");
  require(allocation->stride == 1280 && allocation->frame_bytes == 122880,
          "ordinary frame arithmetic changed");
  require(allocation->slot_extent == 126976 &&
              allocation->mapping_bytes == 253952,
          "two-slot layout changed");
  require(slot_base(*allocation, 0) == 0 &&
              slot_base(*allocation, 1) == allocation->slot_extent &&
              !slot_base(*allocation, 2),
          "slot bounds failed");

  std::array<std::byte, kSlotHeaderSize> header{};
  require(encode_slot_header(header, *allocation, 2, 17),
          "header encoding failed");
  require(header[16] == std::byte{0x01} && header[23] == std::byte{0x08},
          "surface id is not network ordered");
  const auto decoded = decode_slot_header(header);
  require(decoded && decoded->sequence == 2 && decoded->frame_sequence == 17 &&
              header_matches_allocation(*decoded, *allocation),
          "header round trip failed");
  header[88] = std::byte{1};
  require(!decode_slot_header(header), "reserved tail accepted");

  require(!make_allocation({.id = 0, .generation = 1}, 1, 1, 1, 1, 1, 1, 4096),
          "zero surface accepted");
  require(!make_allocation({.id = 1, .generation = 1}, 1, 1, 4097, 1, 4097, 1,
                           4096),
          "oversize dimension accepted");
  require(!make_allocation({.id = 1, .generation = 1}, 2, 2, 2, 2, 1, 1, 3000),
          "non-power-of-two page size accepted");
  require(!make_allocation({.id = 1, .generation = 1}, 2, 2, 2, 2, 2, 2, 4096),
          "non-reduced DPR accepted");
  require(
      !checked_add(std::numeric_limits<std::uint64_t>::max(), std::uint64_t{1}),
      "addition overflow accepted");
  require(!checked_multiply(std::numeric_limits<std::uint64_t>::max(),
                            std::uint64_t{2}),
          "multiplication overflow accepted");

  const auto maximum = make_allocation({.id = 1, .generation = 1}, 4096, 4096,
                                       4096, 4096, 1, 1, 4096);
  require(maximum && maximum->frame_bytes == kMaximumFrameBytes,
          "maximum frame rejected");
  auto inconsistent = *allocation;
  ++inconsistent.mapping_bytes;
  require(!allocation_is_consistent(inconsistent),
          "inconsistent trusted allocation accepted");

  constexpr std::array<std::uint32_t, 6> dimensions{1, 2, 31, 255, 1024, 4096};
  constexpr std::array<std::uint64_t, 3> page_sizes{8, 4096, 65536};
  for (const auto dimension : dimensions) {
    for (const auto page_size : page_sizes) {
      const auto generated =
          make_allocation({.id = dimension, .generation = page_size}, dimension,
                          dimension, dimension, dimension, 1, 1, page_size);
      require(generated && allocation_is_consistent(*generated) &&
                  generated->mapping_bytes == generated->slot_extent * 2 &&
                  generated->slot_extent % page_size == 0,
              "generated layout invariant failed");
    }
  }
}
