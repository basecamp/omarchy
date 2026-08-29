#pragma once

#include "dynamic_activation.hpp"

#include <array>
#include <cstddef>
#include <cstdint>
#include <span>
#include <string_view>

namespace omarchy::plugin_runtime::providers {

namespace definitions = omarchy::plugins::definitions;
namespace permissions = omarchy::plugins::permissions;

inline constexpr std::size_t kMaximumRadioDirectoryBytes = 1024 * 1024;
inline constexpr std::size_t kMaximumRadioStations = 64;
inline constexpr std::size_t kMaximumRadioStreamUrlBytes = 2048;

struct RadioHttpsBackend {
  bool (*get)(std::string_view origin, std::string_view path,
              std::span<std::byte> output, std::size_t &written,
              void *context) noexcept = nullptr;
  void *context = nullptr;
};

struct RadioMediaBackend {
  bool (*play)(std::string_view stream_url, void *context) noexcept = nullptr;
  bool (*control)(std::string_view control, std::uint32_t value,
                  void *context) noexcept = nullptr;
  void *context = nullptr;
};

struct RadioProviderConfiguration {
  permissions::ActivationBinding binding;
  std::uint64_t fetch_epoch = 0;
  std::uint64_t media_epoch = 0;
  RadioHttpsBackend https;
  RadioMediaBackend media;
};

class RadioProvider {
public:
  explicit RadioProvider(RadioProviderConfiguration configuration);
  [[nodiscard]] definitions::DynamicAdapter fetch_adapter() noexcept;
  [[nodiscard]] definitions::DynamicAdapter media_adapter() noexcept;
  [[nodiscard]] std::size_t revoke_fetch(std::uint64_t new_epoch) noexcept;
  [[nodiscard]] std::size_t revoke_media(std::uint64_t new_epoch) noexcept;

private:
  struct StreamHandle {
    permissions::ActivationBinding binding;
    std::uint64_t fetch_epoch = 0;
    std::array<char, 33> token{};
    std::array<char, kMaximumRadioStreamUrlBytes> url{};
    std::array<char, 161> name{};
    std::size_t url_size = 0;
    std::size_t name_size = 0;
    bool occupied = false;
  };

  static bool dispatch_fetch(const definitions::AuthorizedDynamicRequest &,
                             std::span<std::byte>, std::size_t &,
                             void *) noexcept;
  static bool dispatch_media(const definitions::AuthorizedDynamicRequest &,
                             std::span<std::byte>, std::size_t &,
                             void *) noexcept;
  [[nodiscard]] bool authorized(
      const definitions::AuthorizedDynamicRequest &, std::string_view,
      std::string_view, std::uint64_t) const noexcept;
  [[nodiscard]] StreamHandle *issue_handle(std::string_view, std::string_view) noexcept;
  [[nodiscard]] const StreamHandle *find_handle(std::string_view) const noexcept;

  RadioProviderConfiguration configuration_;
  std::array<StreamHandle, kMaximumRadioStations> handles_{};
  std::uint64_t next_handle_ = 1;
  const StreamHandle *current_ = nullptr;
  std::uint32_t volume_ = 70;
  bool running_ = false;
  bool paused_ = false;
  bool muted_ = false;
};

} // namespace omarchy::plugin_runtime::providers
