#include "omarchy/plugin_runtime/surface/frame_transport.hpp"

#include "omarchy/plugin_runtime/surface/checked_math.hpp"

#include <algorithm>
#include <array>
#include <atomic>
#include <cstring>
#include <limits>
#include <new>

namespace omarchy::plugin_runtime::surface {
namespace {

class ScopedConsume {
public:
  explicit ScopedConsume(bool &consuming) : consuming_(consuming) {
    consuming_ = true;
  }
  ~ScopedConsume() { consuming_ = false; }

  ScopedConsume(const ScopedConsume &) = delete;
  ScopedConsume &operator=(const ScopedConsume &) = delete;

private:
  bool &consuming_;
};

static_assert(std::atomic_ref<std::uint64_t>::is_always_lock_free,
              "surface publication requires lock-free shared uint64 atomics");

std::atomic_ref<std::uint64_t> sequence_at(std::span<std::byte> mapping,
                                           std::uint64_t base) {
  auto *pointer = reinterpret_cast<std::uint64_t *>(mapping.data() + base);
  return std::atomic_ref<std::uint64_t>(*pointer);
}

std::atomic_ref<const std::uint64_t>
sequence_at(std::span<const std::byte> mapping, std::uint64_t base) {
  const auto *pointer =
      reinterpret_cast<const std::uint64_t *>(mapping.data() + base);
  return std::atomic_ref<const std::uint64_t>(*pointer);
}

bool region_fits(std::span<const std::byte> mapping,
                 const TrustedAllocation &allocation, std::uint64_t base) {
  if (!allocation_is_consistent(allocation) ||
      allocation.mapping_bytes > mapping.size() ||
      base > allocation.mapping_bytes ||
      kSlotPixelOffset > allocation.slot_extent ||
      allocation.frame_bytes > allocation.slot_extent - kSlotPixelOffset ||
      allocation.slot_extent > mapping.size() ||
      base > mapping.size() - allocation.slot_extent) {
    return false;
  }
  const auto address = reinterpret_cast<std::uintptr_t>(mapping.data() + base);
  return address % alignof(std::uint64_t) == 0;
}

} // namespace

bool initialize_frame_mapping(std::span<std::byte> mapping,
                              const TrustedAllocation &allocation) {
  if (!allocation_is_consistent(allocation) ||
      allocation.mapping_bytes > mapping.size()) {
    return false;
  }
  const auto first = slot_base(allocation, 0);
  const auto second = slot_base(allocation, 1);
  if (!first || !second || !region_fits(mapping, allocation, *first) ||
      !region_fits(mapping, allocation, *second)) {
    return false;
  }
  std::ranges::fill(mapping.first(allocation.mapping_bytes), std::byte{0});
  std::construct_at(reinterpret_cast<std::uint64_t *>(mapping.data() + *first),
                    std::uint64_t{0});
  std::construct_at(reinterpret_cast<std::uint64_t *>(mapping.data() + *second),
                    std::uint64_t{0});
  return true;
}

PublishResult publish_frame(std::span<std::byte> mapping,
                            const TrustedAllocation &allocation,
                            std::uint32_t slot, std::uint64_t slot_sequence,
                            std::uint64_t frame_sequence,
                            std::span<const std::byte> pixels) {
  const auto base = slot_base(allocation, slot);
  if (!base) {
    return PublishResult::invalid_slot;
  }
  if (!region_fits(mapping, allocation, *base)) {
    return PublishResult::invalid_allocation;
  }
  if (slot_sequence < 2 || (slot_sequence & 1U) != 0 || frame_sequence == 0) {
    return PublishResult::invalid_sequence;
  }
  if (pixels.size() != allocation.frame_bytes) {
    return PublishResult::invalid_frame;
  }

  std::array<std::byte, kSlotHeaderSize> encoded{};
  if (!encode_slot_header(encoded, allocation, slot_sequence, frame_sequence)) {
    return PublishResult::invalid_allocation;
  }

  auto sequence = sequence_at(mapping, *base);
  sequence.store(slot_sequence - 1, std::memory_order_release);
  std::memcpy(mapping.data() + *base + sizeof(std::uint64_t),
              encoded.data() + sizeof(std::uint64_t),
              kSlotHeaderSize - sizeof(std::uint64_t));
  std::memcpy(mapping.data() + *base + kSlotPixelOffset, pixels.data(),
              pixels.size());
  std::atomic_thread_fence(std::memory_order_release);
  sequence.store(slot_sequence, std::memory_order_release);
  return PublishResult::published;
}

FrameConsumer::FrameConsumer(TrustedAllocation allocation,
                             std::size_t frame_bytes)
    : allocation_(allocation), last_frame_{}, candidate_pixels_(frame_bytes) {
  last_frame_.pixels.resize(frame_bytes);
}

std::optional<FrameConsumer>
FrameConsumer::create(const TrustedAllocation &allocation) {
  const auto frame_bytes = checked_cast<std::size_t>(allocation.frame_bytes);
  if (!allocation_is_consistent(allocation) || !frame_bytes) {
    return std::nullopt;
  }
  try {
    return FrameConsumer(allocation, *frame_bytes);
  } catch (const std::bad_alloc &) {
    return std::nullopt;
  }
}

ConsumeResult FrameConsumer::consume(std::span<const std::byte> mapping,
                                     const FrameReady &notification,
                                     FrameCopyObserver observer,
                                     void *observer_context) {
  if (consuming_) {
    return ConsumeResult::consumer_busy;
  }
  const ScopedConsume consume_scope(consuming_);
  if (notification.surface != allocation_.surface) {
    return ConsumeResult::stale_surface;
  }
  const auto base = slot_base(allocation_, notification.slot);
  if (!base) {
    return ConsumeResult::invalid_slot;
  }
  if (!region_fits(mapping, allocation_, *base)) {
    return ConsumeResult::region_too_small;
  }
  if (notification.slot_sequence < 2 ||
      (notification.slot_sequence & 1U) != 0 ||
      notification.frame_sequence == 0) {
    return ConsumeResult::invalid_sequence;
  }
  if (notification.slot_sequence <= last_slot_sequences_[notification.slot]) {
    return ConsumeResult::invalid_sequence;
  }
  if (has_frame_ && notification.frame_sequence <= last_frame_.frame_sequence) {
    return ConsumeResult::stale_frame;
  }

  auto sequence = sequence_at(mapping, *base);
  const auto first = sequence.load(std::memory_order_acquire);
  if (first != notification.slot_sequence || (first & 1U) != 0) {
    return ConsumeResult::concurrent_write;
  }
  std::array<std::byte, kSlotHeaderSize> header_bytes{};
  std::memcpy(header_bytes.data(), &first, sizeof(first));
  std::memcpy(header_bytes.data() + sizeof(first),
              mapping.data() + *base + sizeof(first),
              header_bytes.size() - sizeof(first));
  if (observer != nullptr) {
    observer(CopyStage::header_copied, observer_context);
  }
  std::atomic_thread_fence(std::memory_order_acquire);
  const auto second = sequence.load(std::memory_order_acquire);
  if (first != second) {
    return ConsumeResult::concurrent_write;
  }
  const auto header = decode_slot_header(header_bytes);
  if (!header) {
    return ConsumeResult::malformed_header;
  }
  if (header->sequence != notification.slot_sequence ||
      header->frame_sequence != notification.frame_sequence ||
      !header_matches_allocation(*header, allocation_)) {
    return ConsumeResult::allocation_mismatch;
  }

  std::memcpy(candidate_pixels_.data(),
              mapping.data() + *base + kSlotPixelOffset,
              candidate_pixels_.size());
  if (observer != nullptr) {
    observer(CopyStage::pixels_copied, observer_context);
  }
  std::atomic_thread_fence(std::memory_order_acquire);
  const auto third = sequence.load(std::memory_order_acquire);
  if (first != third) {
    return ConsumeResult::concurrent_write;
  }

  last_frame_.surface = allocation_.surface;
  last_frame_.frame_sequence = notification.frame_sequence;
  last_frame_.pixels.swap(candidate_pixels_);
  last_slot_sequences_[notification.slot] = notification.slot_sequence;
  has_frame_ = true;
  return ConsumeResult::accepted;
}

const ConsumedFrame *FrameConsumer::last_frame() const {
  return has_frame_ ? &last_frame_ : nullptr;
}

} // namespace omarchy::plugin_runtime::surface
