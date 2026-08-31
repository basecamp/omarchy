#include "runtime_bootstrap.hpp"
#include "runtime_roots_test_access.hpp"

#include "capability_definition_loader.hpp"
#include "omarchy/plugin_runtime/Version.h"

#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

#include <filesystem>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>
#include <string_view>

namespace channel = omarchy::plugin_runtime::channel;
namespace definitions = omarchy::plugins::definitions;
namespace manifest = omarchy::plugins::manifest;
namespace permissions = omarchy::plugins::permissions;
namespace host_session = omarchy::plugin_runtime::host_session;
namespace policy = omarchy::plugin_runtime::policy;

namespace {

void require(bool condition, std::string_view message) {
  if (!condition)
    throw std::runtime_error(std::string(message));
}

class Fixture final {
public:
  Fixture() {
    std::string pattern = "/tmp/omarchy-runtime-bootstrap.XXXXXX";
    const auto *created = ::mkdtemp(pattern.data());
    require(created != nullptr, "bootstrap fixture creation failed");
    root_ = created;
    require(::chmod(root_.c_str(), 0755) == 0,
            "fixture root mode setup failed");
    home_ = root_ / "user-home";
    create(home_, 0700);
    create(home_ / ".local/share/omarchy-plugin-security/v2/revisions", 0700);
    create(home_ / ".local/state/omarchy/plugin-security/v2/activations",
           0700);
    create(home_ / ".local/state/omarchy/plugin-security/v2/authority", 0700);
    create(home_ / ".local/state/omarchy/plugin-security/v2/state", 0700);
    create(package(), 0755);
    create_authority("example.plugin");
  }

  ~Fixture() {
    std::error_code ignored;
    std::filesystem::remove_all(root_, ignored);
  }

  [[nodiscard]] std::filesystem::path package() const {
    return root_ / "usr/lib/omarchy/plugin-security" /
           std::string(omarchy::plugin_runtime::build_version()) /
           "capabilities.d";
  }
  [[nodiscard]] std::filesystem::path admin() const {
    return root_ / "etc/omarchy/plugin-capabilities.d";
  }
  [[nodiscard]] std::filesystem::path authority(std::string_view plugin) const {
    return home_ / ".local/state/omarchy/plugin-security/v2/authority" /
           std::string(plugin);
  }
  [[nodiscard]] std::filesystem::path activations() const {
    return home_ / ".local/state/omarchy/plugin-security/v2/activations";
  }
  [[nodiscard]] std::filesystem::path revisions() const {
    return home_ / ".local/share/omarchy-plugin-security/v2/revisions";
  }
  [[nodiscard]] std::filesystem::path state() const {
    return home_ / ".local/state/omarchy/plugin-security/v2/state";
  }
  [[nodiscard]] int open_root() const {
    return ::open(root_.c_str(),
                  O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
  }
  [[nodiscard]] std::unique_ptr<channel::RuntimeRoots> roots() const {
    const int home = ::open(home_.c_str(),
                            O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
    require(home >= 0, "fixture home descriptor unavailable");
    channel::RuntimeRootsError error{};
    auto result = channel::RuntimeRootsTestAccess::open_from_home_fd(
        home, static_cast<std::uint32_t>(::getuid()), error);
    ::close(home);
    require(result && error == channel::RuntimeRootsError::none,
            "fixture runtime roots unavailable");
    return result;
  }
  void create_admin(mode_t mode = 0755) {
    create(admin(), mode);
  }
  void create_authority(std::string_view plugin, mode_t mode = 0700) {
    create(authority(plugin), mode);
  }
  void seed_runtime(std::string_view plugin,
                    std::string_view revision_directory) {
    const auto revision = revisions() / std::string(revision_directory);
    create(revision / "ui", 0755);
    {
      std::ofstream manifest_file(revision / "manifest.json");
      manifest_file
          << "{\n  \"schemaVersion\": 2,\n  \"id\": \"" << plugin
          << "\",\n  \"name\": \"Fixture\",\n"
             "  \"version\": \"1.0.0\",\n"
             "  \"runtime\": {\"apiVersion\": 1, \"qml\": "
             "\"ui/Main.qml\"},\n  \"surfaces\": {\"bar\": {"
             "\"role\": \"bar-embedded\", \"defaultSection\": "
             "\"right\"}},\n  \"permissions\": {\"required\": [], "
             "\"optional\": []}\n}\n";
    }
    std::ofstream(revision / "ui/Main.qml") << "import QtQuick\nItem {}\n";
    for (const auto &entry :
         std::filesystem::recursive_directory_iterator(revision)) {
      require(::chmod(entry.path().c_str(), entry.is_directory() ? 0555 : 0444) ==
                  0,
              "cannot secure runtime revision fixture");
    }
    require(::chmod(revision.c_str(), 0555) == 0,
            "cannot secure runtime revision root");

    create(state() / std::string(plugin), 0700);
    const int revision_fd = ::open(
        revision.c_str(), O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
    require(revision_fd >= 0, "runtime revision descriptor unavailable");
    host_session::SourceRevisionVerifier verifier;
    auto verified = verifier.verify_open_revision(revision_fd);
    ::close(revision_fd);
    require(verified && verified->manifest.id == plugin,
            "runtime revision verification failed");

    const auto record_path = activations() / std::string(plugin);
    std::ofstream(record_path)
        << "format=omarchy-plugin-activation-v2\nplugin=" << plugin
        << "\nrevision-directory=" << revision_directory
        << "\nrevision-sha256=" << verified->tree_sha256
        << "\nstate-directory=" << plugin << "\n";
    require(::chmod(record_path.c_str(), 0600) == 0,
            "cannot secure runtime activation record");

    const int authority_fd = ::open(authority(plugin).c_str(),
                                    O_RDONLY | O_DIRECTORY | O_CLOEXEC |
                                        O_NOFOLLOW);
    require(authority_fd >= 0, "runtime authority descriptor unavailable");
    auto store = host_session::AuthorityStore::open(
        authority_fd, ::getuid(), permissions::PluginId(plugin));
    ::close(authority_fd);
    require(store != nullptr, "runtime authority store unavailable");
    policy::GrantSnapshot snapshot;
    snapshot.requests =
        permissions::requests_from_manifest(verified->manifest);
    snapshot.binding = {
        .plugin = permissions::PluginId(plugin),
        .revision = permissions::Digest(verified->tree_sha256),
        .policy_fingerprint = permissions::Digest(
            permissions::policy_request_fingerprint(snapshot.requests)),
        .generation = 1,
    };
    snapshot.source_request_fingerprint =
        permissions::Digest(verified->request_sha256);
    definitions::TrustedDefinitionRegistry registry;
    require(store->publish_candidate(*verified, snapshot, 0, registry, {}) ==
                    host_session::AuthorityMutationResult::applied &&
                store->promote_candidate(snapshot.binding, 1) ==
                    host_session::AuthorityMutationResult::applied,
            "runtime authority activation failed");
  }

private:
  void create(const std::filesystem::path &path, mode_t leaf_mode) {
    auto relative = path.lexically_relative(root_);
    auto current = root_;
    for (const auto &component : relative) {
      current /= component;
      const bool created = std::filesystem::create_directory(current);
      const bool leaf = current == path;
      if (created || leaf)
        require(::chmod(current.c_str(), leaf ? leaf_mode : 0755) == 0,
                "fixture directory mode setup failed");
    }
  }

  std::filesystem::path root_;
  std::filesystem::path home_;
};

std::unique_ptr<channel::RuntimeBootstrap>
load(Fixture &fixture, channel::RuntimeBootstrapError &error) {
  const int root = fixture.open_root();
  require(root >= 0, "fixture filesystem root unavailable");
  auto result = channel::RuntimeBootstrapTestAccess::
      open_from_filesystem_root(fixture.roots(), root,
                                static_cast<std::uint32_t>(::getuid()), error);
  ::close(root);
  return result;
}

std::unique_ptr<channel::PreparedPluginRuntime> prepare_runtime_for_test(
    const channel::RuntimeBootstrap &bootstrap, std::string_view record,
    const permissions::PluginId &plugin) {
  auto authority = channel::RuntimeBootstrapTestAccess::open_permissions(
      bootstrap, record, plugin);
  return channel::RuntimeBootstrapTestAccess::prepare_runtime(bootstrap,
                                                               authority)
      .runtime;
}

definitions::CapabilityDefinition dynamic_definition() {
  definitions::CapabilityDefinition definition{
      .canonical_name = definitions::Name("local.test"),
      .authority_identity = definitions::Name("local.test-v1"),
      .enforcement_family = definitions::EnforcementFamily::network_fetch,
      .display_category_id = definitions::Name("local.testing"),
      .display_category_label = definitions::Label("Local testing"),
      .scope_schema = definitions::ScopeSchema::https_origins_and_methods,
      .title = definitions::Label("Test a dynamic adapter"),
      .risk_text = definitions::Label("Exercises a test-only definition"),
      .risk = definitions::RiskLevel::moderate,
      .revocation = definitions::RevocationPolicy::cancel_inflight,
      .audit = {},
      .adapter = {.adapter_class = definitions::Name("unregistered-adapter"),
                  .contract_digest =
                      definitions::Digest(std::string(64, 'a')),
                  .abi_version = 1},
      .operations = {},
  };
  require(definition.operations.insert(
              {.name = definitions::Name("read"),
               .label = definitions::Label("Read test data")}),
          "definition operation setup failed");
  return definition;
}

std::string hex(char value) { return std::string(64, value); }

struct Review final {
  host_session::VerifiedRevision verified;
  policy::GrantSnapshot snapshot;
};

Review review(std::string_view plugin, std::uint64_t generation,
              char revision) {
  manifest::ManifestV2 plugin_manifest;
  plugin_manifest.id = std::string(plugin);
  plugin_manifest.requests.push_back(
      {.capability = "notifications.send",
       .reason = "status",
       .canonical_scope = "{\"categories\":[\"status\"]}",
       .definition_generation = 0,
       .definition_digest = {},
       .operations = {},
       .required = true});
  policy::GrantSnapshot snapshot;
  snapshot.requests = permissions::requests_from_manifest(plugin_manifest);
  snapshot.binding = {
      .plugin = permissions::PluginId(plugin),
      .revision = permissions::Digest(hex(revision)),
      .policy_fingerprint = permissions::Digest(
          permissions::policy_request_fingerprint(snapshot.requests)),
      .generation = generation,
  };
  snapshot.source_request_fingerprint = permissions::Digest(
      manifest::requested_capability_fingerprint(plugin_manifest.requests));
  snapshot.grants.push_back({.capability = snapshot.requests[0].capability,
                             .scope = snapshot.requests[0].scope,
                             .state = permissions::GrantState::granted,
                             .epoch = generation});
  return {
      .verified = {.manifest = std::move(plugin_manifest),
                   .tree_sha256 = hex(revision),
                   .request_sha256 = std::string(
                       snapshot.source_request_fingerprint.view())},
      .snapshot = std::move(snapshot),
  };
}

void empty_package_and_absent_admin_compose_one_shared_context() {
  Fixture fixture;
  fixture.create_authority("second.plugin");
  fixture.seed_runtime("example.plugin", "first-installed");
  fixture.seed_runtime("second.plugin", "second-installed");
  channel::RuntimeBootstrapError error{};
  auto bootstrap = load(fixture, error);
  require(bootstrap && error == channel::RuntimeBootstrapError::none &&
              channel::RuntimeBootstrapTestAccess::has_fixed_service_context(
                  *bootstrap),
          "fixed bootstrap did not compose exact runtime services");

  const permissions::PluginId plugin("example.plugin");
  require(!prepare_runtime_for_test(
              *bootstrap, "other.plugin", plugin),
          "mismatched activation candidate was accepted");
  auto first = prepare_runtime_for_test(
      *bootstrap, "example.plugin", plugin);
  auto second = prepare_runtime_for_test(
      *bootstrap, "second.plugin", permissions::PluginId("second.plugin"));
  require(first && second,
          "bootstrap could not prepare independent exact candidates");
  require(!prepare_runtime_for_test(
              *bootstrap, "example.plugin", plugin),
          "bootstrap admitted a second owner for one plugin authority");
}

void authority_cannot_cross_runtime_service_identity() {
  Fixture fixture;
  fixture.seed_runtime("example.plugin", "installed");
  const auto shared_definitions =
      std::make_shared<const definitions::TrustedDefinitionRegistry>();
  const auto first_services =
      std::make_shared<const channel::RuntimeServices>();
  const auto second_services =
      std::make_shared<const channel::RuntimeServices>();
  auto first = channel::RuntimeBootstrapTestAccess::compose_with_context(
      fixture.roots(), shared_definitions, first_services);
  auto second = channel::RuntimeBootstrapTestAccess::compose_with_context(
      fixture.roots(), shared_definitions, second_services);
  require(first && second,
          "cross-bootstrap service contexts did not compose");
  const permissions::PluginId plugin("example.plugin");
  auto authority = channel::RuntimeBootstrapTestAccess::open_permissions(
      *first, plugin.view(), plugin);
  require(authority != nullptr,
          "cross-bootstrap service fixture did not open authority");
  const auto crossed = channel::RuntimeBootstrapTestAccess::prepare_runtime(
      *second, authority);
  require(!crossed.runtime && !crossed.permission_disabled,
          "authority reviewed under one service context executed under another");
  require(channel::RuntimeBootstrapTestAccess::prepare_runtime(*first,
                                                                authority)
                  .runtime != nullptr,
          "matching bootstrap rejected its own authority context");
}

void mandatory_package_and_optional_admin_are_exact() {
  {
    Fixture fixture;
    channel::RuntimeBootstrapError error{};
    require(!channel::RuntimeBootstrapTestAccess::
                 open_from_filesystem_root(
                     fixture.roots(), -1,
                     static_cast<std::uint32_t>(::getuid()), error) &&
                error == channel::RuntimeBootstrapError::
                             package_definitions_untrusted,
            "invalid fixed filesystem descriptor was accepted");
  }
  {
    Fixture fixture;
    std::filesystem::remove(fixture.package());
    channel::RuntimeBootstrapError error{};
    require(!load(fixture, error) &&
                error == channel::RuntimeBootstrapError::
                             package_definitions_unavailable,
            "missing mandatory package definitions were accepted");
  }
  {
    Fixture fixture;
    require(::chmod(fixture.package().c_str(), 0775) == 0,
            "package trust-root mode setup failed");
    channel::RuntimeBootstrapError error{};
    require(!load(fixture, error) &&
                error == channel::RuntimeBootstrapError::
                             package_definitions_untrusted,
            "writable package definitions were accepted");
  }
  {
    Fixture fixture;
    const auto package = fixture.package();
    const auto target = package.parent_path() / "alternate-capabilities";
    std::filesystem::remove(package);
    std::filesystem::create_directory(target);
    require(::chmod(target.c_str(), 0755) == 0,
            "package symlink target mode setup failed");
    std::filesystem::create_directory_symlink(target, package);
    channel::RuntimeBootstrapError error{};
    require(!load(fixture, error) &&
                error == channel::RuntimeBootstrapError::
                             package_definitions_untrusted,
            "symlinked package definitions were accepted");
  }
  {
    Fixture fixture;
    fixture.create_admin(0775);
    channel::RuntimeBootstrapError error{};
    require(!load(fixture, error) &&
                error == channel::RuntimeBootstrapError::
                             admin_definitions_untrusted,
            "malformed existing admin definitions were treated as absent");
  }
  {
    Fixture fixture;
    fixture.create_admin();
    const auto document = fixture.admin() / "broken.capability";
    {
      std::ofstream output(document, std::ios::binary);
      output << "not a capability definition";
    }
    require(::chmod(document.c_str(), 0644) == 0,
            "malformed admin definition mode setup failed");
    channel::RuntimeBootstrapError error{};
    require(!load(fixture, error) &&
                error == channel::RuntimeBootstrapError::
                             definition_document_rejected,
            "malformed admin document entered a partial bootstrap");
  }
}

void authority_children_are_exact_and_never_created() {
  const auto uid = static_cast<std::uint32_t>(::getuid());
  require(channel::RuntimeBootstrapTestAccess::
                  authority_directory_accepted(uid, S_IFDIR | 0700, uid) &&
              !channel::RuntimeBootstrapTestAccess::
                  authority_directory_accepted(uid + 1, S_IFDIR | 0700, uid) &&
              !channel::RuntimeBootstrapTestAccess::
                  authority_directory_accepted(uid, S_IFDIR | 0750, uid) &&
              !channel::RuntimeBootstrapTestAccess::
                  authority_directory_accepted(uid, S_IFREG | 0700, uid),
          "per-plugin authority metadata predicate widened ownership or mode");

  const permissions::PluginId plugin("example.plugin");
  {
    Fixture fixture;
    std::filesystem::remove(fixture.authority("example.plugin"));
    channel::RuntimeBootstrapError error{};
    auto bootstrap = load(fixture, error);
    require(bootstrap &&
                !prepare_runtime_for_test(
                    *bootstrap, "example.plugin", plugin) &&
                !std::filesystem::exists(fixture.authority("example.plugin")),
            "bootstrap created a missing authority child");
  }
  {
    Fixture fixture;
    require(::chmod(fixture.authority("example.plugin").c_str(), 0750) == 0,
            "authority mode fixture setup failed");
    channel::RuntimeBootstrapError error{};
    auto bootstrap = load(fixture, error);
    require(bootstrap &&
                !prepare_runtime_for_test(
                    *bootstrap, "example.plugin", plugin),
            "widened per-plugin authority directory was accepted");
  }
  {
    Fixture fixture;
    const auto child = fixture.authority("example.plugin");
    const auto target = fixture.authority("alternate.plugin");
    std::filesystem::remove(child);
    fixture.create_authority("alternate.plugin");
    std::filesystem::create_directory_symlink(target, child);
    channel::RuntimeBootstrapError error{};
    auto bootstrap = load(fixture, error);
    require(bootstrap &&
                !prepare_runtime_for_test(
                    *bootstrap, "example.plugin", plugin),
            "symlinked per-plugin authority directory was accepted");
  }
  {
    Fixture fixture;
    channel::RuntimeBootstrapError error{};
    auto bootstrap = load(fixture, error);
    const permissions::PluginId path_plugin("../example.plugin");
    require(bootstrap &&
                !prepare_runtime_for_test(
                    *bootstrap, path_plugin.view(), path_plugin),
            "noncanonical plugin name selected an authority path");
  }
}

void authority_stores_are_physically_isolated_per_plugin() {
  Fixture fixture;
  fixture.create_authority("second.plugin");
  const permissions::PluginId first_plugin("example.plugin");
  const permissions::PluginId second_plugin("second.plugin");
  const int first_authority =
      ::open(fixture.authority(first_plugin.view()).c_str(),
             O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
  const int second_authority =
      ::open(fixture.authority(second_plugin.view()).c_str(),
             O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
  require(first_authority >= 0 && second_authority >= 0 &&
              (::fcntl(first_authority, F_GETFD) & FD_CLOEXEC) != 0 &&
              (::fcntl(second_authority, F_GETFD) & FD_CLOEXEC) != 0,
          "exact per-plugin authority descriptors were unavailable");

  auto first_store = host_session::AuthorityStore::open(
      first_authority, ::getuid(), first_plugin);
  auto second_store = host_session::AuthorityStore::open(
      second_authority, ::getuid(), second_plugin);
  require(first_store && second_store,
          "different plugin authority locks could not coexist");
  require(!host_session::AuthorityStore::open(
              first_authority, ::getuid(), first_plugin),
          "a second owner acquired the same plugin authority lock");
  ::close(first_authority);
  ::close(second_authority);

  definitions::TrustedDefinitionRegistry registry;
  auto first_review = review(first_plugin.view(), 1, 'a');
  auto second_review = review(second_plugin.view(), 1, 'b');
  require(first_store->publish_candidate(first_review.verified,
                                         first_review.snapshot, 0, registry,
                                         {}) ==
                  host_session::AuthorityMutationResult::applied &&
              second_store->publish_candidate(second_review.verified,
                                               second_review.snapshot, 0,
                                               registry, {}) ==
                  host_session::AuthorityMutationResult::applied &&
              first_store->promote_candidate(first_review.snapshot.binding,
                                             1) ==
                  host_session::AuthorityMutationResult::applied &&
              second_store->promote_candidate(second_review.snapshot.binding,
                                              1) ==
                  host_session::AuthorityMutationResult::applied,
          "independent plugin authority snapshots did not activate");
  require(first_store->resolve(first_plugin.view(), hex('a')).status ==
                  host_session::GrantStatus::activatable &&
              second_store->resolve(second_plugin.view(), hex('b')).status ==
                  host_session::GrantStatus::activatable,
          "one plugin authority snapshot replaced another");

  auto replacement = review(first_plugin.view(), 2, 'c');
  require(first_store->publish_candidate(replacement.verified,
                                         replacement.snapshot, 2, registry,
                                         {}) ==
                  host_session::AuthorityMutationResult::applied &&
              first_store->discard_candidate(replacement.snapshot.binding,
                                             3) ==
                  host_session::AuthorityMutationResult::applied &&
              second_store->resolve(second_plugin.view(), hex('b')).status ==
                  host_session::GrantStatus::activatable,
          "one plugin candidate cleanup touched another plugin store");
  const auto first_view = first_store->read_authority_view();
  const auto second_view = second_store->read_authority_view();
  require(first_view && second_view && first_view->active &&
              second_view->active &&
              first_view->active->binding.plugin == first_plugin &&
              second_view->active->binding.plugin == second_plugin,
          "per-plugin slots crossed authority directories");

  first_store.reset();
  second_store.reset();

  Fixture runtime_fixture;
  runtime_fixture.create_authority("second.plugin");
  runtime_fixture.seed_runtime("example.plugin", "first-installed");
  runtime_fixture.seed_runtime("second.plugin", "second-installed");
  channel::RuntimeBootstrapError error{};
  auto bootstrap = load(runtime_fixture, error);
  auto first = prepare_runtime_for_test(
      *bootstrap, first_plugin.view(), first_plugin);
  auto second = prepare_runtime_for_test(
      *bootstrap, second_plugin.view(), second_plugin);
  require(first && second &&
              !prepare_runtime_for_test(
                  *bootstrap, first_plugin.view(), first_plugin),
          "prepared roots did not preserve independent lock scope");
  first.reset();
  require(static_cast<bool>(
              prepare_runtime_for_test(
                  *bootstrap, first_plugin.view(), first_plugin)),
          "released plugin authority lock could not be reacquired");
}

void trusted_definition_loads_without_a_provider() {
  Fixture fixture;
  const auto definition = dynamic_definition();
  const auto document = definitions::canonical_definition_document(definition, 1);
  require(!document.empty(), "dynamic definition document was empty");
  const auto file = fixture.package() / "test.capability";
  {
    std::ofstream output(file, std::ios::binary);
    output << document;
  }
  require(::chmod(file.c_str(), 0644) == 0,
          "dynamic definition mode setup failed");
  channel::RuntimeBootstrapError error{};
  auto bootstrap = load(fixture, error);
  const auto loaded = bootstrap
                          ? channel::RuntimeBootstrapTestAccess::definition(
                                *bootstrap, definition.canonical_name.view())
                          : std::nullopt;
  require(bootstrap && error == channel::RuntimeBootstrapError::none &&
              loaded && loaded->generation == 1 &&
              loaded->digest == definitions::definition_digest(definition) &&
              loaded->definition->adapter == definition.adapter,
          "trusted definition was coupled to provider availability");
}

} // namespace

int main() {
  try {
    empty_package_and_absent_admin_compose_one_shared_context();
    authority_cannot_cross_runtime_service_identity();
    mandatory_package_and_optional_admin_are_exact();
    authority_children_are_exact_and_never_created();
    authority_stores_are_physically_isolated_per_plugin();
    trusted_definition_loads_without_a_provider();
    return 0;
  } catch (const std::exception &error) {
    std::cerr << "runtime bootstrap test failed: " << error.what()
              << '\n';
    return 1;
  }
}
