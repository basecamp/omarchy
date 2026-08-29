#pragma once

#include "omarchy/plugin_runtime/providers/radio_provider.hpp"

#include <QProcess>

#include <memory>

namespace omarchy::plugin_runtime::providers {

// Host-owned implementation for the bounded Radio Browser and media contracts.
// The plugin receives neither network access, stream URLs, nor a player process.
class RadioLiveBackend {
public:
  RadioLiveBackend();
  ~RadioLiveBackend();
  RadioLiveBackend(const RadioLiveBackend &) = delete;
  RadioLiveBackend &operator=(const RadioLiveBackend &) = delete;

  [[nodiscard]] RadioHttpsBackend https_configuration() noexcept;
  [[nodiscard]] RadioMediaBackend media_configuration() noexcept;

private:
  static bool get(std::string_view, std::string_view, std::span<std::byte>,
                  std::size_t &, void *) noexcept;
  static bool play(std::string_view, void *) noexcept;
  static bool control(std::string_view, std::uint32_t, void *) noexcept;

  QProcess player_;
};

} // namespace omarchy::plugin_runtime::providers
