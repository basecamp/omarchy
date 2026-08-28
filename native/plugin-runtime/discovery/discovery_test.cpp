#include "discovery.hpp"

#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

#include <algorithm>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>
#include <string_view>
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
