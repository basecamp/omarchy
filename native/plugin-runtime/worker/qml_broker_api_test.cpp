#include "qml_broker_api.hpp"
#include "worker_runtime.hpp"

#include "omarchy/plugin/wire/common.hpp"
#include "omarchy/plugin_runtime/broker/broker_codec.hpp"
#include "omarchy/plugin_runtime/broker/broker_schema.hpp"

#include <fcntl.h>
#include <QGuiApplication>
#include <QEventLoop>
#include <QQmlComponent>
#include <QQmlContext>
#include <QQmlEngine>
#include <QTimer>
#include <sys/socket.h>
#include <unistd.h>

#include <array>
#include <cerrno>
#include <iostream>
#include <span>
#include <stdexcept>
#include <vector>

namespace {
namespace broker = omarchy::plugin_runtime::broker;
namespace definitions = omarchy::plugins::definitions;
namespace manifest = omarchy::plugins::manifest;
namespace permissions = omarchy::plugins::permissions;
namespace worker = omarchy::plugin_runtime::worker;
namespace wire = omarchy::plugin::wire;

class DuplicateApiBase : public QObject {
  Q_OBJECT
public:
  Q_INVOKABLE QVariant invoke(const QString &, const QVariantMap &) { return {}; }
};
class DuplicateApi final : public DuplicateApiBase {
  Q_OBJECT
public:
  Q_INVOKABLE QVariant invoke(const QString &, const QVariantMap &) { return {}; }
};
class WrongParameterApi final : public QObject {
  Q_OBJECT
public:
  Q_INVOKABLE QVariant invoke(const QString &, const QVariant &) { return {}; }
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
  require(endpoint.valid() && endpoint.send_hello(), "HELLO failed");
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
            int host, std::uint64_t correlation, std::uint16_t type,
            std::span<const std::byte> payload) {
  require(send_packet(host,
      {.endpoint_role = wire::EndpointRole::broker,
       .message_type = type,
       .role_protocol_version = broker::kBrokerRoleVersion,
       .launch_generation = 77,
       .correlation_id = correlation}, payload), "terminal send failed");
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
                  .implementation_digest = repeated('a'),
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
      "read", {{QStringLiteral("demandScope"),
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
void permission_awareness(worker::WorkerEndpoint &endpoint, int host) {
  const std::string document =
      R"({"schemaVersion":2,"id":"org.example.pet","name":"Pet","version":"1","runtime":{"apiVersion":1,"qml":"Main.qml"},"surfaces":{},"permissions":{"required":[{"capability":"storage.private","reason":"save","quotaBytes":1024}],"optional":[{"capability":"notifications.send","reason":"alerts","categories":["care"]}]}})";
  const auto parsed = manifest::parse_manifest_v2(document);
  worker::QmlBrokerApi api(
      endpoint, std::make_unique<worker::ManifestInvokeEncoder>(parsed),
      parsed, 77);
  worker::WorkerRuntime production_binding_probe("/not-loaded-in-this-test");
  require(static_cast<bool>(production_binding_probe.bind_runtime_api(api)),
          "production permission-aware runtime API failed the exact trusted-surface validator");
  DuplicateApi duplicate;
  worker::WorkerRuntime duplicate_probe("/not-loaded-in-this-test");
  require(!static_cast<bool>(duplicate_probe.bind_runtime_api(duplicate)),
          "duplicate trusted API method signatures passed validation");
  WrongParameterApi wrong_parameters;
  worker::WorkerRuntime parameter_probe("/not-loaded-in-this-test");
  require(!static_cast<bool>(parameter_probe.bind_runtime_api(wrong_parameters)),
          "trusted API validation ignored exact parameter types");
  int changes = 0;
  QObject::connect(&api, &worker::QmlBrokerApi::permissionsChanged,
                   [&] { ++changes; });
  require(api.permissionState("storage.private", "read") == "unavailable" &&
              !api.hasPermission("notifications.send", "send"),
          "permissions became available before a host snapshot");
  const std::array initial{
      worker::QmlBrokerApi::HostPermission{"storage.private", "read", true},
      worker::QmlBrokerApi::HostPermission{"storage.private", "write", true},
      worker::QmlBrokerApi::HostPermission{"notifications.send", "send", false}};
  require(api.applyHostPermissionSnapshot(77, initial),
          "initial host permission snapshot was rejected");
  drain_events();
  require(changes == 1 &&
              api.hasPermission("storage.private", "read") &&
              !api.hasPermission("notifications.send", "send") &&
              api.permissionState("notifications.send", "send") == "denied",
          "required and denied optional permissions were not represented");
  const auto before = api.permissions();
  const std::array spoof{
      worker::QmlBrokerApi::HostPermission{"shell.execute", "run", true}};
  require(!api.applyHostPermissionSnapshot(77, spoof) &&
              api.permissions() == before && changes == 1,
          "an unrequested host entry spoofed QML-visible authority");
  const std::array stale{
      worker::QmlBrokerApi::HostPermission{"notifications.send", "send", true}};
  require(!api.applyHostPermissionSnapshot(78, stale) &&
              !api.hasPermission("notifications.send", "send") && changes == 1,
          "a stale activation generation changed permission UX state");
  const std::array activated{
      worker::QmlBrokerApi::HostPermission{"storage.private", "read", true},
      worker::QmlBrokerApi::HostPermission{"storage.private", "write", true},
      worker::QmlBrokerApi::HostPermission{"notifications.send", "send", true}};
  require(api.applyHostPermissionSnapshot(77, activated),
          "activated host permission snapshot was rejected");
  drain_events();
  require(changes == 2 &&
              api.hasPermission("notifications.send", "send"),
          "optional permission activation was not surfaced");

  QQmlEngine engine;
  engine.rootContext()->setContextProperty(QStringLiteral("runtime"), &api);
  QQmlComponent component(&engine);
  component.setData(R"(
    import QtQml
    QtObject {
      id: root
      property int permissionRevision: 0
      readonly property bool notificationsAvailable:
        permissionRevision >= 0 && runtime.hasPermission("notifications.send", "send")
      property Connections permissionConnection: Connections {
        target: runtime
        function onPermissionsChanged() { root.permissionRevision += 1 }
      }
    })", QUrl());
  std::unique_ptr<QObject> qml(component.create());
  require(qml != nullptr && qml->property("notificationsAvailable").toBool(),
          "representative QML did not enable its granted optional feature");
  auto *still_checked = qobject_cast<worker::BrokerCall *>(
      api.invoke(QStringLiteral("storage_read"),
                 {{QStringLiteral("key"), QStringLiteral("pet-state")}})
          .value<QObject *>());
  static_cast<void>(receive_packet(host));
  const auto broker_denial = broker::encode_broker_error({
      .failed_operation = permissions::OperationId::storage_read,
      .reason = broker::BrokerErrorReason::denied,
      .decision = permissions::GrantDecisionCode::explicitly_denied});
  finish(api, endpoint, host, still_checked->correlation(),
         static_cast<std::uint16_t>(wire::CommonMessageType::typed_error),
         broker_denial);
  require(still_checked->finished() && !still_checked->ok(),
          "QML-visible availability bypassed authoritative broker denial");
  const std::array revoked{
      worker::QmlBrokerApi::HostPermission{"storage.private", "read", true},
      worker::QmlBrokerApi::HostPermission{"storage.private", "write", true},
      worker::QmlBrokerApi::HostPermission{"notifications.send", "send", false}};
  require(api.applyHostPermissionSnapshot(77, revoked),
          "revoked host permission snapshot was rejected");
  drain_events();
  require(changes == 3 &&
              !api.hasPermission("notifications.send", "send") &&
              !qml->property("notificationsAvailable").toBool(),
          "revocation did not notify representative QML and hide its feature");
}
void run() {
  worker::BrokerCall text_call(1);
  text_call.resolve(QByteArray("{\"station\":\"M\xC3\xBCnchen\"}"));
  require(text_call.utf8Text() == QString::fromUtf8("{\"station\":\"M\xC3\xBCnchen\"}"),
          "successful UTF-8 broker result was not exposed safely to QML");
  worker::BrokerCall binary_call(2);
  binary_call.resolve(QByteArray("\xff", 1));
  require(binary_call.utf8Text().isEmpty(),
          "invalid UTF-8 broker result was exposed as text");
  Pair pair;
  worker::WorkerEndpoint endpoint(pair.descriptors[0], wire::EndpointRole::broker,
                                  broker::kBrokerRoleVersion);
  handshake(endpoint, pair.descriptors[1]);
  worker::QmlBrokerApi api(endpoint,
      std::make_unique<worker::BootstrapInvokeEncoder>());

  QVariantMap arguments{{QStringLiteral("key"), QStringLiteral("timer-state")},
                        {QStringLiteral("value"), QByteArray("saved")}};
  auto *allowed = qobject_cast<worker::BrokerCall *>(
      api.invoke(QStringLiteral("storage_write"), arguments).value<QObject *>());
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
  finish(api, endpoint, pair.descriptors[1], allowed->correlation(),
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
        call = runtime.invoke("storage_write", {
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
  finish(api, endpoint, pair.descriptors[1],
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
  finish(api, endpoint, pair.descriptors[1],
         qml_denied_decoded.packet.header.correlation_id,
         static_cast<std::uint16_t>(wire::CommonMessageType::typed_error),
         qml_denial);
  drain_events();
  require(completion->property("phase") == QStringLiteral("denied"),
          "authenticated denial did not update representative QML behavior");

  auto *denied = qobject_cast<worker::BrokerCall *>(
      api.invoke(QStringLiteral("storage_write"), arguments).value<QObject *>());
  static_cast<void>(receive_packet(pair.descriptors[1]));
  const auto denial = broker::encode_broker_error({
      .failed_operation = permissions::OperationId::storage_write,
      .reason = broker::BrokerErrorReason::denied,
      .decision = permissions::GrantDecisionCode::explicitly_denied});
  finish(api, endpoint, pair.descriptors[1], denied->correlation(),
         static_cast<std::uint16_t>(wire::CommonMessageType::typed_error), denial);
  require(denied->finished() && !denied->ok() && denied->error() == "denied",
          "explicit denial did not reject QML call");

  auto *outside = qobject_cast<worker::BrokerCall *>(
      api.invoke(QStringLiteral("storage_write"), arguments).value<QObject *>());
  static_cast<void>(receive_packet(pair.descriptors[1]));
  const auto scope_denial = broker::encode_broker_error({
      .failed_operation = permissions::OperationId::storage_write,
      .reason = broker::BrokerErrorReason::denied,
      .decision = permissions::GrantDecisionCode::outside_scope});
  finish(api, endpoint, pair.descriptors[1], outside->correlation(),
         static_cast<std::uint16_t>(wire::CommonMessageType::typed_error),
         scope_denial);
  require(outside->finished() && !outside->ok(),
          "out-of-scope request did not reject QML call");

  require(fcntl(pair.descriptors[1], F_SETFL, O_NONBLOCK) == 0,
          "nonblocking host setup failed");
  auto *unknown = qobject_cast<worker::BrokerCall *>(
      api.invoke(QStringLiteral("shell_exec"), {}).value<QObject *>());
  std::byte byte{};
  errno = 0;
  require(unknown != nullptr && unknown->finished() && !unknown->ok() &&
              unknown->error() == "operation-undeclared" &&
              recv(pair.descriptors[1], &byte, 1, 0) < 0 &&
              (errno == EAGAIN || errno == EWOULDBLOCK),
          "undeclared operation gained an ambient fallback or broker packet");
  dynamic_qml_to_adapter();
  permission_awareness(endpoint, pair.descriptors[1]);
}
} // namespace

#include "qml_broker_api_test.moc"

int main(int argc, char **argv) {
  qputenv("QT_QPA_PLATFORM", QByteArrayLiteral("offscreen"));
  qputenv("QSG_RHI_BACKEND", QByteArrayLiteral("software"));
  QGuiApplication application(argc, argv);
  try { run(); std::cout << "QML broker API: PASS\n"; return 0; }
  catch (const std::exception &error) {
    std::cerr << "QML broker API: " << error.what() << '\n'; return 1;
  }
}
