#include "PluginManager.h"

#include "omarchy/plugin_runtime/Version.h"
#include "remote_surface.hpp"

#include <QThread>
#include <QQmlEngine>

#include <string_view>

namespace omarchy::plugin_runtime::bridge {

PluginManager *PluginManager::create(QQmlEngine *qml_engine, QJSEngine *) {
  return new PluginManager(qml_engine);
}

PluginManager::PluginManager(QObject *parent)
    : QObject(parent), surfaces_(this) {
  connect(&surfaces_, &PluginSurfaceService::surfacesChanged, this,
          &PluginManager::surfacesChanged);
  connect(&surfaces_, &PluginSurfaceService::openRequested, this,
          &PluginManager::openRequested);
  connect(&surfaces_, &PluginSurfaceService::toggleRequested, this,
          &PluginManager::toggleRequested);
  connect(&surfaces_, &PluginSurfaceService::dismissRequested, this,
          &PluginManager::dismissRequested);
}

bool PluginManager::available() const noexcept { return available_; }

QString PluginManager::runtimeVersion() const {
  const std::string_view version = plugin_runtime::build_version();
  return QString::fromLatin1(version.data(),
                             static_cast<qsizetype>(version.size()));
}

QAbstractItemModel *PluginManager::barSurfaces() {
  return surfaces_.barSurfaces();
}

QAbstractItemModel *PluginManager::panelSurfaces() {
  return surfaces_.panelSurfaces();
}

QAbstractItemModel *PluginManager::overlaySurfaces() {
  return surfaces_.overlaySurfaces();
}

int PluginManager::count() const noexcept { return surfaces_.count(); }

bool PluginManager::attach(const QString &surface_key, QObject *surface) {
  // QML cannot supply an attachment backend. N8D5C will replace this inert
  // branch with exact lookup against its private, readiness-gated slot table.
  if (QThread::currentThread() != thread() || surface == nullptr ||
      qobject_cast<RemotePluginSurface *>(surface) == nullptr ||
      !surfaces_.contains(surface_key))
    return false;
  return false;
}

bool PluginManager::publishSurfaces(
    const plugins::permissions::ActivationBinding &binding,
    std::vector<PluginSurfaceService::SurfaceDeclaration> declarations,
    qulonglong revision) {
  return surfaces_.publishSurfaces(binding, std::move(declarations), revision);
}

bool PluginManager::withdrawSurfaces(
    const plugins::permissions::ActivationBinding &binding) {
  return surfaces_.withdrawSurfaces(binding);
}

bool PluginManager::publishIntent(host_session::AdmittedSurfaceIntent intent) {
  return surfaces_.publishIntent(std::move(intent));
}

} // namespace omarchy::plugin_runtime::bridge
