#include "omarchy/plugin/wire/common.hpp"
#include "omarchy/plugin/wire/state.hpp"
#include "omarchy/plugin_runtime/broker/broker_schema.hpp"
#include "omarchy/plugin_runtime/surface/render_messages.hpp"

#include <QCoreApplication>
#include <QObject>
#include <QQmlComponent>
#include <QQmlContext>
#include <QQmlEngine>

#include <sys/socket.h>
#include <unistd.h>

#include <array>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <memory>
#include <span>
#include <string>
#include <string_view>
#include <vector>

namespace wire = omarchy::plugin::wire;
namespace broker = omarchy::plugin_runtime::broker;
namespace surface = omarchy::plugin_runtime::surface;

namespace {
[[noreturn]] void fail() { _exit(120); }

std::uint16_t version(wire::EndpointRole role) {
  if (role == wire::EndpointRole::broker)
    return broker::kBrokerRoleVersion;
  if (role == wire::EndpointRole::render)
    return surface::kRenderRoleVersion;
  return 1;
}

std::uint64_t negotiate(int fd, wire::EndpointRole role) {
  wire::WorkerNegotiator negotiator(role, {version(role), version(role)});
  const auto hello = negotiator.make_hello();
  if (!hello)
    fail();
  std::array<std::byte, wire::kHeaderSize + 4> packet{};
  auto header = hello.header;
  header.payload_length = 4;
  const auto encoded = wire::encode_packet(header, hello.payload, packet);
  if (!encoded ||
      send(fd, packet.data(), encoded.bytes_written, MSG_NOSIGNAL) !=
          static_cast<ssize_t>(encoded.bytes_written))
    fail();
  std::array<std::byte, wire::kHeaderSize + 8> reply{};
  const ssize_t count = recv(fd, reply.data(), reply.size(), 0);
  if (count <= 0)
    fail();
  const auto decoded = wire::decode_packet(
      std::span(reply).first(static_cast<std::size_t>(count)), role);
  if (!decoded ||
      negotiator.accept_reply(decoded.packet) != wire::FatalReason::none ||
      !negotiator.selected())
    fail();
  return negotiator.launch_generation();
}

void put16(std::span<std::byte> bytes, std::size_t offset,
           std::uint16_t value) {
  bytes[offset] = static_cast<std::byte>(value >> 8U);
  bytes[offset + 1] = static_cast<std::byte>(value);
}
void put32(std::span<std::byte> bytes, std::size_t offset,
           std::uint32_t value) {
  for (std::size_t i = 0; i < 4; ++i)
    bytes[offset + i] = static_cast<std::byte>(value >> ((3U - i) * 8U));
}
void put64(std::span<std::byte> bytes, std::size_t offset,
           std::uint64_t value) {
  for (std::size_t i = 0; i < 8; ++i)
    bytes[offset + i] = static_cast<std::byte>(value >> ((7U - i) * 8U));
}

std::vector<std::byte> storage(std::string_view value) {
  std::vector<std::byte> payload(31 + value.size());
  const auto operation = static_cast<std::uint16_t>(
      broker::permissions::OperationId::storage_write);
  put16(payload, 0, operation);
  put16(payload, 2, 16);
  put32(payload, 4, static_cast<std::uint32_t>(7 + value.size()));
  put64(payload, 8, 4096);
  put64(payload, 16, 1024);
  put16(payload, 24, 1);
  put32(payload, 26, static_cast<std::uint32_t>(value.size()));
  payload[30] = std::byte{'k'};
  for (std::size_t i = 0; i < value.size(); ++i)
    payload[31 + i] = static_cast<std::byte>(value[i]);
  return payload;
}

std::vector<std::byte> notification() {
  constexpr std::string_view token = "timer";
  constexpr std::string_view title = "qml-title";
  constexpr std::string_view body = "qml-body";
  std::vector<std::byte> payload(15 + 4 + title.size() + body.size());
  const auto operation = static_cast<std::uint16_t>(
      broker::permissions::OperationId::notification_send);
  put16(payload, 0, operation);
  put16(payload, 2, 7);
  put32(payload, 4, static_cast<std::uint32_t>(4 + title.size() + body.size()));
  put16(payload, 8, 5);
  for (std::size_t i = 0; i < token.size(); ++i)
    payload[10 + i] = static_cast<std::byte>(token[i]);
  put16(payload, 15, static_cast<std::uint16_t>(title.size()));
  put16(payload, 17, static_cast<std::uint16_t>(body.size()));
  for (std::size_t i = 0; i < title.size(); ++i)
    payload[19 + i] = static_cast<std::byte>(title[i]);
  for (std::size_t i = 0; i < body.size(); ++i)
    payload[19 + title.size() + i] = static_cast<std::byte>(body[i]);
  return payload;
}
} // namespace

int main(int argc, char **argv) {
  QCoreApplication application(argc, argv);
  const char *mode_env = getenv("D1_MODE");
  const QString mode =
      QString::fromUtf8(mode_env == nullptr ? "allowed" : mode_env);
  QQmlEngine engine;
  QQmlComponent component(&engine);
  if (mode_env == nullptr) {
    component.loadUrl(QUrl::fromLocalFile(QStringLiteral("/plugin/Main.qml")));
  } else {
    engine.rootContext()->setContextProperty(QStringLiteral("fixtureMode"),
                                             mode);
    component.setData(R"(import QtQml
QtObject {
  readonly property string action: fixtureMode === "denied" ? "notification.send" : "storage.write"
  readonly property string value: "from-qml"
})",
                      QUrl(QStringLiteral("qrc:/E3Action.qml")));
  }
  std::unique_ptr<QObject> root(component.create());
  if (!root)
    fail();
  const QString action = root->property("action").toString();
  const QString value = root->property("value").toString();

  negotiate(3, wire::EndpointRole::control);
  const auto generation = negotiate(4, wire::EndpointRole::broker);
  negotiate(5, wire::EndpointRole::render);
  const bool denied = action == QStringLiteral("notification.send");
  const auto payload = denied ? notification() : storage(value.toStdString());
  wire::EnvelopeHeader header{
      .endpoint_role = wire::EndpointRole::broker,
      .message_type = static_cast<std::uint16_t>(
          denied ? broker::permissions::OperationId::notification_send
                 : broker::permissions::OperationId::storage_write),
      .role_protocol_version = broker::kBrokerRoleVersion,
      .payload_length = static_cast<std::uint32_t>(payload.size()),
      .launch_generation = generation,
      .correlation_id = denied ? 42U : 41U};
  std::vector<std::byte> packet(wire::kHeaderSize + payload.size());
  const auto encoded = wire::encode_packet(header, payload, packet);
  if (!encoded || send(4, packet.data(), encoded.bytes_written, MSG_NOSIGNAL) !=
                      static_cast<ssize_t>(encoded.bytes_written))
    fail();
  std::byte ignored{};
  while (recv(4, &ignored, 1, 0) < 0)
    ;
  return 0;
}
