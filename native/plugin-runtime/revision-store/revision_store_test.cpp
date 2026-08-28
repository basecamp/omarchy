#include "revision_store.hpp"

#include "manifest_contract.hpp"

#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>
#include <sys/stat.h>
#include <unistd.h>

namespace {

using omarchy::plugins::discovery::VerifiedPlugin;
using omarchy::plugins::store::ErrorCode;
using omarchy::plugins::store::FaultPoint;
using omarchy::plugins::store::Options;
using omarchy::plugins::store::PolicyBinding;
using omarchy::plugins::store::RevisionStore;

void require(bool condition, const std::string &message) {
  if (!condition)
    throw std::runtime_error(message);
}

class TemporaryDirectory {
public:
  TemporaryDirectory() {
    std::string pattern = "/tmp/omarchy-revision-store-XXXXXX";
    char *created = ::mkdtemp(pattern.data());
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
  return {std::istreambuf_iterator<char>(stream), {}};
}

VerifiedPlugin verified(const std::filesystem::path &root) {
  auto manifest = omarchy::plugins::manifest::parse_manifest_v2(
      read_file(root / "manifest.json"));
  auto identity = omarchy::plugins::manifest::identify_tree(root, manifest);
  return {root, std::move(manifest), std::move(identity)};
}

std::filesystem::path make_source(const std::filesystem::path &parent,
                                  const std::string &name,
                                  const std::string &suffix = {}) {
  const auto target = parent / name;
  std::filesystem::copy(MANIFEST_V2_FIXTURE_ROOT, target,
                        std::filesystem::copy_options::recursive);
  if (!suffix.empty()) {
    std::ofstream qml(target / "ui/main.qml", std::ios::app);
    qml << "\n// " << suffix << '\n';
  }
  return target;
}

std::string digest(char value) { return std::string(64, value); }

PolicyBinding binding(const VerifiedPlugin &plugin, char policy, char grant,
                      std::uint64_t generation) {
  return {plugin.manifest.id,
          plugin.identity.tree_sha256,
          plugin.identity.manifest_sha256,
          plugin.identity.request_sha256,
          digest(policy),
          digest(grant),
          generation};
}

void require_owner_only_tree(const std::filesystem::path &path) {
  for (const auto &entry :
       std::filesystem::recursive_directory_iterator(path)) {
    struct stat status{};
    require(::lstat(entry.path().c_str(), &status) == 0, "lstat stored entry");
    require((status.st_mode & 0222) == 0,
            "stored revision must not be writable");
    require((status.st_mode & 0077) == 0, "stored revision must be owner-only");
  }
}

void test_gate_stage_and_identity() {
  TemporaryDirectory temporary;
  const auto source = make_source(temporary.path(), "source");
  const auto plugin = verified(source);
  require(plugin.identity.tree_sha256 == TREE_SHA256_GOLDEN,
          "fixture identity changed");

  RevisionStore disabled(temporary.path() / "disabled", {});
  require(disabled.stage(plugin).code == ErrorCode::feature_disabled,
          "v2 gate must deny staging");

  RevisionStore store(temporary.path() / "store", Options{true});
  require(store.recover().ok(), "create store");
  const auto staged = store.stage(plugin);
  require(staged.ok(), "stage verified plugin: " + staged.detail);
  require(store.stage(plugin).ok(), "stage must be idempotent");
  require_owner_only_tree(store.revision_path(plugin.identity.tree_sha256));
  require(!std::filesystem::exists(
              store.revision_path(plugin.identity.tree_sha256) / ".git"),
          "excluded metadata must not enter revision");

  struct stat root_status{};
  require(::stat((temporary.path() / "store").c_str(), &root_status) == 0,
          "inspect store root");
  require((root_status.st_mode & 0077) == 0, "store root must be owner-only");

  auto forged = plugin;
  forged.manifest.id = "org.example.forged";
  require(store.stage(forged).code == ErrorCode::corrupt_revision,
          "existing revision must not accept a substituted manifest model");

  const auto stored_qml =
      store.revision_path(plugin.identity.tree_sha256) / "ui/Status.qml";
  std::filesystem::permissions(stored_qml, std::filesystem::perms::owner_write,
                               std::filesystem::perm_options::add);
  std::ofstream(stored_qml, std::ios::app) << "\n// tampered\n";
  require(store.activate(binding(plugin, 'a', 'b', 1)).code ==
              ErrorCode::corrupt_revision,
          "activation must reverify immutable content");
}

void test_symlink_and_fault_cleanup() {
  TemporaryDirectory temporary;
  auto source = make_source(temporary.path(), "source");
  auto plugin = verified(source);
  std::filesystem::remove(source / "ui/main.qml");
  std::filesystem::create_symlink("../manifest.json", source / "ui/main.qml");

  RevisionStore store(temporary.path() / "store", Options{true});
  require(store.stage(plugin).code == ErrorCode::unsupported_entry,
          "source symlink must be rejected");

  source = make_source(temporary.path(), "source-two", "fault-copy");
  plugin = verified(source);
  require(store.stage(plugin, FaultPoint::stage_after_copy).code ==
              ErrorCode::injected_failure,
          "copy fault must fire");
  require(store.recover().ok(), "recovery after copy fault");
  require(!std::filesystem::exists(
              store.revision_path(plugin.identity.tree_sha256)),
          "partial tree must not publish");
  require(store.stage(plugin, FaultPoint::stage_after_verify).code ==
              ErrorCode::injected_failure,
          "verify fault must fire");
  require(store.recover().ok(), "recovery after verify fault");
  require(store.stage(plugin).ok(), "clean retry must stage");

  RevisionStore bounded(temporary.path() / "bounded", Options{true, 1, 1024});
  require(bounded.stage(plugin).code == ErrorCode::limit_exceeded,
          "staging must enforce file and byte budgets");

  const auto deep_source = make_source(temporary.path(), "deep");
  std::filesystem::create_directories(deep_source / "a/b/c");
  const auto deep_plugin = verified(deep_source);
  Options shallow_options{true};
  shallow_options.maximum_depth = 1;
  RevisionStore shallow(temporary.path() / "shallow", shallow_options);
  require(shallow.stage(deep_plugin).code == ErrorCode::limit_exceeded,
          "staging must enforce recursion depth");

  const auto unsafe_root = temporary.path() / "unsafe";
  std::filesystem::create_directory(unsafe_root);
  std::filesystem::permissions(unsafe_root,
                               std::filesystem::perms::owner_all |
                                   std::filesystem::perms::group_read);
  RevisionStore unsafe(unsafe_root, Options{true});
  require(unsafe.recover().code == ErrorCode::unsafe_store,
          "non-owner-only store must fail closed");
}

void test_activation_crash_and_exact_binding() {
  TemporaryDirectory temporary;
  const auto first = verified(make_source(temporary.path(), "first"));
  const auto second =
      verified(make_source(temporary.path(), "second", "second"));
  RevisionStore store(temporary.path() / "store", Options{true});
  require(store.stage(first).ok() && store.stage(second).ok(),
          "stage revisions");

  auto wrong = binding(first, 'a', 'b', 1);
  wrong.source_request_sha256 = digest('c');
  require(store.activate(wrong).code == ErrorCode::binding_mismatch,
          "request substitution must fail");
  auto first_binding = binding(first, 'a', 'b', 1);
  require(store.activate(first_binding).ok(), "activate first");
  auto wrong_rebind = first_binding;
  wrong_rebind.generation = 2;
  require(store.rebind_active(wrong_rebind).code == ErrorCode::binding_mismatch,
          "grant rebind changed activation generation");
  first_binding.grant_sha256 = digest('e');
  require(store.rebind_active(first_binding).ok() &&
              store.current()->active == first_binding,
          "grant-only active rebind did not commit atomically");

  const auto second_binding = binding(second, 'c', 'd', 2);
  require(
      store.activate(second_binding, FaultPoint::activate_after_write).code ==
          ErrorCode::injected_failure,
      "pre-sync activation fault");
  require(store.recover().ok(), "recover pre-sync activation");
  require(store.current()->active == first_binding,
          "pre-rename crash must preserve active binding");

  require(store.activate(second_binding, FaultPoint::activate_after_file_sync)
                  .code == ErrorCode::injected_failure,
          "post-sync activation fault");
  require(store.recover().ok(), "recover post-sync activation");
  require(store.current()->active == first_binding,
          "pre-rename synced crash must preserve active binding");

  require(
      store.activate(second_binding, FaultPoint::activate_after_rename).code ==
          ErrorCode::injected_failure,
      "post-rename activation fault");
  require(store.recover().ok(), "recover post-rename activation");
  const auto activation = store.current();
  require(
      activation && activation->active == second_binding &&
          activation->rollback == first_binding,
      "renamed activation must recover atomically with exact rollback binding");
  require(store.rollback().ok(), "rollback exact prior binding");
  auto rolled_back_first = first_binding;
  rolled_back_first.generation = 3;
  require(store.current()->active == rolled_back_first &&
              store.current()->rollback == second_binding,
          "rollback must preserve policy identity with a fresh generation");
  require(store.disable().ok() && store.current() &&
              !store.current()->enabled && !store.current()->removed,
          "disable marker did not persist");
  RevisionStore disabled_restart(temporary.path() / "store",
                                 {.schema_v2_enabled = true});
  require(disabled_restart.recover().ok() && disabled_restart.current() &&
              !disabled_restart.current()->enabled,
          "disabled activation became enabled after recovery");
  require(disabled_restart.mark_removed().ok() &&
              disabled_restart.current()->removed &&
              !disabled_restart.current()->rollback,
          "removal marker retained launch or rollback authority");
}

void test_retention_protects_active_and_rollback() {
  TemporaryDirectory temporary;
  const auto first = verified(make_source(temporary.path(), "first"));
  const auto second =
      verified(make_source(temporary.path(), "second", "second"));
  const auto third = verified(make_source(temporary.path(), "third", "third"));
  RevisionStore store(temporary.path() / "store", Options{true});
  require(store.stage(first).ok() && store.stage(second).ok() &&
              store.stage(third).ok(),
          "stage retention fixtures");
  require(store.activate(binding(first, 'a', 'b', 1)).ok(), "activate first");
  require(store.activate(binding(second, 'c', 'd', 2)).ok(), "activate second");
  require(store.prune(1).code == ErrorCode::retention_blocked,
          "bound below protected set must fail closed");
  require(std::filesystem::exists(
              store.revision_path(first.identity.tree_sha256)) &&
              std::filesystem::exists(
                  store.revision_path(second.identity.tree_sha256)),
          "active and rollback must survive blocked prune");
  require(store.prune(2).ok(),
          "retention should remove only unprotected revision");
  require(
      !std::filesystem::exists(store.revision_path(third.identity.tree_sha256)),
      "unprotected revision should be pruned");
}

} // namespace

int main() {
  try {
    test_gate_stage_and_identity();
    test_symlink_and_fault_cleanup();
    test_activation_crash_and_exact_binding();
    test_retention_protects_active_and_rollback();
    std::cout << "revision store tests passed\n";
    return EXIT_SUCCESS;
  } catch (const std::exception &failure) {
    std::cerr << "revision store test failed: " << failure.what() << '\n';
    return EXIT_FAILURE;
  }
}
