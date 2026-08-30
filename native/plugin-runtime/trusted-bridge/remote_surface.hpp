#pragma once

#include "omarchy/plugin_runtime/surface/bridge_contract.hpp"
#include "omarchy/plugin_runtime/surface/input.hpp"
#include "omarchy/plugin_runtime/surface/surface_state.hpp"
#include "render_input_transport.hpp"

#include <QImage>
#include <QList>
#include <QMouseEvent>
#include <QQuickPaintedItem>
#include <QRect>
#include <QtQml/qqmlregistration.h>

#include <cstdint>
#include <memory>
#include <optional>

namespace omarchy::plugin_runtime::bridge {

struct HostPointerEvent {
  qreal x = 0;
  qreal y = 0;
  Qt::MouseButton button = Qt::NoButton;
  bool pressed = false;
  bool application_synthesized = true;
};

class HostPointerRouter {
public:
  virtual ~HostPointerRouter() = default;
  virtual bool route(const HostPointerEvent &event) = 0;
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
  [[nodiscard]] bool bindHostPointerRouter(HostPointerRouter &router) noexcept;
  void unbindHostPointerRouter(HostPointerRouter &router) noexcept;
  [[nodiscard]] bool bindHostInputRegionRouter(HostInputRegionRouter &router);
  void unbindHostInputRegionRouter(HostInputRegionRouter &router) noexcept;
  bool configure(const surface::TrustedAllocation &allocation) override;
  bool present(surface::SurfaceKey surface, std::uint64_t frame_sequence,
               std::span<const std::byte> trusted_pixels) override;
  bool updateInputRegions(const surface::InputRegionUpdate &update) override;
  void clear(surface::SurfaceKey surface) override;
  void disconnect() override;

  bool suspend();
  bool resume();
  bool beginDestroy();
  bool submitInput(const surface::InputEvent &event);
  bool submitHostRoutedPointerInput(const surface::InputEvent &event);
  bool submitTransientFocus(const surface::FocusEvent &event);
  bool submitFocus(const surface::FocusEvent &event);

  void paint(QPainter *painter) override;

  [[nodiscard]] bool connected() const;
  [[nodiscard]] bool ready() const;
  [[nodiscard]] bool surfaceFocused() const;
  [[nodiscard]] QString inspectionState() const;
  [[nodiscard]] qulonglong surfaceId() const;
  [[nodiscard]] qulonglong surfaceGeneration() const;
  [[nodiscard]] qulonglong frameSequence() const;
  [[nodiscard]] InspectionFailure inspectionFailure() const;
  [[nodiscard]] const QImage &ownedImage() const;
  [[nodiscard]] const QList<QRect> &inputRegions() const;

signals:
  void connectionChanged();
  void frameChanged();
  void focusChanged();
  void surfaceChanged();
  void inspectionChanged();
  void inputRegionsChanged();

private:
  void mousePressEvent(QMouseEvent *event) override;
  void mouseReleaseEvent(QMouseEvent *event) override;
  void routeHostPointerEvent(QMouseEvent &event, bool pressed);
  void fail(InspectionFailure failure, bool terminal);
  void resetFrame();
  void resetInputRegions();

  std::shared_ptr<AuthenticatedInputTransport> transport_;
  HostPointerRouter *host_pointer_router_ = nullptr;
  HostInputRegionRouter *host_input_region_router_ = nullptr;
  RemoteSurfaceLifetimeObserver *lifetime_observer_ = nullptr;
  std::uint64_t input_region_generation_ = 0;
  QList<QRect> input_regions_;
  std::optional<surface::SurfaceState> state_;
  std::optional<surface::InputGate> input_gate_;
  std::optional<surface::FocusGate> focus_gate_;
  QImage image_;
  std::uint64_t frame_sequence_ = 0;
  bool focused_ = false;
  bool connected_ = false;
  InspectionFailure failure_ = InspectionFailure::disconnected;
};

} // namespace omarchy::plugin_runtime::bridge
