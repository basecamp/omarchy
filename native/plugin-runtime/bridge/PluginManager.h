#pragma once

#include "PluginSurfaceService.h"
#include "gesture_intent.hpp"

#include <QObject>
#include <QString>
#include <QtQml/qqmlregistration.h>

#include <memory>
#include <utility>
#include <vector>

#ifdef OMARCHY_PLUGIN_MANAGER_TESTING
#include <cstdint>
#include <functional>
#include <string>
#include <string_view>
#endif

class QJSEngine;
class QQmlEngine;

#ifdef OMARCHY_PLUGIN_MANAGER_TESTING
namespace omarchy::plugin_runtime::channel {
class ProductionPluginBootstrap;
}
#endif

namespace omarchy::plugin_runtime::bridge {

class PluginManager final : public QObject {
  Q_OBJECT
  QML_NAMED_ELEMENT(PluginManager)
  QML_SINGLETON
  Q_PROPERTY(bool available READ available NOTIFY availableChanged)
  Q_PROPERTY(QString runtimeVersion READ runtimeVersion CONSTANT)
  Q_PROPERTY(QAbstractItemModel *barSurfaces READ barSurfaces CONSTANT)
  Q_PROPERTY(QAbstractItemModel *panelSurfaces READ panelSurfaces CONSTANT)
  Q_PROPERTY(QAbstractItemModel *overlaySurfaces READ overlaySurfaces CONSTANT)
  Q_PROPERTY(int count READ count NOTIFY surfacesChanged)

public:
  // Qt owns the one QML singleton instance. The constructor is unavailable to
  // QML and ordinary C++ callers; Qt enters through this factory only.
  [[nodiscard]] static PluginManager *create(QQmlEngine *qml_engine,
                                             QJSEngine *js_engine);
  ~PluginManager() override;

  [[nodiscard]] bool available() const noexcept;
  [[nodiscard]] QString runtimeVersion() const;
  [[nodiscard]] QAbstractItemModel *barSurfaces();
  [[nodiscard]] QAbstractItemModel *panelSurfaces();
  [[nodiscard]] QAbstractItemModel *overlaySurfaces();
  [[nodiscard]] int count() const noexcept;

  // This is the complete QML attachment boundary. It resolves only opaque
  // published keys to manager-owned roots and endpoints; without exact typed
  // readiness, attachment and publication stay inert.
  Q_INVOKABLE bool attach(const QString &surface_key, QObject *surface);

signals:
  void availableChanged();
  void surfacesChanged();
  void openRequested(QString sourceSurface, QString targetSurface,
                     QString generation);
  void toggleRequested(QString sourceSurface, QString targetSurface,
                       QString generation);
  void dismissRequested(QString sourceSurface, QString targetSurface,
                        QString generation);

private:
  explicit PluginManager(QObject *parent = nullptr);
  [[nodiscard]] bool publishSurfaces(
      const plugins::permissions::ActivationBinding &binding,
      std::vector<PluginSurfaceService::SurfaceDeclaration> declarations,
      qulonglong revision);
  [[nodiscard]] bool
  withdrawSurfaces(const plugins::permissions::ActivationBinding &binding);
  [[nodiscard]] bool publishIntent(host_session::AdmittedSurfaceIntent intent);

  struct Runtime;

  PluginSurfaceService surfaces_;
  std::unique_ptr<Runtime> runtime_;
  bool available_ = false;

#ifdef OMARCHY_PLUGIN_MANAGER_TESTING
  friend class PluginManagerTestAccess;
#endif
};

#ifdef OMARCHY_PLUGIN_MANAGER_TESTING
class PluginManagerTestAccess final {
public:
  enum class TestJobKind : std::uint8_t { scan, preparation };
  struct SlotObservation final {
    std::string plugin;
    std::uint64_t epoch = 0;
    std::uint8_t retry_attempts = 0;
    bool retry_wait = false;
    bool opening = false;
    bool preparing = false;
  };

  [[nodiscard]] static std::unique_ptr<PluginManager> create() {
    return std::unique_ptr<PluginManager>(new PluginManager);
  }
  [[nodiscard]] static PluginSurfaceService &model(PluginManager &manager) {
    return manager.surfaces_;
  }
  static void
  installRuntime(PluginManager &manager,
                 std::unique_ptr<channel::ProductionPluginBootstrap> bootstrap);
  [[nodiscard]] static bool scanRuntime(PluginManager &manager);
  [[nodiscard]] static std::vector<SlotObservation>
  runtimeSlots(const PluginManager &manager);
  [[nodiscard]] static bool retryRuntime(PluginManager &manager,
                                         std::string_view plugin);
  [[nodiscard]] static bool queueStaleRunningCallback(PluginManager &manager,
                                                      std::string_view plugin);
  using JobSubmitter =
      std::function<bool(TestJobKind, std::function<void()>)>;
  using JobEntryProbe = std::function<void(TestJobKind)>;
  static void setJobSubmitter(PluginManager &manager, JobSubmitter submitter);
  static void setJobEntryProbe(PluginManager &manager, JobEntryProbe probe);
  static void requestAsyncScan(PluginManager &manager);
  static void requestPreparations(PluginManager &manager);
  static void drainRuntime(PluginManager &manager);
  [[nodiscard]] static std::uint8_t
  preparationCount(const PluginManager &manager);
  [[nodiscard]] static bool scanInFlight(const PluginManager &manager);
  [[nodiscard]] static std::uint8_t occupiedPreparationLanes(
      const PluginManager &manager);
  [[nodiscard]] static bool deliverLifecycle(
      PluginManager &manager, std::string_view plugin, std::uint64_t epoch,
      std::uint8_t state, std::uint8_t error);
  [[nodiscard]] static std::weak_ptr<const void>
  deliveryGate(const PluginManager &manager);
  [[nodiscard]] static bool publishSurfaces(
      PluginManager &manager,
      const plugins::permissions::ActivationBinding &binding,
      std::vector<PluginSurfaceService::SurfaceDeclaration> declarations,
      qulonglong revision) {
    return manager.publishSurfaces(binding, std::move(declarations), revision);
  }
  [[nodiscard]] static bool
  withdrawSurfaces(PluginManager &manager,
                   const plugins::permissions::ActivationBinding &binding) {
    return manager.withdrawSurfaces(binding);
  }
  [[nodiscard]] static bool
  publishIntent(PluginManager &manager,
                host_session::AdmittedSurfaceIntent intent) {
    return manager.publishIntent(std::move(intent));
  }
};
#endif

} // namespace omarchy::plugin_runtime::bridge
