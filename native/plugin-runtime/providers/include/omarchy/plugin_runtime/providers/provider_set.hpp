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
  std::uint64_t fake_service_epoch = 0;
  StorageBackend storage;
  NotificationBackend notification;
  AudioBackend audio;
};

enum class CompletionResult : std::uint8_t {
  completed,
  unknown,
  cancelled,
  output_too_small,
};

class ProviderSet {
public:
  explicit ProviderSet(ProviderConfiguration configuration);
  ProviderSet(const ProviderSet &) = delete;
  ProviderSet &operator=(const ProviderSet &) = delete;

  [[nodiscard]] broker::ProviderRegistry<7> registry() noexcept;

  [[nodiscard]] bool add_fake_status(std::uint32_t resource,
                                     std::uint32_t status,
                                     std::string_view text) noexcept;
  [[nodiscard]] CompletionResult
  complete_fake_list(std::uint64_t correlation, std::span<std::byte> output,
                     std::size_t &bytes_written) noexcept;
  [[nodiscard]] std::size_t revoke(const permissions::CapabilityKey &capability,
                                   std::uint64_t new_epoch) noexcept;

private:
  struct FakeStatus {
    std::uint32_t resource = 0;
    std::uint32_t id = 0;
    bool acknowledged = false;
    std::array<char, kMaximumFakeStatusTextBytes> text{};
    std::size_t text_size = 0;
  };

  struct PendingList {
    std::uint64_t correlation = 0;
    std::uint64_t grant_epoch = 0;
    std::uint32_t resource = 0;
    bool cancelled = false;
    bool occupied = false;
  };

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
  static broker::ProviderResult
  dispatch_fake_list(const broker::AuthorizedRequest &, std::span<std::byte>,
                     void *) noexcept;
  static broker::ProviderResult
  dispatch_fake_acknowledge(const broker::AuthorizedRequest &,
                            std::span<std::byte>, void *) noexcept;
  static bool cancel(std::uint64_t correlation, void *context) noexcept;

  [[nodiscard]] bool authorized(const broker::AuthorizedRequest &request,
                                std::uint64_t expected_epoch) const noexcept;
  [[nodiscard]] static bool exact_token(const permissions::Scope &scope,
                                        std::string_view token) noexcept;
  [[nodiscard]] static bool exact_resource(const permissions::Scope &scope,
                                           permissions::OperationId operation,
                                           std::uint32_t &resource) noexcept;

  ProviderConfiguration configuration_;
  std::array<FakeStatus, kMaximumFakeStatuses> statuses_{};
  std::size_t status_count_ = 0;
  std::array<PendingList, 16> pending_{};
};

} // namespace omarchy::plugin_runtime::providers
