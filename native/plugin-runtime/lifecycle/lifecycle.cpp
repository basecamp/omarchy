#include "lifecycle.hpp"

#include <algorithm>
#include <charconv>
#include <limits>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

namespace omarchy::plugins::lifecycle {
namespace {

using discovery::DiagnosticCode;

Result failure(ErrorCode code, std::string detail) {
  return {.code = code, .detail = std::move(detail)};
}

bool valid_token_character(char value) {
  return (value >= 'a' && value <= 'z') || (value >= 'A' && value <= 'Z') ||
         (value >= '0' && value <= '9') || value == '.' || value == '_' ||
         value == '-';
}

std::uint64_t unsigned_value(std::string_view value) {
  std::uint64_t result = 0;
  const auto [end, error] =
      std::from_chars(value.data(), value.data() + value.size(), result);
  if (value.empty() || error != std::errc{} ||
      end != value.data() + value.size())
    throw std::runtime_error("manifest scope contains an invalid integer");
  return result;
}

std::vector<std::string_view> token_list(std::string_view value) {
  if (value.empty())
    throw std::runtime_error("manifest scope token list is empty");
  std::vector<std::string_view> result;
  while (!value.empty()) {
    if (value.front() != '"')
      throw std::runtime_error("manifest scope token is not a string");
    value.remove_prefix(1);
    const auto end = value.find('"');
    if (end == std::string_view::npos)
      throw std::runtime_error("manifest scope token is unterminated");
    const auto token = value.substr(0, end);
    if (token.empty() || !std::ranges::all_of(token, valid_token_character))
      throw std::runtime_error("manifest scope token is not registered text");
    result.push_back(token);
    value.remove_prefix(end + 1);
    if (value.empty())
      break;
    if (!value.starts_with(","))
      throw std::runtime_error("manifest scope token separator is invalid");
    value.remove_prefix(1);
  }
  return result;
}

std::vector<std::string_view> token_array(std::string_view value,
                                          std::string_view prefix,
                                          std::string_view suffix) {
  if (!value.starts_with(prefix) || !value.ends_with(suffix))
    throw std::runtime_error("manifest scope has an unregistered shape");
  value.remove_prefix(prefix.size());
  value.remove_suffix(suffix.size());
  return token_list(value);
}

permission::TokenScope tokens(std::span<const std::string_view> values) {
  permission::TokenScope result;
  for (const auto value : values) {
    if (!result.tokens.insert(permission::ScopeToken(value)))
      throw std::runtime_error("manifest scope contains a duplicate token");
  }
  return result;
}

permission::ResourceScope fake_scope(std::string_view value) {
  constexpr std::string_view prefix = "{\"operations\":[";
  constexpr std::string_view separator = "],\"resourceIds\":[";
  constexpr std::string_view suffix = "]}";
  if (!value.starts_with(prefix) || !value.ends_with(suffix))
    throw std::runtime_error("fake-service scope has an unregistered shape");
  value.remove_prefix(prefix.size());
  value.remove_suffix(suffix.size());
  const auto split = value.find(separator);
  if (split == std::string_view::npos)
    throw std::runtime_error("fake-service scope is missing resource ids");
  const auto operation_bytes = value.substr(0, split);
  auto resource_bytes = value.substr(split + separator.size());
  const auto operation_names = token_list(operation_bytes);
  permission::ResourceScope result;
  for (const auto name : operation_names) {
    permission::OperationId operation{};
    if (name == "list")
      operation = permission::OperationId::fake_status_list;
    else if (name == "acknowledge")
      operation = permission::OperationId::fake_status_acknowledge;
    else
      throw std::runtime_error("fake-service operation is not registered");
    if (!result.operations.insert(operation))
      throw std::runtime_error("duplicate fake-service operation");
  }
  while (!resource_bytes.empty()) {
    const auto comma = resource_bytes.find(',');
    const auto item = resource_bytes.substr(0, comma);
    const auto number = unsigned_value(item);
    if (number == 0 || number > std::numeric_limits<std::uint32_t>::max() ||
        !result.resources.insert(static_cast<std::uint32_t>(number)))
      throw std::runtime_error("invalid or duplicate fake-service resource");
    if (comma == std::string_view::npos)
      break;
    resource_bytes.remove_prefix(comma + 1);
  }
  return result;
}

permission::CapabilityRequest
translate_request(const manifest::CapabilityRequest &request) {
  permission::CapabilityRequest result{
      .capability = {permission::CapabilityId(request.capability), 1},
      .scope = permission::NoScope{},
      .required = request.required,
  };
  if (request.capability == "storage.private") {
    constexpr std::string_view prefix = "{\"quotaBytes\":";
    constexpr std::string_view suffix = "}";
    if (!request.canonical_scope.starts_with(prefix) ||
        !request.canonical_scope.ends_with(suffix))
      throw std::runtime_error("storage scope has an unregistered shape");
    auto value = std::string_view(request.canonical_scope);
    value.remove_prefix(prefix.size());
    value.remove_suffix(suffix.size());
    const auto total = unsigned_value(value);
    result.scope = permission::QuotaScope{
        .total_bytes = total,
        .item_bytes = std::min<std::uint64_t>(total, 4096),
    };
  } else if (request.capability == "notifications.send") {
    const auto values =
        token_array(request.canonical_scope, "{\"categories\":[", "]}");
    result.scope = tokens(values);
  } else if (request.capability == "audio.play-cue") {
    const auto values =
        token_array(request.canonical_scope, "{\"cues\":[", "]}");
    result.scope = tokens(values);
  } else if (request.capability == "service.fake-status") {
    result.scope = fake_scope(request.canonical_scope);
  } else {
    throw std::runtime_error("manifest requests an unregistered capability");
  }
  const auto *definition = permission::find_capability(result.capability);
  if (definition == nullptr ||
      !permission::valid_scope(*definition, result.scope))
    throw std::runtime_error(
        "manifest scope does not match capability version");
  return result;
}

const grant::PluginGrants *plugin_for(const grant::StoreState &state,
                                      const permission::PluginId &plugin) {
  const auto found = std::ranges::find_if(
      state.plugins, [&](const auto &item) { return item.plugin == plugin; });
  return found == state.plugins.end() ? nullptr : &*found;
}

std::string grant_fingerprint(const grant::RevisionGrants &revision) {
  return permission::grant_fingerprint(
      revision.binding.plugin, revision.binding.revision,
      revision.binding.policy_fingerprint, revision.grants);
}

bool same_revision_binding(const revision::PolicyBinding &persisted,
                           const grant::RevisionGrants &grants,
                           bool include_generation) {
  return persisted.plugin_id == grants.binding.plugin.view() &&
         persisted.revision_sha256 == grants.binding.revision.view() &&
         persisted.source_request_sha256 ==
             grants.source_request_fingerprint.view() &&
         persisted.policy_sha256 == grants.binding.policy_fingerprint.view() &&
         (!include_generation ||
          persisted.generation == grants.binding.generation);
}

revision::PolicyBinding policy_binding(const discovery::VerifiedPlugin &plugin,
                                       const grant::RevisionGrants &grants) {
  return {.plugin_id = plugin.manifest.id,
          .revision_sha256 = plugin.identity.tree_sha256,
          .manifest_sha256 = plugin.identity.manifest_sha256,
          .source_request_sha256 = plugin.identity.request_sha256,
          .policy_sha256 =
              std::string(grants.binding.policy_fingerprint.view()),
          .grant_sha256 = grant_fingerprint(grants),
          .generation = grants.binding.generation};
}

grant::RequestBundle bundle_from(const grant::RevisionGrants &revision) {
  return grant::make_bundle(grant::kSecurePluginSchemaVersion,
                            revision.binding.plugin, revision.binding.revision,
                            revision.source_request_fingerprint,
                            revision.binding.generation, revision.requests);
}

bool required_grants_present(const grant::RevisionGrants &revision) {
  for (const auto &request : revision.requests.values()) {
    if (!request.required)
      continue;
    const auto found =
        std::ranges::find_if(revision.grants.values(), [&](const auto &item) {
          return item.capability == request.capability &&
                 item.state == permission::GrantState::granted;
        });
    if (found == revision.grants.values().end())
      return false;
  }
  return true;
}

} // namespace

permission::RequestSet
translate_requests(const manifest::ManifestV2 &manifest) {
  permission::RequestSet result;
  for (const auto &request : manifest.requests)
    result.push_back(translate_request(request));
  permission::validate_requests(result);
  return result;
}

LifecycleManager::LifecycleManager(std::filesystem::path revision_store,
                                   std::filesystem::path grant_store)
    : revisions_(std::move(revision_store), revision::Options{true}),
      grants_(std::move(grant_store)) {}

std::optional<discovery::VerifiedPlugin>
LifecycleManager::stored_plugin(const grant::RevisionGrants &revision_grants,
                                Result &result) const {
  const auto digest = std::string(revision_grants.binding.revision.view());
  const auto path = revisions_.revision_path(digest);
  const std::array pins{discovery::IdentityPin{digest, digest}};
  const auto report = discovery::discover(path.parent_path(), pins, {true});
  if (report.plugins.size() != 1 ||
      report.plugins.front().manifest.id !=
          revision_grants.binding.plugin.view() ||
      report.plugins.front().identity.request_sha256 !=
          revision_grants.source_request_fingerprint.view()) {
    result = failure(ErrorCode::binding_mismatch,
                     "stored revision no longer matches grant identity");
    return std::nullopt;
  }
  return report.plugins.front();
}

Result LifecycleManager::recover() {
  const auto revision_recovery = revisions_.recover();
  if (!revision_recovery.ok())
    return failure(ErrorCode::recovery_failed, revision_recovery.detail);
  revision::Result current_status;
  const auto current = revisions_.current(&current_status);
  if (!current_status.ok())
    return failure(ErrorCode::recovery_failed, current_status.detail);
  if (!current)
    return {};
  try {
    const auto state = grants_.read();
    const permission::PluginId plugin(current->active.plugin_id);
    const auto *persisted = plugin_for(state, plugin);
    if (persisted == nullptr)
      return failure(ErrorCode::recovery_failed,
                     "active revision has no grant-store identity");
    if (persisted->active &&
        same_revision_binding(current->active, *persisted->active, true)) {
      const auto expected = grant_fingerprint(*persisted->active);
      if (current->active.grant_sha256 == expected)
        return {};
      auto rebound = current->active;
      rebound.grant_sha256 = expected;
      const auto rebound_result = revisions_.rebind_active(rebound);
      return rebound_result.ok()
                 ? Result{}
                 : failure(ErrorCode::recovery_failed, rebound_result.detail);
    }
    if (persisted->candidate &&
        same_revision_binding(current->active, *persisted->candidate, true) &&
        current->active.grant_sha256 ==
            grant_fingerprint(*persisted->candidate)) {
      grants_.activate_candidate(persisted->candidate->binding);
      return {};
    }
    if (persisted->rollback &&
        same_revision_binding(current->active, *persisted->rollback, false) &&
        current->active.grant_sha256 ==
            grant_fingerprint(*persisted->rollback)) {
      auto binding = persisted->rollback->binding;
      binding.generation = current->active.generation;
      grants_.rollback_to(binding);
      return {};
    }
    return failure(ErrorCode::recovery_failed,
                   "active revision and grant store cannot be reconciled");
  } catch (const std::exception &error) {
    return failure(ErrorCode::recovery_failed, error.what());
  }
}

StageOutcome LifecycleManager::stage(const std::filesystem::path &source_root,
                                     std::string_view directory,
                                     std::string_view pinned_tree_sha256,
                                     revision::FaultPoint fault) {
  StageOutcome outcome;
  const auto recovered = recover();
  if (!recovered.ok()) {
    outcome.result = recovered;
    return outcome;
  }
  const std::array pins{discovery::IdentityPin{
      std::string(directory), std::string(pinned_tree_sha256)}};
  const auto report = discovery::discover(source_root, pins, {true});
  if (report.plugins.size() != 1) {
    const bool legacy =
        std::ranges::any_of(report.diagnostics, [](const auto &item) {
          return item.code == DiagnosticCode::legacy_v1_unsafe;
        });
    outcome.result = failure(
        legacy ? ErrorCode::unsafe_legacy_schema : ErrorCode::validation_failed,
        legacy ? "schema v1 remains explicitly unsafe host code"
               : "pinned source did not yield exactly one verified plugin");
    return outcome;
  }
  const auto &plugin = report.plugins.front();
  const auto staged = revisions_.stage(plugin, fault);
  if (!staged.ok()) {
    outcome.result = failure(ErrorCode::store_failed, staged.detail);
    return outcome;
  }
  try {
    std::uint64_t generation = 1;
    if (const auto current = revisions_.current()) {
      if (current->active.plugin_id != plugin.manifest.id)
        throw std::runtime_error("revision store is bound to another plugin");
      generation =
          current->active.revision_sha256 == plugin.identity.tree_sha256
              ? current->active.generation
              : current->active.generation + 1;
      if (generation == 0)
        throw std::runtime_error("activation generation is exhausted");
    }
    auto bundle =
        grant::make_bundle(grant::kSecurePluginSchemaVersion,
                           permission::PluginId(plugin.manifest.id),
                           permission::Digest(plugin.identity.tree_sha256),
                           permission::Digest(plugin.identity.request_sha256),
                           generation, translate_requests(plugin.manifest));
    const auto candidate = grants_.stage_candidate(bundle);
    outcome.binding = candidate.revision.binding;
    outcome.delta = candidate.request_delta;
    outcome.already_active = candidate.target == grant::TargetRevision::active;
    outcome.permission_review_required = std::ranges::any_of(
        candidate.request_delta.values(), [](const auto &entry) {
          return entry.kind == permission::DeltaKind::added ||
                 entry.kind == permission::DeltaKind::expanded ||
                 entry.kind == permission::DeltaKind::incomparable ||
                 entry.kind == permission::DeltaKind::requirement_changed;
        });
    outcome.result = {};
  } catch (const std::exception &error) {
    outcome.result = failure(ErrorCode::store_failed, error.what());
  }
  return outcome;
}

Result LifecycleManager::enable(const permission::PluginId &plugin,
                                revision::FaultPoint fault) {
  const auto recovered = recover();
  if (!recovered.ok())
    return recovered;
  try {
    const auto state = grants_.read();
    const auto *persisted = plugin_for(state, plugin);
    if (persisted == nullptr)
      return failure(ErrorCode::no_candidate, "plugin has no grant state");
    if (!persisted->candidate) {
      if (persisted->active)
        return {};
      return failure(ErrorCode::no_candidate, "plugin has no staged candidate");
    }
    if (!required_grants_present(*persisted->candidate))
      return failure(ErrorCode::grants_incomplete,
                     "required permissions are not granted");
    Result stored_status;
    const auto stored = stored_plugin(*persisted->candidate, stored_status);
    if (!stored)
      return stored_status;
    const auto desired = policy_binding(*stored, *persisted->candidate);
    const auto activated = revisions_.activate(desired, fault);
    const auto current = revisions_.current();
    if (!current || current->active != desired)
      return failure(ErrorCode::store_failed, activated.detail);
    grants_.activate_candidate(persisted->candidate->binding);
    return {};
  } catch (const std::exception &error) {
    return failure(ErrorCode::store_failed, error.what());
  }
}

Result LifecycleManager::rollback(revision::FaultPoint fault) {
  const auto recovered = recover();
  if (!recovered.ok())
    return recovered;
  const auto before = revisions_.current();
  const auto rolled_back = revisions_.rollback(fault);
  const auto reconciled = recover();
  const auto after = revisions_.current();
  const bool committed = before && after &&
                         after->active.generation > before->active.generation &&
                         after->active != before->active;
  if (reconciled.ok() && (rolled_back.ok() || committed))
    return {};
  return rolled_back.code == revision::ErrorCode::no_rollback
             ? failure(ErrorCode::no_rollback, rolled_back.detail)
             : failure(ErrorCode::store_failed, rolled_back.detail.empty()
                                                    ? reconciled.detail
                                                    : rolled_back.detail);
}

RevocationOutcome
LifecycleManager::revoke(const permission::PluginId &plugin,
                         const permission::CapabilityKey &capability,
                         revision::FaultPoint fault) {
  RevocationOutcome outcome;
  const auto recovered = recover();
  if (!recovered.ok()) {
    outcome.result = recovered;
    return outcome;
  }
  try {
    const auto state = grants_.read();
    const auto *persisted = plugin_for(state, plugin);
    if (persisted == nullptr || !persisted->active) {
      outcome.result = failure(ErrorCode::binding_mismatch,
                               "plugin has no active grant revision");
      return outcome;
    }
    outcome.revocation =
        grants_.revoke(bundle_from(*persisted->active), capability);
    const auto after = grants_.read();
    const auto *updated = plugin_for(after, plugin);
    if (updated == nullptr || !updated->active)
      throw std::runtime_error("revocation removed active grant state");
    const auto current = revisions_.current();
    if (!current ||
        !same_revision_binding(current->active, *updated->active, true))
      throw std::runtime_error("revocation activation binding mismatch");
    auto rebound = current->active;
    rebound.grant_sha256 = grant_fingerprint(*updated->active);
    const auto rebound_result = revisions_.rebind_active(rebound, fault);
    const auto final_state = recover();
    if (!final_state.ok())
      throw std::runtime_error(rebound_result.detail.empty()
                                   ? final_state.detail
                                   : rebound_result.detail);
    outcome.result = {};
  } catch (const std::exception &error) {
    outcome.result = failure(ErrorCode::store_failed, error.what());
  }
  return outcome;
}

Result LifecycleManager::discard(const permission::PluginId &plugin) {
  try {
    grants_.discard_candidate(plugin);
    return {};
  } catch (const std::exception &error) {
    return failure(ErrorCode::store_failed, error.what());
  }
}

} // namespace omarchy::plugins::lifecycle
