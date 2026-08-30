#pragma once

#include "omarchy/plugin_runtime/surface/input.hpp"

#include <memory>

class QWindow;

namespace omarchy::plugin_runtime::worker {

namespace surface = omarchy::plugin_runtime::surface;

class QtTouchInjector {
public:
  QtTouchInjector();
  ~QtTouchInjector();
  QtTouchInjector(const QtTouchInjector &) = delete;
  QtTouchInjector &operator=(const QtTouchInjector &) = delete;

  void deliver(QWindow &window, const surface::TouchFrame &frame,
               double device_pixel_ratio);
  void cancel(QWindow &window);

private:
  struct Impl;
  std::unique_ptr<Impl> implementation_;
};

} // namespace omarchy::plugin_runtime::worker
