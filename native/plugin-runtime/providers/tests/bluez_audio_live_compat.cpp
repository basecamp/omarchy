#include "omarchy/plugin_runtime/providers/bluez_audio_backend.hpp"

#include <iostream>

using namespace omarchy::plugin_runtime;

int main(int argc, char **argv) {
  if (argc != 2) return 64;
  providers::BluezAudioBackend backend(argv[1]);
  const auto configuration = backend.configuration();
  providers::AudioDeviceStatus status;
  if (!backend.valid_selection() ||
      !configuration.observe(status, configuration.context))
    return 1;
  std::cout << "name=" << status.display_name << '\n'
            << "connected=" << (status.connected ? "true" : "false") << '\n'
            << "battery=unavailable\ncontrols=none\n";
}
