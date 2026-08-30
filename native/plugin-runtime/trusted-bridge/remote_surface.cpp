#include "remote_surface.hpp"

#include "omarchy/plugin_runtime/surface/profile.hpp"

#include <QPainter>

#include <limits>
#include <type_traits>
#include <utility>

namespace omarchy::plugin_runtime::bridge {
namespace {

static_assert(std::is_nothrow_move_assignable_v<QList<QRect>>);

QString failure_name(RemotePluginSurface::InspectionFailure failure) {
  using Failure = RemotePluginSurface::InspectionFailure;
  switch (failure) {
  case Failure::none:
    return QStringLiteral("ready");
  case Failure::disconnected:
    return QStringLiteral("disconnected");
  case Failure::invalid_allocation:
    return QStringLiteral("invalid-allocation");
  case Failure::invalid_lifecycle:
    return QStringLiteral("invalid-lifecycle");
  case Failure::stale_frame:
    return QStringLiteral("stale-frame");
  case Failure::invalid_pixels:
    return QStringLiteral("invalid-pixels");
  case Failure::input_rejected:
    return QStringLiteral("input-rejected");
  case Failure::transport_failed:
    return QStringLiteral("transport-failed");
  }
  return QStringLiteral("invalid-state");
}

} // namespace

RemotePluginSurface::RemotePluginSurface(QQuickItem *parent)
    : QQuickPaintedItem(parent) {
  setAntialiasing(false);
  setOpaquePainting(false);
  setAcceptedMouseButtons(Qt::LeftButton | Qt::RightButton | Qt::MiddleButton |
                          Qt::BackButton | Qt::ForwardButton);
}

RemotePluginSurface::~RemotePluginSurface() {
  auto *observer = std::exchange(lifetime_observer_, nullptr);
  if (observer != nullptr)
    observer->remote_surface_destroying();
}

bool RemotePluginSurface::bindLifetimeObserver(
    RemoteSurfaceLifetimeObserver &observer) {
  if (lifetime_observer_ != nullptr)
    return false;
  lifetime_observer_ = &observer;
  return true;
}

void RemotePluginSurface::unbindLifetimeObserver(
    RemoteSurfaceLifetimeObserver &observer) noexcept {
  if (lifetime_observer_ == &observer)
    lifetime_observer_ = nullptr;
}

bool RemotePluginSurface::bindHostPointerRouter(
    HostPointerRouter &router) noexcept {
  if (host_pointer_router_ != nullptr)
    return false;
  host_pointer_router_ = &router;
  return true;
}

void RemotePluginSurface::unbindHostPointerRouter(
    HostPointerRouter &router) noexcept {
  if (host_pointer_router_ == &router)
    host_pointer_router_ = nullptr;
}

bool RemotePluginSurface::bindHostInputRegionRouter(
    HostInputRegionRouter &router) {
  if (host_input_region_router_ != nullptr)
    return false;
  host_input_region_router_ = &router;
  return true;
}

void RemotePluginSurface::unbindHostInputRegionRouter(
    HostInputRegionRouter &router) noexcept {
  if (host_input_region_router_ == &router) {
    host_input_region_router_ = nullptr;
    resetInputRegions();
  }
}

bool RemotePluginSurface::updateInputRegions(
    const surface::InputRegionUpdate &update) {
  if (!state_ || update.surface != state_->allocation().surface ||
      state_->phase() != surface::SurfacePhase::active ||
      update.generation <= input_region_generation_ ||
      update.count > update.regions.size() ||
      host_input_region_router_ == nullptr)
    return false;
  QList<QRect> projected;
  projected.reserve(static_cast<qsizetype>(update.count));
  for (std::uint32_t index = 0; index < update.count; ++index) {
    const auto &region = update.regions[index];
    if (region.width >
            static_cast<std::uint32_t>(std::numeric_limits<int>::max()) ||
        region.height >
            static_cast<std::uint32_t>(std::numeric_limits<int>::max()))
      return false;
    projected.emplaceBack(region.x, region.y, static_cast<int>(region.width),
                          static_cast<int>(region.height));
  }
  if (!host_input_region_router_->apply(update))
    return false;
  input_region_generation_ = update.generation;
  input_regions_ = std::move(projected);
  emit inputRegionsChanged();
  return true;
}

void RemotePluginSurface::mousePressEvent(QMouseEvent *event) {
  routeHostPointerEvent(*event, true);
}

void RemotePluginSurface::mouseReleaseEvent(QMouseEvent *event) {
  routeHostPointerEvent(*event, false);
}

void RemotePluginSurface::routeHostPointerEvent(QMouseEvent &event,
                                                bool pressed) {
  const bool application_synthesized =
      event.source() == Qt::MouseEventSynthesizedByApplication;
  event.setAccepted(host_pointer_router_ != nullptr &&
                    host_pointer_router_->route(
                        {.x = event.position().x(),
                         .y = event.position().y(),
                         .button = event.button(),
                         .pressed = pressed,
                         .application_synthesized = application_synthesized}));
}

bool RemotePluginSurface::bindTransport(
    std::shared_ptr<AuthenticatedInputTransport> transport) noexcept {
  if (transport_ != nullptr || state_.has_value() || transport == nullptr ||
      !transport->connected()) {
    if (transport != nullptr)
      transport->disconnect();
    return false;
  }
  transport_ = std::move(transport);
  return true;
}

void RemotePluginSurface::unbindTransport(
    const std::shared_ptr<AuthenticatedInputTransport> &transport) noexcept {
  if (transport_ != transport)
    return;
  if (transport_ != nullptr)
    transport_->disconnect();
  transport_.reset();
}

bool RemotePluginSurface::configure(
    const surface::TrustedAllocation &allocation) {
  if (state_.has_value()) {
    fail(InspectionFailure::invalid_lifecycle, true);
    return false;
  }
  auto state = surface::SurfaceState::create(allocation);
  auto input_gate = surface::InputGate::create(allocation);
  auto focus_gate = surface::FocusGate::create(allocation);
  if (!state || !input_gate || !focus_gate ||
      allocation.pixel_format != surface::kRgba8888Premultiplied ||
      allocation.frame_bytes > surface::kMaximumFrameBytes ||
      transport_ == nullptr || !transport_->connected()) {
    fail(InspectionFailure::invalid_allocation, true);
    return false;
  }
  if (!state->apply(surface::SurfaceTransition::activate)) {
    fail(InspectionFailure::invalid_lifecycle, true);
    return false;
  }
  state_ = std::move(state);
  input_gate_ = std::move(input_gate);
  focus_gate_ = std::move(focus_gate);
  connected_ = true;
  focused_ = false;
  failure_ = InspectionFailure::none;
  resetInputRegions();
  resetFrame();
  setImplicitWidth(allocation.logical_width);
  setImplicitHeight(allocation.logical_height);
  emit connectionChanged();
  emit focusChanged();
  emit surfaceChanged();
  emit inspectionChanged();
  return true;
}

bool RemotePluginSurface::present(surface::SurfaceKey key,
                                  std::uint64_t frame_sequence,
                                  std::span<const std::byte> trusted_pixels) {
  if (!connected_ || transport_ == nullptr || !transport_->connected() ||
      !state_ || !state_->accepts_frame(key) || frame_sequence == 0 ||
      frame_sequence <= frame_sequence_) {
    fail(InspectionFailure::stale_frame, false);
    return false;
  }
  const auto &allocation = state_->allocation();
  if (trusted_pixels.size() != allocation.frame_bytes ||
      allocation.frame_bytes >
          static_cast<std::uint64_t>(std::numeric_limits<int>::max())) {
    fail(InspectionFailure::invalid_pixels, false);
    return false;
  }
  const QImage borrowed(reinterpret_cast<const uchar *>(trusted_pixels.data()),
                        static_cast<int>(allocation.pixel_width),
                        static_cast<int>(allocation.pixel_height),
                        static_cast<qsizetype>(allocation.stride),
                        QImage::Format_RGBA8888_Premultiplied);
  QImage owned = borrowed.copy();
  if (owned.isNull() ||
      owned.sizeInBytes() != static_cast<qsizetype>(allocation.frame_bytes)) {
    fail(InspectionFailure::invalid_pixels, false);
    return false;
  }
  owned.setDevicePixelRatio(static_cast<qreal>(allocation.dpr_numerator) /
                            static_cast<qreal>(allocation.dpr_denominator));
  image_ = owned;
  frame_sequence_ = frame_sequence;
  failure_ = InspectionFailure::none;
  update();
  emit frameChanged();
  emit inspectionChanged();
  return true;
}

void RemotePluginSurface::clear(surface::SurfaceKey key) {
  if (state_ && state_->allocation().surface == key)
    resetFrame();
}

void RemotePluginSurface::disconnect() {
  if (transport_ != nullptr)
    transport_->disconnect();
  if (state_ && state_->phase() != surface::SurfacePhase::destroyed) {
    if (state_->phase() != surface::SurfacePhase::destroying)
      (void)state_->apply(surface::SurfaceTransition::begin_destroy);
    if (state_->phase() == surface::SurfacePhase::destroying)
      (void)state_->apply(surface::SurfaceTransition::finish_destroy);
  }
  fail(InspectionFailure::disconnected, true);
}

bool RemotePluginSurface::suspend() {
  if (!state_ || !state_->apply(surface::SurfaceTransition::suspend)) {
    fail(InspectionFailure::invalid_lifecycle, false);
    return false;
  }
  focused_ = false;
  emit focusChanged();
  return true;
}

bool RemotePluginSurface::resume() {
  if (!state_ || !state_->apply(surface::SurfaceTransition::resume)) {
    fail(InspectionFailure::invalid_lifecycle, false);
    return false;
  }
  return true;
}

bool RemotePluginSurface::beginDestroy() {
  if (!state_ || !state_->apply(surface::SurfaceTransition::begin_destroy)) {
    fail(InspectionFailure::invalid_lifecycle, false);
    return false;
  }
  focused_ = false;
  resetFrame();
  resetInputRegions();
  emit focusChanged();
  return true;
}

bool RemotePluginSurface::submitInput(const surface::InputEvent &event) {
  if (!state_ || !input_gate_ || transport_ == nullptr ||
      input_gate_->accept(event,
                          state_->phase() == surface::SurfacePhase::active,
                          focused_) != surface::InputValidation::accepted) {
    fail(InspectionFailure::input_rejected, false);
    return false;
  }
  if (!transport_->submit(event)) {
    fail(InspectionFailure::transport_failed, true);
    return false;
  }
  return true;
}

bool RemotePluginSurface::submitHostRoutedPointerInput(
    const surface::InputEvent &event) {
  if ((event.kind != surface::InputKind::pointer_button &&
       event.kind != surface::InputKind::touch) ||
      !state_ || !input_gate_ || transport_ == nullptr ||
      input_gate_->accept(event,
                          state_->phase() == surface::SurfacePhase::active,
                          true) != surface::InputValidation::accepted) {
    fail(InspectionFailure::input_rejected, false);
    return false;
  }
  if (!transport_->submit(event)) {
    fail(InspectionFailure::transport_failed, true);
    return false;
  }
  return true;
}

bool RemotePluginSurface::submitTransientFocus(
    const surface::FocusEvent &event) {
  if (!state_ || !focus_gate_ || transport_ == nullptr ||
      focus_gate_->accept(event,
                          state_->phase() == surface::SurfacePhase::active) !=
          surface::InputValidation::accepted) {
    fail(InspectionFailure::input_rejected, false);
    return false;
  }
  if (!transport_->submit_focus(event)) {
    fail(InspectionFailure::transport_failed, true);
    return false;
  }
  return true;
}

bool RemotePluginSurface::submitFocus(const surface::FocusEvent &event) {
  if (!state_ || !focus_gate_ || transport_ == nullptr ||
      focus_gate_->accept(event,
                          state_->phase() == surface::SurfacePhase::active) !=
          surface::InputValidation::accepted) {
    fail(InspectionFailure::input_rejected, false);
    return false;
  }
  if (!transport_->submit_focus(event)) {
    fail(InspectionFailure::transport_failed, true);
    return false;
  }
  focused_ = event.focused;
  emit focusChanged();
  return true;
}

void RemotePluginSurface::paint(QPainter *painter) {
  if (!image_.isNull())
    painter->drawImage(boundingRect(), image_);
}

bool RemotePluginSurface::connected() const { return connected_; }
bool RemotePluginSurface::ready() const { return !image_.isNull(); }
bool RemotePluginSurface::surfaceFocused() const { return focused_; }
QString RemotePluginSurface::inspectionState() const {
  return failure_name(failure_);
}
qulonglong RemotePluginSurface::surfaceId() const {
  return state_ ? state_->allocation().surface.id : 0;
}
qulonglong RemotePluginSurface::surfaceGeneration() const {
  return state_ ? state_->allocation().surface.generation : 0;
}
qulonglong RemotePluginSurface::frameSequence() const {
  return frame_sequence_;
}
RemotePluginSurface::InspectionFailure
RemotePluginSurface::inspectionFailure() const {
  return failure_;
}
const QImage &RemotePluginSurface::ownedImage() const { return image_; }

const QList<QRect> &RemotePluginSurface::inputRegions() const {
  return input_regions_;
}

void RemotePluginSurface::fail(InspectionFailure failure, bool terminal) {
  failure_ = failure;
  if (terminal) {
    if (transport_ != nullptr)
      transport_->disconnect();
    if (state_ && state_->phase() != surface::SurfacePhase::destroyed) {
      if (state_->phase() != surface::SurfacePhase::destroying)
        (void)state_->apply(surface::SurfaceTransition::begin_destroy);
      if (state_->phase() == surface::SurfacePhase::destroying)
        (void)state_->apply(surface::SurfaceTransition::finish_destroy);
    }
    connected_ = false;
    focused_ = false;
    resetFrame();
    resetInputRegions();
    emit connectionChanged();
    emit focusChanged();
  }
  emit inspectionChanged();
}

void RemotePluginSurface::resetFrame() {
  const bool changed = !image_.isNull() || frame_sequence_ != 0;
  image_ = {};
  frame_sequence_ = 0;
  update();
  if (changed)
    emit frameChanged();
}

void RemotePluginSurface::resetInputRegions() {
  input_region_generation_ = 0;
  if (input_regions_.isEmpty())
    return;
  input_regions_.clear();
  emit inputRegionsChanged();
}

} // namespace omarchy::plugin_runtime::bridge
