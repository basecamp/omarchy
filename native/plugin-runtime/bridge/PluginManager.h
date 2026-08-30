#pragma once

#include "PluginSurfaceService.h"
#include "gesture_intent.hpp"

#include <QObject>
#include <QString>
#include <QtQml/qqmlregistration.h>

#include <utility>
#include <memory>
#include <vector>

class QJSEngine;
class QQmlEngine;

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

  [[nodiscard]] bool available() const noexcept;
  [[nodiscard]] QString runtimeVersion() const;
  [[nodiscard]] QAbstractItemModel *barSurfaces();
  [[nodiscard]] QAbstractItemModel *panelSurfaces();
  [[nodiscard]] QAbstractItemModel *overlaySurfaces();
  [[nodiscard]] int count() const noexcept;

  // This is the complete QML attachment boundary. N8D5C will resolve the
  // opaque published key to a manager-owned root and endpoint. Until that
  // readiness source exists, attachment and publication both stay inert.
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
  [[nodiscard]] bool withdrawSurfaces(
      const plugins::permissions::ActivationBinding &binding);
  [[nodiscard]] bool publishIntent(host_session::AdmittedSurfaceIntent intent);

  PluginSurfaceService surfaces_;
  bool available_ = false;

#ifdef OMARCHY_PLUGIN_MANAGER_TESTING
  friend class PluginManagerTestAccess;
#endif
};

#ifdef OMARCHY_PLUGIN_MANAGER_TESTING
class PluginManagerTestAccess final {
public:
  [[nodiscard]] static std::unique_ptr<PluginManager> create() {
    return std::unique_ptr<PluginManager>(new PluginManager);
  }
  [[nodiscard]] static PluginSurfaceService &model(PluginManager &manager) {
    return manager.surfaces_;
  }
  [[nodiscard]] static bool publishSurfaces(
      PluginManager &manager,
      const plugins::permissions::ActivationBinding &binding,
      std::vector<PluginSurfaceService::SurfaceDeclaration> declarations,
      qulonglong revision) {
    return manager.publishSurfaces(binding, std::move(declarations), revision);
  }
  [[nodiscard]] static bool withdrawSurfaces(
      PluginManager &manager,
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
