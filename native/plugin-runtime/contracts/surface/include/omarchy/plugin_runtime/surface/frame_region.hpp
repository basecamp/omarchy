#pragma once

#include "omarchy/plugin_runtime/surface/shared_layout.hpp"

#include <cstddef>
#include <optional>
#include <span>

namespace omarchy::plugin_runtime::surface {

class HostFrameRegion {
public:
  HostFrameRegion() = default;
  HostFrameRegion(const HostFrameRegion &) = delete;
  HostFrameRegion &operator=(const HostFrameRegion &) = delete;
  HostFrameRegion(HostFrameRegion &&other) noexcept;
  HostFrameRegion &operator=(HostFrameRegion &&other) noexcept;
  ~HostFrameRegion();

  [[nodiscard]] static std::optional<HostFrameRegion>
  create(const TrustedAllocation &allocation);

  [[nodiscard]] int duplicate_worker_fd() const;
  [[nodiscard]] std::span<const std::byte> host_mapping() const;
  [[nodiscard]] int seals() const;

private:
  HostFrameRegion(int fd, std::byte *mapping, std::size_t size);
  void reset();

  int fd_ = -1;
  std::byte *mapping_ = nullptr;
  std::size_t size_ = 0;
};

} // namespace omarchy::plugin_runtime::surface
