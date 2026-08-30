#pragma once

#include "plugin_session_io.hpp"
#include "omarchy/plugin/wire/surface_name.hpp"
#include "omarchy/plugin_runtime/surface/shared_layout.hpp"

#include <cstddef>
#include <cstdint>
#include <optional>
#include <vector>

namespace omarchy::plugin_runtime::host_session {

namespace surface = omarchy::plugin_runtime::surface;

// The channel authenticates and decodes packets before they reach this router.
// A message may identify its destination by surface, correlation, or both.
struct OwnedAuthenticatedRenderMessage {
  std::uint64_t launch_generation = 0;
  std::uint16_t message_type = 0;
  std::uint64_t correlation = 0;
  std::optional<surface::SurfaceKey> surface;
  std::vector<std::byte> payload;
  std::vector<OwnedFd> descriptors;
};

class SurfaceEndpoint {
public:
  virtual ~SurfaceEndpoint() = default;
  // Ownership is consumed even when the endpoint rejects the message.
  virtual bool receive(OwnedAuthenticatedRenderMessage message) = 0;
};

enum class AttachResult {
  attached,
  invalid_registration,
  duplicate_surface,
  duplicate_correlation,
  capacity_exceeded,
};

enum class RouteResult {
  delivered,
  endpoint_rejected,
  stale_generation,
  unknown_surface,
  unknown_correlation,
  missing_destination,
  conflicting_destination,
};

// Routes one authenticated render channel to independently attached surfaces.
// Endpoint lifetimes are owned by the caller and must outlive their attachment.
// The class is intentionally event-loop confined; it performs no hidden locking.
class MultiSurfaceRouter final {
public:
  static constexpr std::size_t kMaximumCorrelationsPerEndpoint = 8;

  // A router is inseparable from one concrete launch; zero is never a launch.
  explicit MultiSurfaceRouter(std::uint64_t launch_generation);

  [[nodiscard]] AttachResult
  attach(surface::SurfaceKey key, std::span<const std::uint64_t> correlations,
         SurfaceEndpoint &endpoint);

  // Identity checking prevents a stale owner from detaching a replacement.
  [[nodiscard]] bool detach(surface::SurfaceKey key,
                            const SurfaceEndpoint &endpoint) noexcept;
  void detachAll() noexcept;

  [[nodiscard]] RouteResult route(OwnedAuthenticatedRenderMessage message);
  [[nodiscard]] std::size_t size() const noexcept;
  [[nodiscard]] std::uint64_t launchGeneration() const noexcept;

private:
  struct Registration {
    surface::SurfaceKey key;
    std::vector<std::uint64_t> correlations;
    SurfaceEndpoint *endpoint = nullptr;
  };

  [[nodiscard]] Registration *findSurface(surface::SurfaceKey key);
  [[nodiscard]] Registration *findCorrelation(std::uint64_t correlation);

  std::uint64_t launch_generation_ = 0;
  std::vector<Registration> registrations_;
};

} // namespace omarchy::plugin_runtime::host_session
