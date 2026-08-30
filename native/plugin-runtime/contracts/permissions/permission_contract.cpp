#include "permission_contract.hpp"

#include "manifest_contract.hpp"

#include <bit>
#include <charconv>
#include <limits>
#include <stdexcept>
#include <tuple>

namespace omarchy::plugins::permissions {
namespace {

void require(bool condition, std::string_view message) {
  if (!condition)
    throw std::runtime_error(std::string(message));
}

bool canonical_id(std::string_view value) {
  if (value.empty() || value.size() > 128)
    return false;
  bool separator = true;
  for (const unsigned char item : value) {
    const bool alphanumeric =
        (item >= 'a' && item <= 'z') || (item >= '0' && item <= '9');
    const bool current_separator = item == '.' || item == '-' || item == '_';
    if (!alphanumeric && !current_separator)
      return false;
    if (separator && current_separator)
      return false;
    separator = current_separator;
  }
  return !separator && value.front() >= 'a' && value.front() <= 'z';
}

bool canonical_digest(const Digest &digest) {
  return digest.size() == 64 &&
         std::all_of(digest.view().begin(), digest.view().end(),
                     [](const unsigned char item) {
                       return (item >= '0' && item <= '9') ||
                              (item >= 'a' && item <= 'f');
                     });
}

template <std::size_t Size>
bool nonzero(const std::array<std::byte, Size> &bytes) {
  return std::any_of(bytes.begin(), bytes.end(),
                     [](std::byte value) { return value != std::byte{0}; });
}

template <typename T, std::size_t Capacity>
bool subset(const FixedSet<T, Capacity> &candidate,
            const FixedSet<T, Capacity> &baseline) {
  return std::all_of(
      candidate.values().begin(), candidate.values().end(),
      [&baseline](const T &item) { return baseline.contains(item); });
}

template <typename T, std::size_t Capacity>
ScopeRelation compare_sets(const FixedSet<T, Capacity> &candidate,
                           const FixedSet<T, Capacity> &baseline) {
  const bool candidate_subset = subset(candidate, baseline);
  const bool baseline_subset = subset(baseline, candidate);
  if (candidate_subset && baseline_subset)
    return ScopeRelation::equal;
  if (candidate_subset)
    return ScopeRelation::narrower;
  if (baseline_subset)
    return ScopeRelation::expanded;
  return ScopeRelation::incomparable;
}

ScopeRelation combine(ScopeRelation left, ScopeRelation right) {
  if (left == ScopeRelation::incomparable ||
      right == ScopeRelation::incomparable)
    return ScopeRelation::incomparable;
  if (left == ScopeRelation::equal)
    return right;
  if (right == ScopeRelation::equal)
    return left;
  return left == right ? left : ScopeRelation::incomparable;
}

void append_u8(std::string &output, std::uint8_t value) {
  output.push_back(static_cast<char>(value));
}

void append_u16(std::string &output, std::uint16_t value) {
  output.push_back(static_cast<char>(value >> 8));
  output.push_back(static_cast<char>(value & 0xff));
}

void append_u32(std::string &output, std::uint32_t value) {
  for (int shift = 24; shift >= 0; shift -= 8)
    output.push_back(static_cast<char>((value >> shift) & 0xff));
}

void append_u64(std::string &output, std::uint64_t value) {
  for (int shift = 56; shift >= 0; shift -= 8)
    output.push_back(static_cast<char>((value >> shift) & 0xff));
}

void append_text(std::string &output, std::string_view value) {
  require(value.size() <= std::numeric_limits<std::uint16_t>::max(),
          "canonical text is too long");
  append_u16(output, static_cast<std::uint16_t>(value.size()));
  output.append(value);
}

template <std::size_t Capacity>
void append_tokens(std::string &output,
                   const FixedSet<ScopeToken, Capacity> &tokens) {
  append_u8(output, static_cast<std::uint8_t>(tokens.size()));
  for (const auto &token : tokens.values())
    append_text(output, token.view());
}

const std::array<CapabilityDefinition, 3> kRegistry{{
    {.key = {CapabilityId("storage.private"), 1},
     .scope_kind = ScopeKind::quota,
     .operations = {OperationId::storage_read, OperationId::storage_write,
                    OperationId::storage_remove, OperationId::storage_read},
     .operation_count = 3,
     .gesture = GestureRule::none,
     .revocation = RevocationMode::cancel_inflight},
    {.key = {CapabilityId("notifications.send"), 1},
     .scope_kind = ScopeKind::tokens,
     .operations = {OperationId::notification_send},
     .operation_count = 1,
     .gesture = GestureRule::none,
     .revocation = RevocationMode::deny_new},
    {.key = {CapabilityId("audio.play-cue"), 1},
     .scope_kind = ScopeKind::tokens,
     .operations = {OperationId::audio_play_cue},
     .operation_count = 1,
     .gesture = GestureRule::none,
     .revocation = RevocationMode::deny_new},
}};

bool operation_in(const CapabilityDefinition &definition,
                  OperationId operation) {
  return std::find(definition.operations.begin(),
                   definition.operations.begin() + definition.operation_count,
                   operation) !=
         definition.operations.begin() + definition.operation_count;
}

bool demand_matches_operation(const Scope &scope, OperationId operation) {
  const auto *resources = std::get_if<ResourceScope>(&scope);
  return resources == nullptr || (resources->operations.size() == 1 &&
                                  resources->operations.contains(operation));
}

const CapabilityRequest *request_for(const RequestSet &requests,
                                     const CapabilityKey &key) {
  const auto found = std::find_if(
      requests.values().begin(), requests.values().end(),
      [&key](const auto &request) { return request.capability == key; });
  return found == requests.values().end() ? nullptr : &*found;
}

const GrantRecord *grant_for(const GrantSet &grants, const CapabilityKey &key) {
  const auto found = std::find_if(
      grants.values().begin(), grants.values().end(),
      [&key](const auto &grant) { return grant.capability == key; });
  return found == grants.values().end() ? nullptr : &*found;
}

void validate_grants(const GrantSet &grants, const RequestSet *requests) {
  FixedSet<CapabilityKey, 64> seen;
  for (const auto &grant : grants.values()) {
    require(seen.insert(grant.capability), "duplicate grant");
    require(static_cast<std::uint8_t>(grant.state) <=
                static_cast<std::uint8_t>(GrantState::revoked),
            "invalid grant state");
    const auto *definition = find_capability(grant.capability);
    require(definition != nullptr && valid_scope(*definition, grant.scope) &&
                grant.epoch > 0,
            "invalid grant");
    if (requests == nullptr)
      continue;
    const auto *request = request_for(*requests, grant.capability);
    require(request != nullptr, "grant is not declared by policy");
    const auto relation = compare_scope(grant.scope, request->scope);
    require(relation == ScopeRelation::equal ||
                relation == ScopeRelation::narrower,
            "grant expands policy request");
  }
}

GrantRecord *grant_for(GrantSet &grants, const CapabilityKey &key) {
  const auto found = std::find_if(
      grants.values().begin(), grants.values().end(),
      [&key](const auto &grant) { return grant.capability == key; });
  return found == grants.values().end() ? nullptr : &*found;
}

std::string fingerprint(std::string bytes) {
  return manifest::sha256_hex(bytes);
}

template <std::size_t Size> std::string domain(const char (&value)[Size]) {
  return std::string(value, Size - 1);
}

bool valid_scope_token(char value) {
  return (value >= 'a' && value <= 'z') || (value >= 'A' && value <= 'Z') ||
         (value >= '0' && value <= '9') || value == '.' || value == '_' ||
         value == '-';
}

std::uint64_t parse_unsigned(std::string_view value) {
  std::uint64_t result = 0;
  const auto [end, error] =
      std::from_chars(value.data(), value.data() + value.size(), result);
  require(!value.empty() && error == std::errc{} &&
              end == value.data() + value.size(),
          "manifest scope contains an invalid integer");
  return result;
}

std::vector<std::string_view> parse_token_array(std::string_view value,
                                                std::string_view prefix) {
  constexpr std::string_view suffix = "]}";
  require(value.starts_with(prefix) && value.ends_with(suffix),
          "manifest scope has an unregistered shape");
  value.remove_prefix(prefix.size());
  value.remove_suffix(suffix.size());
  require(!value.empty(), "manifest scope token list is empty");
  std::vector<std::string_view> result;
  while (!value.empty()) {
    require(value.front() == '"', "manifest scope token is not a string");
    value.remove_prefix(1);
    const auto end = value.find('"');
    require(end != std::string_view::npos,
            "manifest scope token is unterminated");
    const auto token = value.substr(0, end);
    require(!token.empty() && std::ranges::all_of(token, valid_scope_token),
            "manifest scope token is not registered text");
    result.push_back(token);
    value.remove_prefix(end + 1);
    if (value.empty())
      break;
    require(value.starts_with(","),
            "manifest scope token separator is invalid");
    value.remove_prefix(1);
  }
  return result;
}

TokenScope token_scope(std::span<const std::string_view> values) {
  TokenScope result;
  for (const auto value : values)
    require(result.tokens.insert(ScopeToken(value)),
            "manifest scope contains a duplicate token");
  return result;
}

CapabilityRequest
translate_manifest_request(const manifest::CapabilityRequest &request) {
  CapabilityRequest result{
      .capability = {CapabilityId(request.capability), 1},
      .scope = NoScope{},
      .required = request.required,
  };
  auto scope = std::string_view(request.canonical_scope);
  if (request.capability == "storage.private") {
    constexpr std::string_view simple_prefix = "{\"quotaBytes\":";
    constexpr std::string_view bounded_prefix = "{\"itemBytes\":";
    constexpr std::string_view separator = ",\"quotaBytes\":";
    require(scope.ends_with("}"), "storage scope has an unregistered shape");
    scope.remove_suffix(1);
    std::uint64_t item = 0;
    std::uint64_t total = 0;
    if (scope.starts_with(simple_prefix)) {
      scope.remove_prefix(simple_prefix.size());
      total = parse_unsigned(scope);
      item = std::min<std::uint64_t>(total, 4096);
    } else {
      require(scope.starts_with(bounded_prefix),
              "storage scope has an unregistered shape");
      scope.remove_prefix(bounded_prefix.size());
      const auto split = scope.find(separator);
      require(split != std::string_view::npos,
              "storage scope has an unregistered shape");
      item = parse_unsigned(scope.substr(0, split));
      total = parse_unsigned(scope.substr(split + separator.size()));
    }
    require(item > 0 && total >= item, "storage scope has invalid bounds");
    result.scope = QuotaScope{.total_bytes = total, .item_bytes = item};
  } else if (request.capability == "notifications.send") {
    result.scope = token_scope(parse_token_array(scope, "{\"categories\":["));
  } else if (request.capability == "audio.play-cue") {
    result.scope = token_scope(parse_token_array(scope, "{\"cues\":["));
  } else {
    throw std::runtime_error(
        "manifest requests an unregistered built-in capability");
  }
  const auto *definition = find_capability(result.capability);
  require(definition != nullptr && valid_scope(*definition, result.scope),
          "manifest scope does not match capability version");
  return result;
}

} // namespace

std::span<const CapabilityDefinition> capability_registry() {
  return kRegistry;
}

const CapabilityDefinition *find_capability(const CapabilityKey &key) {
  const auto found = std::find_if(
      kRegistry.begin(), kRegistry.end(),
      [&key](const auto &definition) { return definition.key == key; });
  return found == kRegistry.end() ? nullptr : &*found;
}

const CapabilityDefinition *find_operation(OperationId operation) {
  const auto found = std::find_if(kRegistry.begin(), kRegistry.end(),
                                  [operation](const auto &definition) {
                                    return operation_in(definition, operation);
                                  });
  return found == kRegistry.end() ? nullptr : &*found;
}

bool valid_scope(const CapabilityDefinition &definition, const Scope &scope) {
  if (scope.index() != static_cast<std::size_t>(definition.scope_kind))
    return false;
  if (const auto *quota = std::get_if<QuotaScope>(&scope)) {
    return quota->item_bytes > 0 && quota->total_bytes >= quota->item_bytes &&
           quota->total_bytes <= (1ULL << 30);
  }
  if (const auto *tokens = std::get_if<TokenScope>(&scope)) {
    return tokens->tokens.size() > 0 &&
           std::all_of(
               tokens->tokens.values().begin(), tokens->tokens.values().end(),
               [](const ScopeToken &token) { return token.size() > 0; });
  }
  if (const auto *resources = std::get_if<ResourceScope>(&scope)) {
    if (resources->resources.size() == 0 || resources->operations.size() == 0)
      return false;
    return std::all_of(resources->resources.values().begin(),
                       resources->resources.values().end(),
                       [](std::uint32_t resource) { return resource > 0; }) &&
           std::all_of(resources->operations.values().begin(),
                       resources->operations.values().end(),
                       [&definition](OperationId operation) {
                         return operation_in(definition, operation);
                       });
  }
  if (const auto *http = std::get_if<HttpScope>(&scope)) {
    if (http->schemes.size() == 0 || http->hosts.size() == 0 ||
        http->methods.size() == 0 || http->allow_unix_socket)
      return false;
    return std::all_of(
               http->schemes.values().begin(), http->schemes.values().end(),
               [](const ScopeToken &scheme) {
                 return scheme.view() == "https" || scheme.view() == "http";
               }) &&
           std::all_of(
               http->hosts.values().begin(), http->hosts.values().end(),
               [](const ScopeToken &host) { return host.size() > 0; }) &&
           std::all_of(
               http->methods.values().begin(), http->methods.values().end(),
               [](const ScopeToken &method) { return method.size() > 0; }) &&
           std::all_of(http->ports.values().begin(), http->ports.values().end(),
                       [](std::uint16_t port) { return port > 0; });
  }
  return std::holds_alternative<NoScope>(scope);
}

ScopeRelation compare_scope(const Scope &candidate, const Scope &baseline) {
  if (candidate.index() != baseline.index())
    return ScopeRelation::incomparable;
  if (std::holds_alternative<NoScope>(candidate))
    return ScopeRelation::equal;
  if (const auto *left = std::get_if<QuotaScope>(&candidate)) {
    const auto &right = std::get<QuotaScope>(baseline);
    const bool narrower = left->total_bytes <= right.total_bytes &&
                          left->item_bytes <= right.item_bytes;
    const bool expanded = right.total_bytes <= left->total_bytes &&
                          right.item_bytes <= left->item_bytes;
    if (narrower && expanded)
      return ScopeRelation::equal;
    if (narrower)
      return ScopeRelation::narrower;
    if (expanded)
      return ScopeRelation::expanded;
    return ScopeRelation::incomparable;
  }
  if (const auto *left = std::get_if<TokenScope>(&candidate)) {
    return compare_sets(left->tokens, std::get<TokenScope>(baseline).tokens);
  }
  if (const auto *left = std::get_if<ResourceScope>(&candidate)) {
    const auto &right = std::get<ResourceScope>(baseline);
    return combine(compare_sets(left->resources, right.resources),
                   compare_sets(left->operations, right.operations));
  }
  const auto &left = std::get<HttpScope>(candidate);
  const auto &right = std::get<HttpScope>(baseline);
  auto relation = compare_sets(left.schemes, right.schemes);
  relation = combine(relation, compare_sets(left.hosts, right.hosts));
  relation = combine(relation, compare_sets(left.methods, right.methods));
  relation = combine(relation, compare_sets(left.ports, right.ports));
  const auto compare_flag = [](bool candidate_flag, bool baseline_flag) {
    if (candidate_flag == baseline_flag)
      return ScopeRelation::equal;
    return candidate_flag ? ScopeRelation::expanded : ScopeRelation::narrower;
  };
  relation = combine(relation,
                     compare_flag(left.allow_redirects, right.allow_redirects));
  relation = combine(relation,
                     compare_flag(left.allow_loopback, right.allow_loopback));
  return combine(relation,
                 compare_flag(left.allow_unix_socket, right.allow_unix_socket));
}

std::string canonical_scope(const Scope &scope) {
  std::string output;
  append_u8(output, static_cast<std::uint8_t>(scope.index()));
  if (const auto *quota = std::get_if<QuotaScope>(&scope)) {
    append_u64(output, quota->total_bytes);
    append_u64(output, quota->item_bytes);
  } else if (const auto *tokens = std::get_if<TokenScope>(&scope)) {
    append_tokens(output, tokens->tokens);
  } else if (const auto *resources = std::get_if<ResourceScope>(&scope)) {
    append_u8(output, static_cast<std::uint8_t>(resources->resources.size()));
    for (auto resource : resources->resources.values())
      append_u32(output, resource);
    append_u8(output, static_cast<std::uint8_t>(resources->operations.size()));
    for (auto operation : resources->operations.values())
      append_u16(output, static_cast<std::uint16_t>(operation));
  } else if (const auto *http = std::get_if<HttpScope>(&scope)) {
    append_tokens(output, http->schemes);
    append_tokens(output, http->hosts);
    append_tokens(output, http->methods);
    append_u8(output, static_cast<std::uint8_t>(http->ports.size()));
    for (auto port : http->ports.values())
      append_u16(output, port);
    append_u8(output, http->allow_redirects ? 1 : 0);
    append_u8(output, http->allow_loopback ? 1 : 0);
    append_u8(output, http->allow_unix_socket ? 1 : 0);
  }
  return output;
}

Scope scope_from_canonical(const CapabilityKey &capability,
                           std::string_view canonical) {
  const auto *definition = find_capability(capability);
  require(canonical.size() <= kMaximumCanonicalScopeBytes &&
              definition != nullptr && !canonical.empty(),
          "canonical scope names an unknown capability");
  std::size_t offset = 0;
  const auto take_u8 = [&] {
    require(offset < canonical.size(), "canonical scope is truncated");
    return static_cast<std::uint8_t>(canonical[offset++]);
  };
  const auto take_u16 = [&] {
    const auto high = take_u8();
    return static_cast<std::uint16_t>(high << 8 | take_u8());
  };
  const auto take_u64 = [&] {
    std::uint64_t value = 0;
    for (int index = 0; index < 8; ++index)
      value = value << 8 | take_u8();
    return value;
  };
  require(take_u8() == static_cast<std::uint8_t>(definition->scope_kind),
          "canonical scope kind does not match capability");
  Scope restored;
  if (definition->scope_kind == ScopeKind::none) {
    restored = NoScope{};
  } else if (definition->scope_kind == ScopeKind::quota) {
    restored = QuotaScope{.total_bytes = take_u64(),
                          .item_bytes = take_u64()};
  } else if (definition->scope_kind == ScopeKind::tokens) {
    TokenScope tokens;
    const auto count = take_u8();
    for (std::uint8_t index = 0; index < count; ++index) {
      const auto size = take_u16();
      require(size <= canonical.size() - std::min(offset, canonical.size()),
              "canonical scope token is truncated");
      require(tokens.tokens.insert(ScopeToken(canonical.substr(offset, size))),
              "canonical scope token is duplicated");
      offset += size;
    }
    restored = std::move(tokens);
  } else {
    throw std::runtime_error("registered scope kind has no durable codec");
  }
  require(offset == canonical.size() && valid_scope(*definition, restored) &&
              canonical_scope(restored) == canonical,
          "scope encoding is not canonical for capability");
  return restored;
}

void validate_requests(const RequestSet &requests) {
  FixedSet<CapabilityKey, 64> seen;
  for (const auto &request : requests.values()) {
    require(canonical_id(request.capability.id.view()) &&
                request.capability.version > 0,
            "invalid capability key");
    require(seen.insert(request.capability), "duplicate capability request");
    const auto *definition = find_capability(request.capability);
    require(definition != nullptr, "unknown capability request");
    require(valid_scope(*definition, request.scope),
            "invalid capability scope");
  }
}

void validate_grants(const GrantSet &grants, const RequestSet &requests) {
  validate_grants(grants, &requests);
}

RequestSet requests_from_manifest(const manifest::ManifestV2 &manifest) {
  RequestSet result;
  for (const auto &request : manifest.requests) {
    if (request.definition_generation > 0 && !request.definition_digest.empty())
      continue;
    result.push_back(translate_manifest_request(request));
  }
  validate_requests(result);
  return result;
}

std::string policy_request_fingerprint(const RequestSet &input) {
  validate_requests(input);
  std::array<const CapabilityRequest *, 64> sorted{};
  for (std::size_t index = 0; index < input.size(); ++index)
    sorted[index] = &input[index];
  std::sort(sorted.begin(), sorted.begin() + input.size(),
            [](auto left, auto right) {
              return left->capability < right->capability;
            });
  std::string bytes = domain("OMARCHY-PLUGIN-POLICY-REQUESTS-V1\0");
  append_u16(bytes, static_cast<std::uint16_t>(input.size()));
  for (std::size_t index = 0; index < input.size(); ++index) {
    const auto &request = *sorted[index];
    append_text(bytes, request.capability.id.view());
    append_u16(bytes, request.capability.version);
    append_u8(bytes, request.required ? 1 : 0);
    append_text(bytes, canonical_scope(request.scope));
  }
  return fingerprint(std::move(bytes));
}

void validate_decision(const UserDecisionRecord &decision) {
  require(decision.sequence > 0 && canonical_id(decision.plugin.view()) &&
              canonical_digest(decision.revision) &&
              canonical_digest(decision.source_request_fingerprint) &&
              canonical_digest(decision.policy_request_fingerprint),
          "invalid user decision identity");
  require(static_cast<std::uint8_t>(decision.decision) <=
                  static_cast<std::uint8_t>(UserDecision::deny) &&
              static_cast<std::uint8_t>(decision.actor) <=
                  static_cast<std::uint8_t>(DecisionActor::reviewed_policy) &&
              decision.decided_wall_seconds > 0,
          "invalid user decision enumeration");
  const auto *definition = find_capability(decision.capability);
  require(definition != nullptr &&
              valid_scope(*definition, decision.requested_scope),
          "invalid requested decision scope");
  require(valid_scope(*definition, decision.decided_scope),
          "invalid decided scope");
  if (decision.decision == UserDecision::grant) {
    const auto relation =
        compare_scope(decision.decided_scope, decision.requested_scope);
    require(relation == ScopeRelation::equal ||
                relation == ScopeRelation::narrower,
            "user decision expands requested scope");
  } else {
    require(compare_scope(decision.decided_scope, decision.requested_scope) ==
                ScopeRelation::equal,
            "denial must preserve the requested scope");
  }
}

std::string grant_fingerprint(const PluginId &plugin, const Digest &revision,
                              const Digest &policy_fingerprint,
                              const GrantSet &grants) {
  require(canonical_id(plugin.view()) && canonical_digest(revision) &&
              canonical_digest(policy_fingerprint),
          "invalid grant fingerprint identity");
  std::array<const GrantRecord *, 64> sorted{};
  validate_grants(grants, nullptr);
  for (std::size_t index = 0; index < grants.size(); ++index) {
    sorted[index] = &grants[index];
  }
  std::sort(sorted.begin(), sorted.begin() + grants.size(),
            [](auto left, auto right) {
              return left->capability < right->capability;
            });
  std::string bytes = domain("OMARCHY-PLUGIN-GRANTS-V1\0");
  append_text(bytes, plugin.view());
  append_text(bytes, revision.view());
  append_text(bytes, policy_fingerprint.view());
  append_u16(bytes, static_cast<std::uint16_t>(grants.size()));
  for (std::size_t index = 0; index < grants.size(); ++index) {
    const auto &grant = *sorted[index];
    append_text(bytes, grant.capability.id.view());
    append_u16(bytes, grant.capability.version);
    append_u8(bytes, static_cast<std::uint8_t>(grant.state));
    append_u64(bytes, grant.epoch);
    append_text(bytes, canonical_scope(grant.scope));
  }
  return fingerprint(std::move(bytes));
}

DeltaSet compute_update_delta(const RequestSet &old_requests,
                              const GrantSet &old_grants,
                              const RequestSet &new_requests) {
  validate_requests(old_requests);
  validate_requests(new_requests);
  validate_grants(old_grants, &old_requests);
  DeltaSet result;
  for (const auto &next : new_requests.values()) {
    PermissionDelta delta{.capability = next.capability,
                          .kind = DeltaKind::unchanged,
                          .inherited_grant = std::nullopt};
    const auto *previous = request_for(old_requests, next.capability);
    const auto *grant = grant_for(old_grants, next.capability);
    if (previous == nullptr) {
      delta.kind = DeltaKind::added;
    } else if (previous->required != next.required) {
      delta.kind = DeltaKind::requirement_changed;
    } else {
      const auto relation = compare_scope(next.scope, previous->scope);
      delta.kind = relation == ScopeRelation::equal      ? DeltaKind::unchanged
                   : relation == ScopeRelation::narrower ? DeltaKind::narrowed
                   : relation == ScopeRelation::expanded
                       ? DeltaKind::expanded
                       : DeltaKind::incomparable;
      if (grant != nullptr && delta.kind == DeltaKind::unchanged) {
        delta.inherited_grant = *grant;
      } else if (grant != nullptr && delta.kind == DeltaKind::narrowed) {
        if (grant->state != GrantState::granted) {
          delta.inherited_grant = *grant;
        } else {
          const auto within_grant = compare_scope(next.scope, grant->scope);
          if (within_grant == ScopeRelation::equal ||
              within_grant == ScopeRelation::narrower) {
            delta.inherited_grant = *grant;
            delta.inherited_grant->scope = next.scope;
          }
        }
      }
    }
    result.push_back(std::move(delta));
  }
  for (const auto &previous : old_requests.values()) {
    if (request_for(new_requests, previous.capability) == nullptr) {
      result.push_back({.capability = previous.capability,
                        .kind = DeltaKind::removed,
                        .inherited_grant = std::nullopt});
    }
  }
  return result;
}

PermissionAuthority::PermissionAuthority(ActivationBinding binding,
                                         RequestSet requests, GrantSet grants)
    : binding_(std::move(binding)), requests_(std::move(requests)),
      grants_(std::move(grants)) {
  require(canonical_id(binding_.plugin.view()) &&
              canonical_digest(binding_.revision) &&
              canonical_digest(binding_.policy_fingerprint) &&
              binding_.generation > 0,
          "invalid activation binding");
  validate_requests(requests_);
  validate_grants(grants_, &requests_);
  require(binding_.policy_fingerprint ==
              Digest(policy_request_fingerprint(requests_)),
          "activation policy fingerprint mismatch");
}

PermissionAuthority::PermissionAuthority(ActivationBinding binding,
                                         RequestSet requests, GrantSet grants,
                                         ValidatedCombinedPolicy)
    : binding_(std::move(binding)), requests_(std::move(requests)),
      grants_(std::move(grants)) {
  require(canonical_id(binding_.plugin.view()) &&
              canonical_digest(binding_.revision) &&
              canonical_digest(binding_.policy_fingerprint) &&
              binding_.generation > 0,
          "invalid activation binding");
  validate_requests(requests_);
  validate_grants(grants_, &requests_);
}

GrantDecision PermissionAuthority::authorize(OperationId operation,
                                             const Scope &demand,
                                             const ActivationBinding &channel,
                                             std::uint64_t now_monotonic_ns,
                                             GestureProof *gesture) const {
  const auto *definition = find_operation(operation);
  if (definition == nullptr)
    return {.code = GrantDecisionCode::unknown_operation,
            .capability = {},
            .grant_epoch = 0};
  GrantDecision result{.code = GrantDecisionCode::ungranted,
                       .capability = definition->key};
  if (channel != binding_) {
    result.code = GrantDecisionCode::activation_mismatch;
    return result;
  }
  const auto *request = request_for(requests_, definition->key);
  if (request == nullptr) {
    result.code = GrantDecisionCode::capability_undeclared;
    return result;
  }
  const auto *grant = grant_for(grants_, definition->key);
  if (grant == nullptr)
    return result;
  result.grant_epoch = grant->epoch;
  if (grant->state == GrantState::denied) {
    result.code = GrantDecisionCode::explicitly_denied;
    return result;
  }
  if (grant->state == GrantState::revoked) {
    result.code = GrantDecisionCode::revoked;
    return result;
  }
  if (!valid_scope(*definition, demand) ||
      !demand_matches_operation(demand, operation)) {
    result.code = GrantDecisionCode::outside_scope;
    return result;
  }
  const auto relation = compare_scope(demand, grant->scope);
  if (relation != ScopeRelation::equal && relation != ScopeRelation::narrower) {
    result.code = GrantDecisionCode::outside_scope;
    return result;
  }
  if (definition->gesture == GestureRule::fresh_single_use) {
    if (gesture == nullptr) {
      result.code = GrantDecisionCode::gesture_missing;
      return result;
    }
    if (gesture->consumed) {
      result.code = GrantDecisionCode::gesture_used;
      return result;
    }
    if (now_monotonic_ns >= gesture->expires_monotonic_ns) {
      result.code = GrantDecisionCode::gesture_expired;
      return result;
    }
    if (!nonzero(gesture->id.bytes) || gesture->plugin != binding_.plugin ||
        gesture->generation != binding_.generation ||
        gesture->operation != operation || gesture->surface == 0) {
      result.code = GrantDecisionCode::gesture_wrong_binding;
      return result;
    }
    gesture->consumed = true;
  }
  result.code = GrantDecisionCode::allowed;
  return result;
}

std::uint64_t PermissionAuthority::revoke(const CapabilityKey &capability) {
  auto *grant = grant_for(grants_, capability);
  require(grant != nullptr, "cannot revoke missing grant");
  require(grant->epoch < std::numeric_limits<std::uint64_t>::max(),
          "grant epoch exhausted");
  ++grant->epoch;
  grant->state = GrantState::revoked;
  return grant->epoch;
}

bool valid_handle_record(const HandleRecord &record) {
  const auto *definition = find_operation(record.operation);
  return nonzero(record.id.bytes) && canonical_id(record.plugin.view()) &&
         canonical_digest(record.revision) &&
         canonical_digest(record.policy_fingerprint) && record.generation > 0 &&
         definition != nullptr && valid_scope(*definition, record.scope) &&
         demand_matches_operation(record.scope, record.operation) &&
         record.grant_epoch > 0 && record.expires_monotonic_ns > 0;
}

bool valid_audit_producer(AuditProducer producer) {
  return static_cast<std::uint8_t>(producer) <=
         static_cast<std::uint8_t>(AuditProducer::surface_host);
}

void validate_audit_draft(const AuditDraft &draft) {
  require(canonical_id(draft.plugin.view()) &&
              canonical_digest(draft.revision) && draft.generation > 0,
          "invalid audit identity");
  require(static_cast<std::uint8_t>(draft.event) <=
                  static_cast<std::uint8_t>(AuditEvent::operation_completed) &&
              static_cast<std::uint8_t>(draft.outcome) <=
                  static_cast<std::uint8_t>(AuditOutcome::failed) &&
              static_cast<std::uint8_t>(draft.decision) <=
                  static_cast<std::uint8_t>(GrantDecisionCode::gesture_used),
          "invalid audit enumeration");
  const CapabilityDefinition *operation_definition = nullptr;
  if (draft.operation.has_value()) {
    operation_definition = find_operation(*draft.operation);
    require(operation_definition != nullptr, "unknown audit operation");
  }
  if (draft.capability.has_value()) {
    require(find_capability(*draft.capability) != nullptr,
            "unknown audit capability");
  }
  if (operation_definition != nullptr && draft.capability.has_value()) {
    require(operation_definition->key == *draft.capability,
            "audit operation and capability disagree");
  }
  if (draft.dynamic_operation.has_value()) {
    const auto &dynamic = *draft.dynamic_operation;
    require(!draft.operation.has_value() && !draft.capability.has_value() &&
                canonical_id(dynamic.capability.view()) &&
                dynamic.definition_generation > 0 &&
                canonical_digest(dynamic.definition_digest) &&
                canonical_id(dynamic.operation.view()) &&
                dynamic.grant_epoch > 0,
            "invalid dynamic audit identity");
  }
  if (draft.dynamic_attempt.has_value()) {
    require(!draft.operation.has_value() && !draft.capability.has_value() &&
                !draft.dynamic_operation.has_value() &&
                canonical_digest(draft.dynamic_attempt->opaque_digest),
            "invalid dynamic audit attempt identity");
  }
  switch (draft.event) {
  case AuditEvent::grant_changed:
    require(draft.capability.has_value() && !draft.operation.has_value() &&
                !draft.dynamic_operation.has_value() &&
                !draft.dynamic_attempt.has_value(),
            "grant audit event has invalid fields");
    break;
  case AuditEvent::capability_revoked:
    require((((draft.capability.has_value() && !draft.operation.has_value()) !=
              draft.dynamic_operation.has_value())) &&
                !draft.dynamic_attempt.has_value() && draft.correlation == 0,
            "revocation audit event has invalid fields");
    break;
  case AuditEvent::operation_decided:
  case AuditEvent::operation_completed:
  case AuditEvent::handle_issued:
  case AuditEvent::handle_denied:
    require(
        static_cast<unsigned>(draft.operation.has_value() &&
                              draft.capability.has_value()) +
                    static_cast<unsigned>(draft.dynamic_operation.has_value()) +
                    static_cast<unsigned>(draft.dynamic_attempt.has_value()) ==
                1 &&
            draft.correlation > 0,
        "operation audit event has invalid fields");
    break;
  case AuditEvent::worker_started:
  case AuditEvent::worker_health:
  case AuditEvent::worker_crashed:
  case AuditEvent::worker_stopped:
  case AuditEvent::worker_disabled:
    require(!draft.operation.has_value() && !draft.capability.has_value() &&
                !draft.dynamic_operation.has_value() &&
                !draft.dynamic_attempt.has_value() && draft.correlation == 0,
            "worker audit event has invalid fields");
    break;
  }
  FixedSet<AuditMetric, 8> metrics;
  for (const auto &metadata : draft.metadata.values()) {
    require(
        static_cast<std::uint8_t>(metadata.metric) <=
                static_cast<std::uint8_t>(AuditMetric::retry_after_seconds) &&
            metadata.value >= 0,
        "invalid audit metric");
    require(metrics.insert(metadata.metric), "duplicate audit metric");
  }
}

std::string audit_record_fingerprint(const AuditRecord &record) {
  require(record.sequence > 0 && canonical_id(record.plugin.view()) &&
              canonical_digest(record.revision),
          "invalid audit record identity");
  require(valid_audit_producer(record.producer), "invalid audit producer");
  validate_audit_draft(record);
  std::string bytes = domain("OMARCHY-PLUGIN-AUDIT-V1\0");
  append_u64(bytes, record.sequence);
  append_u64(bytes, record.wall_seconds);
  append_u64(bytes, record.monotonic_ns);
  append_u8(bytes, static_cast<std::uint8_t>(record.producer));
  append_u8(bytes, static_cast<std::uint8_t>(record.event));
  append_u8(bytes, static_cast<std::uint8_t>(record.outcome));
  append_text(bytes, record.plugin.view());
  append_text(bytes, record.revision.view());
  append_u64(bytes, record.generation);
  append_u64(bytes, record.correlation);
  append_u16(bytes, record.operation.has_value()
                        ? static_cast<std::uint16_t>(*record.operation)
                        : 0);
  if (record.capability.has_value()) {
    append_text(bytes, record.capability->id.view());
    append_u16(bytes, record.capability->version);
  } else {
    append_text(bytes, "-");
    append_u16(bytes, 0);
  }
  if (record.dynamic_operation.has_value()) {
    append_text(bytes, record.dynamic_operation->capability.view());
    append_u32(bytes, record.dynamic_operation->definition_generation);
    append_text(bytes, record.dynamic_operation->definition_digest.view());
    append_text(bytes, record.dynamic_operation->operation.view());
    append_u64(bytes, record.dynamic_operation->grant_epoch);
  }
  if (record.dynamic_attempt.has_value())
    append_text(bytes, record.dynamic_attempt->opaque_digest.view());
  append_u8(bytes, static_cast<std::uint8_t>(record.decision));
  append_u8(bytes, static_cast<std::uint8_t>(record.metadata.size()));
  for (std::uint8_t value = 0;
       value <= static_cast<std::uint8_t>(AuditMetric::retry_after_seconds);
       ++value) {
    const auto metric = static_cast<AuditMetric>(value);
    const auto found = std::find_if(
        record.metadata.values().begin(), record.metadata.values().end(),
        [metric](const AuditMetadata &item) { return item.metric == metric; });
    if (found == record.metadata.values().end())
      continue;
    append_u8(bytes, value);
    append_u64(bytes, std::bit_cast<std::uint64_t>(found->value));
  }
  return fingerprint(std::move(bytes));
}

} // namespace omarchy::plugins::permissions
