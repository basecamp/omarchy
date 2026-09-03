#include "qml_broker_api.hpp"
#include "worker_runtime.hpp"

#include "omarchy/plugin/wire/common.hpp"
#include "omarchy/plugin_runtime/broker/broker_codec.hpp"
#include "omarchy/plugin_runtime/broker/broker_schema.hpp"

#include <fcntl.h>
#include <QGuiApplication>
#include <QEventLoop>
#include <QFile>
#include <QQmlComponent>
#include <QQmlContext>
#include <QQmlEngine>
#include <QJsonArray>
#include <QJsonObject>
#include <QTimer>
#include <QTemporaryDir>
#include <sys/mman.h>
#include <sys/socket.h>
#include <sys/syscall.h>
#include <unistd.h>

#include <array>
#include <algorithm>
#include <cerrno>
#include <filesystem>
#include <iostream>
#include <span>
#include <stdexcept>
#include <string>
#include <vector>

namespace {
namespace broker = omarchy::plugin_runtime::broker;
namespace definitions = omarchy::plugins::definitions;
namespace manifest = omarchy::plugins::manifest;
namespace permissions = omarchy::plugins::permissions;
namespace surface = omarchy::plugin_runtime::surface;
namespace worker = omarchy::plugin_runtime::worker;
namespace wire = omarchy::plugin::wire;

class DuplicateApiBase : public QObject {
  Q_OBJECT
public:
  Q_INVOKABLE QVariant invoke(const QString &, const QString &,
                              const QVariantMap &) { return {}; }
};
class DuplicateApi final : public DuplicateApiBase {
  Q_OBJECT
public:
  Q_INVOKABLE QVariant invoke(const QString &, const QString &,
                              const QVariantMap &) { return {}; }
};
class WrongParameterApi final : public QObject {
  Q_OBJECT
public:
  Q_INVOKABLE QVariant invoke(const QString &, const QString &,
                              const QVariant &) { return {}; }
};

class IntentSink final : public worker::SurfaceIntentSink {
public:
  bool request_surface_intent(
      std::optional<definitions::DynamicInvocation::GestureClaim> source,
      std::string_view target,
      surface::SurfaceIntentAction action, const QVariantMap &data) override {
    ++calls;
    last_source = source;
    last_target = target;
    last_action = action;
    last_data = data;
    return accept && target == declared_target;
  }

  int calls = 0;
  bool accept = true;
  std::string declared_target = "PanelWidget";
  std::optional<definitions::DynamicInvocation::GestureClaim> last_source;
  std::string last_target;
  surface::SurfaceIntentAction last_action = surface::SurfaceIntentAction::open;
  QVariantMap last_data;
};

class FixtureIntentSink final : public worker::SurfaceIntentSink {
public:
  bool request_surface_intent(
      std::optional<definitions::DynamicInvocation::GestureClaim> source,
      std::string_view target,
      surface::SurfaceIntentAction action, const QVariantMap &) override {
    sources.push_back(source);
    targets.emplace_back(target);
    actions.push_back(action);
    return (target == "panel" || target == "overlay") &&
           action == surface::SurfaceIntentAction::toggle;
  }

  std::vector<std::optional<definitions::DynamicInvocation::GestureClaim>>
      sources;
  std::vector<std::string> targets;
  std::vector<surface::SurfaceIntentAction> actions;
};

void require(bool condition, const char *message) {
  if (!condition) throw std::runtime_error(message);
}

void drain_events() {
  for (int pass = 0; pass < 3; ++pass)
    QCoreApplication::processEvents();
}
struct Pair {
  std::array<int, 2> descriptors{-1, -1};
  Pair() { require(socketpair(AF_UNIX, SOCK_SEQPACKET | SOCK_CLOEXEC, 0,
                             descriptors.data()) == 0, "socketpair failed"); }
  ~Pair() { close(descriptors[0]); close(descriptors[1]); }
};
bool send_packet(int fd, wire::EnvelopeHeader header,
                 std::span<const std::byte> payload) {
  header.payload_length = static_cast<std::uint32_t>(payload.size());
  std::vector<std::byte> packet(wire::kHeaderSize + payload.size());
  const auto encoded = wire::encode_packet(header, payload, packet);
  return encoded && send(fd, packet.data(), encoded.bytes_written, MSG_NOSIGNAL) ==
                        static_cast<ssize_t>(encoded.bytes_written);
}
void handshake(worker::WorkerEndpoint &endpoint, int host) {
  if (!endpoint.valid() || !endpoint.send_hello())
    throw std::runtime_error("HELLO failed: " + endpoint.last_error());
  std::array<std::byte, wire::kHeaderSize + 4> hello{};
  require(recv(host, hello.data(), hello.size(), 0) ==
              static_cast<ssize_t>(hello.size()), "HELLO receive failed");
  const auto welcome = wire::encode_welcome_payload(
      {.maximum_payload = wire::payload_cap(wire::EndpointRole::broker),
       .maximum_in_flight = 32});
  require(send_packet(host,
      {.endpoint_role = wire::EndpointRole::broker,
       .message_type = static_cast<std::uint16_t>(wire::CommonMessageType::welcome),
       .role_protocol_version = broker::kBrokerRoleVersion,
       .launch_generation = 77}, welcome), "WELCOME send failed");
  auto packet = endpoint.receive();
  require(packet && endpoint.accept_welcome(packet), "WELCOME rejected");
}
std::vector<std::byte> receive_packet(int fd) {
  std::vector<std::byte> packet(wire::kHeaderSize +
      wire::payload_cap(wire::EndpointRole::broker));
  const auto bytes = recv(fd, packet.data(), packet.size(), 0);
  require(bytes > 0, "broker request receive failed");
  packet.resize(static_cast<std::size_t>(bytes));
  return packet;
}
void finish(worker::QmlBrokerApi &api, worker::WorkerEndpoint &endpoint,
            int host, wire::SessionSequence &host_sequence,
            std::uint64_t correlation, std::uint16_t type,
            std::span<const std::byte> payload) {
  const auto sequence =
      host_sequence.take_outbound(wire::EndpointRole::broker);
  require(static_cast<bool>(sequence), "host sequence exhausted");
  require(send_packet(host,
      {.endpoint_role = wire::EndpointRole::broker,
       .message_type = type,
       .role_protocol_version = broker::kBrokerRoleVersion,
       .launch_generation = 77,
       .correlation_id = correlation,
       .lane_sequence = sequence.value}, payload), "terminal send failed");
  require(api.receive(endpoint.receive()), "terminal response rejected");
}
definitions::Digest repeated(char value) {
  return definitions::Digest(std::string(64, value));
}
definitions::DynamicScopeRelation exact_scope(
    const definitions::CapabilityDefinition &, std::string_view candidate,
    std::string_view baseline, void *) noexcept {
  return candidate == baseline ? definitions::DynamicScopeRelation::equal
                               : definitions::DynamicScopeRelation::incomparable;
}
bool fake_dynamic_dispatch(const definitions::AuthorizedDynamicRequest &request,
                           std::span<std::byte> response,
                           std::size_t &written, void *context) noexcept {
  auto &calls = *static_cast<int *>(context);
  if (request.operation != "read" ||
      request.demand_scope != "{\"dataset\":\"status\"}" ||
      request.payload.empty() || response.empty() ||
      request.authorization.binding.plugin.view() != "org.example.dynamic" ||
      request.authorization.definition.canonical_name.view() !=
          "service.status" ||
      request.authorization.grant_epoch != 1)
    return false;
  ++calls;
  response[0] = std::byte{0x2a};
  written = 1;
  return true;
}

void capability_qualified_collision() {
  const std::string alpha_digest(64, 'a');
  const std::string beta_digest(64, 'b');
  const std::string document =
      "{\"schemaVersion\":2,\"id\":\"org.example.collision\","
      "\"name\":\"Collision\",\"version\":\"1\",\"runtime\":{"
      "\"apiVersion\":1,\"qml\":\"Main.qml\"},\"surfaces\":{},"
      "\"permissions\":{\"required\":[{\"capability\":\"service.alpha\","
      "\"definitionGeneration\":3,\"definitionDigest\":\"" + alpha_digest +
      "\",\"operations\":[\"read\",\"control\"],\"reason\":\"alpha\"},{"
      "\"capability\":\"service.beta\",\"definitionGeneration\":7,"
      "\"definitionDigest\":\"" + beta_digest +
      "\",\"operations\":[\"read\",\"control\"],\"reason\":\"beta\"}],"
      "\"optional\":[]}}";
  const auto parsed = manifest::parse_manifest_v2(document);
  worker::ManifestInvokeEncoder encoder(parsed);
  const QVariantMap arguments{
      {QStringLiteral("demandScope"), QStringLiteral("{}")},
      {QStringLiteral("payload"),
       QVariantMap{{QStringLiteral("resource"), 7}}}};

  const auto alpha_read = encoder.encode("service.alpha", "read", arguments);
  const auto beta_read = encoder.encode("service.beta", "read", arguments);
  const auto beta_control =
      encoder.encode("service.beta", "control", arguments);
  definitions::DynamicInvocation alpha_invocation;
  definitions::DynamicInvocation beta_read_invocation;
  definitions::DynamicInvocation beta_control_invocation;
  require(alpha_read && beta_read && beta_control &&
              definitions::decode_dynamic_invocation(alpha_read->payload,
                                                     alpha_invocation) &&
              definitions::decode_dynamic_invocation(beta_read->payload,
                                                     beta_read_invocation) &&
              definitions::decode_dynamic_invocation(beta_control->payload,
                                                     beta_control_invocation) &&
              alpha_invocation.definition.canonical_name.view() ==
                  "service.alpha" &&
              alpha_invocation.definition.definition_generation == 3 &&
              alpha_invocation.definition.definition_digest.view() ==
                  alpha_digest &&
              alpha_invocation.operation.view() == "read" &&
              beta_read_invocation.definition.canonical_name.view() ==
                  "service.beta" &&
              beta_read_invocation.definition.definition_generation == 7 &&
              beta_read_invocation.definition.definition_digest.view() ==
                  beta_digest &&
              beta_read_invocation.operation.view() == "read" &&
              beta_control_invocation.definition ==
                  beta_read_invocation.definition &&
              beta_control_invocation.operation.view() == "control",
          "shared operation names did not retain their exact capability and "
          "definition bindings");
  require(!encoder.encode("service.old-alpha", "read", arguments) &&
              !encoder.encode("service.alpha", "delete", arguments) &&
              !encoder.encode("storage.private", "read", arguments),
          "an undeclared capability or operation reached encoding");

  auto duplicate_capability = parsed;
  duplicate_capability.requests.push_back(parsed.requests.front());
  worker::ManifestInvokeEncoder duplicate_encoder(duplicate_capability);
  require(!duplicate_encoder.encode("service.alpha", "read", arguments),
          "duplicate capability rows retained an ambiguous binding");
  auto duplicate_operation = parsed;
  duplicate_operation.requests.front().operations.push_back("read");
  worker::ManifestInvokeEncoder duplicate_operation_encoder(
      duplicate_operation);
  require(!duplicate_operation_encoder.encode("service.alpha", "read",
                                               arguments),
          "duplicate operation rows retained an ambiguous binding");
  auto malformed_reference = parsed;
  malformed_reference.requests.front().definition_digest =
      std::string(64, 'A');
  worker::ManifestInvokeEncoder malformed_encoder(malformed_reference);
  require(!malformed_encoder.encode("service.alpha", "read", arguments),
          "a malformed definition reference reached encoding");

  const std::string overlong_name(129, 'a');
  auto overlong_capability = parsed;
  overlong_capability.requests.front().capability = overlong_name;
  worker::ManifestInvokeEncoder overlong_capability_encoder(
      overlong_capability);
  require(!overlong_capability_encoder.encode(overlong_name, "read",
                                              arguments) &&
              !overlong_capability_encoder.encode("service.beta", "read",
                                                  arguments),
          "an overlong capability retained an encodable transport binding");

  auto overlong_operation = parsed;
  overlong_operation.requests.front().operations.front() = overlong_name;
  worker::ManifestInvokeEncoder overlong_operation_encoder(overlong_operation);
  require(!overlong_operation_encoder.encode("service.alpha", overlong_name,
                                             arguments) &&
              !overlong_operation_encoder.encode("service.beta", "read",
                                                 arguments),
          "an overlong operation retained an encodable transport binding");
}

void dynamic_qml_to_adapter() {
  definitions::CapabilityDefinition definition{
      .canonical_name = definitions::Name("service.status"),
      .authority_identity = definitions::Name("service.status-v1"),
      .enforcement_family = definitions::EnforcementFamily::network_fetch,
      .display_category_id = definitions::Name("services"),
      .display_category_label = definitions::Label("Services"),
      .scope_schema = definitions::ScopeSchema::https_origins_and_methods,
      .title = definitions::Label("Read selected status"),
      .risk_text = definitions::Label("Reads one selected bounded dataset"),
      .risk = definitions::RiskLevel::moderate,
      .revocation = definitions::RevocationPolicy::cancel_inflight,
      .audit = {},
      .adapter = {.adapter_class = definitions::Name("status-adapter"),
                  .contract_digest = repeated('a'),
                  .abi_version = 1},
      .operations = {}};
  definition.operations.insert(
      {.name = definitions::Name("read"),
       .label = definitions::Label("Read status")});
  definitions::TrustedDefinitionRegistry registry;
  require(registry.install(definition,
                           definitions::DefinitionSource::local_admin, 3),
          "dynamic definition install failed");
  const auto resolved = registry.find("service.status");
  require(resolved.has_value(), "dynamic definition resolution failed");
  const std::string document =
      "{\"schemaVersion\":2,\"id\":\"org.example.dynamic\",\"name\":\"Dynamic\","
      "\"version\":\"1\",\"runtime\":{\"apiVersion\":1,\"qml\":\"Main.qml\"},"
      "\"surfaces\":{},\"permissions\":{\"required\":[{\"capability\":"
      "\"service.status\",\"definitionGeneration\":3,\"definitionDigest\":\"" +
      std::string(resolved->digest.view()) +
      "\",\"operations\":[\"read\"],\"dataset\":\"status\",\"reason\":\"test\"}],"
      "\"optional\":[]}}";
  const auto parsed = manifest::parse_manifest_v2(document);
  worker::ManifestInvokeEncoder encoder(parsed);
  const auto encoded = encoder.encode(
      "service.status", "read", {{QStringLiteral("demandScope"),
                 QStringLiteral("{\"dataset\":\"status\"}")},
                {QStringLiteral("payload"),
                 QVariantMap{{QStringLiteral("resource"), 7}}}});
  require(encoded && encoded->message_type == broker::kDynamicInvokeMessage,
          "QML dynamic call did not become a bounded broker envelope");

  definitions::DynamicRevisionGrant revision{
      .binding = {.plugin = permissions::PluginId("org.example.dynamic"),
                  .revision = repeated('b'),
                  .policy_fingerprint = repeated('c'),
                  .generation = 5},
      .request = {.definition = {.canonical_name =
                                      definitions::Name("service.status"),
                                  .definition_generation = 3,
                                  .definition_digest = resolved->digest},
                  .operations = {},
                  .scope = definitions::CanonicalScope(
                      "{\"dataset\":\"status\"}"),
                  .required = true},
      .grant = {.definition = {.canonical_name =
                                    definitions::Name("service.status"),
                                .definition_generation = 3,
                                .definition_digest = resolved->digest},
                .operations = {},
                .scope = definitions::CanonicalScope(
                    "{\"dataset\":\"status\"}"),
                .state = permissions::GrantState::granted,
                .epoch = 1}};
  revision.request.operations.insert(definitions::Name("read"));
  revision.grant.operations.insert(definitions::Name("read"));
  int calls = 0;
  definitions::DynamicAdapter adapter{
      .binding = definition.adapter,
      .dispatch = fake_dynamic_dispatch,
      .context = &calls};
  const definitions::DynamicScopeValidator scopes{.compare = exact_scope};
  std::array<std::byte, 8> response{};
  std::size_t written = 0;
  definitions::DynamicDecision decision{};
  require(definitions::dispatch_dynamic_invocation(
              registry, revision, revision.binding, encoded->payload, adapter,
              scopes, false, response, written, decision) ==
              definitions::DynamicDispatchResult::dispatched &&
              calls == 1 && written == 1,
          "QML dynamic envelope did not pass broker authorization and adapter verification");
}

void structured_command_execution() {
  Pair pair;
  wire::SessionSequence worker_sequence;
  wire::SessionSequence host_sequence;
  worker::WorkerEndpoint endpoint(pair.descriptors[0],
                                  wire::EndpointRole::broker,
                                  broker::kBrokerRoleVersion, worker_sequence);
  handshake(endpoint, pair.descriptors[1]);
  const std::string digest(64, 'd');
  const auto parsed = manifest::parse_manifest_v2(
      "{\"schemaVersion\":2,\"id\":\"org.example.command\","
      "\"name\":\"Command\",\"version\":\"1\",\"runtime\":{"
      "\"apiVersion\":1,\"qml\":\"Main.qml\"},\"surfaces\":{},"
      "\"permissions\":{\"required\":[{\"capability\":\"bash.execute\","
      "\"definitionGeneration\":1,\"definitionDigest\":\"" + digest +
      "\",\"operations\":[\"run\"],\"profile\":\"github-api-v1\","
      "\"reason\":\"Read GitHub data\"}],\"optional\":[]}}");
  worker::QmlBrokerApi api(
      endpoint, std::make_unique<worker::ManifestInvokeEncoder>(parsed),
      parsed, 77);
  const auto snapshot = wire::permission_snapshot::encode({
      .manifest_request_fingerprint =
          manifest::requested_capability_fingerprint(parsed.requests),
      .permissions = {
          {wire::permission_snapshot::GrantState::granted, 0x0001}}});
  require(api.applyPermissionSnapshot(77, snapshot) && api.markBrokerReady(),
          "command fixture did not become broker-ready");

  auto *generic = qobject_cast<worker::BrokerCall *>(
      api.invoke(QStringLiteral("bash.execute"), QStringLiteral("run"),
                 {{QStringLiteral("demandScope"),
                   QStringLiteral("{\"profile\":\"github-api-v1\"}")},
                  {QStringLiteral("payload"),
                   QVariantMap{{QStringLiteral("command"),
                                QStringLiteral("gh")}}}})
          .value<QObject *>());
  require(generic != nullptr && generic->finished() && !generic->ok() &&
              generic->correlation() == 0,
          "generic invoke bypassed the structured command API");

  auto *call = qobject_cast<worker::BrokerCall *>(
      api.execute(QStringLiteral("bash"), QStringLiteral("gh"),
                  {QStringLiteral("api"), QStringLiteral("/notifications")})
          .value<QObject *>());
  require(call != nullptr && !call->finished() && call->correlation() != 0,
          "structured command did not become an asynchronous broker call");
  const auto packet_bytes = receive_packet(pair.descriptors[1]);
  const auto packet =
      wire::decode_packet(packet_bytes, wire::EndpointRole::broker);
  definitions::DynamicInvocation invocation;
  require(packet && packet.packet.header.message_type ==
                        broker::kDynamicInvokeMessage &&
              definitions::decode_dynamic_invocation(packet.packet.payload,
                                                     invocation) &&
              invocation.definition.canonical_name.view() == "bash.execute" &&
              invocation.operation.view() == "run" &&
              invocation.demand_scope.view() ==
                  "{\"profile\":\"github-api-v1\"}",
          "structured command lost its exact manifest profile");
  const QByteArray payload(reinterpret_cast<const char *>(invocation.payload.data()),
                           static_cast<qsizetype>(invocation.payload.size()));
  const auto object = QJsonDocument::fromJson(payload).object();
  require(object.value(QStringLiteral("command")).toString() ==
                  QStringLiteral("gh") &&
              object.value(QStringLiteral("arguments")).toArray().size() == 2 &&
              object.value(QStringLiteral("arguments")).toArray().at(0).toString() ==
                  QStringLiteral("api"),
          "structured command did not preserve its argv vector");

  const auto rejected = [&](const QString &runner, const QString &command,
                            const QStringList &arguments) {
    auto *candidate = qobject_cast<worker::BrokerCall *>(
        api.execute(runner, command, arguments).value<QObject *>());
    return candidate != nullptr && candidate->finished() && !candidate->ok() &&
           candidate->correlation() == 0;
  };
  require(rejected(QStringLiteral("shell"), QStringLiteral("gh"), {}) &&
              rejected(QStringLiteral("bash"), QStringLiteral("bash"),
                       {QStringLiteral("-c"), QStringLiteral("gh api user")}) &&
              rejected(QStringLiteral("bash"), QStringLiteral("../gh"), {}),
          "structured command accepted a shell or path escape");

  const std::string result =
      R"({"exitCode":0,"stdout":"{}","stderr":""})";
  finish(api, endpoint, pair.descriptors[1], host_sequence,
         call->correlation(), broker::kBrokerResultMessage,
         std::as_bytes(std::span(result)));
  require(call->finished() && call->ok(),
          "structured command result did not settle");
}
void permission_awareness(worker::WorkerEndpoint &endpoint, int host,
                          wire::SessionSequence &host_sequence) {
  const std::string document =
      R"({"schemaVersion":2,"id":"org.example.widget","name":"Widget","version":"1","runtime":{"apiVersion":1,"qml":"Main.qml"},"surfaces":{},"settings":{"defaults":{"enabled":true,"mode":"compact"},"schema":[{"key":"enabled","type":"boolean","label":"Enabled","defaultValue":true},{"key":"mode","type":"enum","label":"Mode","options":["compact","full"],"defaultValue":"compact"}]},"permissions":{"required":[{"capability":"storage.private","reason":"save","quotaBytes":1024}],"optional":[{"capability":"notifications.send","reason":"alerts","categories":["status"]}]}})";
  const auto parsed = manifest::parse_manifest_v2(document);
  worker::QmlBrokerApi api(
      endpoint, std::make_unique<worker::ManifestInvokeEncoder>(parsed),
      parsed, 77);
  QTemporaryDir packaged_assets;
  require(packaged_assets.isValid(), "packaged asset fixture failed");
  QFile asset(packaged_assets.filePath("countries.json"));
  require(asset.open(QIODevice::WriteOnly) &&
              asset.write("{\"country\":\"Japan\"}") == 19,
          "packaged asset fixture write failed");
  asset.close();
  api.setPackagedAssetRoot(packaged_assets.path().toStdString());
  require(api.readPackagedText("countries.json", 128) ==
              QStringLiteral("{\"country\":\"Japan\"}") &&
              api.readPackagedText("../countries.json", 128).isEmpty() &&
              api.readPackagedText("countries.json", 8).isEmpty() &&
              api.readPackagedText("/etc/passwd", 512 * 1024).isEmpty(),
          "packaged text projection escaped its bounded read-only contract");
  worker::WorkerRuntime runtime_binding_probe("/not-loaded-in-this-test");
  require(static_cast<bool>(runtime_binding_probe.bind_runtime_api(api)),
          "runtime permission-aware API failed the exact trusted-surface validator");
  DuplicateApi duplicate;
  worker::WorkerRuntime duplicate_probe("/not-loaded-in-this-test");
  require(!static_cast<bool>(duplicate_probe.bind_runtime_api(duplicate)),
          "duplicate trusted API method signatures passed validation");
  WrongParameterApi wrong_parameters;
  worker::WorkerRuntime parameter_probe("/not-loaded-in-this-test");
  require(!static_cast<bool>(parameter_probe.bind_runtime_api(wrong_parameters)),
          "trusted API validation ignored exact parameter types");
  require(api.permissionState("storage.private", "read") == "unavailable" &&
              !api.hasPermission("notifications.send", "send"),
          "permissions became available before a host snapshot");
  const auto settings_document =
      manifest::canonical_settings_entry(parsed.settings.defaults);
  const auto settings_bytes = std::as_bytes(std::span(settings_document));
  require(api.applySettingsSnapshot(77, settings_bytes),
          "host settings snapshot was rejected");
  require(api.settings().value(QStringLiteral("id")).toString() ==
              QStringLiteral("org.example.widget"),
          "settings projection lost the plugin identity");
  require(api.settings().value(QStringLiteral("enabled")).toBool(),
          "settings projection lost the boolean value");
  require(api.settings().value(QStringLiteral("mode")).toString() ==
              QStringLiteral("compact"),
          "settings projection lost the enum value");
  require(!api.applySettingsSnapshot(77, settings_bytes) &&
              !api.applySettingsSnapshot(78, settings_bytes),
          "duplicate or wrong-generation settings snapshot was accepted");
  const auto payload = wire::permission_snapshot::encode({
      .manifest_request_fingerprint =
          manifest::requested_capability_fingerprint(parsed.requests),
      // Canonical manifest tuple order is notifications.send, storage.private.
      .permissions = {
          {wire::permission_snapshot::GrantState::granted, 0x0001},
          {wire::permission_snapshot::GrantState::granted, 0x0007}}});
  require(api.applyPermissionSnapshot(77, payload),
          "initial host permission snapshot was rejected");
  require(api.hasPermission("storage.private", "read") &&
              api.hasPermission("notifications.send", "send") &&
              api.permissionState("notifications.send", "send") == "granted" &&
              api.permissions()
                      .value(QStringLiteral("notifications.send"))
                      .toMap()
                      .value(QStringLiteral("state")) ==
                  QStringLiteral("granted") &&
              api.permissions()
                      .value(QStringLiteral("notifications.send"))
                      .toMap()
                      .value(QStringLiteral("operations"))
                      .toMap()
                      .value(QStringLiteral("send")) ==
                  QStringLiteral("granted"),
          "manifest-indexed grants were not represented");
  const auto before = api.permissions();
  require(!api.applyPermissionSnapshot(77, payload) &&
              api.permissions() == before,
          "a duplicate same-generation snapshot mutated immutable QML state");
  require(!api.brokerReady() && api.markBrokerReady() && api.brokerReady(),
          "broker readiness did not follow the accepted permission snapshot");

  const auto fresh_api = [&] {
    return std::make_unique<worker::QmlBrokerApi>(
        endpoint, std::make_unique<worker::ManifestInvokeEncoder>(parsed),
        parsed, 77);
  };
  {
    auto reordered = parsed;
    std::ranges::reverse(reordered.requests);
    worker::QmlBrokerApi candidate(
        endpoint, std::make_unique<worker::ManifestInvokeEncoder>(reordered),
        reordered, 77);
    require(candidate.applyPermissionSnapshot(77, payload) &&
                candidate.hasPermission("notifications.send", "send") &&
                candidate.hasPermission("storage.private", "write"),
            "worker manifest order did not reproduce canonical indices");
  }
  {
    auto candidate = fresh_api();
    auto excess = payload;
    excess[69] = std::byte{0};
    excess[70] = std::byte{2};
    require(!candidate->applyPermissionSnapshot(77, excess) &&
                candidate->applyPermissionSnapshot(77, payload),
            "operation mask bits beyond the exact manifest row were accepted");
  }
  {
    auto candidate = fresh_api();
    auto empty_granted = payload;
    empty_granted[69] = std::byte{0};
    empty_granted[70] = std::byte{0};
    require(!candidate->applyPermissionSnapshot(77, empty_granted) &&
                candidate->applyPermissionSnapshot(77, payload),
            "empty granted wire row reached QML projection");
  }
  {
    auto candidate = fresh_api();
    const auto denied_with_bits = wire::permission_snapshot::encode({
        .manifest_request_fingerprint =
            manifest::requested_capability_fingerprint(parsed.requests),
        .permissions = {
            {wire::permission_snapshot::GrantState::denied, 0x0001},
            {wire::permission_snapshot::GrantState::granted, 0x0007}}});
    require(!candidate->applyPermissionSnapshot(77, denied_with_bits) &&
                candidate->applyPermissionSnapshot(77, payload),
            "denied permission row retained an operation mask");
  }
  {
    auto candidate = fresh_api();
    auto wrong = payload;
    wrong[2] = static_cast<std::byte>(
        wrong[2] == std::byte{'0'} ? '1' : '0');
    require(!candidate->applyPermissionSnapshot(77, wrong) &&
                candidate->permissionState("storage.private", "read") ==
                    "unavailable" &&
                candidate->applyPermissionSnapshot(77, payload),
            "fingerprint mismatch was not rejected transactionally");
  }
  {
    auto candidate = fresh_api();
    auto wrong = payload;
    wrong.pop_back();
    require(!candidate->applyPermissionSnapshot(77, wrong) &&
                candidate->applyPermissionSnapshot(77, payload),
            "request-count mismatch was not rejected transactionally");
  }
  {
    auto candidate = fresh_api();
    require(!candidate->applyPermissionSnapshot(78, payload) &&
                candidate->applyPermissionSnapshot(77, payload),
            "wrong activation generation was not rejected transactionally");
  }
  {
    auto candidate = fresh_api();
    const auto required_denied = wire::permission_snapshot::encode({
        .manifest_request_fingerprint =
            manifest::requested_capability_fingerprint(parsed.requests),
        .permissions = {
            {wire::permission_snapshot::GrantState::granted, 0x0001},
            {wire::permission_snapshot::GrantState::denied, 0x0000}}});
    require(!candidate->applyPermissionSnapshot(77, required_denied) &&
                candidate->permissionState("storage.private", "read") ==
                    "unavailable" &&
                candidate->applyPermissionSnapshot(77, payload),
            "denied required request was not rejected transactionally");
  }
  {
    auto candidate = fresh_api();
    const auto revoked = wire::permission_snapshot::encode({
        .manifest_request_fingerprint =
            manifest::requested_capability_fingerprint(parsed.requests),
        .permissions = {
            {wire::permission_snapshot::GrantState::revoked, 0x0001},
            {wire::permission_snapshot::GrantState::granted, 0x0007}}});
    require(candidate->applyPermissionSnapshot(77, revoked) &&
                !candidate->hasPermission("notifications.send", "send") &&
                candidate->permissionState("notifications.send", "send") ==
                    "revoked",
            "revoked optional request was not exposed exactly");
  }
  {
    auto candidate = fresh_api();
    auto empty_revoked = wire::permission_snapshot::encode({
        .manifest_request_fingerprint =
            manifest::requested_capability_fingerprint(parsed.requests),
        .permissions = {
            {wire::permission_snapshot::GrantState::revoked, 0x0001},
            {wire::permission_snapshot::GrantState::granted, 0x0007}}});
    empty_revoked[69] = std::byte{0};
    empty_revoked[70] = std::byte{0};
    require(!candidate->applyPermissionSnapshot(77, empty_revoked) &&
                candidate->applyPermissionSnapshot(77, payload),
            "empty revoked wire row reached QML projection");
  }
  {
    manifest::ManifestV2 sixteen;
    sixteen.id = "org.example.sixteen";
    manifest::CapabilityRequest request{
        .capability = "org.example.sixteen-operations",
        .reason = "exercise the complete operation mask",
        .canonical_scope = "{}",
        .definition_generation = 1,
        .definition_digest = std::string(64, 'c'),
        .operations = {},
        .required = false};
    for (int index = 0; index < 16; ++index) {
      request.operations.push_back(
          std::string(index < 10 ? "op-0" : "op-") +
          std::to_string(index));
    }
    sixteen.requests.push_back(request);
    const auto fingerprint =
        manifest::requested_capability_fingerprint(sixteen.requests);
    worker::QmlBrokerApi high_bit(
        endpoint, std::make_unique<worker::ManifestInvokeEncoder>(sixteen),
        sixteen, 77);
    const auto high_bit_payload = wire::permission_snapshot::encode({
        .manifest_request_fingerprint = fingerprint,
        .permissions = {
            {wire::permission_snapshot::GrantState::granted, 0x8000}}});
    require(high_bit.applyPermissionSnapshot(77, high_bit_payload) &&
                high_bit.permissionState(
                    "org.example.sixteen-operations", "op-15") == "granted" &&
                high_bit.permissionState(
                    "org.example.sixteen-operations", "op-14") == "denied" &&
                high_bit.permissions()
                        .value(QStringLiteral(
                            "org.example.sixteen-operations"))
                        .toMap()
                        .value(QStringLiteral("state")) ==
                    QStringLiteral("partial"),
            "worker did not map bit 15 to canonical operation index 15");

    worker::QmlBrokerApi full(
        endpoint, std::make_unique<worker::ManifestInvokeEncoder>(sixteen),
        sixteen, 77);
    const auto full_payload = wire::permission_snapshot::encode({
        .manifest_request_fingerprint = fingerprint,
        .permissions = {
            {wire::permission_snapshot::GrantState::granted, 0xffff}}});
    require(full.applyPermissionSnapshot(77, full_payload) &&
                full.hasPermission("org.example.sixteen-operations", "op-00") &&
                full.hasPermission("org.example.sixteen-operations", "op-15"),
            "worker rejected the complete 16-operation mask");

    sixteen.requests.front().operations.pop_back();
    worker::QmlBrokerApi fifteen(
        endpoint, std::make_unique<worker::ManifestInvokeEncoder>(sixteen),
        sixteen, 77);
    const auto excess_payload = wire::permission_snapshot::encode({
        .manifest_request_fingerprint =
            manifest::requested_capability_fingerprint(sixteen.requests),
        .permissions = {
            {wire::permission_snapshot::GrantState::granted, 0x8000}}});
    require(!fifteen.applyPermissionSnapshot(77, excess_payload),
            "worker accepted bit 15 for a 15-operation manifest row");
  }
  {
    manifest::ManifestV2 colliding;
    colliding.id = "org.example.colliding";
    colliding.requests.push_back(
        {.capability = "org.example.reserved-operations",
         .reason = "prove structural namespacing",
         .canonical_scope = "{}",
         .definition_generation = 1,
         .definition_digest = std::string(64, 'b'),
         .operations = {"required", "state"},
         .required = false});
    worker::QmlBrokerApi candidate(
        endpoint, std::make_unique<worker::ManifestInvokeEncoder>(colliding),
        colliding, 77);
    const auto collision_payload = wire::permission_snapshot::encode({
        .manifest_request_fingerprint =
            manifest::requested_capability_fingerprint(colliding.requests),
        .permissions = {
            {wire::permission_snapshot::GrantState::granted, 0x0001}}});
    require(candidate.applyPermissionSnapshot(77, collision_payload),
            "reserved-name operation projection was rejected");
    const auto capability =
        candidate.permissions()
            .value(QStringLiteral("org.example.reserved-operations"))
            .toMap();
    const auto operations =
        capability.value(QStringLiteral("operations")).toMap();
    require(!capability.value(QStringLiteral("required")).toBool() &&
                capability.value(QStringLiteral("state")).toString() ==
                    QStringLiteral("partial") &&
                operations.value(QStringLiteral("required")).toString() ==
                    QStringLiteral("granted") &&
                operations.value(QStringLiteral("state")).toString() ==
                    QStringLiteral("denied") &&
                candidate.hasPermission("org.example.reserved-operations",
                                        "required") &&
                !candidate.hasPermission("org.example.reserved-operations",
                                         "state"),
            "partial optional operations collided with permission metadata");

    colliding.requests.front().required = true;
    worker::QmlBrokerApi required_candidate(
        endpoint, std::make_unique<worker::ManifestInvokeEncoder>(colliding),
        colliding, 77);
    const auto required_partial = wire::permission_snapshot::encode({
        .manifest_request_fingerprint =
            manifest::requested_capability_fingerprint(colliding.requests),
        .permissions = {
            {wire::permission_snapshot::GrantState::granted, 0x0001}}});
    require(required_candidate.applyPermissionSnapshot(77, required_partial) &&
                required_candidate
                    .permissions()
                    .value(QStringLiteral("org.example.reserved-operations"))
                    .toMap()
                    .value(QStringLiteral("state")) ==
                    QStringLiteral("partial") &&
                required_candidate.hasPermission(
                    "org.example.reserved-operations", "required") &&
                !required_candidate.hasPermission(
                    "org.example.reserved-operations", "state"),
            "authority-valid partial required operations were rejected");
  }
  {
    manifest::ManifestV2 many;
    many.id = "org.example.many";
    for (std::size_t index = 0; index < 65; ++index) {
      many.requests.push_back(
          {.capability = "org.example.capability-" + std::to_string(index),
           .reason = "bounded projection",
           .canonical_scope = "{}",
           .definition_generation = 1,
           .definition_digest = std::string(64, 'a'),
           .operations = {"read"},
           .required = false});
    }
    worker::QmlBrokerApi candidate(
        endpoint, std::make_unique<worker::ManifestInvokeEncoder>(many), many,
        77);
    const auto many_payload = wire::permission_snapshot::encode({
        .manifest_request_fingerprint =
            manifest::requested_capability_fingerprint(many.requests),
        .permissions =
            std::vector<wire::permission_snapshot::PermissionRow>(
                many.requests.size(),
                {wire::permission_snapshot::GrantState::granted, 0x0001})});
    require(candidate.applyPermissionSnapshot(77, many_payload) &&
                candidate.hasPermission("org.example.capability-64", "read"),
            "worker retained the removed 64-row projection limit");
  }

  QQmlEngine engine;
  engine.rootContext()->setContextProperty(QStringLiteral("runtime"), &api);
  QQmlComponent component(&engine);
  component.setData(R"(
    import QtQml
    QtObject {
      id: root
      readonly property bool notificationsAvailable:
        runtime.hasPermission("notifications.send", "send")
    })", QUrl());
  std::unique_ptr<QObject> qml(component.create());
  require(qml != nullptr && qml->property("notificationsAvailable").toBool(),
          "representative QML did not enable its granted optional feature");
  auto *still_checked = qobject_cast<worker::BrokerCall *>(
      api.invoke(QStringLiteral("storage.private"), QStringLiteral("read"),
                 {{QStringLiteral("key"), QStringLiteral("widget-state")}})
          .value<QObject *>());
  static_cast<void>(receive_packet(host));
  const auto broker_denial = broker::encode_broker_error({
      .failed_operation = permissions::OperationId::storage_read,
      .reason = broker::BrokerErrorReason::denied,
      .decision = permissions::GrantDecisionCode::explicitly_denied});
  finish(api, endpoint, host, host_sequence, still_checked->correlation(),
         static_cast<std::uint16_t>(wire::CommonMessageType::typed_error),
         broker_denial);
  require(still_checked->finished() && !still_checked->ok(),
          "QML-visible availability bypassed authoritative broker denial");
  require(qml->property("notificationsAvailable").toBool(),
          "one-shot permission projection was not immutable in QML");
}
void neutral_surface_trusted_input() {
  const std::filesystem::path fixture =
      std::filesystem::path(OMARCHY_NEUTRAL_SURFACE_FIXTURE_ROOT);
  QFile manifest_file(
      QString::fromStdString((fixture / "manifest.json").string()));
  require(manifest_file.open(QIODevice::ReadOnly),
          "neutral fixture manifest could not be opened");
  const auto parsed = manifest::parse_manifest_v2(
      manifest_file.readAll().toStdString());
  require(parsed.requests.empty(),
          "neutral input fixture unexpectedly requested authority");

  Pair pair;
  wire::SessionSequence worker_sequence;
  worker::WorkerEndpoint endpoint(pair.descriptors[0],
                                  wire::EndpointRole::broker,
                                  broker::kBrokerRoleVersion,
                                  worker_sequence);
  handshake(endpoint, pair.descriptors[1]);
  worker::QmlBrokerApi api(
      endpoint, std::make_unique<worker::ManifestInvokeEncoder>(parsed),
      parsed, 77);
  FixtureIntentSink sink;
  require(api.bindSurfaceIntentSink(sink),
          "neutral fixture intent sink did not bind");

  const auto page_size = sysconf(_SC_PAGESIZE);
  require(page_size > 0, "neutral input fixture page size was unavailable");
  const auto allocation = surface::make_allocation(
      {.id = 71, .generation = 9}, 252, 48, 252, 48, 1, 1,
      static_cast<std::uint64_t>(page_size));
  const auto panel_allocation = surface::make_allocation(
      {.id = 72, .generation = 9}, 320, 480, 320, 480, 1, 1,
      static_cast<std::uint64_t>(page_size));
  require(allocation.has_value() && panel_allocation.has_value(),
          "neutral surface allocations were invalid");

  worker::WorkerRuntime runtime(fixture);
  require(static_cast<bool>(runtime.bind_runtime_api(api)),
          "neutral runtime API did not bind");
  require(static_cast<bool>(runtime.load_surface_entry("bar", "ui/Bar.qml")),
          "neutral bar surface did not load");
  require(
      static_cast<bool>(runtime.load_surface_entry("panel", "ui/Panel.qml")),
      "neutral panel surface did not load");
  require(static_cast<bool>(runtime.select_software_profile(
              surface::software_profile_offer())),
          "neutral software profile was rejected");
  require(static_cast<bool>(runtime.bind_surface("bar", allocation->surface)),
          "neutral bar surface did not bind");
  require(static_cast<bool>(
              runtime.bind_surface("panel", panel_allocation->surface)),
          "neutral panel surface did not bind");
  const int descriptor = static_cast<int>(
      syscall(SYS_memfd_create, "neutral-input-frame", MFD_CLOEXEC));
  const int panel_descriptor = static_cast<int>(
      syscall(SYS_memfd_create, "neutral-panel-frame", MFD_CLOEXEC));
  require(descriptor >= 0 &&
              ftruncate(descriptor,
                        static_cast<off_t>(allocation->mapping_bytes)) == 0 &&
              panel_descriptor >= 0 &&
              ftruncate(panel_descriptor,
                        static_cast<off_t>(panel_allocation->mapping_bytes)) ==
                  0 &&
              static_cast<bool>(runtime.allocate(*allocation, descriptor)) &&
              static_cast<bool>(
                  runtime.allocate(*panel_allocation, panel_descriptor)),
          "neutral surfaces did not receive trusted frame allocations");

  auto interleaved_pointer = [&](std::uint64_t sequence,
                                 surface::ButtonState state,
                                 std::uint32_t buttons) {
    return surface::InputEvent{
        .surface = allocation->surface,
        .sequence = sequence,
        .payload = surface::PointerButton{
            .position = {.x_q16 = 63U << 16, .y_q16 = 24U << 16},
            .button = static_cast<std::uint32_t>(Qt::LeftButton),
            .state = state,
            .buttons = buttons}};
  };
  const auto interleaved_press = interleaved_pointer(
      1, surface::ButtonState::pressed,
      static_cast<std::uint32_t>(Qt::LeftButton));
  require(api.beginTrustedGestureForInput(interleaved_press) &&
              static_cast<bool>(runtime.input(interleaved_press)),
          "interleaved MouseArea press did not reach the worker");
  api.endTrustedGesture();
  runtime.request_render();
  bool sibling_rendered = false;
  for (int attempt = 0; attempt < 4 && !sibling_rendered; ++attempt) {
    const auto frame = runtime.render();
    require(frame.has_value(),
            "interleaved sibling surface did not produce a frame");
    sibling_rendered = frame->ready.surface == panel_allocation->surface;
  }
  require(sibling_rendered,
          "panel sibling was not rendered between bar press and release");
  drain_events();
  const auto interleaved_release = interleaved_pointer(
      2, surface::ButtonState::released, 0);
  require(api.beginTrustedGestureForInput(interleaved_release) &&
              static_cast<bool>(runtime.input(interleaved_release)),
          "interleaved MouseArea release did not reach the worker");
  api.endTrustedGesture();
  require(sink.targets.size() == 1 && sink.targets[0] == "panel" &&
              sink.actions[0] == surface::SurfaceIntentAction::toggle &&
              sink.sources[0] &&
              sink.sources[0]->surface_id == allocation->surface.id &&
              sink.sources[0]->surface_generation ==
                  allocation->surface.generation &&
              sink.sources[0]->input_sequence == 1,
          "interleaved secure-surface click did not reach the worker MouseArea");
  sink.sources.clear();
  sink.targets.clear();
  sink.actions.clear();

  require(static_cast<bool>(runtime.input(
              {.surface = allocation->surface,
               .sequence = 3,
               .payload = surface::FocusChanged{.focused = true}})) &&
              sink.targets.empty(),
          "neutral bar requested a surface before pointer input");

  auto pointer = [&](std::uint64_t sequence, std::uint32_t x,
                     surface::ButtonState state, std::uint32_t buttons) {
    return surface::InputEvent{
        .surface = allocation->surface,
        .sequence = sequence,
        .payload = surface::PointerButton{
            .position = {.x_q16 = x << 16, .y_q16 = 24U << 16},
            .button = static_cast<std::uint32_t>(Qt::LeftButton),
            .state = state,
            .buttons = buttons}};
  };
  const auto panel_press =
      pointer(4, 63, surface::ButtonState::pressed,
              static_cast<std::uint32_t>(Qt::LeftButton));
  require(api.beginTrustedGestureForInput(panel_press) &&
              static_cast<bool>(runtime.input(panel_press)),
          "neutral panel press did not traverse trusted worker input");
  api.endTrustedGesture();
  bool deferred_callback_accepted = true;
  QTimer::singleShot(0, [&] {
    deferred_callback_accepted = api.requestSurfaceIntent(
        QStringLiteral("panel"), QStringLiteral("toggle"));
  });
  drain_events();
  require(sink.targets.empty() && !deferred_callback_accepted,
          "pointer press exposed its deferred claim outside input dispatch");

  const auto panel_release =
      pointer(5, 63, surface::ButtonState::released, 0);
  require(api.beginTrustedGestureForInput(panel_release) &&
              static_cast<bool>(runtime.input(panel_release)),
          "neutral panel release did not traverse trusted worker input");
  api.endTrustedGesture();
  require(sink.targets.size() == 1 && sink.targets[0] == "panel" &&
              sink.actions[0] == surface::SurfaceIntentAction::toggle &&
              sink.sources[0] &&
              sink.sources[0]->surface_id == allocation->surface.id &&
              sink.sources[0]->surface_generation ==
                  allocation->surface.generation &&
              sink.sources[0]->input_sequence == 4,
          "neutral panel click lost its exact press gesture claim");
  require(!api.requestSurfaceIntent(QStringLiteral("panel"),
                                    QStringLiteral("toggle")),
          "neutral panel click replayed its consumed gesture claim");

  const auto overlay_press =
      pointer(6, 189, surface::ButtonState::pressed,
              static_cast<std::uint32_t>(Qt::LeftButton));
  require(api.beginTrustedGestureForInput(overlay_press) &&
              static_cast<bool>(runtime.input(overlay_press)),
          "neutral overlay press did not traverse trusted worker input");
  api.endTrustedGesture();
  require(sink.targets.size() == 1,
          "TapHandler requested its intent before the tap completed");
  const auto overlay_release =
      pointer(7, 189, surface::ButtonState::released, 0);
  require(api.beginTrustedGestureForInput(overlay_release) &&
              static_cast<bool>(runtime.input(overlay_release)),
          "neutral overlay release did not traverse trusted worker input");
  api.endTrustedGesture();
  require(sink.targets.size() == 2 && sink.targets[1] == "overlay" &&
              sink.actions[1] == surface::SurfaceIntentAction::toggle &&
              sink.sources[1] && sink.sources[1]->input_sequence == 6,
          "neutral TapHandler lost its exact press gesture claim");
}

void run() {
  neutral_surface_trusted_input();
  structured_command_execution();
  worker::BrokerCall text_call(1);
  text_call.resolve(QByteArray("{\"station\":\"M\xC3\xBCnchen\"}"));
  require(text_call.utf8Text() == QString::fromUtf8("{\"station\":\"M\xC3\xBCnchen\"}"),
          "successful UTF-8 broker result was not exposed safely to QML");
  worker::BrokerCall binary_call(2);
  binary_call.resolve(QByteArray("\xff", 1));
  require(binary_call.utf8Text().isEmpty(),
          "invalid UTF-8 broker result was exposed as text");
  Pair pair;
  wire::SessionSequence worker_sequence;
  wire::SessionSequence host_sequence;
  worker::WorkerEndpoint endpoint(pair.descriptors[0], wire::EndpointRole::broker,
                                  broker::kBrokerRoleVersion, worker_sequence);
  handshake(endpoint, pair.descriptors[1]);
  const auto readiness_manifest = manifest::parse_manifest_v2(
      R"({"schemaVersion":2,"id":"org.example.readiness","name":"Readiness","version":"1","runtime":{"apiVersion":1,"qml":"Main.qml"},"surfaces":{},"permissions":{"required":[],"optional":[{"capability":"storage.private","reason":"state","quotaBytes":65536}]}})");
  worker::QmlBrokerApi api(
      endpoint,
      std::make_unique<worker::ManifestInvokeEncoder>(readiness_manifest),
      readiness_manifest, 77);
  QQmlEngine readiness_engine;
  readiness_engine.rootContext()->setContextProperty(
      QStringLiteral("runtime"), &api);
  QQmlComponent readiness_component(&readiness_engine);
  readiness_component.setData(R"(
    import QtQml
    QtObject {
      id: root
      property bool observedReady: runtime.brokerReady
      property int transitions: 0
      property var startupCall
      property var readyCall
      function requestWrite() {
        return runtime.invoke("storage.private", "write", {
          key: "startup-state", value: "saved",
          quotaBytes: 65536, itemBytes: 4096
        })
      }
      Component.onCompleted: startupCall = requestWrite()
      property Connections readiness: Connections {
        target: runtime
        function onBrokerReadyChanged() {
          root.transitions += 1
          if (runtime.brokerReady)
            root.readyCall = root.requestWrite()
        }
      }
    })", QUrl());
  std::unique_ptr<QObject> readiness(readiness_component.create());
  require(readiness != nullptr && !api.brokerReady() &&
              !readiness->property("observedReady").toBool(),
          "broker was QML-visible as ready before startup acknowledgement");
  require(fcntl(pair.descriptors[1], F_SETFL, O_NONBLOCK) == 0,
          "early-invoke nonblocking host setup failed");
  auto *early = qobject_cast<worker::BrokerCall *>(
      readiness->property("startupCall").value<QObject *>());
  std::byte early_byte{};
  errno = 0;
  require(early != nullptr && early->finished() && !early->ok() &&
              early->correlation() == 0 &&
              early->error() == QStringLiteral("broker-not-ready") &&
              recv(pair.descriptors[1], &early_byte, 1, 0) < 0 &&
              (errno == EAGAIN || errno == EWOULDBLOCK),
          "startup QML emitted a broker request before readiness");
  require(!api.markBrokerReady() && !api.brokerReady(),
          "broker became ready before a permission snapshot existed");
  const auto readiness_snapshot = wire::permission_snapshot::encode({
      .manifest_request_fingerprint =
          manifest::requested_capability_fingerprint(
              readiness_manifest.requests),
      .permissions = {
          {wire::permission_snapshot::GrantState::granted, 0x0002}}});
  require(api.applyPermissionSnapshot(77, readiness_snapshot) &&
              api.hasPermission("storage.private", "write") &&
              !api.hasPermission("storage.private", "read") &&
              !api.brokerReady() &&
              !readiness->property("observedReady").toBool(),
          "accepting a permission snapshot implied broker readiness");
  require(api.markBrokerReady() && api.brokerReady() &&
              !api.markBrokerReady(),
          "broker readiness was not a one-shot startup transition");
  drain_events();
  require(readiness->property("observedReady").toBool() &&
              readiness->property("transitions").toInt() == 1,
          "QML did not observe the exact broker readiness transition");
  require(fcntl(pair.descriptors[1], F_SETFL, 0) == 0,
          "blocking host restore failed");
  auto *ready_call = qobject_cast<worker::BrokerCall *>(
      readiness->property("readyCall").value<QObject *>());
  require(ready_call != nullptr && !ready_call->finished() &&
              ready_call->correlation() != 0,
          "QML readiness transition did not permit a broker request");
  const auto ready_request_bytes = receive_packet(pair.descriptors[1]);
  const auto ready_request = wire::decode_packet(
      ready_request_bytes, wire::EndpointRole::broker);
  broker::DecodedBrokerRequest ready_decoded{};
  require(ready_request &&
              broker::decode_broker_request(
                  ready_request.packet.header.message_type,
                  ready_request.packet.payload, ready_decoded) ==
                  broker::BrokerDecodeResult::accepted &&
              ready_decoded.operation ==
                  permissions::OperationId::storage_write,
          "post-readiness QML request was not a bounded broker operation");
  finish(api, endpoint, pair.descriptors[1], host_sequence,
         ready_call->correlation(), broker::kBrokerResultMessage, {});
  require(ready_call->finished() && ready_call->ok(),
          "post-readiness QML request did not complete");
  IntentSink intent_sink;
  IntentSink second_sink;
  require(api.bindSurfaceIntentSink(intent_sink) &&
              !api.bindSurfaceIntentSink(second_sink) &&
              !api.requestSurfaceIntent(QStringLiteral("panel"),
                                        QStringLiteral("toggle")) &&
              intent_sink.calls == 0,
          "surface intent sink was rebound or invoked without trusted input");
  require(api.requestSurfaceIntent(QStringLiteral("PanelWidget"),
                                   QStringLiteral("dismiss")) &&
              intent_sink.calls == 1 && !intent_sink.last_source &&
              intent_sink.last_target == "PanelWidget" &&
              intent_sink.last_action == surface::SurfaceIntentAction::dismiss,
          "declared self-dismiss incorrectly required a trusted gesture");
  intent_sink.calls = 0;
  intent_sink.last_source.reset();
  api.beginTrustedGesture(3, 77, 9);
  require(!api.requestSurfaceIntent(QString(), QStringLiteral("toggle")) &&
              !api.requestSurfaceIntent(QStringLiteral("Panel.Widget"),
                                        QStringLiteral("toggle")) &&
              !api.requestSurfaceIntent(QStringLiteral("PanelWidget"),
                                        QStringLiteral("execute")) &&
              !api.requestSurfaceIntent(QStringLiteral("MissingWidget"),
                                       QStringLiteral("toggle")) &&
              intent_sink.calls == 1 &&
              !api.requestSurfaceIntent(QStringLiteral("PanelWidget"),
                                        QStringLiteral("toggle")),
          "undeclared target was accepted or retained gesture eligibility");
  api.beginTrustedGesture(3, 77, 10);
  require(api.requestSurfaceIntent(QStringLiteral("PanelWidget"),
                                   QStringLiteral("toggle")) &&
              intent_sink.calls == 2 &&
              intent_sink.last_source &&
              intent_sink.last_source->surface_id == 3 &&
              intent_sink.last_source->surface_generation == 77 &&
              intent_sink.last_source->input_sequence == 10 &&
              intent_sink.last_target == "PanelWidget" &&
              intent_sink.last_action == surface::SurfaceIntentAction::toggle &&
              !api.requestSurfaceIntent(QStringLiteral("PanelWidget"),
                                        QStringLiteral("toggle")),
          "QML intent request escaped its closed trusted sink contract");
  api.beginTrustedGesture(3, 77, 11);
  const QVariantMap intent_data{
      {QStringLiteral("screen"), QStringLiteral("DP-1")},
      {QStringLiteral("resume"), true}};
  require(api.requestSurfaceIntent(QStringLiteral("PanelWidget"),
                                   QStringLiteral("open"), intent_data) &&
              intent_sink.calls == 3 && intent_sink.last_source &&
              intent_sink.last_source->input_sequence == 11 &&
              intent_sink.last_data == intent_data,
          "bounded same-plugin intent data was not preserved");
  api.beginTrustedGesture(3, 77, 12);
  require(!api.requestSurfaceIntent(
              QStringLiteral("PanelWidget"), QStringLiteral("open"),
              {{QStringLiteral("oversized"), QString(4097, QLatin1Char('x'))}}) &&
              intent_sink.calls == 3 &&
              api.requestSurfaceIntent(QStringLiteral("PanelWidget"),
                                       QStringLiteral("open")) &&
              intent_sink.calls == 4 && intent_sink.last_source &&
              intent_sink.last_source->input_sequence == 12,
          "oversized intent data was accepted or consumed gesture authority");
  api.endTrustedGesture();

  const surface::SurfaceKey gesture_surface{.id = 3, .generation = 77};
  const auto pointer = [&](std::uint64_t sequence, std::uint32_t button,
                           surface::ButtonState state) {
    return surface::InputEvent{
        .surface = gesture_surface,
        .sequence = sequence,
        .payload = surface::PointerButton{
            .position = {.x_q16 = 1U << 16, .y_q16 = 1U << 16},
            .button = button,
            .state = state,
            .buttons = state == surface::ButtonState::pressed ? button : 0U}};
  };
  const auto left = static_cast<std::uint32_t>(Qt::LeftButton);
  const auto right = static_cast<std::uint32_t>(Qt::RightButton);

  const auto pressed_once = pointer(11, left, surface::ButtonState::pressed);
  require(api.beginTrustedGestureForInput(pressed_once) &&
              api.requestSurfaceIntent(QStringLiteral("PanelWidget"),
                                       QStringLiteral("toggle")),
          "onPressed compatibility did not consume the exact gesture");
  api.endTrustedGesture();
  require(!api.beginTrustedGestureForInput(
              pointer(12, left, surface::ButtonState::released)) &&
              !api.requestSurfaceIntent(QStringLiteral("PanelWidget"),
                                        QStringLiteral("toggle")),
          "onPressed gesture was reusable during release");

  intent_sink.accept = false;
  require(api.beginTrustedGestureForInput(
              pointer(13, left, surface::ButtonState::pressed)) &&
              !api.requestSurfaceIntent(QStringLiteral("PanelWidget"),
                                        QStringLiteral("toggle")),
          "sink failure was not surfaced to the press handler");
  api.endTrustedGesture();
  require(!api.beginTrustedGestureForInput(
              pointer(14, left, surface::ButtonState::released)),
          "failed surface-intent send retained a release-phase replay");
  intent_sink.accept = true;

  require(api.beginTrustedGestureForInput(
              pointer(15, left, surface::ButtonState::pressed)),
          "mismatch fixture did not retain its press claim");
  api.endTrustedGesture();
  require(!api.beginTrustedGestureForInput(
              pointer(16, right, surface::ButtonState::released)) &&
              !api.requestSurfaceIntent(QStringLiteral("PanelWidget"),
                                        QStringLiteral("toggle")),
          "mismatched pointer release exposed a deferred gesture");

  require(api.beginTrustedGestureForInput(
              pointer(17, left, surface::ButtonState::pressed)),
          "cancel fixture did not retain its press claim");
  api.endTrustedGesture();
  require(!api.beginTrustedGestureForInput(
              {.surface = gesture_surface,
               .sequence = 18,
               .payload = surface::Cancel{}}) &&
              !api.beginTrustedGestureForInput(
                  pointer(19, left, surface::ButtonState::released)),
          "Cancel did not erase the deferred pointer gesture");

  require(api.beginTrustedGestureForInput(
              pointer(20, left, surface::ButtonState::pressed)),
          "focus-loss fixture did not retain its press claim");
  api.endTrustedGesture();
  require(!api.beginTrustedGestureForInput(
              {.surface = gesture_surface,
               .sequence = 21,
               .payload = surface::FocusChanged{.focused = false}}) &&
              !api.beginTrustedGestureForInput(
                  pointer(22, left, surface::ButtonState::released)),
          "focus loss did not erase the deferred pointer gesture");

  require(api.beginTrustedGestureForInput(
              pointer(23, left, surface::ButtonState::pressed)),
          "replacement fixture did not retain its first press");
  api.endTrustedGesture();
  require(api.beginTrustedGestureForInput(
              pointer(24, right, surface::ButtonState::pressed)),
          "new press did not replace the prior deferred gesture");
  api.endTrustedGesture();
  require(api.beginTrustedGestureForInput(
              pointer(25, right, surface::ButtonState::released)) &&
              api.requestSurfaceIntent(QStringLiteral("PanelWidget"),
                                       QStringLiteral("toggle")) &&
              intent_sink.last_source &&
              intent_sink.last_source->input_sequence == 24,
          "matching release did not expose only the newest press claim");
  api.endTrustedGesture();

  const surface::InputEvent touch_begin{
      .surface = gesture_surface,
      .sequence = 26,
      .payload = surface::TouchFrame{
          .phase = surface::TouchFramePhase::begin}};
  require(api.beginTrustedGestureForInput(touch_begin),
          "touch begin did not retain its exact gesture claim");
  bool touch_callback_accepted = true;
  QTimer::singleShot(0, [&] {
    touch_callback_accepted = api.requestSurfaceIntent(
        QStringLiteral("PanelWidget"), QStringLiteral("toggle"));
  });
  api.endTrustedGesture();
  drain_events();
  require(!touch_callback_accepted,
          "deferred touch claim escaped into a queued callback");
  const surface::InputEvent touch_end{
      .surface = gesture_surface,
      .sequence = 27,
      .payload = surface::TouchFrame{
          .phase = surface::TouchFramePhase::end}};
  require(api.beginTrustedGestureForInput(touch_end) &&
              api.requestSurfaceIntent(QStringLiteral("PanelWidget"),
                                       QStringLiteral("toggle")) &&
              intent_sink.last_source &&
              intent_sink.last_source->input_sequence == 26 &&
              !api.requestSurfaceIntent(QStringLiteral("PanelWidget"),
                                        QStringLiteral("toggle")),
          "touch end did not consume the original begin claim exactly once");
  api.endTrustedGesture();

  require(api.beginTrustedGestureForInput(
              {.surface = gesture_surface,
               .sequence = 28,
               .payload = surface::TouchFrame{
                   .phase = surface::TouchFramePhase::begin}}),
          "touch-cancel fixture did not retain its begin claim");
  api.endTrustedGesture();
  require(!api.beginTrustedGestureForInput(
              {.surface = gesture_surface,
               .sequence = 29,
               .payload = surface::TouchFrame{
                   .phase = surface::TouchFramePhase::cancel}}) &&
              !api.beginTrustedGestureForInput(
                  {.surface = gesture_surface,
                   .sequence = 30,
                   .payload = surface::TouchFrame{
                       .phase = surface::TouchFramePhase::end}}),
          "touch cancel did not erase the deferred begin claim");

  QVariantMap arguments{{QStringLiteral("key"), QStringLiteral("timer-state")},
                        {QStringLiteral("value"), QByteArray("saved")}};
  auto *allowed = qobject_cast<worker::BrokerCall *>(
      api.invoke(QStringLiteral("storage.private"), QStringLiteral("write"),
                 arguments).value<QObject *>());
  require(allowed != nullptr && !allowed->finished() && allowed->correlation() != 0,
          "declared invoke did not become asynchronous");
  const auto request_bytes = receive_packet(pair.descriptors[1]);
  const auto request = wire::decode_packet(request_bytes, wire::EndpointRole::broker);
  broker::DecodedBrokerRequest decoded{};
  require(request && broker::decode_broker_request(
              request.packet.header.message_type, request.packet.payload, decoded) ==
              broker::BrokerDecodeResult::accepted &&
              decoded.operation == permissions::OperationId::storage_write,
          "compiled bootstrap request failed broker decoding");
  finish(api, endpoint, pair.descriptors[1], host_sequence,
         allowed->correlation(),
         broker::kBrokerResultMessage, {});
  require(allowed->finished() && allowed->ok(),
          "successful terminal response did not resolve QML call");

  QQmlEngine completion_engine;
  completion_engine.rootContext()->setContextProperty(
      QStringLiteral("runtime"), &api);
  QQmlComponent completion_component(&completion_engine);
  completion_component.setData(R"(
    import QtQml
    QtObject {
      id: root
      property var call: null
      property string phase: "idle"
      function start() {
        call = runtime.invoke("storage.private", "write", {
          key: "qml-completion", value: "saved",
          quotaBytes: 65536, itemBytes: 4096
        })
        phase = "waiting"
      }
      property Connections completion: Connections {
        target: runtime
        function onCallFinished(call) {
          if (call && root.call && call.finished &&
              call.correlation === root.call.correlation)
            root.phase = call.ok ? "allowed" : "denied"
        }
      }
    })", QUrl());
  std::unique_ptr<QObject> completion(completion_component.create());
  require(completion != nullptr &&
              QMetaObject::invokeMethod(completion.get(), "start"),
          "representative QML completion fixture failed to start");
  const auto qml_request = receive_packet(pair.descriptors[1]);
  const auto qml_decoded =
      wire::decode_packet(qml_request, wire::EndpointRole::broker);
  require(static_cast<bool>(qml_decoded),
          "representative QML request was malformed");
  finish(api, endpoint, pair.descriptors[1], host_sequence,
         qml_decoded.packet.header.correlation_id,
         broker::kBrokerResultMessage, {});
  drain_events();
  require(completion->property("phase") == QStringLiteral("allowed"),
          "authenticated reply did not update representative QML behavior");
  require(QMetaObject::invokeMethod(completion.get(), "start"),
          "representative denied QML completion fixture failed to restart");
  const auto qml_denied_request = receive_packet(pair.descriptors[1]);
  const auto qml_denied_decoded =
      wire::decode_packet(qml_denied_request, wire::EndpointRole::broker);
  require(static_cast<bool>(qml_denied_decoded),
          "representative denied QML request was malformed");
  const auto qml_denial = broker::encode_broker_error({
      .failed_operation = permissions::OperationId::storage_write,
      .reason = broker::BrokerErrorReason::denied,
      .decision = permissions::GrantDecisionCode::explicitly_denied});
  finish(api, endpoint, pair.descriptors[1], host_sequence,
         qml_denied_decoded.packet.header.correlation_id,
         static_cast<std::uint16_t>(wire::CommonMessageType::typed_error),
         qml_denial);
  drain_events();
  require(completion->property("phase") == QStringLiteral("denied"),
          "authenticated denial did not update representative QML behavior");

  auto *denied = qobject_cast<worker::BrokerCall *>(
      api.invoke(QStringLiteral("storage.private"), QStringLiteral("write"),
                 arguments).value<QObject *>());
  static_cast<void>(receive_packet(pair.descriptors[1]));
  const auto denial = broker::encode_broker_error({
      .failed_operation = permissions::OperationId::storage_write,
      .reason = broker::BrokerErrorReason::denied,
      .decision = permissions::GrantDecisionCode::explicitly_denied});
  finish(api, endpoint, pair.descriptors[1], host_sequence,
         denied->correlation(),
         static_cast<std::uint16_t>(wire::CommonMessageType::typed_error), denial);
  require(denied->finished() && !denied->ok() && denied->error() == "denied",
          "explicit denial did not reject QML call");

  auto *outside = qobject_cast<worker::BrokerCall *>(
      api.invoke(QStringLiteral("storage.private"), QStringLiteral("write"),
                 arguments).value<QObject *>());
  static_cast<void>(receive_packet(pair.descriptors[1]));
  const auto scope_denial = broker::encode_broker_error({
      .failed_operation = permissions::OperationId::storage_write,
      .reason = broker::BrokerErrorReason::denied,
      .decision = permissions::GrantDecisionCode::outside_scope});
  finish(api, endpoint, pair.descriptors[1], host_sequence,
         outside->correlation(),
         static_cast<std::uint16_t>(wire::CommonMessageType::typed_error),
         scope_denial);
  require(outside->finished() && !outside->ok(),
          "out-of-scope request did not reject QML call");

  require(fcntl(pair.descriptors[1], F_SETFL, O_NONBLOCK) == 0,
          "nonblocking host setup failed");
  auto *unknown = qobject_cast<worker::BrokerCall *>(
      api.invoke(QStringLiteral("shell.exec"), QStringLiteral("execute"), {})
          .value<QObject *>());
  auto *wrong_capability = qobject_cast<worker::BrokerCall *>(
      api.invoke(QStringLiteral("notifications.send"),
                 QStringLiteral("send"), {})
          .value<QObject *>());
  std::byte byte{};
  errno = 0;
  require(unknown != nullptr && unknown->finished() && !unknown->ok() &&
              unknown->error() == "request-undeclared" &&
              wrong_capability != nullptr && wrong_capability->finished() &&
              !wrong_capability->ok() &&
              wrong_capability->error() == "request-undeclared" &&
              recv(pair.descriptors[1], &byte, 1, 0) < 0 &&
              (errno == EAGAIN || errno == EWOULDBLOCK),
          "undeclared capability or operation gained an ambient fallback or "
          "broker packet");
  dynamic_qml_to_adapter();
  capability_qualified_collision();
  permission_awareness(endpoint, pair.descriptors[1], host_sequence);
  require(api.beginTrustedGestureForInput(
              pointer(31, left, surface::ButtonState::pressed)),
          "disconnect fixture did not retain its press claim");
  api.endTrustedGesture();
  api.disconnect(QStringLiteral("test-disconnect"));
  require(!api.beginTrustedGestureForInput(
              pointer(32, left, surface::ButtonState::released)),
          "disconnect retained a deferred release-phase gesture");
  drain_events();
  auto *disconnected = qobject_cast<worker::BrokerCall *>(
      api.invoke(QStringLiteral("storage.private"), QStringLiteral("write"),
                 arguments).value<QObject *>());
  errno = 0;
  require(!api.brokerReady() &&
              !readiness->property("observedReady").toBool() &&
              readiness->property("transitions").toInt() == 2 &&
              disconnected != nullptr && disconnected->finished() &&
              !disconnected->ok() && disconnected->correlation() == 0 &&
              disconnected->error() == QStringLiteral("broker-unavailable") &&
              recv(pair.descriptors[1], &byte, 1, 0) < 0 &&
              (errno == EAGAIN || errno == EWOULDBLOCK),
          "disconnect did not withdraw QML broker readiness without traffic");
}
} // namespace

#include "qml_broker_api_test.moc"

int main(int argc, char **argv) {
  qputenv("QT_QPA_PLATFORM", QByteArrayLiteral("offscreen"));
  qputenv("QSG_RHI_BACKEND", QByteArrayLiteral("software"));
  QGuiApplication application(argc, argv);
  try { run(); std::cout << "QML broker API: PASS\n"; return 0; }
  catch (const std::exception &error) {
    if (std::string_view(error.what()).find("SO_PEERCRED baseline: Operation not permitted") != std::string_view::npos) {
      std::cout << "QML broker API: SKIP (SO_PEERCRED blocked by test namespace)\n";
      return 77;
    }
    std::cerr << "QML broker API: " << error.what() << '\n'; return 1;
  }
}
