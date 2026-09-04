#pragma once

#include "manifest_contract.hpp"
#include "omarchy/plugin/wire/surface_name.hpp"
#include "permission_contract.hpp"
#include "remote_surface.hpp"
#include "render_session.hpp"

#include <QPointer>

#include <cstdint>
#include <memory>
#include <span>
#include <string>
#include <string_view>
#include <vector>

namespace omarchy::plugin_runtime::bridge {
class SurfaceEndpoint;
}

namespace omarchy::plugin_runtime::surface_host {

namespace bridge = omarchy::plugin_runtime::bridge;
namespace render_session = omarchy::plugin_runtime::render_session;
namespace surface = omarchy::plugin_runtime::surface;
namespace permissions = omarchy::plugins::permissions;

enum class SurfaceRole { bar_embedded, desktop_overlay, panel };
enum class KeyboardFocusPolicy { none, after_gesture };
enum class BarSection { unspecified, left, center, right };

struct NamedSurfacePolicy {
  std::string plugin_id;
  std::string surface_name;
  SurfaceRole role;
  std::uint32_t maximum_width;
  std::uint32_t maximum_height;
  std::uint32_t maximum_frames_per_second;
  KeyboardFocusPolicy keyboard_focus;
  bool dynamic_input_regions;
  bool initially_visible;
  BarSection default_bar_section = BarSection::unspecified;

  bool operator==(const NamedSurfacePolicy &) const = default;
};

[[nodiscard]] NamedSurfacePolicy parse_named_surface_policy(
    const omarchy::plugins::manifest::ManifestV2 &manifest,
    std::string_view surface_name);

class MonotonicClock {
public:
  virtual ~MonotonicClock() = default;
  [[nodiscard]] virtual std::uint64_t now_nanoseconds() const = 0;
};

class HostSurface final : private bridge::HostInputRegionRouter {
public:
  [[nodiscard]] static std::unique_ptr<HostSurface>
  create(NamedSurfacePolicy policy, permissions::ActivationBinding binding,
         std::uint64_t surface_id, std::uint32_t logical_width,
         std::uint32_t logical_height, std::uint32_t dpr_numerator,
         std::uint32_t dpr_denominator,
         bridge::RemotePluginSurface &bridge_item,
         render_session::PacketSender &render_sender,
         std::shared_ptr<bridge::RenderPacketSink> input_sink,
         bridge::TrustedInputAuthority &input_authority,
         MonotonicClock &clock);

  ~HostSurface();
  HostSurface(const HostSurface &) = delete;
  HostSurface &operator=(const HostSurface &) = delete;

  [[nodiscard]] bool receive_render(
      const render_session::AuthenticatedRenderPacket &packet);
  [[nodiscard]] bool route_input(bridge::HostInputEvent event);
  [[nodiscard]] bool cancel_input(std::uint64_t device);
  void close();

  [[nodiscard]] const surface::TrustedAllocation &allocation() const;
  [[nodiscard]] bool terminated() const noexcept;

private:
  HostSurface(NamedSurfacePolicy policy, permissions::ActivationBinding binding,
              surface::TrustedAllocation allocation,
              bridge::RemotePluginSurface &bridge_item,
              render_session::PacketSender &render_sender,
              std::shared_ptr<bridge::RenderPacketSink> input_sink,
              bridge::TrustedInputAuthority &input_authority,
              MonotonicClock &clock);

  [[nodiscard]] bool point_is_inside(std::uint32_t x_q16,
                                     std::uint32_t y_q16) const;
  [[nodiscard]] bool end_input();
  [[nodiscard]] bool active() const;
  [[nodiscard]] bool apply(const surface::InputRegionUpdate &update) override;
  void unbind_input_region_router();
  void abandon_bridge_item() noexcept;

  NamedSurfacePolicy policy_;
  surface::TrustedAllocation allocation_;
  QPointer<bridge::RemotePluginSurface> bridge_item_;
  std::shared_ptr<bridge::AuthenticatedInputTransport> input_transport_;
  bridge::TrustedInputAuthority &input_authority_;
  render_session::HostRenderSession render_session_;
  MonotonicClock &clock_;
  std::vector<surface::TransportedInputRegion> input_regions_;
  bool input_region_router_bound_ = false;
  bool input_transport_bound_ = false;
  std::uint64_t last_admitted_frame_ns_ = 0;
  bool has_admitted_frame_ = false;
  bool input_ended_ = false;
  bool terminated_ = false;

  friend class omarchy::plugin_runtime::bridge::SurfaceEndpoint;
};

} // namespace omarchy::plugin_runtime::surface_host
