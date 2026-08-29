#include "PluginSurfaceService.h"

#include <stdexcept>
#include <string_view>
#include <iostream>

namespace {

namespace bridge = omarchy::plugin_runtime::bridge;

void require(bool condition, std::string_view message) {
  if (!condition)
    throw std::runtime_error(std::string(message));
}

class Backend final : public bridge::PluginSurfaceBackend {
public:
  bool attach(QStringView, bridge::RemotePluginSurface &) override {
    ++attachments;
    return true;
  }

  bool dismiss(QStringView surface_key) override {
    ++dismissals;
    last_dismissed = surface_key.toString();
    return true;
  }

  int attachments = 0;
  int dismissals = 0;
  QString last_dismissed;
};

QVariantMap declaration(QString key, QString role) {
  const bool bar = role == QStringLiteral("bar");
  const QString surface_name = key;
  QVariantMap result{
      {QStringLiteral("surfaceKey"), QStringLiteral("v2.org.omarchy.fixture.") + key},
      {QStringLiteral("pluginId"), QStringLiteral("org.omarchy.fixture")},
      {QStringLiteral("surfaceName"), surface_name},
      {QStringLiteral("role"), role},
      {QStringLiteral("generation"), 7},
      {QStringLiteral("screenName"), QStringLiteral("DP-1")},
      {QStringLiteral("visible"), true},
      {QStringLiteral("maximumWidth"), bar ? 280 : 640},
      {QStringLiteral("maximumHeight"), bar ? 64 : 480},
  };
  if (bar)
    result.insert(QStringLiteral("defaultSection"), QStringLiteral("left"));
  if (role == QStringLiteral("overlay"))
    result.insert(QStringLiteral("inputMask"), QStringLiteral("bounded"));
  return result;
}

void run() {
  bridge::PluginSurfaceService service;
  Backend backend;
  require(!service.available() && service.surfaces().isEmpty() &&
              !service.dismiss(QStringLiteral("panel")),
          "unbound shell bridge did not fail closed");
  require(service.bindBackend(backend) && service.available() &&
              !service.bindBackend(backend),
          "shell bridge backend binding was not exclusive");

  const QVariantList invalid{declaration(QStringLiteral("panel"),
                                         QStringLiteral("window"))};
  require(!service.publishSurfaces(invalid, 1),
          "unknown compositor role reached shell declarations");

  const QVariantList surfaces{
      declaration(QStringLiteral("bar"), QStringLiteral("bar")),
      declaration(QStringLiteral("panel"), QStringLiteral("panel")),
      declaration(QStringLiteral("overlay"), QStringLiteral("overlay")),
  };
  require(service.publishSurfaces(surfaces, 2) && service.revision() == 2 &&
              service.surfaces().size() == 3 &&
              !service.publishSurfaces(surfaces, 2),
          "bounded shell surface revision was not monotonic");

  int toggles = 0;
  QObject::connect(&service, &bridge::PluginSurfaceService::toggleRequested,
                   [&toggles](const QString &, const QString &, qulonglong) {
                     ++toggles;
                   });
  require(!service.publishIntent(
              QStringLiteral("v2.org.omarchy.fixture.bar"), QStringLiteral("v2.org.omarchy.fixture.panel"),
              bridge::PluginSurfaceService::Intent::toggle, 7, false, true) &&
              !service.publishIntent(
                  QStringLiteral("v2.org.omarchy.fixture.bar"), QStringLiteral("v2.org.omarchy.fixture.panel"),
                  bridge::PluginSurfaceService::Intent::toggle, 7, true,
                  false) &&
              service.publishIntent(
                  QStringLiteral("v2.org.omarchy.fixture.bar"), QStringLiteral("v2.org.omarchy.fixture.panel"),
                  bridge::PluginSurfaceService::Intent::toggle, 7, true,
                  true) &&
              toggles == 1,
          "unauthenticated or gestureless surface intent escaped the bridge");
  require(service.dismiss(QStringLiteral("v2.org.omarchy.fixture.panel")) &&
              backend.dismissals == 1 &&
              backend.last_dismissed == QStringLiteral("v2.org.omarchy.fixture.panel") &&
              !service.dismiss(QStringLiteral("missing")),
          "shell-owned dismissal escaped its declared surface");

  service.unbindBackend(backend);
  require(!service.available() && service.surfaces().isEmpty() &&
              service.revision() == 0,
          "backend loss retained stale shell surfaces");
}

} // namespace

int main() {
  try {
    run();
    return 0;
  } catch (const std::exception &error) {
    std::cerr << error.what() << '\n';
    return 1;
  }
}
