#include "MultiSurfaceRouter.h"

#include <algorithm>
#include <stdexcept>
#include <utility>

namespace omarchy::plugin_runtime::host_session {
namespace wire = omarchy::plugin::wire;

MultiSurfaceRouter::MultiSurfaceRouter(std::uint64_t launch_generation)
    : launch_generation_(launch_generation) {
  if (launch_generation_ == 0) {
    throw std::invalid_argument("launch generation must be nonzero");
  }
  registrations_.reserve(wire::kMaximumPluginSurfaces);
}

AttachResult MultiSurfaceRouter::attach(
    surface::SurfaceKey key,
    std::span<const std::uint64_t> correlations,
    SurfaceEndpoint &endpoint) {
  if (key.id == 0 || key.generation != launch_generation_ ||
      correlations.size() > kMaximumCorrelationsPerEndpoint) {
    return AttachResult::invalid_registration;
  }
  if (findSurface(key) != nullptr) {
    return AttachResult::duplicate_surface;
  }
  if (registrations_.size() == wire::kMaximumPluginSurfaces) {
    return AttachResult::capacity_exceeded;
  }

  for (std::size_t index = 0; index < correlations.size(); ++index) {
    const auto correlation = correlations[index];
    if (correlation == 0 ||
        std::find(correlations.begin(), correlations.begin() + index,
                  correlation) != correlations.begin() + index) {
      return AttachResult::invalid_registration;
    }
    if (findCorrelation(correlation) != nullptr) {
      return AttachResult::duplicate_correlation;
    }
  }

  registrations_.push_back(Registration{
      .key = key,
      .correlations =
          std::vector<std::uint64_t>(correlations.begin(), correlations.end()),
      .endpoint = &endpoint,
  });
  return AttachResult::attached;
}

bool MultiSurfaceRouter::detach(surface::SurfaceKey key,
                                const SurfaceEndpoint &endpoint) noexcept {
  if (key.id == 0 || key.generation != launch_generation_) {
    return false;
  }
  const auto registration =
      std::find_if(registrations_.begin(), registrations_.end(),
                   [key](const Registration &candidate) {
                     return candidate.key == key;
                   });
  if (registration == registrations_.end()) {
    return true;
  }
  if (registration->endpoint != &endpoint) {
    return false;
  }
  registrations_.erase(registration);
  return true;
}

void MultiSurfaceRouter::detachAll() noexcept { registrations_.clear(); }

RouteResult
MultiSurfaceRouter::route(OwnedAuthenticatedRenderMessage message) {
  if (message.launch_generation != launch_generation_) {
    return RouteResult::stale_generation;
  }
  if (message.surface.has_value() &&
      (message.surface->id == 0 ||
       message.surface->generation != launch_generation_)) {
    return RouteResult::stale_generation;
  }
  if (!message.surface.has_value() && message.correlation == 0) {
    return RouteResult::missing_destination;
  }

  Registration *surface_registration = nullptr;
  if (message.surface.has_value()) {
    surface_registration = findSurface(*message.surface);
    if (surface_registration == nullptr) {
      return RouteResult::unknown_surface;
    }
  }

  Registration *correlation_registration = nullptr;
  if (message.correlation != 0) {
    correlation_registration = findCorrelation(message.correlation);
    if (correlation_registration == nullptr) {
      return RouteResult::unknown_correlation;
    }
  }

  if (surface_registration != nullptr && correlation_registration != nullptr &&
      surface_registration != correlation_registration) {
    return RouteResult::conflicting_destination;
  }
  auto *registration = surface_registration != nullptr
                           ? surface_registration
                           : correlation_registration;
  return registration->endpoint->receive(std::move(message))
             ? RouteResult::delivered
             : RouteResult::endpoint_rejected;
}

std::size_t MultiSurfaceRouter::size() const noexcept {
  return registrations_.size();
}

std::uint64_t MultiSurfaceRouter::launchGeneration() const noexcept {
  return launch_generation_;
}

MultiSurfaceRouter::Registration *
MultiSurfaceRouter::findSurface(surface::SurfaceKey key) {
  const auto registration =
      std::find_if(registrations_.begin(), registrations_.end(),
                   [key](const Registration &candidate) {
                     return candidate.key == key;
                   });
  return registration == registrations_.end() ? nullptr : &*registration;
}

MultiSurfaceRouter::Registration *
MultiSurfaceRouter::findCorrelation(std::uint64_t correlation) {
  const auto registration = std::find_if(
      registrations_.begin(), registrations_.end(),
      [correlation](const Registration &candidate) {
        return std::find(candidate.correlations.begin(),
                         candidate.correlations.end(),
                         correlation) != candidate.correlations.end();
      });
  return registration == registrations_.end() ? nullptr : &*registration;
}

} // namespace omarchy::plugin_runtime::host_session
