#include "PluginManager.h"

#include "omarchy/plugin_runtime/Version.h"
#include "remote_surface.hpp"

#include <QMetaMethod>

#include <stdexcept>
#include <string>
#include <string_view>
#include <thread>

namespace {

namespace bridge = omarchy::plugin_runtime::bridge;
namespace permissions = omarchy::plugins::permissions;

void require(bool condition, std::string_view message) {
  if (!condition)
    throw std::runtime_error(std::string(message));
}

permissions::ActivationBinding binding() {
  return {
      .plugin = permissions::PluginId("org.example.singleton"),
      .revision = permissions::Digest(std::string(64, 'a')),
      .policy_fingerprint = permissions::Digest(std::string(64, 'b')),
      .generation = 4,
  };
}

void singleton_boundary_is_inert_and_not_configurable() {
  auto manager_owner = bridge::PluginManagerTestAccess::create();
  auto &manager = *manager_owner;
  const auto version = omarchy::plugin_runtime::build_version();
  require(!manager.available() && manager.count() == 0 &&
              manager.barSurfaces()->rowCount() == 0 &&
              manager.panelSurfaces()->rowCount() == 0 &&
              manager.overlaySurfaces()->rowCount() == 0 &&
              manager.runtimeVersion() ==
                  QString::fromLatin1(version.data(), version.size()),
          "singleton boundary did not start inert");

  const auto *meta = manager.metaObject();
  for (int index = meta->methodOffset(); index < meta->methodCount(); ++index) {
    const auto name = meta->method(index).name();
    require(name != "publishSurfaces" && name != "withdrawSurfaces" &&
                name != "publishIntent" && name != "bindBackend",
            "authority/configuration method escaped into the QML metaobject");
  }
  bridge::RemotePluginSurface remote;
  require(!manager.attach(QStringLiteral("missing"), &remote),
          "inert singleton accepted an unpublished surface");
}

void private_projection_seam_preserves_fail_closed_boundary() {
  using Service = bridge::PluginSurfaceService;
  auto manager_owner = bridge::PluginManagerTestAccess::create();
  auto &manager = *manager_owner;
  int changes = 0;
  QObject::connect(&manager, &bridge::PluginManager::surfacesChanged,
                   [&changes] { ++changes; });
  std::vector<Service::SurfaceDeclaration> declarations;
  declarations.push_back({.surface_name = "panel",
                          .role = Service::Role::Panel,
                          .screen_name = QStringLiteral("DP-1"),
                          .initially_visible = false,
                          .maximum_width = 640,
                          .maximum_height = 480,
                          .dynamic_input_regions = true});
  const auto exact = binding();
  require(bridge::PluginManagerTestAccess::publishSurfaces(
              manager, exact, std::move(declarations), 1) &&
              manager.count() == 1 && changes == 1 && !manager.available(),
          "private readiness seam did not project one exact row");

  const auto key = manager.panelSurfaces()
                       ->data(manager.panelSurfaces()->index(0, 0),
                              Service::SurfaceKeyRole)
                       .toString();
  bridge::RemotePluginSurface remote;
  require(!manager.attach(key, &remote),
          "projection without an N8D5C endpoint owner accepted attachment");

  bool off_thread = true;
  std::thread worker([&] {
    off_thread = bridge::PluginManagerTestAccess::withdrawSurfaces(manager,
                                                                   exact);
  });
  worker.join();
  require(!off_thread && manager.count() == 1 &&
              bridge::PluginManagerTestAccess::withdrawSurfaces(manager,
                                                                 exact) &&
              manager.count() == 0 && changes == 2,
          "projection seam escaped UI-thread or exact-binding confinement");
}

} // namespace

void run_plugin_manager_tests() {
  singleton_boundary_is_inert_and_not_configurable();
  private_projection_seam_preserves_fail_closed_boundary();
}
