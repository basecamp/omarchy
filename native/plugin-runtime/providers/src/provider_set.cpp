#include "omarchy/plugin_runtime/providers/provider_set.hpp"

#include <algorithm>
#include <array>
#include <variant>

namespace omarchy::plugin_runtime::providers {
namespace {

using OperationId = permissions::OperationId;

bool capability_is(const permissions::CapabilityKey &capability,
                   std::string_view id) noexcept {
  return capability.version == 1 && capability.id.view() == id;
}

} // namespace

ProviderSet::ProviderSet(ProviderConfiguration configuration)
    : configuration_(std::move(configuration)) {}

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

std::size_t ProviderSet::revoke(const permissions::CapabilityKey &capability,
                                std::uint64_t new_epoch) noexcept {
  if (capability_is(capability, "storage.private")) {
    if (new_epoch <= configuration_.storage_epoch)
      return 0;
    configuration_.storage_epoch = new_epoch;
  } else if (capability_is(capability, "notifications.send")) {
    if (new_epoch <= configuration_.notification_epoch)
      return 0;
    configuration_.notification_epoch = new_epoch;
  } else if (capability_is(capability, "audio.play-cue")) {
    if (new_epoch <= configuration_.audio_epoch)
      return 0;
    configuration_.audio_epoch = new_epoch;
  }
  return 0;
}

bool ProviderSet::authorized(const broker::AuthorizedRequest &request,
                             std::uint64_t expected_epoch) const noexcept {
  const auto *definition = permissions::find_operation(request.operation);
  return definition != nullptr &&
         request.authorization.capability == definition->key &&
         request.authorization.binding == configuration_.binding &&
         expected_epoch > 0 &&
         request.authorization.grant_epoch == expected_epoch;
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
      !self.authorized(request, self.configuration_.storage_epoch) ||
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
      !self.authorized(request, self.configuration_.storage_epoch) ||
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
      !self.authorized(request, self.configuration_.storage_epoch) ||
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
      !self.authorized(request, self.configuration_.notification_epoch) ||
      category.empty() ||
      self.configuration_.notification.send == nullptr ||
      !decode_notification(request.payload, decoded) ||
      !self.configuration_.notification.send(
          category, decoded.title, decoded.body,
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
      !self.authorized(request, self.configuration_.audio_epoch) ||
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
