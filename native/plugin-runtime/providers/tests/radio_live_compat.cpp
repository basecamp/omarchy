#include "omarchy/plugin_runtime/providers/radio_live_backend.hpp"
#include "omarchy/plugin_runtime/providers/radio_provider.hpp"

#include <QJsonDocument>
#include <QJsonArray>
#include <QJsonObject>
#include <QThread>

#include <array>
#include <iostream>
#include <stdexcept>
#include <string>

namespace {
using namespace omarchy::plugin_runtime::providers;
namespace definitions = omarchy::plugins::definitions;
namespace permissions = omarchy::plugins::permissions;

constexpr std::string_view kFetchDigest = "1b1d34c104f5850ef21c6b16c6d71daa19fe3b7a35f38ab5892d640faf9f5874";
constexpr std::string_view kMediaDigest = "2c0698cd289b084479aa0992cd11ec191b651af0f837e1030aabfed3fdc4e4c9";
constexpr std::string_view kFetchScope = "{\"methods\":[\"GET\"],\"origins\":[\"https://all.api.radio-browser.info\"]}";
constexpr std::string_view kMediaScope = "{\"controls\":[\"pause\",\"stop\",\"mute\",\"volume\",\"status\"],\"sourceHandles\":[\"network.fetch\"]}";

permissions::ActivationBinding binding() {
  return {.plugin = permissions::PluginId("akshar.radio-atlas"),
          .revision = permissions::Digest(std::string(64, 'a')),
          .policy_fingerprint = permissions::Digest(std::string(64, 'b')),
          .generation = 7};
}

std::span<const std::byte> bytes(std::string_view value) {
  return std::as_bytes(std::span(value.data(), value.size()));
}

definitions::AuthorizedDynamicRequest request(
    std::string_view name, std::string_view digest, std::uint64_t epoch,
    std::string_view operation, std::string_view scope,
    std::string_view payload) {
  return {.authorization = {.binding = binding(),
                            .definition = {.canonical_name = definitions::Name(name),
                                           .definition_generation = 1,
                                           .definition_digest = definitions::Digest(digest)},
                            .grant_epoch = epoch},
          .operation = operation,
          .demand_scope = scope,
          .payload = bytes(payload)};
}

void require(bool condition, std::string_view detail) {
  if (!condition) throw std::runtime_error(std::string(detail));
}
} // namespace

int main() try {
  RadioLiveBackend backend;
  RadioProvider provider({.binding = binding(), .fetch_epoch = 3,
                          .media_epoch = 4,
                          .https = backend.https_configuration(),
                          .media = backend.media_configuration()});
  std::array<std::byte, kMaximumRadioDirectoryBytes> output{};
  std::size_t written = 0;
  const auto fetch = request("network.fetch", kFetchDigest, 3, "fetch",
                             kFetchScope,
                             R"({"operation":"radio-directory.world","limit":64})");
  auto fetch_adapter = provider.fetch_adapter();
  require(fetch_adapter.dispatch(fetch, output, written, fetch_adapter.context),
          "live directory fetch failed");
  const auto directory_bytes = written;
  const auto document = QJsonDocument::fromJson(QByteArray(
      reinterpret_cast<const char *>(output.data()),
      static_cast<qsizetype>(written)));
  const auto stations = document.object().value("stations").toArray();
  require(!stations.isEmpty(), "live directory had no policy-compliant HTTPS station");
  const auto handle = stations.first().toObject().value("playbackHandle").toString();
  require(!handle.isEmpty() && !document.toJson(QJsonDocument::Compact).contains("https://"),
          "live result exposed stream authority instead of an opaque handle");
  auto media_adapter = provider.media_adapter();
  const std::string play_payload = "{\"handle\":\"" + handle.toStdString() + "\"}";
  const auto play = request("media.play-stream", kMediaDigest, 4, "play",
                            kMediaScope, play_payload);
  require(media_adapter.dispatch(play, output, written, media_adapter.context),
          "host-owned mpv did not start");
  QThread::msleep(1500);
  for (const auto &[payload, label] : std::array{
           std::pair{std::string_view(R"({"control":"volume","value":15})"), "volume"},
           std::pair{std::string_view(R"({"control":"pause"})"), "pause"},
           std::pair{std::string_view(R"({"control":"status"})"), "status"},
           std::pair{std::string_view(R"({"control":"stop"})"), "stop"}}) {
    const auto control = request("media.play-stream", kMediaDigest, 4,
                                 "control", kMediaScope, payload);
    require(media_adapter.dispatch(control, output, written, media_adapter.context),
            std::string("live media control failed: ") + label);
  }
  require(provider.revoke_fetch(4) >= 1 &&
              !media_adapter.dispatch(play, output, written, media_adapter.context),
          "live opaque handle survived fetch revocation");
  std::cout << "radio live compatibility: stations=" << stations.size()
            << " responseBytes=" << directory_bytes
            << " playback=started controls=volume,pause,status,stop revocation=denied\n";
  return 0;
} catch (const std::exception &error) {
  std::cerr << error.what() << '\n';
  return 1;
}
