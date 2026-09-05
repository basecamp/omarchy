#include "omarchy/plugin_runtime/providers/provider_set.hpp"

#include <algorithm>
#include <array>
#include <limits>
#include <variant>

namespace omarchy::plugin_runtime::providers {
namespace {

using OperationId = permissions::OperationId;

bool capability_is(const permissions::CapabilityKey &capability,
                   std::string_view id) noexcept {
  return capability.version == 1 && capability.id.view() == id;
}

std::uint64_t configured_epoch(const ProviderConfiguration &configuration,
                               OperationId operation) noexcept {
  switch (operation) {
  case OperationId::storage_read:
  case OperationId::storage_write:
  case OperationId::storage_remove:
    return configuration.storage_epoch;
  case OperationId::notification_send:
    return configuration.notification_epoch;
  case OperationId::audio_play_cue:
    return configuration.audio_epoch;
  }
  return 0;
}

} // namespace

ProviderSet::ProviderSet(ProviderConfiguration configuration)
    : configuration_(std::move(configuration)),
      effect_authority_(
          configuration_.binding, configuration_.requests,
          configuration_.grants,
          permissions::PermissionAuthority::ValidatedCombinedPolicy{}) {}

broker::ProviderRegistry<5> ProviderSet::registry() noexcept {
  broker::ProviderRegistry<5> result;
  const std::array entries{
      broker::ProviderEntry{OperationId::storage_read, dispatch_storage_read,
                            cancel_synchronous, this},
      broker::ProviderEntry{OperationId::storage_write, dispatch_storage_write,
                            cancel_synchronous, this},
      broker::ProviderEntry{OperationId::storage_remove,
                            dispatch_storage_remove, cancel_synchronous, this},
      broker::ProviderEntry{OperationId::notification_send,
                            dispatch_notification, nullptr, this},
      broker::ProviderEntry{OperationId::audio_play_cue, dispatch_audio,
                            nullptr, this},
  };
  for (const auto &entry : entries) {
    if (!result.add(entry))
      return {};
  }
  return result;
}

bool ProviderSet::revoke(const permissions::CapabilityKey &capability,
                         std::uint64_t new_epoch) noexcept {
  std::uint64_t *configured_epoch = nullptr;
  if (capability_is(capability, "storage.private"))
    configured_epoch = &configuration_.storage_epoch;
  else if (capability_is(capability, "notifications.send"))
    configured_epoch = &configuration_.notification_epoch;
  else if (capability_is(capability, "audio.play-cue"))
    configured_epoch = &configuration_.audio_epoch;
  if (configured_epoch == nullptr)
    return false;
  const auto current = std::ranges::find_if(
      effect_authority_.grants().values(), [&](const auto &grant) {
        return grant.capability == capability;
      });
  if (current == effect_authority_.grants().values().end() ||
      current->epoch == std::numeric_limits<std::uint64_t>::max() ||
      new_epoch != current->epoch + 1)
    return false;
  try {
    if (effect_authority_.revoke(capability) != new_epoch)
      return false;
  } catch (...) {
    return false;
  }
  *configured_epoch = new_epoch;
  return true;
}

bool ProviderSet::authorized(
    const broker::AuthorizedRequest &request) const noexcept {
  try {
    const auto decision = effect_authority_.authorize(
        request.operation, request.demand, request.authorization.binding, 0);
    return decision.allowed() &&
           request.authorization.binding == configuration_.binding &&
           request.authorization.capability == decision.capability &&
           request.authorization.grant_epoch == decision.grant_epoch &&
           decision.grant_epoch ==
               configured_epoch(configuration_, request.operation);
  } catch (...) {
    return false;
  }
}

std::string_view ProviderSet::exact_token(
    const permissions::Scope &scope) noexcept {
  const auto *tokens = std::get_if<permissions::TokenScope>(&scope);
  if (tokens == nullptr || tokens->tokens.size() != 1)
    return {};
  return tokens->tokens.values().front().view();
}

broker::ProviderResult
ProviderSet::dispatch_storage_read(const broker::AuthorizedRequest &request,
                                   std::span<std::byte> response,
                                   void *context) noexcept {
  auto &self = *static_cast<ProviderSet *>(context);
  const auto *quota = std::get_if<permissions::QuotaScope>(&request.demand);
  StorageReadRequest decoded{};
  if (request.operation != OperationId::storage_read ||
      !self.authorized(request) ||
      quota == nullptr ||
      quota->total_bytes > self.configuration_.storage.maximum_total_bytes ||
      quota->item_bytes > self.configuration_.storage.maximum_item_bytes ||
      self.configuration_.storage.read == nullptr ||
      !decode_storage_read(request.payload, decoded))
    return {};
  std::array<std::byte, kMaximumStorageValueBytes> value{};
  std::size_t value_size = 0;
  bool found = false;
  const auto maximum = static_cast<std::size_t>(
      std::min<std::uint64_t>(quota->item_bytes, value.size()));
  if (!self.configuration_.storage.read(
          decoded.key, std::span<std::byte>(value.data(), maximum), value_size,
          found, self.configuration_.storage.context) ||
      value_size > maximum || (!found && value_size != 0))
    return {};
  std::size_t written = 0;
  if (!encode_storage_read_result(
          found, std::span<const std::byte>(value.data(), value_size), response,
          written))
    return {};
  return {.status = broker::ProviderStatus::completed,
          .bytes_written = written};
}

broker::ProviderResult
ProviderSet::dispatch_storage_write(const broker::AuthorizedRequest &request,
                                    std::span<std::byte>,
                                    void *context) noexcept {
  auto &self = *static_cast<ProviderSet *>(context);
  const auto *quota = std::get_if<permissions::QuotaScope>(&request.demand);
  StorageWriteRequest decoded{};
  if (request.operation != OperationId::storage_write ||
      !self.authorized(request) ||
      quota == nullptr ||
      quota->total_bytes > self.configuration_.storage.maximum_total_bytes ||
      quota->item_bytes > self.configuration_.storage.maximum_item_bytes ||
      self.configuration_.storage.write == nullptr ||
      !decode_storage_write(request.payload, decoded) ||
      decoded.value.size() > quota->item_bytes ||
      !self.configuration_.storage.write(decoded.key, decoded.value,
                                         self.configuration_.storage.context))
    return {};
  return {.status = broker::ProviderStatus::completed, .bytes_written = 0};
}

broker::ProviderResult
ProviderSet::dispatch_storage_remove(const broker::AuthorizedRequest &request,
                                     std::span<std::byte>,
                                     void *context) noexcept {
  auto &self = *static_cast<ProviderSet *>(context);
  const auto *quota = std::get_if<permissions::QuotaScope>(&request.demand);
  StorageReadRequest decoded{};
  if (request.operation != OperationId::storage_remove ||
      !self.authorized(request) ||
      quota == nullptr ||
      quota->total_bytes > self.configuration_.storage.maximum_total_bytes ||
      quota->item_bytes > self.configuration_.storage.maximum_item_bytes ||
      self.configuration_.storage.remove == nullptr ||
      !decode_storage_read(request.payload, decoded) ||
      !self.configuration_.storage.remove(decoded.key,
                                          self.configuration_.storage.context))
    return {};
  return {.status = broker::ProviderStatus::completed, .bytes_written = 0};
}

broker::ProviderResult
ProviderSet::dispatch_notification(const broker::AuthorizedRequest &request,
                                   std::span<std::byte>,
                                   void *context) noexcept {
  auto &self = *static_cast<ProviderSet *>(context);
  NotificationRequest decoded{};
  const auto category = exact_token(request.demand);
  if (request.operation != OperationId::notification_send ||
      !self.authorized(request) ||
      category.empty() ||
      self.configuration_.notification.send == nullptr ||
      !decode_notification(request.payload, decoded) ||
      !self.configuration_.notification.send(
          self.configuration_.binding.plugin.view(), category, decoded.title,
          decoded.body,
          self.configuration_.notification.context))
    return {};
  return {.status = broker::ProviderStatus::completed, .bytes_written = 0};
}

broker::ProviderResult
ProviderSet::dispatch_audio(const broker::AuthorizedRequest &request,
                            std::span<std::byte>, void *context) noexcept {
  auto &self = *static_cast<ProviderSet *>(context);
  const auto cue = exact_token(request.demand);
  if (request.operation != OperationId::audio_play_cue ||
      !self.authorized(request) ||
      cue.empty() || !request.payload.empty() ||
      self.configuration_.audio.play == nullptr ||
      !self.configuration_.audio.play(cue, self.configuration_.audio.context))
    return {};
  return {.status = broker::ProviderStatus::completed, .bytes_written = 0};
}

bool ProviderSet::cancel_synchronous(std::uint64_t, void *) noexcept {
  return false;
}

} // namespace omarchy::plugin_runtime::providers
