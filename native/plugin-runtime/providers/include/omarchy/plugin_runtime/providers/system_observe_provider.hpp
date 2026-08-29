#pragma once

#include "dynamic_activation.hpp"

#include <array>
#include <cstdint>
#include <span>
#include <string>

namespace omarchy::plugin_runtime::providers {

namespace definitions = omarchy::plugins::definitions;
namespace permissions = omarchy::plugins::permissions;

inline constexpr std::size_t kMaximumObservedWindows = 64;

struct SanitizedWindowRectangle {
  std::uint64_t opaque_id = 0;
  std::int32_t x = 0;
  std::int32_t y = 0;
  std::uint32_t width = 0;
  std::uint32_t height = 0;
};

struct SanitizedWindowSnapshot {
  std::uint32_t width = 0;
  std::uint32_t height = 0;
  std::uint32_t reserved_bottom = 0;
  std::array<SanitizedWindowRectangle, kMaximumObservedWindows> windows{};
  std::size_t window_count = 0;
};

struct SystemObserveBackend {
  bool (*window_rectangles)(SanitizedWindowSnapshot &, void *) noexcept = nullptr;
  void *context = nullptr;
};

struct SystemObserveProviderConfiguration {
  permissions::ActivationBinding binding;
  std::uint64_t epoch = 0;
  SystemObserveBackend backend;
};

class SystemObserveProvider {
public:
  explicit SystemObserveProvider(SystemObserveProviderConfiguration configuration);
  [[nodiscard]] definitions::DynamicAdapter adapter() noexcept;
  [[nodiscard]] bool revoke(std::uint64_t new_epoch) noexcept;

private:
  static bool dispatch(const definitions::AuthorizedDynamicRequest &,
                       std::span<std::byte>, std::size_t &, void *) noexcept;
  SystemObserveProviderConfiguration configuration_;
};

} // namespace omarchy::plugin_runtime::providers
