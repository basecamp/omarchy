#pragma once

#include "omarchy/plugin_runtime/providers/audio_device_provider.hpp"

#include <string>

namespace omarchy::plugin_runtime::providers {

// Trusted host-side view of one device selected during permission review.
// The BlueZ address is never returned through the provider response.
class BluezAudioBackend {
public:
  explicit BluezAudioBackend(std::string selected_address);
  [[nodiscard]] AudioDeviceBackend configuration() noexcept;
  [[nodiscard]] bool valid_selection() const noexcept;

private:
  static bool observe(AudioDeviceStatus &, void *) noexcept;
  static bool control(std::string_view, std::string_view, void *) noexcept;
  std::string selected_address_;
  std::string display_name_;
};

} // namespace omarchy::plugin_runtime::providers
