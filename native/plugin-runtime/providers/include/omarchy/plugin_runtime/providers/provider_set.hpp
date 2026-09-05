#pragma once

#include "omarchy/plugin_runtime/broker/broker_core.hpp"
#include "omarchy/plugin_runtime/providers/provider_schemas.hpp"

#include <array>
#include <cstddef>
#include <cstdint>
#include <span>
#include <string_view>
#include <type_traits>

namespace omarchy::plugin_runtime::providers {

namespace broker = omarchy::plugin_runtime::broker;
namespace permissions = omarchy::plugins::permissions;

using StorageRead = bool (*)(std::string_view, std::span<std::byte>,
                             std::size_t &, bool &, void *) noexcept;
using StorageWrite = bool (*)(std::string_view, std::span<const std::byte>,
                              void *) noexcept;
using StorageRemove = bool (*)(std::string_view, void *) noexcept;
using NotificationSend = bool (*)(std::string_view, std::string_view,
                                  std::string_view, std::string_view,
                                  void *) noexcept;
using AudioPlay = bool (*)(std::string_view, void *) noexcept;

static_assert(std::is_nothrow_invocable_r_v<bool, StorageRead, std::string_view,
                                            std::span<std::byte>, std::size_t &,
                                            bool &, void *>);
static_assert(
    std::is_nothrow_invocable_r_v<bool, StorageWrite, std::string_view,
                                  std::span<const std::byte>, void *>);
static_assert(std::is_nothrow_invocable_r_v<bool, StorageRemove,
                                            std::string_view, void *>);
static_assert(
    std::is_nothrow_invocable_r_v<bool, NotificationSend, std::string_view,
                                  std::string_view, std::string_view,
                                  std::string_view, void *>);
static_assert(
    std::is_nothrow_invocable_r_v<bool, AudioPlay, std::string_view, void *>);

struct StorageBackend {
  StorageRead read = nullptr;
  StorageWrite write = nullptr;
  StorageRemove remove = nullptr;
  void *context = nullptr;
  std::uint64_t maximum_total_bytes = 0;
  std::uint64_t maximum_item_bytes = 0;
};

struct NotificationBackend {
  NotificationSend send = nullptr;
  void *context = nullptr;
};

struct AudioBackend {
  AudioPlay play = nullptr;
  void *context = nullptr;
};

struct ProviderConfiguration {
  // The runtime replaces these authority fields from its verified snapshot;
  // backend callers cannot supply or extend provider authority.
  permissions::ActivationBinding binding{};
  permissions::RequestSet requests{};
  permissions::GrantSet grants{};
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
  [[nodiscard]] bool revoke(const permissions::CapabilityKey &capability,
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

  [[nodiscard]] bool
  authorized(const broker::AuthorizedRequest &request) const noexcept;
  [[nodiscard]] static std::string_view
  exact_token(const permissions::Scope &scope) noexcept;
  ProviderConfiguration configuration_;
  permissions::PermissionAuthority effect_authority_;
};

} // namespace omarchy::plugin_runtime::providers
