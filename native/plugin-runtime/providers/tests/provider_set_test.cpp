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

  static bool notify(std::string_view plugin, std::string_view category,
                     std::string_view title, std::string_view body,
                     void *context) noexcept {
    auto &self = *static_cast<BackendProbe *>(context);
    if (plugin != "org.example.timer")
      return false;
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
dispatch(const broker::ProviderRegistry<5> &registry,
         permissions::OperationId operation,
         const permissions::ActivationBinding &activation,
         const permissions::Scope &demand, std::span<const std::byte> payload,
         std::uint64_t epoch, std::uint64_t correlation,
         std::span<std::byte> response = {}) {
  const auto *entry = registry.find(operation);
  require(entry != nullptr, "provider missing from registry");
  const auto *definition = permissions::find_operation(operation);
  require(definition != nullptr, "operation definition missing");
  const broker::ProviderAuthorizationContext authorization{
      .binding = activation,
      .capability = definition->key,
      .grant_epoch = epoch};
  return entry->dispatch({.authorization = authorization,
                          .correlation = correlation,
                          .operation = operation,
                          .demand = demand,
                          .payload = payload},
                         response, entry->context);
}

} // namespace

int main() {
  using permissions::OperationId;
  BackendProbe backend;
  const auto activation = binding();
  permissions::RequestSet requests;
  requests.push_back({.capability = {
                          permissions::CapabilityId("storage.private"), 1},
                      .scope = quota(),
                      .required = true});
  permissions::TokenScope notification_scope;
  require(notification_scope.tokens.insert(permissions::ScopeToken("timer")) &&
              notification_scope.tokens.insert(permissions::ScopeToken("other")),
          "notification request fixture");
  requests.push_back(
      {.capability = {permissions::CapabilityId("notifications.send"), 1},
       .scope = notification_scope,
       .required = false});
  permissions::TokenScope audio_scope;
  require(audio_scope.tokens.insert(permissions::ScopeToken("complete")) &&
              audio_scope.tokens.insert(permissions::ScopeToken("evolve")),
          "audio request fixture");
  requests.push_back(
      {.capability = {permissions::CapabilityId("audio.play-cue"), 1},
       .scope = audio_scope,
       .required = true});
  permissions::GrantSet grants;
  grants.push_back({.capability = requests[0].capability,
                    .scope = requests[0].scope,
                    .state = permissions::GrantState::granted,
                    .epoch = 4});
  grants.push_back({.capability = requests[1].capability,
                    .scope = requests[1].scope,
                    .state = permissions::GrantState::granted,
                    .epoch = 5});
  grants.push_back({.capability = requests[2].capability,
                    .scope = requests[2].scope,
                    .state = permissions::GrantState::granted,
                    .epoch = 6});
  const providers::ProviderConfiguration configuration{
      .binding = activation,
      .requests = requests,
      .grants = grants,
      .storage_epoch = 4,
      .notification_epoch = 5,
      .audio_epoch = 6,
      .storage = {.read = BackendProbe::read,
                  .write = BackendProbe::write,
                  .remove = BackendProbe::remove,
                  .context = &backend,
                  .maximum_total_bytes = 4096,
                  .maximum_item_bytes = 1024},
      .notification = {.send = BackendProbe::notify, .context = &backend},
      .audio = {.play = BackendProbe::audio, .context = &backend},
  };
  providers::ProviderSet set(configuration);
  const auto registry = set.registry();
  for (const auto operation :
       {OperationId::storage_read, OperationId::storage_write,
        OperationId::storage_remove, OperationId::notification_send,
        OperationId::audio_play_cue})
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
  auto wrong_revision = activation;
  wrong_revision.revision = digest('c');
  auto wrong_policy = activation;
  wrong_policy.policy_fingerprint = digest('d');
  auto wrong_generation = activation;
  ++wrong_generation.generation;
  for (const auto &stale : {wrong_revision, wrong_policy, wrong_generation})
    require(dispatch(registry, OperationId::storage_write, stale, quota(), write,
                     4, 60 + stale.generation)
                    .status == broker::ProviderStatus::failed,
            "stale activation identity reached storage");
  require(backend.writes == 1,
          "stale activation identity performed a provider effect");
  const auto *write_provider = registry.find(OperationId::storage_write);
  require(write_provider != nullptr, "storage write provider missing");
  const broker::ProviderAuthorizationContext substituted_capability{
      .binding = activation,
      .capability = permissions::CapabilityKey{
          .id = permissions::CapabilityId("notifications.send"), .version = 1},
      .grant_epoch = 4};
  require(write_provider
                  ->dispatch({.authorization = substituted_capability,
                              .correlation = 61,
                              .operation = OperationId::storage_write,
                              .demand = quota(),
                              .payload = write},
                             {}, write_provider->context)
                  .status == broker::ProviderStatus::failed &&
              backend.writes == 1,
          "foreign capability context reached storage");
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
                      .status == broker::ProviderStatus::completed &&
              backend.notifications == 2 &&
              backend.last == "other:Timer:Done\nNow",
          "grant-authorized notification category was not forwarded");
  require(dispatch(registry, OperationId::notification_send, activation,
                   token("plugin-chosen"), notification, 5, 120)
                      .status == broker::ProviderStatus::failed &&
              backend.notifications == 2,
          "plugin-chosen scope widened authoritative notification grant");

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
  require(dispatch(registry, OperationId::audio_play_cue, activation,
                   token("evolve"), {}, 6, 15)
                      .status == broker::ProviderStatus::completed &&
              backend.audio_plays == 2 && backend.last == "evolve",
          "grant-authorized packaged cue was not forwarded");

  require(set.revoke({permissions::CapabilityId("storage.private"), 1}, 5),
          "exact next storage revocation was rejected");
  require(!set.revoke({permissions::CapabilityId("storage.private"), 1}, 4),
          "non-monotonic revocation was accepted");
  require(dispatch(registry, OperationId::storage_read, activation, quota(),
                   read, 4, 26, response)
                  .status == broker::ProviderStatus::failed,
          "revoked storage epoch was reused");

  const broker::ProviderAuthorizationContext queued_authorization{
      .binding = activation,
      .capability = requests[1].capability,
      .grant_epoch = 5};
  const broker::AuthorizedRequest queued_notification{
      .authorization = queued_authorization,
      .correlation = 127,
      .operation = OperationId::notification_send,
      .demand = requests[1].scope,
      .payload = notification};
  require(set.revoke(requests[1].capability, 6),
          "exact next notification revocation was rejected");
  const auto *notification_provider =
      registry.find(OperationId::notification_send);
  require(notification_provider != nullptr &&
              notification_provider
                      ->dispatch(queued_notification, {},
                                 notification_provider->context)
                      .status == broker::ProviderStatus::failed &&
              backend.notifications == 2,
          "queued pre-revocation authority performed an effect");

  auto optional_denied = configuration;
  optional_denied.grants[1].state = permissions::GrantState::denied;
  providers::ProviderSet denied_set(optional_denied);
  require(dispatch(denied_set.registry(), OperationId::notification_send,
                   activation, token("timer"), notification, 5, 128)
                      .status == broker::ProviderStatus::failed &&
              backend.notifications == 2,
          "optional declaration was mistaken for provider authority");

  auto missing_backend = configuration;
  missing_backend.notification.send = nullptr;
  providers::ProviderSet missing_backend_set(missing_backend);
  require(dispatch(missing_backend_set.registry(),
                   OperationId::notification_send, activation, token("timer"),
                   notification, 5, 1281)
                      .status == broker::ProviderStatus::failed &&
              backend.notifications == 2,
          "missing provider implementation performed an effect");

  auto undeclared = configuration;
  undeclared.grants = {};
  providers::ProviderSet declaration_only(undeclared);
  require(dispatch(declaration_only.registry(), OperationId::storage_write,
                   activation, quota(), write, 4, 129)
                      .status == broker::ProviderStatus::failed &&
              backend.writes == 1,
          "required declaration was mistaken for provider authority");

  bool rejected_plugin_capability = false;
  try {
    auto spoofed = configuration;
    spoofed.requests = {};
    spoofed.grants = {};
    spoofed.requests.push_back(
        {.capability = {permissions::CapabilityId("plugin.chosen"), 1},
         .scope = permissions::NoScope{},
         .required = false});
    providers::ProviderSet invalid(std::move(spoofed));
    (void)invalid;
  } catch (...) {
    rejected_plugin_capability = true;
  }
  require(rejected_plugin_capability,
          "plugin-created capability name entered provider authority");

  bool rejected_definition_substitution = false;
  try {
    auto spoofed = configuration;
    spoofed.requests[0].capability.version = 2;
    spoofed.grants[0].capability.version = 2;
    providers::ProviderSet invalid(std::move(spoofed));
    (void)invalid;
  } catch (...) {
    rejected_definition_substitution = true;
  }
  require(rejected_definition_substitution,
          "same capability name with a foreign definition identity was accepted");

  broker::ProviderRegistry<2> unique;
  const auto *storage_provider = registry.find(OperationId::storage_write);
  require(storage_provider != nullptr && unique.add(*storage_provider) &&
              !unique.add(*storage_provider),
          "duplicate exact provider route was accepted");
  broker::ProviderRegistry<1> missing;
  require(missing.find(OperationId::storage_write) == nullptr &&
              !missing.add({.operation = static_cast<OperationId>(0xffff),
                            .dispatch = storage_provider->dispatch,
                            .cancel = storage_provider->cancel,
                            .context = storage_provider->context}),
          "missing or unknown provider definition gained authority");

  return 0;
}
