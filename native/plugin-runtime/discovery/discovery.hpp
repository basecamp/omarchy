#pragma once

#include "manifest_contract.hpp"

#include <cstddef>
#include <filesystem>
#include <span>
#include <string>
#include <vector>

namespace omarchy::plugins::discovery {

inline constexpr std::size_t kMaximumDiscoveredPlugins = 1024;

struct IdentityPin {
  std::string directory;
  std::string tree_sha256;
};

enum class DiagnosticCode {
  root_unavailable,
  root_not_directory,
  traversal_limit,
  unexpected_entry,
  symlink_rejected,
  manifest_missing,
  manifest_too_large,
  invalid_manifest,
  legacy_v1_unsafe,
  schema_v2_feature_disabled,
  identity_pin_missing,
  identity_pin_invalid,
  registered_directory_missing,
  identity_mismatch,
  tree_verification_failed,
  duplicate_registration,
  duplicate_plugin_id,
};

struct Diagnostic {
  DiagnosticCode code;
  std::string directory;
  std::string detail;

  bool operator==(const Diagnostic &) const = default;
};

struct VerifiedPlugin {
  std::filesystem::path root;
  manifest::ManifestV2 manifest;
  manifest::ContentIdentity identity;
};

struct DiscoveryOptions {
  bool schema_v2_enabled = false;
};

struct DiscoveryReport {
  std::vector<VerifiedPlugin> plugins;
  std::vector<Diagnostic> diagnostics;
};

[[nodiscard]] DiscoveryReport discover(const std::filesystem::path &root,
                                       std::span<const IdentityPin> pins,
                                       DiscoveryOptions options);

} // namespace omarchy::plugins::discovery
