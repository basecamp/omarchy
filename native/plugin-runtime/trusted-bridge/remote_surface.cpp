#include "remote_surface.hpp"

#include "omarchy/plugin_runtime/surface/profile.hpp"

#include <QPainter>

#include <limits>
#include <utility>

namespace omarchy::plugin_runtime::bridge {
namespace {

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
}

void RemotePluginSurface::bindTransport(
    std::shared_ptr<AuthenticatedInputTransport> transport) {
  if (transport_ != nullptr || state_.has_value()) {
    if (transport != nullptr)
      transport->disconnect();
    fail(InspectionFailure::invalid_lifecycle, true);
    return;
  }
  transport_ = std::move(transport);
  if (transport_ == nullptr || !transport_->connected())
    fail(InspectionFailure::disconnected, true);
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
  const QImage owned = borrowed.copy();
  if (owned.isNull() ||
      owned.sizeInBytes() != static_cast<qsizetype>(allocation.frame_bytes)) {
    fail(InspectionFailure::invalid_pixels, false);
    return false;
  }
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

} // namespace omarchy::plugin_runtime::bridge
