#include "authenticated_channel.hpp"
#include "broker_runtime.hpp"
#include "surface_host.hpp"
#include "worker_runtime.hpp"

#include "omarchy/plugin_runtime/broker/broker_schema.hpp"
#include "omarchy/plugin_runtime/sandbox/policy.h"
#include "omarchy/plugin_runtime/surface/render_messages.hpp"

#include <QGuiApplication>
#include <QMetaObject>
#include <QVariant>

#include <fcntl.h>
#include <unistd.h>

#include <algorithm>
#include <array>
#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <memory>
#include <span>
#include <stdexcept>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace {

namespace audit = omarchy::plugins::audit;
namespace bridge = omarchy::plugin_runtime::bridge;
namespace broker = omarchy::plugin_runtime::broker;
namespace channel = omarchy::plugin_runtime::channel;
namespace grants = omarchy::plugins::grants;
namespace host = omarchy::plugin_runtime::surface_host;
namespace launcher = omarchy::plugin_runtime::launcher;
namespace manifest = omarchy::plugins::manifest;
namespace permissions = omarchy::plugins::permissions;
namespace providers = omarchy::plugin_runtime::providers;
namespace runtime = omarchy::plugin_runtime::runtime;
namespace sandbox = omarchy::plugin_runtime::sandbox;
namespace session = omarchy::plugin_runtime::render_session;
namespace surface = omarchy::plugin_runtime::surface;
namespace wire = omarchy::plugin::wire;
namespace worker = omarchy::plugin_runtime::worker;

const std::filesystem::path kPomodoro{E1_POMODORO_ROOT};
const std::string kRevision(64, 'a');
const std::string kSourceFingerprint(64, 'c');

void require(bool condition, std::string_view detail) {
  if (!condition)
    throw std::runtime_error(std::string(detail));
}

std::string read_text(const std::filesystem::path &path) {
  std::ifstream input(path, std::ios::binary);
  require(input.good(), "fixture file could not be opened");
  return {std::istreambuf_iterator<char>(input),
          std::istreambuf_iterator<char>()};
}

void write_text(const std::filesystem::path &path, std::string_view value) {
  std::ofstream output(path, std::ios::binary | std::ios::trunc);
  require(output.good(), "hostile fixture file could not be opened");
  output.write(value.data(), static_cast<std::streamsize>(value.size()));
  require(output.good(), "hostile fixture file could not be written");
}

void put16(std::vector<std::byte> &bytes, std::size_t offset,
           std::uint16_t value) {
  bytes[offset] = static_cast<std::byte>(value >> 8U);
  bytes[offset + 1] = static_cast<std::byte>(value);
}

void put32(std::vector<std::byte> &bytes, std::size_t offset,
           std::uint32_t value) {
  for (std::size_t index = 0; index < 4; ++index)
    bytes[offset + index] =
        static_cast<std::byte>(value >> ((3U - index) * 8U));
}

void put64(std::vector<std::byte> &bytes, std::size_t offset,
           std::uint64_t value) {
  for (std::size_t index = 0; index < 8; ++index)
    bytes[offset + index] =
        static_cast<std::byte>(value >> ((7U - index) * 8U));
}

permissions::CapabilityKey capability(std::string_view id) {
  return {.id = permissions::CapabilityId(id), .version = 1};
}

permissions::TokenScope token(std::string_view value) {
  permissions::TokenScope scope;
  require(scope.tokens.insert(permissions::ScopeToken(value)),
          "token scope fixture failed");
  return scope;
}

grants::RevisionGrants revision() {
  grants::RevisionGrants result;
  result.binding.plugin = permissions::PluginId("org.omarchy.fixture.pomodoro");
  result.binding.revision = permissions::Digest(kRevision);
  result.binding.generation = 71;
  result.source_request_fingerprint = permissions::Digest(kSourceFingerprint);
  result.requests.push_back({capability("storage.private"),
                             permissions::QuotaScope{65536, 4096}, true});
  result.requests.push_back(
      {capability("notifications.send"), token("timer"), false});
  result.requests.push_back(
      {capability("audio.play-cue"), token("timer-complete"), false});
  result.grants.push_back({capability("storage.private"),
                           permissions::QuotaScope{65536, 4096},
                           permissions::GrantState::granted, 1});
  result.grants.push_back({capability("notifications.send"), token("timer"),
                           permissions::GrantState::denied, 1});
  result.grants.push_back({capability("audio.play-cue"),
                           token("timer-complete"),
                           permissions::GrantState::denied, 1});
  result.binding.policy_fingerprint = permissions::Digest(
      permissions::policy_request_fingerprint(result.requests));
  return result;
}

class TemporaryDirectory {
public:
  TemporaryDirectory() {
    std::string pattern = "/tmp/omarchy-e1-XXXXXX";
    char *created = mkdtemp(pattern.data());
    require(created != nullptr, "temporary directory creation failed");
    path_ = created;
  }
  ~TemporaryDirectory() {
    std::error_code error;
    std::filesystem::remove_all(path_, error);
  }
  [[nodiscard]] const std::filesystem::path &path() const { return path_; }

private:
  std::filesystem::path path_;
};

struct Backend {
  static bool latest_allowed(const Backend &self,
                             permissions::OperationId operation) noexcept {
    try {
      const auto records = self.audit_store->query({});
      if (!records.status.ok() || records.records.empty())
        return false;
      const auto &record = records.records.back();
      return record.producer == permissions::AuditProducer::broker &&
             record.event == permissions::AuditEvent::operation_decided &&
             record.outcome == permissions::AuditOutcome::allowed &&
             record.plugin.view() == "org.omarchy.fixture.pomodoro" &&
             record.revision.view() == kRevision && record.generation == 71 &&
             record.correlation != 0 && record.operation == operation;
    } catch (...) {
      return false;
    }
  }

  static bool read(std::string_view key, std::span<std::byte>,
                   std::size_t &bytes_written, bool &found,
                   void *context) noexcept {
    auto &self = *static_cast<Backend *>(context);
    ++self.reads;
    self.last_key = std::string(key);
    bytes_written = 0;
    found = false;
    self.audit_before_effect =
        latest_allowed(self, permissions::OperationId::storage_read);
    return true;
  }
  static bool write(std::string_view key, std::span<const std::byte> value,
                    void *context) noexcept {
    auto &self = *static_cast<Backend *>(context);
    ++self.writes;
    self.last_key = std::string(key);
    self.last_value.assign(reinterpret_cast<const char *>(value.data()),
                           value.size());
    self.audit_before_effect =
        self.audit_before_effect &&
        latest_allowed(self, permissions::OperationId::storage_write);
    return true;
  }
  static bool notify(std::string_view, std::string_view, std::string_view,
                     void *context) noexcept {
    ++static_cast<Backend *>(context)->notifications;
    return true;
  }
  static bool audio(std::string_view, void *context) noexcept {
    ++static_cast<Backend *>(context)->audio_cues;
    return true;
  }

  audit::AuditStore *audit_store = nullptr;
  std::size_t reads = 0;
  std::size_t writes = 0;
  std::size_t notifications = 0;
  std::size_t audio_cues = 0;
  bool audit_before_effect = false;
  std::string last_key;
  std::string last_value;
};

providers::ProviderConfiguration provider_configuration(Backend &backend) {
  providers::ProviderConfiguration result;
  result.storage.read = Backend::read;
  result.storage.write = Backend::write;
  result.storage.context = &backend;
  result.storage.maximum_total_bytes = 65536;
  result.storage.maximum_item_bytes = 4096;
  result.notification.send = Backend::notify;
  result.notification.context = &backend;
  result.audio.play = Backend::audio;
  result.audio.context = &backend;
  return result;
}

std::vector<std::byte> quota_request(permissions::OperationId operation,
                                     std::span<const std::byte> provider) {
  std::vector<std::byte> result(24 + provider.size());
  put16(result, 0, static_cast<std::uint16_t>(operation));
  put16(result, 2, 16);
  put32(result, 4, static_cast<std::uint32_t>(provider.size()));
  put64(result, 8, 65536);
  put64(result, 16, 4096);
  std::copy(provider.begin(), provider.end(), result.begin() + 24);
  return result;
}

std::vector<std::byte> token_request(permissions::OperationId operation,
                                     std::string_view scope,
                                     std::span<const std::byte> provider) {
  std::vector<std::byte> result(10 + scope.size() + provider.size());
  put16(result, 0, static_cast<std::uint16_t>(operation));
  put16(result, 2, static_cast<std::uint16_t>(2 + scope.size()));
  put32(result, 4, static_cast<std::uint32_t>(provider.size()));
  put16(result, 8, static_cast<std::uint16_t>(scope.size()));
  std::transform(scope.begin(), scope.end(), result.begin() + 10,
                 [](char value) { return static_cast<std::byte>(value); });
  std::copy(provider.begin(), provider.end(),
            result.begin() + static_cast<std::ptrdiff_t>(10 + scope.size()));
  return result;
}

std::vector<std::byte> storage_read(std::string_view key) {
  std::vector<std::byte> provider(2 + key.size());
  put16(provider, 0, static_cast<std::uint16_t>(key.size()));
  std::transform(key.begin(), key.end(), provider.begin() + 2,
                 [](char value) { return static_cast<std::byte>(value); });
  return quota_request(permissions::OperationId::storage_read, provider);
}

std::vector<std::byte> storage_write(std::string_view key,
                                     std::string_view value) {
  std::vector<std::byte> provider(6 + key.size() + value.size());
  put16(provider, 0, static_cast<std::uint16_t>(key.size()));
  put32(provider, 2, static_cast<std::uint32_t>(value.size()));
  std::transform(key.begin(), key.end(), provider.begin() + 6,
                 [](char item) { return static_cast<std::byte>(item); });
  std::transform(value.begin(), value.end(),
                 provider.begin() + static_cast<std::ptrdiff_t>(6 + key.size()),
                 [](char item) { return static_cast<std::byte>(item); });
  return quota_request(permissions::OperationId::storage_write, provider);
}

std::vector<std::byte> notification(std::string_view title,
                                    std::string_view body) {
  std::vector<std::byte> provider(4 + title.size() + body.size());
  put16(provider, 0, static_cast<std::uint16_t>(title.size()));
  put16(provider, 2, static_cast<std::uint16_t>(body.size()));
  std::transform(title.begin(), title.end(), provider.begin() + 4,
                 [](char item) { return static_cast<std::byte>(item); });
  std::transform(body.begin(), body.end(),
                 provider.begin() +
                     static_cast<std::ptrdiff_t>(4 + title.size()),
                 [](char item) { return static_cast<std::byte>(item); });
  return token_request(permissions::OperationId::notification_send, "timer",
                       provider);
}

class AuditedDispatcher final : public channel::BrokerDispatcher {
public:
  AuditedDispatcher(runtime::AuditedBrokerRuntime &broker_runtime,
                    std::uint64_t generation)
      : runtime_(broker_runtime), generation_(generation) {}

  [[nodiscard]] bool
  accepts(const launcher::LaunchIdentity &identity) const noexcept override {
    const auto &binding = runtime_.binding();
    return identity.plugin_id == binding.plugin.view() &&
           identity.revision_sha256 == binding.revision.view() &&
           identity.generation == binding.generation;
  }

  [[nodiscard]] bool dispatch(const wire::PacketView &packet) override {
    std::array<std::byte, 4096> response{};
    last = runtime_.dispatch(packet, ++now_, response);
    ++calls;
    if (last.outcome == broker::DispatchOutcome::dispatched) {
      const wire::PacketView terminal{
          .header = {.endpoint_role = wire::EndpointRole::broker,
                     .message_type = broker::kBrokerResultMessage,
                     .role_protocol_version = broker::kBrokerRoleVersion,
                     .payload_length =
                         static_cast<std::uint32_t>(last.response_bytes),
                     .launch_generation = generation_,
                     .correlation_id = packet.header.correlation_id},
          .payload = std::span(response).first(last.response_bytes)};
      return runtime_.accept_terminal(terminal) ==
             broker::TerminalResult::accepted;
    }
    if (last.outcome == broker::DispatchOutcome::denied) {
      const auto error = broker::encode_broker_error(
          {.failed_operation = static_cast<permissions::OperationId>(
               packet.header.message_type),
           .reason = broker::BrokerErrorReason::denied,
           .decision = last.decision.code});
      const wire::PacketView terminal{
          .header = {.endpoint_role = wire::EndpointRole::broker,
                     .message_type = static_cast<std::uint16_t>(
                         wire::CommonMessageType::typed_error),
                     .role_protocol_version = broker::kBrokerRoleVersion,
                     .payload_length = error.size(),
                     .launch_generation = generation_,
                     .correlation_id = packet.header.correlation_id},
          .payload = error};
      return runtime_.accept_terminal(terminal) ==
             broker::TerminalResult::accepted;
    }
    return false;
  }

  runtime::AuditedBrokerRuntime &runtime_;
  std::uint64_t generation_ = 0;
  std::uint64_t now_ = 100;
  std::uint64_t correlation = 0;
  std::size_t calls = 0;
  broker::DispatchResult last{};
};

class BrokerApi final : public QObject {
  Q_OBJECT

public:
  BrokerApi(AuditedDispatcher &dispatcher, std::uint64_t generation,
            QObject *parent = nullptr)
      : QObject(parent), dispatcher_(dispatcher), generation_(generation) {}

  Q_INVOKABLE QVariant invoke(const QString &operation,
                              const QVariantMap &payload) {
    permissions::OperationId id{};
    std::vector<std::byte> request;
    if (operation == QStringLiteral("storage_read")) {
      id = permissions::OperationId::storage_read;
      request = storage_read(
          payload.value(QStringLiteral("key")).toString().toStdString());
    } else if (operation == QStringLiteral("storage_write")) {
      id = permissions::OperationId::storage_write;
      request = storage_write(
          payload.value(QStringLiteral("key")).toString().toStdString(),
          payload.value(QStringLiteral("value")).toString().toStdString());
    } else if (operation == QStringLiteral("notification_send")) {
      id = permissions::OperationId::notification_send;
      request = notification(
          payload.value(QStringLiteral("title")).toString().toStdString(),
          payload.value(QStringLiteral("body")).toString().toStdString());
    } else if (operation == QStringLiteral("audio_play_cue")) {
      id = permissions::OperationId::audio_play_cue;
      request = token_request(id, "timer-complete", {});
    } else {
      ++unknown_denials;
      return false;
    }
    ++correlation_;
    const wire::PacketView packet{
        .header = {.endpoint_role = wire::EndpointRole::broker,
                   .message_type = static_cast<std::uint16_t>(id),
                   .role_protocol_version = broker::kBrokerRoleVersion,
                   .payload_length = static_cast<std::uint32_t>(request.size()),
                   .launch_generation = generation_,
                   .correlation_id = correlation_},
        .payload = request};
    if (!dispatcher_.dispatch(packet))
      return false;
    return dispatcher_.last.outcome == broker::DispatchOutcome::dispatched;
  }

  std::size_t unknown_denials = 0;

private:
  AuditedDispatcher &dispatcher_;
  std::uint64_t generation_ = 0;
  std::uint64_t correlation_ = 0;
};

class AmbientApi final : public QObject {
  Q_OBJECT

public:
  Q_INVOKABLE QVariant invoke(const QString &, const QVariantMap &) {
    return false;
  }
  Q_INVOKABLE QString hostPath() const { return QStringLiteral("/home/user"); }
};

std::vector<std::byte> encode(const wire::EnvelopeHeader &header,
                              std::span<const std::byte> payload) {
  std::vector<std::byte> result(wire::kHeaderSize + payload.size());
  const auto encoded = wire::encode_packet(header, payload, result);
  require(static_cast<bool>(encoded), "render packet encoding failed");
  result.resize(encoded.bytes_written);
  return result;
}

wire::EnvelopeHeader worker_header(std::uint16_t type, std::size_t bytes,
                                   std::uint64_t generation,
                                   std::uint64_t correlation = 0) {
  return {.endpoint_role = wire::EndpointRole::render,
          .message_type = type,
          .role_protocol_version = surface::kRenderRoleVersion,
          .flags = 0,
          .payload_length = static_cast<std::uint32_t>(bytes),
          .launch_generation = generation,
          .correlation_id = correlation};
}

struct QueuedRenderPacket {
  wire::EnvelopeHeader header{};
  std::vector<std::byte> payload;
  int descriptor = -1;
};

class RenderSender final : public session::PacketSender {
public:
  ~RenderSender() override {
    for (auto &packet : packets) {
      if (packet.descriptor >= 0)
        close(packet.descriptor);
    }
  }

  bool send(const wire::EnvelopeHeader &header,
            std::span<const std::byte> payload,
            std::span<const int> descriptors) override {
    if (descriptors.size() > 1)
      return false;
    QueuedRenderPacket packet{.header = header,
                              .payload = {payload.begin(), payload.end()}};
    if (!descriptors.empty()) {
      packet.descriptor = fcntl(descriptors.front(), F_DUPFD_CLOEXEC, 64);
      if (packet.descriptor < 0)
        return false;
    }
    packets.push_back(std::move(packet));
    return true;
  }

  QueuedRenderPacket take() {
    require(!packets.empty(), "render packet queue is empty");
    auto packet = std::move(packets.front());
    packets.erase(packets.begin());
    return packet;
  }

  std::vector<QueuedRenderPacket> packets;
};

class WorkerInputSink final : public bridge::RenderPacketSink {
public:
  explicit WorkerInputSink(worker::WorkerRuntime &runtime)
      : runtime_(runtime) {}

  bool send(const wire::EnvelopeHeader &header,
            std::span<const std::byte> payload) override {
    if (header.message_type ==
        static_cast<std::uint16_t>(surface::RenderMessageType::focus)) {
      surface::FocusEvent event{};
      return surface::decode_focus_event(payload, event) &&
             static_cast<bool>(runtime_.focus(event));
    }
    if (header.message_type ==
        static_cast<std::uint16_t>(surface::RenderMessageType::input)) {
      surface::InputEvent event{};
      return surface::decode_input_event(payload, event) &&
             static_cast<bool>(runtime_.input(event));
    }
    return false;
  }

private:
  worker::WorkerRuntime &runtime_;
};

class Inspector final : public host::InspectionAuthority {
public:
  bool perform(host::InspectionAction, std::string_view, std::string_view,
               std::string_view) override {
    return true;
  }
};

class Clock final : public host::MonotonicClock {
public:
  [[nodiscard]] std::uint64_t now_nanoseconds() const override { return now; }
  std::uint64_t now = 1'000'000'000ULL;
};

surface::InputEvent pointer(surface::SurfaceKey key, std::uint64_t sequence,
                            surface::ButtonState state) {
  return {.surface = key,
          .sequence = sequence,
          .kind = surface::InputKind::pointer_button,
          .x_q16 = 126U << surface::kQ16FractionBits,
          .y_q16 = 24U << surface::kQ16FractionBits,
          .delta_x_q16 = 0,
          .delta_y_q16 = 0,
          .code = 1,
          .state = static_cast<std::uint32_t>(state),
          .active_touch_points = 0};
}

surface::InputEvent touch(surface::SurfaceKey key, std::uint64_t sequence,
                          std::uint32_t state,
                          std::uint32_t active_touch_points) {
  return {.surface = key,
          .sequence = sequence,
          .kind = surface::InputKind::touch,
          .x_q16 = 126U << surface::kQ16FractionBits,
          .y_q16 = 24U << surface::kQ16FractionBits,
          .delta_x_q16 = 0,
          .delta_y_q16 = 0,
          .code = 1,
          .state = state,
          .active_touch_points = active_touch_points};
}

void negotiate(host::HostSurface &hosted, RenderSender &sender,
               worker::WorkerRuntime &worker_runtime,
               std::uint64_t generation) {
  auto offer_packet = sender.take();
  surface::ProfileOffer offer{};
  require(surface::decode_profile_offer(offer_packet.payload, offer) &&
              static_cast<bool>(worker_runtime.select_software_profile(offer)),
          "worker rejected host software profile");
  const auto selection =
      surface::select_software_profile(std::array{offer.version});
  require(selection.has_value(), "software selection failed");
  const auto selected = surface::encode_profile_selection(*selection);
  require(hosted.receive_render(encode(
              worker_header(static_cast<std::uint16_t>(
                                surface::RenderMessageType::profile_select),
                            selected.size(), generation, 1),
              selected)),
          "host rejected worker profile selection");

  auto allocation_packet = sender.take();
  surface::TrustedAllocation allocation{};
  const long page_size = sysconf(_SC_PAGESIZE);
  require(page_size > 0 && allocation_packet.descriptor >= 0 &&
              surface::decode_surface_allocation(
                  allocation_packet.payload,
                  static_cast<std::uint64_t>(page_size), allocation) &&
              static_cast<bool>(worker_runtime.allocate(
                  allocation, std::exchange(allocation_packet.descriptor, -1))),
          "worker rejected host-owned bar allocation");
  const auto acknowledged = surface::encode_surface_key(allocation.surface);
  require(hosted.receive_render(encode(
              worker_header(static_cast<std::uint16_t>(
                                surface::RenderMessageType::surface_allocated),
                            acknowledged.size(), generation, 2),
              acknowledged)) &&
              hosted.inspection().render_active,
          "bar allocation did not become active");
}

void publish(host::HostSurface &hosted, worker::WorkerRuntime &worker_runtime,
             std::uint64_t generation) {
  const auto frame = worker_runtime.render();
  require(frame.has_value(), "arbitrary QML did not render");
  const auto payload = surface::encode_frame_ready(frame->ready);
  require(hosted.receive_render(
              encode(worker_header(static_cast<std::uint16_t>(
                                       surface::RenderMessageType::frame_ready),
                                   payload.size(), generation),
                     payload)),
          "trusted host rejected arbitrary-QML frame");
}

void prove_ambient_denial_plan() {
  const auto plan = sandbox::build_plan();
  require(
      sandbox::contains_argument_pair(plan, "--ro-bind-fd", "9") &&
          sandbox::contains_argument_pair(plan, "--bind-fd", "10") &&
          std::ranges::find(plan.argv, "--unshare-user") != plan.argv.end() &&
          std::ranges::find(plan.argv, "--unshare-pid") != plan.argv.end() &&
          std::ranges::find(plan.argv, "--unshare-net") != plan.argv.end() &&
          std::ranges::find(plan.argv, "--new-session") != plan.argv.end() &&
          std::ranges::find(plan.argv, "--share-net") == plan.argv.end() &&
          std::ranges::find(plan.worker_environment, "WAYLAND_DISPLAY") ==
              plan.worker_environment.end() &&
          plan.worker_descriptors == std::vector<int>({3, 4, 5}),
      "E1 did not consume the ambient-authority-denying B5 launch plan");
}

void prove_relative_import_escape_denied(const std::filesystem::path &root) {
  const auto plugin = root / "escape-plugin";
  const auto outside = root / "outside";
  std::filesystem::create_directories(plugin);
  std::filesystem::create_directories(outside);
  write_text(outside / "Secret.qml", "import QtQuick\nItem {}\n");
  write_text(plugin / "Main.qml",
             "import QtQuick\nimport \"../outside\"\nItem { Secret {} }\n");
  worker::WorkerRuntime escaped(plugin);
  const auto result = escaped.load_entry("Main.qml");
  require(!result && result.failure == worker::RuntimeFailure::qml_load_failed,
          "relative QML import escaped the immutable plugin root");
}

void embedded_bar_vertical_slice() {
  prove_ambient_denial_plan();
  TemporaryDirectory temporary;
  prove_relative_import_escape_denied(temporary.path());
  audit::AuditStore audit_store(temporary.path() / "audit",
                                {.maximum_records = 128});
  Backend backend;
  backend.audit_store = &audit_store;
  auto active = revision();
  runtime::AuditedBrokerRuntime broker_runtime(
      active, provider_configuration(backend), audit_store);
  AuditedDispatcher dispatcher(broker_runtime, active.binding.generation);
  require(dispatcher.accepts(
              {.plugin_id = std::string(active.binding.plugin.view()),
               .revision_sha256 = kRevision,
               .generation = active.binding.generation}) &&
              !dispatcher.accepts({.plugin_id = "org.omarchy.fixture.pet",
                                   .revision_sha256 = kRevision,
                                   .generation = active.binding.generation}) &&
              !dispatcher.accepts(
                  {.plugin_id = std::string(active.binding.plugin.view()),
                   .revision_sha256 = std::string(64, 'b'),
                   .generation = active.binding.generation}) &&
              !dispatcher.accepts(
                  {.plugin_id = std::string(active.binding.plugin.view()),
                   .revision_sha256 = kRevision,
                   .generation = active.binding.generation + 1}),
          "D1 dispatcher accepted a crossed activation identity");
  BrokerApi api(dispatcher, active.binding.generation);

  worker::WorkerRuntime worker_runtime(kPomodoro);
  AmbientApi ambient_api;
  require(!worker_runtime.bind_runtime_api(ambient_api),
          "worker exposed a runtime QObject with ambient methods");
  require(static_cast<bool>(worker_runtime.bind_runtime_api(api)),
          "trusted runtime API did not bind");
  const auto load_result = worker_runtime.load_manifest_entry();
  require(static_cast<bool>(load_result),
          std::string("Pomodoro QML did not load: ") + load_result.detail);
  require(backend.reads == 1 && backend.last_key == "timer-state" &&
              backend.audit_before_effect,
          "Pomodoro startup storage read did not pass the audited broker");
  require(!worker_runtime.bind_runtime_api(api),
          "plugin runtime API was rebound after QML load");

  const auto parsed =
      manifest::parse_manifest_v2(read_text(kPomodoro / "manifest.json"));
  auto policy = host::parse_named_surface_policy(parsed, "timer");
  RenderSender render_sender;
  auto input_sink = std::make_shared<WorkerInputSink>(worker_runtime);
  Inspector inspector;
  Clock clock;
  bridge::RemotePluginSurface item;
  auto hosted = host::HostSurface::create(policy, active.binding, 171, 252, 48,
                                          1, 1, item, render_sender, input_sink,
                                          inspector, clock);
  require(hosted != nullptr, "host did not assign the named bar envelope");
  negotiate(*hosted, render_sender, worker_runtime, active.binding.generation);
  publish(*hosted, worker_runtime, active.binding.generation);
  const QImage before = item.ownedImage();
  require(item.ready() && before.width() == 252 && before.height() == 48 &&
              hosted->inspection().role == host::SurfaceRole::bar_embedded &&
              hosted->inspection().plugin_id == parsed.id &&
              hosted->inspection().revision_digest == kRevision,
          "host inspection or bar pixels lost trusted identity/geometry");

  const auto key = hosted->allocation().surface;
  require(hosted->route_input(pointer(key, 1, surface::ButtonState::pressed),
                              true) &&
              worker_runtime.focused() &&
              hosted->route_input(
                  pointer(key, 2, surface::ButtonState::released), false) &&
              !worker_runtime.focused() && !hosted->inspection().focused,
          "bar click did not use transient worker focus without shell focus");
  clock.now += 40'000'000ULL;
  publish(*hosted, worker_runtime, active.binding.generation);
  require(item.ownedImage() != before,
          "arbitrary Pomodoro QML did not react and repaint after input");
  require(hosted->route_input(touch(key, 3, 1, 1), true) &&
              worker_runtime.focused() &&
              hosted->route_input(touch(key, 4, 2, 1), false) &&
              hosted->route_input(touch(key, 5, 3, 0), false) &&
              !worker_runtime.focused() && !hosted->inspection().focused,
          "authenticated touch lifecycle lost its trusted synthetic device");

  QVariantMap write_payload;
  write_payload.insert(QStringLiteral("key"), QStringLiteral("timer-state"));
  write_payload.insert(QStringLiteral("value"),
                       QStringLiteral("{\"completedSessions\":1}"));
  QVariant wrote;
  require(
      QMetaObject::invokeMethod(&api, "invoke", Q_RETURN_ARG(QVariant, wrote),
                                Q_ARG(QString, QStringLiteral("storage_write")),
                                Q_ARG(QVariantMap, write_payload)) &&
          wrote.toBool() && backend.writes == 1 &&
          backend.last_key == "timer-state" && backend.audit_before_effect,
      "named storage write did not pass D1 dispatcher/D4 audit authority");

  const QVariant denied_notification =
      api.invoke(QStringLiteral("notification_send"),
                 {{QStringLiteral("title"), QStringLiteral("done")},
                  {QStringLiteral("body"), QStringLiteral("break")}});
  const QVariant denied_audio =
      api.invoke(QStringLiteral("audio_play_cue"),
                 {{QStringLiteral("cue"), QStringLiteral("timer-complete")}});
  const auto calls_before_unknown = dispatcher.calls;
  const QVariant denied_unknown = api.invoke(
      QStringLiteral("open_uri"),
      {{QStringLiteral("url"), QStringLiteral("https://example.invalid")}});
  require(!denied_notification.toBool() && !denied_audio.toBool() &&
              !denied_unknown.toBool() && backend.notifications == 0 &&
              backend.audio_cues == 0 && api.unknown_denials == 1 &&
              dispatcher.calls == calls_before_unknown &&
              !broker_runtime.failed(),
          "ungranted or unknown effects escaped the broker-only API");

  std::string exported;
  require(audit_store.export_tsv({}, exported).ok() &&
              exported.find("completedSessions") == std::string::npos &&
              exported.find("timer-state") == std::string::npos &&
              dispatcher.calls == 4,
          "authoritative E1 audit leaked plugin payload or missed decisions");
  hosted->close();
  auto release_packet = render_sender.take();
  surface::SurfaceKey released{};
  require(!item.connected() && !item.ready() &&
              release_packet.header.message_type ==
                  static_cast<std::uint16_t>(
                      surface::RenderMessageType::surface_release) &&
              surface::decode_surface_key(release_packet.payload, released) &&
              released == key &&
              static_cast<bool>(worker_runtime.release(released)) &&
              !worker_runtime.allocated() && !worker_runtime.active() &&
              !worker_runtime.focused() && !worker_runtime.render().has_value(),
          "bar teardown retained worker pixels, mapping, or input authority");
}

} // namespace

int main(int argc, char **argv) {
  try {
    QGuiApplication application(argc, argv);
    embedded_bar_vertical_slice();
    return 0;
  } catch (const std::exception &error) {
    std::cerr << "embedded bar slice failed: " << error.what() << '\n';
    return 1;
  }
}

#include "embedded_bar_test.moc"
