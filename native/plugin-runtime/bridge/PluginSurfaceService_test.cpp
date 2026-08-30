#include "PluginSurfaceService.h"
#include "gesture_intent.hpp"

#include <stdexcept>
#include <string_view>
#include <iostream>
#include <memory>

namespace {

namespace bridge = omarchy::plugin_runtime::bridge;
namespace host = omarchy::plugin_runtime::host_session;
namespace permissions = omarchy::plugins::permissions;
namespace runtime = omarchy::plugin_runtime::runtime;
namespace surface = omarchy::plugin_runtime::surface;

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

class Clock final : public runtime::GestureEligibilityClock {
public:
  std::uint64_t now = 100;
  std::uint64_t now_nanoseconds() const override { return now; }
};

permissions::Digest digest(char value) {
  return permissions::Digest(std::string(64, value));
}

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

  const QString maximum_name(64, QChar(u'X'));
  const QVariantList surfaces{
      declaration(QStringLiteral("bar"), QStringLiteral("bar")),
      declaration(QStringLiteral("PanelWidget"), QStringLiteral("panel")),
      declaration(QStringLiteral("overlay"), QStringLiteral("overlay")),
      declaration(maximum_name, QStringLiteral("panel")),
  };
  require(service.publishSurfaces(surfaces, 2) && service.revision() == 2 &&
              service.surfaces().size() == 4 &&
              !service.publishSurfaces(surfaces, 2),
          "bounded shell surface revision was not monotonic");
  QVariantList overflow = surfaces;
  for (int index = overflow.size(); index <= 8; ++index)
    overflow.push_back(declaration(QStringLiteral("surface%1").arg(index),
                                   QStringLiteral("panel")));
  require(!service.publishSurfaces(overflow, 3),
          "shell bridge accepted more than the product surface limit");

  int toggles = 0;
  QString last_target;
  QObject::connect(&service, &bridge::PluginSurfaceService::toggleRequested,
                   [&toggles, &last_target](const QString &,
                                            const QString &target,
                                            qulonglong) {
                     ++toggles;
                     last_target = target;
                   });
  auto clock = std::make_shared<Clock>();
  runtime::GestureEligibilityLatch eligibility(clock);
  const permissions::ActivationBinding binding{
      .plugin = permissions::PluginId("org.omarchy.fixture"),
      .revision = digest('1'),
      .policy_fingerprint = digest('2'),
      .generation = 7};
  host::GestureIntentAuthority authority(binding, eligibility);
  const surface::SurfaceKey bar{.id = 1, .generation = 7};
  const surface::SurfaceKey panel{.id = 2, .generation = 7};
  const surface::SurfaceKey maximum{.id = 3, .generation = 7};
  const std::string maximum_name_bytes(64, 'X');
  require(authority.declare_surface(bar, "bar") ==
              host::SurfaceDeclarationResult::declared &&
              authority.declare_surface(panel, "PanelWidget") ==
                  host::SurfaceDeclarationResult::declared &&
              authority.declare_surface(maximum, maximum_name_bytes) ==
                  host::SurfaceDeclarationResult::declared &&
              authority.arm(bar, 11),
          "bridge intent authority fixture failed");
  auto admitted = authority.admit(
      {.source = bar,
       .target = panel,
       .input_sequence = 11,
       .action = surface::SurfaceIntentAction::toggle});
  require(admitted.intent && service.publishIntent(std::move(*admitted.intent)) &&
              toggles == 1 &&
              last_target ==
                  QStringLiteral("v2.org.omarchy.fixture.PanelWidget"),
          "admitted surface intent did not reach the shell adapter");
  require(authority.arm(bar, 15), "maximum-name gesture did not arm");
  auto maximum_name_intent = authority.admit(
      {.source = bar,
       .target = maximum,
       .input_sequence = 15,
       .action = surface::SurfaceIntentAction::toggle});
  require(maximum_name_intent.intent &&
              service.publishIntent(std::move(*maximum_name_intent.intent)) &&
              toggles == 2 &&
              last_target ==
                  QStringLiteral("v2.org.omarchy.fixture.") + maximum_name,
          "maximum raw manifest name was not canonicalized at publication");
  require(authority.arm(bar, 12), "delayed intent gesture did not arm");
  auto delayed = authority.admit(
      {.source = bar,
       .target = panel,
       .input_sequence = 12,
       .action = surface::SurfaceIntentAction::toggle});
  require(delayed.intent && delayed.intent->available(),
          "admitted delayed intent fixture failed");
  clock->now += 5'000'000'000ULL;
  require(!service.publishIntent(std::move(*delayed.intent)) && toggles == 2,
          "expired admitted intent reached the shell adapter");
  require(authority.arm(bar, 13), "detach invalidation gesture did not arm");
  auto detached_token = authority.admit(
      {.source = bar,
       .target = panel,
       .input_sequence = 13,
       .action = surface::SurfaceIntentAction::toggle});
  require(detached_token.intent && authority.detach_surface(panel) &&
              !service.publishIntent(std::move(*detached_token.intent)) &&
              toggles == 2,
          "admitted intent survived surface detach");
  require(authority.declare_surface(panel, "PanelWidget") ==
              host::SurfaceDeclarationResult::declared &&
              authority.arm(bar, 14),
          "revoke invalidation fixture failed");
  auto revoked_token = authority.admit(
      {.source = bar,
       .target = panel,
       .input_sequence = 14,
       .action = surface::SurfaceIntentAction::toggle});
  require(revoked_token.intent.has_value(),
          "revoke intent was not admitted");
  authority.revoke();
  require(!service.publishIntent(std::move(*revoked_token.intent)) &&
              toggles == 2,
          "admitted intent survived session revocation");
  require(service.dismiss(
              QStringLiteral("v2.org.omarchy.fixture.PanelWidget")) &&
              backend.dismissals == 1 &&
              backend.last_dismissed ==
                  QStringLiteral("v2.org.omarchy.fixture.PanelWidget") &&
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
