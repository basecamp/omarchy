#include "SurfaceEndpointOwner.h"

#include "SurfaceEndpoint.h"
#include "omarchy/plugin/wire/surface_name.hpp"
#include "omarchy/plugin_runtime/surface/profile.hpp"
#include "remote_surface.hpp"

#include <QQuickWindow>
#include <QThread>

#include <algorithm>
#include <cmath>
#include <limits>
#include <numeric>
#include <optional>
#include <utility>

namespace omarchy::plugin_runtime::bridge {
namespace {

constexpr qsizetype kMaximumPublishedSurfaceKeyCharacters = 512;
constexpr std::uint32_t kDprScaleDenominator = 120;
constexpr double kDprRoundingTolerance = 0.000001;

struct TrustedSurfaceGeometry final {
  std::uint32_t logical_width = 0;
  std::uint32_t logical_height = 0;
  std::uint32_t dpr_numerator = 0;
  std::uint32_t dpr_denominator = 0;
};

enum class GeometryResult : std::uint8_t { ready, not_ready, rejected };

GeometryResult trusted_geometry(qreal width, qreal height, qreal dpr,
                                TrustedSurfaceGeometry &output) noexcept {
  if (!std::isfinite(width) || !std::isfinite(height) || width < 0 ||
      height < 0)
    return GeometryResult::rejected;
  if (width == 0 || height == 0)
    return GeometryResult::not_ready;
  if (std::trunc(width) != width || std::trunc(height) != height ||
      width > surface::kMaximumPixelDimension ||
      height > surface::kMaximumPixelDimension)
    return GeometryResult::rejected;

  if (!std::isfinite(dpr) || dpr <= 0)
    return GeometryResult::rejected;
  const double scaled = static_cast<double>(dpr) * kDprScaleDenominator;
  const double rounded = std::round(scaled);
  if (std::abs(scaled - rounded) > kDprRoundingTolerance || rounded < 1 ||
      rounded > std::numeric_limits<std::uint32_t>::max())
    return GeometryResult::rejected;
  const auto numerator = static_cast<std::uint32_t>(rounded);
  const auto divisor = std::gcd(numerator, kDprScaleDenominator);
  const auto reduced_numerator = numerator / divisor;
  const auto reduced_denominator = kDprScaleDenominator / divisor;
  const auto pixel_width =
      (static_cast<std::uint64_t>(width) * reduced_numerator +
       reduced_denominator - 1) /
      reduced_denominator;
  const auto pixel_height =
      (static_cast<std::uint64_t>(height) * reduced_numerator +
       reduced_denominator - 1) /
      reduced_denominator;
  if (pixel_width > surface::kMaximumPixelDimension ||
      pixel_height > surface::kMaximumPixelDimension)
    return GeometryResult::rejected;

  output = {
      .logical_width = static_cast<std::uint32_t>(width),
      .logical_height = static_cast<std::uint32_t>(height),
      .dpr_numerator = reduced_numerator,
      .dpr_denominator = reduced_denominator,
  };
  return GeometryResult::ready;
}

GeometryResult trusted_geometry(const RemotePluginSurface &surface_item,
                                TrustedSurfaceGeometry &output) noexcept {
  const auto *window = surface_item.window();
  return window == nullptr
             ? GeometryResult::not_ready
             : trusted_geometry(surface_item.width(), surface_item.height(),
                                window->effectiveDevicePixelRatio(), output);
}

} // namespace

PublishedSurfaceAttachment::PublishedSurfaceAttachment(
    QString surface_key, plugins::permissions::ActivationBinding binding,
    std::string declared_surface, qulonglong publication_revision) noexcept
    : surface_key_(std::move(surface_key)), binding_(std::move(binding)),
      declared_surface_(std::move(declared_surface)),
      publication_revision_(publication_revision) {}

struct SurfaceEndpointOwner::Record final {
  QString surface_key;
  RemotePluginSurface *remote = nullptr;
  std::unique_ptr<SurfaceEndpoint> endpoint;
};

SurfaceEndpointOwner::SurfaceEndpointOwner(
    surface_host::MonotonicClock &clock,
    plugins::permissions::ActivationBinding binding,
    qulonglong publication_revision,
    channel::SurfaceSessionPort &session) noexcept
    : clock_(clock), binding_(std::move(binding)),
      publication_revision_(publication_revision), session_(session),
      owner_thread_(std::this_thread::get_id()) {}

SurfaceEndpointOwner::~SurfaceEndpointOwner() noexcept {
  if (!on_owner_thread())
    std::terminate();
  close_all();
}

SurfaceEndpointAttachResult SurfaceEndpointOwner::attach(
    const PublishedSurfaceAttachment &published, QStringView qml_key,
    RemotePluginSurface &surface_item) noexcept {
  if (!on_owner_thread() || closing_all_ ||
      QThread::currentThread() != surface_item.thread())
    return SurfaceEndpointAttachResult::rejected;
  prune_closed();
  if (qml_key != published.surface_key_ || published.surface_key_.isEmpty() ||
      published.surface_key_.size() > kMaximumPublishedSurfaceKeyCharacters ||
      publication_revision_ == 0 ||
      published.publication_revision_ != publication_revision_ ||
      binding_.generation == 0 || published.binding_ != binding_ ||
      !plugin::wire::valid_surface_name(published.declared_surface_) ||
      records_.size() >= plugin::wire::kMaximumPluginSurfaces ||
      std::ranges::any_of(records_, [&](const Record &record) {
        return record.surface_key == published.surface_key_ ||
               record.remote == &surface_item;
      }))
    return SurfaceEndpointAttachResult::rejected;
  TrustedSurfaceGeometry geometry;
  switch (trusted_geometry(surface_item, geometry)) {
  case GeometryResult::not_ready:
    return SurfaceEndpointAttachResult::not_ready;
  case GeometryResult::rejected:
    return SurfaceEndpointAttachResult::rejected;
  case GeometryResult::ready:
    break;
  }
  const auto description = session_.describe(published.declared_surface_);
  if (!description || description->binding != binding_ ||
      description->surface_name != published.declared_surface_ ||
      description->plugin_id != published.binding_.plugin.view() ||
      description->session_nonce == 0 || description->key.id == 0 ||
      description->key.generation != published.binding_.generation)
    return SurfaceEndpointAttachResult::rejected;

  try {
    Record record{
        .surface_key = published.surface_key_,
        .remote = &surface_item,
        .endpoint = std::unique_ptr<SurfaceEndpoint>(
            new SurfaceEndpoint(session_, input_authority_,
                                published.declared_surface_)),
    };
    records_.reserve(records_.size() + 1);
    if (!record.endpoint->attach(surface_item, geometry.logical_width,
                                 geometry.logical_height,
                                 geometry.dpr_numerator,
                                 geometry.dpr_denominator, clock_))
      return SurfaceEndpointAttachResult::rejected;
    records_.push_back(std::move(record));
    return SurfaceEndpointAttachResult::attached;
  } catch (...) {
    return SurfaceEndpointAttachResult::rejected;
  }
}

void SurfaceEndpointOwner::close_all() noexcept {
  if (!on_owner_thread())
    std::terminate();
  if (closing_all_)
    return;
  closing_all_ = true;
  while (true) {
    const auto candidate = std::ranges::find_if(records_, [](const Record &record) {
      return record.endpoint->state() != SurfaceEndpoint::State::closing;
    });
    if (candidate == records_.end())
      break;
    auto endpoint = std::move(candidate->endpoint);
    records_.erase(candidate);
    endpoint->close();
  }
  closing_all_ = false;
}

void SurfaceEndpointOwner::prune_closed() noexcept {
  std::erase_if(records_, [](const Record &record) {
    return record.endpoint->state() ==
           SurfaceEndpoint::State::closed;
  });
}

bool SurfaceEndpointOwner::on_owner_thread() const noexcept {
  return std::this_thread::get_id() == owner_thread_;
}

#ifdef OMARCHY_SURFACE_ENDPOINT_OWNER_TESTING
bool SurfaceEndpointOwnerTestAccess::route_input(SurfaceEndpointOwner &owner,
                                                 QStringView surface_key,
                                                 HostInputEvent event) {
  const auto found = std::ranges::find_if(
      owner.records_, [surface_key](const SurfaceEndpointOwner::Record &record) {
        return record.surface_key == surface_key;
      });
  return found != owner.records_.end() && found->endpoint &&
         found->endpoint->route(std::move(event));
}

std::size_t SurfaceEndpointOwnerTestAccess::count(
    const SurfaceEndpointOwner &owner) noexcept {
  return owner.records_.size();
}

std::optional<SurfaceEndpointOwnerTestAccess::Geometry>
SurfaceEndpointOwnerTestAccess::geometry(
    const RemotePluginSurface &surface) noexcept {
  TrustedSurfaceGeometry geometry;
  if (trusted_geometry(surface, geometry) != GeometryResult::ready)
    return std::nullopt;
  return Geometry{.logical_width = geometry.logical_width,
                  .logical_height = geometry.logical_height,
                  .dpr_numerator = geometry.dpr_numerator,
                  .dpr_denominator = geometry.dpr_denominator};
}

std::optional<SurfaceEndpointOwnerTestAccess::Geometry>
SurfaceEndpointOwnerTestAccess::geometry(
    qreal width, qreal height, qreal device_pixel_ratio) noexcept {
  TrustedSurfaceGeometry geometry;
  if (trusted_geometry(width, height, device_pixel_ratio, geometry) !=
      GeometryResult::ready)
    return std::nullopt;
  return Geometry{.logical_width = geometry.logical_width,
                  .logical_height = geometry.logical_height,
                  .dpr_numerator = geometry.dpr_numerator,
                  .dpr_denominator = geometry.dpr_denominator};
}
#endif

} // namespace omarchy::plugin_runtime::bridge
