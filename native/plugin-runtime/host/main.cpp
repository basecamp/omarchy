#include <QDebug>
#include <QCoreApplication>
#include <QFile>
#include <QGuiApplication>
#include <QQuickWindow>
#include <QStringList>
#include <QTextStream>
#include <QTimer>

#include "audit_store.hpp"
#include "grant_store.hpp"
#include "omarchy/plugin/wire/envelope.hpp"
#include "omarchy/plugin_runtime/Version.h"
#include "product_host.hpp"

#include <fcntl.h>
#include <unistd.h>

#include <algorithm>
#include <chrono>
#include <cstdlib>
#include <ctime>
#include <memory>
#include <stdexcept>
#include <vector>

namespace {
namespace audit = omarchy::plugins::audit;
namespace grants = omarchy::plugins::grants;
namespace permissions = omarchy::plugins::permissions;
namespace bridge = omarchy::plugin_runtime::bridge;
namespace health = omarchy::plugin_runtime::health;
namespace host = omarchy::plugin_runtime::product_host;
namespace launcher = omarchy::plugin_runtime::launcher;
namespace render = omarchy::plugin_runtime::render_session;
namespace surface_host = omarchy::plugin_runtime::surface_host;
namespace wire = omarchy::plugin::wire;

int usage_error(const QString &argument) {
  qCritical().noquote() << "omarchy-plugin-host: unsupported argument:" << argument;
  return 64;
}
bool preview_enabled() {
  const char *value = std::getenv("OMARCHY_PLUGIN_SCHEMA_V2_ENABLED");
  return value != nullptr && std::string_view(value) == "1";
}

class Authority final : public omarchy::plugin_runtime::channel::GenerationAuthority {
public:
  explicit Authority(permissions::ActivationBinding binding) : binding_(std::move(binding)) {}
  bool is_current(const launcher::LaunchIdentity &identity) const noexcept override {
    return identity.plugin_id == binding_.plugin.view() &&
           identity.revision_sha256 == binding_.revision.view() &&
           identity.generation == binding_.generation;
  }
private:
  permissions::ActivationBinding binding_;
};

class Transport final : public render::PacketSender, public bridge::RenderPacketSink {
public:
  explicit Transport(omarchy::plugin_runtime::headless::Session &session) : session_(session) {}
  bool send(const wire::EnvelopeHeader &header, std::span<const std::byte> payload,
            std::span<const int> descriptors) override {
    std::vector<std::byte> encoded(wire::kHeaderSize + payload.size());
    const auto result = wire::encode_packet(header, payload, encoded);
    return result && session_.send_render(std::span(encoded).first(result.bytes_written), descriptors);
  }
  bool send(const wire::EnvelopeHeader &header, std::span<const std::byte> payload) override {
    return send(header, payload, {});
  }
private:
  omarchy::plugin_runtime::headless::Session &session_;
};

class Inspection final : public surface_host::InspectionAuthority {
public:
  bool perform(surface_host::InspectionAction, std::string_view,
               std::string_view, std::string_view) override { return false; }
};
class Clock final : public surface_host::MonotonicClock {
public:
  std::uint64_t now_nanoseconds() const override {
    return static_cast<std::uint64_t>(std::chrono::duration_cast<std::chrono::nanoseconds>(
        std::chrono::steady_clock::now().time_since_epoch()).count());
  }
};

int preview(const QStringList &arguments, QGuiApplication &application) {
  if (!preview_enabled()) {
    qCritical() << "omarchy-plugin-host: schema-v2 preview feature is disabled";
    return 77;
  }
  if (arguments.size() != 7)
    return usage_error(arguments.value(1));
  const std::filesystem::path plugin_root(arguments.at(2).toStdString());
  QFile manifest_file(QString::fromStdString((plugin_root / "manifest.json").string()));
  if (!manifest_file.open(QIODevice::ReadOnly)) {
    qCritical() << "omarchy-plugin-host: manifest unavailable";
    return 78;
  }
  const auto parsed = omarchy::plugins::manifest::parse_manifest_v2(
      manifest_file.readAll().toStdString());
  grants::GrantStore grant_store(arguments.at(4).toStdString());
  const auto state = grant_store.read();
  const grants::RevisionGrants *active = nullptr;
  for (const auto &plugin : state.plugins)
    if (plugin.plugin == permissions::PluginId(parsed.id) && plugin.active)
      active = &*plugin.active;
  if (active == nullptr) {
    qCritical() << "omarchy-plugin-host: no explicitly reviewed active grants";
    return 78;
  }
  auto prepared = host::prepare(
      plugin_root, {.directory = plugin_root.filename().string(),
                    .tree_sha256 = arguments.at(3).toStdString()},
      *active, {.schema_v2_enabled = true});
  if (!prepared) {
    qCritical().noquote() << "omarchy-plugin-host: preview rejected:"
                          << QString::fromStdString(prepared.detail);
    return 78;
  }
  const int state_fd = open(arguments.at(5).toLocal8Bit().constData(),
                            O_RDONLY | O_DIRECTORY | O_CLOEXEC);
  if (state_fd < 0) return 78;
  struct Fd { int value; ~Fd() { close(value); } } owned_state{state_fd};
  audit::AuditStore audit_store(arguments.at(6).toStdString(), {});
  health::HealthSupervisor health_supervisor({}, audit_store);
  auto supervisor = launcher::Supervisor::production();
  auto started = host::launch(
      supervisor, *prepared.prepared, state_fd, health_supervisor,
      std::make_shared<Authority>(prepared.prepared->binding),
      static_cast<std::uint64_t>(std::time(nullptr)), std::chrono::seconds(5));
  if (!started) {
    qCritical().noquote() << "omarchy-plugin-host: preview launch failed:"
                          << QString::fromStdString(started.detail);
    return 78;
  }
  const auto &policy = prepared.prepared->surfaces.front();
  const auto width = std::min<std::uint32_t>(policy.maximum_width, 640);
  const auto height = std::min<std::uint32_t>(policy.maximum_height, 480);
  QQuickWindow window;
  window.resize(static_cast<int>(width), static_cast<int>(height));
  window.setTitle(QStringLiteral("Omarchy secure plugin preview: ") + QString::fromStdString(parsed.name));
  bridge::RemotePluginSurface surface(window.contentItem());
  surface.setWidth(width);
  surface.setHeight(height);
  auto transport = std::make_shared<Transport>(*started.session);
  Inspection inspection;
  Clock clock;
  auto hosted = surface_host::HostSurface::create(
      policy, prepared.prepared->binding, 1, width, height, 1, 1, surface,
      *transport, transport, inspection, clock);
  if (!hosted) return 78;
  QTimer pump;
  QObject::connect(&pump, &QTimer::timeout, [&] {
    auto message = started.session->receive_render(std::chrono::milliseconds(1));
    if (message) {
      if (!hosted->receive_render(message.payload)) application.exit(79);
    } else if (message.failure != launcher::ReceiveFailure::timeout) {
      application.exit(79);
    }
  });
  pump.start(4);
  window.show();
  return application.exec();
}
} // namespace

int main(int argc, char *argv[]) {
  const bool preview_requested = argc > 1 &&
      QString::fromLocal8Bit(argv[1]) == QStringLiteral("--preview-plugin");
  if (preview_requested) {
    QGuiApplication application(argc, argv);
    application.setApplicationName(QStringLiteral("omarchy-plugin-host"));
    return preview(application.arguments(), application);
  }
  QCoreApplication application(argc, argv);
  application.setApplicationName(QStringLiteral("omarchy-plugin-host"));
  const auto arguments = application.arguments();
  if (arguments.size() == 2 && arguments.at(1) == QStringLiteral("--version")) {
    const auto version = omarchy::plugin_runtime::build_version();
    QTextStream(stdout) << "omarchy-plugin-host " << QString::fromLatin1(version.data(), version.size())
                        << " envelope=" << omarchy::plugin_runtime::envelope_version() << '\n';
    return 0;
  }
  if (arguments.size() == 2 && arguments.at(1) == QStringLiteral("--check-launch-prerequisites")) {
    auto supervisor = launcher::Supervisor::production();
    std::string error;
    return supervisor.prerequisites(error) ? 0 : 1;
  }
  if (arguments.size() > 1) return usage_error(arguments.at(1));
  qInfo() << "omarchy-plugin-host: secure preview dormant";
  return 0;
}
