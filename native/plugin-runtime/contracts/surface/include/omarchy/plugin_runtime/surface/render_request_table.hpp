#pragma once

#include "omarchy/plugin_runtime/surface/render_messages.hpp"

#include <array>
#include <cstddef>
#include <cstdint>

namespace omarchy::plugin_runtime::surface {

enum class RenderPairResult {
  accepted,
  invalid_request,
  invalid_terminal,
  zero_correlation,
  duplicate_correlation,
  capacity_exhausted,
  unknown_correlation,
  mismatched_terminal,
  mismatched_surface,
};

template <std::size_t Capacity> class RenderRequestTable {
public:
  [[nodiscard]] RenderPairResult begin(RenderMessageType request,
                                       std::uint64_t correlation_id,
                                       SurfaceKey surface = {}) {
    if (!valid_request(request, surface)) {
      return RenderPairResult::invalid_request;
    }
    if (correlation_id == 0) {
      return RenderPairResult::zero_correlation;
    }
    for (const auto &entry : entries_) {
      if (entry.occupied && entry.correlation_id == correlation_id) {
        return RenderPairResult::duplicate_correlation;
      }
    }
    for (auto &entry : entries_) {
      if (!entry.occupied) {
        entry = {.correlation_id = correlation_id,
                 .request = request,
                 .surface = surface,
                 .occupied = true};
        ++size_;
        return RenderPairResult::accepted;
      }
    }
    return RenderPairResult::capacity_exhausted;
  }

  [[nodiscard]] RenderPairResult
  validate_terminal(RenderMessageType terminal, std::uint64_t correlation_id,
                    SurfaceKey surface = {}) const {
    const auto *entry = find(correlation_id);
    if (entry == nullptr) {
      return correlation_id == 0 ? RenderPairResult::zero_correlation
                                 : RenderPairResult::unknown_correlation;
    }
    const auto expected = terminal_for(entry->request);
    if (!expected.has_value() || *expected != terminal) {
      return RenderPairResult::mismatched_terminal;
    }
    if (entry->surface != surface) {
      return RenderPairResult::mismatched_surface;
    }
    return RenderPairResult::accepted;
  }

  [[nodiscard]] RenderPairResult
  validate_error(const RenderTypedError &error,
                 std::uint64_t correlation_id) const {
    const auto *entry = find(correlation_id);
    if (entry == nullptr) {
      return correlation_id == 0 ? RenderPairResult::zero_correlation
                                 : RenderPairResult::unknown_correlation;
    }
    if (error.failed_message_type !=
        static_cast<std::uint16_t>(entry->request)) {
      return RenderPairResult::mismatched_terminal;
    }
    if (error.surface != entry->surface) {
      return RenderPairResult::mismatched_surface;
    }
    return RenderPairResult::accepted;
  }

  [[nodiscard]] RenderPairResult complete(std::uint64_t correlation_id) {
    auto *entry = find(correlation_id);
    if (entry == nullptr) {
      return correlation_id == 0 ? RenderPairResult::zero_correlation
                                 : RenderPairResult::unknown_correlation;
    }
    erase(*entry);
    return RenderPairResult::accepted;
  }

  [[nodiscard]] std::size_t size() const { return size_; }

private:
  struct Entry {
    std::uint64_t correlation_id = 0;
    RenderMessageType request = RenderMessageType::profile_offer;
    SurfaceKey surface{};
    bool occupied = false;
  };

  [[nodiscard]] static bool valid_request(RenderMessageType request,
                                          SurfaceKey surface) {
    if (request == RenderMessageType::profile_offer) {
      return surface == SurfaceKey{};
    }
    return request == RenderMessageType::surface_allocate && surface.id != 0 &&
           surface.generation != 0;
  }

  [[nodiscard]] static std::optional<RenderMessageType>
  terminal_for(RenderMessageType request) {
    if (request == RenderMessageType::profile_offer) {
      return RenderMessageType::profile_select;
    }
    if (request == RenderMessageType::surface_allocate) {
      return RenderMessageType::surface_allocated;
    }
    return std::nullopt;
  }

  [[nodiscard]] Entry *find(std::uint64_t correlation_id) {
    for (auto &entry : entries_) {
      if (entry.occupied && entry.correlation_id == correlation_id) {
        return &entry;
      }
    }
    return nullptr;
  }

  [[nodiscard]] const Entry *find(std::uint64_t correlation_id) const {
    for (const auto &entry : entries_) {
      if (entry.occupied && entry.correlation_id == correlation_id) {
        return &entry;
      }
    }
    return nullptr;
  }

  void erase(Entry &entry) {
    entry = {};
    --size_;
  }

  std::array<Entry, Capacity> entries_{};
  std::size_t size_ = 0;
};

} // namespace omarchy::plugin_runtime::surface
