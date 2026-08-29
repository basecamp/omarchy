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
#include "broker_runtime.hpp"
#include "omarchy/plugin_runtime/broker/broker_schema.hpp"
#include "omarchy/plugin_runtime/providers/private_storage_backend.hpp"
#include "lifecycle.hpp"

#include <fcntl.h>
#include <spawn.h>
#include <sys/wait.h>
#include <unistd.h>

#include <algorithm>
#include <chrono>
#include <cstdlib>
#include <ctime>
#include <memory>
#include <stdexcept>
#include <vector>

extern char **environ;

namespace {
namespace audit = omarchy::plugins::audit;
namespace grants = omarchy::plugins::grants;
namespace permissions = omarchy::plugins::permissions;
namespace bridge = omarchy::plugin_runtime::bridge;
namespace health = omarchy::plugin_runtime::health;
namespace host = omarchy::plugin_runtime::product_host;
namespace headless = omarchy::plugin_runtime::headless;
namespace launcher = omarchy::plugin_runtime::launcher;
namespace render = omarchy::plugin_runtime::render_session;
namespace surface = omarchy::plugin_runtime::surface;
namespace surface_host = omarchy::plugin_runtime::surface_host;
namespace wire = omarchy::plugin::wire;
namespace broker = omarchy::plugin_runtime::broker;
namespace runtime = omarchy::plugin_runtime::runtime;
namespace providers = omarchy::plugin_runtime::providers;
namespace lifecycle = omarchy::plugins::lifecycle;

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

class PreviewPointerBridge final : public bridge::HostPointerRouter {
public:
  explicit PreviewPointerBridge(surface_host::HostSurface &surface)
      : surface_(surface) {}

  bool route(const bridge::HostPointerEvent &event) override {
    if (event.button != Qt::LeftButton || event.application_synthesized ||
        sequence_ == UINT64_MAX)
      return false;
    if (event.x < 0 || event.y < 0)
      return false;
    const auto x = static_cast<std::uint64_t>(event.x);
    const auto y = static_cast<std::uint64_t>(event.y);
    if (x > (UINT32_MAX >> surface::kQ16FractionBits) ||
        y > (UINT32_MAX >> surface::kQ16FractionBits))
      return false;
    const surface::InputEvent input{
        .surface = surface_.allocation().surface,
        .sequence = ++sequence_,
        .kind = surface::InputKind::pointer_button,
        .x_q16 = static_cast<std::uint32_t>(x) << surface::kQ16FractionBits,
        .y_q16 = static_cast<std::uint32_t>(y) << surface::kQ16FractionBits,
        .delta_x_q16 = 0,
        .delta_y_q16 = 0,
        .code = 1,
        .state = static_cast<std::uint32_t>(
            event.pressed ? surface::ButtonState::pressed
                          : surface::ButtonState::released),
        .active_touch_points = 0};
    return surface_.route_input(input, event.pressed);
  }

private:
  surface_host::HostSurface &surface_;
  std::uint64_t sequence_ = 0;
};

bool run_exact(const std::vector<std::string> &arguments) noexcept {
  if (arguments.empty() || arguments.front().empty()) return false;
  try {
    std::vector<char *> pointers;
    pointers.reserve(arguments.size() + 1);
    for (const auto &argument : arguments)
      pointers.push_back(const_cast<char *>(argument.c_str()));
    pointers.push_back(nullptr);
    pid_t child = -1;
    if (posix_spawn(&child, arguments.front().c_str(), nullptr, nullptr,
                    pointers.data(), ::environ) != 0)
      return false;
    int status = 0;
    while (waitpid(child, &status, 0) < 0) {
      if (errno != EINTR) return false;
    }
    return WIFEXITED(status) && WEXITSTATUS(status) == 0;
  } catch (...) {
    return false;
  }
}

struct DesktopEffects {
  std::filesystem::path plugin_root;
  static bool notification(std::string_view, std::string_view title,
                           std::string_view body, void *) noexcept {
    return run_exact({"/usr/share/omarchy/bin/omarchy-notification-send",
                      "--app-name", "omarchy-plugin-lab",
                      std::string(title), std::string(body)});
  }
  static bool audio(std::string_view cue, void *context) noexcept {
    auto &self = *static_cast<DesktopEffects *>(context);
    for (const auto extension : {".wav", ".mp3", ".ogg"}) {
      const auto asset = self.plugin_root / "sounds" /
                         (std::string(cue) + extension);
      std::error_code error;
      if (std::filesystem::symlink_status(asset, error).type() ==
              std::filesystem::file_type::regular &&
          !error)
        return run_exact({"/usr/bin/pw-play", "--", asset.string()});
    }
    return false;
  }
};

class LabBroker final : public omarchy::plugin_runtime::channel::BrokerDispatcher {
public:
  LabBroker(runtime::AuditedBrokerRuntime &runtime, std::uint64_t generation)
      : runtime_(runtime), generation_(generation) {}
  bool accepts(const launcher::LaunchIdentity &identity) const noexcept override {
    const auto &binding = runtime_.binding();
    return identity.plugin_id == binding.plugin.view() &&
           identity.revision_sha256 == binding.revision.view() &&
           identity.generation == binding.generation;
  }
  bool dispatch(const wire::PacketView &packet) override {
    std::array<std::byte, 8192> output{};
    const auto result = runtime_.dispatch(packet, ++now_, output);
    std::vector<std::byte> payload;
    std::uint16_t type = 0;
    if (result.outcome == broker::DispatchOutcome::dispatched) {
      type = broker::kBrokerResultMessage;
      payload.assign(output.begin(), output.begin() +
                                      static_cast<std::ptrdiff_t>(result.response_bytes));
    } else if (result.outcome == broker::DispatchOutcome::denied) {
      type = static_cast<std::uint16_t>(wire::CommonMessageType::typed_error);
      const auto error = broker::encode_broker_error(
          {.failed_operation = static_cast<permissions::OperationId>(
               packet.header.message_type),
           .reason = broker::BrokerErrorReason::denied,
           .decision = result.decision.code});
      payload.assign(error.begin(), error.end());
    } else {
      return false;
    }
    const wire::PacketView terminal{
        .header = {.endpoint_role = wire::EndpointRole::broker,
                   .message_type = type,
                   .role_protocol_version = broker::kBrokerRoleVersion,
                   .payload_length = static_cast<std::uint32_t>(payload.size()),
                   .launch_generation = generation_,
                   .correlation_id = packet.header.correlation_id},
        .payload = payload};
    if (runtime_.accept_terminal(terminal) != broker::TerminalResult::accepted)
      return false;
    reply_ = omarchy::plugin_runtime::channel::BrokerReply{
        .message_type = type,
        .correlation_id = packet.header.correlation_id,
        .payload = std::move(payload)};
    return true;
  }
  std::optional<omarchy::plugin_runtime::channel::BrokerReply>
  take_reply() override { return std::exchange(reply_, {}); }
private:
  runtime::AuditedBrokerRuntime &runtime_;
  std::uint64_t generation_ = 0;
  std::uint64_t now_ = 100;
  std::optional<omarchy::plugin_runtime::channel::BrokerReply> reply_;
};

int preview(const QStringList &arguments, QGuiApplication &application,
            bool live_lab) {
  if (!preview_enabled()) {
    qCritical() << "omarchy-plugin-host: schema-v2 preview feature is disabled";
    return 77;
  }
  const qsizetype expected_arguments = live_lab ? 10 : 7;
  if (arguments.size() != expected_arguments)
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
  auto supervisor = live_lab
      ? launcher::Supervisor::forRootOwnedLiveLabOnly(
            arguments.at(7).toStdString(), arguments.at(8).toStdString(),
            arguments.at(9).toStdString())
      : launcher::Supervisor::production();
  std::unique_ptr<providers::PrivateStorageBackend> storage;
  std::unique_ptr<DesktopEffects> effects;
  std::unique_ptr<runtime::AuditedBrokerRuntime> broker_runtime;
  std::shared_ptr<LabBroker> lab_broker;
  headless::StartResult started;
  if (live_lab) {
    const char *gate = std::getenv("OMARCHY_PLUGIN_LIVE_LAB_ENABLED");
    if (gate == nullptr || std::string_view(gate) != "I_ACCEPT_LAB_RISK") {
      qCritical() << "omarchy-plugin-host: live lab requires explicit risk gate";
      return 77;
    }
    storage = std::make_unique<providers::PrivateStorageBackend>(
        state_fd, 1024 * 1024, providers::kMaximumStorageValueBytes);
    effects = std::make_unique<DesktopEffects>();
    effects->plugin_root = plugin_root;
    providers::ProviderConfiguration provider_configuration{
        .binding = {},
        .storage_epoch = 0,
        .notification_epoch = 0,
        .audio_epoch = 0,
        .fake_service_epoch = 0,
        .storage = storage->configuration(),
        .notification = {.send = DesktopEffects::notification,
                         .context = effects.get()},
        .audio = {.play = DesktopEffects::audio, .context = effects.get()}};
    broker_runtime = std::make_unique<runtime::AuditedBrokerRuntime>(
        *active, provider_configuration, audit_store);
    lab_broker = std::make_shared<LabBroker>(*broker_runtime,
                                             prepared.prepared->binding.generation);
    started = host::launch_with_broker_for_lab(
        supervisor, *prepared.prepared, state_fd, health_supervisor, lab_broker,
        std::make_shared<Authority>(prepared.prepared->binding),
        static_cast<std::uint64_t>(std::time(nullptr)), std::chrono::seconds(5));
  } else {
    started = host::launch(
        supervisor, *prepared.prepared, state_fd, health_supervisor,
        std::make_shared<Authority>(prepared.prepared->binding),
        static_cast<std::uint64_t>(std::time(nullptr)), std::chrono::seconds(5));
  }
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
  PreviewPointerBridge pointer_bridge(*hosted);
  surface.bindHostPointerRouter(pointer_bridge);
  QTimer pump;
  QObject::connect(&pump, &QTimer::timeout, [&] {
    if (live_lab) {
      const auto dispatched = started.session->dispatch_one(
          static_cast<std::uint64_t>(std::time(nullptr)),
          std::chrono::milliseconds(0));
      if (dispatched == omarchy::plugin_runtime::channel::DispatchStatus::fatal) {
        qCritical() << "omarchy-plugin-host: live broker dispatch became fatal";
        application.exit(79);
      }
    }
    auto message = started.session->receive_render(std::chrono::milliseconds(1));
    if (message) {
      if (!hosted->receive_render(message.payload) &&
          !hosted->inspection().render_active) {
        const auto decoded = wire::decode_packet(
            message.payload, wire::EndpointRole::render);
        if (decoded)
          qCritical() << "omarchy-plugin-host: host surface rejected render packet"
                      << decoded.packet.header.message_type
                      << decoded.packet.header.correlation_id;
        else
          qCritical() << "omarchy-plugin-host: host surface rejected malformed render packet";
        application.exit(79);
      }
    } else if (message.failure != launcher::ReceiveFailure::timeout) {
      qCritical() << "omarchy-plugin-host: render receive failed"
                  << static_cast<int>(message.failure);
      const auto diagnostic = started.session->take_worker_standard_error();
      if (!diagnostic.empty())
        qCritical().noquote() << QString::fromStdString(diagnostic);
      application.exit(79);
    }
  });
  pump.start(4);
  window.show();
  return application.exec();
}
} // namespace

int main(int argc, char *argv[]) {
  const bool live_lab = argc > 1 && QString::fromLocal8Bit(argv[1]) ==
                                        QStringLiteral("--preview-plugin-live-lab");
  const bool preview_requested = live_lab || (argc > 1 &&
      QString::fromLocal8Bit(argv[1]) == QStringLiteral("--preview-plugin"));
  if (preview_requested) {
    QGuiApplication application(argc, argv);
    application.setApplicationName(QStringLiteral("omarchy-plugin-host"));
    return preview(application.arguments(), application, live_lab);
  }
  QCoreApplication application(argc, argv);
  application.setApplicationName(QStringLiteral("omarchy-plugin-host"));
  const auto arguments = application.arguments();
  if (arguments.size() == 4 &&
      arguments.at(1) == QStringLiteral("--activate-plugin-live-lab")) {
    const char *schema_gate = std::getenv("OMARCHY_PLUGIN_SCHEMA_V2_ENABLED");
    const char *lab_gate = std::getenv("OMARCHY_PLUGIN_LIVE_LAB_ENABLED");
    if (schema_gate == nullptr || std::string_view(schema_gate) != "1" ||
        lab_gate == nullptr ||
        std::string_view(lab_gate) != "I_ACCEPT_LAB_RISK")
      return 77;
    try {
      grants::GrantStore store(arguments.at(2).toStdString());
      const auto state = store.read();
      const permissions::PluginId plugin(arguments.at(3).toStdString());
      const auto record = std::ranges::find_if(
          state.plugins, [&](const auto &item) { return item.plugin == plugin; });
      if (record == state.plugins.end() || !record->candidate) return 78;
      store.activate_candidate(record->candidate->binding);
      return 0;
    } catch (const std::exception &error) {
      qCritical().noquote() << error.what();
      return 78;
    }
  }
  if (arguments.size() == 5 && arguments.at(1) ==
                                  QStringLiteral("--stage-activate-plugin-live-lab")) {
    const char *schema_gate = std::getenv("OMARCHY_PLUGIN_SCHEMA_V2_ENABLED");
    const char *lab_gate = std::getenv("OMARCHY_PLUGIN_LIVE_LAB_ENABLED");
    if (schema_gate == nullptr || std::string_view(schema_gate) != "1" ||
        lab_gate == nullptr ||
        std::string_view(lab_gate) != "I_ACCEPT_LAB_RISK")
      return 77;
    try {
      const std::filesystem::path root(arguments.at(3).toStdString());
      bool generation_ok = false;
      const auto generation = arguments.at(4).toULongLong(&generation_ok);
      if (!generation_ok || generation == 0) return 78;
      QFile file(QString::fromStdString((root / "manifest.json").string()));
      if (!file.open(QIODevice::ReadOnly)) return 78;
      const auto manifest = omarchy::plugins::manifest::parse_manifest_v2(
          file.readAll().toStdString());
      const auto identity = omarchy::plugins::manifest::identify_tree(root, manifest);
      grants::GrantStore store(arguments.at(2).toStdString());
      const auto bundle = grants::make_bundle(
          grants::kSecurePluginSchemaVersion,
          permissions::PluginId(manifest.id),
          permissions::Digest(identity.tree_sha256),
          permissions::Digest(identity.request_sha256), generation,
          lifecycle::translate_requests(manifest));
      const auto staged = store.stage_candidate(bundle);
      store.activate_candidate(staged.revision.binding);
      return 0;
    } catch (const std::exception &error) {
      qCritical().noquote() << error.what();
      return 78;
    }
  }
  if (arguments.size() == 3 &&
      arguments.at(1) == QStringLiteral("--identify-plugin-live-lab")) {
    const char *schema_gate = std::getenv("OMARCHY_PLUGIN_SCHEMA_V2_ENABLED");
    const char *lab_gate = std::getenv("OMARCHY_PLUGIN_LIVE_LAB_ENABLED");
    if (schema_gate == nullptr || std::string_view(schema_gate) != "1" ||
        lab_gate == nullptr ||
        std::string_view(lab_gate) != "I_ACCEPT_LAB_RISK")
      return 77;
    const std::filesystem::path root(arguments.at(2).toStdString());
    QFile file(QString::fromStdString((root / "manifest.json").string()));
    if (!file.open(QIODevice::ReadOnly)) return 78;
    try {
      const auto manifest = omarchy::plugins::manifest::parse_manifest_v2(
          file.readAll().toStdString());
      const auto identity = omarchy::plugins::manifest::identify_tree(root, manifest);
      QTextStream(stdout) << "plugin=" << QString::fromStdString(manifest.id)
                          << "\ntree=" << QString::fromStdString(identity.tree_sha256)
                          << "\nrequest=" << QString::fromStdString(identity.request_sha256)
                          << '\n';
      return 0;
    } catch (const std::exception &error) {
      qCritical().noquote() << error.what();
      return 78;
    }
  }
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
