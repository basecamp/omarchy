#pragma once

#include "manifest_contract.hpp"
#include "permission_contract.hpp"
#include "remote_surface.hpp"
#include "render_session.hpp"

#include <cstdint>
#include <memory>
#include <span>
#include <string>
#include <string_view>
#include <vector>

namespace omarchy::plugin_runtime::surface_host {

namespace bridge = omarchy::plugin_runtime::bridge;
namespace render_session = omarchy::plugin_runtime::render_session;
namespace surface = omarchy::plugin_runtime::surface;
namespace permissions = omarchy::plugins::permissions;

inline constexpr std::size_t kMaximumSurfacesPerPlugin = 8;
inline constexpr std::size_t kMaximumInputRegions = 16;

enum class SurfaceRole { bar_embedded, desktop_overlay, panel };
enum class KeyboardFocusPolicy { none, after_gesture };

struct InputRegion {
  std::uint32_t x;
  std::uint32_t y;
  std::uint32_t width;
  std::uint32_t height;

  constexpr bool operator==(const InputRegion &) const = default;
};

struct NamedSurfacePolicy {
  std::string plugin_id;
  std::string surface_name;
  SurfaceRole role;
  std::uint32_t maximum_width;
  std::uint32_t maximum_height;
  std::uint32_t maximum_frames_per_second;
  KeyboardFocusPolicy keyboard_focus;
  bool dynamic_input_regions;

  bool operator==(const NamedSurfacePolicy &) const = default;
};

[[nodiscard]] NamedSurfacePolicy parse_named_surface_policy(
    const omarchy::plugins::manifest::ManifestV2 &manifest,
    std::string_view surface_name);

enum class InspectionAction { open_permissions, terminate };

class InspectionAuthority {
public:
  virtual ~InspectionAuthority() = default;
  virtual bool perform(InspectionAction action, std::string_view plugin_id,
                       std::string_view revision_digest,
                       std::string_view surface_name) = 0;
};

struct InspectionSnapshot {
  std::string plugin_id;
  std::string revision_digest;
  std::string policy_fingerprint;
  std::string surface_name;
  SurfaceRole role;
  std::uint32_t logical_width;
  std::uint32_t logical_height;
  std::uint32_t dpr_numerator;
  std::uint32_t dpr_denominator;
  std::uint64_t surface_id;
  std::uint64_t surface_generation;
  std::uint64_t frame_sequence;
  std::uint64_t pace_drops;
  std::size_t input_region_count;
  bool render_active;
  bool visible;
  bool focused;
  bool locked;
  bool terminated;
  std::string bridge_state;
};

class MonotonicClock {
public:
  virtual ~MonotonicClock() = default;
  [[nodiscard]] virtual std::uint64_t now_nanoseconds() const = 0;
};

class HostSurface final {
public:
  [[nodiscard]] static std::unique_ptr<HostSurface>
  create(NamedSurfacePolicy policy, permissions::ActivationBinding binding,
         std::uint64_t surface_id, std::uint32_t logical_width,
         std::uint32_t logical_height, std::uint32_t dpr_numerator,
         std::uint32_t dpr_denominator,
         bridge::RemotePluginSurface &bridge_item,
         render_session::PacketSender &render_sender,
         std::shared_ptr<bridge::RenderPacketSink> input_sink,
         InspectionAuthority &inspection_authority, MonotonicClock &clock);

  ~HostSurface();
  HostSurface(const HostSurface &) = delete;
  HostSurface &operator=(const HostSurface &) = delete;

  [[nodiscard]] bool receive_render(std::span<const std::byte> packet);
  [[nodiscard]] bool set_input_regions(std::span<const InputRegion> regions);
  [[nodiscard]] bool route_input(const surface::InputEvent &event,
                                 bool trusted_gesture);
  [[nodiscard]] bool clear_focus();
  [[nodiscard]] bool set_locked(bool locked);
  [[nodiscard]] bool perform_inspection_action(InspectionAction action);
  void peer_lost();
  void close();

  [[nodiscard]] const NamedSurfacePolicy &policy() const;
  [[nodiscard]] const surface::TrustedAllocation &allocation() const;
  [[nodiscard]] InspectionSnapshot inspection() const;

private:
  HostSurface(NamedSurfacePolicy policy, permissions::ActivationBinding binding,
              surface::TrustedAllocation allocation,
              bridge::RemotePluginSurface &bridge_item,
              render_session::PacketSender &render_sender,
              std::shared_ptr<bridge::RenderPacketSink> input_sink,
              InspectionAuthority &inspection_authority, MonotonicClock &clock);

  [[nodiscard]] bool point_is_inside(std::uint32_t x_q16,
                                     std::uint32_t y_q16) const;
  [[nodiscard]] bool active() const;

  NamedSurfacePolicy policy_;
  permissions::ActivationBinding binding_;
  surface::TrustedAllocation allocation_;
  bridge::RemotePluginSurface &bridge_item_;
  std::shared_ptr<bridge::AuthenticatedInputTransport> input_transport_;
  render_session::HostRenderSession render_session_;
  InspectionAuthority &inspection_authority_;
  MonotonicClock &clock_;
  std::vector<InputRegion> input_regions_;
  std::uint64_t focus_sequence_ = 0;
  std::uint64_t last_admitted_frame_ns_ = 0;
  bool has_admitted_frame_ = false;
  std::uint64_t pace_drops_ = 0;
  std::uint32_t captured_pointer_button_ = 0;
  bool touch_active_ = false;
  bool locked_ = false;
  bool terminated_ = false;
};

} // namespace omarchy::plugin_runtime::surface_host
