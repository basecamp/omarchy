#include "omarchy/plugin_runtime/providers/radio_provider.hpp"

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>

#include <algorithm>
#include <array>
#include <cstring>
#include <iostream>
#include <stdexcept>
#include <string>

namespace {
using namespace omarchy::plugin_runtime::providers;
namespace definitions = omarchy::plugins::definitions;
namespace permissions = omarchy::plugins::permissions;

void require(bool condition, std::string_view message) {
  if (!condition) throw std::runtime_error(std::string(message));
}

permissions::Digest repeated(char value) {
  return permissions::Digest(std::string(64, value));
}

permissions::ActivationBinding binding(std::uint64_t generation = 7) {
  return {.plugin = permissions::PluginId("akshar.radio-atlas"),
          .revision = repeated('a'),
          .policy_fingerprint = repeated('b'),
          .generation = generation};
}

struct Effects {
  std::string played;
  std::string control;
  std::uint32_t value = 0;
};

bool https_get(std::string_view origin, std::string_view path,
               std::span<std::byte> output, std::size_t &written,
               void *) noexcept {
  constexpr std::string_view body =
      R"([{"stationuuid":"good","name":"Good FM","url_resolved":"https://radio.example/stream","country":"US","countrycode":"us","geo_lat":40.1,"geo_long":-87.2,"votes":9},{"stationuuid":"http","name":"Unsafe","url_resolved":"http://radio.example/stream"}])";
  if (origin != "https://all.api.radio-browser.info" ||
      path != "/json/stations/topvote/2?hidebroken=true&order=votes&reverse=true" ||
      output.size() < body.size()) return false;
  std::memcpy(output.data(), body.data(), body.size());
  written = body.size();
  return true;
}

bool play(std::string_view url, void *context) noexcept {
  static_cast<Effects *>(context)->played = url;
  return true;
}

bool control(std::string_view name, std::uint32_t value, void *context) noexcept {
  auto &effects = *static_cast<Effects *>(context);
  effects.control = name;
  effects.value = value;
  return true;
}

definitions::AuthorizedDynamicRequest request(
    std::string_view name, std::string_view digest, std::uint64_t epoch,
    std::string_view operation, std::string_view scope,
    std::span<const std::byte> payload) {
  return {.authorization = {.binding = binding(),
                            .definition = {.canonical_name = definitions::Name(name),
                                           .definition_generation = 1,
                                           .definition_digest = definitions::Digest(digest)},
                            .grant_epoch = epoch},
          .operation = operation,
          .demand_scope = scope,
          .payload = payload};
}

std::span<const std::byte> bytes(std::string_view value) {
  return std::as_bytes(std::span(value.data(), value.size()));
}
} // namespace

int main() {
  try {
    Effects effects;
    RadioProvider provider({.binding = binding(),
                            .fetch_epoch = 3,
                            .media_epoch = 4,
                            .https = {.get = https_get},
                            .media = {.play = play, .control = control,
                                      .context = &effects}});
    const std::string fetch_payload =
        R"({"operation":"radio-directory.world","limit":2})";
    auto fetch = request(
        "network.fetch",
        "1b1d34c104f5850ef21c6b16c6d71daa19fe3b7a35f38ab5892d640faf9f5874",
        3, "fetch",
        "{\"methods\":[\"GET\"],\"origins\":[\"https://all.api.radio-browser.info\"]}",
        bytes(fetch_payload));
    std::array<std::byte, 8192> output{};
    std::size_t written = 0;
    auto fetch_adapter = provider.fetch_adapter();
    require(fetch_adapter.dispatch(fetch, output, written,
                                   fetch_adapter.context),
            "authorized Radio Browser fetch failed");
    const auto result = QJsonDocument::fromJson(QByteArray(
        reinterpret_cast<const char *>(output.data()),
        static_cast<qsizetype>(written))).object();
    const auto stations = result.value("stations").toArray();
    require(result.value("version").toInt() == 1 && stations.size() == 1,
            "provider did not normalize and filter the directory");
    const auto station = stations.at(0).toObject();
    const auto handle = station.value("playbackHandle").toString().toStdString();
    require(!handle.empty() && !QJsonDocument(result).toJson().contains("radio.example"),
            "provider exposed a raw stream URL instead of an opaque handle");

    const std::string play_payload = "{\"handle\":\"" + handle + "\"}";
    auto play_request = request(
        "media.play-stream",
        "2c0698cd289b084479aa0992cd11ec191b651af0f837e1030aabfed3fdc4e4c9",
        4, "play",
        "{\"controls\":[\"pause\",\"stop\",\"mute\",\"volume\",\"status\"],\"sourceHandles\":[\"network.fetch\"]}",
        bytes(play_payload));
    auto media_adapter = provider.media_adapter();
    require(media_adapter.dispatch(play_request, output, written,
                                   media_adapter.context) &&
                effects.played == "https://radio.example/stream",
            "media adapter did not resolve the activation-bound opaque handle");
    const std::string volume_payload = R"({"control":"volume","value":55})";
    auto volume = request(
        "media.play-stream",
        "2c0698cd289b084479aa0992cd11ec191b651af0f837e1030aabfed3fdc4e4c9",
        4, "control", play_request.demand_scope, bytes(volume_payload));
    require(media_adapter.dispatch(volume, output, written,
                                   media_adapter.context) &&
                effects.control == "volume" && effects.value == 55,
            "bounded media control failed");
    auto spoofed = fetch;
    spoofed.authorization.binding = binding(8);
    require(!fetch_adapter.dispatch(spoofed, output, written,
                                    fetch_adapter.context),
            "cross-generation fetch reached the provider");
    require(provider.revoke_fetch(4) == 1 &&
                !media_adapter.dispatch(play_request, output, written,
                                        media_adapter.context),
            "fetch revocation did not invalidate opaque stream handles");
    std::cout << "radio provider: PASS\n";
    return 0;
  } catch (const std::exception &error) {
    std::cerr << error.what() << '\n';
    return 1;
  }
}
