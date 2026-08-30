#include "qt_touch_injector.hpp"

#include <QEventPoint>
#include <QGuiApplication>
#include <QInputDevice>
#include <QPointingDevice>
#include <QScreen>
#include <QWindow>
#include <QtGui/private/qhighdpiscaling_p.h>
#include <QtGui/private/qinputdevice_p.h>
#include <QtGui/qpa/qwindowsysteminterface.h>

#include <algorithm>

namespace omarchy::plugin_runtime::worker {
namespace {

QEventPoint::State point_state(surface::TouchPointState state) {
  switch (state) {
  case surface::TouchPointState::pressed:
    return QEventPoint::State::Pressed;
  case surface::TouchPointState::updated:
    return QEventPoint::State::Updated;
  case surface::TouchPointState::stationary:
    return QEventPoint::State::Stationary;
  case surface::TouchPointState::released:
    return QEventPoint::State::Released;
  }
  return QEventPoint::State::Unknown;
}

QRect native_virtual_geometry(const QWindow &window) {
  QRect geometry;
  for (const QScreen *screen : QGuiApplication::screens())
    geometry |= QHighDpi::toNativePixels(screen->geometry(), screen);
  if (geometry.isEmpty()) {
    const QPointF origin = QHighDpi::toNativeGlobalPosition(
        window.mapToGlobal(QPointF()), &window);
    geometry = QRect(origin.toPoint(), window.size());
  }
  return geometry;
}

QPointF normalized_position(const QRect &geometry,
                            const QPointF &native_global_position) {
  if (geometry.width() <= 0 || geometry.height() <= 0)
    return {};
  return {
      std::clamp((native_global_position.x() - geometry.x()) /
                     geometry.width(),
                 0.0, 1.0),
      std::clamp((native_global_position.y() - geometry.y()) /
                     geometry.height(),
                 0.0, 1.0),
  };
}

} // namespace

struct QtTouchInjector::Impl {
  Impl()
      : device(QStringLiteral("omarchy-plugin-touch"), 0,
               QInputDevice::DeviceType::TouchScreen,
               QPointingDevice::PointerType::Finger,
               QInputDevice::Capability::Position |
                   QInputDevice::Capability::Area |
                   QInputDevice::Capability::Pressure |
                   QInputDevice::Capability::NormalizedPosition,
               static_cast<int>(surface::kMaximumTouchPoints), 0) {
    QWindowSystemInterface::registerInputDevice(&device);
  }

  QPointingDevice device;
};

QtTouchInjector::QtTouchInjector() : implementation_(std::make_unique<Impl>()) {}

QtTouchInjector::~QtTouchInjector() = default;

void QtTouchInjector::deliver(QWindow &window,
                              const surface::TouchFrame &frame,
                              double device_pixel_ratio) {
  // SynchronousDelivery completes dispatch before returning. Qt's bool result
  // is receiver acceptance, not a transport status; an unhandled frame is valid.
  if (frame.phase == surface::TouchFramePhase::cancel) {
    (void)QWindowSystemInterface::handleTouchCancelEvent<
        QWindowSystemInterface::SynchronousDelivery>(
        &window, &implementation_->device,
        static_cast<Qt::KeyboardModifiers>(frame.modifiers));
    return;
  }

  QList<QWindowSystemInterface::TouchPoint> points;
  points.reserve(static_cast<qsizetype>(frame.count));
  const QRect device_geometry = native_virtual_geometry(window);
  QInputDevicePrivate::get(&implementation_->device)
      ->setAvailableVirtualGeometry(device_geometry);
  for (std::size_t index = 0; index < frame.count; ++index) {
    const auto &source = frame.points[index];
    const QPointF local(
        static_cast<double>(source.position.x_q16) / 65536.0 *
            device_pixel_ratio,
        static_cast<double>(source.position.y_q16) / 65536.0 *
            device_pixel_ratio);
    const QPointF global = QHighDpi::toNativeGlobalPosition(
        window.mapToGlobal(local), &window);
    QWindowSystemInterface::TouchPoint point;
    point.id = static_cast<int>(source.id);
    point.state = point_state(source.state);
    point.area = QRectF(global - QPointF(4.0, 4.0), QSizeF(8.0, 8.0));
    point.normalPosition = normalized_position(device_geometry, global);
    point.pressure = source.state == surface::TouchPointState::released
                         ? 0.0
                         : 1.0;
    points.append(point);
  }
  (void)QWindowSystemInterface::handleTouchEvent<
      QWindowSystemInterface::SynchronousDelivery>(
      &window, &implementation_->device, points,
      static_cast<Qt::KeyboardModifiers>(frame.modifiers));
}

void QtTouchInjector::cancel(QWindow &window) {
  (void)QWindowSystemInterface::handleTouchCancelEvent<
      QWindowSystemInterface::SynchronousDelivery>(
      &window, &implementation_->device);
}

} // namespace omarchy::plugin_runtime::worker
