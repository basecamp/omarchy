#include "omarchy/plugin_runtime/providers/radio_provider.hpp"

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>

#include <algorithm>
#include <charconv>
#include <cstring>
#include <string>
#include <utility>

namespace omarchy::plugin_runtime::providers {
namespace {

constexpr std::string_view kOrigin = "https://all.api.radio-browser.info";
constexpr std::string_view kFetchScope = "{\"methods\":[\"GET\"],\"origins\":[\"https://all.api.radio-browser.info\"]}";
constexpr std::string_view kMediaScope = "{\"controls\":[\"pause\",\"stop\",\"mute\",\"volume\",\"status\"],\"sourceHandles\":[\"network.fetch\"]}";
constexpr std::string_view kFetchDefinition = "1b1d34c104f5850ef21c6b16c6d71daa19fe3b7a35f38ab5892d640faf9f5874";
constexpr std::string_view kMediaDefinition = "2c0698cd289b084479aa0992cd11ec191b651af0f837e1030aabfed3fdc4e4c9";
constexpr std::string_view kFetchAdapter = "ef88d37a4658ea47d16063d959e610c83c7bc353de779816be99019bee9d7fe0";
constexpr std::string_view kMediaAdapter = "ade7096c108ff7af2a11dc2fe0f925f51ff2422db7f8e833214afc576f3755df";

bool copy(const QByteArray &bytes, std::span<std::byte> output,
          std::size_t &written) noexcept {
  written = 0;
  if (static_cast<std::size_t>(bytes.size()) > output.size()) return false;
  std::memcpy(output.data(), bytes.constData(), static_cast<std::size_t>(bytes.size()));
  written = static_cast<std::size_t>(bytes.size());
  return true;
}

bool text(const QString &value, int maximum) {
  return !value.isEmpty() && value.size() <= maximum && !value.contains(QChar::Null);
}

} // namespace

RadioProvider::RadioProvider(RadioProviderConfiguration configuration)
    : configuration_(std::move(configuration)) {}

definitions::DynamicAdapter RadioProvider::fetch_adapter() noexcept {
  return {.binding = {.adapter_class = definitions::Name("bounded-https-fetch"),
                      .implementation_digest = definitions::Digest(kFetchAdapter),
                      .abi_version = 1},
          .dispatch = dispatch_fetch,
          .context = this};
}

definitions::DynamicAdapter RadioProvider::media_adapter() noexcept {
  return {.binding = {.adapter_class = definitions::Name("bounded-media-stream"),
                      .implementation_digest = definitions::Digest(kMediaAdapter),
                      .abi_version = 1},
          .dispatch = dispatch_media,
          .context = this};
}

bool RadioProvider::authorized(const definitions::AuthorizedDynamicRequest &request,
                               std::string_view name, std::string_view digest,
                               std::uint64_t epoch) const noexcept {
  return epoch > 0 && request.authorization.grant_epoch == epoch &&
         request.authorization.binding == configuration_.binding &&
         request.authorization.definition.canonical_name.view() == name &&
         request.authorization.definition.definition_generation == 1 &&
         request.authorization.definition.definition_digest.view() == digest;
}

RadioProvider::StreamHandle *RadioProvider::issue_handle(std::string_view url,
                                                         std::string_view name) noexcept {
  if (url.size() >= kMaximumRadioStreamUrlBytes || name.empty() || name.size() > 160)
    return nullptr;
  auto found = std::ranges::find_if(handles_, [](const auto &entry) { return !entry.occupied; });
  if (found == handles_.end()) return nullptr;
  const auto converted = std::to_chars(found->token.data(), found->token.data() + 32,
                                       next_handle_++, 16);
  if (converted.ec != std::errc{}) return nullptr;
  *converted.ptr = '\0';
  found->binding = configuration_.binding;
  found->fetch_epoch = configuration_.fetch_epoch;
  std::copy(url.begin(), url.end(), found->url.begin());
  std::copy(name.begin(), name.end(), found->name.begin());
  found->url_size = url.size();
  found->name_size = name.size();
  found->occupied = true;
  return &*found;
}

const RadioProvider::StreamHandle *RadioProvider::find_handle(std::string_view token) const noexcept {
  const auto found = std::ranges::find_if(handles_, [&](const auto &entry) {
    return entry.occupied && entry.binding == configuration_.binding &&
           entry.fetch_epoch == configuration_.fetch_epoch &&
           std::string_view(entry.token.data()) == token;
  });
  return found == handles_.end() ? nullptr : &*found;
}

bool RadioProvider::dispatch_fetch(const definitions::AuthorizedDynamicRequest &request,
                                   std::span<std::byte> response,
                                   std::size_t &written, void *context) noexcept {
  written = 0;
  auto &self = *static_cast<RadioProvider *>(context);
  if (!self.authorized(request, "network.fetch", kFetchDefinition,
                       self.configuration_.fetch_epoch) ||
      request.operation != "fetch" || request.demand_scope != kFetchScope ||
      self.configuration_.https.get == nullptr) return false;
  const auto document = QJsonDocument::fromJson(QByteArray(
      reinterpret_cast<const char *>(request.payload.data()),
      static_cast<qsizetype>(request.payload.size())));
  const auto object = document.object();
  const auto limit = object.value("limit").toInt();
  if (document.isNull() || object.size() != 2 ||
      object.value("operation").toString() != "radio-directory.world" ||
      limit <= 0 || limit > static_cast<int>(kMaximumRadioStations)) return false;
  std::array<std::byte, kMaximumRadioDirectoryBytes> raw{};
  std::size_t raw_size = 0;
  const std::string path = "/json/stations/topvote/" + std::to_string(limit) +
                           "?hidebroken=true&order=votes&reverse=true";
  if (!self.configuration_.https.get(kOrigin, path, raw, raw_size,
                                     self.configuration_.https.context) ||
      raw_size == 0 || raw_size > raw.size()) return false;
  const auto directory = QJsonDocument::fromJson(QByteArray(
      reinterpret_cast<const char *>(raw.data()), static_cast<qsizetype>(raw_size)));
  if (!directory.isArray() || directory.array().size() > limit) return false;
  QJsonArray stations;
  for (const auto &value : directory.array()) {
    const auto station = value.toObject();
    const auto uuid = station.value("stationuuid").toString();
    const auto name = station.value("name").toString().trimmed();
    const auto stream = station.value("url_resolved").toString();
    if (!text(uuid, 64) || !text(name, 160) || !stream.startsWith("https://") ||
        stream.size() >= static_cast<int>(kMaximumRadioStreamUrlBytes)) continue;
    const auto *handle = self.issue_handle(stream.toStdString(), name.toStdString());
    if (handle == nullptr) break;
    stations.append(QJsonObject{{"uuid", uuid}, {"name", name},
                                {"country", station.value("country").toString().left(96)},
                                {"countryCode", station.value("countrycode").toString().left(2).toUpper()},
                                {"latitude", station.value("geo_lat")},
                                {"longitude", station.value("geo_long")},
                                {"votes", station.value("votes").toInt()},
                                {"playbackHandle", QString::fromLatin1(handle->token.data())}});
  }
  return copy(QJsonDocument(QJsonObject{{"version", 1}, {"stations", stations}})
                  .toJson(QJsonDocument::Compact), response, written);
}

bool RadioProvider::dispatch_media(const definitions::AuthorizedDynamicRequest &request,
                                   std::span<std::byte> response,
                                   std::size_t &written, void *context) noexcept {
  written = 0;
  auto &self = *static_cast<RadioProvider *>(context);
  if (!self.authorized(request, "media.play-stream", kMediaDefinition,
                       self.configuration_.media_epoch) ||
      request.demand_scope != kMediaScope) return false;
  const auto document = QJsonDocument::fromJson(QByteArray(
      reinterpret_cast<const char *>(request.payload.data()),
      static_cast<qsizetype>(request.payload.size())));
  const auto object = document.object();
  bool accepted = false;
  if (request.operation == "play" && object.size() == 1) {
    const auto token = object.value("handle").toString().toStdString();
    const auto *handle = self.find_handle(token);
    accepted = handle != nullptr && self.configuration_.media.play != nullptr &&
               self.configuration_.media.play(
                   std::string_view(handle->url.data(), handle->url_size),
                   self.configuration_.media.context);
    if (accepted) {
      self.current_ = handle;
      self.running_ = true;
      self.paused_ = false;
    }
  } else if (request.operation == "control" &&
             (object.size() == 1 || object.size() == 2)) {
    const auto control = object.value("control").toString().toStdString();
    const auto value = object.value("value").toInt();
    const bool valid = control == "pause" || control == "stop" ||
                       control == "mute" || control == "status" ||
                       (control == "volume" && value >= 0 && value <= 100);
    accepted = valid && self.configuration_.media.control != nullptr &&
               self.configuration_.media.control(
                   control, static_cast<std::uint32_t>(std::max(value, 0)),
                   self.configuration_.media.context);
    if (accepted && control == "pause") self.paused_ = !self.paused_;
    else if (accepted && control == "stop") {
      self.running_ = false;
      self.paused_ = false;
    } else if (accepted && control == "mute") self.muted_ = !self.muted_;
    else if (accepted && control == "volume") self.volume_ = static_cast<std::uint32_t>(value);
  }
  if (!accepted) return false;
  const QString title = self.current_ == nullptr ? QString{} : QString::fromUtf8(
      self.current_->name.data(), static_cast<qsizetype>(self.current_->name_size));
  return copy(QJsonDocument(QJsonObject{{"accepted", true},
                                        {"running", self.running_},
                                        {"paused", self.paused_},
                                        {"muted", self.muted_},
                                        {"volume", static_cast<int>(self.volume_)},
                                        {"title", title}})
                  .toJson(QJsonDocument::Compact), response, written);
}

std::size_t RadioProvider::revoke_fetch(std::uint64_t new_epoch) noexcept {
  if (new_epoch <= configuration_.fetch_epoch) return 0;
  configuration_.fetch_epoch = new_epoch;
  std::size_t invalidated = 0;
  for (auto &handle : handles_) if (handle.occupied) { handle = {}; ++invalidated; }
  current_ = nullptr;
  return invalidated;
}

std::size_t RadioProvider::revoke_media(std::uint64_t new_epoch) noexcept {
  if (new_epoch <= configuration_.media_epoch) return 0;
  configuration_.media_epoch = new_epoch;
  return 0;
}

} // namespace omarchy::plugin_runtime::providers
