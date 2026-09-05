#pragma once

#include "omarchy/plugin_runtime/surface/bridge_contract.hpp"
#include "omarchy/plugin_runtime/surface/input.hpp"
#include "omarchy/plugin_runtime/surface/surface_state.hpp"
#include "TrustedInputAuthority.h"
#include "render_input_transport.hpp"

#include <QImage>
#include <QInputMethodEvent>
#include <QList>
#include <QMetaObject>
#include <QPointer>
#include <QQuickPaintedItem>
#include <QRect>
#include <QTimer>
#include <QtQml/qqmlregistration.h>

#include <cstdint>
#include <memory>
#include <optional>

namespace omarchy::plugin_runtime::bridge {

class HostInputRouter {
public:
  virtual ~HostInputRouter() = default;
  virtual bool route(HostInputEvent event) = 0;
  virtual bool cancel(std::uint64_t device) = 0;
};
class HostInputRegionRouter {
public:
  virtual ~HostInputRegionRouter() = default;
  virtual bool apply(const surface::InputRegionUpdate &) = 0;
};
class RemoteSurfaceLifetimeObserver {
public:
  virtual ~RemoteSurfaceLifetimeObserver() = default;
  // Runs at the start of RemotePluginSurface's C++ destructor, while its
  // trusted sink, transport and QQuickItem base are still alive.
  virtual void remote_surface_destroying() noexcept = 0;
};
class RemotePluginSurfaceTestAccess;

class RemotePluginSurface : public QQuickPaintedItem,
                            public surface::TrustedFrameSink {
  Q_OBJECT
  QML_ELEMENT
  Q_PROPERTY(bool connected READ connected NOTIFY connectionChanged)
  Q_PROPERTY(bool ready READ ready NOTIFY frameChanged)
  Q_PROPERTY(bool surfaceFocused READ surfaceFocused NOTIFY focusChanged)
  Q_PROPERTY(
      QString inspectionState READ inspectionState NOTIFY inspectionChanged)
  Q_PROPERTY(qulonglong surfaceId READ surfaceId NOTIFY surfaceChanged)
  Q_PROPERTY(
      qulonglong surfaceGeneration READ surfaceGeneration NOTIFY surfaceChanged)
  Q_PROPERTY(qulonglong frameSequence READ frameSequence NOTIFY frameChanged)
  Q_PROPERTY(
      QList<QRect> inputRegions READ inputRegions NOTIFY inputRegionsChanged)

public:
  enum class InspectionFailure {
    none,
    disconnected,
    invalid_allocation,
    invalid_lifecycle,
    stale_frame,
    invalid_pixels,
    input_rejected,
    transport_failed,
  };
  Q_ENUM(InspectionFailure)

  explicit RemotePluginSurface(QQuickItem *parent = nullptr);
  ~RemotePluginSurface() override;

  [[nodiscard]] bool bindTransport(
      std::shared_ptr<AuthenticatedInputTransport> transport) noexcept;
  void unbindTransport(
      const std::shared_ptr<AuthenticatedInputTransport> &transport) noexcept;
  [[nodiscard]] bool
  bindLifetimeObserver(RemoteSurfaceLifetimeObserver &observer);
  void unbindLifetimeObserver(
      RemoteSurfaceLifetimeObserver &observer) noexcept;
  [[nodiscard]] bool bindHostInputRouter(HostInputRouter &router) noexcept;
  void unbindHostInputRouter(HostInputRouter &router) noexcept;
  [[nodiscard]] bool bindHostInputRegionRouter(HostInputRegionRouter &router);
  void unbindHostInputRegionRouter(HostInputRegionRouter &router) noexcept;
  bool configure(const surface::TrustedAllocation &allocation) override;
  bool present(surface::SurfaceKey surface, std::uint64_t frame_sequence,
               std::span<const std::byte> trusted_pixels) override;
  bool updateInputRegions(const surface::InputRegionUpdate &update) override;
  void clear(surface::SurfaceKey surface) override;
  void disconnect() override;

  bool submitInput(const surface::InputEvent &event);

  void paint(QPainter *painter) override;

  [[nodiscard]] bool connected() const;
  [[nodiscard]] bool ready() const;
  [[nodiscard]] bool surfaceFocused() const;
  [[nodiscard]] QString inspectionState() const;
  [[nodiscard]] qulonglong surfaceId() const;
  [[nodiscard]] qulonglong surfaceGeneration() const;
  [[nodiscard]] qulonglong frameSequence() const;
  [[nodiscard]] const QList<QRect> &inputRegions() const;

signals:
  void connectionChanged();
  void frameChanged();
  void focusChanged();
  void surfaceChanged();
  void inspectionChanged();
  void inputRegionsChanged();

private:
  friend class RemotePluginSurfaceTestAccess;
  bool eventFilter(QObject *watched, QEvent *event) override;
  bool childMouseEventFilter(QQuickItem *item, QEvent *event) override;
  void geometryChange(const QRectF &new_geometry,
                      const QRectF &old_geometry) override;
  void hoverMoveEvent(QHoverEvent *event) override;
  void mouseMoveEvent(QMouseEvent *event) override;
  void mousePressEvent(QMouseEvent *event) override;
  void mouseReleaseEvent(QMouseEvent *event) override;
  void wheelEvent(QWheelEvent *event) override;
  void keyPressEvent(QKeyEvent *event) override;
  void keyReleaseEvent(QKeyEvent *event) override;
  void inputMethodEvent(QInputMethodEvent *event) override;
  void touchEvent(QTouchEvent *event) override;
  void focusInEvent(QFocusEvent *event) override;
  void focusOutEvent(QFocusEvent *event) override;
  [[nodiscard]] bool routeHostInput(HostInputPayload payload,
                                    const QInputEvent &event,
                                    bool trusted_physical);
  [[nodiscard]] bool routeMouseInput(QMouseEvent &event,
                                     bool trusted_physical);
  [[nodiscard]] bool consumeWindowPointerClaim(const QMouseEvent &event);
  void bindWindowInputBoundary(QQuickWindow *window);
  [[nodiscard]] bool cancelHostInput(const QInputEvent &event);
  void fail(InspectionFailure failure, bool terminal);
  void logInputRejectionOnce(std::uint32_t reason_bit, const char *reason,
                             const QMouseEvent &event);
  void resetFrame();
  void resetInputRegions();

  std::shared_ptr<AuthenticatedInputTransport> transport_;
  HostInputRouter *host_input_router_ = nullptr;
  HostInputRegionRouter *host_input_region_router_ = nullptr;
  RemoteSurfaceLifetimeObserver *lifetime_observer_ = nullptr;
  QQuickItem *input_proxy_ = nullptr;
  QMetaObject::Connection window_changed_connection_;
  QPointer<QQuickWindow> input_window_;
  struct WindowPointerClaim {
    std::uint64_t generation = 0;
    QEvent::Type type = QEvent::None;
    ulong timestamp = 0;
    const QPointingDevice *device = nullptr;
    Qt::MouseButton button = Qt::NoButton;
    Qt::MouseButtons buttons = Qt::NoButton;
    Qt::KeyboardModifiers modifiers = Qt::NoModifier;
    QPointF global_position;
  };
  std::optional<WindowPointerClaim> window_pointer_claim_;
  std::uint64_t next_window_pointer_claim_generation_ = 0;
  std::uint64_t expiring_window_pointer_claim_generation_ = 0;
  QTimer window_pointer_claim_expiry_;
  std::uint64_t input_region_generation_ = 0;
  std::uint32_t logged_input_rejections_ = 0;
  QList<QRect> input_regions_;
  std::optional<surface::SurfaceState> state_;
  QImage image_;
  std::uint64_t frame_sequence_ = 0;
  bool focused_ = false;
  bool connected_ = false;
  InspectionFailure failure_ = InspectionFailure::disconnected;
};

} // namespace omarchy::plugin_runtime::bridge
