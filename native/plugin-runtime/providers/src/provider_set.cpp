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

broker::ProviderRegistry<7> ProviderSet::registry() noexcept {
  broker::ProviderRegistry<7> result;
  const std::array entries{
      broker::ProviderEntry{OperationId::storage_read, dispatch_storage_read,
                            cancel, this},
      broker::ProviderEntry{OperationId::storage_write, dispatch_storage_write,
                            cancel, this},
      broker::ProviderEntry{OperationId::storage_remove,
                            dispatch_storage_remove, cancel, this},
      broker::ProviderEntry{OperationId::notification_send,
                            dispatch_notification, nullptr, this},
      broker::ProviderEntry{OperationId::audio_play_cue, dispatch_audio,
                            nullptr, this},
      broker::ProviderEntry{OperationId::fake_status_list, dispatch_fake_list,
                            cancel, this},
      broker::ProviderEntry{OperationId::fake_status_acknowledge,
                            dispatch_fake_acknowledge, cancel, this},
  };
  for (const auto &entry : entries) {
    if (!result.add(entry))
      return {};
  }
  return result;
}

bool ProviderSet::add_fake_status(std::uint32_t resource, std::uint32_t status,
                                  std::string_view text) noexcept {
  if (resource == 0 || status == 0 || status_count_ == statuses_.size() ||
      text.size() > kMaximumFakeStatusTextBytes ||
      !valid_utf8_text(text, false))
    return false;
  if (std::any_of(statuses_.begin(), statuses_.begin() + status_count_,
                  [resource, status](const auto &existing) {
                    return existing.resource == resource &&
                           existing.id == status;
                  }))
    return false;
  auto &entry = statuses_[status_count_++];
  entry.resource = resource;
  entry.id = status;
  entry.text_size = text.size();
  std::copy(text.begin(), text.end(), entry.text.begin());
  return true;
}

CompletionResult
ProviderSet::complete_fake_list(std::uint64_t correlation,
                                std::span<std::byte> output,
                                std::size_t &bytes_written) noexcept {
  bytes_written = 0;
  const auto found = std::find_if(
      pending_.begin(), pending_.end(), [correlation](const auto &entry) {
        return entry.occupied && entry.correlation == correlation;
      });
  if (found == pending_.end())
    return CompletionResult::unknown;
  if (found->cancelled ||
      found->grant_epoch != configuration_.fake_service_epoch) {
    *found = {};
    return CompletionResult::cancelled;
  }
  std::array<FakeStatusView, kMaximumFakeStatuses> views{};
  std::size_t count = 0;
  for (const auto &status : statuses_) {
    if (status.id == 0 || status.resource != found->resource)
      continue;
    views[count++] = {
        .id = status.id,
        .acknowledged = status.acknowledged,
        .text = std::string_view(status.text.data(), status.text_size),
    };
  }
  if (!encode_fake_status_result(
          std::span<const FakeStatusView>(views.data(), count), output,
          bytes_written))
    return CompletionResult::output_too_small;
  *found = {};
  return CompletionResult::completed;
}

std::size_t ProviderSet::revoke(const permissions::CapabilityKey &capability,
                                std::uint64_t new_epoch) noexcept {
  std::size_t cancelled = 0;
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
  } else if (capability_is(capability, "service.fake-status")) {
    if (new_epoch <= configuration_.fake_service_epoch)
      return 0;
    configuration_.fake_service_epoch = new_epoch;
    for (auto &pending : pending_) {
      if (pending.occupied && !pending.cancelled) {
        pending.cancelled = true;
        ++cancelled;
      }
    }
  }
  return cancelled;
}

bool ProviderSet::authorized(const broker::AuthorizedRequest &request,
                             std::uint64_t expected_epoch) const noexcept {
  return request.binding == configuration_.binding && expected_epoch > 0 &&
         request.grant_epoch == expected_epoch;
}

bool ProviderSet::exact_token(const permissions::Scope &scope,
                              std::string_view token) noexcept {
  const auto *tokens = std::get_if<permissions::TokenScope>(&scope);
  return tokens != nullptr && tokens->tokens.size() == 1 &&
         tokens->tokens.values().front().view() == token;
}

bool ProviderSet::exact_resource(const permissions::Scope &scope,
                                 permissions::OperationId operation,
                                 std::uint32_t &resource) noexcept {
  const auto *resources = std::get_if<permissions::ResourceScope>(&scope);
  if (resources == nullptr || resources->resources.size() != 1 ||
      resources->operations.size() != 1 ||
      !resources->operations.contains(operation))
    return false;
  resource = resources->resources.values().front();
  return resource != 0;
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
  if (request.operation != OperationId::notification_send ||
      !self.authorized(request, self.configuration_.notification_epoch) ||
      !exact_token(request.demand, "timer") ||
      self.configuration_.notification.send == nullptr ||
      !decode_notification(request.payload, decoded) ||
      !self.configuration_.notification.send(
          "timer", decoded.title, decoded.body,
          self.configuration_.notification.context))
    return {};
  return {.status = broker::ProviderStatus::completed, .bytes_written = 0};
}

broker::ProviderResult
ProviderSet::dispatch_audio(const broker::AuthorizedRequest &request,
                            std::span<std::byte>, void *context) noexcept {
  auto &self = *static_cast<ProviderSet *>(context);
  if (request.operation != OperationId::audio_play_cue ||
      !self.authorized(request, self.configuration_.audio_epoch) ||
      !exact_token(request.demand, "complete") || !request.payload.empty() ||
      self.configuration_.audio.play == nullptr ||
      !self.configuration_.audio.play("complete",
                                      self.configuration_.audio.context))
    return {};
  return {.status = broker::ProviderStatus::completed, .bytes_written = 0};
}

broker::ProviderResult
ProviderSet::dispatch_fake_list(const broker::AuthorizedRequest &request,
                                std::span<std::byte>, void *context) noexcept {
  auto &self = *static_cast<ProviderSet *>(context);
  std::uint32_t resource = 0;
  if (request.operation != OperationId::fake_status_list ||
      !self.authorized(request, self.configuration_.fake_service_epoch) ||
      !request.payload.empty() ||
      !exact_resource(request.demand, request.operation, resource) ||
      request.correlation == 0)
    return {};
  if (std::any_of(self.pending_.begin(), self.pending_.end(),
                  [&request](const auto &pending) {
                    return pending.occupied &&
                           pending.correlation == request.correlation;
                  }))
    return {};
  const auto free =
      std::find_if(self.pending_.begin(), self.pending_.end(),
                   [](const auto &pending) { return !pending.occupied; });
  if (free == self.pending_.end())
    return {};
  *free = {.correlation = request.correlation,
           .grant_epoch = request.grant_epoch,
           .resource = resource,
           .cancelled = false,
           .occupied = true};
  return {.status = broker::ProviderStatus::pending, .bytes_written = 0};
}

broker::ProviderResult
ProviderSet::dispatch_fake_acknowledge(const broker::AuthorizedRequest &request,
                                       std::span<std::byte>,
                                       void *context) noexcept {
  auto &self = *static_cast<ProviderSet *>(context);
  std::uint32_t resource = 0;
  FakeAcknowledgeRequest decoded{};
  if (request.operation != OperationId::fake_status_acknowledge ||
      !self.authorized(request, self.configuration_.fake_service_epoch) ||
      !exact_resource(request.demand, request.operation, resource) ||
      !decode_fake_acknowledge(request.payload, decoded))
    return {};
  const auto status = std::find_if(
      self.statuses_.begin(), self.statuses_.begin() + self.status_count_,
      [resource, &decoded](const auto &entry) {
        return entry.resource == resource && entry.id == decoded.status;
      });
  if (status == self.statuses_.begin() + self.status_count_)
    return {};
  status->acknowledged = true;
  return {.status = broker::ProviderStatus::completed, .bytes_written = 0};
}

bool ProviderSet::cancel(std::uint64_t correlation, void *context) noexcept {
  auto &self = *static_cast<ProviderSet *>(context);
  const auto pending =
      std::find_if(self.pending_.begin(), self.pending_.end(),
                   [correlation](const auto &entry) {
                     return entry.occupied && entry.correlation == correlation;
                   });
  if (pending == self.pending_.end())
    return false;
  pending->cancelled = true;
  return true;
}

} // namespace omarchy::plugin_runtime::providers
