#include "capability_definition.hpp"

#include "manifest_contract.hpp"

#include <algorithm>
#include <charconv>
#include <string>

namespace omarchy::plugins::definitions {
namespace {

bool canonical_name(std::string_view value) {
  if (value.empty())
    return false;
  bool separator = true;
  for (const unsigned char item : value) {
    const bool alphanumeric = (item >= 'a' && item <= 'z') ||
                              (item >= '0' && item <= '9');
    const bool current_separator = item == '.' || item == '-';
    if ((!alphanumeric && !current_separator) ||
        (separator && current_separator))
      return false;
    separator = current_separator;
  }
  return !separator;
}

bool hex_digest(const Digest &digest) {
  return digest.size() == 64 &&
         std::all_of(digest.view().begin(), digest.view().end(), [](char item) {
           return (item >= '0' && item <= '9') ||
                  (item >= 'a' && item <= 'f');
         });
}

void append(std::string &bytes, std::string_view value) {
  bytes.append(std::to_string(value.size()));
  bytes.push_back(':');
  bytes.append(value);
}

bool absolute_normal_path(std::string_view path) {
  return path.starts_with('/') && path.find("//") == std::string_view::npos &&
         path.find("/../") == std::string_view::npos &&
         !path.ends_with("/..") && path.find("/./") == std::string_view::npos &&
         !path.ends_with("/.");
}

bool safe_token(std::string_view value) {
  return !value.empty() && value.size() <= 96 &&
         std::all_of(value.begin(), value.end(), [](unsigned char item) {
           return (item >= 'a' && item <= 'z') ||
                  (item >= 'A' && item <= 'Z') ||
                  (item >= '0' && item <= '9') || item == '.' || item == '-' ||
                  item == '_' || item == ':' || item == '/';
         });
}

} // namespace

bool valid_definition(const CapabilityDefinition &definition) {
  if (!canonical_name(definition.canonical_name.view()) ||
      !canonical_name(definition.authority_identity.view()) ||
      !canonical_name(definition.display_category_id.view()) ||
      definition.display_category_label.size() == 0 ||
      !canonical_name(definition.adapter.adapter_class.view()) ||
      !hex_digest(definition.adapter.implementation_digest) ||
      definition.adapter.abi_version == 0 || definition.operations.size() == 0 ||
      definition.title.size() == 0 || definition.risk_text.size() == 0 ||
      !definition.audit.record_decision || !definition.audit.redact_payload ||
      !definition.audit.redact_tokens)
    return false;
  if ((definition.enforcement_family == EnforcementFamily::external_open_uri) !=
      (definition.scope_schema == ScopeSchema::https_origins_after_gesture))
    return false;
  if (definition.enforcement_family == EnforcementFamily::external_open_uri &&
      std::any_of(definition.operations.values().begin(),
                  definition.operations.values().end(), [](const auto &op) {
                    return !op.requires_fresh_gesture;
                  }))
    return false;
  return std::all_of(
      definition.operations.values().begin(),
      definition.operations.values().end(), [](const auto &operation) {
        return canonical_name(operation.name.view()) && operation.label.size() > 0;
      });
}

Digest definition_digest(const CapabilityDefinition &definition) {
  std::string bytes("OMARCHY-CAPABILITY-DEFINITION-V1\0", 33);
  append(bytes, definition.canonical_name.view());
  append(bytes, definition.authority_identity.view());
  bytes.push_back(static_cast<char>(definition.enforcement_family));
  append(bytes, definition.display_category_id.view());
  append(bytes, definition.display_category_label.view());
  bytes.push_back(static_cast<char>(definition.scope_schema));
  append(bytes, definition.title.view());
  append(bytes, definition.risk_text.view());
  bytes.push_back(static_cast<char>(definition.risk));
  bytes.push_back(static_cast<char>(definition.revocation));
  bytes.push_back(definition.audit.record_decision ? 1 : 0);
  bytes.push_back(definition.audit.record_duration ? 1 : 0);
  bytes.push_back(definition.audit.record_byte_counts ? 1 : 0);
  bytes.push_back(definition.audit.redact_payload ? 1 : 0);
  bytes.push_back(definition.audit.redact_uri ? 1 : 0);
  bytes.push_back(definition.audit.redact_tokens ? 1 : 0);
  append(bytes, definition.adapter.adapter_class.view());
  append(bytes, definition.adapter.implementation_digest.view());
  for (int shift = 24; shift >= 0; shift -= 8)
    bytes.push_back(static_cast<char>(definition.adapter.abi_version >> shift));
  for (const auto &operation : definition.operations.values()) {
    append(bytes, operation.name.view());
    append(bytes, operation.label.view());
    bytes.push_back(operation.mutating ? 1 : 0);
    bytes.push_back(operation.requires_fresh_gesture ? 1 : 0);
  }
  return Digest(manifest::sha256_hex(bytes));
}

bool TrustedDefinitionRegistry::install(const CapabilityDefinition &definition,
                                        DefinitionSource source,
                                        std::uint32_t generation) {
  if (!valid_definition(definition) || generation == 0 || size_ == entries_.size())
    return false;
  const auto digest = definition_digest(definition);
  for (std::size_t index = 0; index < size_; ++index) {
    const auto &entry = entries_[index];
    if (entry.definition.canonical_name == definition.canonical_name ||
        entry.definition.authority_identity == definition.authority_identity)
      return false;
    if (entry.definition.adapter == definition.adapter &&
        entry.definition.operations == definition.operations)
      return false;
  }
  entries_[size_++] = {.definition = definition,
                       .source = source,
                       .generation = generation,
                       .digest = digest};
  return true;
}

std::optional<ResolvedDefinition>
TrustedDefinitionRegistry::find(std::string_view canonical) const {
  const auto found = std::find_if(entries_.begin(), entries_.begin() + size_,
                                  [canonical](const auto &entry) {
                                    return entry.definition.canonical_name.view() == canonical;
                                  });
  if (found == entries_.begin() + size_)
    return std::nullopt;
  return ResolvedDefinition{.definition = &found->definition,
                            .generation = found->generation,
                            .digest = found->digest};
}

std::optional<ResolvedDefinition>
TrustedDefinitionRegistry::resolve(const CapabilityReference &reference) const {
  const auto found = find(reference.canonical_name.view());
  if (!found || found->generation != reference.definition_generation ||
      found->digest != reference.definition_digest)
    return std::nullopt;
  return found;
}

bool valid_cli_profile(const CliHarnessProfile &profile) {
  if (!canonical_name(profile.profile_name.view()) ||
      !absolute_normal_path(profile.executable.view()) ||
      !absolute_normal_path(profile.working_directory.view()) ||
      !hex_digest(profile.executable_digest) || profile.subcommands.empty() ||
      profile.maximum_stdout_bytes == 0 || profile.maximum_stdout_bytes > 1048576 ||
      profile.maximum_stderr_bytes > 65536 ||
      profile.maximum_stdin_bytes > 1048576 ||
      profile.timeout_milliseconds == 0 || profile.timeout_milliseconds > 30000)
    return false;
  const auto executable = profile.executable.view();
  const auto basename = executable.substr(executable.find_last_of('/') + 1);
  if (basename == "bash" || basename == "sh" || basename == "env")
    return false;
  for (const auto &environment : profile.fixed_environment.values()) {
    const auto value = environment.view();
    const auto equal = value.find('=');
    if (equal == std::string_view::npos || equal == 0 ||
        !safe_token(value.substr(0, equal)) || !safe_token(value.substr(equal + 1)))
      return false;
  }
  for (const auto &subcommand : profile.subcommands.values()) {
    if (!canonical_name(subcommand.name.view()))
      return false;
    for (const auto &rule : subcommand.arguments.values()) {
      if (rule.kind == ArgumentKind::literal && !safe_token(rule.value.view()))
        return false;
      if (rule.kind != ArgumentKind::literal &&
          (rule.maximum == 0 || rule.maximum > 4096))
        return false;
    }
  }
  return true;
}

bool authorize_cli_invocation(const CliHarnessProfile &profile,
                              const Digest &actual_executable,
                              std::span<const std::string_view> argv,
                              CliInvocation &output) {
  output = {};
  if (!valid_cli_profile(profile) || actual_executable != profile.executable_digest ||
      argv.empty() || argv.size() > output.argv.size())
    return false;
  const auto found = std::find_if(
      profile.subcommands.values().begin(), profile.subcommands.values().end(),
      [&argv](const auto &command) { return command.name.view() == argv[0]; });
  if (found == profile.subcommands.values().end() ||
      argv.size() != found->arguments.size() + 1)
    return false;
  for (std::size_t index = 0; index < found->arguments.size(); ++index) {
    const auto argument = argv[index + 1];
    const auto &rule = found->arguments[index];
    if (argument.empty() || argument.size() > 4096 ||
        (rule.kind == ArgumentKind::literal && argument != rule.value.view()) ||
        (rule.kind == ArgumentKind::bounded_token &&
         (argument.size() > rule.maximum || !safe_token(argument))))
      return false;
    if (rule.kind == ArgumentKind::bounded_unsigned) {
      std::uint32_t value = 0;
      const auto [end, error] =
          std::from_chars(argument.data(), argument.data() + argument.size(), value);
      if (error != std::errc{} || end != argument.data() + argument.size() ||
          value > rule.maximum)
        return false;
    }
  }
  std::copy(argv.begin(), argv.end(), output.argv.begin());
  output.argc = argv.size();
  return true;
}

DynamicAuthorization authorize_dynamic_operation(
    const TrustedDefinitionRegistry &registry, const DynamicRequest &request,
    const DynamicGrant &grant, std::string_view operation,
    std::string_view demand_scope, const AdapterBinding &running_adapter,
    const DynamicScopeValidator &scope_validator, bool fresh_gesture) {
  const auto by_name = registry.find(request.definition.canonical_name.view());
  if (!by_name)
    return {.decision = DynamicDecision::unknown_definition};
  const auto resolved = registry.resolve(request.definition);
  if (!resolved || grant.definition.canonical_name != request.definition.canonical_name ||
      grant.definition.definition_generation != request.definition.definition_generation ||
      grant.definition.definition_digest != request.definition.definition_digest)
    return {.decision = DynamicDecision::stale_definition};
  if (!std::any_of(request.operations.values().begin(),
                   request.operations.values().end(), [operation](const auto &item) {
                     return item.view() == operation;
                   }))
    return {.decision = DynamicDecision::operation_undeclared,
            .definition = resolved->definition};
  const auto found = std::find_if(
      resolved->definition->operations.values().begin(),
      resolved->definition->operations.values().end(), [operation](const auto &item) {
        return item.name.view() == operation;
      });
  if (found == resolved->definition->operations.values().end())
    return {.decision = DynamicDecision::operation_undeclared,
            .definition = resolved->definition};
  if (grant.state == permissions::GrantState::denied)
    return {.decision = DynamicDecision::denied,
            .definition = resolved->definition, .operation = &*found};
  if (grant.state == permissions::GrantState::revoked || grant.epoch == 0)
    return {.decision = DynamicDecision::revoked,
            .definition = resolved->definition, .operation = &*found};
  if (!std::any_of(grant.operations.values().begin(),
                   grant.operations.values().end(), [operation](const auto &item) {
                     return item.view() == operation;
                   }))
    return {.decision = DynamicDecision::operation_ungranted,
            .definition = resolved->definition, .operation = &*found};
  if (scope_validator.compare == nullptr)
    return {.decision = DynamicDecision::scope_expanded,
            .definition = resolved->definition, .operation = &*found};
  const auto grant_to_request = scope_validator.compare(
      *resolved->definition, grant.scope.view(), request.scope.view(),
      scope_validator.context);
  const auto demand_to_grant = scope_validator.compare(
      *resolved->definition, demand_scope, grant.scope.view(),
      scope_validator.context);
  const auto allowed_relation = [](DynamicScopeRelation relation) {
    return relation == DynamicScopeRelation::equal ||
           relation == DynamicScopeRelation::narrower;
  };
  if (!allowed_relation(grant_to_request) || !allowed_relation(demand_to_grant))
    return {.decision = DynamicDecision::scope_expanded,
            .definition = resolved->definition, .operation = &*found};
  if (running_adapter != resolved->definition->adapter)
    return {.decision = DynamicDecision::adapter_mismatch,
            .definition = resolved->definition, .operation = &*found};
  if (found->requires_fresh_gesture && !fresh_gesture)
    return {.decision = DynamicDecision::gesture_missing,
            .definition = resolved->definition, .operation = &*found};
  return {.decision = DynamicDecision::allowed,
          .definition = resolved->definition,
          .operation = &*found,
          .grant_epoch = grant.epoch};
}

std::optional<DynamicRequest>
dynamic_request_from_manifest(const manifest::CapabilityRequest &request,
                              const TrustedDefinitionRegistry &registry) {
  try {
    if (request.definition_generation == 0 || request.definition_digest.empty() ||
        request.operations.empty())
      return std::nullopt;
    DynamicRequest result{
        .definition = {.canonical_name = Name(request.capability),
                       .definition_generation = request.definition_generation,
                       .definition_digest = Digest(request.definition_digest)},
        .operations = {},
        .scope = CanonicalScope(request.canonical_scope),
        .required = request.required,
    };
    const auto resolved = registry.resolve(result.definition);
    if (!resolved)
      return std::nullopt;
    for (const auto &operation : request.operations) {
      const Name name(operation);
      if (!std::ranges::any_of(resolved->definition->operations.values(),
                               [&](const auto &defined) {
                                 return defined.name == name;
                               }) ||
          !result.operations.insert(name))
        return std::nullopt;
    }
    return result;
  } catch (const std::runtime_error &) {
    return std::nullopt;
  }
}

} // namespace omarchy::plugins::definitions
