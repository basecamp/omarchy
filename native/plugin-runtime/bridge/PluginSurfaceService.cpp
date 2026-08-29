#include "PluginSurfaceService.h"

#include "remote_surface.hpp"

#include <QVariantMap>

#include <algorithm>

namespace omarchy::plugin_runtime::bridge {
namespace {

constexpr qsizetype kMaximumSurfaces = 32;
constexpr int kMaximumBarWidth = 1024;
constexpr int kMaximumBarHeight = 128;
constexpr int kMaximumPanelWidth = 1024;
constexpr int kMaximumPanelHeight = 1024;
constexpr int kMaximumOverlayWidth = 8192;
constexpr int kMaximumOverlayHeight = 8192;

bool bounded_name(QStringView value) {
  if (value.isEmpty() || value.size() > 128)
    return false;
  bool separator = true;
  for (const QChar item : value) {
    const bool alphanumeric = item.isLower() || item.isDigit();
    const bool current_separator = item == u'.' || item == u'-' || item == u'_';
    if ((!alphanumeric && !current_separator) ||
        (separator && current_separator))
      return false;
    separator = current_separator;
  }
  return !separator;
}

bool bounded_geometry(const QVariantMap &surface, int maximum_width,
                      int maximum_height) {
  bool width_ok = false;
  bool height_ok = false;
  const int width = surface.value(QStringLiteral("maximumWidth")).toInt(&width_ok);
  const int height =
      surface.value(QStringLiteral("maximumHeight")).toInt(&height_ok);
  return width_ok && height_ok && width > 0 && height > 0 &&
         width <= maximum_width && height <= maximum_height;
}

bool valid_surface(const QVariant &value) {
  if (value.metaType().id() != QMetaType::QVariantMap)
    return false;
  const auto surface = value.toMap();
  const auto key = surface.value(QStringLiteral("surfaceKey")).toString();
  const auto plugin = surface.value(QStringLiteral("pluginId")).toString();
  const auto name = surface.value(QStringLiteral("surfaceName")).toString();
  const auto role = surface.value(QStringLiteral("role")).toString();
  const auto generation = surface.value(QStringLiteral("generation")).toULongLong();
  const auto screen = surface.value(QStringLiteral("screenName")).toString();
  const auto visible = surface.value(QStringLiteral("visible"));
  if (!bounded_name(key) || !bounded_name(plugin) || !bounded_name(name) ||
      key != QStringLiteral("v2.") + plugin + u'.' + name || generation == 0 ||
      visible.metaType().id() != QMetaType::Bool ||
      screen.isEmpty() || screen.size() > 128 ||
      std::ranges::any_of(screen, [](QChar item) { return !item.isPrint(); }))
    return false;
  if (role == QStringLiteral("bar")) {
    const auto section = surface.value(QStringLiteral("defaultSection")).toString();
    return (section == QStringLiteral("left") ||
            section == QStringLiteral("center") ||
            section == QStringLiteral("right")) &&
           bounded_geometry(surface, kMaximumBarWidth, kMaximumBarHeight);
  }
  if (role == QStringLiteral("panel"))
    return bounded_geometry(surface, kMaximumPanelWidth, kMaximumPanelHeight);
  if (role == QStringLiteral("overlay")) {
    const auto mask = surface.value(QStringLiteral("inputMask")).toString();
    return mask == QStringLiteral("bounded") &&
           bounded_geometry(surface, kMaximumOverlayWidth,
                            kMaximumOverlayHeight);
  }
  return false;
}

} // namespace

PluginSurfaceService::PluginSurfaceService(QObject *parent) : QObject(parent) {}

bool PluginSurfaceService::available() const { return backend_ != nullptr; }

QVariantList PluginSurfaceService::surfaces() const { return surfaces_; }

qulonglong PluginSurfaceService::revision() const { return revision_; }

bool PluginSurfaceService::attach(const QString &surface_key, QObject *surface) {
  auto *remote = qobject_cast<RemotePluginSurface *>(surface);
  return backend_ != nullptr && remote != nullptr && declared(surface_key) &&
         backend_->attach(surface_key, *remote);
}

bool PluginSurfaceService::dismiss(const QString &surface_key) {
  return backend_ != nullptr && declared(surface_key) &&
         backend_->dismiss(surface_key);
}

bool PluginSurfaceService::bindBackend(PluginSurfaceBackend &backend) {
  if (backend_ != nullptr)
    return false;
  backend_ = &backend;
  emit availableChanged();
  return true;
}

void PluginSurfaceService::unbindBackend(PluginSurfaceBackend &backend) {
  if (backend_ != &backend)
    return;
  backend_ = nullptr;
  surfaces_.clear();
  revision_ = 0;
  emit availableChanged();
  emit surfacesChanged();
}

bool PluginSurfaceService::publishSurfaces(const QVariantList &surfaces,
                                           qulonglong revision) {
  if (backend_ == nullptr || revision == 0 || revision <= revision_ ||
      surfaces.size() > kMaximumSurfaces ||
      !std::ranges::all_of(surfaces, valid_surface))
    return false;
  for (qsizetype index = 0; index < surfaces.size(); ++index) {
    const auto key = surfaces.at(index).toMap().value(QStringLiteral("surfaceKey"));
    for (qsizetype candidate = index + 1; candidate < surfaces.size(); ++candidate)
      if (surfaces.at(candidate).toMap().value(QStringLiteral("surfaceKey")) == key)
        return false;
  }
  surfaces_ = surfaces;
  revision_ = revision;
  emit surfacesChanged();
  return true;
}

bool PluginSurfaceService::publishIntent(
    const QString &source_surface, const QString &target_surface, Intent intent,
    qulonglong generation, bool authenticated, bool fresh_gesture) {
  if (backend_ == nullptr || !authenticated || !fresh_gesture ||
      generation == 0 || !declared(source_surface) ||
      !declared(target_surface))
    return false;
  switch (intent) {
  case Intent::open:
    emit openRequested(source_surface, target_surface, generation);
    return true;
  case Intent::toggle:
    emit toggleRequested(source_surface, target_surface, generation);
    return true;
  case Intent::dismiss:
    emit dismissRequested(source_surface, target_surface, generation);
    return true;
  }
  return false;
}

bool PluginSurfaceService::declared(QStringView surface_key) const {
  return std::ranges::any_of(surfaces_, [surface_key](const QVariant &value) {
    return value.toMap().value(QStringLiteral("surfaceKey")).toString() ==
           surface_key;
  });
}

} // namespace omarchy::plugin_runtime::bridge
