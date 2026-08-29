#pragma once

#include "permission_contract.hpp"

#include <array>
#include <cstddef>
#include <cstdint>
#include <optional>
#include <span>
#include <string_view>

namespace omarchy::plugins::definitions {

using Name = permissions::BoundedString<128>;
using Label = permissions::BoundedString<160>;
using Digest = permissions::Digest;
using Token = permissions::ScopeToken;

enum class DefinitionSource : std::uint8_t { omarchy_package, local_admin };
enum class AuthorityCategory : std::uint8_t {
  network_fetch,
  external_open_uri,
  system_observe,
  device_observe,
  device_control,
  media_play_stream,
  cli_harness,
};
enum class ScopeSchema : std::uint8_t {
  https_origins_and_methods,
  https_origins_after_gesture,
  named_sanitized_datasets,
  adapter_resources,
  https_stream_origins,
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
  Digest implementation_digest;
  std::uint32_t abi_version = 0;
  bool operator==(const AdapterBinding &) const = default;
};

struct CapabilityDefinition {
  Name canonical_name;
  Name authority_identity;
  AuthorityCategory category = AuthorityCategory::network_fetch;
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
[[nodiscard]] Digest
definition_digest(const CapabilityDefinition &definition);

enum class ArgumentKind : std::uint8_t {
  literal,
  bounded_token,
  bounded_unsigned,
};

struct ArgumentRule {
  ArgumentKind kind = ArgumentKind::literal;
  Token value;
  std::uint32_t maximum = 0;
  bool operator==(const ArgumentRule &) const = default;
};

struct CliSubcommand {
  Name name;
  permissions::FixedVector<ArgumentRule, 12> arguments;
};

struct CliHarnessProfile {
  Name profile_name;
  permissions::BoundedString<256> executable;
  Digest executable_digest;
  permissions::BoundedString<256> working_directory;
  permissions::FixedSet<Token, 16> fixed_environment;
  permissions::FixedVector<CliSubcommand, 16> subcommands;
  std::uint32_t maximum_stdin_bytes = 0;
  std::uint32_t maximum_stdout_bytes = 0;
  std::uint32_t maximum_stderr_bytes = 0;
  std::uint32_t timeout_milliseconds = 0;
};

struct CliInvocation {
  std::array<std::string_view, 13> argv{};
  std::size_t argc = 0;
};

[[nodiscard]] bool valid_cli_profile(const CliHarnessProfile &profile);
[[nodiscard]] bool authorize_cli_invocation(const CliHarnessProfile &profile,
                                            const Digest &actual_executable,
                                            std::span<const std::string_view> argv,
                                            CliInvocation &output);

} // namespace omarchy::plugins::definitions
