#include "expressive_surface.hpp"

#include <algorithm>
#include <utility>

namespace omarchy::plugin_runtime::expressive_surface {
namespace {

HostLayer layer_for(host::SurfaceRole role) {
  switch (role) {
  case host::SurfaceRole::desktop_overlay:
    return HostLayer::desktop_overlay;
  case host::SurfaceRole::panel:
    return HostLayer::panel;
  case host::SurfaceRole::bar_embedded:
    return HostLayer::bar;
  }
  return HostLayer::desktop_overlay;
}

} // namespace

std::optional<Registry> Registry::create(std::string plugin_id,
                                         std::span<const Monitor> monitors) {
  if (plugin_id.empty() || plugin_id.size() > 128 || monitors.empty() ||
      monitors.size() > kMaximumMonitors)
    return std::nullopt;
  Registry result;
  result.plugin_id_ = std::move(plugin_id);
  for (const auto &monitor : monitors) {
    if (monitor.id == 0 || monitor.width == 0 || monitor.height == 0 ||
        std::find_if(result.monitors_.begin(),
                     result.monitors_.begin() + result.monitor_count_,
                     [&monitor](const Monitor &candidate) {
                       return candidate.id == monitor.id;
                     }) != result.monitors_.begin() + result.monitor_count_)
      return std::nullopt;
    result.monitors_[result.monitor_count_++] = monitor;
  }
  return result;
}

std::optional<Admission> Registry::admit(const host::NamedSurfacePolicy &policy,
                                         std::uint64_t surface_id,
                                         std::uint32_t logical_width,
                                         std::uint32_t logical_height,
                                         PlacementAuthority &authority) {
  if (policy.plugin_id != plugin_id_ || surface_id == 0 || logical_width == 0 ||
      logical_height == 0 || logical_width > policy.maximum_width ||
      logical_height > policy.maximum_height ||
      policy.maximum_frames_per_second == 0 ||
      policy.maximum_frames_per_second > 60 || size_ >= entries_.size() ||
      admitting_ ||
      std::find_if(entries_.begin(), entries_.begin() + size_,
                   [&policy, surface_id](const Admission &entry) {
                     return entry.surface_id == surface_id ||
                            entry.surface_name == policy.surface_name;
                   }) != entries_.begin() + size_)
    return std::nullopt;

  admitting_ = true;
  const auto placement = authority.place(policy, logical_width, logical_height);
  admitting_ = false;
  if (!placement)
    return std::nullopt;
  const auto monitor =
      std::find_if(monitors_.begin(), monitors_.begin() + monitor_count_,
                   [&placement](const Monitor &candidate) {
                     return candidate.id == placement->monitor_id;
                   });
  if (monitor == monitors_.begin() + monitor_count_ ||
      placement->x > monitor->width || placement->y > monitor->height ||
      logical_width > monitor->width - placement->x ||
      logical_height > monitor->height - placement->y)
    return std::nullopt;

  Admission admitted{.surface_id = surface_id,
                     .surface_name = policy.surface_name,
                     .monitor_id = placement->monitor_id,
                     .x = placement->x,
                     .y = placement->y,
                     .width = logical_width,
                     .height = logical_height,
                     .maximum_frames_per_second =
                         policy.maximum_frames_per_second,
                     .layer = layer_for(policy.role),
                     .keyboard_focus = policy.keyboard_focus};
  entries_[size_++] = admitted;
  return admitted;
}

bool Registry::close(std::uint64_t surface_id) noexcept {
  const auto found = std::find_if(entries_.begin(), entries_.begin() + size_,
                                  [surface_id](const Admission &entry) {
                                    return entry.surface_id == surface_id;
                                  });
  if (found == entries_.begin() + size_)
    return false;
  std::move(found + 1, entries_.begin() + size_, found);
  entries_[--size_] = {};
  return true;
}

std::size_t Registry::size() const noexcept { return size_; }
std::span<const Admission> Registry::entries() const noexcept {
  return std::span(entries_).first(size_);
}

} // namespace omarchy::plugin_runtime::expressive_surface
