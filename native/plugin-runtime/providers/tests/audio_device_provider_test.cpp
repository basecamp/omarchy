#include "omarchy/plugin_runtime/providers/audio_device_provider.hpp"

#include <array>
#include <stdexcept>

namespace providers = omarchy::plugin_runtime::providers;
namespace definitions = omarchy::plugins::definitions;
namespace permissions = omarchy::plugins::permissions;

namespace {
void require(bool value, const char *message) { if (!value) throw std::runtime_error(message); }
permissions::Digest digest(char value) { return permissions::Digest(std::string(64, value)); }
permissions::ActivationBinding binding() { return {.plugin = permissions::PluginId("io.github.thisisgm.omapods"), .revision = digest('a'), .policy_fingerprint = digest('b'), .generation = 2}; }
bool observe(providers::AudioDeviceStatus &status, void *context) noexcept {
  if (!*static_cast<bool *>(context)) return false;
  status = {.display_name = "AirPods Pro", .connected = true, .left = 71,
            .right = 84, .case_level = 93, .listening_mode = "adaptive",
            .adaptive_level = 42, .conversation_awareness = true,
            .one_bud_anc = true, .ear_detection = "pause-one-out",
            .supported_controls = providers::kListeningModeControl |
                providers::kAdaptiveLevelControl};
  return true;
}
bool control(std::string_view operation, std::string_view value, void *) noexcept {
  return operation == "set-adaptive-level" && value == "54";
}
definitions::AuthorizedDynamicRequest request(std::string_view capability,
                                              std::string_view definition,
                                              std::uint64_t epoch,
                                              std::string_view operation,
                                              std::string_view scope,
                                              std::string_view payload) {
  return {.authorization = {.binding = binding(),
                            .definition = {.canonical_name = definitions::Name(capability),
                                           .definition_generation = 1,
                                           .definition_digest = definitions::Digest(definition)},
                            .grant_epoch = epoch},
          .operation = operation, .demand_scope = scope,
          .payload = std::as_bytes(std::span(payload.data(), payload.size()))};
}
}

int main() {
  bool available = true;
  providers::AudioDeviceProvider provider({.binding = binding(), .observe_epoch = 3,
      .control_epoch = 4, .backend = {.observe = observe, .control = control,
                                     .context = &available}});
  auto observer = provider.observe_adapter();
  auto observation = request("device.observe", "0813f3e80f26e2c2eed9254c325bca8a6be4980cee94056608cc243590de6c37", 3, "observe", "{\"fields\":[\"identity\",\"connection\",\"battery\",\"supported-controls\",\"listening-mode\",\"adaptive-level\",\"conversation-awareness\",\"one-bud-anc\",\"ear-detection\"],\"resourceClass\":\"paired-audio-device\",\"selection\":\"user-selected\"}", "{\"fields\":[]}");
  std::array<std::byte, 4096> output{}; std::size_t written = 0;
  require(observer.dispatch(observation, output, written, observer.context), "observe failed");
  const std::string result(reinterpret_cast<const char *>(output.data()), written);
  require(result.find("AirPods Pro") != std::string::npos &&
              result.find("set-adaptive-level") != std::string::npos &&
              result.find("D4:94") == std::string::npos,
          "observe leaked backend identity or lost bounded status");
  available = false;
  require(observer.dispatch(observation, output, written, observer.context) &&
              std::string(reinterpret_cast<const char *>(output.data()), written).find("unavailable") != std::string::npos,
          "no-device state was not typed");
  auto controller = provider.control_adapter();
  auto mutation = request("device.control", "c8449dbd2bfc12dc4f8b18aed658b85e6d461f2efe867f1dca90a63db2541e45", 4, "control", "{\"controls\":[\"set-listening-mode\",\"set-adaptive-level\",\"set-conversation-awareness\",\"set-one-bud-anc\",\"set-ear-detection\"],\"resourceClass\":\"paired-audio-device\",\"selection\":\"same-as:device.observe\"}", "{\"operation\":\"set-adaptive-level\",\"value\":54}");
  require(controller.dispatch(mutation, output, written, controller.context), "bounded control failed");
  auto spoofed = mutation; const std::string payload = "{\"operation\":\"connect\",\"value\":true}"; spoofed.payload = std::as_bytes(std::span(payload.data(), payload.size()));
  require(!controller.dispatch(spoofed, output, written, controller.context), "unlisted device control reached backend");
}
