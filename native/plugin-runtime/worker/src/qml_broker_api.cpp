#include "qml_broker_api.hpp"

#include "omarchy/plugin_runtime/broker/broker_schema.hpp"
#include "permission_contract.hpp"
#include "omarchy/plugin/wire/control.hpp"

#include <QByteArray>
#include <QColor>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSet>
#include <QStringDecoder>

#include <algorithm>
#include <cmath>
#include <fstream>
#include <limits>
#include <type_traits>

namespace omarchy::plugin_runtime::worker {
namespace {
namespace broker = omarchy::plugin_runtime::broker;
namespace permissions = omarchy::plugins::permissions;
namespace wire = omarchy::plugin::wire;
namespace snapshot_wire = wire::permission_snapshot;

constexpr qsizetype kMaximumSurfaceIntentDataBytes = 4096;
constexpr qsizetype kMaximumSurfaceIntentDataItems = 32;
constexpr int kMaximumSurfaceIntentDataDepth = 4;
constexpr qsizetype kMaximumPresentationBytes = 4096;

std::optional<QVariantMap>
parse_presentation_snapshot(std::span<const std::byte> payload) {
  if (payload.empty() || payload.size() > kMaximumPresentationBytes)
    return std::nullopt;
  QJsonParseError error{};
  const auto document = QJsonDocument::fromJson(
      QByteArray(reinterpret_cast<const char *>(payload.data()),
                 static_cast<qsizetype>(payload.size())),
      &error);
  if (error.error != QJsonParseError::NoError || !document.isObject())
    return std::nullopt;
  const auto object = document.object();
  static const QSet<QString> color_keys{
      QStringLiteral("foreground"), QStringLiteral("background"),
      QStringLiteral("accent"), QStringLiteral("urgent"),
      QStringLiteral("barForeground"), QStringLiteral("barBackground")};
  static const QSet<QString> size_keys{
      QStringLiteral("barSize"), QStringLiteral("iconSlot"),
      QStringLiteral("statusSlot")};
  QVariantMap result;
  for (auto entry = object.begin(); entry != object.end(); ++entry) {
    if (color_keys.contains(entry.key())) {
      if (!entry->isString() || entry->toString().size() > 16 ||
          !QColor::isValidColorName(entry->toString()))
        return std::nullopt;
      result.insert(entry.key(), entry->toString());
    } else if (size_keys.contains(entry.key())) {
      if (!entry->isDouble())
        return std::nullopt;
      const auto value = entry->toDouble();
      if (!std::isfinite(value) || std::floor(value) != value || value < 1 ||
          value > 256)
        return std::nullopt;
      result.insert(entry.key(), static_cast<int>(value));
    } else if (entry.key() == QStringLiteral("fontFamily")) {
      if (!entry->isString() || entry->toString().isEmpty() ||
          entry->toString().toUtf8().size() > 128)
        return std::nullopt;
      result.insert(entry.key(), entry->toString());
    } else if (entry.key() == QStringLiteral("barPosition")) {
      if (!entry->isString() ||
          (entry->toString() != QStringLiteral("top") &&
           entry->toString() != QStringLiteral("bottom") &&
           entry->toString() != QStringLiteral("left") &&
           entry->toString() != QStringLiteral("right")))
        return std::nullopt;
      result.insert(entry.key(), entry->toString());
    } else {
      return std::nullopt;
    }
  }
  return result;
}

bool valid_surface_intent_value(const QVariant &value, int depth) {
  if (depth > kMaximumSurfaceIntentDataDepth)
    return false;
  switch (value.metaType().id()) {
  case QMetaType::Bool:
  case QMetaType::Int:
  case QMetaType::UInt:
  case QMetaType::LongLong:
  case QMetaType::ULongLong:
    return true;
  case QMetaType::QString:
    return value.toString().toUtf8().size() <= 1024;
  case QMetaType::Double:
    return std::isfinite(value.toDouble());
  case QMetaType::QVariantList: {
    const auto list = value.toList();
    return list.size() <= kMaximumSurfaceIntentDataItems &&
           std::ranges::all_of(list, [depth](const QVariant &item) {
             return valid_surface_intent_value(item, depth + 1);
           });
  }
  case QMetaType::QVariantMap: {
    const auto map = value.toMap();
    return map.size() <= kMaximumSurfaceIntentDataItems &&
           std::ranges::all_of(
               map.asKeyValueRange(), [depth](const auto &item) {
                 return !item.first.isEmpty() && item.first.size() <= 64 &&
                        !item.first.contains(QChar::Null) &&
                        valid_surface_intent_value(item.second, depth + 1);
               });
  }
  default:
    return false;
  }
}

std::optional<QVariantMap>
bounded_surface_intent_data(const QVariantMap &candidate) {
  if (!valid_surface_intent_value(QVariant(candidate), 0))
    return std::nullopt;
  const auto document = QJsonDocument::fromVariant(candidate);
  if (!document.isObject() ||
      document.toJson(QJsonDocument::Compact).size() >
          kMaximumSurfaceIntentDataBytes)
    return std::nullopt;
  return document.object().toVariantMap();
}

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

QStringList operations_for(
    const omarchy::plugins::manifest::CapabilityRequest &request) {
  QStringList result;
  if (!request.operations.empty()) {
    for (const auto &operation : request.operations)
      result.push_back(QString::fromStdString(operation));
  } else {
    const permissions::CapabilityKey key{
        permissions::CapabilityId(request.capability), 1};
    const auto *definition = permissions::find_capability(key);
    if (definition == nullptr)
      return {};
    for (std::size_t index = 0; index < definition->operation_count; ++index) {
      const auto name = permissions::operation_name(definition->operations[index]);
      if (name.empty())
        return {};
      result.push_back(QString::fromUtf8(name.data(),
                                        static_cast<qsizetype>(name.size())));
    }
  }
  return result;
}

QString permission_state(snapshot_wire::GrantState state) {
  switch (state) {
  case snapshot_wire::GrantState::granted:
    return QStringLiteral("granted");
  case snapshot_wire::GrantState::denied:
    return QStringLiteral("denied");
  case snapshot_wire::GrantState::revoked:
    return QStringLiteral("revoked");
  }
  return QStringLiteral("unavailable");
}

QString capability_state(
    std::span<const snapshot_wire::GrantState> operations) {
  if (operations.empty())
    return QStringLiteral("denied");
  if (std::ranges::all_of(operations, [&](const auto state) {
        return state == operations.front();
      }))
    return permission_state(operations.front());
  return QStringLiteral("partial");
}

QVariantMap to_variant_settings(
    const std::map<std::string, omarchy::plugins::manifest::SettingValue,
                   std::less<>> &entry,
    std::string_view plugin_id) {
  QVariantMap result;
  result.insert(QStringLiteral("id"), QString::fromStdString(
                                          std::string(plugin_id)));
  for (const auto &[key, value] : entry) {
    result.insert(
        QString::fromStdString(key),
        std::visit(
            [](const auto &item) -> QVariant {
              using Value = std::decay_t<decltype(item)>;
              if constexpr (std::is_same_v<Value, std::string>)
                return QString::fromStdString(item);
              return QVariant::fromValue(item);
            },
            value));
  }
  return result;
}

std::optional<std::map<std::string,
                       omarchy::plugins::manifest::SettingValue, std::less<>>>
from_variant_settings(const omarchy::plugins::manifest::ManifestV2 &manifest,
                      const QVariantMap &candidate) {
  if (candidate.size() !=
          static_cast<qsizetype>(manifest.settings.schema.size() + 1) ||
      candidate.value(QStringLiteral("id")).toString().toStdString() !=
          manifest.id)
    return std::nullopt;
  std::map<std::string, omarchy::plugins::manifest::SettingValue, std::less<>>
      entry;
  for (const auto &definition : manifest.settings.schema) {
    const auto key = QString::fromStdString(definition.key);
    const auto found = candidate.constFind(key);
    if (found == candidate.cend())
      return std::nullopt;
    const QVariant &value = found.value();
    switch (definition.type) {
    case omarchy::plugins::manifest::SettingType::boolean:
      if (value.metaType().id() != QMetaType::Bool)
        return std::nullopt;
      entry.emplace(definition.key, value.toBool());
      break;
    case omarchy::plugins::manifest::SettingType::integer: {
      bool converted = false;
      const double number = value.toDouble(&converted);
      if (!converted || !std::isfinite(number) || std::trunc(number) != number ||
          number < static_cast<double>(std::numeric_limits<std::int64_t>::min()) ||
          number > static_cast<double>(std::numeric_limits<std::int64_t>::max()))
        return std::nullopt;
      entry.emplace(definition.key, static_cast<std::int64_t>(number));
      break;
    }
    case omarchy::plugins::manifest::SettingType::enumeration:
      if (value.metaType().id() != QMetaType::QString)
        return std::nullopt;
      entry.emplace(definition.key, value.toString().toStdString());
      break;
    }
  }
  return omarchy::plugins::manifest::validate_settings_entry(manifest, entry)
             ? std::optional(std::move(entry))
             : std::nullopt;
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

} // namespace

ManifestInvokeEncoder::ManifestInvokeEncoder(
    const omarchy::plugins::manifest::ManifestV2 &manifest) {
  for (const auto &request : manifest.requests) {
    if (!omarchy::plugins::definitions::canonical_identifier(
            request.capability)) {
      valid_ = false;
      continue;
    }
    if (std::ranges::any_of(bindings_, [&](const Binding &binding) {
          return binding.capability == request.capability;
        })) {
      valid_ = false;
      continue;
    }
    Binding binding{.capability = request.capability,
                    .operations = {},
                    .definition = std::nullopt};
    const permissions::CapabilityKey builtin_key{
        permissions::CapabilityId(request.capability), 1};
    if (const auto *builtin = permissions::find_capability(builtin_key)) {
      if (request.definition_generation != 0 ||
          !request.definition_digest.empty() || !request.operations.empty()) {
        valid_ = false;
        continue;
      }
      for (std::size_t index = 0; index < builtin->operation_count; ++index) {
        const auto operation =
            permissions::operation_name(builtin->operations[index]);
        if (operation.empty()) {
          valid_ = false;
          break;
        }
        binding.operations.emplace_back(operation);
      }
    } else {
      if (request.definition_generation == 0 ||
          !omarchy::plugins::definitions::valid_digest(
              request.definition_digest) ||
          request.operations.empty()) {
        valid_ = false;
        continue;
      }
      binding.definition =
          omarchy::plugins::definitions::CapabilityReference{
              .canonical_name = omarchy::plugins::definitions::Name(
                  request.capability),
              .definition_generation = request.definition_generation,
              .definition_digest = omarchy::plugins::definitions::Digest(
                  request.definition_digest)};
      for (const auto &operation : request.operations) {
        if (!omarchy::plugins::definitions::canonical_identifier(operation) ||
            std::ranges::find(binding.operations, operation) !=
            binding.operations.end()) {
          valid_ = false;
          break;
        }
        binding.operations.push_back(operation);
      }
    }
    if (valid_)
      bindings_.push_back(std::move(binding));
  }
}

std::optional<EncodedInvoke> ManifestInvokeEncoder::encode(
    std::string_view capability, std::string_view operation,
    const QVariantMap &arguments) const {
  if (!valid_)
    return std::nullopt;
  const auto binding = std::ranges::find(bindings_, capability,
                                         &Binding::capability);
  if (binding == bindings_.end() ||
      std::ranges::find(binding->operations, operation) ==
          binding->operations.end())
    return std::nullopt;
  if (!binding->definition)
    return builtin_.encode(capability, operation, arguments);
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
      .definition = *binding->definition,
      .operation = omarchy::plugins::definitions::Name(operation),
      .demand_scope = omarchy::plugins::definitions::CanonicalScope(
          scope.toStdString()),
      .gesture = {},
      .payload = payload_bytes};
  if (!omarchy::plugins::definitions::encode_dynamic_invocation(
          invocation, envelope, written))
    return std::nullopt;
  return EncodedInvoke{
      broker::kDynamicInvokeMessage,
      std::vector<std::byte>(envelope.begin(), envelope.begin() + written)};
}

std::optional<EncodedInvoke> BuiltinInvokeEncoder::encode(
    std::string_view capability, std::string_view operation,
    const QVariantMap &arguments) const {
  if (capability == "storage.private" && operation == "read")
    return storage(permissions::OperationId::storage_read, arguments);
  if (capability == "storage.private" && operation == "write")
    return storage(permissions::OperationId::storage_write, arguments);
  if (capability == "storage.private" && operation == "remove")
    return storage(permissions::OperationId::storage_remove, arguments);
  if (capability == "notifications.send" && operation == "send") {
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
  if (capability == "audio.play-cue" && operation == "play") {
    const auto cue = arguments.value(QStringLiteral("cue")).toString().toUtf8();
    return token_request(permissions::OperationId::audio_play_cue, cue, {});
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

QmlBrokerApi::QmlBrokerApi(
    WorkerEndpoint &endpoint, std::unique_ptr<InvokeEncoder> encoder,
    const omarchy::plugins::manifest::ManifestV2 &manifest,
    std::uint64_t activation_generation, QObject *parent,
    WorkerEndpoint *control)
    : QObject(parent), endpoint_(endpoint), control_(control),
      encoder_(std::move(encoder)),
      manifest_request_fingerprint_(
          omarchy::plugins::manifest::requested_capability_fingerprint(
              manifest.requests)),
      activation_generation_(activation_generation), manifest_(manifest) {
  const auto ordered =
      omarchy::plugins::manifest::canonical_capability_requests(
          manifest.requests);
  requested_permissions_.reserve(ordered.size());
  for (const auto &request : ordered) {
    requested_permissions_.push_back(
        {.capability = QString::fromStdString(request.capability),
         .operations = operations_for(request),
         .required = request.required,
         .operation_states = {}});
  }
}

bool QmlBrokerApi::hasPermission(const QString &capability,
                                 const QString &operation) const {
  const auto found = std::ranges::find_if(
      requested_permissions_, [&](const RequestedPermission &item) {
        return item.capability == capability &&
               item.operations.contains(operation);
      });
  if (!host_snapshot_received_ || found == requested_permissions_.end())
    return false;
  const auto index = found->operations.indexOf(operation);
  return index >= 0 &&
         found->operation_states[static_cast<std::size_t>(index)] ==
             snapshot_wire::GrantState::granted;
}

QString QmlBrokerApi::permissionState(const QString &capability,
                                      const QString &operation) const {
  const auto found = std::ranges::find_if(
      requested_permissions_, [&](const RequestedPermission &item) {
        return item.capability == capability &&
               item.operations.contains(operation);
      });
  if (found == requested_permissions_.end())
    return QStringLiteral("unrequested");
  if (!host_snapshot_received_)
    return QStringLiteral("unavailable");
  const auto index = found->operations.indexOf(operation);
  return permission_state(
      found->operation_states[static_cast<std::size_t>(index)]);
}

void QmlBrokerApi::setPackagedAssetRoot(std::filesystem::path root) {
  packaged_asset_root_ = std::filesystem::absolute(std::move(root)).lexically_normal();
}

bool QmlBrokerApi::bindSurfaceIntentSink(SurfaceIntentSink &sink) {
  if (surface_intent_sink_ != nullptr)
    return false;
  surface_intent_sink_ = &sink;
  return true;
}

bool QmlBrokerApi::requestSurfaceIntent(const QString &targetSurface,
                                        const QString &action) {
  return requestSurfaceIntent(targetSurface, action, {});
}

bool QmlBrokerApi::requestSurfaceIntent(const QString &targetSurface,
                                        const QString &action,
                                        const QVariantMap &data) {
  if (status_ != QStringLiteral("ready") || surface_intent_sink_ == nullptr ||
      targetSurface.isEmpty())
    return false;
  const auto encoded_target = targetSurface.toUtf8().toStdString();
  if (!wire::valid_surface_name(encoded_target))
    return false;
  surface::SurfaceIntentAction parsed;
  if (action == QStringLiteral("open"))
    parsed = surface::SurfaceIntentAction::open;
  else if (action == QStringLiteral("toggle"))
    parsed = surface::SurfaceIntentAction::toggle;
  else if (action == QStringLiteral("dismiss"))
    parsed = surface::SurfaceIntentAction::dismiss;
  else
    return false;
  const auto bounded_data = bounded_surface_intent_data(data);
  if (!bounded_data || (parsed != surface::SurfaceIntentAction::dismiss &&
                        !trusted_gesture_))
    return false;
  const auto source = parsed == surface::SurfaceIntentAction::dismiss
                          ? std::nullopt
                          : trusted_gesture_;
  const bool sent = surface_intent_sink_->request_surface_intent(
      source, encoded_target, parsed, *bounded_data);
  if (source) {
    if (deferred_gesture_ && deferred_gesture_->claim == *source)
      deferred_gesture_.reset();
    trusted_gesture_.reset();
  }
  return sent;
}

QString QmlBrokerApi::readPackagedText(const QString &relativePath,
                                       int maximumBytes) const {
  if (packaged_asset_root_.empty() || maximumBytes < 1 ||
      maximumBytes > 512 * 1024 || relativePath.isEmpty() ||
      relativePath.size() > 240 || relativePath.contains(QChar::Null))
    return {};
  const auto relative = std::filesystem::path(relativePath.toStdString());
  if (relative.is_absolute() || relative.empty()) return {};
  for (const auto &component : relative) {
    const auto value = component.string();
    if (value.empty() || value == "." || value == "..") return {};
  }
  const auto candidate = (packaged_asset_root_ / relative).lexically_normal();
  auto current = packaged_asset_root_;
  std::error_code error;
  for (const auto &component : relative) {
    current /= component;
    if (std::filesystem::is_symlink(std::filesystem::symlink_status(current, error)) ||
        error)
      return {};
  }
  if (!std::filesystem::is_regular_file(candidate, error) || error) return {};
  const auto size = std::filesystem::file_size(candidate, error);
  if (error || size == 0 || size > static_cast<std::uintmax_t>(maximumBytes))
    return {};
  std::ifstream input(candidate, std::ios::binary);
  std::string bytes(size, '\0');
  input.read(bytes.data(), static_cast<std::streamsize>(bytes.size()));
  if (!input || input.peek() != std::ifstream::traits_type::eof()) return {};
  const QByteArray encoded(bytes.data(), static_cast<qsizetype>(bytes.size()));
  QStringDecoder decoder(QStringDecoder::Utf8);
  const auto decoded = decoder.decode(encoded);
  return decoder.hasError() ? QString{} : decoded;
}

QVariantMap QmlBrokerApi::permissions() const {
  QVariantMap result;
  for (const auto &item : requested_permissions_) {
    QVariantMap operations;
    for (qsizetype index = 0; index < item.operations.size(); ++index) {
      operations.insert(item.operations[index],
                        host_snapshot_received_
                            ? permission_state(item.operation_states[
                                  static_cast<std::size_t>(index)])
                            : QStringLiteral("unavailable"));
    }
    QVariantMap capability;
    capability.insert(QStringLiteral("required"), item.required);
    capability.insert(QStringLiteral("state"),
                      host_snapshot_received_
                          ? capability_state(item.operation_states)
                          : QStringLiteral("unavailable"));
    capability.insert(QStringLiteral("operations"), operations);
    result.insert(item.capability, capability);
  }
  return result;
}

QVariantMap QmlBrokerApi::settings() const { return settings_; }

QVariantMap QmlBrokerApi::presentation() const { return presentation_; }

bool QmlBrokerApi::applySettingsSnapshot(
    std::uint64_t envelope_generation, std::span<const std::byte> payload) {
  if (envelope_generation != activation_generation_ || !settings_.isEmpty())
    return false;
  const std::string bytes(reinterpret_cast<const char *>(payload.data()),
                          payload.size());
  const auto parsed =
      omarchy::plugins::manifest::parse_settings_entry(manifest_, bytes);
  if (!parsed)
    return false;
  settings_ = to_variant_settings(*parsed, manifest_.id);
  return true;
}

bool QmlBrokerApi::applyPresentationSnapshot(
    std::uint64_t envelope_generation, std::span<const std::byte> payload) {
  if (envelope_generation != activation_generation_ ||
      !presentation_.isEmpty())
    return false;
  const auto parsed = parse_presentation_snapshot(payload);
  if (!parsed)
    return false;
  presentation_ = *parsed;
  return true;
}

bool QmlBrokerApi::updateSettings(const QVariantMap &candidate) {
  if (!control_ || settings_.isEmpty() || settings_correlation_ != 0 ||
      status_ != QStringLiteral("ready"))
    return false;
  const auto parsed = from_variant_settings(manifest_, candidate);
  if (!parsed)
    return false;
  const auto canonical =
      omarchy::plugins::manifest::canonical_settings_entry(*parsed);
  const auto bytes = std::as_bytes(std::span(canonical));
  const auto correlation = next_settings_correlation_++;
  if (correlation == 0 ||
      !control_->send(wire::kSettingsUpdateMessage, bytes, correlation))
    return false;
  pending_settings_ = candidate;
  settings_correlation_ = correlation;
  return true;
}

bool QmlBrokerApi::receiveSettingsResult(ReceivedPacket packet) {
  if (!packet || packet.header.endpoint_role != wire::EndpointRole::control ||
      packet.header.message_type != wire::kSettingsUpdateResultMessage ||
      packet.header.launch_generation != activation_generation_ ||
      packet.header.correlation_id != settings_correlation_ ||
      packet.payload.size() != 1 || !packet.descriptors.empty())
    return false;
  const bool accepted = packet.payload.front() == std::byte{1};
  if (!accepted && packet.payload.front() != std::byte{0})
    return false;
  if (accepted) {
    settings_ = std::move(pending_settings_);
    emit settingsChanged();
  }
  pending_settings_.clear();
  settings_correlation_ = 0;
  return true;
}

qulonglong QmlBrokerApi::permissionGeneration() const {
  return activation_generation_;
}

bool QmlBrokerApi::applyPermissionSnapshot(
    std::uint64_t envelope_generation, std::span<const std::byte> payload) {
  if (host_snapshot_received_ || activation_generation_ == 0 ||
      envelope_generation != activation_generation_)
    return false;
  snapshot_wire::PermissionSnapshot snapshot;
  if (!snapshot_wire::decode(payload, snapshot) ||
      snapshot.manifest_request_fingerprint !=
          manifest_request_fingerprint_ ||
      snapshot.permissions.size() != requested_permissions_.size())
    return false;
  std::vector<std::vector<snapshot_wire::GrantState>> next;
  next.reserve(requested_permissions_.size());
  for (std::size_t index = 0; index < snapshot.permissions.size(); ++index) {
    const auto operation_count = requested_permissions_[index].operations.size();
    if (operation_count < 1 || operation_count > 16)
      return false;
    const auto valid_mask = operation_count == 16
                                ? std::numeric_limits<std::uint16_t>::max()
                                : static_cast<std::uint16_t>(
                                      (1U << operation_count) - 1U);
    if ((snapshot.permissions[index].operation_mask & ~valid_mask) != 0)
      return false;
    if (snapshot.permissions[index].state ==
            snapshot_wire::GrantState::denied &&
        snapshot.permissions[index].operation_mask != 0)
      return false;
    if (requested_permissions_[index].required &&
        snapshot.permissions[index].state !=
            snapshot_wire::GrantState::granted)
      return false;
    auto &states = next.emplace_back();
    states.reserve(static_cast<std::size_t>(operation_count));
    for (qsizetype operation = 0; operation < operation_count; ++operation) {
      states.push_back((snapshot.permissions[index].operation_mask &
                        (1U << operation)) != 0
                           ? snapshot.permissions[index].state
                           : snapshot_wire::GrantState::denied);
    }
  }
  for (std::size_t index = 0; index < next.size(); ++index)
    requested_permissions_[index].operation_states = std::move(next[index]);
  host_snapshot_received_ = true;
  return true;
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

QVariant QmlBrokerApi::invoke(const QString &capability,
                              const QString &operation,
                              const QVariantMap &arguments) {
  if (capability == QStringLiteral("bash.execute"))
    return rejected(QStringLiteral("Use runtime.execute for commands"));
  return dispatchInvoke(capability, operation, arguments);
}

QVariant QmlBrokerApi::dispatchInvoke(const QString &capability,
                                      const QString &operation,
                                      const QVariantMap &arguments) {
  if (status_ != QStringLiteral("ready") || encoder_ == nullptr)
    return rejected(QStringLiteral("broker-unavailable"));
  if (!broker_ready_)
    return rejected(QStringLiteral("broker-not-ready"));
  auto encoded = encoder_->encode(capability.toUtf8().toStdString(),
                                  operation.toUtf8().toStdString(), arguments);
  if (!encoded)
    return rejected(QStringLiteral("request-undeclared"));
  if (encoded->message_type == broker::kDynamicInvokeMessage &&
      trusted_gesture_) {
    omarchy::plugins::definitions::DynamicInvocation invocation;
    if (!omarchy::plugins::definitions::decode_dynamic_invocation(
            encoded->payload, invocation))
      return rejected(QStringLiteral("request-undeclared"));
    invocation.gesture = trusted_gesture_;
    std::array<std::byte,
               omarchy::plugins::definitions::kMaximumDynamicEnvelopeBytes>
        envelope{};
    std::size_t written = 0;
    if (!omarchy::plugins::definitions::encode_dynamic_invocation(
            invocation, envelope, written))
      return rejected(QStringLiteral("request-undeclared"));
    encoded->payload.assign(envelope.begin(), envelope.begin() + written);
  }
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

QVariant QmlBrokerApi::execute(const QString &runner, const QString &command,
                               const QStringList &arguments) {
  if (runner != QStringLiteral("bash") || command.isEmpty() ||
      command.size() > 128 || command.contains(QChar::Null) ||
      arguments.size() > 64)
    return rejected(QStringLiteral("Invalid command request"));
  const auto command_bytes = command.toUtf8();
  if (!bounded_text(command_bytes, 128, false) ||
      !std::ranges::all_of(command_bytes, [](char byte) {
        const auto value = static_cast<unsigned char>(byte);
        return (value >= 'a' && value <= 'z') ||
               (value >= '0' && value <= '9') || value == '-' || value == '_';
      }))
    return rejected(QStringLiteral("Invalid command request"));
  static const std::array forbidden_shells{
      std::string_view("bash"), std::string_view("dash"),
      std::string_view("fish"), std::string_view("sh"),
      std::string_view("zsh")};
  if (std::ranges::find(forbidden_shells, command_bytes.toStdString()) !=
      forbidden_shells.end())
    return rejected(QStringLiteral("Shell execution is not supported"));

  qsizetype total_bytes = command_bytes.size();
  QVariantList encoded_arguments;
  encoded_arguments.reserve(arguments.size());
  for (const auto &argument : arguments) {
    const auto bytes = argument.toUtf8();
    if (bytes.size() > 4096 || bytes.contains('\0') ||
        total_bytes > 16384 - bytes.size())
      return rejected(QStringLiteral("Invalid command request"));
    total_bytes += bytes.size();
    encoded_arguments.push_back(argument);
  }

  const auto request = std::ranges::find_if(
      manifest_.requests, [](const auto &candidate) {
        return candidate.capability == "bash.execute";
      });
  if (request == manifest_.requests.end() ||
      request->definition_generation == 0 ||
      std::ranges::find(request->operations, std::string("run")) ==
          request->operations.end())
    return rejected(QStringLiteral("Command execution was not declared"));

  const QVariantMap payload{
      {QStringLiteral("command"), command},
      {QStringLiteral("arguments"), encoded_arguments}};
  const QVariantMap invocation{
      {QStringLiteral("demandScope"),
       QString::fromStdString(request->canonical_scope)},
      {QStringLiteral("payload"), payload}};
  return dispatchInvoke(QStringLiteral("bash.execute"), QStringLiteral("run"),
                        invocation);
}

bool QmlBrokerApi::beginTrustedGestureForInput(
    const surface::InputEvent &event) {
  trusted_gesture_.reset();
  return std::visit(
      [this, &event](const auto &payload) {
        using Event = std::decay_t<decltype(payload)>;
        if constexpr (std::is_same_v<Event, surface::PointerButton>) {
          if (payload.state == surface::ButtonState::pressed) {
            deferred_gesture_.reset();
            beginTrustedGesture(event.surface.id, event.surface.generation,
                                event.sequence);
            if (!trusted_gesture_)
              return false;
            deferred_gesture_ = DeferredGesture{
                .claim = *trusted_gesture_,
                .kind = DeferredGestureKind::pointer,
                .pointer_button = payload.button};
            return true;
          }
          const bool matches =
              deferred_gesture_ &&
              deferred_gesture_->kind == DeferredGestureKind::pointer &&
              deferred_gesture_->claim.surface_id == event.surface.id &&
              deferred_gesture_->claim.surface_generation ==
                  event.surface.generation &&
              deferred_gesture_->pointer_button == payload.button;
          if (matches)
            trusted_gesture_ = deferred_gesture_->claim;
          deferred_gesture_.reset();
          return matches;
        }
        if constexpr (std::is_same_v<Event, surface::TouchFrame>) {
          if (payload.phase == surface::TouchFramePhase::begin) {
            deferred_gesture_.reset();
            beginTrustedGesture(event.surface.id, event.surface.generation,
                                event.sequence);
            if (!trusted_gesture_)
              return false;
            deferred_gesture_ = DeferredGesture{
                .claim = *trusted_gesture_,
                .kind = DeferredGestureKind::touch,
                .pointer_button = 0};
            return true;
          }
          if (payload.phase == surface::TouchFramePhase::end) {
            const bool matches =
                deferred_gesture_ &&
                deferred_gesture_->kind == DeferredGestureKind::touch &&
                deferred_gesture_->claim.surface_id == event.surface.id &&
                deferred_gesture_->claim.surface_generation ==
                    event.surface.generation;
            if (matches)
              trusted_gesture_ = deferred_gesture_->claim;
            deferred_gesture_.reset();
            return matches;
          }
          if (payload.phase == surface::TouchFramePhase::cancel)
            deferred_gesture_.reset();
          return false;
        }
        if constexpr (std::is_same_v<Event, surface::Key>) {
          if (payload.state == surface::ButtonState::pressed &&
              !payload.auto_repeat) {
            deferred_gesture_.reset();
            beginTrustedGesture(event.surface.id, event.surface.generation,
                                event.sequence);
            return trusted_gesture_.has_value();
          }
          return false;
        }
        if constexpr (std::is_same_v<Event, surface::Cancel>) {
          deferred_gesture_.reset();
        } else if constexpr (std::is_same_v<Event, surface::FocusChanged>) {
          if (!payload.focused)
            deferred_gesture_.reset();
        }
        return false;
      },
      event.payload);
}

void QmlBrokerApi::beginTrustedGesture(
    std::uint64_t surface_id, std::uint64_t surface_generation,
    std::uint64_t input_sequence) {
  deferred_gesture_.reset();
  if (surface_id == 0 || surface_generation == 0 || input_sequence == 0) {
    trusted_gesture_.reset();
    return;
  }
  trusted_gesture_ =
      omarchy::plugins::definitions::DynamicInvocation::GestureClaim{
          .surface_id = surface_id,
          .surface_generation = surface_generation,
          .input_sequence = input_sequence};
}

void QmlBrokerApi::endTrustedGesture() { trusted_gesture_.reset(); }

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
bool QmlBrokerApi::brokerReady() const { return broker_ready_; }
bool QmlBrokerApi::markBrokerReady() {
  if (status_ != QStringLiteral("ready") || broker_ready_ ||
      !host_snapshot_received_)
    return false;
  broker_ready_ = true;
  emit brokerReadyChanged();
  return true;
}
void QmlBrokerApi::disconnect(QString reason) {
  trusted_gesture_.reset();
  deferred_gesture_.reset();
  pending_settings_.clear();
  settings_correlation_ = 0;
  if (status_ != QStringLiteral("ready")) return;
  status_ = std::move(reason);
  if (broker_ready_) {
    broker_ready_ = false;
    emit brokerReadyChanged();
  }
  for (auto &pending : pending_) {
    if (pending.call != nullptr) {
      pending.call->reject(QStringLiteral("broker-disconnected"));
      notifyFinished(pending.call);
    }
    pending = {};
  }
}
} // namespace omarchy::plugin_runtime::worker
