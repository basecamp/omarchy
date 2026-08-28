#pragma once

#include "omarchy/plugin_runtime/surface/input.hpp"

#include <cstddef>
#include <cstdint>
#include <span>

namespace omarchy::plugin_runtime::surface {

class TrustedFrameSink {
public:
  virtual ~TrustedFrameSink() = default;
  virtual bool configure(const TrustedAllocation &allocation) = 0;
  virtual bool present(SurfaceKey surface, std::uint64_t frame_sequence,
                       std::span<const std::byte> trusted_pixels) = 0;
  virtual void clear(SurfaceKey surface) = 0;
  virtual void disconnect() = 0;
};

class HostInputSource {
public:
  virtual ~HostInputSource() = default;
  virtual bool submit(const InputEvent &event) = 0;
};

} // namespace omarchy::plugin_runtime::surface
