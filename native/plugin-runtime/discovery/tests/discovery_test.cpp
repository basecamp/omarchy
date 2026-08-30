#include "discovery.hpp"

#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

#include <algorithm>
#include <atomic>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>
#include <string_view>
#include <thread>
#include <vector>

namespace discovery = omarchy::plugins::discovery;
namespace manifest = omarchy::plugins::manifest;

namespace {

void require(bool condition, std::string_view message) {
  if (!condition) {
    throw std::runtime_error(std::string(message));
  }
}

class TemporaryDirectory {
public:
  TemporaryDirectory() {
    std::string pattern =
        (std::filesystem::temp_directory_path() / "omarchy-c0-XXXXXX").string();
    path_ = mkdtemp(pattern.data());
    require(!path_.empty(), "temporary directory creation failed");
  }
  ~TemporaryDirectory() {
    std::error_code error;
    std::filesystem::remove_all(path_, error);
  }
  const std::filesystem::path &path() const { return path_; }

private:
  std::filesystem::path path_;
};

void copy_tree(const std::filesystem::path &source,
               const std::filesystem::path &destination) {
  std::filesystem::create_directories(destination);
  for (const auto &entry : std::filesystem::directory_iterator(source)) {
    std::filesystem::copy(
        entry.path(), destination / entry.path().filename(),
        std::filesystem::copy_options::recursive |
            std::filesystem::copy_options::overwrite_existing);
  }
}

std::size_t count(const discovery::DiscoveryReport &report,
                  discovery::DiagnosticCode code) {
  return static_cast<std::size_t>(std::ranges::count_if(
      report.diagnostics, [code](const discovery::Diagnostic &value) {
        return value.code == code;
      }));
}

template <typename Function>
void expect_rejected(Function &&function, std::string_view message) {
  try {
    function();
  } catch (const std::exception &) {
    return;
  }
  throw std::runtime_error(std::string(message));
}

discovery::IdentityPin pin(std::string directory, std::string digest) {
  return {.directory = std::move(directory), .tree_sha256 = std::move(digest)};
}

} // namespace

int main() {
  try {
    TemporaryDirectory verified_root;
    copy_tree(MANIFEST_V2_FIXTURE_ROOT, verified_root.path() / "secure");
    const std::vector correct_pin{pin("secure", TREE_SHA256_GOLDEN)};
    auto report = discovery::discover(verified_root.path(), correct_pin,
                                      {.schema_v2_enabled = true});
    require(report.plugins.size() == 1 && report.diagnostics.empty() &&
                report.plugins.front().identity.tree_sha256 ==
                    TREE_SHA256_GOLDEN,
            "pinned schema-v2 plugin was not discovered");

    const int stable_fd =
        ::open((verified_root.path() / "secure").c_str(),
               O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
    require(stable_fd >= 0, "could not open stable plugin descriptor");
    const auto descriptor_result = discovery::discover_open_revision(stable_fd);
    require(descriptor_result.manifest == report.plugins.front().manifest &&
                descriptor_result.identity == report.plugins.front().identity,
            "descriptor discovery identity differs from stable path discovery");
    require(discovery::discover_open_revision(stable_fd).identity ==
                descriptor_result.identity,
            "descriptor discovery changed the caller's directory position");

    const auto original_path = verified_root.path() / "secure";
    const auto displaced_path = verified_root.path() / "displaced";
    std::filesystem::rename(original_path, displaced_path);
    copy_tree(MANIFEST_DUPLICATE_FIXTURE_ROOT, original_path);
    const auto after_replacement = discovery::discover_open_revision(stable_fd);
    require(after_replacement.identity == descriptor_result.identity &&
                after_replacement.manifest == descriptor_result.manifest,
            "pathname replacement retargeted descriptor discovery");
    ::close(stable_fd);
    std::filesystem::remove_all(original_path);
    std::filesystem::rename(displaced_path, original_path);

    report = discovery::discover(verified_root.path(), correct_pin,
                                 {.schema_v2_enabled = false});
    require(report.plugins.empty() &&
                count(report,
                      discovery::DiagnosticCode::schema_v2_feature_disabled) ==
                    1,
            "schema-v2 feature gate was bypassed");
    report = discovery::discover(verified_root.path(), {},
                                 {.schema_v2_enabled = true});
    require(
        report.plugins.empty() &&
            count(report, discovery::DiagnosticCode::identity_pin_missing) == 1,
        "unpinned schema-v2 tree was admitted");
    const std::vector wrong_pin{pin("secure", std::string(64, '0'))};
    report = discovery::discover(verified_root.path(), wrong_pin,
                                 {.schema_v2_enabled = true});
    require(report.plugins.empty() &&
                count(report, discovery::DiagnosticCode::identity_mismatch) ==
                    1,
            "identity mismatch was admitted");
    const std::vector missing_pin{pin("missing", TREE_SHA256_GOLDEN)};
    report = discovery::discover(verified_root.path(), missing_pin,
                                 {.schema_v2_enabled = true});
    require(count(report,
                  discovery::DiagnosticCode::registered_directory_missing) == 1,
            "missing registered directory was not diagnosed");

    TemporaryDirectory mixed_root;
    copy_tree(DISCOVERY_FIXTURE_ROOT "/legacy-v1",
              mixed_root.path() / "legacy");
    copy_tree(MANIFEST_DUPLICATE_FIXTURE_ROOT, mixed_root.path() / "bad");
    copy_tree(MANIFEST_V2_FIXTURE_ROOT, mixed_root.path() / "target");
    std::filesystem::create_symlink(mixed_root.path() / "target",
                                    mixed_root.path() / "linked");
    std::ofstream(mixed_root.path() / "not-a-plugin") << "data";
    report =
        discovery::discover(mixed_root.path(), {}, {.schema_v2_enabled = true});
    require(
        report.plugins.empty() &&
            count(report, discovery::DiagnosticCode::legacy_v1_unsafe) == 1 &&
            count(report, discovery::DiagnosticCode::invalid_manifest) == 1 &&
            count(report, discovery::DiagnosticCode::symlink_rejected) == 1 &&
            count(report, discovery::DiagnosticCode::unexpected_entry) == 1 &&
            count(report, discovery::DiagnosticCode::identity_pin_missing) == 1,
        "mixed unsafe discovery diagnostics changed");

    TemporaryDirectory special_root;
    const auto special_plugin = special_root.path() / "special";
    std::filesystem::create_directory(special_plugin);
    require(::mkfifo((special_plugin / "manifest.json").c_str(), 0600) == 0,
            "manifest FIFO creation failed");
    report = discovery::discover(special_root.path(), {},
                                 {.schema_v2_enabled = true});
    require(report.plugins.empty() &&
                count(report, discovery::DiagnosticCode::manifest_missing) == 1,
            "special manifest file did not fail closed without blocking");

    const int special_fd =
        ::open(special_plugin.c_str(),
               O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
    require(special_fd >= 0, "could not open special plugin descriptor");
    expect_rejected(
        [&] { (void)discovery::discover_open_revision(special_fd); },
        "descriptor discovery admitted a special file");
    ::close(special_fd);

    TemporaryDirectory symlink_root;
    copy_tree(MANIFEST_V2_FIXTURE_ROOT, symlink_root.path() / "linked");
    std::filesystem::create_symlink("ui/Status.qml",
                                    symlink_root.path() / "linked" / "escape");
    const int symlink_fd =
        ::open((symlink_root.path() / "linked").c_str(),
               O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
    require(symlink_fd >= 0, "could not open symlink plugin descriptor");
    expect_rejected(
        [&] { (void)discovery::discover_open_revision(symlink_fd); },
        "descriptor discovery admitted a symlink");
    ::close(symlink_fd);

    TemporaryDirectory git_root;
    copy_tree(MANIFEST_V2_FIXTURE_ROOT, git_root.path() / "checkout");
    std::filesystem::create_directories(git_root.path() / "checkout" / ".git");
    std::ofstream(git_root.path() / "checkout" / ".git/config")
        << "untrusted metadata\n";
    const int git_fd = ::open((git_root.path() / "checkout").c_str(),
                              O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
    require(git_fd >= 0, "could not open .git plugin descriptor");
    expect_rejected(
        [&] { (void)discovery::discover_open_revision(git_fd); },
        "descriptor discovery excluded sandbox-visible .git content");
    ::close(git_fd);

    TemporaryDirectory oversized_manifest_root;
    copy_tree(MANIFEST_V2_FIXTURE_ROOT,
              oversized_manifest_root.path() / "oversized");
    {
      std::ofstream manifest_file(oversized_manifest_root.path() /
                                  "oversized/manifest.json");
      manifest_file << std::string(1024 * 1024 + 1, ' ');
    }
    const int oversized_manifest_fd =
        ::open((oversized_manifest_root.path() / "oversized").c_str(),
               O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
    require(oversized_manifest_fd >= 0,
            "could not open oversized-manifest plugin descriptor");
    expect_rejected(
        [&] { (void)discovery::discover_open_revision(oversized_manifest_fd); },
        "descriptor discovery admitted an oversized manifest");
    ::close(oversized_manifest_fd);

    TemporaryDirectory changing_root;
    copy_tree(MANIFEST_V2_FIXTURE_ROOT, changing_root.path() / "changing");
    {
      std::ofstream padding(changing_root.path() / "changing" / "padding");
      padding << std::string(8 * 1024 * 1024, 'x');
    }
    const int changing_fd =
        ::open((changing_root.path() / "changing").c_str(),
               O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
    require(changing_fd >= 0, "could not open changing plugin descriptor");
    std::atomic_bool mutate{true};
    std::atomic_bool first_mutation{false};
    std::jthread mutator([&] {
      const auto marker = changing_root.path() / "changing" / "mutation";
      while (mutate.load(std::memory_order_relaxed)) {
        std::ofstream(marker) << "changed";
        std::filesystem::remove(marker);
        first_mutation.store(true, std::memory_order_release);
      }
    });
    while (!first_mutation.load(std::memory_order_acquire))
      std::this_thread::yield();
    expect_rejected(
        [&] { (void)discovery::discover_open_revision(changing_fd); },
        "descriptor discovery admitted a concurrently changing tree");
    mutate.store(false, std::memory_order_relaxed);
    mutator.join();
    ::close(changing_fd);

    const std::vector duplicate_pins{pin("target", TREE_SHA256_GOLDEN),
                                     pin("target", TREE_SHA256_GOLDEN)};
    report = discovery::discover(mixed_root.path(), duplicate_pins,
                                 {.schema_v2_enabled = true});
    require(report.plugins.empty() &&
                count(report,
                      discovery::DiagnosticCode::duplicate_registration) == 1,
            "duplicate identity registration was accepted");

    TemporaryDirectory duplicate_root;
    copy_tree(MANIFEST_V2_FIXTURE_ROOT, duplicate_root.path() / "a");
    copy_tree(MANIFEST_V2_FIXTURE_ROOT, duplicate_root.path() / "b");
    const std::vector duplicate_id_pins{pin("a", TREE_SHA256_GOLDEN),
                                        pin("b", TREE_SHA256_GOLDEN)};
    report = discovery::discover(duplicate_root.path(), duplicate_id_pins,
                                 {.schema_v2_enabled = true});
    require(report.plugins.empty() &&
                count(report, discovery::DiagnosticCode::duplicate_plugin_id) ==
                    2,
            "duplicate plugin id used first-wins discovery");

    TemporaryDirectory inert_root;
    copy_tree(MANIFEST_V2_FIXTURE_ROOT, inert_root.path() / "inert");
    const auto executable = inert_root.path() / "inert" / "never-run";
    const auto sentinel = inert_root.path() / "sentinel-fired";
    {
      std::ofstream script(executable);
      script << "#!/bin/bash\ntouch \"" << sentinel.string() << "\"\n";
    }
    std::filesystem::permissions(executable, std::filesystem::perms::owner_exec,
                                 std::filesystem::perm_options::add);
    const auto bytes = [&] {
      std::ifstream input(inert_root.path() / "inert" / "manifest.json");
      return std::string(std::istreambuf_iterator<char>(input), {});
    }();
    const auto model = manifest::parse_manifest_v2(bytes);
    const auto identity =
        manifest::identify_tree(inert_root.path() / "inert", model);
    const std::vector inert_pin{pin("inert", identity.tree_sha256)};
    report = discovery::discover(inert_root.path(), inert_pin,
                                 {.schema_v2_enabled = true});
    require(report.plugins.size() == 1 && !std::filesystem::exists(sentinel),
            "discovery executed plugin content");

    const auto repeated =
        discovery::discover(mixed_root.path(), {}, {.schema_v2_enabled = true});
    require(repeated.diagnostics ==
                discovery::discover(mixed_root.path(), {},
                                    {.schema_v2_enabled = true})
                    .diagnostics,
            "diagnostics are not deterministic");
    std::cout << "plugin manifest discovery: PASS\n";
    return 0;
  } catch (const std::exception &exception) {
    std::cerr << "plugin manifest discovery: FAIL: " << exception.what()
              << '\n';
    return 1;
  }
}
