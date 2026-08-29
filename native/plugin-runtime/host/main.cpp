#include <QDebug>
#include <QCoreApplication>
#include <QCryptographicHash>
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
#include "dynamic_broker_runtime.hpp"
#include "capability_definition_loader.hpp"
#include "provider_registration.hpp"
#include "omarchy/plugin_runtime/broker/broker_schema.hpp"
#include "omarchy/plugin_runtime/providers/private_storage_backend.hpp"
#include "omarchy/plugin_runtime/providers/audio_device_provider.hpp"
#include "omarchy/plugin_runtime/providers/bluez_audio_backend.hpp"
#include "omarchy/plugin_runtime/providers/github_cli_backend.hpp"
#include "omarchy/plugin_runtime/providers/github_provider.hpp"
#include "omarchy/plugin_runtime/providers/radio_live_backend.hpp"
#include "omarchy/plugin_runtime/providers/radio_provider.hpp"
#include "omarchy/plugin_runtime/sandbox/policy.h"
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
#include <iostream>
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
namespace external_provider = omarchy::plugins::external_provider;
namespace providers = omarchy::plugin_runtime::providers;
namespace lifecycle = omarchy::plugins::lifecycle;
namespace definitions = omarchy::plugins::definitions;

#ifdef OMARCHY_PLUGIN_PRODUCT_E2E
class TestScope final : public launcher::ResourceScopeController {
public:
  bool probe(std::string &) override { return true; }
  bool attach(std::string_view, pid_t, pid_t,
              const omarchy::plugin_runtime::sandbox::SandboxPlan &,
              std::chrono::milliseconds, std::string &) override {
    return true;
  }
  void kill(std::string_view) noexcept override {}
  void remove(std::string_view) noexcept override {}
};
#endif

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

class PreviewInputRegionBridge final : public bridge::HostInputRegionRouter {
public:
  explicit PreviewInputRegionBridge(surface_host::HostSurface &surface)
      : surface_(surface) {}
  bool apply(const surface::InputRegionUpdate &update) override {
    std::array<surface_host::InputRegion,
               surface::kMaximumTransportedInputRegions> converted{};
    for (std::size_t index = 0; index < update.count; ++index) {
      if (update.regions[index].x < 0 || update.regions[index].y < 0)
        return false;
      converted[index] = {
          .x = static_cast<std::uint32_t>(update.regions[index].x),
          .y = static_cast<std::uint32_t>(update.regions[index].y),
                          .width = update.regions[index].width,
                          .height = update.regions[index].height};
    }
    return surface_.set_input_regions(
        std::span(converted).first(update.count));
  }
private:
  surface_host::HostSurface &surface_;
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

definitions::DynamicScopeRelation exact_dynamic_scope(
    const definitions::CapabilityDefinition &, std::string_view candidate,
    std::string_view baseline, void *) noexcept {
  return candidate == baseline ? definitions::DynamicScopeRelation::equal
                               : definitions::DynamicScopeRelation::incomparable;
}

struct DynamicAdapters {
  definitions::DynamicAdapter fetch;
  definitions::DynamicAdapter media;
  definitions::DynamicAdapter device_observe;
  definitions::DynamicAdapter device_control;
  definitions::DynamicAdapter account_read;
  definitions::DynamicAdapter account_write;
  definitions::DynamicAdapter open_uri;
  std::vector<definitions::DynamicAdapter> external;
};

bool dynamic_adapter_available(std::string_view adapter_class,
                               const definitions::Digest &digest,
                               std::uint32_t abi, void *opaque) noexcept {
  const auto &adapters = *static_cast<const DynamicAdapters *>(opaque);
  for (const auto *adapter : {&adapters.fetch, &adapters.media,
                              &adapters.device_observe,
                              &adapters.device_control,
                              &adapters.account_read,
                              &adapters.account_write,
                              &adapters.open_uri})
    if (adapter->binding.adapter_class.view() == adapter_class &&
        adapter->binding.implementation_digest == digest &&
        adapter->binding.abi_version == abi)
      return true;
  for (const auto &adapter : adapters.external)
    if (adapter.binding.adapter_class.view() == adapter_class &&
        adapter.binding.implementation_digest == digest &&
        adapter.binding.abi_version == abi)
      return true;
  return false;
}

#if defined(OMARCHY_PLUGIN_PRODUCT_E2E) && !defined(OMARCHY_PLUGIN_REAL_RADIO_E2E)
bool fixture_radio_get(std::string_view origin, std::string_view,
                       std::span<std::byte> output, std::size_t &written,
                       void *) noexcept {
  if (origin != "https://all.api.radio-browser.info") return false;
  constexpr std::string_view body =
      "[{\"stationuuid\":\"fixture-radio\",\"name\":\"Fixture Radio\","
      "\"country\":\"Test\",\"countrycode\":\"TS\",\"geo_lat\":1,"
      "\"geo_long\":2,\"votes\":9,"
      "\"url_resolved\":\"https://stream.example.invalid/radio\"}]";
  if (output.size() < body.size()) return false;
  std::ranges::copy(std::as_bytes(std::span(body.data(), body.size())),
                    output.begin());
  written = body.size();
  return true;
}
bool fixture_radio_play(std::string_view url, void *) noexcept {
  return url == "https://stream.example.invalid/radio";
}
bool fixture_radio_control(std::string_view control, std::uint32_t,
                           void *) noexcept {
  return control == "pause" || control == "stop" || control == "mute" ||
         control == "volume" || control == "status";
}
#endif

#ifdef OMARCHY_PLUGIN_PRODUCT_E2E
bool fixture_audio_observe(providers::AudioDeviceStatus &status,
                           void *) noexcept {
  status = {.display_name = "AirPods Pro", .connected = true, .left = 71,
            .right = 84, .case_level = 93, .listening_mode = "adaptive",
            .adaptive_level = 42, .conversation_awareness = true,
            .one_bud_anc = true, .ear_detection = "pause-one-out",
            .supported_controls = providers::kListeningModeControl |
                providers::kAdaptiveLevelControl |
                providers::kConversationAwarenessControl |
                providers::kOneBudAncControl |
                providers::kEarDetectionControl};
  return true;
}

bool fixture_audio_control(std::string_view operation, std::string_view value,
                           void *) noexcept {
  return operation == "set-adaptive-level" && value == "54";
}
#endif

class LabBroker final : public omarchy::plugin_runtime::channel::BrokerDispatcher {
public:
  LabBroker(runtime::AuditedBrokerRuntime &runtime,
            runtime::DynamicBrokerRuntime *dynamic,
            std::uint64_t generation)
      : runtime_(runtime), dynamic_(dynamic), generation_(generation) {}
  bool accepts(const launcher::LaunchIdentity &identity) const noexcept override {
    const auto &binding = runtime_.binding();
    return identity.plugin_id == binding.plugin.view() &&
           identity.revision_sha256 == binding.revision.view() &&
           identity.generation == binding.generation;
  }
  bool dispatch(const wire::PacketView &packet) override {
    ++dispatch_count_;
    std::vector<std::byte> output(providers::kMaximumRadioDirectoryBytes);
    if (packet.header.message_type == broker::kDynamicInvokeMessage) {
      if (dynamic_ == nullptr) return false;
      const auto result = dynamic_->dispatch(packet, runtime_.binding(), output);
      if (dynamic_->failed()) return false;
      std::vector<std::byte> payload;
      std::uint16_t type = 0;
      if (result.outcome == definitions::DynamicDispatchResult::dispatched) {
        type = broker::kBrokerResultMessage;
        payload.assign(output.begin(), output.begin() +
                                        static_cast<std::ptrdiff_t>(result.response_bytes));
      } else if (result.outcome == definitions::DynamicDispatchResult::denied ||
                 result.outcome == definitions::DynamicDispatchResult::adapter_failed) {
        type = static_cast<std::uint16_t>(wire::CommonMessageType::typed_error);
        const auto error = broker::encode_broker_error(
            {.failed_operation = static_cast<permissions::OperationId>(broker::kDynamicInvokeMessage),
             .reason = result.outcome == definitions::DynamicDispatchResult::denied
                           ? broker::BrokerErrorReason::denied
                           : broker::BrokerErrorReason::provider_failed,
             .decision = result.outcome == definitions::DynamicDispatchResult::adapter_failed
                             ? permissions::GrantDecisionCode::allowed
                             : (result.decision == definitions::DynamicDecision::revoked
                                    ? permissions::GrantDecisionCode::revoked
                                    : permissions::GrantDecisionCode::ungranted)});
        payload.assign(error.begin(), error.end());
      } else {
        return false;
      }
      reply_ = omarchy::plugin_runtime::channel::BrokerReply{
          .message_type = type, .correlation_id = packet.header.correlation_id,
          .payload = std::move(payload)};
      return true;
    }
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
#ifdef OMARCHY_PLUGIN_PRODUCT_E2E
  [[nodiscard]] std::uint64_t dispatch_count() const { return dispatch_count_; }
#endif
private:
  runtime::AuditedBrokerRuntime &runtime_;
  runtime::DynamicBrokerRuntime *dynamic_ = nullptr;
  std::uint64_t generation_ = 0;
  std::uint64_t now_ = 100;
  std::uint64_t dispatch_count_ = 0;
  std::optional<omarchy::plugin_runtime::channel::BrokerReply> reply_;
};

bool apply_lab_revocation_update(
    const grants::RevisionGrants &updated,
    runtime::AuditedBrokerRuntime &broker_runtime,
    runtime::DynamicBrokerRuntime *dynamic_runtime,
    providers::RadioProvider *radio_provider,
    providers::AudioDeviceProvider *audio_device_provider,
    providers::GitHubProvider *github_provider,
    host::PreparedPlugin &prepared,
    headless::Session &session) {
  if (updated.binding != broker_runtime.binding() ||
      updated.grants.size() != broker_runtime.revision().grants.size() ||
      updated.dynamic_grants.size() !=
          broker_runtime.revision().dynamic_grants.size())
    return false;
  std::size_t changes = 0;
  for (const auto &current : broker_runtime.revision().grants.values()) {
    const auto found = std::ranges::find_if(
        updated.grants.values(), [&](const auto &candidate) {
          return candidate.capability == current.capability;
        });
    if (found == updated.grants.values().end())
      return false;
    if (*found == current)
      continue;
    const auto *definition = permissions::find_capability(current.capability);
    if (definition == nullptr ||
        current.state != permissions::GrantState::granted ||
        found->state != permissions::GrantState::revoked ||
        found->scope != current.scope || found->epoch != current.epoch + 1)
      return false;
    grants::RevocationResult revocation{
        .target = grants::TargetRevision::active,
        .grant = *found,
        .action = definition->revocation,
        .grant_fingerprint = {}};
    const auto applied = broker_runtime.apply_revocation(revocation);
    if (applied.status != runtime::RuntimeStatus::accepted ||
        applied.restart_worker)
      return false;
    for (auto &availability : prepared.permission_availability) {
      if (availability.capability == current.capability.id.view())
        availability.granted = false;
    }
    ++changes;
  }
  for (const auto &current : broker_runtime.revision().dynamic_grants) {
    const auto found = std::ranges::find_if(
        updated.dynamic_grants, [&](const auto &candidate) {
          return candidate.request.definition.canonical_name ==
                 current.request.definition.canonical_name;
        });
    if (found == updated.dynamic_grants.end()) return false;
    if (found->grant.state == current.grant.state &&
        found->grant.epoch == current.grant.epoch)
      continue;
    if (dynamic_runtime == nullptr ||
        current.request.definition.definition_generation !=
            found->request.definition.definition_generation ||
        current.request.definition.definition_digest !=
            found->request.definition.definition_digest ||
        current.request.operations != found->request.operations ||
        current.request.scope != found->request.scope ||
        current.grant.state != permissions::GrantState::granted ||
        found->grant.state != permissions::GrantState::revoked ||
        found->grant.epoch != current.grant.epoch + 1)
      return false;
    if (found->request.definition.canonical_name.view() == "network.fetch") {
      if (radio_provider == nullptr) return false;
      (void)radio_provider->revoke_fetch(found->grant.epoch);
    } else if (found->request.definition.canonical_name.view() ==
               "media.play-stream") {
      if (radio_provider == nullptr) return false;
      (void)radio_provider->revoke_media(found->grant.epoch);
    } else if (found->request.definition.canonical_name.view() ==
               "device.observe") {
      if (audio_device_provider == nullptr ||
          !audio_device_provider->revoke_observe(found->grant.epoch))
        return false;
    } else if (found->request.definition.canonical_name.view() ==
               "device.control") {
      if (audio_device_provider == nullptr ||
          !audio_device_provider->revoke_control(found->grant.epoch))
        return false;
    } else if (found->request.definition.canonical_name.view() ==
               "remote-account.read") {
      if (github_provider == nullptr)
        return false;
      (void)github_provider->revoke_read(found->grant.epoch);
    } else if (found->request.definition.canonical_name.view() ==
               "remote-account.write") {
      if (github_provider == nullptr)
        return false;
      (void)github_provider->revoke_write(found->grant.epoch);
    } else if (found->request.definition.canonical_name.view() ==
               "external.open-uri.https") {
      if (github_provider == nullptr)
        return false;
      (void)github_provider->revoke_open(found->grant.epoch);
    } else {
      return false;
    }
    if (!dynamic_runtime->apply_reconstructed_update(*found)) return false;
    for (auto &availability : prepared.permission_availability)
      if (availability.capability ==
          found->request.definition.canonical_name.view())
        availability.granted = false;
    ++changes;
  }
  return changes == 1 && host::update_permission_availability(session, prepared);
}

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
#ifdef OMARCHY_PLUGIN_PRODUCT_E2E
    std::cerr << "PRODUCT_E2E prepare failed: " << prepared.detail << '\n';
#endif
    qCritical().noquote() << "omarchy-plugin-host: preview rejected:"
                          << QString::fromStdString(prepared.detail);
    return 78;
  }
  const int state_fd = open(arguments.at(5).toLocal8Bit().constData(),
                            O_RDONLY | O_DIRECTORY | O_CLOEXEC);
  if (state_fd < 0) {
#ifdef OMARCHY_PLUGIN_PRODUCT_E2E
    qCritical() << "PRODUCT_E2E state open failed" << errno;
#endif
    return 78;
  }
  struct Fd { int value; ~Fd() { close(value); } } owned_state{state_fd};
  audit::AuditStore audit_store(arguments.at(6).toStdString(), {});
  health::HealthSupervisor health_supervisor({}, audit_store);
  auto supervisor = live_lab
#ifdef OMARCHY_PLUGIN_PRODUCT_E2E
      ? launcher::Supervisor::forTestOnly(
            "/usr/bin/bwrap", arguments.at(7).toStdString(),
            std::make_shared<TestScope>())
#else
      ? launcher::Supervisor::forRootOwnedLiveLabOnly(
            arguments.at(7).toStdString(), arguments.at(8).toStdString(),
            arguments.at(9).toStdString())
#endif
      : launcher::Supervisor::production();
  std::unique_ptr<providers::PrivateStorageBackend> storage;
  std::unique_ptr<DesktopEffects> effects;
  std::unique_ptr<runtime::AuditedBrokerRuntime> broker_runtime;
  std::unique_ptr<definitions::TrustedDefinitionRegistry> dynamic_registry;
  std::unique_ptr<providers::RadioProvider> radio_provider;
  std::unique_ptr<providers::AudioDeviceProvider> audio_device_provider;
  std::unique_ptr<providers::BluezAudioBackend> bluez_audio_backend;
  std::unique_ptr<providers::GitHubCliBackend> github_cli_backend;
  std::unique_ptr<providers::GitHubProvider> github_provider;
  std::unique_ptr<providers::RadioLiveBackend> radio_live_backend;
  std::unique_ptr<runtime::DynamicBrokerRuntime> dynamic_runtime;
  std::vector<external_provider::Registration> external_registrations;
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
    if (!active->dynamic_grants.empty()) {
      std::uint64_t fetch_epoch = 0;
      std::uint64_t media_epoch = 0;
      std::uint64_t observe_epoch = 0;
      std::uint64_t control_epoch = 0;
      std::uint64_t account_read_epoch = 0;
      std::uint64_t account_write_epoch = 0;
      std::uint64_t open_uri_epoch = 0;
      for (const auto &dynamic : active->dynamic_grants) {
        if (dynamic.grant.definition.canonical_name.view() == "network.fetch")
          fetch_epoch = dynamic.grant.epoch;
        else if (dynamic.grant.definition.canonical_name.view() == "media.play-stream")
          media_epoch = dynamic.grant.epoch;
        else if (dynamic.grant.definition.canonical_name.view() == "device.observe")
          observe_epoch = dynamic.grant.epoch;
        else if (dynamic.grant.definition.canonical_name.view() == "device.control")
          control_epoch = dynamic.grant.epoch;
        else if (dynamic.grant.definition.canonical_name.view() == "remote-account.read")
          account_read_epoch = dynamic.grant.epoch;
        else if (dynamic.grant.definition.canonical_name.view() == "remote-account.write")
          account_write_epoch = dynamic.grant.epoch;
        else if (dynamic.grant.definition.canonical_name.view() == "external.open-uri.https")
          open_uri_epoch = dynamic.grant.epoch;
      }
      providers::RadioProviderConfiguration radio_configuration{
          .binding = active->binding, .fetch_epoch = fetch_epoch,
          .media_epoch = media_epoch, .https = {}, .media = {}};
#if defined(OMARCHY_PLUGIN_PRODUCT_E2E) && !defined(OMARCHY_PLUGIN_REAL_RADIO_E2E)
      radio_configuration.https = {.get = fixture_radio_get};
      radio_configuration.media = {.play = fixture_radio_play,
                                   .control = fixture_radio_control};
#else
      radio_live_backend = std::make_unique<providers::RadioLiveBackend>();
      radio_configuration.https = radio_live_backend->https_configuration();
      radio_configuration.media = radio_live_backend->media_configuration();
#endif
      radio_provider = std::make_unique<providers::RadioProvider>(radio_configuration);
      providers::AudioDeviceProviderConfiguration audio_configuration{
          .binding = active->binding, .observe_epoch = observe_epoch,
          .control_epoch = control_epoch, .backend = {}};
#ifdef OMARCHY_PLUGIN_PRODUCT_E2E
      const auto selected_audio_address =
          qEnvironmentVariable("OMARCHY_PLUGIN_E2E_SELECTED_AUDIO_ADDRESS");
      if (!selected_audio_address.isEmpty()) {
        bluez_audio_backend = std::make_unique<providers::BluezAudioBackend>(
            selected_audio_address.toStdString());
        if (!bluez_audio_backend->valid_selection()) {
          qCritical() << "PRODUCT_E2E selected audio device is invalid";
          return 78;
        }
        audio_configuration.backend = bluez_audio_backend->configuration();
      } else {
        audio_configuration.backend = {.observe = fixture_audio_observe,
                                       .control = fixture_audio_control};
      }
#endif
      audio_device_provider = std::make_unique<providers::AudioDeviceProvider>(
          audio_configuration);
      std::filesystem::path github_program;
#ifdef OMARCHY_PLUGIN_PRODUCT_E2E
      github_program = qEnvironmentVariable("OMARCHY_PLUGIN_GITHUB_PROVIDER").toStdString();
      const std::uint32_t github_provider_owner = static_cast<std::uint32_t>(getuid());
#else
      github_program = "/usr/lib/omarchy/plugin-providers/omarchy-github-provider";
      constexpr std::uint32_t github_provider_owner = 0;
#endif
      github_cli_backend = std::make_unique<providers::GitHubCliBackend>(
          github_program, std::filesystem::path(arguments.at(5).toStdString()) /
                              "github-provider",
          github_provider_owner);
      github_provider = std::make_unique<providers::GitHubProvider>(
          providers::GitHubProviderConfiguration{
              .binding = active->binding,
              .read_epoch = account_read_epoch,
              .write_epoch = account_write_epoch,
              .open_epoch = open_uri_epoch,
              .backend = github_cli_backend->configuration()});
      DynamicAdapters adapters{.fetch = radio_provider->fetch_adapter(),
          .media = radio_provider->media_adapter(),
          .device_observe = audio_device_provider->observe_adapter(),
          .device_control = audio_device_provider->control_adapter(),
          .account_read = github_provider->read_adapter(),
          .account_write = github_provider->write_adapter(),
          .open_uri = github_provider->open_adapter(),
          .external = {}};
#ifndef OMARCHY_PLUGIN_PRODUCT_E2E
      const std::filesystem::path provider_registration_root(
          "/etc/omarchy/plugin-providers.d");
      if (std::filesystem::exists(provider_registration_root)) {
        if (external_provider::load_registration_directory(
                provider_registration_root.string(), 0,
                external_registrations) !=
            external_provider::RegistrationLoadResult::loaded) {
          qCritical() << "omarchy-plugin-host: administrator provider registrations are invalid";
          return 78;
        }
        adapters.external.reserve(external_registrations.size());
        for (auto &registration : external_registrations)
          adapters.external.push_back(
              external_provider::compose_dynamic_adapter(registration));
      }
#endif
      dynamic_registry = std::make_unique<definitions::TrustedDefinitionRegistry>();
      std::size_t loaded = 0;
#ifdef OMARCHY_PLUGIN_PRODUCT_E2E
      const std::filesystem::path definition_root(
          OMARCHY_PLUGIN_DYNAMIC_DEFINITION_ROOT);
      const std::uint32_t definition_owner = static_cast<std::uint32_t>(getuid());
#else
      const auto executable = std::filesystem::canonical("/proc/self/exe");
      const auto definition_root = executable.parent_path().parent_path() /
                                   "lib/omarchy/plugin-capabilities.d";
      constexpr std::uint32_t definition_owner = 0;
#endif
      const definitions::AdapterVerifier verifier{
          .available = dynamic_adapter_available,
          .context = &adapters};
      if (definitions::load_definition_directory(
              definition_root.string(), definitions::DefinitionSource::omarchy_package,
              definition_owner, verifier, *dynamic_registry, loaded) !=
              definitions::LoadResult::loaded || loaded < 2) {
        qCritical() << "omarchy-plugin-host: trusted dynamic definitions unavailable";
        return 78;
      }
#ifndef OMARCHY_PLUGIN_PRODUCT_E2E
      const std::filesystem::path admin_definition_root(
          "/etc/omarchy/plugin-capabilities.d");
      if (std::filesystem::exists(admin_definition_root)) {
        std::size_t admin_loaded = 0;
        if (definitions::load_definition_directory(
                admin_definition_root.string(),
                definitions::DefinitionSource::local_admin, 0, verifier,
                *dynamic_registry, admin_loaded) !=
            definitions::LoadResult::loaded) {
          qCritical() << "omarchy-plugin-host: administrator capability definitions are invalid";
          return 78;
        }
      }
#endif
      std::vector<runtime::DynamicRoute> routes;
      for (const auto &dynamic : active->dynamic_grants) {
        const auto resolved = dynamic_registry->resolve(dynamic.request.definition);
        if (!resolved) return 78;
        definitions::DynamicAdapter adapter;
        if (resolved->definition->adapter == adapters.fetch.binding)
          adapter = adapters.fetch;
        else if (resolved->definition->adapter == adapters.media.binding)
          adapter = adapters.media;
        else if (resolved->definition->adapter == adapters.device_observe.binding)
          adapter = adapters.device_observe;
        else if (resolved->definition->adapter == adapters.device_control.binding)
          adapter = adapters.device_control;
        else if (resolved->definition->adapter == adapters.account_read.binding)
          adapter = adapters.account_read;
        else if (resolved->definition->adapter == adapters.account_write.binding)
          adapter = adapters.account_write;
        else if (resolved->definition->adapter == adapters.open_uri.binding)
          adapter = adapters.open_uri;
        else {
          const auto external = std::ranges::find_if(
              adapters.external, [&](const auto &candidate) {
                return resolved->definition->adapter == candidate.binding;
              });
          if (external != adapters.external.end())
            adapter = *external;
          else if (dynamic.request.required)
            return 78;
          else
            continue;
        }
        routes.push_back({.grant = dynamic, .adapter = adapter,
                          .scope_validator = {.compare = exact_dynamic_scope}});
      }
      if (!routes.empty())
        dynamic_runtime = std::make_unique<runtime::DynamicBrokerRuntime>(
            *dynamic_registry, std::move(routes), audit_store);
    }
    lab_broker = std::make_shared<LabBroker>(*broker_runtime,
                                             dynamic_runtime.get(),
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
#ifdef OMARCHY_PLUGIN_PRODUCT_E2E
    std::cerr << "PRODUCT_E2E launch failed "
              << static_cast<int>(started.failure) << ": " << started.detail
              << '\n';
#endif
    qCritical().noquote() << "omarchy-plugin-host: preview launch failed:"
                          << QString::fromStdString(started.detail);
    return 78;
  }
  auto transport = std::make_shared<Transport>(*started.session);
  Inspection inspection;
  Clock clock;
  struct PreviewSurface {
    std::string name;
    std::unique_ptr<QQuickWindow> window;
    std::unique_ptr<bridge::RemotePluginSurface> bridge;
    std::unique_ptr<surface_host::HostSurface> hosted;
    std::unique_ptr<PreviewPointerBridge> pointer;
    std::unique_ptr<PreviewInputRegionBridge> input_regions;
  };
  std::vector<PreviewSurface> previews;
  previews.reserve(prepared.prepared->surfaces.size());
  bool composition_failed = false;
  for (std::size_t index = 0; index < prepared.prepared->surfaces.size();
       ++index) {
    const auto &policy = prepared.prepared->surfaces[index];
    const auto width = std::min<std::uint32_t>(policy.maximum_width, 640);
    const auto height = std::min<std::uint32_t>(policy.maximum_height, 480);
    const auto surface_id = static_cast<std::uint64_t>(index + 1);
    if (!host::bind_surface_session(
            *started.session, *prepared.prepared, policy.surface_name,
            surface_id, prepared.prepared->binding.generation)) {
      composition_failed = true;
      break;
    }
    PreviewSurface preview;
    preview.name = policy.surface_name;
    preview.window = std::make_unique<QQuickWindow>();
    preview.window->resize(static_cast<int>(width), static_cast<int>(height));
    preview.window->setTitle(
        QStringLiteral("Omarchy secure plugin preview: ") +
        QString::fromStdString(parsed.name) + QStringLiteral(" — ") +
        QString::fromStdString(policy.surface_name));
    preview.bridge = std::make_unique<bridge::RemotePluginSurface>(
        preview.window->contentItem());
    preview.bridge->setWidth(width);
    preview.bridge->setHeight(height);
    preview.hosted = surface_host::HostSurface::create(
        policy, prepared.prepared->binding, surface_id, width, height, 1, 1,
        *preview.bridge, *transport, transport, inspection, clock);
    if (!preview.hosted) {
      composition_failed = true;
      break;
    }
    preview.pointer =
        std::make_unique<PreviewPointerBridge>(*preview.hosted);
    preview.input_regions =
        std::make_unique<PreviewInputRegionBridge>(*preview.hosted);
    preview.bridge->bindHostPointerRouter(*preview.pointer);
    preview.bridge->bindHostInputRegionRouter(*preview.input_regions);
    previews.push_back(std::move(preview));
  }
  if (composition_failed || previews.empty()) {
#ifdef OMARCHY_PLUGIN_PRODUCT_E2E
    std::cerr << "PRODUCT_E2E host surface creation failed\n";
    qCritical() << "PRODUCT_E2E host surface creation failed";
#endif
    return 78;
  }
  QTimer pump;
  std::uint64_t observed_grant_mutation = state.mutation_sequence;
#ifdef OMARCHY_PLUGIN_PRODUCT_E2E
  const std::uint64_t startup_grant_mutation = state.mutation_sequence;
  const int expected_calls = qEnvironmentVariableIntValue("OMARCHY_PLUGIN_E2E_EXPECT_CALLS");
  const bool expected_calls_set = qEnvironmentVariableIsSet("OMARCHY_PLUGIN_E2E_EXPECT_CALLS");
  const int expected_frames = qEnvironmentVariableIntValue("OMARCHY_PLUGIN_E2E_EXPECT_FRAMES");
  const int expected_render_packets =
      qEnvironmentVariableIntValue("OMARCHY_PLUGIN_E2E_EXPECT_RENDER_PACKETS");
  const int expected_mutation =
      qEnvironmentVariableIntValue("OMARCHY_PLUGIN_E2E_EXPECT_MUTATION");
  const int expected_post_mutation_frames =
      qEnvironmentVariableIntValue("OMARCHY_PLUGIN_E2E_EXPECT_POST_MUTATION_FRAMES");
  const int expected_post_call_frames =
      qEnvironmentVariableIntValue("OMARCHY_PLUGIN_E2E_EXPECT_POST_CALL_FRAMES");
  struct FrameEvidence {
    std::uint64_t surface_id;
    QByteArray hash;
  };
  std::vector<FrameEvidence> frame_hashes;
  std::vector<std::uint64_t> post_mutation_surface_frames;
  std::uint64_t render_packets = 0;
  std::uint64_t post_mutation_frames = 0;
  std::uint64_t post_call_frames = 0;
  bool injected_pointer = false;
  QTimer deadline;
  deadline.setSingleShot(true);
  QObject::connect(&deadline, &QTimer::timeout, [&] {
    const auto worker_error = started.session->take_worker_standard_error();
    std::cerr << "PRODUCT_E2E timeout calls " << lab_broker->dispatch_count()
              << " frames " << frame_hashes.size() << " render_packets "
              << render_packets << " post_mutation_frames "
              << post_mutation_frames << " post_call_frames "
              << post_call_frames << " worker_stderr "
              << worker_error << " grant_mutation " << observed_grant_mutation
              << '\n';
    qCritical() << "PRODUCT_E2E timeout calls" << lab_broker->dispatch_count()
                << "frames" << frame_hashes.size();
    application.exit(80);
  });
  const int deadline_milliseconds =
      qEnvironmentVariableIntValue("OMARCHY_PLUGIN_E2E_DEADLINE_MS");
  deadline.start(deadline_milliseconds > 0 ? deadline_milliseconds : 8000);
#endif
  QObject::connect(&pump, &QTimer::timeout, [&] {
    if (live_lab) {
      try {
        const auto latest = grant_store.read();
        if (latest.mutation_sequence != observed_grant_mutation) {
          const grants::RevisionGrants *updated = nullptr;
          for (const auto &plugin : latest.plugins) {
            if (plugin.plugin == prepared.prepared->binding.plugin && plugin.active)
              updated = &*plugin.active;
          }
          if (updated == nullptr ||
              !apply_lab_revocation_update(*updated, *broker_runtime,
                                           dynamic_runtime.get(), radio_provider.get(),
                                           audio_device_provider.get(),
                                           github_provider.get(),
                                           *prepared.prepared, *started.session)) {
            qCritical() << "omarchy-plugin-host: live grant update was not an exact revocation";
            application.exit(79);
            return;
          }
          observed_grant_mutation = latest.mutation_sequence;
#ifdef OMARCHY_PLUGIN_PRODUCT_E2E
          std::cerr << "PRODUCT_E2E grant_mutation "
                    << observed_grant_mutation << " render_packets "
                    << render_packets << '\n';
#endif
        }
      } catch (const std::exception &error) {
        qCritical().noquote() << "omarchy-plugin-host: live grant reload failed:"
                              << error.what();
        application.exit(79);
        return;
      }
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
      const auto decoded = wire::decode_packet(
          message.payload, wire::EndpointRole::render);
      std::uint64_t target_surface_id = 0;
      if (decoded && decoded.packet.header.correlation_id != 0) {
        target_surface_id = decoded.packet.header.correlation_id / 4;
      } else if (decoded) {
        const auto type = static_cast<surface::RenderMessageType>(
            decoded.packet.header.message_type);
        if (type == surface::RenderMessageType::frame_ready) {
          surface::FrameReady frame{};
          if (surface::decode_frame_ready(decoded.packet.payload, frame))
            target_surface_id = frame.surface.id;
        } else if (type == surface::RenderMessageType::input_regions) {
          surface::InputRegionUpdate regions{};
          if (surface::decode_input_region_update(decoded.packet.payload,
                                                   regions))
            target_surface_id = regions.surface.id;
        }
      }
      auto target = std::ranges::find_if(previews, [&](const auto &preview) {
        return preview.hosted->allocation().surface.id == target_surface_id;
      });
      if (target == previews.end() ||
          (!target->hosted->receive_render(message.payload) &&
           !target->hosted->inspection().render_active)) {
        if (decoded) {
          qCritical() << "omarchy-plugin-host: host surface rejected render packet"
                      << decoded.packet.header.message_type
                      << decoded.packet.header.correlation_id << "target"
                      << target_surface_id << "declared surfaces";
          for (const auto &preview : previews)
            qCritical() << QString::fromStdString(preview.name)
                        << preview.hosted->allocation().surface.id;
        } else {
          qCritical() << "omarchy-plugin-host: host surface rejected malformed render packet";
        }
        application.exit(79);
        return;
      }
#ifdef OMARCHY_PLUGIN_PRODUCT_E2E
      const auto message_type = decoded
          ? static_cast<surface::RenderMessageType>(
                decoded.packet.header.message_type)
          : surface::RenderMessageType{};
      const auto &image = target->bridge->ownedImage();
      ++render_packets;
      if (message_type == surface::RenderMessageType::frame_ready &&
          !image.isNull()) {
        if (observed_grant_mutation > startup_grant_mutation)
          ++post_mutation_frames;
        if (lab_broker->dispatch_count() >=
            static_cast<std::uint64_t>(expected_calls))
          ++post_call_frames;
        const auto bytes = QByteArrayView(
            reinterpret_cast<const char *>(image.constBits()), image.sizeInBytes());
        const auto hash = QCryptographicHash::hash(bytes, QCryptographicHash::Sha256);
        if (observed_grant_mutation > startup_grant_mutation &&
            std::ranges::find(post_mutation_surface_frames,
                              target_surface_id) ==
                post_mutation_surface_frames.end()) {
          post_mutation_surface_frames.push_back(target_surface_id);
          std::cerr << "PRODUCT_E2E post_mutation_surface " << target->name
                    << ' ' << target_surface_id << " hash "
                    << hash.toHex().constData() << '\n';
        }
        const auto evidence = std::ranges::find_if(
            frame_hashes, [&](const auto &frame) {
              return frame.surface_id == target_surface_id &&
                     frame.hash == hash;
            });
        if (evidence == frame_hashes.end()) {
          frame_hashes.push_back(
              {.surface_id = target_surface_id, .hash = hash});
          std::cerr << "PRODUCT_E2E frame " << frame_hashes.size()
                    << " surface " << target->name << ' ' << target_surface_id
                    << " hash " << hash.toHex().constData() << '\n';
          qInfo().noquote() << "PRODUCT_E2E frame" << frame_hashes.size()
                            << "surface" << QString::fromStdString(target->name)
                            << target_surface_id << "hash" << hash.toHex();
        }
        if (!injected_pointer &&
            qEnvironmentVariableIsSet("OMARCHY_PLUGIN_E2E_CLICK_X") &&
            observed_grant_mutation >= static_cast<std::uint64_t>(
                qEnvironmentVariableIntValue(
                    "OMARCHY_PLUGIN_E2E_CLICK_AFTER_MUTATION"))) {
          const auto x = qEnvironmentVariableIntValue("OMARCHY_PLUGIN_E2E_CLICK_X");
          const auto y = qEnvironmentVariableIntValue("OMARCHY_PLUGIN_E2E_CLICK_Y");
          injected_pointer = previews.front().pointer->route(
              {.x = static_cast<qreal>(x), .y = static_cast<qreal>(y),
               .button = Qt::LeftButton, .pressed = true,
               .application_synthesized = false}) &&
              previews.front().pointer->route(
                  {.x = static_cast<qreal>(x), .y = static_cast<qreal>(y),
                   .button = Qt::LeftButton, .pressed = false,
                   .application_synthesized = false});
          if (!injected_pointer) {
            qCritical() << "PRODUCT_E2E bounded pointer route rejected";
            application.exit(79);
            return;
          }
          std::cerr << "PRODUCT_E2E pointer " << x << ' ' << y << '\n';
        }
      }
      if (expected_calls_set && expected_frames > 0 &&
          lab_broker->dispatch_count() >= static_cast<std::uint64_t>(expected_calls) &&
          frame_hashes.size() >= static_cast<std::size_t>(expected_frames) &&
          render_packets >= static_cast<std::uint64_t>(expected_render_packets) &&
          post_mutation_frames >=
              static_cast<std::uint64_t>(expected_post_mutation_frames) &&
          post_call_frames >=
              static_cast<std::uint64_t>(expected_post_call_frames) &&
          observed_grant_mutation >= static_cast<std::uint64_t>(expected_mutation)) {
        qInfo() << "PRODUCT_E2E complete calls" << lab_broker->dispatch_count()
                << "frames" << frame_hashes.size()
                << "grant_mutation" << observed_grant_mutation;
        std::cerr << "PRODUCT_E2E complete calls " << lab_broker->dispatch_count()
                  << " frames " << frame_hashes.size()
                  << " render_packets " << render_packets
                  << " post_mutation_frames " << post_mutation_frames
                  << " post_call_frames " << post_call_frames
                  << " grant_mutation " << observed_grant_mutation << '\n';
        application.exit(0);
      }
#endif
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
  for (auto &preview : previews)
    preview.window->show();
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
#ifdef OMARCHY_PLUGIN_PRODUCT_E2E
      std::cerr << "PRODUCT_E2E stage activation failed: " << error.what()
                << '\n';
#endif
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
#ifdef OMARCHY_PLUGIN_PRODUCT_E2E
      std::cerr << "PRODUCT_E2E empty activation failed: " << error.what()
                << '\n';
#endif
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
