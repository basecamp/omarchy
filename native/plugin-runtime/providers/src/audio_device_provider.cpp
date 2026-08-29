#include "omarchy/plugin_runtime/providers/audio_device_provider.hpp"

#include <QJsonDocument>
#include <QJsonObject>

#include <cstring>
#include <utility>

namespace omarchy::plugin_runtime::providers {
namespace {
constexpr std::string_view kObserveDefinition = "0813f3e80f26e2c2eed9254c325bca8a6be4980cee94056608cc243590de6c37";
constexpr std::string_view kControlDefinition = "c8449dbd2bfc12dc4f8b18aed658b85e6d461f2efe867f1dca90a63db2541e45";
constexpr std::string_view kObserveAdapter = "7976b6ac3e50b864e4ce8272a37053d7a6a5c5a35bae791a1b1235043cd72b2c";
constexpr std::string_view kControlAdapter = "d9865a5292df03c21e43ac977c2b4b5425627b4108a3321d154da0b991e54900";
constexpr std::string_view kObserveScope = "{\"fields\":[\"identity\",\"connection\",\"battery\",\"supported-controls\",\"listening-mode\",\"adaptive-level\",\"conversation-awareness\",\"one-bud-anc\",\"ear-detection\"],\"resourceClass\":\"paired-audio-device\",\"selection\":\"user-selected\"}";
constexpr std::string_view kControlScope = "{\"controls\":[\"set-listening-mode\",\"set-adaptive-level\",\"set-conversation-awareness\",\"set-one-bud-anc\",\"set-ear-detection\"],\"resourceClass\":\"paired-audio-device\",\"selection\":\"same-as:device.observe\"}";

bool copy(const QByteArray &bytes, std::span<std::byte> output,
          std::size_t &written) noexcept {
  written = 0;
  if (static_cast<std::size_t>(bytes.size()) > output.size()) return false;
  std::memcpy(output.data(), bytes.constData(), static_cast<std::size_t>(bytes.size()));
  written = static_cast<std::size_t>(bytes.size());
  return true;
}
}

AudioDeviceProvider::AudioDeviceProvider(AudioDeviceProviderConfiguration configuration)
    : configuration_(std::move(configuration)) {}

definitions::DynamicAdapter AudioDeviceProvider::observe_adapter() noexcept {
  return {.binding = {.adapter_class = definitions::Name("opaque-device-observer"),
                      .implementation_digest = definitions::Digest(kObserveAdapter),
                      .abi_version = 1},
          .dispatch = dispatch_observe, .context = this};
}

definitions::DynamicAdapter AudioDeviceProvider::control_adapter() noexcept {
  return {.binding = {.adapter_class = definitions::Name("opaque-device-controller"),
                      .implementation_digest = definitions::Digest(kControlAdapter),
                      .abi_version = 1},
          .dispatch = dispatch_control, .context = this};
}

bool AudioDeviceProvider::authorized(
    const definitions::AuthorizedDynamicRequest &request, std::string_view name,
    std::string_view digest, std::uint64_t epoch) const noexcept {
  return epoch > 0 && request.authorization.binding == configuration_.binding &&
         request.authorization.grant_epoch == epoch &&
         request.authorization.definition.canonical_name.view() == name &&
         request.authorization.definition.definition_generation == 1 &&
         request.authorization.definition.definition_digest.view() == digest;
}

bool AudioDeviceProvider::dispatch_observe(
    const definitions::AuthorizedDynamicRequest &request,
    std::span<std::byte> response, std::size_t &written, void *opaque) noexcept {
  auto &self = *static_cast<AudioDeviceProvider *>(opaque);
  written = 0;
  if (!self.authorized(request, "device.observe", kObserveDefinition,
                       self.configuration_.observe_epoch) ||
      request.operation != "observe" || request.demand_scope != kObserveScope ||
      self.configuration_.backend.observe == nullptr)
    return false;
  AudioDeviceStatus status;
  if (!self.configuration_.backend.observe(status,
                                            self.configuration_.backend.context))
    return copy(QByteArrayLiteral("{\"ok\":false,\"error\":\"unavailable\"}"),
                response, written);
  const QJsonObject result{{"ok", true}, {"deviceName", QString::fromUtf8(status.display_name)},
                           {"connected", status.connected}, {"left", status.left},
                           {"right", status.right}, {"caseLevel", status.case_level},
                           {"mode", QString::fromUtf8(status.listening_mode)},
                           {"adaptiveLevel", status.adaptive_level}};
  return copy(QJsonDocument(result).toJson(QJsonDocument::Compact), response, written);
}

bool AudioDeviceProvider::dispatch_control(
    const definitions::AuthorizedDynamicRequest &request,
    std::span<std::byte> response, std::size_t &written, void *opaque) noexcept {
  auto &self = *static_cast<AudioDeviceProvider *>(opaque);
  written = 0;
  if (!self.authorized(request, "device.control", kControlDefinition,
                       self.configuration_.control_epoch) ||
      request.operation != "control" || request.demand_scope != kControlScope ||
      self.configuration_.backend.control == nullptr)
    return false;
  const auto document = QJsonDocument::fromJson(QByteArray(
      reinterpret_cast<const char *>(request.payload.data()),
      static_cast<qsizetype>(request.payload.size())));
  const auto object = document.object();
  const auto operation = object.value("operation").toString().toStdString();
  const auto value = object.value("value").toVariant().toString().toStdString();
  const bool valid_operation =
      operation == "set-listening-mode" || operation == "set-adaptive-level" ||
      operation == "set-conversation-awareness" ||
      operation == "set-one-bud-anc" || operation == "set-ear-detection";
  bool valid_value = !value.empty();
  if (operation == "set-adaptive-level") {
    bool converted = false;
    const auto level = QString::fromStdString(value).toInt(&converted);
    valid_value = converted && level >= 0 && level <= 100;
  }
  if (document.isNull() || object.size() != 2 || !valid_operation ||
      !valid_value ||
      !self.configuration_.backend.control(operation, value,
                                            self.configuration_.backend.context))
    return false;
  return copy(QByteArrayLiteral("{\"ok\":true}"), response, written);
}

bool AudioDeviceProvider::revoke_observe(std::uint64_t epoch) noexcept {
  if (epoch <= configuration_.observe_epoch) return false;
  configuration_.observe_epoch = epoch;
  return true;
}
bool AudioDeviceProvider::revoke_control(std::uint64_t epoch) noexcept {
  if (epoch <= configuration_.control_epoch) return false;
  configuration_.control_epoch = epoch;
  return true;
}
} // namespace omarchy::plugin_runtime::providers
