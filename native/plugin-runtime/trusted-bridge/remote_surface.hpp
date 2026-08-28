#pragma once

#include "omarchy/plugin_runtime/surface/bridge_contract.hpp"
#include "omarchy/plugin_runtime/surface/input.hpp"
#include "omarchy/plugin_runtime/surface/surface_state.hpp"
#include "render_input_transport.hpp"

#include <QImage>
#include <QQuickPaintedItem>
#include <QtQml/qqmlregistration.h>

#include <cstdint>
#include <memory>
#include <optional>

namespace omarchy::plugin_runtime::bridge {

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

  void bindTransport(std::shared_ptr<AuthenticatedInputTransport> transport);
  bool configure(const surface::TrustedAllocation &allocation) override;
  bool present(surface::SurfaceKey surface, std::uint64_t frame_sequence,
               std::span<const std::byte> trusted_pixels) override;
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

signals:
  void connectionChanged();
  void frameChanged();
  void focusChanged();
  void surfaceChanged();
  void inspectionChanged();

private:
  void fail(InspectionFailure failure, bool terminal);
  void resetFrame();

  std::shared_ptr<AuthenticatedInputTransport> transport_;
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
