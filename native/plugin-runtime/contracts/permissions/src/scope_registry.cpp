#include "permission_contract.hpp"

#include "canonical_identity_encoding.hpp"
#include "manifest_contract.hpp"

#include <charconv>
#include <tuple>

namespace omarchy::plugins::permissions {
namespace {

using detail::append_text;
using detail::append_u16;
using detail::append_u32;
using detail::append_u64;
using detail::append_u8;
using detail::canonical_id;
using detail::require;

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

std::string_view operation_name(OperationId operation) noexcept {
  switch (operation) {
  case OperationId::storage_read:
    return "read";
  case OperationId::storage_write:
    return "write";
  case OperationId::storage_remove:
    return "remove";
  case OperationId::notification_send:
    return "send";
  case OperationId::audio_play_cue:
    return "play";
  }
  return {};
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

} // namespace omarchy::plugins::permissions
