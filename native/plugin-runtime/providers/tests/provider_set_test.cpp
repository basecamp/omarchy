#include "omarchy/plugin_runtime/providers/provider_set.hpp"

#include <algorithm>
#include <array>
#include <cstddef>
#include <cstdint>
#include <stdexcept>
#include <string>
#include <string_view>
#include <vector>

namespace {

namespace broker = omarchy::plugin_runtime::broker;
namespace permissions = omarchy::plugins::permissions;
namespace providers = omarchy::plugin_runtime::providers;

void require(bool condition, std::string_view message) {
  if (!condition)
    throw std::runtime_error(std::string(message));
}

permissions::Digest digest(char value) {
  return permissions::Digest(std::string(64, value));
}

permissions::ActivationBinding
binding(std::string_view plugin = "org.example.timer") {
  return {.plugin = permissions::PluginId(plugin),
          .revision = digest('a'),
          .policy_fingerprint = digest('b'),
          .generation = 7};
}

permissions::QuotaScope quota(std::uint64_t total = 4096,
                              std::uint64_t item = 1024) {
  return {.total_bytes = total, .item_bytes = item};
}

permissions::TokenScope token(std::string_view value) {
  permissions::TokenScope scope;
  require(scope.tokens.insert(permissions::ScopeToken(value)),
          "duplicate token fixture");
  return scope;
}

permissions::ResourceScope resource(std::uint32_t value,
                                    permissions::OperationId operation) {
  permissions::ResourceScope scope;
  require(scope.resources.insert(value), "duplicate resource fixture");
  require(scope.operations.insert(operation), "duplicate operation fixture");
  return scope;
}

void put16(std::vector<std::byte> &bytes, std::size_t offset,
           std::uint16_t value) {
  bytes[offset] = static_cast<std::byte>(value >> 8U);
  bytes[offset + 1] = static_cast<std::byte>(value);
}

void put32(std::vector<std::byte> &bytes, std::size_t offset,
           std::uint32_t value) {
  for (std::size_t index = 0; index < 4; ++index)
    bytes[offset + index] =
        static_cast<std::byte>(value >> ((3U - index) * 8U));
}

std::vector<std::byte> read_payload(std::string_view key) {
  std::vector<std::byte> bytes(2 + key.size());
  put16(bytes, 0, static_cast<std::uint16_t>(key.size()));
  std::transform(key.begin(), key.end(), bytes.begin() + 2,
                 [](char value) { return static_cast<std::byte>(value); });
  return bytes;
}

std::vector<std::byte> write_payload(std::string_view key,
                                     std::span<const std::byte> value) {
  std::vector<std::byte> bytes(6 + key.size() + value.size());
  put16(bytes, 0, static_cast<std::uint16_t>(key.size()));
  put32(bytes, 2, static_cast<std::uint32_t>(value.size()));
  std::transform(key.begin(), key.end(), bytes.begin() + 6, [](char character) {
    return static_cast<std::byte>(character);
  });
  std::copy(value.begin(), value.end(), bytes.begin() + 6 + key.size());
  return bytes;
}

std::vector<std::byte> notification_payload(std::string_view title,
                                            std::string_view body) {
  std::vector<std::byte> bytes(4 + title.size() + body.size());
  put16(bytes, 0, static_cast<std::uint16_t>(title.size()));
  put16(bytes, 2, static_cast<std::uint16_t>(body.size()));
  std::transform(title.begin(), title.end(), bytes.begin() + 4,
                 [](char value) { return static_cast<std::byte>(value); });
  std::transform(body.begin(), body.end(), bytes.begin() + 4 + title.size(),
                 [](char value) { return static_cast<std::byte>(value); });
  return bytes;
}

struct BackendProbe {
  static bool read(std::string_view key, std::span<std::byte> output,
                   std::size_t &written, bool &found, void *context) noexcept {
    auto &self = *static_cast<BackendProbe *>(context);
    ++self.reads;
    found = key == self.key;
    written = found ? self.value_size : 0;
    if (written > output.size())
      return false;
    std::copy_n(self.value.begin(), written, output.begin());
    return true;
  }

  static bool write(std::string_view key, std::span<const std::byte> value,
                    void *context) noexcept {
    auto &self = *static_cast<BackendProbe *>(context);
    ++self.writes;
    if (value.size() > self.value.size())
      return false;
    self.key.assign(key);
    self.value_size = value.size();
    std::copy(value.begin(), value.end(), self.value.begin());
    return true;
  }

  static bool remove(std::string_view key, void *context) noexcept {
    auto &self = *static_cast<BackendProbe *>(context);
    ++self.removes;
    if (key != self.key)
      return false;
    self.key.clear();
    self.value_size = 0;
    return true;
  }

  static bool notify(std::string_view category, std::string_view title,
                     std::string_view body, void *context) noexcept {
    auto &self = *static_cast<BackendProbe *>(context);
    ++self.notifications;
    self.last = std::string(category) + ":" + std::string(title) + ":" +
                std::string(body);
    return true;
  }

  static bool audio(std::string_view cue, void *context) noexcept {
    auto &self = *static_cast<BackendProbe *>(context);
    ++self.audio_plays;
    self.last = std::string(cue);
    return true;
  }

  std::string key;
  std::array<std::byte, providers::kMaximumStorageValueBytes> value{};
  std::size_t value_size = 0;
  std::string last;
  int reads = 0;
  int writes = 0;
  int removes = 0;
  int notifications = 0;
  int audio_plays = 0;
};

broker::ProviderResult
dispatch(const broker::ProviderRegistry<7> &registry,
         permissions::OperationId operation,
         const permissions::ActivationBinding &activation,
         const permissions::Scope &demand, std::span<const std::byte> payload,
         std::uint64_t epoch, std::uint64_t correlation,
         std::span<std::byte> response = {}) {
  const auto *entry = registry.find(operation);
  require(entry != nullptr, "provider missing from registry");
  return entry->dispatch({.binding = activation,
                          .correlation = correlation,
                          .operation = operation,
                          .demand = demand,
                          .payload = payload,
                          .grant_epoch = epoch},
                         response, entry->context);
}

} // namespace

int main() {
  using permissions::OperationId;
  BackendProbe backend;
  const auto activation = binding();
  providers::ProviderSet set({
      .binding = activation,
      .storage_epoch = 4,
      .notification_epoch = 5,
      .audio_epoch = 6,
      .fake_service_epoch = 7,
      .storage = {.read = BackendProbe::read,
                  .write = BackendProbe::write,
                  .remove = BackendProbe::remove,
                  .context = &backend,
                  .maximum_total_bytes = 4096,
                  .maximum_item_bytes = 1024},
      .notification = {.send = BackendProbe::notify, .context = &backend},
      .audio = {.play = BackendProbe::audio, .context = &backend},
  });
  const auto registry = set.registry();
  for (const auto operation :
       {OperationId::storage_read, OperationId::storage_write,
        OperationId::storage_remove, OperationId::notification_send,
        OperationId::audio_play_cue, OperationId::fake_status_list,
        OperationId::fake_status_acknowledge})
    require(registry.find(operation) != nullptr,
            "closed provider set incomplete");

  const std::array value{std::byte{0xde}, std::byte{0xad}};
  const auto write = write_payload("state-1", value);
  require(dispatch(registry, OperationId::storage_write, activation, quota(),
                   write, 4, 1)
                      .status == broker::ProviderStatus::completed &&
              backend.writes == 1,
          "bounded storage write failed");
  std::array<std::byte, 64> response{};
  const auto read = read_payload("state-1");
  const auto read_result = dispatch(registry, OperationId::storage_read,
                                    activation, quota(), read, 4, 2, response);
  require(read_result.status == broker::ProviderStatus::completed &&
              read_result.bytes_written == 10 && response[0] == std::byte{1} &&
              response[8] == value[0] && response[9] == value[1],
          "storage read result was not exact");
  require(dispatch(registry, OperationId::storage_read, activation, quota(),
                   read, 4, 3, std::span<std::byte>(response).first(9))
                  .status == broker::ProviderStatus::failed,
          "undersized storage output was accepted");
  auto bad_key = read_payload("../state");
  require(dispatch(registry, OperationId::storage_read, activation, quota(),
                   bad_key, 4, 4, response)
                  .status == broker::ProviderStatus::failed,
          "path-like storage key was accepted");
  auto trailing = read;
  trailing.push_back(std::byte{0});
  require(dispatch(registry, OperationId::storage_read, activation, quota(),
                   trailing, 4, 5, response)
                  .status == broker::ProviderStatus::failed,
          "trailing storage bytes were accepted");
  const auto wrong_binding = binding("org.example.attacker");
  require(dispatch(registry, OperationId::storage_write, wrong_binding, quota(),
                   write, 4, 6)
                      .status == broker::ProviderStatus::failed &&
              backend.writes == 1,
          "foreign activation reached storage");
  require(dispatch(registry, OperationId::storage_write, activation, quota(),
                   write, 3, 7)
                      .status == broker::ProviderStatus::failed &&
              backend.writes == 1,
          "stale grant epoch reached storage");
  require(dispatch(registry, OperationId::storage_write, activation,
                   quota(8192, 1024), write, 4, 8)
                  .status == broker::ProviderStatus::failed,
          "provider backend authority was exceeded");
  std::vector<std::byte> large(1025);
  const auto oversized_value = write_payload("state-2", large);
  require(dispatch(registry, OperationId::storage_write, activation, quota(),
                   oversized_value, 4, 9)
                  .status == broker::ProviderStatus::failed,
          "oversized storage item was accepted");

  const auto notification = notification_payload("Timer", "Done\nNow");
  require(dispatch(registry, OperationId::notification_send, activation,
                   token("timer"), notification, 5, 10)
                      .status == broker::ProviderStatus::completed &&
              backend.notifications == 1 &&
              backend.last == "timer:Timer:Done\nNow",
          "registered notification failed");
  auto invalid_utf8 = notification_payload("Timer", "ok");
  invalid_utf8.back() = std::byte{0xc0};
  require(dispatch(registry, OperationId::notification_send, activation,
                   token("timer"), invalid_utf8, 5, 11)
                      .status == broker::ProviderStatus::failed &&
              backend.notifications == 1,
          "invalid UTF-8 reached notification backend");
  require(dispatch(registry, OperationId::notification_send, activation,
                   token("other"), notification, 5, 12)
                      .status == broker::ProviderStatus::failed &&
              backend.notifications == 1,
          "unregistered notification category reached backend");

  require(dispatch(registry, OperationId::audio_play_cue, activation,
                   token("complete"), {}, 6, 13)
                      .status == broker::ProviderStatus::completed &&
              backend.audio_plays == 1 && backend.last == "complete",
          "registered audio cue failed");
  require(dispatch(registry, OperationId::audio_play_cue, activation,
                   token("complete"), value, 6, 14)
                      .status == broker::ProviderStatus::failed &&
              backend.audio_plays == 1,
          "audio payload smuggled authority");

  require(set.add_fake_status(17, 100, "Deploy waiting"),
          "fake status setup failed");
  require(!set.add_fake_status(17, 100, "duplicate"),
          "duplicate fake status was accepted");
  const auto list_scope = resource(17, OperationId::fake_status_list);
  require(dispatch(registry, OperationId::fake_status_list, activation,
                   list_scope, {}, 7, 20)
                  .status == broker::ProviderStatus::pending,
          "fake list did not become cancellable work");
  std::size_t completed_bytes = 0;
  require(set.complete_fake_list(20, response, completed_bytes) ==
                  providers::CompletionResult::completed &&
              completed_bytes == 28 && response[1] == std::byte{1},
          "fake list result was not bounded and encoded");
  require(set.complete_fake_list(20, response, completed_bytes) ==
              providers::CompletionResult::unknown,
          "fake completion was reusable");
  require(dispatch(registry, OperationId::fake_status_list, activation,
                   list_scope, {}, 7, 30)
                  .status == broker::ProviderStatus::pending,
          "fake output retry fixture did not start");
  require(set.complete_fake_list(30, std::span<std::byte>(response).first(4),
                                 completed_bytes) ==
                  providers::CompletionResult::output_too_small &&
              set.complete_fake_list(30, response, completed_bytes) ==
                  providers::CompletionResult::completed,
          "bounded output retry lost or duplicated provider state");
  require(dispatch(registry, OperationId::fake_status_list, activation,
                   list_scope, {}, 7, 21)
                  .status == broker::ProviderStatus::pending,
          "second fake list did not start");
  const auto *list_provider = registry.find(OperationId::fake_status_list);
  require(list_provider != nullptr &&
              list_provider->cancel(21, list_provider->context) &&
              set.complete_fake_list(21, response, completed_bytes) ==
                  providers::CompletionResult::cancelled,
          "explicit cancellation did not suppress completion");
  require(dispatch(registry, OperationId::fake_status_list, activation,
                   list_scope, {}, 7, 22)
                  .status == broker::ProviderStatus::pending,
          "revocation fixture did not start");
  require(set.revoke({permissions::CapabilityId("service.fake-status"), 1},
                     8) == 1 &&
              set.complete_fake_list(22, response, completed_bytes) ==
                  providers::CompletionResult::cancelled,
          "revocation did not invalidate pending fake result");
  require(dispatch(registry, OperationId::fake_status_list, activation,
                   list_scope, {}, 7, 23)
                  .status == broker::ProviderStatus::failed,
          "revoked epoch started provider work");

  std::vector<std::byte> ack(4);
  put32(ack, 0, 100);
  const auto ack_scope = resource(17, OperationId::fake_status_acknowledge);
  require(dispatch(registry, OperationId::fake_status_acknowledge, activation,
                   ack_scope, ack, 8, 24)
                  .status == broker::ProviderStatus::completed,
          "fake acknowledgement failed after trusted epoch advance");
  put32(ack, 0, 999);
  require(dispatch(registry, OperationId::fake_status_acknowledge, activation,
                   ack_scope, ack, 8, 25)
                  .status == broker::ProviderStatus::failed,
          "unknown fake status was acknowledged");

  require(set.revoke({permissions::CapabilityId("storage.private"), 1}, 5) == 0,
          "synchronous storage invented cancellation");
  require(set.revoke({permissions::CapabilityId("storage.private"), 1}, 4) == 0,
          "non-monotonic revocation reported work");
  require(dispatch(registry, OperationId::storage_read, activation, quota(),
                   read, 4, 26, response)
                  .status == broker::ProviderStatus::failed,
          "revoked storage epoch was reused");

  return 0;
}
