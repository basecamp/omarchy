#pragma once

#include <cstdint>
#include <optional>
#include <map>
#include <span>
#include <string>
#include <string_view>
#include <variant>
#include <vector>

namespace omarchy::plugins::manifest {

using SettingValue = std::variant<bool, std::int64_t, std::string>;

enum class SettingType : std::uint8_t { boolean, integer, enumeration };

struct SettingDefinition {
  std::string key;
  SettingType type = SettingType::boolean;
  std::string label;
  std::string description;
  std::optional<std::int64_t> minimum;
  std::optional<std::int64_t> maximum;
  std::optional<std::int64_t> step;
  std::vector<std::string> options;
  SettingValue default_value = false;

  bool operator==(const SettingDefinition &) const = default;
};

struct Settings {
  std::map<std::string, SettingValue, std::less<>> defaults;
  std::vector<SettingDefinition> schema;
  std::string canonical_defaults;

  bool operator==(const Settings &) const = default;
};

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
  std::string author;
  std::string license;
  std::string homepage;
  std::string repository;
  std::vector<std::string> keywords;
  Runtime runtime;
  Settings settings;
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
// Settings entries are whole replacements. Every declared key must be present
// and no undeclared key is accepted, so callers can apply a candidate
// atomically without a partially validated merge.
bool validate_settings_entry(
    const ManifestV2 &manifest,
    const std::map<std::string, SettingValue, std::less<>> &entry) noexcept;
std::optional<std::map<std::string, SettingValue, std::less<>>>
parse_settings_entry(const ManifestV2 &manifest, std::string_view bytes) noexcept;
std::string canonical_settings_entry(
    const std::map<std::string, SettingValue, std::less<>> &entry);
// Returns owned requests in the exact tuple order used by
// requested_capability_fingerprint(). Operations are sorted in each returned
// request, so callers cannot accidentally construct a different index space.
std::vector<CapabilityRequest> canonical_capability_requests(
    std::vector<CapabilityRequest> requests);
ContentIdentity identify_tree_contents(TreeContents contents,
                                       const ManifestV2 &manifest);
std::string requested_capability_fingerprint(
    const std::vector<CapabilityRequest> &requests);
std::string sha256_hex(std::span<const std::byte> bytes);
std::string sha256_hex(std::string_view bytes);

} // namespace omarchy::plugins::manifest
