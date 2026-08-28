#include "lifecycle.hpp"

#include "manifest_contract.hpp"

#include <filesystem>
#include <fstream>
#include <stdexcept>
#include <string>
#include <string_view>
#include <sys/stat.h>
#include <unistd.h>

namespace {

namespace grant = omarchy::plugins::grants;
namespace lifecycle = omarchy::plugins::lifecycle;
namespace manifest = omarchy::plugins::manifest;
namespace permission = omarchy::plugins::permissions;
namespace revision = omarchy::plugins::store;

void require(bool condition, std::string_view message) {
  if (!condition)
    throw std::runtime_error(std::string(message));
}

class TemporaryDirectory {
public:
  TemporaryDirectory() {
    std::string pattern = "/tmp/omarchy-plugin-lifecycle-XXXXXX";
    const auto created = ::mkdtemp(pattern.data());
    if (created == nullptr)
      throw std::runtime_error("mkdtemp failed");
    path_ = created;
  }

  ~TemporaryDirectory() {
    std::error_code error;
    for (auto iterator = std::filesystem::recursive_directory_iterator(
             path_, std::filesystem::directory_options::skip_permission_denied,
             error);
         iterator != std::filesystem::recursive_directory_iterator();
         iterator.increment(error)) {
      std::filesystem::permissions(iterator->path(),
                                   std::filesystem::perms::owner_all,
                                   std::filesystem::perm_options::add, error);
      error.clear();
    }
    std::filesystem::permissions(path_, std::filesystem::perms::owner_all,
                                 std::filesystem::perm_options::add, error);
    std::filesystem::remove_all(path_, error);
  }

  [[nodiscard]] const std::filesystem::path &path() const { return path_; }

private:
  std::filesystem::path path_;
};

std::string read_file(const std::filesystem::path &path) {
  std::ifstream stream(path, std::ios::binary);
  require(stream.good(), "fixture file is unavailable");
  return {std::istreambuf_iterator<char>(stream), {}};
}

void write_file(const std::filesystem::path &path, std::string_view bytes) {
  std::ofstream stream(path, std::ios::binary | std::ios::trunc);
  require(stream.good(), "cannot write fixture file");
  stream << bytes;
  require(stream.good(), "cannot finish fixture file");
}

std::filesystem::path source(const std::filesystem::path &temporary,
                             std::string_view name, std::string_view suffix,
                             bool expanded = false) {
  const auto root = temporary / std::string(name);
  const auto plugin = root / "plugin";
  std::filesystem::create_directories(root);
  std::filesystem::copy(MANIFEST_V2_FIXTURE_ROOT, plugin,
                        std::filesystem::copy_options::recursive);
  if (!suffix.empty()) {
    std::ofstream qml(plugin / "ui/Status.qml", std::ios::app);
    qml << "\n// " << suffix << '\n';
  }
  if (expanded) {
    auto bytes = read_file(plugin / "manifest.json");
    const auto position = bytes.find("1048576");
    require(position != std::string::npos, "quota fixture changed");
    bytes.replace(position, 7, "2097152");
    write_file(plugin / "manifest.json", bytes);
  }
  return root;
}

manifest::ContentIdentity identity(const std::filesystem::path &root) {
  const auto plugin = root / "plugin";
  const auto parsed =
      manifest::parse_manifest_v2(read_file(plugin / "manifest.json"));
  return manifest::identify_tree(plugin, parsed);
}

const grant::PluginGrants &only_plugin(const grant::StoreState &state) {
  require(state.plugins.size() == 1, "expected one plugin grant record");
  return state.plugins.front();
}

grant::RequestBundle bundle(const std::filesystem::path &root,
                            const manifest::ContentIdentity &content,
                            std::uint64_t generation) {
  const auto parsed =
      manifest::parse_manifest_v2(read_file(root / "plugin/manifest.json"));
  return grant::make_bundle(2, permission::PluginId(parsed.id),
                            permission::Digest(content.tree_sha256),
                            permission::Digest(content.request_sha256),
                            generation, lifecycle::translate_requests(parsed));
}

permission::CapabilityKey storage_key() {
  return {.id = permission::CapabilityId("storage.private"), .version = 1};
}

std::string fingerprint(const grant::RevisionGrants &revision_grants) {
  return permission::grant_fingerprint(
      revision_grants.binding.plugin, revision_grants.binding.revision,
      revision_grants.binding.policy_fingerprint, revision_grants.grants);
}

revision::PolicyBinding
policy_binding(const grant::RevisionGrants &revision_grants,
               const manifest::ContentIdentity &content) {
  return {.plugin_id = std::string(revision_grants.binding.plugin.view()),
          .revision_sha256 =
              std::string(revision_grants.binding.revision.view()),
          .manifest_sha256 = content.manifest_sha256,
          .source_request_sha256 =
              std::string(revision_grants.source_request_fingerprint.view()),
          .policy_sha256 =
              std::string(revision_grants.binding.policy_fingerprint.view()),
          .grant_sha256 = fingerprint(revision_grants),
          .generation = revision_grants.binding.generation};
}

void grant_required(lifecycle::LifecycleManager &manager,
                    const grant::RequestBundle &request) {
  const auto capability = storage_key();
  const auto preview = manager.grants().preview(request, capability);
  const auto decision = manager.grants().decide(
      request, capability, std::nullopt, permission::UserDecision::grant,
      permission::DecisionActor::trusted_ui, 1,
      preview.expected_mutation_sequence);
  require(decision.grant.state == permission::GrantState::granted,
          "trusted fixture decision did not grant storage");
}

void disable_survives_grant_store_corruption() {
  TemporaryDirectory temporary;
  const auto revisions = temporary.path() / "revisions";
  const auto grants = temporary.path() / "grants";
  lifecycle::LifecycleManager manager(revisions, grants);
  const auto root = source(temporary.path(), "corrupt-disable", "initial");
  const auto content = identity(root);
  const auto staged = manager.stage(root, "plugin", content.tree_sha256);
  require(staged.result.ok() && staged.binding,
          "corrupt-disable fixture did not stage");
  grant_required(manager, bundle(root, content, staged.binding->generation));
  const permission::PluginId plugin("org.example.status");
  require(manager.enable(plugin).ok(),
          "corrupt-disable fixture did not enable");
  require(::truncate((grants / "grants-v1.bin").c_str(), 4) == 0,
          "grant corruption fixture truncate failed");
  require(manager.disable().ok() && manager.revisions().current() &&
              !manager.revisions().current()->enabled,
          "grant corruption prevented durable disable");
  lifecycle::LifecycleManager restarted(revisions, grants);
  require(restarted.recover().ok() && restarted.revisions().current() &&
              !restarted.revisions().current()->enabled,
          "restart consulted corrupt grants for a disabled activation");
}

} // namespace

int main() {
  disable_survives_grant_store_corruption();
  manifest::ManifestV2 translation_fixture;
  translation_fixture.requests = {
      {.capability = "audio.play-cue",
       .reason = "cue",
       .canonical_scope = "{\"cues\":[\"complete\"]}",
       .required = false},
      {.capability = "service.fake-status",
       .reason = "status",
       .canonical_scope =
           "{\"operations\":[\"acknowledge\",\"list\"],\"resourceIds\":[17]}",
       .required = false},
  };
  const auto translated = lifecycle::translate_requests(translation_fixture);
  require(
      translated.size() == 2 &&
          std::holds_alternative<permission::TokenScope>(translated[0].scope) &&
          std::holds_alternative<permission::ResourceScope>(
              translated[1].scope),
      "closed audio/fake manifest scopes did not translate");

  TemporaryDirectory temporary;
  const auto revisions = temporary.path() / "revisions";
  const auto grants = temporary.path() / "grants";
  lifecycle::LifecycleManager manager(revisions, grants);

  const auto first_root = source(temporary.path(), "source-first", "first");
  const auto first_identity = identity(first_root);
  const auto first =
      manager.stage(first_root, "plugin", first_identity.tree_sha256);
  require(first.result.ok() && first.binding &&
              first.permission_review_required && !first.already_active,
          "first pinned install did not stage for permission review");
  require(!manager.revisions().current().has_value(),
          "staging replaced activation");
  const permission::PluginId plugin("org.example.status");
  require(manager.enable(plugin).code ==
              lifecycle::ErrorCode::grants_incomplete,
          "required permission was bypassed during enable");
  const auto first_bundle = bundle(first_root, first_identity, 1);
  grant_required(manager, first_bundle);
  require(manager.enable(plugin).ok(), "granted first revision did not enable");
  const auto first_activation = manager.revisions().current();
  require(first_activation && first_activation->active.revision_sha256 ==
                                  first_identity.tree_sha256,
          "first activation identity changed");
  require(manager.rollback().code == lifecycle::ErrorCode::no_rollback,
          "missing rollback target reported success");

  std::ofstream(first_root / "plugin/ui/Status.qml", std::ios::app)
      << "\n// forged after pin\n";
  const auto forged =
      manager.stage(first_root, "plugin", first_identity.tree_sha256);
  require(forged.result.code == lifecycle::ErrorCode::validation_failed &&
              manager.revisions().current()->active == first_activation->active,
          "changed source crossed the trusted pin");

  const auto second_root = source(temporary.path(), "source-second", "second");
  const auto second_identity = identity(second_root);
  const auto second =
      manager.stage(second_root, "plugin", second_identity.tree_sha256);
  require(second.result.ok() && !second.permission_review_required &&
              manager.revisions().current()->active == first_activation->active,
          "safe update did not remain staged or inherit exact grants");
  const auto staged_state = manager.grants().read();
  require(only_plugin(staged_state).candidate &&
              only_plugin(staged_state).candidate->grants.size() == 1,
          "unchanged update did not inherit the reviewed storage grant");

  const auto desired =
      policy_binding(*only_plugin(staged_state).candidate, second_identity);
  require(manager.revisions().activate(desired).ok(),
          "crash-window activation fixture failed");
  lifecycle::LifecycleManager recovered_manager(revisions, grants);
  require(recovered_manager.recover().ok(),
          "recovery did not finish revision-first activation");
  const auto recovered_grants = recovered_manager.grants().read();
  require(only_plugin(recovered_grants).active &&
              only_plugin(recovered_grants).rollback &&
              !only_plugin(recovered_grants).candidate &&
              only_plugin(recovered_grants).active->binding.revision.view() ==
                  second_identity.tree_sha256,
          "grant promotion was not recovered atomically");

  require(recovered_manager.revisions().rollback().ok(),
          "crash-window rollback fixture failed");
  require(recovered_manager.recover().ok(),
          "recovery did not finish revision-first rollback");
  const auto rolled_back = recovered_manager.grants().read();
  require(only_plugin(rolled_back).active &&
              only_plugin(rolled_back).rollback &&
              only_plugin(rolled_back).active->binding.revision.view() ==
                  first_identity.tree_sha256 &&
              only_plugin(rolled_back).active->binding.generation == 3,
          "rollback did not restore exact grants with fresh generation");

  const auto active_before_revoke = only_plugin(rolled_back).active.value();
  const auto revoked = recovered_manager.grants().revoke(
      grant::make_bundle(2, active_before_revoke.binding.plugin,
                         active_before_revoke.binding.revision,
                         active_before_revoke.source_request_fingerprint,
                         active_before_revoke.binding.generation,
                         active_before_revoke.requests),
      storage_key());
  require(revoked.grant.state == permission::GrantState::revoked,
          "revocation fixture did not persist first");
  const auto stale_activation = recovered_manager.revisions().current()->active;
  require(stale_activation.grant_sha256 != revoked.grant_fingerprint,
          "revocation fixture did not create the recoverable seam");
  require(recovered_manager.recover().ok() &&
              recovered_manager.revisions().current()->active.grant_sha256 ==
                  revoked.grant_fingerprint,
          "recovery did not atomically rebind revoked authority");

  const auto expanded_root =
      source(temporary.path(), "source-expanded", "expanded", true);
  const auto expanded_identity = identity(expanded_root);
  const auto expanded = recovered_manager.stage(expanded_root, "plugin",
                                                expanded_identity.tree_sha256);
  require(expanded.result.ok() && expanded.permission_review_required,
          "permission-expanding update was not staged for review");
  require(recovered_manager.enable(plugin).code ==
                  lifecycle::ErrorCode::grants_incomplete &&
              recovered_manager.revisions().current()->active.revision_sha256 ==
                  first_identity.tree_sha256,
          "expanded permission replaced the active revision");
  require(recovered_manager.discard(plugin).ok() &&
              !only_plugin(recovered_manager.grants().read()).candidate,
          "failed candidate discard changed active state");

  require(recovered_manager.disable(revision::FaultPoint::activate_after_write)
                      .code == lifecycle::ErrorCode::store_failed &&
              recovered_manager.revisions().current()->enabled,
          "pre-commit disable fault changed durable launch intent");
  require(recovered_manager.remove(permission::PluginId("org.example.other"))
                      .code == lifecycle::ErrorCode::binding_mismatch &&
              recovered_manager.revisions().current()->enabled,
          "mismatched removal disabled another plugin");
  require(recovered_manager.disable().ok(), "durable disable failed");
  require(recovered_manager.rollback().code ==
              lifecycle::ErrorCode::store_failed,
          "rollback silently re-enabled a disabled activation");
  lifecycle::LifecycleManager disabled_restart(revisions, grants);
  require(disabled_restart.recover().ok() &&
              disabled_restart.revisions().current() &&
              !disabled_restart.revisions().current()->enabled &&
              !disabled_restart.revisions().current()->removed,
          "restart recovered a disabled plugin as launchable");
  require(disabled_restart.remove(plugin).ok(),
          "disabled plugin removal failed");
  lifecycle::LifecycleManager removed_restart(revisions, grants);
  const auto removed_activation = removed_restart.revisions().current();
  const auto removed_grants = removed_restart.grants().read();
  require(removed_restart.recover().ok() && removed_activation &&
              !removed_activation->enabled && removed_activation->removed &&
              removed_grants.plugins.empty() &&
              removed_grants.decisions.empty(),
          "restart resurrected removed grant or launch authority");

  const auto reinstall_root =
      source(temporary.path(), "source-reinstall", "first");
  const auto reinstall_identity = identity(reinstall_root);
  require(reinstall_identity.tree_sha256 == first_identity.tree_sha256,
          "same-content reinstall fixture changed identity");
  const auto reinstall = removed_restart.stage(reinstall_root, "plugin",
                                               reinstall_identity.tree_sha256);
  require(reinstall.result.ok() && reinstall.binding &&
              reinstall.binding->generation >
                  removed_activation->active.generation,
          "reinstall did not require a fresh post-removal generation");

  const auto legacy_root = temporary.path() / "legacy-root";
  std::filesystem::create_directories(legacy_root / "legacy");
  write_file(
      legacy_root / "legacy/manifest.json",
      R"({"schemaVersion":1,"id":"legacy.clock","name":"Legacy clock","version":"1.0.0","kinds":["barWidget"],"entryPoints":{"barWidget":"Clock.qml"}})");
  const auto legacy =
      removed_restart.stage(legacy_root, "legacy", std::string(64, '0'));
  require(legacy.result.code == lifecycle::ErrorCode::unsafe_legacy_schema,
          "legacy schema lost its explicit unsafe classification");

  return 0;
}
