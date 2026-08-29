#include "qml_broker_api.hpp"

#include "omarchy/plugin/wire/common.hpp"
#include "omarchy/plugin_runtime/broker/broker_codec.hpp"
#include "omarchy/plugin_runtime/broker/broker_schema.hpp"

#include <fcntl.h>
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
namespace permissions = omarchy::plugins::permissions;
namespace worker = omarchy::plugin_runtime::worker;
namespace wire = omarchy::plugin::wire;

void require(bool condition, const char *message) {
  if (!condition) throw std::runtime_error(message);
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
void run() {
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
}
} // namespace

int main() {
  try { run(); std::cout << "QML broker API: PASS\n"; return 0; }
  catch (const std::exception &error) {
    std::cerr << "QML broker API: " << error.what() << '\n'; return 1;
  }
}
