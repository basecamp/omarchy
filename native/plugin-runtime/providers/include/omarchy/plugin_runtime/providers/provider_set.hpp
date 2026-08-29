#pragma once

#include "omarchy/plugin_runtime/broker/broker_core.hpp"
#include "omarchy/plugin_runtime/providers/provider_schemas.hpp"

#include <array>
#include <cstddef>
#include <cstdint>
#include <span>
#include <string_view>

namespace omarchy::plugin_runtime::providers {

namespace broker = omarchy::plugin_runtime::broker;
namespace permissions = omarchy::plugins::permissions;

struct StorageBackend {
  bool (*read)(std::string_view key, std::span<std::byte> output,
               std::size_t &bytes_written, bool &found,
               void *context) noexcept = nullptr;
  bool (*write)(std::string_view key, std::span<const std::byte> value,
                void *context) noexcept = nullptr;
  bool (*remove)(std::string_view key, void *context) noexcept = nullptr;
  void *context = nullptr;
  std::uint64_t maximum_total_bytes = 0;
  std::uint64_t maximum_item_bytes = 0;
};

struct NotificationBackend {
  bool (*send)(std::string_view category, std::string_view title,
               std::string_view body, void *context) noexcept = nullptr;
  void *context = nullptr;
};

struct AudioBackend {
  bool (*play)(std::string_view cue, void *context) noexcept = nullptr;
  void *context = nullptr;
};

struct ProviderConfiguration {
  permissions::ActivationBinding binding;
  std::uint64_t storage_epoch = 0;
  std::uint64_t notification_epoch = 0;
  std::uint64_t audio_epoch = 0;
  StorageBackend storage;
  NotificationBackend notification;
  AudioBackend audio;
};

class ProviderSet {
public:
  explicit ProviderSet(ProviderConfiguration configuration);
  ProviderSet(const ProviderSet &) = delete;
  ProviderSet &operator=(const ProviderSet &) = delete;

  [[nodiscard]] broker::ProviderRegistry<5> registry() noexcept;
  [[nodiscard]] std::size_t revoke(const permissions::CapabilityKey &capability,
                                   std::uint64_t new_epoch) noexcept;

private:
  static broker::ProviderResult
  dispatch_storage_read(const broker::AuthorizedRequest &, std::span<std::byte>,
                        void *) noexcept;
  static broker::ProviderResult
  dispatch_storage_write(const broker::AuthorizedRequest &,
                         std::span<std::byte>, void *) noexcept;
  static broker::ProviderResult
  dispatch_storage_remove(const broker::AuthorizedRequest &,
                          std::span<std::byte>, void *) noexcept;
  static broker::ProviderResult
  dispatch_notification(const broker::AuthorizedRequest &, std::span<std::byte>,
                        void *) noexcept;
  static broker::ProviderResult
  dispatch_audio(const broker::AuthorizedRequest &, std::span<std::byte>,
                 void *) noexcept;
  static bool cancel_synchronous(std::uint64_t, void *) noexcept;

  [[nodiscard]] bool authorized(const broker::AuthorizedRequest &request,
                                std::uint64_t expected_epoch) const noexcept;
  [[nodiscard]] static std::string_view
  exact_token(const permissions::Scope &scope) noexcept;
  ProviderConfiguration configuration_;
};

} // namespace omarchy::plugin_runtime::providers
