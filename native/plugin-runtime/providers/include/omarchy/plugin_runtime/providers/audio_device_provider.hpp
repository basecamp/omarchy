#pragma once

#include "dynamic_activation.hpp"

#include <cstdint>
#include <span>
#include <string_view>

namespace omarchy::plugin_runtime::providers {

namespace definitions = omarchy::plugins::definitions;
namespace permissions = omarchy::plugins::permissions;

struct AudioDeviceStatus {
  std::string_view display_name;
  bool connected = false;
  int left = -1;
  int right = -1;
  int case_level = -1;
  std::string_view listening_mode;
  int adaptive_level = 0;
  bool conversation_awareness = false;
  bool one_bud_anc = false;
  std::string_view ear_detection;
  std::uint32_t supported_controls = 0;
};

inline constexpr std::uint32_t kListeningModeControl = 1U << 0;
inline constexpr std::uint32_t kAdaptiveLevelControl = 1U << 1;
inline constexpr std::uint32_t kConversationAwarenessControl = 1U << 2;
inline constexpr std::uint32_t kOneBudAncControl = 1U << 3;
inline constexpr std::uint32_t kEarDetectionControl = 1U << 4;

struct AudioDeviceBackend {
  bool (*observe)(AudioDeviceStatus &, void *) noexcept = nullptr;
  bool (*control)(std::string_view, std::string_view, void *) noexcept = nullptr;
  void *context = nullptr;
};

struct AudioDeviceProviderConfiguration {
  permissions::ActivationBinding binding;
  std::uint64_t observe_epoch = 0;
  std::uint64_t control_epoch = 0;
  AudioDeviceBackend backend;
};

class AudioDeviceProvider {
public:
  explicit AudioDeviceProvider(AudioDeviceProviderConfiguration configuration);
  [[nodiscard]] definitions::DynamicAdapter observe_adapter() noexcept;
  [[nodiscard]] definitions::DynamicAdapter control_adapter() noexcept;
  [[nodiscard]] bool revoke_observe(std::uint64_t new_epoch) noexcept;
  [[nodiscard]] bool revoke_control(std::uint64_t new_epoch) noexcept;

private:
  static bool dispatch_observe(const definitions::AuthorizedDynamicRequest &,
                               std::span<std::byte>, std::size_t &,
                               void *) noexcept;
  static bool dispatch_control(const definitions::AuthorizedDynamicRequest &,
                               std::span<std::byte>, std::size_t &,
                               void *) noexcept;
  [[nodiscard]] bool authorized(const definitions::AuthorizedDynamicRequest &,
                                std::string_view, std::string_view,
                                std::uint64_t) const noexcept;
  AudioDeviceProviderConfiguration configuration_;
};

} // namespace omarchy::plugin_runtime::providers
