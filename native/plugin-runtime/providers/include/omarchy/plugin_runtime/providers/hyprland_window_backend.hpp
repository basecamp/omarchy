#pragma once

#include "omarchy/plugin_runtime/providers/system_observe_provider.hpp"

#include <array>
#include <string_view>

namespace omarchy::plugin_runtime::providers {

struct HyprlandCommandBackend {
  bool (*read_json)(std::string_view argument, std::span<char> output,
                    std::size_t &written, void *context) noexcept = nullptr;
  void *context = nullptr;
};

class HyprlandWindowBackend {
public:
  explicit HyprlandWindowBackend(HyprlandCommandBackend command = {});
  [[nodiscard]] SystemObserveBackend configuration() noexcept;

private:
  static bool observe(SanitizedWindowSnapshot &, void *) noexcept;
  static bool process_command(std::string_view, std::span<char>, std::size_t &,
                              void *) noexcept;
  HyprlandCommandBackend command_;
  std::array<unsigned char, 32> identity_key_{};
};

} // namespace omarchy::plugin_runtime::providers
