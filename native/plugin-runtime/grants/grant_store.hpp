#pragma once

#include "permission_contract.hpp"

#include <cstdint>
#include <filesystem>
#include <functional>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace omarchy::plugins::grants {

namespace permission = omarchy::plugins::permissions;

inline constexpr std::uint16_t kStoreSchemaVersion = 2;
inline constexpr std::uint16_t kSecurePluginSchemaVersion = 2;
inline constexpr std::size_t kMaximumPlugins = 1024;
inline constexpr std::size_t kMaximumDecisions = 4096;
inline constexpr std::size_t kMaximumStoreBytes = 4 * 1024 * 1024;

struct RequestBundle {
  std::uint16_t plugin_schema_version = 0;
  permission::PluginId plugin;
  permission::Digest revision;
  permission::Digest source_request_fingerprint;
  std::uint64_t generation = 0;
  permission::RequestSet requests;
};

struct RevisionGrants {
  permission::ActivationBinding binding;
  permission::Digest source_request_fingerprint;
  permission::RequestSet requests;
  permission::GrantSet grants;
};

struct CapabilityEpoch {
  permission::CapabilityKey capability;
  std::uint64_t epoch = 0;
};

struct PluginGrants {
  permission::PluginId plugin;
  std::optional<RevisionGrants> active;
  std::optional<RevisionGrants> candidate;
  std::optional<RevisionGrants> rollback;
  std::vector<CapabilityEpoch> epochs;
};

struct StoreState {
  std::uint16_t schema_version = kStoreSchemaVersion;
  std::uint64_t mutation_sequence = 0;
  std::uint64_t next_decision_sequence = 1;
  std::vector<PluginGrants> plugins;
  std::vector<permission::UserDecisionRecord> decisions;
};

enum class TargetRevision : std::uint8_t { active, candidate };

struct Preview {
  std::uint64_t expected_mutation_sequence = 0;
  TargetRevision target = TargetRevision::candidate;
  permission::DeltaSet request_delta;
  std::optional<permission::GrantRecord> current_grant;
  permission::ActivationBinding binding;
  permission::Digest source_request_fingerprint;
};

struct MutationResult {
  std::uint64_t mutation_sequence = 0;
  std::uint64_t decision_sequence = 0;
  TargetRevision target = TargetRevision::candidate;
  permission::GrantRecord grant;
  std::string grant_fingerprint;
};

struct RevocationResult {
  std::uint64_t mutation_sequence = 0;
  TargetRevision target = TargetRevision::candidate;
  permission::GrantRecord grant;
  permission::RevocationMode action = permission::RevocationMode::deny_new;
  std::string grant_fingerprint;
};

struct StageResult {
  std::uint64_t mutation_sequence = 0;
  TargetRevision target = TargetRevision::candidate;
  permission::DeltaSet request_delta;
  RevisionGrants revision;
};

class GrantStore {
public:
  explicit GrantStore(std::filesystem::path directory);

  [[nodiscard]] StoreState read() const;
  [[nodiscard]] Preview
  preview(const RequestBundle &bundle,
          const permission::CapabilityKey &capability) const;
  [[nodiscard]] MutationResult
  decide(const RequestBundle &bundle,
         const permission::CapabilityKey &capability,
         const std::optional<permission::Scope> &granted_scope,
         permission::UserDecision decision, permission::DecisionActor actor,
         std::uint64_t decided_wall_seconds,
         std::uint64_t expected_mutation_sequence);
  [[nodiscard]] RevocationResult
  revoke(const RequestBundle &bundle,
         const permission::CapabilityKey &capability);

  [[nodiscard]] StageResult stage_candidate(const RequestBundle &bundle);

  // Lifecycle integration only. The user-facing permission CLI does not expose
  // activation or candidate discard.
  void activate_candidate(const permission::ActivationBinding &binding);
  void rollback_to(const permission::ActivationBinding &binding);
  void discard_candidate(const permission::PluginId &plugin);

  [[nodiscard]] const std::filesystem::path &directory() const {
    return directory_;
  }

private:
  std::filesystem::path directory_;
};

[[nodiscard]] RequestBundle
make_bundle(std::uint16_t plugin_schema_version, permission::PluginId plugin,
            permission::Digest revision,
            permission::Digest source_request_fingerprint,
            std::uint64_t generation, permission::RequestSet requests);

[[nodiscard]] std::string state_json(const StoreState &state);
[[nodiscard]] std::string preview_json(const Preview &preview);
[[nodiscard]] std::string mutation_json(const MutationResult &result);
[[nodiscard]] std::string revocation_json(const RevocationResult &result);

} // namespace omarchy::plugins::grants
