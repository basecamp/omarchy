#include "update_hardening.hpp"

#include "manifest_contract.hpp"

#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <iterator>
#include <stdexcept>
#include <string>
#include <string_view>
#include <unistd.h>

namespace {

namespace grant = omarchy::plugins::grants;
namespace manifest = omarchy::plugins::manifest;
namespace permissions = omarchy::plugins::permissions;
namespace updates = omarchy::plugins::updates;

void require(bool condition, std::string_view message) {
  if (!condition)
    throw std::runtime_error(std::string(message));
}

class TemporaryDirectory {
public:
  TemporaryDirectory() {
    std::string pattern = "/tmp/omarchy-update-hardening-XXXXXX";
    char *created = ::mkdtemp(pattern.data());
    if (created == nullptr)
      throw std::runtime_error("mkdtemp failed");
    path_ = created;
  }
  ~TemporaryDirectory() {
    std::error_code error;
    std::filesystem::remove_all(path_, error);
  }
  const std::filesystem::path &path() const { return path_; }

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
                             std::string_view name, std::string_view version,
                             std::string_view suffix = {}) {
  const auto root = temporary / std::string(name);
  const auto plugin = root / "plugin";
  std::filesystem::create_directories(root);
  std::filesystem::copy(MANIFEST_V2_FIXTURE_ROOT, plugin,
                        std::filesystem::copy_options::recursive);
  auto bytes = read_file(plugin / "manifest.json");
  const auto marker = bytes.find("\"version\": \"2.0.0\"");
  require(marker != std::string::npos, "version fixture changed");
  bytes.replace(marker, std::string_view("\"version\": \"2.0.0\"").size(),
                "\"version\": \"" + std::string(version) + "\"");
  write_file(plugin / "manifest.json", bytes);
  if (!suffix.empty()) {
    std::ofstream qml(plugin / "ui/Status.qml", std::ios::app);
    qml << "\n// " << suffix << '\n';
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

void activate_first(updates::UpdateManager &manager,
                    const std::filesystem::path &root,
                    const manifest::ContentIdentity &content) {
  const auto request = manager.stage(root, "plugin", content.tree_sha256);
  require(request.ok() &&
              request.disposition == updates::Disposition::fresh_install &&
              request.stage && request.stage->permission_review_required,
          "fresh secure revision did not stage for review");
  const auto state = manager.lifecycle().grants().read();
  const auto &candidate = only_plugin(state).candidate.value();
  const auto capability = permissions::CapabilityKey{
      permissions::CapabilityId("storage.private"), 1};
  const auto bundle = grant::make_bundle(
      2, candidate.binding.plugin, candidate.binding.revision,
      candidate.source_request_fingerprint, candidate.binding.generation,
      candidate.requests);
  const auto preview = manager.lifecycle().grants().preview(bundle, capability);
  (void)manager.lifecycle().grants().decide(
      bundle, capability, std::nullopt, permissions::UserDecision::grant,
      permissions::DecisionActor::trusted_ui, 1,
      preview.expected_mutation_sequence);
  require(manager.lifecycle()
              .enable(permissions::PluginId("org.example.status"))
              .ok(),
          "reviewed first revision did not activate");
}

void test_legacy_is_indivisible_and_never_secure() {
  TemporaryDirectory temporary;
  updates::UpdateManager manager(temporary.path() / "revisions",
                                 temporary.path() / "grants");
  const auto root = temporary.path() / "legacy-root";
  std::filesystem::create_directories(root / "legacy");
  write_file(
      root / "legacy/manifest.json",
      R"({"schemaVersion":1,"id":"legacy.clock","name":"Legacy clock","version":"9.9.9","kinds":["barWidget"],"entryPoints":{"barWidget":"Clock.qml"}})");
  const auto result = manager.stage(root, "legacy", std::string(64, '0'));
  require(result.code == updates::ErrorCode::unsafe_legacy_schema &&
              result.compatibility ==
                  updates::CompatibilityMode::legacy_v1_unsafe_unmigrated &&
              result.disposition == updates::Disposition::unsafe_unmigrated &&
              !result.stage && !result.granular_permissions_eligible() &&
              !result.sandbox_eligible() &&
              !manager.lifecycle().revisions().current().has_value() &&
              manager.lifecycle().grants().read().plugins.empty(),
          "schema v1 entered a secure claim or durable authority state");
}

void test_reinstall_upgrade_downgrade_rebuild_and_identity() {
  TemporaryDirectory temporary;
  updates::UpdateManager manager(temporary.path() / "revisions",
                                 temporary.path() / "grants");
  const auto original = source(temporary.path(), "original", "2.0.0");
  const auto original_identity = identity(original);
  activate_first(manager, original, original_identity);
  const auto active = manager.lifecycle().revisions().current()->active;
  const auto mutation = manager.lifecycle().grants().read().mutation_sequence;

  const auto reinstall =
      manager.stage(original, "plugin", original_identity.tree_sha256);
  require(reinstall.ok() &&
              reinstall.disposition == updates::Disposition::exact_reinstall &&
              reinstall.stage && reinstall.stage->already_active &&
              manager.lifecycle().grants().read().mutation_sequence ==
                  mutation &&
              manager.lifecycle().revisions().current()->active == active,
          "exact reinstall mutated activation or grants");

  const auto upgrade = source(temporary.path(), "upgrade", "3.0.0", "upgrade");
  const auto upgrade_identity = identity(upgrade);
  const auto upgraded =
      manager.stage(upgrade, "plugin", upgrade_identity.tree_sha256);
  require(upgraded.ok() &&
              upgraded.disposition == updates::Disposition::staged_upgrade &&
              only_plugin(manager.lifecycle().grants().read()).candidate &&
              manager.lifecycle().revisions().current()->active == active,
          "upgrade bypassed candidate staging");
  require(manager.lifecycle()
              .discard(permissions::PluginId("org.example.status"))
              .ok(),
          "upgrade candidate discard failed");

  const auto downgrade =
      source(temporary.path(), "downgrade", "1.0.0", "downgrade");
  const auto downgrade_identity = identity(downgrade);
  const auto denied =
      manager.stage(downgrade, "plugin", downgrade_identity.tree_sha256);
  require(denied.code == updates::ErrorCode::downgrade_requires_approval &&
              !only_plugin(manager.lifecycle().grants().read()).candidate &&
              manager.lifecycle().revisions().current()->active == active,
          "unreviewed downgrade changed secure state");
  updates::Approval stale{.kind = updates::ApprovalKind::downgrade,
                          .active_revision_sha256 = active.revision_sha256,
                          .candidate_revision_sha256 = std::string(64, 'f')};
  require(
      manager.stage(downgrade, "plugin", downgrade_identity.tree_sha256, stale)
              .code == updates::ErrorCode::stale_approval,
      "approval for another candidate authorized downgrade");
  updates::Approval downgrade_approval{
      .kind = updates::ApprovalKind::downgrade,
      .active_revision_sha256 = active.revision_sha256,
      .candidate_revision_sha256 = downgrade_identity.tree_sha256};
  const auto approved = manager.stage(
      downgrade, "plugin", downgrade_identity.tree_sha256, downgrade_approval);
  require(approved.ok() &&
              approved.disposition == updates::Disposition::staged_downgrade &&
              manager.lifecycle().revisions().current()->active == active,
          "exactly approved downgrade did not remain staged");
  require(manager.lifecycle()
              .discard(permissions::PluginId("org.example.status"))
              .ok(),
          "downgrade candidate discard failed");

  const auto rebuild =
      source(temporary.path(), "rebuild", "2.0.0", "rebuilt-content");
  const auto rebuild_identity = identity(rebuild);
  require(manager.stage(rebuild, "plugin", rebuild_identity.tree_sha256).code ==
              updates::ErrorCode::rebuild_requires_approval,
          "same-version replacement avoided exact review");
  updates::Approval rebuild_approval{
      .kind = updates::ApprovalKind::same_version_rebuild,
      .active_revision_sha256 = active.revision_sha256,
      .candidate_revision_sha256 = rebuild_identity.tree_sha256};
  const auto rebuilt = manager.stage(
      rebuild, "plugin", rebuild_identity.tree_sha256, rebuild_approval);
  require(rebuilt.ok() &&
              rebuilt.disposition == updates::Disposition::staged_rebuild &&
              manager.lifecycle().revisions().current()->active == active,
          "approved same-version replacement bypassed staging");
  require(manager.lifecycle()
              .discard(permissions::PluginId("org.example.status"))
              .ok(),
          "rebuild candidate discard failed");

  const auto unorderable =
      source(temporary.path(), "unorderable", "latest", "unorderable");
  const auto unorderable_identity = identity(unorderable);
  require(manager.stage(unorderable, "plugin", unorderable_identity.tree_sha256)
                      .code == updates::ErrorCode::unorderable_version &&
              !only_plugin(manager.lifecycle().grants().read()).candidate,
          "unorderable version was guessed or staged");

  const auto changed =
      source(temporary.path(), "identity", "3.0.0", "identity");
  auto manifest_bytes = read_file(changed / "plugin/manifest.json");
  const auto id = manifest_bytes.find("org.example.status");
  require(id != std::string::npos, "identity fixture changed");
  manifest_bytes.replace(id, std::string_view("org.example.status").size(),
                         "org.example.changed");
  write_file(changed / "plugin/manifest.json", manifest_bytes);
  const auto changed_identity = identity(changed);
  require(manager.stage(changed, "plugin", changed_identity.tree_sha256).code ==
                  updates::ErrorCode::identity_change &&
              manager.lifecycle().revisions().current()->active == active,
          "plugin identity change entered update staging");

  const auto faulted =
      source(temporary.path(), "faulted", "4.0.0", "faulted-copy");
  const auto faulted_identity = identity(faulted);
  require(manager.stage(faulted, "plugin", faulted_identity.tree_sha256,
                        std::nullopt,
                        omarchy::plugins::store::FaultPoint::stage_after_copy)
                      .code == updates::ErrorCode::lifecycle_failed &&
              manager.lifecycle().revisions().current()->active == active &&
              !only_plugin(manager.lifecycle().grants().read()).candidate,
          "faulted stage changed active or candidate authority");
}

} // namespace

int main() {
  try {
    test_legacy_is_indivisible_and_never_secure();
    test_reinstall_upgrade_downgrade_rebuild_and_identity();
  } catch (const std::exception &error) {
    std::cerr << "FAIL: " << error.what() << '\n';
    return 1;
  }
  std::cout << "update hardening tests passed\n";
  return 0;
}
