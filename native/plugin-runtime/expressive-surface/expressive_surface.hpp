#pragma once

#include "surface_host.hpp"

#include <array>
#include <cstddef>
#include <cstdint>
#include <optional>
#include <span>
#include <string>
#include <string_view>

namespace omarchy::plugin_runtime::expressive_surface {

namespace host = omarchy::plugin_runtime::surface_host;

inline constexpr std::size_t kMaximumMonitors = 16;

enum class HostLayer : std::uint8_t { desktop_overlay, panel, bar };

struct Monitor {
  std::uint32_t id = 0;
  std::uint32_t width = 0;
  std::uint32_t height = 0;
  constexpr bool operator==(const Monitor &) const = default;
};

struct Placement {
  std::uint32_t monitor_id = 0;
  std::uint32_t x = 0;
  std::uint32_t y = 0;
};

class PlacementAuthority {
public:
  virtual ~PlacementAuthority() = default;
  [[nodiscard]] virtual std::optional<Placement>
  place(const host::NamedSurfacePolicy &policy, std::uint32_t logical_width,
        std::uint32_t logical_height) noexcept = 0;
};

struct Admission {
  std::uint64_t surface_id = 0;
  std::string surface_name;
  std::uint32_t monitor_id = 0;
  std::uint32_t x = 0;
  std::uint32_t y = 0;
  std::uint32_t width = 0;
  std::uint32_t height = 0;
  std::uint32_t maximum_frames_per_second = 0;
  HostLayer layer = HostLayer::desktop_overlay;
  host::KeyboardFocusPolicy keyboard_focus = host::KeyboardFocusPolicy::none;
};

class Registry final {
public:
  [[nodiscard]] static std::optional<Registry>
  create(std::string plugin_id, std::span<const Monitor> monitors);

  [[nodiscard]] std::optional<Admission>
  admit(const host::NamedSurfacePolicy &policy, std::uint64_t surface_id,
        std::uint32_t logical_width, std::uint32_t logical_height,
        PlacementAuthority &authority);
  [[nodiscard]] bool close(std::uint64_t surface_id) noexcept;
  [[nodiscard]] std::size_t size() const noexcept;
  [[nodiscard]] std::span<const Admission> entries() const noexcept;

private:
  std::string plugin_id_;
  std::array<Monitor, kMaximumMonitors> monitors_{};
  std::size_t monitor_count_ = 0;
  std::array<Admission, host::kMaximumSurfacesPerPlugin> entries_{};
  std::size_t size_ = 0;
  bool admitting_ = false;
};

} // namespace omarchy::plugin_runtime::expressive_surface
