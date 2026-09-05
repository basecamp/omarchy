#pragma once

#include "MultiSurfaceRouter.h"
#include "omarchy/plugin/wire/state.hpp"
#include "permission_contract.hpp"

#include <cstdint>
#include <optional>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace omarchy::plugin_runtime::bridge {
class SurfaceEndpoint;
}

namespace omarchy::plugin_runtime::channel {

namespace session = omarchy::plugin_runtime::host_session;
namespace permissions = omarchy::plugins::permissions;

struct SurfaceDescription final {
  permissions::ActivationBinding binding;
  session::surface::SurfaceKey key;
  std::uint64_t session_nonce = 0;
  std::string plugin_id;
  std::string surface_name;
  std::string canonical_surfaces;

  bool operator==(const SurfaceDescription &) const = default;
};

// UI/event-loop-confined access to one root-owned running session. A
// A description alone is not publication readiness: the manager consumes it
// only after the session's authenticated startup ACK and exact slot recheck.
// This seam deliberately exposes neither PluginSession nor permission and
// lifecycle authorities.
class SurfaceSessionPort {
public:
  virtual ~SurfaceSessionPort() = default;
  [[nodiscard]] virtual std::optional<SurfaceDescription>
  describe(std::string_view declared_surface) const noexcept = 0;
  // All-or-nothing: false guarantees endpoint was not published.
  [[nodiscard]] virtual bool
  attach(const SurfaceDescription &expected,
         session::SurfaceEndpoint &endpoint) noexcept = 0;
  // Exact identity makes late G1 teardown a successful no-op after G2 exists.
  [[nodiscard]] virtual bool
  detach(const SurfaceDescription &expected,
         const session::SurfaceEndpoint &endpoint) noexcept = 0;
  [[nodiscard]] virtual bool
  arm_surface_intent(const SurfaceDescription &expected,
                     std::uint64_t input_sequence) noexcept = 0;
  virtual void clear_surface_intent_eligibility(
      const SurfaceDescription &expected) noexcept = 0;

private:
  [[nodiscard]] bool send_render_packet(
      const SurfaceDescription &expected,
      const plugin::wire::EnvelopeHeader &header,
      std::vector<std::byte> payload,
      std::vector<session::OwnedFd> descriptors) noexcept {
    return send_render_packet_impl(expected, header, std::move(payload),
                                   std::move(descriptors));
  }
  [[nodiscard]] virtual bool send_render_packet_impl(
      const SurfaceDescription &expected,
      const plugin::wire::EnvelopeHeader &header,
      std::vector<std::byte> payload,
      std::vector<session::OwnedFd> descriptors) noexcept = 0;

  friend class omarchy::plugin_runtime::bridge::SurfaceEndpoint;
};

} // namespace omarchy::plugin_runtime::channel
