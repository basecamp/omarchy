#include "omarchy/plugin_runtime/providers/bluez_audio_backend.hpp"

using namespace omarchy::plugin_runtime;

int main() {
  providers::BluezAudioBackend valid("00:11:22:AA:BB:CC");
  if (!valid.valid_selection()) return 1;
  const auto configuration = valid.configuration();
  if (configuration.observe == nullptr || configuration.control == nullptr)
    return 2;

  providers::BluezAudioBackend malformed("../../org/bluez/hci0");
  if (malformed.valid_selection()) return 3;
  providers::AudioDeviceStatus status;
  const auto malformed_configuration = malformed.configuration();
  if (malformed_configuration.observe(status, malformed_configuration.context))
    return 4;
}
