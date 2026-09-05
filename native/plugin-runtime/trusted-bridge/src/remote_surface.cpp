#include "remote_surface.hpp"

#include "pointer_provenance.hpp"

#include "omarchy/plugin_runtime/surface/profile.hpp"

#include <QDebug>
#include <QFocusEvent>
#include <QHoverEvent>
#include <QKeyEvent>
#include <QMouseEvent>
#include <QPainter>
#include <QPointer>
#include <QQuickWindow>
#include <QTouchEvent>
#include <QWheelEvent>

#include <cmath>
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

std::optional<std::uint32_t> q16(qreal value, std::uint32_t bound) {
  if (!std::isfinite(value) || value < 0 || value >= bound)
    return std::nullopt;
  const double scaled = std::floor(value * 65536.0);
  if (scaled > std::numeric_limits<std::uint32_t>::max())
    return std::nullopt;
  return static_cast<std::uint32_t>(scaled);
}

std::uint32_t modifiers(Qt::KeyboardModifiers value) {
  return static_cast<std::uint32_t>(value.toInt());
}

std::uint32_t buttons(Qt::MouseButtons value) {
  return static_cast<std::uint32_t>(value.toInt());
}

std::uint64_t device_token(const QInputEvent &event) {
  return static_cast<std::uint64_t>(
      reinterpret_cast<std::uintptr_t>(event.device()));
}

detail::PointerProvenance pointer_provenance(const QMouseEvent &event) {
  return detail::classify_pointer_provenance(
      event.spontaneous(), event.source(), event.device());
}

const char *pointer_failure_name(detail::PointerProvenanceFailure failure) {
  using Failure = detail::PointerProvenanceFailure;
  switch (failure) {
  case Failure::none:
    return "none";
  case Failure::not_spontaneous:
    return "not-spontaneous";
  case Failure::synthesized:
    return "synthesized";
  case Failure::missing_device:
    return "missing-device";
  case Failure::unsupported_device:
    return "unsupported-device";
  }
  return "unknown";
}

std::uint32_t pointer_failure_bit(detail::PointerProvenanceFailure failure) {
  return std::uint32_t{1} << static_cast<unsigned>(failure);
}

} // namespace

RemotePluginSurface::RemotePluginSurface(QQuickItem *parent)
    : QQuickPaintedItem(parent) {
  setAntialiasing(false);
  setOpaquePainting(false);
  setAcceptedMouseButtons(Qt::LeftButton | Qt::RightButton | Qt::MiddleButton |
                          Qt::BackButton | Qt::ForwardButton);
  setAcceptHoverEvents(true);
  setAcceptTouchEvents(true);
  setFlag(QQuickItem::ItemAcceptsInputMethod, true);
  setFiltersChildMouseEvents(true);

  // Qt Quick clears QEvent::spontaneous() when it redispatches a window-system
  // mouse event to a QQuickItem with QCoreApplication::sendEvent(). A private
  // child makes childMouseEventFilter() the last public Qt Quick boundary at
  // which both the exact hit target and the original QPA provenance exist.
  input_proxy_ = new QQuickItem(this);
  input_proxy_->setAcceptedMouseButtons(
      Qt::LeftButton | Qt::RightButton | Qt::MiddleButton | Qt::BackButton |
      Qt::ForwardButton);
  input_proxy_->setSize(size());
  window_changed_connection_ =
      connect(this, &QQuickItem::windowChanged, this,
              [this](QQuickWindow *window) { bindWindowInputBoundary(window); });
  window_pointer_claim_expiry_.setSingleShot(true);
  connect(&window_pointer_claim_expiry_, &QTimer::timeout, this, [this] {
    if (window_pointer_claim_ && window_pointer_claim_->generation ==
                                     expiring_window_pointer_claim_generation_)
      window_pointer_claim_.reset();
  });
  bindWindowInputBoundary(window());
}

RemotePluginSurface::~RemotePluginSurface() {
  QObject::disconnect(window_changed_connection_);
  bindWindowInputBoundary(nullptr);
  auto *observer = std::exchange(lifetime_observer_, nullptr);
  if (observer != nullptr)
    observer->remote_surface_destroying();
}

void RemotePluginSurface::bindWindowInputBoundary(QQuickWindow *window) {
  if (input_window_ == window)
    return;
  if (input_window_)
    input_window_->removeEventFilter(this);
  input_window_ = window;
  window_pointer_claim_.reset();
  window_pointer_claim_expiry_.stop();
  if (input_window_)
    input_window_->installEventFilter(this);
}

bool RemotePluginSurface::eventFilter(QObject *watched, QEvent *event) {
  if (watched != input_window_ || event == nullptr)
    return false;
  const bool pointer = event->type() == QEvent::MouseMove ||
                       event->type() == QEvent::MouseButtonPress ||
                       event->type() == QEvent::MouseButtonRelease;
  if (!pointer)
    return false;

  window_pointer_claim_.reset();
  const auto &mouse = *static_cast<QMouseEvent *>(event);
  if (!pointer_provenance(mouse).trusted() || !isVisible() ||
      !contains(mapFromScene(mouse.position())))
    return false;
  if (++next_window_pointer_claim_generation_ == 0)
    ++next_window_pointer_claim_generation_;
  const auto generation = next_window_pointer_claim_generation_;
  window_pointer_claim_ = WindowPointerClaim{
      .generation = generation,
      .type = mouse.type(),
      .timestamp = mouse.timestamp(),
      .device = mouse.pointingDevice(),
      .button = mouse.button(),
      .buttons = mouse.buttons(),
      .modifiers = mouse.modifiers(),
      .global_position = mouse.globalPosition(),
  };
  expiring_window_pointer_claim_generation_ = generation;
  window_pointer_claim_expiry_.start(0);
  return false;
}

bool RemotePluginSurface::consumeWindowPointerClaim(
    const QMouseEvent &event) {
  const auto claim = std::exchange(window_pointer_claim_, std::nullopt);
  return claim && claim->type == event.type() &&
         claim->timestamp == event.timestamp() &&
         claim->device == event.pointingDevice() &&
         claim->button == event.button() && claim->buttons == event.buttons() &&
         claim->modifiers == event.modifiers() &&
         claim->global_position == event.globalPosition();
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

bool RemotePluginSurface::bindHostInputRouter(
    HostInputRouter &router) noexcept {
  if (host_input_router_ != nullptr)
    return false;
  host_input_router_ = &router;
  return true;
}

void RemotePluginSurface::unbindHostInputRouter(
    HostInputRouter &router) noexcept {
  if (host_input_router_ == &router)
    host_input_router_ = nullptr;
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

bool RemotePluginSurface::routeHostInput(HostInputPayload payload,
                                         const QInputEvent &event,
                                         bool trusted_physical) {
  return host_input_router_ != nullptr &&
         host_input_router_->route({.payload = std::move(payload),
                                    .device = device_token(event),
                                    .trusted_physical = trusted_physical});
}

bool RemotePluginSurface::cancelHostInput(const QInputEvent &event) {
  return host_input_router_ != nullptr &&
         host_input_router_->cancel(device_token(event));
}

void RemotePluginSurface::geometryChange(const QRectF &new_geometry,
                                         const QRectF &old_geometry) {
  QQuickPaintedItem::geometryChange(new_geometry, old_geometry);
  if (input_proxy_ != nullptr) {
    input_proxy_->setPosition({0, 0});
    input_proxy_->setSize(new_geometry.size());
  }
}

bool RemotePluginSurface::childMouseEventFilter(QQuickItem *item,
                                                QEvent *event) {
  if (item != input_proxy_ || event == nullptr)
    return false;

  const bool supported = event->type() == QEvent::MouseMove ||
                         event->type() == QEvent::MouseButtonPress ||
                         event->type() == QEvent::MouseButtonRelease;
  if (!supported)
    return false;

  auto &mouse = *static_cast<QMouseEvent *>(event);
  const bool exact_geometry =
      state_.has_value() && input_proxy_->x() == 0 && input_proxy_->y() == 0 &&
      input_proxy_->width() == width() &&
      input_proxy_->height() == height() &&
      width() == state_->allocation().logical_width &&
      height() == state_->allocation().logical_height;
  const auto provenance = pointer_provenance(mouse);
  const bool trusted = provenance.trusted() ||
                       (provenance.failure ==
                            detail::PointerProvenanceFailure::not_spontaneous &&
                        consumeWindowPointerClaim(mouse));
  if (!exact_geometry || !trusted) {
    window_pointer_claim_.reset();
    if (!exact_geometry) {
      logInputRejectionOnce(std::uint32_t{1} << 8, "geometry-mismatch",
                            mouse);
    } else {
      logInputRejectionOnce(pointer_failure_bit(provenance.failure),
                            pointer_failure_name(provenance.failure), mouse);
    }
    event->ignore();
    return true;
  }

  window_pointer_claim_.reset();
  event->setAccepted(routeMouseInput(mouse, true));
  return true;
}

bool RemotePluginSurface::routeMouseInput(QMouseEvent &event,
                                          bool trusted_physical) {
  if (!state_)
    return false;
  const auto x = q16(event.position().x(), state_->allocation().logical_width);
  const auto y = q16(event.position().y(), state_->allocation().logical_height);
  if (!x || !y) {
    if (event.type() == QEvent::MouseButtonRelease)
      return cancelHostInput(event);
    return false;
  }

  if (event.type() == QEvent::MouseMove) {
    return routeHostInput(
        surface::PointerMotion{.position = {*x, *y},
                               .buttons = buttons(event.buttons()),
                               .modifiers = modifiers(event.modifiers())},
        event, trusted_physical);
  }

  if (event.type() != QEvent::MouseButtonPress &&
      event.type() != QEvent::MouseButtonRelease)
    return false;
  return routeHostInput(
      surface::PointerButton{
          .position = {*x, *y},
          .button = static_cast<std::uint32_t>(event.button()),
          .state = event.type() == QEvent::MouseButtonPress
                       ? surface::ButtonState::pressed
                       : surface::ButtonState::released,
          .buttons = buttons(event.buttons()),
          .modifiers = modifiers(event.modifiers())},
      event, trusted_physical);
}

void RemotePluginSurface::hoverMoveEvent(QHoverEvent *event) {
  if (!state_) {
    event->ignore();
    return;
  }
  const auto x = q16(event->position().x(), state_->allocation().logical_width);
  const auto y = q16(event->position().y(), state_->allocation().logical_height);
  event->setAccepted(x && y && routeHostInput(
      surface::PointerMotion{.position = {*x, *y}}, *event,
      event->spontaneous()));
}

void RemotePluginSurface::mouseMoveEvent(QMouseEvent *event) {
  event->setAccepted(
      routeMouseInput(*event, pointer_provenance(*event).trusted()));
}

void RemotePluginSurface::mousePressEvent(QMouseEvent *event) {
  event->setAccepted(
      routeMouseInput(*event, pointer_provenance(*event).trusted()));
}

void RemotePluginSurface::mouseReleaseEvent(QMouseEvent *event) {
  event->setAccepted(
      routeMouseInput(*event, pointer_provenance(*event).trusted()));
}

void RemotePluginSurface::logInputRejectionOnce(std::uint32_t reason_bit,
                                                const char *reason,
                                                const QMouseEvent &event) {
  if ((logged_input_rejections_ & reason_bit) != 0)
    return;
  logged_input_rejections_ |= reason_bit;
  qInfo().noquote().nospace()
      << "omarchy-plugin-security stage=host-input-pre-router decision=deny"
      << " reason=" << reason << " surface-id=" << surfaceId()
      << " generation=" << surfaceGeneration()
      << " event-type=" << static_cast<int>(event.type())
      << " spontaneous=" << (event.spontaneous() ? "true" : "false")
      << " source=" << static_cast<int>(event.source())
      << " device-type="
      << (event.device() == nullptr ? -1
                                    : static_cast<int>(event.deviceType()));
}

void RemotePluginSurface::wheelEvent(QWheelEvent *event) {
  if (!state_) {
    event->ignore();
    return;
  }
  const auto x = q16(event->position().x(), state_->allocation().logical_width);
  const auto y = q16(event->position().y(), state_->allocation().logical_height);
  const auto phase = event->phase() == Qt::ScrollBegin
                         ? surface::WheelPhase::begin
                     : event->phase() == Qt::ScrollUpdate
                         ? surface::WheelPhase::update
                     : event->phase() == Qt::ScrollMomentum
                         ? surface::WheelPhase::momentum
                     : event->phase() == Qt::ScrollEnd
                         ? surface::WheelPhase::end
                         : surface::WheelPhase::discrete;
  constexpr std::int64_t q16_scale = std::int64_t{1} << 16;
  const auto pixel_x =
      static_cast<std::int64_t>(event->pixelDelta().x()) * q16_scale;
  const auto pixel_y =
      static_cast<std::int64_t>(event->pixelDelta().y()) * q16_scale;
  if (!x || !y || pixel_x < std::numeric_limits<std::int32_t>::min() ||
      pixel_x > std::numeric_limits<std::int32_t>::max() ||
      pixel_y < std::numeric_limits<std::int32_t>::min() ||
      pixel_y > std::numeric_limits<std::int32_t>::max()) {
    if (phase == surface::WheelPhase::end)
      event->setAccepted(cancelHostInput(*event));
    else
      event->ignore();
    return;
  }
  event->setAccepted(routeHostInput(
      surface::Wheel{.position = {*x, *y},
                     .pixel_delta_x_q16 = static_cast<std::int32_t>(pixel_x),
                     .pixel_delta_y_q16 = static_cast<std::int32_t>(pixel_y),
                     .angle_delta_x = event->angleDelta().x(),
                     .angle_delta_y = event->angleDelta().y(),
                     .phase = phase,
                     .buttons = buttons(event->buttons()),
                     .modifiers = modifiers(event->modifiers()),
                     .inverted = event->inverted()},
      *event, event->spontaneous()));
}

void RemotePluginSurface::keyPressEvent(QKeyEvent *event) {
  event->setAccepted(routeHostInput(
      surface::Key{.key = static_cast<std::uint32_t>(event->key()),
                   .native_scan_code = event->nativeScanCode(),
                   .modifiers = modifiers(event->modifiers()),
                   .state = surface::ButtonState::pressed,
                   .auto_repeat = event->isAutoRepeat(),
                   .text = event->text().toUtf8().toStdString()},
      *event, event->spontaneous()));
}

void RemotePluginSurface::keyReleaseEvent(QKeyEvent *event) {
  if (event->isAutoRepeat()) {
    event->accept();
    return;
  }
  event->setAccepted(routeHostInput(
      surface::Key{.key = static_cast<std::uint32_t>(event->key()),
                   .native_scan_code = event->nativeScanCode(),
                   .modifiers = modifiers(event->modifiers()),
                   .state = surface::ButtonState::released,
                   .auto_repeat = false,
                   .text = event->text().toUtf8().toStdString()},
      *event, event->spontaneous()));
}

void RemotePluginSurface::inputMethodEvent(QInputMethodEvent *event) {
  if ((event->commitString().isEmpty() && event->replacementLength() == 0) ||
      event->replacementLength() < 0) {
    event->ignore();
    return;
  }
  event->setAccepted(host_input_router_ != nullptr &&
                     host_input_router_->route(
                         {.payload = surface::TextCommit{
                              .text = event->commitString().toUtf8().toStdString(),
                              .replacement_start = event->replacementStart(),
                              .replacement_length = static_cast<std::uint32_t>(
                                  event->replacementLength())},
                          .device = 0,
                          .trusted_physical = event->spontaneous()}));
}

void RemotePluginSurface::touchEvent(QTouchEvent *event) {
  if (!state_ || event->points().size() >
                     static_cast<qsizetype>(surface::kMaximumTouchPoints)) {
    if (state_ && (event->type() == QEvent::TouchEnd ||
                   event->type() == QEvent::TouchCancel))
      event->setAccepted(cancelHostInput(*event));
    else
      event->ignore();
    return;
  }
  HostTouchFrame frame{
      .phase = event->type() == QEvent::TouchBegin
                   ? surface::TouchFramePhase::begin
               : event->type() == QEvent::TouchEnd
                   ? surface::TouchFramePhase::end
               : event->type() == QEvent::TouchCancel
                   ? surface::TouchFramePhase::cancel
                   : surface::TouchFramePhase::update,
      .count = event->type() == QEvent::TouchCancel
                   ? 0U
                   : static_cast<std::uint32_t>(event->points().size()),
      .modifiers = modifiers(event->modifiers())};
  for (std::size_t index = 0; index < frame.count; ++index) {
    const auto &point = event->points()[static_cast<qsizetype>(index)];
    const auto x = q16(point.position().x(), state_->allocation().logical_width);
    const auto y = q16(point.position().y(), state_->allocation().logical_height);
    if (!x || !y) {
      if (event->type() == QEvent::TouchEnd)
        event->setAccepted(cancelHostInput(*event));
      else
        event->ignore();
      return;
    }
    const auto point_state = point.state() == QEventPoint::State::Pressed
                                 ? surface::TouchPointState::pressed
                             : point.state() == QEventPoint::State::Released
                                 ? surface::TouchPointState::released
                             : point.state() == QEventPoint::State::Updated
                                 ? surface::TouchPointState::updated
                                 : surface::TouchPointState::stationary;
    frame.points[index] = {.id = point.id(),
                           .state = point_state,
                           .position = {*x, *y}};
  }
  event->setAccepted(routeHostInput(frame, *event, event->spontaneous()));
}

void RemotePluginSurface::focusInEvent(QFocusEvent *event) {
  event->setAccepted(host_input_router_ != nullptr &&
                     host_input_router_->route(
                         {.payload = surface::FocusChanged{.focused = true},
                          .device = 0,
                          .trusted_physical = event->spontaneous()}));
}

void RemotePluginSurface::focusOutEvent(QFocusEvent *event) {
  event->setAccepted(host_input_router_ != nullptr &&
                     host_input_router_->route(
                         {.payload = surface::FocusChanged{.focused = false},
                          .device = 0,
                          .trusted_physical = event->spontaneous()}));
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
  if (!state ||
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
  logged_input_rejections_ = 0;
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

bool RemotePluginSurface::submitInput(const surface::InputEvent &event) {
  if (!state_ || transport_ == nullptr ||
      event.surface != state_->allocation().surface ||
      state_->phase() != surface::SurfacePhase::active) {
    fail(InspectionFailure::input_rejected, false);
    return false;
  }
  QPointer<RemotePluginSurface> alive(this);
  if (!transport_->submit(event)) {
    if (!alive)
      return false;
    fail(InspectionFailure::transport_failed, true);
    return false;
  }
  if (!alive)
    return false;
  if (const auto *focus = std::get_if<surface::FocusChanged>(&event.payload)) {
    focused_ = focus->focused;
    emit focusChanged();
  } else if (std::holds_alternative<surface::Cancel>(event.payload) &&
             focused_) {
    focused_ = false;
    emit focusChanged();
  }
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

const QList<QRect> &RemotePluginSurface::inputRegions() const {
  return input_regions_;
}

void RemotePluginSurface::fail(InspectionFailure failure, bool terminal) {
  QPointer<RemotePluginSurface> alive(this);
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
    if (!alive)
      return;
    resetInputRegions();
    if (!alive)
      return;
    emit connectionChanged();
    if (!alive)
      return;
    emit focusChanged();
    if (!alive)
      return;
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
