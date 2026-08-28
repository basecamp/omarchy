#pragma once

#include "omarchy/plugin_runtime/surface/render_messages.hpp"

#include <array>
#include <cstddef>
#include <cstdint>
#include <optional>
#include <span>
#include <vector>

namespace omarchy::plugin_runtime::surface {

enum class PublishResult {
  published,
  invalid_allocation,
  invalid_slot,
  invalid_sequence,
  invalid_frame,
};

enum class ConsumeResult {
  accepted,
  stale_surface,
  invalid_slot,
  invalid_sequence,
  stale_frame,
  malformed_header,
  allocation_mismatch,
  concurrent_write,
  consumer_busy,
  region_too_small,
};

struct ConsumedFrame {
  SurfaceKey surface{};
  std::uint64_t frame_sequence = 0;
  std::vector<std::byte> pixels;
};

enum class CopyStage { header_copied, pixels_copied };
using FrameCopyObserver = void (*)(CopyStage stage, void *context) noexcept;

[[nodiscard]] PublishResult
publish_frame(std::span<std::byte> mapping, const TrustedAllocation &allocation,
              std::uint32_t slot, std::uint64_t slot_sequence,
              std::uint64_t frame_sequence, std::span<const std::byte> pixels);

[[nodiscard]] bool
initialize_frame_mapping(std::span<std::byte> mapping,
                         const TrustedAllocation &allocation);

class FrameConsumer {
public:
  [[nodiscard]] static std::optional<FrameConsumer>
  create(const TrustedAllocation &allocation);

  [[nodiscard]] ConsumeResult consume(std::span<const std::byte> mapping,
                                      const FrameReady &notification,
                                      FrameCopyObserver observer = nullptr,
                                      void *observer_context = nullptr);
  [[nodiscard]] const ConsumedFrame *last_frame() const;

private:
  FrameConsumer(TrustedAllocation allocation, std::size_t frame_bytes);

  TrustedAllocation allocation_;
  ConsumedFrame last_frame_;
  std::vector<std::byte> candidate_pixels_;
  std::array<std::uint64_t, kSlotCount> last_slot_sequences_{};
  bool has_frame_ = false;
  bool consuming_ = false;
};

} // namespace omarchy::plugin_runtime::surface
