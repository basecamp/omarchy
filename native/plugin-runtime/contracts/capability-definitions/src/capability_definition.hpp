#pragma once

#include "manifest_contract.hpp"
#include "permission_contract.hpp"

#include <array>
#include <cstddef>
#include <cstdint>
#include <optional>
#include <string_view>
#include <type_traits>

namespace omarchy::plugins::definitions {

using Name = permissions::BoundedString<128>;
using Label = permissions::BoundedString<160>;
using Digest = permissions::Digest;
using Token = permissions::ScopeToken;
using CanonicalScope = permissions::BoundedString<4096>;

enum class DefinitionSource : std::uint8_t { omarchy_package, local_admin };
enum class EnforcementFamily : std::uint8_t {
  network_fetch,
  external_open_uri,
  system_observe,
  device_observe,
  device_control,
  media_play_stream,
  remote_account_read,
  remote_account_write,
  cli_harness,
};
enum class ScopeSchema : std::uint8_t {
  https_origins_and_methods,
  https_origins_after_gesture,
  named_sanitized_datasets,
  selected_device_fields,
  selected_device_controls,
  selected_remote_account,
  activation_source_handles_and_controls,
  exact_cli_profile,
};
enum class RiskLevel : std::uint8_t { low, moderate, high, critical };
enum class RevocationPolicy : std::uint8_t {
  deny_new,
  cancel_inflight,
  restart_worker,
};

struct AuditPolicy {
  bool record_decision = true;
  bool record_duration = true;
  bool record_byte_counts = true;
  bool redact_payload = true;
  bool redact_uri = true;
  bool redact_tokens = true;
  bool operator==(const AuditPolicy &) const = default;
};

struct OperationDefinition {
  Name name;
  Label label;
  bool mutating = false;
  bool requires_fresh_gesture = false;
  auto operator<=>(const OperationDefinition &) const = default;
};

struct AdapterBinding {
  Name adapter_class;
  // Identifies the provider protocol and its bounded semantics. Executable
  // identity belongs to the trusted provider profile, not this definition.
  Digest contract_digest;
  std::uint32_t abi_version = 0;
  bool operator==(const AdapterBinding &) const = default;
};

struct CapabilityDefinition {
  Name canonical_name;
  Name authority_identity;
  EnforcementFamily enforcement_family = EnforcementFamily::network_fetch;
  Name display_category_id;
  Label display_category_label;
  ScopeSchema scope_schema = ScopeSchema::https_origins_and_methods;
  Label title;
  Label risk_text;
  RiskLevel risk = RiskLevel::critical;
  RevocationPolicy revocation = RevocationPolicy::deny_new;
  AuditPolicy audit;
  AdapterBinding adapter;
  permissions::FixedSet<OperationDefinition, 16> operations;
  bool operator==(const CapabilityDefinition &) const = default;
};

struct CapabilityReference {
  Name canonical_name;
  std::uint32_t definition_generation = 0;
  Digest definition_digest;
  bool operator==(const CapabilityReference &) const = default;
};

struct ResolvedDefinition {
  const CapabilityDefinition *definition = nullptr;
  std::uint32_t generation = 0;
  Digest digest;
};

class TrustedDefinitionRegistry {
public:
  bool install(const CapabilityDefinition &definition, DefinitionSource source,
               std::uint32_t generation);
  [[nodiscard]] std::optional<ResolvedDefinition>
  resolve(const CapabilityReference &reference) const;
  [[nodiscard]] std::optional<ResolvedDefinition>
  find(std::string_view canonical_name) const;
  [[nodiscard]] std::size_t size() const { return size_; }

private:
  struct Entry {
    CapabilityDefinition definition;
    DefinitionSource source = DefinitionSource::omarchy_package;
    std::uint32_t generation = 0;
    Digest digest;
  };
  std::array<Entry, 128> entries_{};
  std::size_t size_ = 0;
};

[[nodiscard]] bool valid_definition(const CapabilityDefinition &definition);
[[nodiscard]] bool canonical_identifier(std::string_view value);
[[nodiscard]] bool valid_digest(std::string_view digest);
[[nodiscard]] bool valid_digest(const Digest &digest);
[[nodiscard]] Digest semantic_contract_digest(std::string_view descriptor);
[[nodiscard]] Digest definition_digest(const CapabilityDefinition &definition);

struct DynamicRequest {
  CapabilityReference definition;
  permissions::FixedSet<Name, 16> operations;
  CanonicalScope scope;
  bool required = false;
  bool operator==(const DynamicRequest &) const = default;
};

struct DynamicGrant {
  CapabilityReference definition;
  permissions::FixedSet<Name, 16> operations;
  CanonicalScope scope;
  permissions::GrantState state = permissions::GrantState::denied;
  std::uint64_t epoch = 0;
};

enum class DynamicDecision : std::uint8_t {
  allowed,
  unknown_definition,
  stale_definition,
  operation_undeclared,
  operation_ungranted,
  denied,
  revoked,
  adapter_mismatch,
  scope_expanded,
  gesture_missing,
};

enum class DynamicScopeRelation : std::uint8_t {
  equal,
  narrower,
  expanded,
  incomparable,
  invalid,
};

// Trusted adapter callbacks cross the broker/provider boundary. They are
// synchronous and noexcept: throwing across this ABI is a process-contract
// violation, not a plugin-visible error path.
using DynamicScopeCompare = DynamicScopeRelation (*)(
    const CapabilityDefinition &definition, std::string_view candidate,
    std::string_view baseline, void *context) noexcept;
static_assert(
    std::is_nothrow_invocable_r_v<DynamicScopeRelation, DynamicScopeCompare,
                                  const CapabilityDefinition &,
                                  std::string_view, std::string_view, void *>);

struct DynamicScopeValidator {
  DynamicScopeCompare compare = nullptr;
  void *context = nullptr;
};

struct DynamicAuthorization {
  DynamicDecision decision = DynamicDecision::denied;
  const CapabilityDefinition *definition = nullptr;
  const OperationDefinition *operation = nullptr;
  std::uint64_t grant_epoch = 0;
  [[nodiscard]] bool allowed() const {
    return decision == DynamicDecision::allowed;
  }
};

[[nodiscard]] DynamicAuthorization authorize_dynamic_operation(
    const TrustedDefinitionRegistry &registry, const DynamicRequest &request,
    const DynamicGrant &grant, std::string_view operation,
    std::string_view demand_scope, const AdapterBinding &running_adapter,
    const DynamicScopeValidator &scope_validator, bool fresh_gesture);

[[nodiscard]] std::optional<DynamicRequest>
dynamic_request_from_manifest(const manifest::CapabilityRequest &request,
                              const TrustedDefinitionRegistry &registry);

} // namespace omarchy::plugins::definitions
