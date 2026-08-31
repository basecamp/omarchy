#pragma once

#include "surface_session_port.hpp"
#include "remote_surface.hpp"

#include <memory>
#include <cstdint>
#include <span>
#include <string>
#include <thread>

namespace omarchy::plugin_runtime::surface_host {
class MonotonicClock;
}

namespace omarchy::plugin_runtime::bridge {

class SurfaceEndpointOwner;
#ifdef OMARCHY_SURFACE_ENDPOINT_TESTING
class SurfaceEndpointTestAccess;
#endif
#ifdef OMARCHY_SURFACE_ENDPOINT_OWNER_TESTING
class SurfaceEndpointOwnerTestAccess;
#endif

// Manager-owned adapter for one declared surface. It remains event-loop
// confined and owns every object that can route the session into QML. Active
// means transport-ready only; it is not permission/publication readiness.
class SurfaceEndpoint final
    : public host_session::SurfaceEndpoint,
      private RemoteSurfaceLifetimeObserver,
      private HostInputRouter {
public:
  ~SurfaceEndpoint() override;
  SurfaceEndpoint(const SurfaceEndpoint &) = delete;
  SurfaceEndpoint &
  operator=(const SurfaceEndpoint &) = delete;

private:
  enum class State { inert, attached, active, closing, closed };

  SurfaceEndpoint(channel::SurfaceSessionPort &session,
                  TrustedInputAuthority &input_authority,
                  std::string declared_surface);
  [[nodiscard]] bool attach(RemotePluginSurface &surface,
                            std::uint32_t logical_width,
                            std::uint32_t logical_height,
                            std::uint32_t dpr_numerator,
                            std::uint32_t dpr_denominator,
                            surface_host::MonotonicClock &clock);
  void close() noexcept;

  [[nodiscard]] State state() const noexcept;

  struct Impl;
  [[nodiscard]] bool
  receive(host_session::OwnedAuthenticatedRenderMessage message) override;
  void remote_surface_destroying() noexcept override;
  [[nodiscard]] bool route(HostInputEvent event) override;
  [[nodiscard]] bool cancel(std::uint64_t device) override;
  [[nodiscard]] bool forward_render(
      const plugin::wire::EnvelopeHeader &header,
      std::span<const std::byte> payload,
      std::span<const int> descriptors);
  [[nodiscard]] bool forward_input(
      const plugin::wire::EnvelopeHeader &header,
      std::span<const std::byte> payload);
  void close_impl() noexcept;

  channel::SurfaceSessionPort &session_;
  TrustedInputAuthority &input_authority_;
  const std::string declared_surface_;
  const std::thread::id owner_thread_;
  std::unique_ptr<Impl> implementation_;

  friend class SurfaceEndpointOwner;
#ifdef OMARCHY_SURFACE_ENDPOINT_TESTING
  friend class SurfaceEndpointTestAccess;
#endif
#ifdef OMARCHY_SURFACE_ENDPOINT_OWNER_TESTING
  friend class SurfaceEndpointOwnerTestAccess;
#endif
};

} // namespace omarchy::plugin_runtime::bridge
