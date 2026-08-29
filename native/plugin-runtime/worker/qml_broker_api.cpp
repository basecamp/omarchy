#include "qml_broker_api.hpp"

#include "omarchy/plugin_runtime/broker/broker_schema.hpp"
#include "permission_contract.hpp"

#include <QByteArray>
#include <QJsonDocument>
#include <QJsonArray>
#include <QJsonObject>
#include <QStringDecoder>

#include <algorithm>
#include <limits>

namespace omarchy::plugin_runtime::worker {
namespace {
namespace broker = omarchy::plugin_runtime::broker;
namespace permissions = omarchy::plugins::permissions;
namespace wire = omarchy::plugin::wire;

void put16(std::span<std::byte> bytes, std::size_t offset, std::uint16_t value) {
  bytes[offset] = static_cast<std::byte>(value >> 8U);
  bytes[offset + 1] = static_cast<std::byte>(value);
}
void put32(std::span<std::byte> bytes, std::size_t offset, std::uint32_t value) {
  for (std::size_t index = 0; index < 4; ++index)
    bytes[offset + index] = static_cast<std::byte>(value >> ((3U - index) * 8U));
}
void put64(std::span<std::byte> bytes, std::size_t offset, std::uint64_t value) {
  for (std::size_t index = 0; index < 8; ++index)
    bytes[offset + index] = static_cast<std::byte>(value >> ((7U - index) * 8U));
}
bool bounded_text(const QByteArray &value, qsizetype maximum,
                  bool allow_newline = false) {
  if (value.isEmpty() || value.size() > maximum || value.contains('\0'))
    return false;
  for (const char byte : value) {
    const auto character = static_cast<unsigned char>(byte);
    if ((character < 0x20 && !(allow_newline && character == '\n')) ||
        character == 0x7f)
      return false;
  }
  return true;
}

std::optional<EncodedInvoke> storage(permissions::OperationId operation,
                                     const QVariantMap &arguments) {
  const QByteArray key = arguments.value(QStringLiteral("key")).toString().toUtf8();
  if (!bounded_text(key, 128)) return std::nullopt;
  const auto total = arguments.value(QStringLiteral("quotaBytes"), 65536).toULongLong();
  const auto item = arguments.value(QStringLiteral("itemBytes"), 4096).toULongLong();
  if (total == 0 || item == 0 || item > total) return std::nullopt;
  QByteArray value;
  if (operation == permissions::OperationId::storage_write) {
    value = arguments.value(QStringLiteral("value")).toByteArray();
    if (value.size() > 4096) return std::nullopt;
  }
  const std::size_t provider_size = operation == permissions::OperationId::storage_write
      ? 6U + static_cast<std::size_t>(key.size() + value.size())
      : 2U + static_cast<std::size_t>(key.size());
  std::vector<std::byte> output(24 + provider_size);
  const auto type = static_cast<std::uint16_t>(operation);
  put16(output, 0, type); put16(output, 2, 16);
  put32(output, 4, static_cast<std::uint32_t>(provider_size));
  put64(output, 8, total); put64(output, 16, item);
  put16(output, 24, static_cast<std::uint16_t>(key.size()));
  std::size_t offset = 26;
  if (operation == permissions::OperationId::storage_write) {
    put32(output, offset, static_cast<std::uint32_t>(value.size()));
    offset += 4;
  }
  std::transform(key.begin(), key.end(), output.begin() + offset,
                 [](char byte) { return static_cast<std::byte>(byte); });
  offset += static_cast<std::size_t>(key.size());
  std::transform(value.begin(), value.end(), output.begin() + offset,
                 [](char byte) { return static_cast<std::byte>(byte); });
  return EncodedInvoke{type, std::move(output)};
}

std::optional<EncodedInvoke> token_request(
    permissions::OperationId operation, const QByteArray &token,
    const QByteArray &provider) {
  if (!bounded_text(token, 96) || provider.size() > 60 * 1024)
    return std::nullopt;
  const auto type = static_cast<std::uint16_t>(operation);
  std::vector<std::byte> output(
      10 + static_cast<std::size_t>(token.size() + provider.size()));
  put16(output, 0, type);
  put16(output, 2, static_cast<std::uint16_t>(2 + token.size()));
  put32(output, 4, static_cast<std::uint32_t>(provider.size()));
  put16(output, 8, static_cast<std::uint16_t>(token.size()));
  std::transform(token.begin(), token.end(), output.begin() + 10,
                 [](char byte) { return static_cast<std::byte>(byte); });
  std::transform(provider.begin(), provider.end(),
                 output.begin() + 10 + token.size(),
                 [](char byte) { return static_cast<std::byte>(byte); });
  return EncodedInvoke{type, std::move(output)};
}

std::optional<EncodedInvoke> resource_request(
    permissions::OperationId operation, std::uint32_t resource,
    std::span<const std::byte> provider) {
  if (resource == 0 || provider.size() > 60 * 1024) return std::nullopt;
  const auto type = static_cast<std::uint16_t>(operation);
  std::vector<std::byte> output(16 + provider.size());
  put16(output, 0, type); put16(output, 2, 8);
  put32(output, 4, static_cast<std::uint32_t>(provider.size()));
  put32(output, 8, resource); put16(output, 12, type); put16(output, 14, 0);
  std::copy(provider.begin(), provider.end(), output.begin() + 16);
  return EncodedInvoke{type, std::move(output)};
}
} // namespace

ManifestInvokeEncoder::ManifestInvokeEncoder(
    const omarchy::plugins::manifest::ManifestV2 &manifest) {
  for (const auto &request : manifest.requests) {
    if (request.definition_generation == 0)
      continue;
    DynamicBinding binding{
        .definition = {
            .canonical_name = omarchy::plugins::definitions::Name(
                request.capability),
            .definition_generation = request.definition_generation,
            .definition_digest = omarchy::plugins::definitions::Digest(
                request.definition_digest)},
        .operations = request.operations};
    for (const auto &operation : binding.operations) {
      if (std::ranges::any_of(dynamic_, [&](const DynamicBinding &existing) {
            return std::ranges::find(existing.operations, operation) !=
                   existing.operations.end();
          }))
        ambiguous_ = true;
    }
    dynamic_.push_back(std::move(binding));
  }
}

std::optional<EncodedInvoke> ManifestInvokeEncoder::encode(
    std::string_view operation, const QVariantMap &arguments) const {
  if (const auto compiled = bootstrap_.encode(operation, arguments))
    return compiled;
  if (ambiguous_)
    return std::nullopt;
  const auto binding = std::ranges::find_if(
      dynamic_, [&](const DynamicBinding &candidate) {
        return std::ranges::find(candidate.operations, operation) !=
               candidate.operations.end();
      });
  if (binding == dynamic_.end())
    return std::nullopt;
  const auto scope =
      arguments.value(QStringLiteral("demandScope")).toString().toUtf8();
  if (!bounded_text(scope, 4096, false))
    return std::nullopt;
  const auto payload = QJsonDocument::fromVariant(
                           arguments.value(QStringLiteral("payload")))
                           .toJson(QJsonDocument::Compact);
  if (payload.isEmpty() ||
      payload.size() > static_cast<qsizetype>(
                           omarchy::plugins::definitions::
                               kMaximumDynamicPayloadBytes))
    return std::nullopt;
  std::array<std::byte,
             omarchy::plugins::definitions::kMaximumDynamicEnvelopeBytes>
      envelope{};
  std::size_t written = 0;
  const auto payload_bytes = std::as_bytes(std::span(
      payload.constData(), static_cast<std::size_t>(payload.size())));
  const omarchy::plugins::definitions::DynamicInvocation invocation{
      .definition = binding->definition,
      .operation = omarchy::plugins::definitions::Name(operation),
      .demand_scope = omarchy::plugins::definitions::CanonicalScope(
          scope.toStdString()),
      .payload = payload_bytes};
  if (!omarchy::plugins::definitions::encode_dynamic_invocation(
          invocation, envelope, written))
    return std::nullopt;
  return EncodedInvoke{
      broker::kDynamicInvokeMessage,
      std::vector<std::byte>(envelope.begin(), envelope.begin() + written)};
}

std::optional<EncodedInvoke> BootstrapInvokeEncoder::encode(
    std::string_view operation, const QVariantMap &arguments) const {
  if (operation == "storage_read")
    return storage(permissions::OperationId::storage_read, arguments);
  if (operation == "storage_write")
    return storage(permissions::OperationId::storage_write, arguments);
  if (operation == "storage_remove")
    return storage(permissions::OperationId::storage_remove, arguments);
  if (operation == "notification_send") {
    const auto category = arguments.value(QStringLiteral("category")).toString().toUtf8();
    const auto title = arguments.value(QStringLiteral("title")).toString().toUtf8();
    const auto body = arguments.value(QStringLiteral("body")).toString().toUtf8();
    if (!bounded_text(title, 96) || !bounded_text(body, 512, true))
      return std::nullopt;
    QByteArray provider(4, '\0');
    provider.append(title); provider.append(body);
    auto provider_bytes = std::span(reinterpret_cast<std::byte *>(provider.data()),
                                    static_cast<std::size_t>(provider.size()));
    put16(provider_bytes, 0, static_cast<std::uint16_t>(title.size()));
    put16(provider_bytes, 2, static_cast<std::uint16_t>(body.size()));
    return token_request(permissions::OperationId::notification_send,
                         category, provider);
  }
  if (operation == "audio_play_cue") {
    const auto cue = arguments.value(QStringLiteral("cue")).toString().toUtf8();
    return token_request(permissions::OperationId::audio_play_cue, cue, {});
  }
  if (operation == "fake_status_list") {
    const auto resource = arguments.value(QStringLiteral("resource")).toUInt();
    return resource_request(permissions::OperationId::fake_status_list,
                            resource, {});
  }
  if (operation == "fake_status_acknowledge") {
    const auto resource = arguments.value(QStringLiteral("resource")).toUInt();
    const auto status = arguments.value(QStringLiteral("id")).toUInt();
    if (status == 0) return std::nullopt;
    std::array<std::byte, 4> provider{};
    put32(provider, 0, status);
    return resource_request(
        permissions::OperationId::fake_status_acknowledge, resource, provider);
  }
  return std::nullopt;
}

BrokerCall::BrokerCall(std::uint64_t correlation, QObject *parent)
    : QObject(parent), correlation_(correlation) {}
bool BrokerCall::finished() const { return finished_; }
bool BrokerCall::ok() const { return ok_; }
QVariant BrokerCall::value() const { return value_; }
QString BrokerCall::utf8Text() const {
  if (!finished_ || !ok_ || !value_.canConvert<QByteArray>()) return {};
  QStringDecoder decoder(QStringDecoder::Utf8);
  const QByteArray bytes = value_.toByteArray();
  const QString text = decoder.decode(bytes);
  return decoder.hasError() ? QString{} : text;
}
QString BrokerCall::error() const { return error_; }
qulonglong BrokerCall::correlation() const { return correlation_; }
void BrokerCall::resolve(QVariant value) {
  if (finished_) return;
  value_ = std::move(value); ok_ = true; finished_ = true;
  QMetaObject::invokeMethod(this, [this] { emit finishedChanged(); },
                            Qt::QueuedConnection);
}
void BrokerCall::reject(QString error) {
  if (finished_) return;
  error_ = std::move(error); ok_ = false; finished_ = true;
  QMetaObject::invokeMethod(this, [this] { emit finishedChanged(); },
                            Qt::QueuedConnection);
}

QmlBrokerApi::QmlBrokerApi(WorkerEndpoint &endpoint,
                           std::unique_ptr<InvokeEncoder> encoder,
                           QObject *parent)
    : QObject(parent), endpoint_(endpoint), encoder_(std::move(encoder)) {}

QmlBrokerApi::QmlBrokerApi(
    WorkerEndpoint &endpoint, std::unique_ptr<InvokeEncoder> encoder,
    const omarchy::plugins::manifest::ManifestV2 &manifest,
    std::uint64_t activation_generation, QObject *parent)
    : QObject(parent), endpoint_(endpoint), encoder_(std::move(encoder)),
      activation_generation_(activation_generation) {
  for (const auto &request : manifest.requests) {
    std::vector<std::string> operations = request.operations;
    if (operations.empty() && request.capability == "storage.private")
      operations = {"read", "write", "remove"};
    else if (operations.empty() && request.capability == "notifications.send")
      operations = {"send"};
    else if (operations.empty() && request.capability == "audio.play-cue")
      operations = {"play"};
    else if (operations.empty() && request.capability == "service.fake-status")
      operations = {"list", "acknowledge"};
    for (const auto &operation : operations) {
      requested_permissions_.push_back(
          {.capability = QString::fromStdString(request.capability),
           .operation = QString::fromStdString(operation),
           .required = request.required,
           .granted = false});
    }
  }
}

bool QmlBrokerApi::hasPermission(const QString &capability,
                                 const QString &operation) const {
  const auto found = std::ranges::find_if(
      requested_permissions_, [&](const RequestedPermission &item) {
        return item.capability == capability && item.operation == operation;
      });
  return host_snapshot_received_ && found != requested_permissions_.end() &&
         found->granted;
}

QString QmlBrokerApi::permissionState(const QString &capability,
                                      const QString &operation) const {
  const auto found = std::ranges::find_if(
      requested_permissions_, [&](const RequestedPermission &item) {
        return item.capability == capability && item.operation == operation;
      });
  if (found == requested_permissions_.end())
    return QStringLiteral("unrequested");
  if (!host_snapshot_received_)
    return QStringLiteral("unavailable");
  return found->granted ? QStringLiteral("granted") : QStringLiteral("denied");
}

QVariantMap QmlBrokerApi::permissions() const {
  QVariantMap result;
  for (const auto &item : requested_permissions_) {
    QVariantMap capability = result.value(item.capability).toMap();
    capability.insert(item.operation,
                      host_snapshot_received_ && item.granted);
    capability.insert(QStringLiteral("required"), item.required);
    result.insert(item.capability, capability);
  }
  return result;
}

qulonglong QmlBrokerApi::permissionGeneration() const {
  return activation_generation_;
}

bool QmlBrokerApi::applyHostPermissionSnapshot(
    std::uint64_t activation_generation,
    std::span<const HostPermission> permissions) {
  if (activation_generation_ == 0 ||
      activation_generation != activation_generation_)
    return false;
  std::vector<bool> next(requested_permissions_.size(), false);
  std::vector<bool> seen(requested_permissions_.size(), false);
  for (const auto &permission : permissions) {
    const QString capability = QString::fromStdString(permission.capability);
    const QString operation = QString::fromStdString(permission.operation);
    const auto found = std::ranges::find_if(
        requested_permissions_, [&](const RequestedPermission &item) {
          return item.capability == capability && item.operation == operation;
        });
    if (found == requested_permissions_.end())
      return false;
    const auto index = static_cast<std::size_t>(
        std::distance(requested_permissions_.begin(), found));
    if (seen[index])
      return false;
    seen[index] = true;
    next[index] = permission.granted;
  }
  bool changed = !host_snapshot_received_;
  for (std::size_t index = 0; index < requested_permissions_.size(); ++index) {
    changed = changed || requested_permissions_[index].granted != next[index];
    requested_permissions_[index].granted = next[index];
  }
  host_snapshot_received_ = true;
  if (changed) {
    QMetaObject::invokeMethod(this, [this] { emit permissionsChanged(); },
                              Qt::QueuedConnection);
  }
  return true;
}

bool QmlBrokerApi::applyHostPermissionSnapshotPayload(
    std::uint64_t envelope_generation, std::span<const std::byte> payload) {
  if (payload.empty() || payload.size() > 32 * 1024)
    return false;
  QJsonParseError error{};
  const auto document = QJsonDocument::fromJson(
      QByteArray(reinterpret_cast<const char *>(payload.data()),
                 static_cast<qsizetype>(payload.size())),
      &error);
  if (error.error != QJsonParseError::NoError || !document.isObject())
    return false;
  const auto object = document.object();
  if (object.size() != 2 || !object.value(QStringLiteral("generation")).isDouble() ||
      !object.value(QStringLiteral("permissions")).isArray())
    return false;
  const auto generation_value = object.value(QStringLiteral("generation")).toDouble();
  if (generation_value < 1 || generation_value > 9007199254740991.0 ||
      generation_value != static_cast<double>(envelope_generation))
    return false;
  const auto entries = object.value(QStringLiteral("permissions")).toArray();
  if (entries.size() > 64)
    return false;
  std::vector<HostPermission> decoded;
  decoded.reserve(static_cast<std::size_t>(entries.size()));
  for (const auto &value : entries) {
    if (!value.isObject()) return false;
    const auto item = value.toObject();
    if (item.size() != 3 ||
        !item.value(QStringLiteral("capability")).isString() ||
        !item.value(QStringLiteral("operation")).isString() ||
        !item.value(QStringLiteral("granted")).isBool())
      return false;
    const auto capability = item.value(QStringLiteral("capability")).toString();
    const auto operation = item.value(QStringLiteral("operation")).toString();
    if (capability.isEmpty() || capability.size() > 128 || operation.isEmpty() ||
        operation.size() > 128 || capability.contains(QChar::Null) ||
        operation.contains(QChar::Null))
      return false;
    decoded.push_back({capability.toStdString(), operation.toStdString(),
                       item.value(QStringLiteral("granted")).toBool()});
  }
  return applyHostPermissionSnapshot(envelope_generation, decoded);
}

QVariant QmlBrokerApi::rejected(QString reason) {
  auto *call = new BrokerCall(0, this);
  call->reject(std::move(reason));
  notifyFinished(call);
  return QVariant::fromValue(static_cast<QObject *>(call));
}

void QmlBrokerApi::notifyFinished(BrokerCall *call) {
  QMetaObject::invokeMethod(
      this, [this, call] { emit callFinished(call); }, Qt::QueuedConnection);
}

QVariant QmlBrokerApi::invoke(const QString &operation,
                              const QVariantMap &arguments) {
  if (status_ != QStringLiteral("ready") || encoder_ == nullptr)
    return rejected(QStringLiteral("broker-unavailable"));
  auto encoded = encoder_->encode(operation.toUtf8().toStdString(), arguments);
  if (!encoded)
    return rejected(QStringLiteral("operation-undeclared"));
  auto slot = std::ranges::find_if(pending_, [](const Pending &item) {
    return item.call == nullptr;
  });
  if (slot == pending_.end() || next_correlation_ == 0)
    return rejected(QStringLiteral("request-limit"));
  const std::uint64_t correlation = next_correlation_++;
  auto *call = new BrokerCall(correlation, this);
  *slot = {.correlation = correlation,
           .message_type = encoded->message_type,
           .call = call};
  if (!endpoint_.send(encoded->message_type, encoded->payload, correlation)) {
    *slot = {};
    call->reject(QStringLiteral("transport-failed"));
    notifyFinished(call);
    disconnect(QStringLiteral("failed"));
  }
  return QVariant::fromValue(static_cast<QObject *>(call));
}

QmlBrokerApi::Pending *QmlBrokerApi::find(std::uint64_t correlation) {
  const auto found = std::ranges::find_if(pending_, [&](const Pending &item) {
    return item.call != nullptr && item.correlation == correlation;
  });
  return found == pending_.end() ? nullptr : &*found;
}

bool QmlBrokerApi::receive(ReceivedPacket packet) {
  if (!packet || packet.header.endpoint_role != wire::EndpointRole::broker ||
      packet.header.role_protocol_version != broker::kBrokerRoleVersion ||
      packet.header.launch_generation != endpoint_.generation() ||
      packet.header.correlation_id == 0 || !packet.descriptors.empty()) {
    disconnect(QStringLiteral("protocol-failed"));
    return false;
  }
  Pending *pending = find(packet.header.correlation_id);
  if (pending == nullptr) {
    disconnect(QStringLiteral("protocol-failed"));
    return false;
  }
  if (packet.header.message_type == broker::kBrokerResultMessage) {
    QByteArray bytes(reinterpret_cast<const char *>(packet.payload.data()),
                     static_cast<qsizetype>(packet.payload.size()));
    pending->call->resolve(bytes);
  } else if (packet.header.message_type ==
             static_cast<std::uint16_t>(wire::CommonMessageType::typed_error)) {
    broker::BrokerTypedError error{};
    if (!broker::decode_broker_error(packet.payload, error) ||
        static_cast<std::uint16_t>(error.failed_operation) != pending->message_type) {
      disconnect(QStringLiteral("protocol-failed"));
      return false;
    }
    pending->call->reject(QStringLiteral("denied"));
  } else {
    disconnect(QStringLiteral("protocol-failed"));
    return false;
  }
  notifyFinished(pending->call);
  *pending = {};
  return true;
}

QString QmlBrokerApi::status() const { return status_; }
void QmlBrokerApi::disconnect(QString reason) {
  if (status_ != QStringLiteral("ready")) return;
  status_ = std::move(reason);
  for (auto &pending : pending_) {
    if (pending.call != nullptr) {
      pending.call->reject(QStringLiteral("broker-disconnected"));
      notifyFinished(pending.call);
    }
    pending = {};
  }
}
} // namespace omarchy::plugin_runtime::worker
