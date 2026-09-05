#include "runtime_roots.hpp"
#include "runtime_roots_test_access.hpp"
#include "activation_catalog.hpp"
#include "consent_review.hpp"
#include "revision_verifier_adapter.hpp"
#include "plugin_permission_authority_test_access.hpp"

#include <fcntl.h>
#include <pwd.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

#include <array>
#include <barrier>
#include <atomic>
#include <cerrno>
#include <filesystem>
#include <functional>
#include <iostream>
#include <stdexcept>
#include <string>
#include <string_view>
#include <thread>

namespace channel = omarchy::plugin_runtime::channel;
namespace host = omarchy::plugin_runtime::host_session;
namespace permissions = omarchy::plugins::permissions;
namespace definitions = omarchy::plugins::definitions;

namespace {

enum class LookupBehavior { mixed_then_success, interrupt_forever, success,
                            wrong_result, wrong_uid };

LookupBehavior lookup_behavior = LookupBehavior::success;
std::size_t lookup_calls = 0;
uid_t lookup_home_uid = 0;
const char *lookup_home = "/home";
std::filesystem::path provisioning_race_home;

void substitute_first_provisioned_component() {
  const auto local = provisioning_race_home / ".local";
  const auto displaced = provisioning_race_home / "displaced-local";
  std::filesystem::rename(local, displaced);
  std::filesystem::create_directory_symlink(displaced, local);
}

int scripted_lookup(uid_t requested_uid, struct passwd *account, char *,
                    std::size_t, struct passwd **result) {
  ++lookup_calls;
  if (lookup_behavior == LookupBehavior::interrupt_forever)
    return EINTR;
  if (lookup_behavior == LookupBehavior::mixed_then_success &&
      lookup_calls < 16)
    return lookup_calls % 2 == 0 ? EINTR : ERANGE;
  account->pw_uid = lookup_behavior == LookupBehavior::wrong_uid
                        ? static_cast<uid_t>(requested_uid + 1)
                        : lookup_home_uid;
  account->pw_dir = const_cast<char *>(lookup_home);
  static struct passwd unrelated{};
  *result = lookup_behavior == LookupBehavior::wrong_result ? &unrelated
                                                             : account;
  return 0;
}

void require(bool condition, std::string_view message) {
  if (!condition)
    throw std::runtime_error(std::string(message));
}

void write_file(const std::filesystem::path &path, std::string_view bytes,
                mode_t mode = 0644) {
  const int fd = ::open(path.c_str(), O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC,
                        mode);
  require(fd >= 0, "test file creation failed");
  while (!bytes.empty()) {
    const auto count = ::write(fd, bytes.data(), bytes.size());
    if (count < 0 && errno == EINTR)
      continue;
    require(count > 0, "test file write failed");
    bytes.remove_prefix(static_cast<std::size_t>(count));
  }
  require(::close(fd) == 0, "test file close failed");
}

int create_standard_ustar(const std::filesystem::path &home,
                          std::string_view suffix = "base") {
  const auto source = home / ("archive-source-" + std::string(suffix));
  std::filesystem::create_directories(source / "ui");
  constexpr std::string_view manifest = R"({
    "schemaVersion": 2,
    "id": "org.example.ingress",
    "name": "Ingress",
    "version": "1.0.0",
    "runtime": {"apiVersion": 1, "qml": "ui/Main.qml"},
    "surfaces": {"overlay": {"role": "overlay"}},
    "permissions": {"required": [{"capability": "storage.private", "quotaBytes": 1024, "reason": "state"}], "optional": []}
  })";
  write_file(source / "manifest.json", manifest);
  write_file(source / "ui/Main.qml",
             "import QtQuick\nItem { property string revision: \"" +
                 std::string(suffix) + "\" }\n");
  const auto output = home / ("plugin-" + std::string(suffix) + ".tar");
  const pid_t child = ::fork();
  require(child >= 0, "tar fork failed");
  if (child == 0) {
    ::execlp("tar", "tar", "--format=ustar", "-cf", output.c_str(), "-C",
             source.c_str(), "ui", "manifest.json", nullptr);
    ::_exit(127);
  }
  int status = 0;
  require(::waitpid(child, &status, 0) == child && WIFEXITED(status) &&
              WEXITSTATUS(status) == 0,
          "system tar could not create ustar fixture");
  const int archive = ::open(output.c_str(), O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
  require(archive >= 0, "ustar fixture open failed");
  return archive;
}

class Fixture final {
public:
  explicit Fixture(bool with_roots = true) {
    std::string pattern = "/tmp/omarchy-runtime-roots.XXXXXX";
    const auto *created = ::mkdtemp(pattern.data());
    require(created != nullptr, "root fixture creation failed");
    home_ = created;
    if (with_roots) {
      create(".local/share/omarchy-plugin-security/v2/revisions");
      create(".local/state/omarchy/plugin-security/v2/activations");
      create(".local/state/omarchy/plugin-security/v2/authority");
      create(".local/state/omarchy/plugin-security/v2/state");
    }
  }

  ~Fixture() {
    std::error_code error;
    for (std::filesystem::recursive_directory_iterator it(home_, error), end;
         !error && it != end; it.increment(error)) {
      if (it->is_directory(error))
        std::filesystem::permissions(
            it->path(), std::filesystem::perms::owner_write,
            std::filesystem::perm_options::add, error);
    }
    std::filesystem::permissions(home_, std::filesystem::perms::owner_write,
                                 std::filesystem::perm_options::add, error);
    std::filesystem::remove_all(home_, error);
    if (error)
      std::terminate();
  }

  [[nodiscard]] int open_home() const {
    return ::open(home_.c_str(),
                  O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
  }
  [[nodiscard]] const std::filesystem::path &home() const { return home_; }

private:
  void create(const std::filesystem::path &relative) {
    auto current = home_;
    for (const auto &component : relative) {
      current /= component;
      std::filesystem::create_directory(current);
      require(::chmod(current.c_str(), 0700) == 0,
              "root fixture mode setup failed");
    }
  }

  std::filesystem::path home_;
};

class ScopedUmask final {
public:
  explicit ScopedUmask(mode_t value) : previous_(::umask(value)) {}
  ~ScopedUmask() { ::umask(previous_); }

private:
  mode_t previous_;
};

std::unique_ptr<channel::RuntimeRoots>
load(const Fixture &fixture, channel::RuntimeRootsError &error,
     std::uint32_t uid = static_cast<std::uint32_t>(::getuid())) {
  const int home = fixture.open_home();
  require(home >= 0, "fixture home open failed");
  auto result = channel::RuntimeRootsTestAccess::open_from_home_fd(
      home, uid, error);
  ::close(home);
  return result;
}

std::unique_ptr<channel::RuntimeRoots>
provision(const Fixture &fixture, channel::RuntimeRootsError &error,
          std::uint32_t uid = static_cast<std::uint32_t>(::getuid())) {
  const int home = fixture.open_home();
  require(home >= 0, "fixture home open failed");
  auto result = channel::RuntimeRootsTestAccess::provision_from_home_fd(
      home, uid, error);
  ::close(home);
  return result;
}

std::size_t open_descriptor_count() {
  return static_cast<std::size_t>(std::distance(
      std::filesystem::directory_iterator("/proc/self/fd"),
      std::filesystem::directory_iterator{}));
}

void fresh_home_is_provisioned_privately_and_idempotently() {
  Fixture fixture(false);
  channel::RuntimeRootsError error{};
  std::unique_ptr<channel::RuntimeRoots> roots;
  {
    ScopedUmask hostile(0777);
    roots = provision(fixture, error);
  }
  require(roots && error == channel::RuntimeRootsError::none,
          "fresh home was not provisioned");

  const std::array<std::filesystem::path, 12> created{
      ".local",
      ".local/share",
      ".local/share/omarchy-plugin-security",
      ".local/share/omarchy-plugin-security/v2",
      ".local/share/omarchy-plugin-security/v2/revisions",
      ".local/state",
      ".local/state/omarchy",
      ".local/state/omarchy/plugin-security",
      ".local/state/omarchy/plugin-security/v2",
      ".local/state/omarchy/plugin-security/v2/activations",
      ".local/state/omarchy/plugin-security/v2/authority",
      ".local/state/omarchy/plugin-security/v2/state"};
  for (const auto &relative : created) {
    struct stat metadata{};
    const auto path = fixture.home() / relative;
    require(::lstat(path.c_str(), &metadata) == 0 &&
                S_ISDIR(metadata.st_mode) && metadata.st_uid == ::getuid() &&
                (metadata.st_mode & 07777) == 0700,
            "provisioned component is not private and user-owned");
  }
  const std::array leaves{
      fixture.home() /
          ".local/share/omarchy-plugin-security/v2/revisions",
      fixture.home() /
          ".local/state/omarchy/plugin-security/v2/activations",
      fixture.home() /
          ".local/state/omarchy/plugin-security/v2/authority",
      fixture.home() / ".local/state/omarchy/plugin-security/v2/state"};
  std::array<struct stat, leaves.size()> before{};
  for (std::size_t index = 0; index < leaves.size(); ++index) {
    require(std::filesystem::is_empty(leaves[index]) &&
                ::stat(leaves[index].c_str(), &before[index]) == 0,
            "provisioning fabricated plugin authority or activation data");
  }
  roots.reset();
  roots = provision(fixture, error);
  require(roots && error == channel::RuntimeRootsError::none,
          "provisioning was not idempotent");
  for (std::size_t index = 0; index < leaves.size(); ++index) {
    struct stat after{};
    require(::stat(leaves[index].c_str(), &after) == 0 &&
                after.st_dev == before[index].st_dev &&
                after.st_ino == before[index].st_ino &&
                std::filesystem::is_empty(leaves[index]),
            "idempotent provisioning replaced a root or created authority");
  }
}

void provisioning_coexists_with_the_omarchy_compatibility_symlink() {
  Fixture fixture(false);
  const auto local = fixture.home() / ".local";
  const auto share = local / "share";
  const auto compatibility_target = fixture.home() / "system-omarchy";
  std::filesystem::create_directories(share);
  std::filesystem::create_directory(compatibility_target);
  require(::chmod(local.c_str(), 0755) == 0 &&
              ::chmod(share.c_str(), 0755) == 0 &&
              ::chmod(compatibility_target.c_str(), 0755) == 0,
          "compatibility fixture mode setup failed");
  write_file(compatibility_target / "sentinel", "Omarchy data tree\n");
  std::filesystem::create_directory_symlink(
      compatibility_target, share / "omarchy");

  channel::RuntimeRootsError error{};
  auto roots = provision(fixture, error);
  require(roots && error == channel::RuntimeRootsError::none,
          "Omarchy compatibility symlink blocked runtime provisioning");
  require(std::filesystem::is_symlink(share / "omarchy") &&
              std::filesystem::exists(compatibility_target / "sentinel") &&
              !std::filesystem::exists(compatibility_target /
                                       "plugin-security"),
          "runtime provisioning traversed or changed the compatibility symlink");
  require(std::filesystem::is_directory(
              share / "omarchy-plugin-security/v2/revisions") &&
              std::filesystem::is_directory(
                  fixture.home() /
                  ".local/state/omarchy/plugin-security/v2/activations"),
          "real-home-like provisioning omitted a fixed runtime root");
}

void provisioning_rejects_untrusted_existing_components() {
  {
    Fixture fixture(false);
    require(::mkdir((fixture.home() / ".local").c_str(), 0700) == 0 &&
                ::chmod((fixture.home() / ".local").c_str(), 0770) == 0,
            "unsafe provisioning mode setup failed");
    channel::RuntimeRootsError error{};
    require(!provision(fixture, error) &&
                error == channel::RuntimeRootsError::root_untrusted,
            "group-writable existing component was provisioned");
  }
  {
    Fixture fixture(false);
    write_file(fixture.home() / ".local", "not a directory");
    channel::RuntimeRootsError error{};
    require(!provision(fixture, error),
            "non-directory existing component was provisioned");
  }
  {
    Fixture fixture(false);
    const auto target = fixture.home() / "local-target";
    require(::mkdir(target.c_str(), 0700) == 0,
            "symlink target setup failed");
    std::filesystem::create_directory_symlink(target,
                                               fixture.home() / ".local");
    channel::RuntimeRootsError error{};
    require(!provision(fixture, error),
            "symlinked existing component was provisioned");
  }
  {
    Fixture fixture(false);
    channel::RuntimeRootsError error{};
    require(!provision(fixture, error,
                       static_cast<std::uint32_t>(::getuid()) + 1) &&
                error == channel::RuntimeRootsError::home_untrusted,
            "wrong-owner home was provisioned");
  }
}

void provisioning_substitution_is_rejected_at_each_identity_fence() {
  for (const auto point : {channel::ProvisioningRacePoint::after_mkdir,
                           channel::ProvisioningRacePoint::after_pin,
                           channel::ProvisioningRacePoint::after_named_stat}) {
    Fixture fixture(false);
    provisioning_race_home = fixture.home();
    channel::set_provisioning_race_hook_for_testing(
        point, substitute_first_provisioned_component);
    channel::RuntimeRootsError error{};
    auto roots = provision(fixture, error);
    channel::set_provisioning_race_hook_for_testing(
        channel::ProvisioningRacePoint::none, nullptr);
    require(!roots && error != channel::RuntimeRootsError::none,
            "path substitution crossed a provisioning identity fence");
    require(!std::filesystem::exists(
                fixture.home() /
                ".local/state/omarchy/plugin-security/v2/activations") &&
                !std::filesystem::exists(
                    fixture.home() /
                    ".local/state/omarchy/plugin-security/v2/authority"),
            "failed substitution created activation or authority roots");
  }
  provisioning_race_home.clear();
}

void concurrent_provisioning_converges_without_leaks() {
  Fixture fixture(false);
  constexpr std::size_t workers = 8;
  std::barrier start(static_cast<std::ptrdiff_t>(workers + 1));
  std::array<std::thread, workers> threads;
  std::atomic<std::size_t> successes{0};
  for (auto &thread : threads) {
    thread = std::thread([&] {
      start.arrive_and_wait();
      channel::RuntimeRootsError error{};
      auto roots = provision(fixture, error);
      if (roots && error == channel::RuntimeRootsError::none)
        ++successes;
    });
  }
  start.arrive_and_wait();
  for (auto &thread : threads)
    thread.join();
  require(successes == workers,
          "concurrent provisioning did not converge on one root set");

  const auto activations =
      fixture.home() / ".local/state/omarchy/plugin-security/v2/activations";
  const auto authority =
      fixture.home() / ".local/state/omarchy/plugin-security/v2/authority";
  require(std::filesystem::is_empty(activations) &&
              std::filesystem::is_empty(authority),
          "concurrent provisioning fabricated authority or activation data");

  const auto displaced = fixture.home() / "real-local";
  std::filesystem::rename(fixture.home() / ".local", displaced);
  std::filesystem::create_directory_symlink(displaced,
                                             fixture.home() / ".local");
  const auto descriptors_before = open_descriptor_count();
  for (int attempt = 0; attempt < 128; ++attempt) {
    channel::RuntimeRootsError error{};
    require(!provision(fixture, error),
            "symlink race target was provisioned");
  }
  require(open_descriptor_count() == descriptors_before,
          "failed provisioning leaked descriptors");
}

void fixed_roots_are_exact_distinct_and_pinned() {
  Fixture fixture;
  channel::RuntimeRootsError error{};
  auto roots = load(fixture, error);
  require(roots && error == channel::RuntimeRootsError::none &&
              roots->trusted_uid() == static_cast<std::uint32_t>(::getuid()),
          "fixed root set did not load");
  const std::array descriptors{roots->revisions_fd(), roots->activations_fd(),
                               roots->authority_fd(), roots->state_fd()};
  std::array<struct stat, descriptors.size()> metadata{};
  for (std::size_t index = 0; index < descriptors.size(); ++index) {
    require(descriptors[index] >= 0 &&
                (::fcntl(descriptors[index], F_GETFD) & FD_CLOEXEC) != 0 &&
                ::fstat(descriptors[index], &metadata[index]) == 0 &&
                (metadata[index].st_mode & 07777) == 0700,
            "fixed root lost exact descriptor metadata");
    for (std::size_t prior = 0; prior < index; ++prior)
      require(metadata[index].st_dev != metadata[prior].st_dev ||
                  metadata[index].st_ino != metadata[prior].st_ino,
              "fixed roots alias one filesystem object");
  }

  const auto revisions =
      fixture.home() / ".local/share/omarchy-plugin-security/v2/revisions";
  const auto displaced = fixture.home() / "displaced-revisions";
  std::filesystem::rename(revisions, displaced);
  std::filesystem::create_directory(revisions);
  require(::chmod(revisions.c_str(), 0700) == 0,
          "replacement revisions mode failed");
  struct stat pinned{};
  struct stat replacement{};
  require(::fstat(roots->revisions_fd(), &pinned) == 0 &&
              ::stat(revisions.c_str(), &replacement) == 0 &&
              (pinned.st_dev != replacement.st_dev ||
               pinned.st_ino != replacement.st_ino),
          "path replacement retargeted a fixed root descriptor");
}

void unsafe_home_components_and_roots_fail_closed() {
  {
    Fixture fixture;
    require(::chmod(fixture.home().c_str(), 0770) == 0,
            "unsafe home mode setup failed");
    channel::RuntimeRootsError error{};
    require(!load(fixture, error) &&
                error == channel::RuntimeRootsError::home_untrusted,
            "group-writable home was accepted");
  }
  {
    Fixture fixture;
    const auto component =
        fixture.home() / ".local/share/omarchy-plugin-security";
    require(::chmod(component.c_str(), 0770) == 0,
            "unsafe component mode setup failed");
    channel::RuntimeRootsError error{};
    require(!load(fixture, error) &&
                error == channel::RuntimeRootsError::root_untrusted,
            "group-writable fixed-path component was accepted");
  }
  {
    Fixture fixture;
    const auto revisions =
        fixture.home() / ".local/share/omarchy-plugin-security/v2/revisions";
    require(::chmod(revisions.c_str(), 0755) == 0,
            "inexact leaf mode setup failed");
    channel::RuntimeRootsError error{};
    require(!load(fixture, error) &&
                error == channel::RuntimeRootsError::root_untrusted,
            "non-0700 fixed root was accepted");
  }
  {
    Fixture fixture;
    const auto activations =
        fixture.home() / ".local/state/omarchy/plugin-security/v2/activations";
    const auto moved = fixture.home() / "real-activations";
    std::filesystem::rename(activations, moved);
    std::filesystem::create_directory_symlink(moved, activations);
    channel::RuntimeRootsError error{};
    require(!load(fixture, error) &&
                error == channel::RuntimeRootsError::path_unavailable,
            "symlinked fixed root was accepted");
  }
  {
    Fixture fixture;
    channel::RuntimeRootsError error{};
    require(!load(fixture, error, static_cast<std::uint32_t>(::getuid()) + 1) &&
                error == channel::RuntimeRootsError::home_untrusted,
            "wrong trusted UID was accepted");
  }
  {
    channel::RuntimeRootsError error{};
    auto roots = channel::RuntimeRootsTestAccess::open_from_home_fd(
        -1, static_cast<std::uint32_t>(::getuid()), error);
    require(!roots &&
                error == channel::RuntimeRootsError::home_untrusted,
            "invalid borrowed home descriptor was accepted");
  }
}

void absolute_home_walker_rejects_untrusted_paths() {
  struct stat system_home{};
  require(::stat("/home", &system_home) == 0,
          "system home metadata unavailable");
  const auto owner = static_cast<std::uint32_t>(system_home.st_uid);
  channel::RuntimeRootsError error{};
  auto open_home = [&](const char *path, std::uint32_t uid = 0) {
    const int descriptor =
        channel::RuntimeRootsTestAccess::open_absolute_home(
            path, uid == 0 ? owner : uid, error);
    if (descriptor >= 0)
      ::close(descriptor);
    return descriptor;
  };

  require(open_home("/home") >= 0 &&
              error == channel::RuntimeRootsError::none,
          "target-owned absolute home was rejected");
  require(open_home("home") < 0 &&
              error == channel::RuntimeRootsError::home_untrusted,
          "non-absolute home was accepted");
  require(open_home("/home/.") < 0 &&
              error == channel::RuntimeRootsError::home_untrusted,
          "dot home component was accepted");
  require(open_home("/home/../home") < 0 &&
              error == channel::RuntimeRootsError::home_untrusted,
          "dot-dot home component was accepted");
  require(open_home("/bin") < 0 &&
              error == channel::RuntimeRootsError::home_untrusted,
          "symlinked home component was accepted");
  const auto *current_account = ::getpwuid(::getuid());
  require(current_account != nullptr && current_account->pw_dir != nullptr,
          "current account home unavailable");
  require(open_home(current_account->pw_dir) < 0 &&
              error == channel::RuntimeRootsError::home_untrusted,
          "wrong-owned final home was accepted");

  require(channel::RuntimeRootsTestAccess::
              absolute_ancestor_is_secure(0, S_IFDIR | 0755, 1000),
          "root-owned safe system ancestor was rejected");
  require(!channel::RuntimeRootsTestAccess::
               absolute_ancestor_is_secure(0, S_IFDIR | 0775, 1000),
          "root-owned writable system ancestor was accepted");
}

void account_resolution_is_bounded_and_exact() {
  struct stat system_home{};
  require(::stat("/home", &system_home) == 0,
          "system home metadata unavailable");
  lookup_home_uid = system_home.st_uid;
  channel::RuntimeRootsError error{};
  auto resolve = [&](LookupBehavior behavior) {
    lookup_behavior = behavior;
    lookup_calls = 0;
    const int descriptor =
        channel::RuntimeRootsTestAccess::resolve_account_home(
            static_cast<std::uint32_t>(lookup_home_uid), 128,
            scripted_lookup, error);
    if (descriptor >= 0)
      ::close(descriptor);
    return descriptor;
  };

  require(resolve(LookupBehavior::mixed_then_success) >= 0 &&
              lookup_calls == 16 &&
              error == channel::RuntimeRootsError::none,
          "bounded mixed EINTR/ERANGE lookup did not complete");
  require(resolve(LookupBehavior::interrupt_forever) < 0 &&
              lookup_calls == 16 &&
              error == channel::RuntimeRootsError::account_unavailable,
          "account lookup exceeded its total attempt budget");
  require(resolve(LookupBehavior::wrong_result) < 0 &&
              error == channel::RuntimeRootsError::account_unavailable,
          "non-account result pointer was accepted");
  require(resolve(LookupBehavior::wrong_uid) < 0 &&
              error == channel::RuntimeRootsError::account_unavailable,
          "mismatched account UID was accepted");
}

void archive_reaches_exact_review_without_fabricating_authority() {
  Fixture fixture;
  channel::RuntimeRootsError error{};
  auto roots = load(fixture, error);
  require(roots && error == channel::RuntimeRootsError::none,
          "review fixture roots did not load");
  const int archive = create_standard_ustar(fixture.home());
  auto published = roots->stage_revision_for_review(archive);
  ::close(archive);
  const auto &plugin = published.verified().manifest.id;
  const auto &digest = published.verified().identity.tree_sha256;

  auto record = host::inspect_activation_record(
      roots->activations_fd(), plugin, roots->trusted_uid());
  require(record && record->record().plugin_id == plugin &&
              record->record().revision_directory == digest &&
              record->record().revision_sha256 == digest &&
              record->record().state_directory == plugin,
          "candidate record was not derived from the published revision");
  channel::ActivationCatalogError catalog_error{};
  auto catalog = channel::ActivationCatalog::load(
      roots->activations_fd(), roots->trusted_uid(), catalog_error);
  require(catalog && catalog_error == channel::ActivationCatalogError::none &&
              catalog->entries().size() == 1 &&
              catalog->entries().front().plugin_id() == plugin,
          "published candidate is not catalog-visible");

  const int authority_fd = ::openat(roots->authority_fd(), plugin.c_str(),
                                    O_RDONLY | O_DIRECTORY | O_CLOEXEC |
                                        O_NOFOLLOW);
  require(authority_fd >= 0, "plugin authority root was not provisioned");
  auto definitions_registry =
      std::make_shared<const definitions::TrustedDefinitionRegistry>();
  auto services = std::make_shared<const channel::RuntimeServices>();
  auto authority = channel::PluginPermissionAuthorityTestAccess::open(
      roots->activations_fd(), roots->revisions_fd(), roots->state_fd(),
      host::OwnedDescriptor(authority_fd), permissions::PluginId(plugin),
      roots->trusted_uid(), definitions_registry, services, plugin);
  require(authority != nullptr, "product plugin authority did not open");
  host::DescriptorRevisionVerifier verifier(roots->trusted_uid());
  const auto verified = verifier.verify_open_revision(published.descriptor());
  require(verified && verified->tree_sha256 == digest &&
              verified->request_sha256 ==
                  published.verified().identity.request_sha256,
          "runtime verifier lost the exact published identity");
  const auto review =
      channel::PluginPermissionAuthorityTestAccess::prepare_review(*authority);
  require(review && review->verified.tree_sha256 == digest &&
              review->candidate_binding.revision.view() == digest &&
              review->builtin_rows.size() == 1,
          "consent review did not bind the exact candidate digest");
  const std::array decisions{host::BuiltinConsentDecision{
      .capability = review->builtin_rows.front().requested->capability,
      .decided_scope = review->builtin_rows.front().requested->scope,
      .decision = permissions::UserDecision::deny}};
  const std::array<host::DynamicConsentDecision, 0> dynamic{};
  host::ConsentConfirmation confirmation{
      .review_fingerprint = review->fingerprint,
      .decision_fingerprint = host::consent_decision_fingerprint(
          *review, decisions, dynamic),
      .actor = permissions::DecisionActor::trusted_ui,
      .confirmed_wall_seconds = 1};
  const auto applied = channel::PluginPermissionAuthorityTestAccess::apply_review(
      *authority, *review, confirmation, decisions, dynamic);
  require(applied.publication == host::ConsentResult::required_denied,
          "required denial was not rejected");
  const auto view = channel::PluginPermissionAuthorityTestAccess::list(*authority);
  require(view && !view->authority_slots.active &&
              !view->authority_slots.candidate &&
              view->authority_slots.sequence == 0,
          "candidate staging or denial fabricated authority");
}

void candidate_record_crashes_recover_to_complete_state() {
  for (const auto point : {channel::CandidateRecordCrashPoint::write,
                           channel::CandidateRecordCrashPoint::file_sync,
                           channel::CandidateRecordCrashPoint::rename,
                           channel::CandidateRecordCrashPoint::directory_sync}) {
    Fixture fixture;
    channel::RuntimeRootsError error{};
    auto roots = load(fixture, error);
    require(roots != nullptr, "crash fixture roots did not load");
    const int input = create_standard_ustar(fixture.home(), "crash");
    const pid_t child = ::fork();
    require(child >= 0, "candidate crash fork failed");
    if (child == 0) {
      channel::set_candidate_record_crash_point_for_testing(point);
      try {
        auto ignored = roots->stage_revision_for_review(input);
      } catch (...) {
        ::_exit(125);
      }
      ::_exit(126);
    }
    int status = 0;
    require(::waitpid(child, &status, 0) == child && WIFEXITED(status) &&
                WEXITSTATUS(status) == 90 + static_cast<int>(point),
            "candidate crash point was not reached");
    ::close(input);
    roots.reset();
    roots = load(fixture, error);
    require(roots != nullptr, "candidate crash recovery rejected roots");
    auto record = host::inspect_activation_record(
        roots->activations_fd(), "org.example.ingress", roots->trusted_uid());
    const bool renamed = point == channel::CandidateRecordCrashPoint::rename ||
                         point == channel::CandidateRecordCrashPoint::directory_sync;
    require(record.has_value() == renamed,
            "candidate crash exposed neither absent nor complete record");
    channel::ActivationCatalogError catalog_error{};
    auto catalog = channel::ActivationCatalog::load(
        roots->activations_fd(), roots->trusted_uid(), catalog_error);
    require(catalog && catalog_error == channel::ActivationCatalogError::none &&
                catalog->entries().size() == (renamed ? 1U : 0U),
            "catalog observed candidate staging or a torn record");
    catalog.reset();
    const int retry = create_standard_ustar(fixture.home(), "retry");
    auto recovered = roots->stage_revision_for_review(retry);
    ::close(retry);
    const auto retry_record = host::inspect_activation_record(
        roots->activations_fd(), "org.example.ingress", roots->trusted_uid());
    require(retry_record && retry_record->record().revision_sha256 ==
                                recovered.verified().identity.tree_sha256,
            "candidate retry did not publish its exact revision");
  }
}

void candidate_update_crashes_leave_exact_old_or_new_record() {
  for (const auto point : {channel::CandidateRecordCrashPoint::write,
                           channel::CandidateRecordCrashPoint::file_sync,
                           channel::CandidateRecordCrashPoint::rename,
                           channel::CandidateRecordCrashPoint::directory_sync}) {
    Fixture fixture;
    channel::RuntimeRootsError error{};
    auto roots = load(fixture, error);
    const int old_archive = create_standard_ustar(fixture.home(), "old");
    auto old_revision = roots->stage_revision_for_review(old_archive);
    const auto old_digest = old_revision.verified().identity.tree_sha256;
    const int next_archive = create_standard_ustar(fixture.home(), "new");
    auto expected_new = roots->stage_revision_for_review(next_archive);
    const auto new_digest = expected_new.verified().identity.tree_sha256;
    require(::lseek(old_archive, 0, SEEK_SET) == 0,
            "old archive rewind failed");
    auto restored_old = roots->stage_revision_for_review(old_archive);
    require(restored_old.verified().identity.tree_sha256 == old_digest,
            "old candidate restore changed identity");
    ::close(old_archive);
    channel::ActivationCatalogError before_error{};
    auto before_catalog = channel::ActivationCatalog::load(
        roots->activations_fd(), roots->trusted_uid(), before_error);
    require(before_catalog && before_catalog->unchanged(),
            "pre-crash candidate catalog is unstable");
    require(::lseek(next_archive, 0, SEEK_SET) == 0,
            "new archive rewind failed");
    const pid_t child = ::fork();
    require(child >= 0, "candidate update crash fork failed");
    if (child == 0) {
      channel::set_candidate_record_crash_point_for_testing(point);
      try {
        auto ignored = roots->stage_revision_for_review(next_archive);
      } catch (...) {
        ::_exit(125);
      }
      ::_exit(126);
    }
    int status = 0;
    require(::waitpid(child, &status, 0) == child && WIFEXITED(status) &&
                WEXITSTATUS(status) == 90 + static_cast<int>(point),
            "candidate update crash point was not reached");
    roots.reset();
    roots = load(fixture, error);
    require(roots != nullptr, "candidate update recovery rejected roots");
    auto record = host::inspect_activation_record(
        roots->activations_fd(), "org.example.ingress", roots->trusted_uid());
    require(record != std::nullopt, "candidate update lost the old record");
    const bool after_rename =
        point == channel::CandidateRecordCrashPoint::rename ||
        point == channel::CandidateRecordCrashPoint::directory_sync;
    require((after_rename && record->record().revision_sha256 == new_digest) ||
                (!after_rename && record->record().revision_sha256 == old_digest),
            "candidate update exposed a record outside the old/new states");
    for (const auto &entry : std::filesystem::directory_iterator(
             fixture.home() /
             ".local/share/omarchy-plugin-security/v2/revisions")) {
      const auto name = entry.path().filename().string();
      if (name.starts_with(".incoming-"))
        continue;
      const int revision = ::open(entry.path().c_str(),
                                  O_RDONLY | O_DIRECTORY | O_CLOEXEC |
                                      O_NOFOLLOW);
      require(revision >= 0, "update revision cannot be reopened");
      const auto verified = omarchy::plugins::discovery::
          discover_open_published_revision(revision, roots->trusted_uid());
      ::close(revision);
      require(verified.identity.tree_sha256 == name,
              "candidate update left a torn published revision");
    }
    require(::lseek(next_archive, 0, SEEK_SET) == 0,
            "candidate update retry rewind failed");
    auto retried = roots->stage_revision_for_review(next_archive);
    ::close(next_archive);
    require(retried.verified().identity.tree_sha256 == new_digest,
            "candidate update retry changed revision identity");
    auto retried_record = host::inspect_activation_record(
        roots->activations_fd(), "org.example.ingress", roots->trusted_uid());
    require(retried_record &&
                retried_record->record().revision_sha256 == new_digest,
            "candidate update retry did not publish exact new record");
    require(!before_catalog->unchanged(),
            "candidate crash retry did not invalidate the prior catalog epoch");
  }
}

void superseded_product_review_is_stale_without_authority_change() {
  Fixture fixture;
  channel::RuntimeRootsError error{};
  auto roots = load(fixture, error);
  const int old_archive = create_standard_ustar(fixture.home(), "review-old");
  auto old_revision = roots->stage_revision_for_review(old_archive);
  ::close(old_archive);
  const auto plugin = old_revision.verified().manifest.id;
  const int authority_fd = ::openat(roots->authority_fd(), plugin.c_str(),
                                    O_RDONLY | O_DIRECTORY | O_CLOEXEC |
                                        O_NOFOLLOW);
  require(authority_fd >= 0, "stale review authority root unavailable");
  auto definitions_registry =
      std::make_shared<const definitions::TrustedDefinitionRegistry>();
  auto services = std::make_shared<const channel::RuntimeServices>();
  auto authority = channel::PluginPermissionAuthorityTestAccess::open(
      roots->activations_fd(), roots->revisions_fd(), roots->state_fd(),
      host::OwnedDescriptor(authority_fd), permissions::PluginId(plugin),
      roots->trusted_uid(), definitions_registry, services, plugin);
  require(authority != nullptr, "stale review product authority did not open");
  const auto old_review =
      channel::PluginPermissionAuthorityTestAccess::prepare_review(*authority);
  require(old_review && old_review->verified.tree_sha256 ==
                            old_revision.verified().identity.tree_sha256,
          "old product review did not bind old revision");

  const int new_archive = create_standard_ustar(fixture.home(), "review-new");
  auto new_revision = roots->stage_revision_for_review(new_archive);
  ::close(new_archive);
  const std::array decisions{host::BuiltinConsentDecision{
      .capability = old_review->builtin_rows.front().requested->capability,
      .decided_scope = old_review->builtin_rows.front().requested->scope,
      .decision = permissions::UserDecision::deny}};
  const std::array<host::DynamicConsentDecision, 0> dynamic{};
  const host::ConsentConfirmation confirmation{
      .review_fingerprint = old_review->fingerprint,
      .decision_fingerprint = host::consent_decision_fingerprint(
          *old_review, decisions, dynamic),
      .actor = permissions::DecisionActor::trusted_ui,
      .confirmed_wall_seconds = 1};
  const auto rejected = channel::PluginPermissionAuthorityTestAccess::apply_review(
      *authority, *old_review, confirmation, decisions, dynamic);
  require(rejected.publication == host::ConsentResult::invalid_review &&
              !rejected.binding,
          "superseded product review was not rejected as stale");
  const auto view = channel::PluginPermissionAuthorityTestAccess::list(*authority);
  require(view && view->authority_slots.sequence == 0 &&
              !view->authority_slots.active && !view->authority_slots.candidate,
          "superseded review changed authority");
  const auto current =
      channel::PluginPermissionAuthorityTestAccess::prepare_review(*authority);
  require(current && current->verified.tree_sha256 ==
                         new_revision.verified().identity.tree_sha256,
          "product review did not re-read the winning candidate record");
}

void concurrent_candidates_publish_one_exact_record_and_two_revisions() {
  Fixture fixture;
  channel::RuntimeRootsError error{};
  auto roots = load(fixture, error);
  const int left_archive = create_standard_ustar(fixture.home(), "parallel-a");
  const int right_archive = create_standard_ustar(fixture.home(), "parallel-b");
  std::barrier start(3);
  std::atomic<int> failures{0};
  std::string left_digest;
  std::string right_digest;
  auto stage = [&](int archive, std::string &digest) {
    start.arrive_and_wait();
    try {
      auto revision = roots->stage_revision_for_review(archive);
      digest = revision.verified().identity.tree_sha256;
    } catch (...) {
      ++failures;
    }
  };
  std::thread left(stage, left_archive, std::ref(left_digest));
  std::thread right(stage, right_archive, std::ref(right_digest));
  start.arrive_and_wait();
  left.join();
  right.join();
  ::close(left_archive);
  ::close(right_archive);
  require(failures == 0 && left_digest.size() == 64 &&
              right_digest.size() == 64 && left_digest != right_digest,
          "concurrent candidate staging did not complete exact revisions");
  auto record = host::inspect_activation_record(
      roots->activations_fd(), "org.example.ingress", roots->trusted_uid());
  require(record && (record->record().revision_sha256 == left_digest ||
                     record->record().revision_sha256 == right_digest),
          "concurrent candidates published a hybrid record");
  for (const auto &digest : {left_digest, right_digest}) {
    const int revision = ::openat(roots->revisions_fd(), digest.c_str(),
                                  O_RDONLY | O_DIRECTORY | O_CLOEXEC |
                                      O_NOFOLLOW);
    require(revision >= 0, "concurrent candidate revision is absent");
    const auto verified = omarchy::plugins::discovery::
        discover_open_published_revision(revision, roots->trusted_uid());
    ::close(revision);
    require(verified.identity.tree_sha256 == digest,
            "concurrent candidate revision is torn");
  }
}

void hostile_umask_is_normalized_at_every_published_leaf() {
  Fixture fixture;
  channel::RuntimeRootsError error{};
  auto roots = load(fixture, error);
  const int input = create_standard_ustar(fixture.home(), "umask");
  std::optional<omarchy::plugins::discovery::PublishedRevision> published;
  {
    ScopedUmask hostile(0777);
    published.emplace(roots->stage_revision_for_review(input));
  }
  ::close(input);
  const auto &plugin = published->verified().manifest.id;
  const auto &digest = published->verified().identity.tree_sha256;
  struct stat metadata{};
  require(::fstat(published->descriptor(), &metadata) == 0 &&
              (metadata.st_mode & 07777) == 0555,
          "hostile umask changed revision mode");
  for (const auto &pair : {std::pair{roots->state_fd(), plugin},
                           std::pair{roots->authority_fd(), plugin}}) {
    const int directory = ::openat(pair.first, pair.second.c_str(),
                                   O_RDONLY | O_DIRECTORY | O_CLOEXEC |
                                       O_NOFOLLOW);
    require(directory >= 0 && ::fstat(directory, &metadata) == 0 &&
                (metadata.st_mode & 07777) == 0700,
            "hostile umask changed private plugin directory mode");
    ::close(directory);
  }
  const int record = ::openat(roots->activations_fd(), plugin.c_str(),
                              O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
  require(record >= 0 && ::fstat(record, &metadata) == 0 &&
              (metadata.st_mode & 07777) == 0600,
          "hostile umask changed activation record mode");
  ::close(record);
  require(host::inspect_activation_record(roots->activations_fd(), plugin,
                                          roots->trusted_uid())
                  ->record()
                  .revision_sha256 == digest,
          "hostile umask publication changed record identity");
}

void live_catalog_does_not_hold_the_transaction_lock() {
  Fixture fixture;
  channel::RuntimeRootsError error{};
  auto roots = load(fixture, error);
  const int first_archive = create_standard_ustar(fixture.home(), "catalog-a");
  auto first = roots->stage_revision_for_review(first_archive);
  (void)first;
  ::close(first_archive);
  channel::ActivationCatalogError catalog_error{};
  auto catalog = channel::ActivationCatalog::load(
      roots->activations_fd(), roots->trusted_uid(), catalog_error);
  require(catalog && catalog->unchanged(), "initial catalog is not stable");
  const int second_archive = create_standard_ustar(fixture.home(), "catalog-b");
  auto second = roots->stage_revision_for_review(second_archive);
  (void)second;
  ::close(second_archive);
  require(!catalog->unchanged(),
          "live catalog retained a transaction lock or missed the update");
}

void concurrent_catalog_scan_waits_for_an_exact_transaction_epoch() {
  Fixture fixture;
  channel::RuntimeRootsError error{};
  auto roots = load(fixture, error);
  const int initial_archive = create_standard_ustar(fixture.home(), "scan-base");
  auto initial = roots->stage_revision_for_review(initial_archive);
  (void)initial;
  ::close(initial_archive);
  for (int iteration = 0; iteration < 10; ++iteration) {
    const auto suffix = "scan-" + std::to_string(iteration);
    const int update_archive = create_standard_ustar(fixture.home(), suffix);
    std::barrier start(3);
    std::atomic<bool> writer_ok{false};
    std::atomic<bool> reader_ok{false};
    std::thread writer([&] {
      start.arrive_and_wait();
      try {
        auto update = roots->stage_revision_for_review(update_archive);
        (void)update;
        writer_ok = true;
      } catch (...) {
      }
    });
    std::thread reader([&] {
      start.arrive_and_wait();
      channel::ActivationCatalogError catalog_error{};
      auto catalog = channel::ActivationCatalog::load(
          roots->activations_fd(), roots->trusted_uid(), catalog_error);
      reader_ok = catalog &&
                  catalog_error == channel::ActivationCatalogError::none &&
                  catalog->entries().size() == 1;
    });
    start.arrive_and_wait();
    writer.join();
    reader.join();
    ::close(update_archive);
    require(writer_ok && reader_ok,
            "concurrent catalog scan observed a transaction temp or failed epoch");
  }
}

void product_review_rejects_mutated_published_metadata() {
  Fixture fixture;
  channel::RuntimeRootsError error{};
  auto roots = load(fixture, error);
  const int input = create_standard_ustar(fixture.home(), "metadata");
  auto published = roots->stage_revision_for_review(input);
  ::close(input);
  const auto plugin = published.verified().manifest.id;
  const int authority_fd = ::openat(roots->authority_fd(), plugin.c_str(),
                                    O_RDONLY | O_DIRECTORY | O_CLOEXEC |
                                        O_NOFOLLOW);
  require(authority_fd >= 0, "metadata authority root unavailable");
  auto registry =
      std::make_shared<const definitions::TrustedDefinitionRegistry>();
  auto services = std::make_shared<const channel::RuntimeServices>();
  auto authority = channel::PluginPermissionAuthorityTestAccess::open(
      roots->activations_fd(), roots->revisions_fd(), roots->state_fd(),
      host::OwnedDescriptor(authority_fd), permissions::PluginId(plugin),
      roots->trusted_uid(), registry, services, plugin);
  require(authority && channel::PluginPermissionAuthorityTestAccess::
                           prepare_review(*authority),
          "canonical published metadata did not reach product review");
  require(::fchmodat(published.descriptor(), "manifest.json", 0644, 0) == 0,
          "test could not make published file writable");
  require(!channel::PluginPermissionAuthorityTestAccess::prepare_review(
              *authority),
          "product review accepted writable published metadata");
  const auto view = channel::PluginPermissionAuthorityTestAccess::list(*authority);
  require(view && view->authority_slots.sequence == 0 &&
              !view->authority_slots.active && !view->authority_slots.candidate,
          "metadata rejection changed authority");
}

} // namespace

int main() {
  try {
    fresh_home_is_provisioned_privately_and_idempotently();
    provisioning_coexists_with_the_omarchy_compatibility_symlink();
    provisioning_rejects_untrusted_existing_components();
    provisioning_substitution_is_rejected_at_each_identity_fence();
    concurrent_provisioning_converges_without_leaks();
    fixed_roots_are_exact_distinct_and_pinned();
    unsafe_home_components_and_roots_fail_closed();
    absolute_home_walker_rejects_untrusted_paths();
    account_resolution_is_bounded_and_exact();
    archive_reaches_exact_review_without_fabricating_authority();
    candidate_record_crashes_recover_to_complete_state();
    candidate_update_crashes_leave_exact_old_or_new_record();
    superseded_product_review_is_stale_without_authority_change();
    concurrent_candidates_publish_one_exact_record_and_two_revisions();
    hostile_umask_is_normalized_at_every_published_leaf();
    live_catalog_does_not_hold_the_transaction_lock();
    concurrent_catalog_scan_waits_for_an_exact_transaction_epoch();
    product_review_rejects_mutated_published_metadata();
    return 0;
  } catch (const std::exception &error) {
    std::cerr << "runtime roots test failed: " << error.what()
              << '\n';
    return 1;
  }
}
