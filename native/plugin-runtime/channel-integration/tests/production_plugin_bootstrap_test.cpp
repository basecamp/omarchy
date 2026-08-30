#include "production_plugin_bootstrap.hpp"

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

class Hooks final : public channel::ProductionPluginRuntimeHooks {
public:
  void state_changed(host_session::SessionState,
                     host_session::SessionError) override {}
  void control_received(const host_session::OwnedMessage &) override {}
  void render_rejected(host_session::RouteResult) override {}
  bool accept(host_session::AdmittedSurfaceIntent) override {
    return false;
  }
};

class Fixture final {
public:
  Fixture() {
    std::string pattern = "/tmp/omarchy-production-bootstrap.XXXXXX";
    const auto *created = ::mkdtemp(pattern.data());
    require(created != nullptr, "bootstrap fixture creation failed");
    root_ = created;
    require(::chmod(root_.c_str(), 0755) == 0,
            "fixture root mode setup failed");
    home_ = root_ / "user-home";
    create(home_, 0700);
    create(home_ / ".local/share/omarchy/plugin-security/v2/revisions", 0700);
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
  [[nodiscard]] int open_root() const {
    return ::open(root_.c_str(),
                  O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
  }
  [[nodiscard]] std::unique_ptr<channel::ProductionPluginRoots> roots() const {
    const int home = ::open(home_.c_str(),
                            O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
    require(home >= 0, "fixture home descriptor unavailable");
    channel::ProductionPluginRootsError error{};
    auto result = channel::ProductionPluginRootsTestAccess::open_from_home_fd(
        home, static_cast<std::uint32_t>(::getuid()), error);
    ::close(home);
    require(result && error == channel::ProductionPluginRootsError::none,
            "fixture production roots unavailable");
    return result;
  }
  void create_admin(mode_t mode = 0755) {
    create(admin(), mode);
  }
  void create_authority(std::string_view plugin, mode_t mode = 0700) {
    create(authority(plugin), mode);
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

std::unique_ptr<channel::ProductionPluginBootstrap>
load(Fixture &fixture, channel::ProductionPluginBootstrapError &error) {
  const int root = fixture.open_root();
  require(root >= 0, "fixture filesystem root unavailable");
  auto result = channel::ProductionPluginBootstrapTestAccess::
      open_from_filesystem_root(fixture.roots(), root,
                                static_cast<std::uint32_t>(::getuid()), error);
  ::close(root);
  return result;
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
                  .implementation_digest =
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
  channel::ProductionPluginBootstrapError error{};
  auto bootstrap = load(fixture, error);
  require(bootstrap && error == channel::ProductionPluginBootstrapError::none &&
              bootstrap->definitions().size() == 0 &&
              bootstrap->services().notification_send == nullptr &&
              bootstrap->services().audio_play == nullptr &&
              bootstrap->services().dynamic_services.empty(),
          "fixed empty bootstrap did not compose fail-unavailable services");

  Hooks hooks;
  const permissions::PluginId plugin("example.plugin");
  auto first = channel::ProductionPluginBootstrapTestAccess::configuration(
      *bootstrap, "example.plugin", plugin, &hooks);
  auto second = channel::ProductionPluginBootstrapTestAccess::configuration(
      *bootstrap, "example.plugin", plugin, &hooks);
  require(first && second && first->definitions == second->definitions &&
              first->services == second->services &&
              first->definitions.get() == &bootstrap->definitions() &&
              first->services.get() == &bootstrap->services(),
          "plugin configurations copied their trusted host context");
  require(!channel::ProductionPluginBootstrapTestAccess::configuration(
              *bootstrap, "other.plugin", plugin, &hooks) &&
              !channel::ProductionPluginBootstrapTestAccess::configuration(
                  *bootstrap, "example.plugin", plugin, nullptr),
          "unmatched or hookless activation candidate was accepted");
}

void mandatory_package_and_optional_admin_are_exact() {
  {
    Fixture fixture;
    channel::ProductionPluginBootstrapError error{};
    require(!channel::ProductionPluginBootstrapTestAccess::
                 open_from_filesystem_root(
                     fixture.roots(), -1,
                     static_cast<std::uint32_t>(::getuid()), error) &&
                error == channel::ProductionPluginBootstrapError::
                             package_definitions_untrusted,
            "invalid fixed filesystem descriptor was accepted");
  }
  {
    Fixture fixture;
    std::filesystem::remove(fixture.package());
    channel::ProductionPluginBootstrapError error{};
    require(!load(fixture, error) &&
                error == channel::ProductionPluginBootstrapError::
                             package_definitions_unavailable,
            "missing mandatory package definitions were accepted");
  }
  {
    Fixture fixture;
    require(::chmod(fixture.package().c_str(), 0775) == 0,
            "package trust-root mode setup failed");
    channel::ProductionPluginBootstrapError error{};
    require(!load(fixture, error) &&
                error == channel::ProductionPluginBootstrapError::
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
    channel::ProductionPluginBootstrapError error{};
    require(!load(fixture, error) &&
                error == channel::ProductionPluginBootstrapError::
                             package_definitions_untrusted,
            "symlinked package definitions were accepted");
  }
  {
    Fixture fixture;
    fixture.create_admin(0775);
    channel::ProductionPluginBootstrapError error{};
    require(!load(fixture, error) &&
                error == channel::ProductionPluginBootstrapError::
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
    channel::ProductionPluginBootstrapError error{};
    require(!load(fixture, error) &&
                error == channel::ProductionPluginBootstrapError::
                             definition_document_rejected,
            "malformed admin document entered a partial bootstrap");
  }
}

void authority_children_are_exact_and_never_created() {
  const auto uid = static_cast<std::uint32_t>(::getuid());
  require(channel::ProductionPluginBootstrapTestAccess::
                  authority_directory_accepted(uid, S_IFDIR | 0700, uid) &&
              !channel::ProductionPluginBootstrapTestAccess::
                  authority_directory_accepted(uid + 1, S_IFDIR | 0700, uid) &&
              !channel::ProductionPluginBootstrapTestAccess::
                  authority_directory_accepted(uid, S_IFDIR | 0750, uid) &&
              !channel::ProductionPluginBootstrapTestAccess::
                  authority_directory_accepted(uid, S_IFREG | 0700, uid),
          "per-plugin authority metadata predicate widened ownership or mode");

  Hooks hooks;
  const permissions::PluginId plugin("example.plugin");
  {
    Fixture fixture;
    std::filesystem::remove(fixture.authority("example.plugin"));
    channel::ProductionPluginBootstrapError error{};
    auto bootstrap = load(fixture, error);
    require(bootstrap &&
                !channel::ProductionPluginBootstrapTestAccess::configuration(
                    *bootstrap, "example.plugin", plugin, &hooks) &&
                !std::filesystem::exists(fixture.authority("example.plugin")),
            "bootstrap created a missing authority child");
  }
  {
    Fixture fixture;
    require(::chmod(fixture.authority("example.plugin").c_str(), 0750) == 0,
            "authority mode fixture setup failed");
    channel::ProductionPluginBootstrapError error{};
    auto bootstrap = load(fixture, error);
    require(bootstrap &&
                !channel::ProductionPluginBootstrapTestAccess::configuration(
                    *bootstrap, "example.plugin", plugin, &hooks),
            "widened per-plugin authority directory was accepted");
  }
  {
    Fixture fixture;
    const auto child = fixture.authority("example.plugin");
    const auto target = fixture.authority("alternate.plugin");
    std::filesystem::remove(child);
    fixture.create_authority("alternate.plugin");
    std::filesystem::create_directory_symlink(target, child);
    channel::ProductionPluginBootstrapError error{};
    auto bootstrap = load(fixture, error);
    require(bootstrap &&
                !channel::ProductionPluginBootstrapTestAccess::configuration(
                    *bootstrap, "example.plugin", plugin, &hooks),
            "symlinked per-plugin authority directory was accepted");
  }
  {
    Fixture fixture;
    channel::ProductionPluginBootstrapError error{};
    auto bootstrap = load(fixture, error);
    const permissions::PluginId path_plugin("../example.plugin");
    require(bootstrap &&
                !channel::ProductionPluginBootstrapTestAccess::configuration(
                    *bootstrap, path_plugin.view(), path_plugin, &hooks),
            "noncanonical plugin name selected an authority path");
  }
}

void authority_stores_are_physically_isolated_per_plugin() {
  Fixture fixture;
  fixture.create_authority("second.plugin");
  channel::ProductionPluginBootstrapError error{};
  auto bootstrap = load(fixture, error);
  Hooks hooks;
  const permissions::PluginId first_plugin("example.plugin");
  const permissions::PluginId second_plugin("second.plugin");
  auto first_configuration =
      channel::ProductionPluginBootstrapTestAccess::configuration(
          *bootstrap, first_plugin.view(), first_plugin, &hooks);
  auto second_configuration =
      channel::ProductionPluginBootstrapTestAccess::configuration(
          *bootstrap, second_plugin.view(), second_plugin, &hooks);
  require(first_configuration && second_configuration &&
              first_configuration->authority_root &&
              second_configuration->authority_root &&
              (::fcntl(first_configuration->authority_root.get(), F_GETFD) &
               FD_CLOEXEC) != 0 &&
              (::fcntl(second_configuration->authority_root.get(), F_GETFD) &
               FD_CLOEXEC) != 0,
          "exact per-plugin authority descriptors were unavailable");

  auto first_store = host_session::AuthorityStore::open(
      first_configuration->authority_root.get(), ::getuid(), first_plugin);
  auto second_store = host_session::AuthorityStore::open(
      second_configuration->authority_root.get(), ::getuid(), second_plugin);
  require(first_store && second_store,
          "different plugin authority locks could not coexist");
  require(!host_session::AuthorityStore::open(
              first_configuration->authority_root.get(), ::getuid(),
              first_plugin),
          "a second owner acquired the same plugin authority lock");

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
  require(first_store->resolve(first_plugin.view(), hex('a')) &&
              second_store->resolve(second_plugin.view(), hex('b')),
          "one plugin authority snapshot replaced another");

  auto replacement = review(first_plugin.view(), 2, 'c');
  require(first_store->publish_candidate(replacement.verified,
                                         replacement.snapshot, 2, registry,
                                         {}) ==
                  host_session::AuthorityMutationResult::applied &&
              first_store->discard_candidate(replacement.snapshot.binding,
                                             3) ==
                  host_session::AuthorityMutationResult::applied &&
              second_store->resolve(second_plugin.view(), hex('b')),
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
  auto first_root = channel::ProductionPluginRuntimeRoot::open(
      std::move(*first_configuration));
  auto second_root = channel::ProductionPluginRuntimeRoot::open(
      std::move(*second_configuration));
  auto duplicate_configuration =
      channel::ProductionPluginBootstrapTestAccess::configuration(
          *bootstrap, first_plugin.view(), first_plugin, &hooks);
  require(first_root && second_root && duplicate_configuration &&
              !channel::ProductionPluginRuntimeRoot::open(
                  std::move(*duplicate_configuration)),
          "per-plugin product roots did not preserve independent lock scope");
}

void every_unregistered_native_adapter_fails_closed() {
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
  channel::ProductionPluginBootstrapError error{};
  require(!load(fixture, error) &&
              error == channel::ProductionPluginBootstrapError::
                           definition_adapter_unavailable &&
              !channel::ProductionPluginBootstrapTestAccess::adapter_available(
                  definition.adapter.adapter_class.view(),
                  definition.adapter.implementation_digest,
                  definition.adapter.abi_version),
          "unregistered native adapter entered the frozen registry");
}

} // namespace

int main() {
  try {
    empty_package_and_absent_admin_compose_one_shared_context();
    mandatory_package_and_optional_admin_are_exact();
    authority_children_are_exact_and_never_created();
    authority_stores_are_physically_isolated_per_plugin();
    every_unregistered_native_adapter_fails_closed();
    return 0;
  } catch (const std::exception &error) {
    std::cerr << "production plugin bootstrap test failed: " << error.what()
              << '\n';
    return 1;
  }
}
