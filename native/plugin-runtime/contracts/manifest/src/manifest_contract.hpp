#pragma once

#include <cstdint>
#include <optional>
#include <span>
#include <string>
#include <string_view>
#include <vector>

namespace omarchy::plugins::manifest {

struct CapabilityRequest {
  std::string capability;
  std::string reason;
  std::string canonical_scope;
  std::uint32_t definition_generation = 0;
  std::string definition_digest;
  std::vector<std::string> operations;
  bool required = false;

  bool operator==(const CapabilityRequest &) const = default;
};

struct Runtime {
  struct SurfaceEntry {
    std::string surface;
    std::string qml;

    bool operator==(const SurfaceEntry &) const = default;
  };

  struct Sidecar {
    std::string name;
    std::vector<std::string> command;

    bool operator==(const Sidecar &) const = default;
  };

  std::uint32_t api_version = 0;
  std::string qml;
  std::vector<SurfaceEntry> surface_qml;
  std::vector<std::string> worker;
  std::vector<Sidecar> sidecars;

  bool operator==(const Runtime &) const = default;
};

struct ManifestV2 {
  std::string id;
  std::string name;
  std::string version;
  std::string description;
  Runtime runtime;
  std::vector<std::string> surface_names;
  std::string canonical_surfaces;
  std::vector<CapabilityRequest> requests;
  std::string canonical_json;

  bool operator==(const ManifestV2 &) const = default;
};

struct ContentIdentity {
  std::string tree_sha256;
  std::string manifest_sha256;
  std::string request_sha256;

  bool operator==(const ContentIdentity &) const = default;
};

struct TreeEntry {
  std::string relative;
  std::string bytes;
  bool executable = false;
};

// Bounded, owned input to the canonical content-identity algorithm. Filesystem
// front ends add entries here so size, count, and relative-path rules have one
// implementation regardless of how the tree was opened.
class TreeContents {
public:
  void add(TreeEntry entry);
  [[nodiscard]] std::uint64_t remaining_bytes() const noexcept;
  [[nodiscard]] const TreeEntry *find(std::string_view relative) const noexcept;

private:
  std::vector<TreeEntry> entries_;
  std::uint64_t total_bytes_ = 0;

  friend ContentIdentity identify_tree_contents(TreeContents,
                                                const ManifestV2 &);
};

ManifestV2 parse_manifest_v2(std::string_view bytes);
ContentIdentity identify_tree_contents(TreeContents contents,
                                       const ManifestV2 &manifest);
std::string requested_capability_fingerprint(
    const std::vector<CapabilityRequest> &requests);
std::string sha256_hex(std::span<const std::byte> bytes);
std::string sha256_hex(std::string_view bytes);

} // namespace omarchy::plugins::manifest
