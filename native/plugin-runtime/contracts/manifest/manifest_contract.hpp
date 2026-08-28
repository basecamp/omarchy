#pragma once

#include <cstdint>
#include <filesystem>
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
  bool required = false;

  bool operator==(const CapabilityRequest &) const = default;
};

struct Runtime {
  std::uint32_t api_version = 0;
  std::string qml;
  std::vector<std::string> worker;

  bool operator==(const Runtime &) const = default;
};

struct ManifestV2 {
  std::string id;
  std::string name;
  std::string version;
  std::string description;
  Runtime runtime;
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

ManifestV2 parse_manifest_v2(std::string_view bytes);
ContentIdentity identify_tree(const std::filesystem::path &root,
                              const ManifestV2 &manifest);
std::string requested_capability_fingerprint(
    const std::vector<CapabilityRequest> &requests);
std::string sha256_hex(std::span<const std::byte> bytes);
std::string sha256_hex(std::string_view bytes);

enum class RevisionState {
  staged,
  awaiting_grants,
  candidate,
  active,
  failed,
  rollback_candidate,
};

enum class FailureReason {
  validation,
  missing_grants,
  health,
  rollback_health,
};

struct RevisionStatus {
  std::string digest;
  RevisionState state = RevisionState::staged;
  std::optional<FailureReason> failure;

  bool operator==(const RevisionStatus &) const = default;
};

class Lifecycle {
public:
  void stage(std::string digest);
  void validation_succeeded(bool required_grants_present);
  void validation_failed();
  void grants_changed(bool required_grants_present);
  void candidate_health_succeeded();
  void candidate_health_failed();
  void begin_rollback(std::string digest, bool required_grants_present);
  void rollback_health_succeeded();
  void rollback_health_failed();
  void discard_failed();

  [[nodiscard]] const std::optional<RevisionStatus> &active() const;
  [[nodiscard]] const std::optional<RevisionStatus> &pending() const;
  [[nodiscard]] const std::vector<RevisionStatus> &history() const;

private:
  std::optional<RevisionStatus> active_;
  std::optional<RevisionStatus> pending_;
  std::vector<RevisionStatus> history_;
};

} // namespace omarchy::plugins::manifest
