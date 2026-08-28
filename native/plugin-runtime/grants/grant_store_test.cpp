#include "grant_store.hpp"

#include <array>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>
#include <string_view>
#include <sys/stat.h>
#include <unistd.h>

namespace {

namespace grant = omarchy::plugins::grants;
namespace permission = omarchy::plugins::permissions;

void require(bool condition, std::string_view message) {
  if (!condition)
    throw std::runtime_error(std::string(message));
}

template <typename Operation>
void rejects(Operation operation, std::string_view expected) {
  try {
    operation();
  } catch (const std::exception &error) {
    require(std::string_view(error.what()).find(expected) !=
                std::string_view::npos,
            "rejection did not contain expected diagnostic");
    return;
  }
  throw std::runtime_error("operation unexpectedly succeeded");
}

class TemporaryDirectory {
public:
  TemporaryDirectory() {
    std::array<char, 64> pattern{};
    const std::string value = "/tmp/omarchy-grants-test.XXXXXX";
    std::copy(value.begin(), value.end(), pattern.begin());
    const auto *created = mkdtemp(pattern.data());
    if (created == nullptr)
      throw std::runtime_error("mkdtemp failed");
    path_ = created;
  }
  ~TemporaryDirectory() { std::filesystem::remove_all(path_); }
  TemporaryDirectory(const TemporaryDirectory &) = delete;
  TemporaryDirectory &operator=(const TemporaryDirectory &) = delete;
  [[nodiscard]] const std::filesystem::path &path() const { return path_; }

private:
  std::filesystem::path path_;
};

permission::Digest digest(char value) {
  return permission::Digest(std::string(64, value));
}

permission::CapabilityKey key(std::string_view id) {
  return {.id = permission::CapabilityId(id), .version = 1};
}

permission::TokenScope tokens(std::initializer_list<std::string_view> values) {
  permission::TokenScope result;
  for (const auto value : values)
    require(result.tokens.insert(permission::ScopeToken(value)),
            "test token was duplicated");
  return result;
}

grant::RequestBundle bundle(char revision, char source,
                            std::uint64_t generation,
                            permission::QuotaScope storage,
                            permission::TokenScope notifications,
                            bool notification_required = false) {
  permission::RequestSet requests;
  requests.push_back({.capability = key("storage.private"),
                      .scope = storage,
                      .required = true});
  requests.push_back({.capability = key("notifications.send"),
                      .scope = std::move(notifications),
                      .required = notification_required});
  requests.push_back({.capability = key("audio.play-cue"),
                      .scope = tokens({"ping"}),
                      .required = false});
  return grant::make_bundle(2, permission::PluginId("example.clock"),
                            digest(revision), digest(source), generation,
                            std::move(requests));
}

permission::ActivationBinding binding(const grant::RequestBundle &request) {
  return {.plugin = request.plugin,
          .revision = request.revision,
          .policy_fingerprint = permission::Digest(
              permission::policy_request_fingerprint(request.requests)),
          .generation = request.generation};
}

const grant::PluginGrants &only_plugin(const grant::StoreState &state) {
  require(state.plugins.size() == 1, "expected exactly one plugin");
  return state.plugins.front();
}

mode_t permissions(const std::filesystem::path &path) {
  struct stat metadata{};
  require(lstat(path.c_str(), &metadata) == 0, "cannot stat test path");
  return metadata.st_mode & 0777;
}

void lifecycle_and_monotonicity() {
  TemporaryDirectory temporary;
  const auto directory = temporary.path() / "state/grants";
  grant::GrantStore store(directory);
  const auto initial = store.read();
  require(initial.mutation_sequence == 0 && initial.plugins.empty(),
          "absent store must read as empty");
  require(!std::filesystem::exists(directory),
          "read and preview must not create state");

  permission::RequestSet schema_one_requests;
  schema_one_requests.push_back({.capability = key("audio.play-cue"),
                                 .scope = tokens({"ping"}),
                                 .required = false});
  rejects(
      [&] {
        (void)grant::make_bundle(1, permission::PluginId("example.clock"),
                                 digest('a'), digest('b'), 1,
                                 schema_one_requests);
      },
      "schema v1 is unsafe host code");

  auto first = bundle('a', 'b', 1, {.total_bytes = 4096, .item_bytes = 1024},
                      tokens({"normal", "urgent"}));
  const auto storage = key("storage.private");
  const auto notification = key("notifications.send");
  const auto preview = store.preview(first, storage);
  require(preview.expected_mutation_sequence == 0 &&
              preview.target == grant::TargetRevision::candidate &&
              preview.request_delta.size() == 3,
          "new plugin preview must expose complete delta");
  require(!std::filesystem::exists(directory),
          "preview must remain side-effect free");

  rejects(
      [&] {
        (void)store.decide(first, storage,
                           permission::Scope(permission::QuotaScope{
                               .total_bytes = 1, .item_bytes = 1}),
                           permission::UserDecision::deny,
                           permission::DecisionActor::interactive_cli, 100, 0);
      },
      "denial does not accept an alternate scope");

  rejects(
      [&] {
        (void)store.decide(first, storage, std::nullopt,
                           permission::UserDecision::grant,
                           permission::DecisionActor::reviewed_policy, 100, 0);
      },
      "unattended or reviewed-policy");
  require(!std::filesystem::exists(directory),
          "rejected unattended grant must not create state");

  const auto storage_result =
      store.decide(first, storage,
                   permission::Scope(permission::QuotaScope{.total_bytes = 2048,
                                                            .item_bytes = 512}),
                   permission::UserDecision::grant,
                   permission::DecisionActor::interactive_cli, 100, 0);
  require(storage_result.mutation_sequence == 1 &&
              storage_result.decision_sequence == 1 &&
              storage_result.grant.epoch == 1 &&
              storage_result.grant.state == permission::GrantState::granted,
          "first grant must start all monotonic counters at one");
  require(permissions(directory) == 0700 &&
              permissions(directory / "grants-v1.bin") == 0600 &&
              permissions(directory / "grants-v1.lock") == 0600,
          "store, data, and lock must be owner-only");

  rejects(
      [&] {
        (void)store.decide(first, notification, std::nullopt,
                           permission::UserDecision::deny,
                           permission::DecisionActor::interactive_cli, 101, 0);
      },
      "changed after permission preview");
  const auto after_stale = store.read();
  require(after_stale.mutation_sequence == 1 &&
              after_stale.decisions.size() == 1,
          "stale optimistic decision must not mutate state");

  auto notification_preview = store.preview(first, notification);
  const auto denied = store.decide(
      first, notification, std::nullopt, permission::UserDecision::deny,
      permission::DecisionActor::trusted_ui, 101,
      notification_preview.expected_mutation_sequence);
  require(denied.grant.epoch == 1 && denied.decision_sequence == 2,
          "first denial must have its own monotonic epoch");
  notification_preview = store.preview(first, notification);
  const auto allowed =
      store.decide(first, notification, permission::Scope(tokens({"normal"})),
                   permission::UserDecision::grant,
                   permission::DecisionActor::interactive_cli, 102,
                   notification_preview.expected_mutation_sequence);
  require(allowed.grant.epoch == 2 && allowed.decision_sequence == 3,
          "redecision must advance both counters");

  store.activate_candidate(binding(first));
  const auto active_state = store.read();
  require(only_plugin(active_state).active.has_value() &&
              !only_plugin(active_state).candidate.has_value(),
          "activation must promote candidate atomically");
  const auto active_json = grant::state_json(active_state);
  require(active_json == grant::state_json(store.read()),
          "persisted machine output must be deterministic");
  require(active_json.find("\"legacySchemaV1Safe\":false") != std::string::npos,
          "machine output must never portray schema v1 as safe");

  const auto revoked = store.revoke(first, notification);
  require(revoked.target == grant::TargetRevision::active &&
              revoked.grant.epoch == 3 &&
              revoked.grant.state == permission::GrantState::revoked &&
              revoked.action == permission::RevocationMode::deny_new,
          "live revocation must advance epoch and return broker action");
  require(store.read().decisions.size() == 3,
          "revocation is not a fabricated user decision");

  auto wrong_generation = first;
  wrong_generation.generation = 9;
  rejects([&] { (void)store.revoke(wrong_generation, notification); },
          "binding does not match");
  auto wrong_source = first;
  wrong_source.source_request_fingerprint = digest('9');
  rejects([&] { (void)store.preview(wrong_source, notification); },
          "source request fingerprint does not match");
  rejects(
      [&] {
        (void)store.decide(first, storage,
                           permission::Scope(permission::QuotaScope{
                               .total_bytes = 8192, .item_bytes = 2048}),
                           permission::UserDecision::grant,
                           permission::DecisionActor::interactive_cli, 103,
                           store.read().mutation_sequence);
      },
      "expands requested scope");

  auto update = bundle('c', 'd', 2, {.total_bytes = 4096, .item_bytes = 1024},
                       tokens({"normal", "urgent", "critical"}), true);
  const auto update_preview = store.preview(update, notification);
  bool requirement_changed = false;
  bool inherited_storage = false;
  for (const auto &entry : update_preview.request_delta.values()) {
    if (entry.capability == notification) {
      requirement_changed =
          entry.kind == permission::DeltaKind::requirement_changed;
      require(!entry.inherited_grant.has_value(),
              "changed authority must never inherit");
    }
    if (entry.capability == storage)
      inherited_storage = entry.kind == permission::DeltaKind::unchanged &&
                          entry.inherited_grant.has_value();
  }
  require(requirement_changed && inherited_storage,
          "update preview must expose changes and only safe inheritance");
  require(!only_plugin(store.read()).candidate.has_value(),
          "delta preview must precede candidate persistence");

  const auto update_denial = store.decide(
      update, notification, std::nullopt, permission::UserDecision::deny,
      permission::DecisionActor::interactive_cli, 104,
      update_preview.expected_mutation_sequence);
  require(update_denial.target == grant::TargetRevision::candidate &&
              update_denial.grant.epoch == 4,
          "candidate decision must preserve global revocation epoch");
  const auto update_state = store.read();
  require(only_plugin(update_state).active->binding == binding(first) &&
              only_plugin(update_state).candidate.has_value(),
          "candidate decisions must never replace active revision");
  const auto active_storage_revocation = store.revoke(first, storage);
  const auto candidate_storage_revocation = store.revoke(update, storage);
  require(active_storage_revocation.grant.epoch == 2 &&
              candidate_storage_revocation.grant.epoch == 3,
          "revocation must use the global epoch floor across revisions");
  rejects([&] { store.activate_candidate(binding(update)); },
          "required capability is not granted");
  require(only_plugin(store.read()).active->binding == binding(first),
          "failed activation must leave active intact");
  store.discard_candidate(update.plugin);
  require(only_plugin(store.read()).active->binding == binding(first) &&
              !only_plugin(store.read()).candidate.has_value(),
          "discard must preserve active grants");

  const auto empty_golden =
      "{\"schemaVersion\":1,\"securePluginSchemaVersion\":2,"
      "\"legacySchemaV1Safe\":false,\"mutationSequence\":0,"
      "\"nextDecisionSequence\":1,\"plugins\":[],\"decisions\":[]}";
  require(grant::state_json(grant::StoreState{}) == empty_golden,
          "empty JSON golden changed");
  require(grant::mutation_json(storage_result)
                  .find("\"decisionSequence\":1,\"target\":\"candidate\"") !=
              std::string::npos,
          "mutation JSON contract changed");
}

void hostile_filesystem() {
  TemporaryDirectory temporary;
  const auto directory = temporary.path() / "grants";
  grant::GrantStore store(directory);
  auto request = bundle('e', 'f', 1, {.total_bytes = 1024, .item_bytes = 256},
                        tokens({"normal"}));
  const auto capability = key("storage.private");
  const auto before = store.preview(request, capability);
  (void)store.decide(request, capability, std::nullopt,
                     permission::UserDecision::grant,
                     permission::DecisionActor::interactive_cli, 200,
                     before.expected_mutation_sequence);
  const auto known_json = grant::state_json(store.read());

  require(chmod((directory / "grants-v1.bin").c_str(), 0644) == 0,
          "chmod file failed");
  rejects([&] { (void)store.read(); }, "permits group or other access");
  require(chmod((directory / "grants-v1.bin").c_str(), 0600) == 0,
          "restore file mode failed");
  require(chmod(directory.c_str(), 0755) == 0, "chmod directory failed");
  rejects([&] { (void)store.read(); }, "permits group or other access");
  require(chmod(directory.c_str(), 0700) == 0, "restore directory mode failed");

  std::filesystem::rename(directory / "grants-v1.bin",
                          directory / "grants-v1.saved");
  std::filesystem::create_symlink(directory / "grants-v1.saved",
                                  directory / "grants-v1.bin");
  rejects([&] { (void)store.read(); }, "cannot open grant store file");
  std::filesystem::remove(directory / "grants-v1.bin");
  std::filesystem::rename(directory / "grants-v1.saved",
                          directory / "grants-v1.bin");

  {
    std::ofstream orphan(directory / ".grants-v1.tmp.crashed",
                         std::ios::binary);
    orphan << "partial";
  }
  require(grant::state_json(store.read()) == known_json,
          "orphaned pre-rename temporary must not replace committed state");

  std::filesystem::rename(directory / "grants-v1.lock",
                          directory / "grants-v1.lock.saved");
  std::filesystem::create_symlink(directory / "grants-v1.lock.saved",
                                  directory / "grants-v1.lock");
  rejects([&] { (void)store.revoke(request, capability); },
          "cannot open grant store lock");
  std::filesystem::remove(directory / "grants-v1.lock");
  std::filesystem::rename(directory / "grants-v1.lock.saved",
                          directory / "grants-v1.lock");
  require(grant::state_json(store.read()) == known_json,
          "rejected lock symlink must not mutate state");

  const auto link = temporary.path() / "link";
  std::filesystem::create_directory(temporary.path() / "real");
  std::filesystem::create_symlink(temporary.path() / "real", link);
  grant::GrantStore linked(link / "grants");
  rejects([&] { (void)linked.read(); }, "cannot open grant store directory");

  std::filesystem::rename(directory / "grants-v1.bin",
                          directory / "grants-v1.valid");
  {
    std::ofstream oversized(directory / "grants-v1.bin", std::ios::binary);
    oversized.seekp(static_cast<std::streamoff>(grant::kMaximumStoreBytes));
    oversized.put('x');
  }
  require(chmod((directory / "grants-v1.bin").c_str(), 0600) == 0,
          "chmod oversized file failed");
  rejects([&] { (void)store.read(); }, "exceeds byte limit");
  std::filesystem::remove(directory / "grants-v1.bin");
  std::filesystem::rename(directory / "grants-v1.valid",
                          directory / "grants-v1.bin");

  const auto original_size =
      std::filesystem::file_size(directory / "grants-v1.bin");
  require(truncate((directory / "grants-v1.bin").c_str(), 4) == 0,
          "truncate failed");
  rejects([&] { (void)store.read(); }, "truncated");
  require(original_size > 4, "test store unexpectedly small");
}

} // namespace

int main() {
  try {
    lifecycle_and_monotonicity();
    hostile_filesystem();
    std::cout << "grant store contract: ok\n";
    return 0;
  } catch (const std::exception &error) {
    std::cerr << "grant store contract: " << error.what() << '\n';
    return 1;
  }
}
