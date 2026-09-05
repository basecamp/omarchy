#include "runtime_bootstrap.hpp"
#include "runtime_roots_test_access.hpp"

#include "capability_definition_loader.hpp"
#include "omarchy/plugin_runtime/Version.h"
#include "omarchy/plugin_runtime/broker/broker_schema.hpp"
#include "structured_broker.hpp"

#include <fcntl.h>
#include <signal.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

#include <array>
#include <cerrno>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <span>
#include <stdexcept>
#include <string>
#include <string_view>
#include <vector>

namespace channel = omarchy::plugin_runtime::channel;
namespace definitions = omarchy::plugins::definitions;
namespace host = omarchy::plugin_runtime::host_session;
namespace manifest = omarchy::plugins::manifest;
namespace permissions = omarchy::plugins::permissions;
namespace policy = omarchy::plugin_runtime::policy;
namespace runtime = omarchy::plugin_runtime::runtime;
namespace wire = omarchy::plugin::wire;
namespace broker = omarchy::plugin_runtime::broker;

namespace {

void require(bool condition, std::string_view message) {
  if (!condition)
    throw std::runtime_error(std::string(message));
}

std::string repeated(char value) { return std::string(64, value); }

std::string read_file(const std::filesystem::path &path) {
  std::ifstream input(path, std::ios::binary);
  return {std::istreambuf_iterator<char>(input),
          std::istreambuf_iterator<char>()};
}

void secure_directory(const std::filesystem::path &path, mode_t mode) {
  std::filesystem::create_directories(path);
  require(::chmod(path.c_str(), mode) == 0, "directory mode setup failed");
}

bool change_owner_for_test(const std::filesystem::path &path, uid_t uid,
                           gid_t gid) {
  if (::chown(path.c_str(), uid, gid) == 0)
    return true;
  struct stat metadata{};
  return ::getenv("OMARCHY_TEST_FAKE_OWNERSHIP") != nullptr &&
         ::stat(path.c_str(), &metadata) == 0 && metadata.st_uid == uid &&
         metadata.st_gid == gid;
}

definitions::CapabilityDefinition definition() {
  definitions::CapabilityDefinition value{
      .canonical_name = definitions::Name("service.echo"),
      .authority_identity = definitions::Name("service.echo.authority"),
      .enforcement_family = definitions::EnforcementFamily::network_fetch,
      .display_category_id = definitions::Name("developer.services"),
      .display_category_label = definitions::Label("Developer services"),
      .scope_schema = definitions::ScopeSchema::https_origins_and_methods,
      .title = definitions::Label("Echo"),
      .risk_text = definitions::Label("Uses a trusted echo service"),
      .risk = definitions::RiskLevel::moderate,
      .revocation = definitions::RevocationPolicy::deny_new,
      .audit = {},
      .adapter = {.adapter_class = definitions::Name("service.echo.adapter"),
                  .contract_digest = permissions::Digest(repeated('d')),
                  .abi_version = 1},
      .operations = {}};
  require(
      value.operations.insert({.name = definitions::Name("echo"),
                               .label = definitions::Label("Echo payload")}),
      "operation setup failed");
  return value;
}

class Clock final : public runtime::GestureEligibilityClock {
public:
  [[nodiscard]] std::uint64_t now_nanoseconds() const override { return 1; }
};

std::shared_ptr<runtime::GestureEligibilityLatch> gesture() {
  return std::make_shared<runtime::GestureEligibilityLatch>(
      std::make_shared<Clock>());
}

struct Fixture final {
  std::filesystem::path root;
  std::filesystem::path home;
  std::filesystem::path marker;
  std::filesystem::path executable;
  std::filesystem::path profile;
  int revision_fd = -1;
  int state_fd = -1;

  explicit Fixture(std::string_view mode = "ok") {
    auto pattern = (std::filesystem::temp_directory_path() /
                    "omarchy-provider-composition-XXXXXX")
                       .string();
    pattern.push_back('\0');
    const auto *created = ::mkdtemp(pattern.data());
    require(created != nullptr, "fixture creation failed");
    root = created;
    home = root / "home";
    marker = root / "started";
    executable = root / "usr/lib/omarchy/plugin-security/provider-peer";
    profile = root / "usr/lib/omarchy/plugin-security" /
              std::string(omarchy::plugin_runtime::build_version()) /
              "providers.d/echo.profile";

    require(::chmod(root.c_str(), 0755) == 0, "fixture root mode failed");
    secure_directory(home, 0700);
    secure_directory(home / ".local/share/omarchy-plugin-security/v2/revisions",
                     0700);
    secure_directory(
        home / ".local/state/omarchy/plugin-security/v2/activations", 0700);
    secure_directory(home / ".local/state/omarchy/plugin-security/v2/authority",
                     0700);
    secure_directory(home / ".local/state/omarchy/plugin-security/v2/state",
                     0700);
    secure_directory(root / "revision", 0700);
    secure_directory(root / "state", 0700);

    const auto version_root =
        root / "usr/lib/omarchy/plugin-security" /
        std::string(omarchy::plugin_runtime::build_version());
    secure_directory(root / "usr", 0755);
    secure_directory(root / "usr/lib", 0755);
    secure_directory(root / "usr/lib/omarchy", 0755);
    secure_directory(root / "usr/lib/omarchy/plugin-security", 0755);
    secure_directory(version_root, 0755);
    secure_directory(version_root / "capabilities.d", 0755);
    secure_directory(version_root / "providers.d", 0755);
    std::filesystem::copy_file(PROVIDER_COMPOSITION_PEER_PATH, executable);
    require(::chmod(executable.c_str(), 0500) == 0,
            "provider executable mode failed");
    write_definition();
    write_profile(mode);

    revision_fd = ::open((root / "revision").c_str(),
                         O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
    state_fd = ::open((root / "state").c_str(),
                      O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
    require(revision_fd >= 0 && state_fd >= 0,
            "session descriptors unavailable");
  }

  ~Fixture() {
    if (revision_fd >= 0)
      ::close(revision_fd);
    if (state_fd >= 0)
      ::close(state_fd);
    std::error_code ignored;
    std::filesystem::remove_all(root, ignored);
  }

  void write_definition() const {
    const auto document =
        definitions::canonical_definition_document(definition(), 1);
    require(!document.empty(), "definition serialization failed");
    const auto path = profile.parent_path().parent_path() /
                      "capabilities.d/service.echo.capability";
    std::ofstream(path, std::ios::binary) << document;
    require(::chmod(path.c_str(), 0644) == 0, "definition mode failed");
  }

  void write_profile(std::string_view mode,
                     std::string_view adapter = "service.echo.adapter",
                     std::string_view contract = repeated('d'),
                     std::uint32_t abi = 1,
                     std::string_view executable_path =
                         "/usr/lib/omarchy/plugin-security/provider-peer",
                     std::string_view digest = {}) const {
    std::ofstream output(profile);
    output << "schema=1\n"
           << "adapter-class=" << adapter << "\n"
           << "contract-digest=" << contract << "\n"
           << "abi-version=" << abi << "\n"
           << "group=echo.group\n"
           << "executable=" << executable_path << "\n"
           << "executable-sha256="
           << (digest.empty() ? manifest::sha256_hex(read_file(executable))
                              : std::string(digest))
           << "\narg=" << mode << "\narg=" << marker.string() << "\n";
    output.close();
    require(::chmod(profile.c_str(), 0644) == 0, "profile mode failed");
  }

  [[nodiscard]] std::unique_ptr<channel::RuntimeRoots> roots() const {
    const int home_fd =
        ::open(home.c_str(), O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
    require(home_fd >= 0, "home descriptor unavailable");
    channel::RuntimeRootsError error{};
    auto result = channel::RuntimeRootsTestAccess::open_from_home_fd(
        home_fd, static_cast<std::uint32_t>(::getuid()), error);
    ::close(home_fd);
    require(result && error == channel::RuntimeRootsError::none,
            "runtime roots rejected");
    return result;
  }

  [[nodiscard]] std::unique_ptr<channel::RuntimeBootstrap>
  bootstrap(channel::RuntimeBootstrapError &error) const {
    const int root_fd =
        ::open(root.c_str(), O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
    require(root_fd >= 0, "filesystem root unavailable");
    auto result =
        channel::RuntimeBootstrapTestAccess::open_from_filesystem_root(
            roots(), root_fd, static_cast<std::uint32_t>(::getuid()), error);
    ::close(root_fd);
    return result;
  }

  [[nodiscard]] std::size_t starts() const {
    std::ifstream input(marker);
    std::size_t count = 0;
    std::string line;
    while (std::getline(input, line))
      ++count;
    return count;
  }
};

manifest::ManifestV2
plugin_manifest(const definitions::ResolvedDefinition &resolved,
                bool required = false) {
  manifest::ManifestV2 value;
  value.id = "fixture.plugin";
  value.requests.push_back(
      {.capability = std::string(resolved.definition->canonical_name.view()),
       .reason = "exercise product provider composition",
       .canonical_scope = "exact",
       .definition_generation = resolved.generation,
       .definition_digest = std::string(resolved.digest.view()),
       .operations = {"echo"},
       .required = required});
  return value;
}

policy::GrantSnapshot snapshot(const definitions::ResolvedDefinition &resolved,
                               permissions::GrantState state,
                               bool required = false,
                               std::uint64_t generation = 7) {
  const auto plugin = plugin_manifest(resolved, required);
  policy::GrantSnapshot value;
  value.requests = permissions::requests_from_manifest(plugin);
  value.binding = {.plugin = permissions::PluginId(plugin.id),
                   .revision = permissions::Digest(repeated('a')),
                   .policy_fingerprint = permissions::Digest(
                       permissions::policy_request_fingerprint(value.requests)),
                   .generation = generation};
  value.source_request_fingerprint = permissions::Digest(
      manifest::requested_capability_fingerprint(plugin.requests));
  definitions::DynamicRevisionGrant grant{
      .binding = value.binding,
      .request = {.definition = {.canonical_name =
                                     resolved.definition->canonical_name,
                                 .definition_generation = resolved.generation,
                                 .definition_digest = resolved.digest},
                  .operations = {},
                  .scope = definitions::CanonicalScope("exact"),
                  .required = required},
      .grant = {}};
  require(grant.request.operations.insert(definitions::Name("echo")),
          "grant operation setup failed");
  grant.grant = {.definition = grant.request.definition,
                 .operations = grant.request.operations,
                 .scope = grant.request.scope,
                 .state = state,
                 .epoch = 7};
  value.dynamic_grants.push_back(std::move(grant));
  return value;
}

std::vector<std::byte> invocation(const policy::GrantSnapshot &grants) {
  const definitions::DynamicInvocation call{
      .definition = grants.dynamic_grants[0].request.definition,
      .operation = definitions::Name("echo"),
      .demand_scope = definitions::CanonicalScope("exact"),
      .gesture = std::nullopt,
      .payload = {}};
  std::vector<std::byte> encoded(definitions::kMaximumDynamicEnvelopeBytes);
  std::size_t written = 0;
  require(definitions::encode_dynamic_invocation(call, encoded, written),
          "invocation encoding failed");
  encoded.resize(written);
  return encoded;
}

std::unique_ptr<channel::AuthenticatedSessionRuntime> create_runtime(
    const channel::RuntimeBootstrap &bootstrap, const Fixture &fixture,
    const manifest::ManifestV2 &plugin, const policy::GrantSnapshot &grants,
    std::shared_ptr<host::LiveGenerationState> live, std::uint64_t nonce = 41) {
  return channel::RuntimeBootstrapTestAccess::create_session_runtime(
      bootstrap, plugin, grants, fixture.revision_fd, fixture.state_fd, nonce,
      std::move(live), gesture());
}

host::BrokerTransaction dispatch(channel::AuthenticatedSessionRuntime &product,
                                 host::AuthenticatedBrokerAdmission &admission,
                                 const policy::GrantSnapshot &grants,
                                 std::uint64_t correlation,
                                 std::span<std::byte> response) {
  const auto payload = invocation(grants);
  auto admitted =
      admission.admit({.message_type = broker::kDynamicInvokeMessage,
                       .correlation_id = correlation,
                       .payload = payload});
  require(static_cast<bool>(admitted), "request admission failed");
  return product.broker().dispatch(std::move(*admitted.request), correlation,
                                   response);
}

void exact_identity_and_pinned_dispatch() {
  Fixture fixture;
  channel::RuntimeBootstrapError error{};
  auto bootstrap = fixture.bootstrap(error);
  require(bootstrap && error == channel::RuntimeBootstrapError::none,
          "exact bootstrap rejected: " +
              std::to_string(static_cast<unsigned>(error)));
  const auto resolved = channel::RuntimeBootstrapTestAccess::definition(
      *bootstrap, "service.echo");
  require(resolved.has_value(), "exact definition absent");
  const auto grants = snapshot(*resolved, permissions::GrantState::granted);
  const auto plugin = plugin_manifest(*resolved);
  const auto projected =
      channel::RuntimeBootstrapTestAccess::project_permissions(*bootstrap,
                                                               plugin, grants);
  require(projected && projected->permissions.size() == 1 &&
              projected->permissions[0] ==
                  wire::permission_snapshot::PermissionRow{
                      wire::permission_snapshot::GrantState::granted, 1},
          "exact class/contract/ABI did not become available");

  std::filesystem::rename(fixture.executable,
                          fixture.executable.string() + ".pinned");
  std::ofstream(fixture.executable) << "replacement must never execute\n";
  require(::chmod(fixture.executable.c_str(), 0500) == 0,
          "replacement mode failed");
  auto live = std::make_shared<host::LiveGenerationState>(grants.binding);
  auto product = create_runtime(*bootstrap, fixture, plugin, grants, live);
  require(static_cast<bool>(product), "pinned product runtime rejected");
  auto extracted = product->broker().take_admission();
  require(static_cast<bool>(extracted), "product admission unavailable");
  std::array<std::byte, 128> response{};
  auto result = dispatch(*product, *extracted.admission, grants, 1, response);
  require(result.state() == host::TransactionState::reply &&
              result.reply_kind() == host::ReplyKind::result &&
              fixture.starts() == 1,
          "post-load path replacement defeated pinned dispatch");
  require(product->broker().commit_sent(std::move(result)),
          "pinned provider transaction did not settle");
}

void unavailable_and_denied_never_launch() {
  for (const auto &mismatch :
       {std::string("class"), std::string("contract"), std::string("abi")}) {
    Fixture fixture;
    if (mismatch == "class")
      fixture.write_profile("ok", "service.other.adapter");
    else if (mismatch == "contract")
      fixture.write_profile("ok", "service.echo.adapter", repeated('e'));
    else
      fixture.write_profile("ok", "service.echo.adapter", repeated('d'), 2);
    channel::RuntimeBootstrapError error{};
    auto bootstrap = fixture.bootstrap(error);
    require(static_cast<bool>(bootstrap),
            "mismatch bootstrap unexpectedly failed");
    const auto resolved = channel::RuntimeBootstrapTestAccess::definition(
        *bootstrap, "service.echo");
    require(resolved.has_value(), "mismatch definition absent");
    const auto optional = snapshot(*resolved, permissions::GrantState::granted);
    const auto plugin = plugin_manifest(*resolved);
    const auto projected =
        channel::RuntimeBootstrapTestAccess::project_permissions(
            *bootstrap, plugin, optional);
    auto live = std::make_shared<host::LiveGenerationState>(optional.binding);
    auto product = create_runtime(*bootstrap, fixture, plugin, optional, live);
    require(projected && projected->permissions[0].operation_mask == 0 &&
                product && fixture.starts() == 0,
            "optional exact-binding mismatch was not masked without launch");
    auto admission = product->broker().take_admission();
    std::array<std::byte, 64> response{};
    auto denied =
        dispatch(*product, *admission.admission, optional, 1, response);
    require(denied.state() == host::TransactionState::reply &&
                denied.reply_kind() == host::ReplyKind::denied &&
                product->broker().commit_sent(std::move(denied)) &&
                fixture.starts() == 0,
            "masked optional request escaped to a provider");

    const auto required =
        snapshot(*resolved, permissions::GrantState::granted, true);
    const auto required_plugin = plugin_manifest(*resolved, true);
    auto required_live =
        std::make_shared<host::LiveGenerationState>(required.binding);
    require(!channel::RuntimeBootstrapTestAccess::project_permissions(
                *bootstrap, required_plugin, required) &&
                !create_runtime(*bootstrap, fixture, required_plugin, required,
                                required_live) &&
                fixture.starts() == 0,
            "required unavailable provider activated");
  }

  Fixture denied_fixture;
  channel::RuntimeBootstrapError error{};
  auto bootstrap = denied_fixture.bootstrap(error);
  const auto resolved = channel::RuntimeBootstrapTestAccess::definition(
      *bootstrap, "service.echo");
  const auto denied = snapshot(*resolved, permissions::GrantState::denied);
  const auto plugin = plugin_manifest(*resolved);
  const auto projected =
      channel::RuntimeBootstrapTestAccess::project_permissions(*bootstrap,
                                                               plugin, denied);
  auto live = std::make_shared<host::LiveGenerationState>(denied.binding);
  auto product =
      create_runtime(*bootstrap, denied_fixture, plugin, denied, live);
  require(projected && projected->permissions[0].operation_mask == 0 && product,
          "explicit denial did not create a zero-authority runtime");
  auto admission = product->broker().take_admission();
  std::array<std::byte, 64> response{};
  auto result = dispatch(*product, *admission.admission, denied, 1, response);
  require(result.state() == host::TransactionState::reply &&
              result.reply_kind() == host::ReplyKind::denied &&
              product->broker().commit_sent(std::move(result)) &&
              denied_fixture.starts() == 0,
          "explicitly denied provider launched");
}

void bootstrap_rejects_provider_tamper() {
  auto rejected = [](Fixture &fixture, std::string_view message) {
    channel::RuntimeBootstrapError error{};
    require(!fixture.bootstrap(error) &&
                error ==
                    channel::RuntimeBootstrapError::provider_profiles_untrusted,
            message);
  };
  {
    Fixture fixture;
    require(::chmod(fixture.profile.parent_path().c_str(), 0775) == 0,
            "provider root mutation failed");
    rejected(fixture, "group-writable fixed provider root accepted");
  }
  {
    Fixture fixture;
    require(::chmod(fixture.profile.c_str(), 0664) == 0,
            "profile mutation failed");
    rejected(fixture, "group-writable profile accepted");
  }
  {
    Fixture fixture;
    require(::chmod(fixture.executable.c_str(), 0520) == 0,
            "executable mutation failed");
    rejected(fixture, "group-writable executable accepted");
  }
  {
    Fixture fixture;
    fixture.write_profile("ok", "service.echo.adapter", repeated('d'), 1,
                          "/usr/lib/omarchy/plugin-security/provider-peer",
                          repeated('f'));
    rejected(fixture, "wrong executable hash accepted");
  }
  {
    Fixture fixture;
    fixture.write_profile(
        "ok", "service.echo.adapter", repeated('d'), 1,
        "/usr/lib/omarchy/plugin-security/../plugin-security/provider-peer");
    rejected(fixture, "noncanonical executable path accepted");
  }
  {
    Fixture fixture;
    std::filesystem::rename(fixture.executable,
                            fixture.executable.string() + ".real");
    std::filesystem::create_symlink("provider-peer.real", fixture.executable);
    rejected(fixture, "symlink executable accepted");
  }
  {
    Fixture fixture;
    std::filesystem::rename(fixture.profile,
                            fixture.profile.string() + ".real");
    std::filesystem::create_symlink("echo.profile.real", fixture.profile);
    rejected(fixture, "symlink profile accepted");
  }
  {
    Fixture fixture;
    const auto directory = fixture.profile.parent_path();
    const auto real = directory.string() + ".real";
    std::filesystem::rename(directory, real);
    std::filesystem::create_symlink(std::filesystem::path(real).filename(),
                                    directory);
    rejected(fixture, "symlink fixed provider root accepted");
  }
  if (::geteuid() == 0 || ::getenv("OMARCHY_TEST_FAKE_OWNERSHIP") != nullptr) {
    {
      Fixture fixture;
      require(
          change_owner_for_test(fixture.profile.parent_path(), 65534, 65534),
          "provider root ownership mutation failed");
      rejected(fixture, "wrong-owner fixed provider root accepted");
    }
    {
      Fixture fixture;
      require(change_owner_for_test(fixture.profile, 65534, 65534),
              "profile ownership mutation failed");
      rejected(fixture, "wrong-owner profile accepted");
    }
    {
      Fixture fixture;
      require(change_owner_for_test(fixture.executable, 65534, 65534),
              "executable ownership mutation failed");
      rejected(fixture, "wrong-owner executable accepted");
    }
  }
}

void provider_failures_are_fail_stop_and_reaped() {
  for (const std::string mode :
       {"crash", "timeout", "malformed", "truncated", "oversized", "late"}) {
    Fixture fixture(mode);
    channel::RuntimeBootstrapError error{};
    auto bootstrap = fixture.bootstrap(error);
    require(static_cast<bool>(bootstrap), "failure fixture bootstrap failed");
    const auto resolved = channel::RuntimeBootstrapTestAccess::definition(
        *bootstrap, "service.echo");
    const auto grants = snapshot(*resolved, permissions::GrantState::granted);
    const auto plugin = plugin_manifest(*resolved);
    auto live = std::make_shared<host::LiveGenerationState>(grants.binding);
    auto product = create_runtime(*bootstrap, fixture, plugin, grants, live);
    require(static_cast<bool>(product), "failure fixture runtime failed");
    auto admission = product->broker().take_admission();
    std::array<std::byte, 128> response{};
    auto first = dispatch(*product, *admission.admission, grants, 1, response);
    require(first.state() == host::TransactionState::reply &&
                first.reply_kind() == host::ReplyKind::provider_failed &&
                product->broker().commit_sent(std::move(first)) &&
                fixture.starts() == 1,
            "provider failure did not fail closed");
    auto second = dispatch(*product, *admission.admission, grants, 2, response);
    require(second.state() == host::TransactionState::reply &&
                second.reply_kind() == host::ReplyKind::provider_failed &&
                product->broker().commit_sent(std::move(second)) &&
                fixture.starts() == 1,
            "failed provider restarted");
    errno = 0;
    require(::waitpid(-1, nullptr, WNOHANG) < 0 && errno == ECHILD,
            "failed provider was not reaped");
  }
}

void activation_and_admission_binding() {
  Fixture fixture("pid");
  channel::RuntimeBootstrapError error{};
  auto bootstrap = fixture.bootstrap(error);
  const auto resolved = channel::RuntimeBootstrapTestAccess::definition(
      *bootstrap, "service.echo");
  const auto first_grants =
      snapshot(*resolved, permissions::GrantState::granted, false, 7);
  const auto second_grants =
      snapshot(*resolved, permissions::GrantState::granted, false, 8);
  const auto plugin = plugin_manifest(*resolved);
  auto first_live =
      std::make_shared<host::LiveGenerationState>(first_grants.binding);
  auto second_live =
      std::make_shared<host::LiveGenerationState>(second_grants.binding);
  auto first =
      create_runtime(*bootstrap, fixture, plugin, first_grants, first_live, 51);
  auto second = create_runtime(*bootstrap, fixture, plugin, second_grants,
                               second_live, 52);
  require(first && second, "cross-activation fixtures rejected");
  auto first_admission = first->broker().take_admission();
  auto second_admission = second->broker().take_admission();
  const auto payload = invocation(first_grants);
  auto foreign = first_admission.admission->admit(
      {.message_type = broker::kDynamicInvokeMessage,
       .correlation_id = 1,
       .payload = payload});
  require(static_cast<bool>(foreign), "foreign request admission failed");
  std::array<std::byte, 128> response{};
  auto rejected =
      second->broker().dispatch(std::move(*foreign.request), 1, response);
  require(rejected.state() == host::TransactionState::fatal &&
              fixture.starts() == 0,
          "cross-activation admitted handle replay reached provider");
  auto duplicate = first_admission.admission->admit(
      {.message_type = broker::kDynamicInvokeMessage,
       .correlation_id = 1,
       .payload = payload});
  require(!duplicate, "correlation replay was admitted");

  auto valid =
      dispatch(*first, *first_admission.admission, first_grants, 2, response);
  require(valid.state() == host::TransactionState::reply &&
              valid.reply_kind() == host::ReplyKind::result &&
              first->broker().commit_sent(std::move(valid)) &&
              fixture.starts() == 1,
          "valid activation did not dispatch once");
  const auto marker = read_file(fixture.marker);
  const auto pid = static_cast<pid_t>(std::stol(marker));
  require(first_live->revoke_and_drain() ==
              host::LiveGenerationRevokeResult::drained,
          "generation revocation did not drain");
  auto revoked =
      dispatch(*first, *first_admission.admission, first_grants, 3, response);
  require(revoked.state() == host::TransactionState::fatal &&
              fixture.starts() == 1,
          "revoked generation reached provider");
  first.reset();
  errno = 0;
  require(::kill(pid, 0) < 0 && errno == ESRCH,
          "runtime teardown left provider alive");
  errno = 0;
  require(::waitpid(-1, nullptr, WNOHANG) < 0 && errno == ECHILD,
          "runtime teardown did not reap provider");
  (void)second_admission;
}

} // namespace

int main() {
  try {
    if (::getenv("OMARCHY_TEST_FAKE_OWNERSHIP") != nullptr) {
      // fakeroot deliberately reports uid 0, so the production resource-scope
      // controller would probe /run/user/0 instead of the caller's real user
      // bus. This pass exists only for the ownership mutations below; the
      // ordinary test already covers composition and provider lifecycles.
      bootstrap_rejects_provider_tamper();
      std::cout << "provider composition ownership tests passed\n";
      return 0;
    }
    exact_identity_and_pinned_dispatch();
    unavailable_and_denied_never_launch();
    bootstrap_rejects_provider_tamper();
    provider_failures_are_fail_stop_and_reaped();
    activation_and_admission_binding();
    std::cout << "provider composition tests passed\n";
    return 0;
  } catch (const std::exception &error) {
    std::cerr << "provider composition test failed: " << error.what() << '\n';
    return 1;
  }
}
