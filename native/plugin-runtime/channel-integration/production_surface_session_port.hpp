#pragma once

#include "../host-session/MultiSurfaceRouter.h"
#include "omarchy/plugin/wire/state.hpp"
#include "permission_contract.hpp"

#include <cstdint>
#include <optional>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace omarchy::plugin_runtime::bridge {
class ProductionSurfaceEndpoint;
}

namespace omarchy::plugin_runtime::channel {

namespace session = omarchy::plugin_runtime::host_session;
namespace permissions = omarchy::plugins::permissions;

struct ProductionSurfaceDescription final {
  permissions::ActivationBinding binding;
  session::surface::SurfaceKey key;
  std::uint64_t session_nonce = 0;
  std::string plugin_id;
  std::string surface_name;
  std::string canonical_surfaces;

  bool operator==(const ProductionSurfaceDescription &) const = default;
};

// UI/event-loop-confined access to one root-owned running session. A
// description is not publication readiness: the future manager must also
// complete N6B permission projection before exposing this surface to QML.
// This seam deliberately exposes neither PluginSession nor permission and
// lifecycle authorities.
class ProductionSurfaceSessionPort {
public:
  virtual ~ProductionSurfaceSessionPort() = default;
  [[nodiscard]] virtual std::optional<ProductionSurfaceDescription>
  describe(std::string_view declared_surface) const noexcept = 0;
  // All-or-nothing: false guarantees endpoint was not published.
  [[nodiscard]] virtual bool
  attach(const ProductionSurfaceDescription &expected,
         session::SurfaceEndpoint &endpoint) noexcept = 0;
  // Exact identity makes late G1 teardown a successful no-op after G2 exists.
  [[nodiscard]] virtual bool
  detach(const ProductionSurfaceDescription &expected,
         const session::SurfaceEndpoint &endpoint) noexcept = 0;
  [[nodiscard]] virtual bool
  arm_surface_intent(const ProductionSurfaceDescription &expected,
                     std::uint64_t input_sequence) noexcept = 0;
  virtual void clear_surface_intent_eligibility(
      const ProductionSurfaceDescription &expected) noexcept = 0;

private:
  [[nodiscard]] bool send_render_packet(
      const ProductionSurfaceDescription &expected,
      const plugin::wire::EnvelopeHeader &header,
      std::vector<std::byte> payload,
      std::vector<session::OwnedFd> descriptors) noexcept {
    return send_render_packet_impl(expected, header, std::move(payload),
                                   std::move(descriptors));
  }
  [[nodiscard]] virtual bool send_render_packet_impl(
      const ProductionSurfaceDescription &expected,
      const plugin::wire::EnvelopeHeader &header,
      std::vector<std::byte> payload,
      std::vector<session::OwnedFd> descriptors) noexcept = 0;

  friend class omarchy::plugin_runtime::bridge::ProductionSurfaceEndpoint;
};

} // namespace omarchy::plugin_runtime::channel
