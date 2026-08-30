#include "PluginSurfaceService.h"

#include "remote_surface.hpp"
#include "gesture_intent.hpp"

#include <QVariantMap>

#include <algorithm>
#include <optional>
#include <string>

namespace omarchy::plugin_runtime::bridge {
namespace {

namespace wire = omarchy::plugin::wire;

constexpr int kMaximumBarWidth = 1024;
constexpr int kMaximumBarHeight = 128;
constexpr int kMaximumPanelWidth = 1024;
constexpr int kMaximumPanelHeight = 1024;
constexpr int kMaximumOverlayWidth = 8192;
constexpr int kMaximumOverlayHeight = 8192;

bool valid_plugin_id(QStringView value) {
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

std::optional<QString> canonical_surface_key(
    const omarchy::plugins::permissions::ActivationBinding &binding,
    std::string_view raw_name) {
  constexpr std::string_view prefix = "v2.";
  constexpr std::size_t maximum_canonical_bytes =
      prefix.size() + 128 + 1 + wire::kMaximumSurfaceNameBytes;
  const auto plugin = binding.plugin.view();
  if (!wire::valid_surface_name(raw_name) || plugin.empty() ||
      plugin.size() > 128 ||
      raw_name.size() >
          maximum_canonical_bytes - prefix.size() - 1 - plugin.size())
    return std::nullopt;

  std::string bytes;
  bytes.reserve(prefix.size() + plugin.size() + 1 + raw_name.size());
  bytes.append(prefix);
  bytes.append(plugin);
  bytes.push_back('.');
  bytes.append(raw_name);
  const QByteArray encoded(bytes.data(), static_cast<qsizetype>(bytes.size()));
  const QString canonical = QString::fromUtf8(encoded);
  const QString plugin_text = QString::fromUtf8(
      plugin.data(), static_cast<qsizetype>(plugin.size()));
  if (canonical.toUtf8() != encoded || !valid_plugin_id(plugin_text))
    return std::nullopt;
  return canonical;
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
  const auto encoded_name = name.toUtf8().toStdString();
  if (!valid_plugin_id(plugin) ||
      !wire::valid_surface_name(encoded_name) ||
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
      surfaces.size() >
          static_cast<qsizetype>(wire::kMaximumPluginSurfaces) ||
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
    host_session::AdmittedSurfaceIntent intent) {
  if (backend_ == nullptr)
    return false;
  auto publication = intent.take_if_fresh();
  if (!publication)
    return false;
  const auto source =
      canonical_surface_key(publication->binding(), publication->source_name());
  const auto target =
      canonical_surface_key(publication->binding(), publication->target_name());
  if (!source || !target)
    return false;
  const qulonglong generation = publication->binding().generation;
  const auto declared_generation = [this](QStringView key) {
    const auto found = std::ranges::find_if(
        surfaces_, [key](const QVariant &value) {
          return value.toMap().value(QStringLiteral("surfaceKey")).toString() ==
                 key;
        });
    return found == surfaces_.end()
               ? qulonglong{0}
               : found->toMap()
                     .value(QStringLiteral("generation"))
                     .toULongLong();
  };
  const auto action = publication->action();
  if (generation == 0 || declared_generation(*source) != generation ||
      declared_generation(*target) != generation)
    return false;
  switch (action) {
  case surface::SurfaceIntentAction::open:
    emit openRequested(*source, *target, generation);
    return true;
  case surface::SurfaceIntentAction::toggle:
    emit toggleRequested(*source, *target, generation);
    return true;
  case surface::SurfaceIntentAction::dismiss:
    emit dismissRequested(*source, *target, generation);
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
