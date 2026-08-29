#include "product_host.hpp"

#include "lifecycle.hpp"
#include "manifest_contract.hpp"

#include <chrono>
#include <fcntl.h>
#include <unistd.h>
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
      .grants = {},
      .dynamic_grants = {}};
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
              prepared.prepared->surface_entrypoints.size() == 1 &&
              prepared.prepared->surface_entrypoints[0].surface == "pet" &&
              prepared.prepared->surface_entrypoints[0].qml == "ui/Pet.qml" &&
              prepared.prepared->surfaces.front().surface_name == "pet" &&
              prepared.prepared->surfaces.front().role ==
                  omarchy::plugin_runtime::surface_host::SurfaceRole::desktop_overlay,
          "verified arbitrary-QML plugin lost its host-owned surface policy");

  const auto multi_parent =
      std::filesystem::temp_directory_path() /
      ("omarchy-product-host-multi-" +
       std::to_string(
           std::chrono::steady_clock::now().time_since_epoch().count()));
  struct MultiCleanup {
    std::filesystem::path path;
    ~MultiCleanup() {
      std::error_code ignored;
      std::filesystem::remove_all(path, ignored);
    }
  } multi_cleanup{multi_parent};
  const auto multi_root = multi_parent / "radio";
  std::filesystem::create_directories(multi_parent);
  std::filesystem::copy(root, multi_root,
                        std::filesystem::copy_options::recursive);
  {
    std::ofstream bar(multi_root / "ui/Bar.qml");
    bar << "import QtQuick\nItem {}\n";
  }
  const std::string multi_manifest_bytes =
      R"({"schemaVersion":2,"id":"org.omarchy.fixture.radio","name":"Radio","version":"2.0.0","runtime":{"apiVersion":1,"qml":"ui/Pet.qml","surfaceQml":{"atlas":"ui/Pet.qml","barWidget":"ui/Bar.qml"}},"surfaces":{"atlas":{"role":"desktop-overlay","maximumWidth":900,"maximumHeight":700,"maximumFramesPerSecond":60,"keyboardFocus":"after-gesture"},"barWidget":{"role":"bar-embedded","maximumWidth":72,"maximumHeight":64,"maximumFramesPerSecond":30,"defaultSection":"left"}},"permissions":{"required":[],"optional":[]}})";
  {
    std::ofstream manifest_output(multi_root / "manifest.json",
                                  std::ios::binary | std::ios::trunc);
    manifest_output << multi_manifest_bytes;
  }
  const auto multi_parsed = manifest::parse_manifest_v2(multi_manifest_bytes);
  const auto multi_identity = manifest::identify_tree(multi_root, multi_parsed);
  const omarchy::plugins::discovery::IdentityPin multi_pin{
      .directory = multi_root.filename(),
      .tree_sha256 = multi_identity.tree_sha256};
  const auto multi_revision = active(multi_parsed, multi_identity, 17);
  auto multi_prepared = host::prepare(
      multi_root, multi_pin, multi_revision, {.schema_v2_enabled = true});
  require(multi_prepared &&
              multi_prepared.prepared->surface_entrypoints.size() == 2 &&
              multi_prepared.prepared->surface_entrypoints[0].surface ==
                  "atlas" &&
              multi_prepared.prepared->surface_entrypoints[0].qml ==
                  "ui/Pet.qml" &&
              multi_prepared.prepared->surface_entrypoints[1].surface ==
                  "barWidget" &&
              multi_prepared.prepared->surface_entrypoints[1].qml ==
                  "ui/Bar.qml",
          "multi-surface entries did not reach trusted preparation: " +
              multi_prepared.detail);

  host::MultiSurfaceActivation activation(*multi_prepared.prepared);
  constexpr std::uint64_t bar_nonce = 0x53a7;
  require(activation.register_surface("barWidget", bar_nonce,
                                      multi_revision.binding),
          "authenticated bar surface did not register");
  const auto opened = activation.route_intent(
      "barWidget", bar_nonce, multi_revision.binding, "atlas",
      host::SurfaceIntentAction::toggle, true);
  require(opened == host::SurfaceCommand{
                        "atlas", host::SurfaceIntentAction::toggle},
          "authenticated bar toggle did not produce a bounded host command");
  auto stale_multi_binding = multi_revision.binding;
  stale_multi_binding.generation++;
  require(!activation.route_intent(
              "barWidget", bar_nonce, stale_multi_binding, "atlas",
              host::SurfaceIntentAction::toggle, true) &&
              !activation.route_intent(
                  "barWidget", bar_nonce + 1, multi_revision.binding,
                  "atlas", host::SurfaceIntentAction::toggle, true) &&
              !activation.route_intent(
                  "barWidget", bar_nonce, multi_revision.binding, "atlas",
                  host::SurfaceIntentAction::toggle, false) &&
              !activation.route_intent(
                  "barWidget", bar_nonce, multi_revision.binding, "missing",
                  host::SurfaceIntentAction::toggle, true),
          "unbound, stale, gestureless, or undeclared surface intent escaped");

  const auto swap_parent =
      std::filesystem::temp_directory_path() /
      ("omarchy-product-host-swap-" +
       std::to_string(
           std::chrono::steady_clock::now().time_since_epoch().count()));
  struct SwapCleanup {
    std::filesystem::path path;
    ~SwapCleanup() {
      std::error_code ignored;
      std::filesystem::remove_all(path, ignored);
    }
  } swap_cleanup{swap_parent};
  const auto swap_root = swap_parent / "pet";
  std::filesystem::create_directories(swap_parent);
  std::filesystem::copy(root, swap_root,
                        std::filesystem::copy_options::recursive);
  const auto swap_parsed =
      manifest::parse_manifest_v2(read(swap_root / "manifest.json"));
  const auto swap_identity = manifest::identify_tree(swap_root, swap_parsed);
  const omarchy::plugins::discovery::IdentityPin swap_pin{
      .directory = swap_root.filename(),
      .tree_sha256 = swap_identity.tree_sha256};
  auto swap_prepared = host::prepare(
      swap_root, swap_pin, active(swap_parsed, swap_identity),
      {.schema_v2_enabled = true});
  require(static_cast<bool>(swap_prepared),
          "swap fixture did not reach preparation");
  std::filesystem::rename(swap_root, swap_parent / "verified");
  std::filesystem::create_directories(swap_root);
  {
    std::ofstream replacement(swap_root / "manifest.json");
    replacement << "attacker replacement";
  }
  const int pinned_manifest =
      openat(swap_prepared.prepared->revision_directory_fd, "manifest.json",
             O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
  require(pinned_manifest >= 0,
          "prepared revision descriptor was invalidated by path swap");
  std::array<char, 32> prefix{};
  const auto prefix_size = ::read(pinned_manifest, prefix.data(), prefix.size());
  close(pinned_manifest);
  require(prefix_size > 0 &&
              std::string_view(prefix.data(),
                               static_cast<std::size_t>(prefix_size))
                  .starts_with("{"),
          "launch revision descriptor followed a substituted path");

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
  require(static_cast<bool>(sidecar_prepared),
          "validated sidecar plugin did not reach trusted preparation");

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
