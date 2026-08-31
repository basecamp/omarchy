#include "omarchy/plugin_runtime/provider_host/provider_host.hpp"

#include "manifest_contract.hpp"

#include <fcntl.h>
#include <signal.h>
#include <sys/stat.h>
#include <unistd.h>

#include <array>
#include <cerrno>
#include <chrono>
#include <cstddef>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <span>
#include <string>
#include <string_view>
#include <vector>

namespace host = omarchy::plugin_runtime::provider_host;
namespace definitions = omarchy::plugins::definitions;
namespace permissions = omarchy::plugins::permissions;

namespace {

[[noreturn]] void fail(std::string_view message) {
  std::cerr << "FAIL: " << message << '\n';
  std::exit(1);
}
void require(bool condition, std::string_view message) {
  if (!condition)
    fail(message);
}

std::string read_file(const std::filesystem::path &path) {
  std::ifstream input(path, std::ios::binary);
  return {std::istreambuf_iterator<char>(input),
          std::istreambuf_iterator<char>()};
}

struct Fixture final {
  std::filesystem::path root;
  std::string executable_digest;

  Fixture() {
    std::array<char, 4096> pattern{};
    const std::string prefix =
        std::string(::getenv("TMPDIR") ? ::getenv("TMPDIR") : "/tmp") +
        "/omarchy-provider-host-XXXXXX";
    require(prefix.size() + 1 < pattern.size(), "temporary path too long");
    std::copy(prefix.begin(), prefix.end(), pattern.begin());
    const auto *created = ::mkdtemp(pattern.data());
    require(created != nullptr, "mkdtemp failed");
    root = created;
    std::filesystem::create_directories(root / "pkg");
    std::filesystem::create_directories(root / "admin");
    std::filesystem::create_directories(root / "bin");
    std::filesystem::copy_file(PROVIDER_PEER_PATH, root / "bin/provider-peer");
    std::filesystem::permissions(root / "bin/provider-peer",
                                 std::filesystem::perms::owner_read |
                                     std::filesystem::perms::owner_exec);
    executable_digest = omarchy::plugins::manifest::sha256_hex(
        read_file(root / "bin/provider-peer"));
  }
  ~Fixture() { std::filesystem::remove_all(root); }

  std::filesystem::path profile_path(std::string_view name,
                                     bool admin = false) const {
    return root / (admin ? "admin" : "pkg") /
           (std::string(name) + ".profile");
  }
  void profile(std::string_view name, std::string_view adapter,
               std::string_view contract, std::string_view group,
               std::string_view mode = "pid", bool admin = false,
               std::string_view executable = "/bin/provider-peer",
               std::string_view digest = {}) const {
    std::ofstream output(profile_path(name, admin));
    output << "schema=1\n"
           << "adapter-class=" << adapter << "\n"
           << "contract-digest=" << contract << "\n"
           << "abi-version=1\n"
           << "group=" << group << "\n"
           << "executable=" << executable << "\n"
           << "executable-sha256="
           << (digest.empty() ? executable_digest : digest) << "\n"
           << "arg=" << mode << "\n";
    output.close();
    std::filesystem::permissions(profile_path(name, admin),
                                 std::filesystem::perms::owner_read |
                                     std::filesystem::perms::owner_write);
  }
  int open_root() const {
    return ::open(root.c_str(), O_RDONLY | O_DIRECTORY | O_CLOEXEC);
  }
};

std::string digest(char value) { return std::string(64, value); }

definitions::AdapterBinding binding(std::string_view adapter, char value = 'a') {
  return {.adapter_class = definitions::Name(adapter),
          .contract_digest = definitions::Digest(digest(value)),
          .abi_version = 1};
}

permissions::ActivationBinding activation(std::uint64_t generation) {
  return {.plugin = permissions::PluginId("test.provider"),
          .revision = permissions::Digest(digest('b')),
          .policy_fingerprint = permissions::Digest(digest('c')),
          .generation = generation};
}

std::shared_ptr<const host::ProviderCatalog> load(
    const Fixture &fixture, host::CatalogError &error) {
  const int root = fixture.open_root();
  require(root >= 0, "open fixture root failed");
  const std::array<std::string_view, 1> package{"pkg"};
  const std::array<std::string_view, 1> admin{"admin"};
  auto result = host::ProviderCatalog::load(
      root, package, admin, static_cast<std::uint32_t>(::getuid()), error);
  ::close(root);
  return result;
}

bool invoke(const std::shared_ptr<host::ProviderRoute> &route,
            const permissions::ActivationBinding &active, std::string &result) {
  std::array<std::byte, 256> response{};
  std::size_t written = 0;
  const std::array<std::byte, 1> payload{std::byte{7}};
  const definitions::AuthorizedDynamicRequest request{
      .authorization = {.binding = active,
                        .definition = {.canonical_name =
                                           definitions::Name("test.capability"),
                                       .definition_generation = 1,
                                       .definition_digest =
                                           definitions::Digest(digest('d'))},
                        .grant_epoch = 1},
      .operation = "observe",
      .demand_scope = "{}",
      .payload = payload};
  const bool ok = host::ProviderRoute::dispatch(request, response, written,
                                                route.get());
  result.assign(reinterpret_cast<const char *>(response.data()), written);
  return ok;
}

void catalog_security() {
  Fixture fixture;
  fixture.profile("good", "test.adapter", digest('a'), "test.group");
  host::CatalogError error{};
  const auto catalog = load(fixture, error);
  require(catalog && error == host::CatalogError::none && catalog->size() == 1,
          "valid trusted catalog rejected");
  require(catalog->available(binding("test.adapter")),
          "exact adapter unavailable");
  require(!catalog->available(binding("test.adapter", 'e')),
          "wrong contract digest available");

  Fixture bad_hash;
  bad_hash.profile("bad", "test.adapter", digest('a'), "test.group", "pid",
                   false, "/bin/provider-peer", digest('f'));
  require(!load(bad_hash, error) && error == host::CatalogError::executable_rejected,
          "wrong executable digest accepted");

  Fixture writable;
  writable.profile("bad", "test.adapter", digest('a'), "test.group");
  std::filesystem::permissions(
      writable.profile_path("bad"), std::filesystem::perms::group_write,
      std::filesystem::perm_options::add);
  require(!load(writable, error) && error == host::CatalogError::profile_rejected,
          "group-writable profile accepted");

  Fixture profile_link;
  profile_link.profile("real", "test.adapter", digest('a'), "test.group");
  std::filesystem::rename(profile_link.profile_path("real"),
                          profile_link.root / "pkg/real.data");
  std::filesystem::create_symlink("real.data",
                                  profile_link.profile_path("linked"));
  require(!load(profile_link, error) &&
              error == host::CatalogError::profile_rejected,
          "symlink profile accepted");

  Fixture symlink;
  std::filesystem::create_symlink("/bin/provider-peer",
                                  symlink.root / "bin/provider-link");
  symlink.profile("bad", "test.adapter", digest('a'), "test.group", "pid",
                  false, "/bin/provider-link");
  require(!load(symlink, error) && error == host::CatalogError::executable_rejected,
          "symlink executable accepted");

  Fixture traversal;
  traversal.profile("bad", "test.adapter", digest('a'), "test.group", "pid",
                    false, "/bin/../bin/provider-peer");
  require(!load(traversal, error) &&
              error == host::CatalogError::executable_rejected,
          "noncanonical executable path accepted");

  Fixture duplicate;
  duplicate.profile("one", "test.adapter", digest('a'), "test.group");
  duplicate.profile("two", "test.adapter", digest('a'), "test.group", "pid",
                    true);
  require(!load(duplicate, error) && error == host::CatalogError::duplicate_binding,
          "duplicate exact adapter accepted");
}

void protocol_and_lifecycle() {
  Fixture fixture;
  fixture.profile("one", "test.adapter", digest('a'), "shared.group");
  fixture.profile("two", "test.second", digest('e'), "shared.group");
  host::CatalogError error{};
  auto catalog = load(fixture, error);
  require(catalog && catalog->size() == 2, "shared process catalog rejected");
  std::filesystem::rename(fixture.root / "bin/provider-peer",
                          fixture.root / "bin/provider-peer-pinned");
  {
    std::ofstream replacement(fixture.root / "bin/provider-peer");
    replacement << "not the reviewed executable\n";
  }
  std::filesystem::permissions(fixture.root / "bin/provider-peer",
                               std::filesystem::perms::owner_read |
                                   std::filesystem::perms::owner_exec);
  const auto active = activation(4);
  auto runtime = host::ProviderActivation::create(catalog, active);
  auto first = runtime->route(binding("test.adapter"));
  auto second = runtime->route(binding("test.second", 'e'));
  require(first && second && !runtime->route(binding("test.missing")),
          "route did not require exact pinned profile");
  std::string first_pid, second_pid;
  require(invoke(first, active, first_pid), "first provider invocation failed");
  require(invoke(second, active, second_pid), "second provider invocation failed");
  require(first_pid == second_pid,
          "same activation/group did not retain one process");
  std::string rejected;
  require(!invoke(first, activation(5), rejected),
          "cross-activation request reached provider");

  auto other = host::ProviderActivation::create(catalog, activation(5));
  auto other_route = other->route(binding("test.adapter"));
  std::string other_pid;
  require(invoke(other_route, activation(5), other_pid) && other_pid != first_pid,
          "provider process crossed activation boundary");
  const auto pid = static_cast<pid_t>(std::stoi(other_pid));
  other->cancel();
  require(::kill(pid, 0) < 0 && errno == ESRCH,
          "cancel did not reap provider process");
  std::string cancelled;
  require(!invoke(other_route, activation(5), cancelled),
          "cancelled activation restarted provider");
}

void failure_modes() {
  for (const auto mode : {"crash", "malformed", "wrong-correlation", "late"}) {
    Fixture fixture;
    fixture.profile("bad", "test.adapter", digest('a'), "bad.group", mode);
    host::CatalogError error{};
    auto catalog = load(fixture, error);
    require(catalog != nullptr, "failure-mode catalog rejected");
    auto runtime = host::ProviderActivation::create(
        catalog, activation(8), std::chrono::milliseconds(50));
    auto route = runtime->route(binding("test.adapter"));
    std::string output;
    require(!invoke(route, activation(8), output),
            "bad provider response succeeded");
    require(!invoke(route, activation(8), output),
            "failed provider restarted within activation");
  }

  Fixture environment;
  environment.profile("env", "test.adapter", digest('a'), "env.group",
                      "environment");
  host::CatalogError error{};
  auto catalog = load(environment, error);
  auto runtime = host::ProviderActivation::create(catalog, activation(9));
  auto route = runtime->route(binding("test.adapter"));
  std::string output;
  require(invoke(route, activation(9), output) &&
              output == "/usr/bin|/nonexistent",
          "provider did not receive fixed sanitized environment");
}

} // namespace

int main() {
  catalog_security();
  protocol_and_lifecycle();
  failure_modes();
  std::cout << "provider host tests passed\n";
}
