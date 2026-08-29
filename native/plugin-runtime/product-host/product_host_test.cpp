#include "product_host.hpp"

#include "lifecycle.hpp"
#include "manifest_contract.hpp"

#include <chrono>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>
#include <string_view>

namespace {

namespace host = omarchy::plugin_runtime::product_host;
namespace launcher = omarchy::plugin_runtime::launcher;
namespace manifest = omarchy::plugins::manifest;
namespace grants = omarchy::plugins::grants;
namespace lifecycle = omarchy::plugins::lifecycle;
namespace permissions = omarchy::plugins::permissions;

void require(bool condition, std::string_view message) {
  if (!condition)
    throw std::runtime_error(std::string(message));
}

std::string read(const std::filesystem::path &path) {
  std::ifstream input(path, std::ios::binary);
  require(input.good(), "fixture could not be read");
  return {std::istreambuf_iterator<char>(input),
          std::istreambuf_iterator<char>()};
}

grants::RevisionGrants active(const manifest::ManifestV2 &parsed,
                              const manifest::ContentIdentity &identity,
                              std::uint64_t generation = 9) {
  auto requests = lifecycle::translate_requests(parsed);
  const auto policy = permissions::policy_request_fingerprint(requests);
  return {
      .binding = {.plugin = permissions::PluginId(parsed.id),
                  .revision = permissions::Digest(identity.tree_sha256),
                  .policy_fingerprint = permissions::Digest(policy),
                  .generation = generation},
      .source_request_fingerprint =
          permissions::Digest(identity.request_sha256),
      .requests = std::move(requests),
      .grants = {}};
}

void run() {
  const std::filesystem::path root{PRODUCT_HOST_PET_ROOT};
  const auto parsed = manifest::parse_manifest_v2(read(root / "manifest.json"));
  const auto identity = manifest::identify_tree(root, parsed);
  const omarchy::plugins::discovery::IdentityPin pin{
      .directory = root.filename(), .tree_sha256 = identity.tree_sha256};
  const auto revision = active(parsed, identity);

  auto disabled = host::prepare(root, pin, revision, {});
  require(!disabled &&
              disabled.failure == host::PrepareFailure::feature_disabled,
          "feature-disabled host admitted a plugin");

  auto wrong_pin = pin;
  wrong_pin.tree_sha256 = std::string(64, '0');
  auto unverified = host::prepare(
      root, wrong_pin, revision, {.schema_v2_enabled = true});
  require(!unverified &&
              unverified.failure == host::PrepareFailure::discovery_rejected,
          "identity mismatch reached host preparation");

  auto stale = revision;
  stale.binding.generation++;
  stale.binding.revision = permissions::Digest(std::string(64, 'a'));
  auto mismatched = host::prepare(
      root, pin, stale, {.schema_v2_enabled = true});
  require(!mismatched && mismatched.failure ==
                               host::PrepareFailure::grant_binding_mismatch,
          "stale grant binding reached host preparation");

  auto substituted_requests = revision;
  substituted_requests.source_request_fingerprint =
      permissions::Digest(std::string(64, 'b'));
  auto substituted = host::prepare(
      root, pin, substituted_requests, {.schema_v2_enabled = true});
  require(!substituted && substituted.failure ==
                                host::PrepareFailure::grant_binding_mismatch,
          "substituted permission request set reached host preparation");

  auto prepared = host::prepare(
      root, pin, revision, {.schema_v2_enabled = true});
  require(prepared && prepared.prepared->plugin.manifest.id == parsed.id &&
              prepared.prepared->surfaces.size() == 1 &&
              prepared.prepared->surfaces.front().surface_name == "pet" &&
              prepared.prepared->surfaces.front().role ==
                  omarchy::plugin_runtime::surface_host::SurfaceRole::desktop_overlay,
          "verified arbitrary-QML plugin lost its host-owned surface policy");

  const auto sidecar_root =
      std::filesystem::temp_directory_path() /
      ("omarchy-product-host-sidecar-" +
       std::to_string(
           std::chrono::steady_clock::now().time_since_epoch().count()));
  struct RemoveTree {
    std::filesystem::path path;
    ~RemoveTree() {
      std::error_code ignored;
      std::filesystem::remove_all(path, ignored);
    }
  } cleanup{sidecar_root};
  std::filesystem::copy(root, sidecar_root,
                        std::filesystem::copy_options::recursive);
  std::filesystem::permissions(sidecar_root / "ui/Pet.qml",
                               std::filesystem::perms::owner_exec,
                               std::filesystem::perm_options::add);
  auto sidecar_bytes = read(sidecar_root / "manifest.json");
  constexpr std::string_view qml_field = "\"qml\": \"ui/Pet.qml\"";
  const auto qml_position = sidecar_bytes.find(qml_field);
  require(qml_position != std::string::npos,
          "sidecar fixture insertion failed");
  const auto qml_end = qml_position + qml_field.size();
  sidecar_bytes.insert(
      qml_end,
      ",\n    \"sidecars\": [{\"name\": \"helper\", \"command\": [\"ui/Pet.qml\"]}]");
  {
    std::ofstream output(sidecar_root / "manifest.json",
                         std::ios::binary | std::ios::trunc);
    output << sidecar_bytes;
  }
  const auto sidecar_parsed = manifest::parse_manifest_v2(sidecar_bytes);
  const auto sidecar_identity =
      manifest::identify_tree(sidecar_root, sidecar_parsed);
  const omarchy::plugins::discovery::IdentityPin sidecar_pin{
      .directory = sidecar_root.filename(),
      .tree_sha256 = sidecar_identity.tree_sha256};
  const auto sidecar_revision = active(sidecar_parsed, sidecar_identity);
  auto sidecar_prepared = host::prepare(
      sidecar_root, sidecar_pin, sidecar_revision,
      {.schema_v2_enabled = true});
  require(!sidecar_prepared && sidecar_prepared.failure ==
                                   host::PrepareFailure::sidecars_not_supported,
          "sidecar plugin activated without the trusted sandbox init");

  host::DenyAllBroker broker(revision.binding);
  const launcher::LaunchIdentity exact{
      .plugin_id = parsed.id,
      .revision_sha256 = identity.tree_sha256,
      .generation = revision.binding.generation};
  auto stale_identity = exact;
  stale_identity.generation++;
  require(broker.accepts(exact) && !broker.accepts(stale_identity),
          "deny broker did not bind the exact worker identity");
  require(!broker.dispatch({}),
          "default broker unexpectedly granted an operation");
}

} // namespace

int main() {
  try {
    run();
    std::cout << "feature-gated product host: PASS\n";
    return 0;
  } catch (const std::exception &error) {
    std::cerr << "product-host-test: " << error.what() << '\n';
    return 1;
  }
}
