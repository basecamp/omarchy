#include "runtime_roots.hpp"
#include "runtime_roots_test_access.hpp"

#include <fcntl.h>
#include <pwd.h>
#include <sys/stat.h>
#include <unistd.h>

#include <array>
#include <cerrno>
#include <filesystem>
#include <iostream>
#include <stdexcept>
#include <string>
#include <string_view>

namespace channel = omarchy::plugin_runtime::channel;

namespace {

enum class LookupBehavior { mixed_then_success, interrupt_forever, success,
                            wrong_result, wrong_uid };

LookupBehavior lookup_behavior = LookupBehavior::success;
std::size_t lookup_calls = 0;
uid_t lookup_home_uid = 0;
const char *lookup_home = "/home";

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

class Fixture final {
public:
  Fixture() {
    std::string pattern = "/tmp/omarchy-runtime-roots.XXXXXX";
    const auto *created = ::mkdtemp(pattern.data());
    require(created != nullptr, "root fixture creation failed");
    home_ = created;
    create(".local/share/omarchy/plugin-security/v2/revisions");
    create(".local/state/omarchy/plugin-security/v2/activations");
    create(".local/state/omarchy/plugin-security/v2/authority");
    create(".local/state/omarchy/plugin-security/v2/state");
  }

  ~Fixture() {
    std::error_code ignored;
    std::filesystem::remove_all(home_, ignored);
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
      fixture.home() / ".local/share/omarchy/plugin-security/v2/revisions";
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
    const auto component = fixture.home() / ".local/share/omarchy";
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
        fixture.home() / ".local/share/omarchy/plugin-security/v2/revisions";
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

} // namespace

int main() {
  try {
    fixed_roots_are_exact_distinct_and_pinned();
    unsafe_home_components_and_roots_fail_closed();
    absolute_home_walker_rejects_untrusted_paths();
    account_resolution_is_bounded_and_exact();
    return 0;
  } catch (const std::exception &error) {
    std::cerr << "runtime roots test failed: " << error.what()
              << '\n';
    return 1;
  }
}
