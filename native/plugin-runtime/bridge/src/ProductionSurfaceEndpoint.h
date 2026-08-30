#pragma once

#include "production_surface_session_port.hpp"
#include "remote_surface.hpp"

#include <memory>
#include <cstdint>
#include <span>
#include <string>
#include <string_view>
#include <thread>

namespace omarchy::plugin_runtime::surface_host {
class InspectionAuthority;
class MonotonicClock;
}

namespace omarchy::plugin_runtime::bridge {

// Manager-owned adapter for one declared surface. It remains event-loop
// confined and owns every object that can route the session into QML. Active
// means transport-ready only; it is not permission/publication readiness.
class ProductionSurfaceEndpoint final
    : public host_session::SurfaceEndpoint,
      private RemoteSurfaceLifetimeObserver,
      private HostPointerRouter {
public:
  enum class State { inert, attached, active, closing };

  ProductionSurfaceEndpoint(channel::ProductionSurfaceSessionPort &session,
                            std::string declared_surface);
  ~ProductionSurfaceEndpoint() override;
  ProductionSurfaceEndpoint(const ProductionSurfaceEndpoint &) = delete;
  ProductionSurfaceEndpoint &
  operator=(const ProductionSurfaceEndpoint &) = delete;

  [[nodiscard]] bool attach(RemotePluginSurface &surface,
                            std::uint32_t logical_width,
                            std::uint32_t logical_height,
                            std::uint32_t dpr_numerator,
                            std::uint32_t dpr_denominator,
                            surface_host::InspectionAuthority &inspection,
                            surface_host::MonotonicClock &clock);
  [[nodiscard]] bool route_input(const surface::InputEvent &event,
                                 bool trusted_gesture);
  void close() noexcept;

  [[nodiscard]] State state() const noexcept;
  [[nodiscard]] std::string_view declared_surface() const noexcept;

private:
  struct Impl;
  [[nodiscard]] bool
  receive(host_session::OwnedAuthenticatedRenderMessage message) override;
  void remote_surface_destroying() noexcept override;
  [[nodiscard]] bool route(const HostPointerEvent &event) override;
  [[nodiscard]] bool forward_render(
      const plugin::wire::EnvelopeHeader &header,
      std::span<const std::byte> payload,
      std::span<const int> descriptors);
  [[nodiscard]] bool forward_input(
      const plugin::wire::EnvelopeHeader &header,
      std::span<const std::byte> payload);
  void close_impl() noexcept;

  channel::ProductionSurfaceSessionPort &session_;
  const std::string declared_surface_;
  const std::thread::id owner_thread_;
  std::unique_ptr<Impl> implementation_;
};

} // namespace omarchy::plugin_runtime::bridge
