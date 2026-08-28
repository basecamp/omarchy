#include "update_hardening.hpp"

#include "discovery.hpp"
#include "manifest_contract.hpp"

#include <array>
#include <charconv>
#include <limits>
#include <string_view>
#include <utility>

namespace omarchy::plugins::updates {
namespace {

struct NumericVersion {
  std::array<std::uint64_t, 3> parts{};
  auto operator<=>(const NumericVersion &) const = default;
};

std::optional<NumericVersion> parse_version(std::string_view value) {
  NumericVersion result;
  for (std::size_t index = 0; index < result.parts.size(); ++index) {
    const auto separator = value.find('.');
    const auto component = value.substr(0, separator);
    if (component.empty() || (component.size() > 1 && component.front() == '0'))
      return std::nullopt;
    const auto [end, error] =
        std::from_chars(component.data(), component.data() + component.size(),
                        result.parts[index]);
    if (error != std::errc{} || end != component.data() + component.size())
      return std::nullopt;
    if (index + 1 == result.parts.size()) {
      if (separator != std::string_view::npos)
        return std::nullopt;
    } else {
      if (separator == std::string_view::npos)
        return std::nullopt;
      value.remove_prefix(separator + 1);
    }
  }
  return result;
}

Result failure(
    ErrorCode code, std::string detail,
    CompatibilityMode compatibility = CompatibilityMode::secure_v2_candidate) {
  return {.code = code,
          .compatibility = compatibility,
          .disposition = code == ErrorCode::unsafe_legacy_schema
                             ? Disposition::unsafe_unmigrated
                             : Disposition::rejected,
          .detail = std::move(detail),
          .stage = std::nullopt};
}

bool approved(const std::optional<Approval> &approval, ApprovalKind kind,
              std::string_view active, std::string_view candidate) {
  return approval && approval->kind == kind &&
         approval->active_revision_sha256 == active &&
         approval->candidate_revision_sha256 == candidate;
}

} // namespace

UpdateManager::UpdateManager(std::filesystem::path revision_store,
                             std::filesystem::path grant_store)
    : lifecycle_(std::move(revision_store), std::move(grant_store)) {}

Result UpdateManager::stage(const std::filesystem::path &source_root,
                            std::string_view directory,
                            std::string_view pinned_tree_sha256,
                            const std::optional<Approval> &approval,
                            revision::FaultPoint fault) {
  const auto recovered = lifecycle_.recover();
  if (!recovered.ok())
    return failure(ErrorCode::recovery_failed, recovered.detail);

  const std::array pins{discovery::IdentityPin{
      std::string(directory), std::string(pinned_tree_sha256)}};
  const auto report = discovery::discover(source_root, pins, {true});
  if (report.plugins.size() != 1) {
    for (const auto &diagnostic : report.diagnostics) {
      if (diagnostic.code == discovery::DiagnosticCode::legacy_v1_unsafe) {
        return failure(
            ErrorCode::unsafe_legacy_schema,
            "schema v1 is unsafe, unmigrated, indivisible host code; it has no "
            "granular grants, sandbox claim, or secure update path",
            CompatibilityMode::legacy_v1_unsafe_unmigrated);
      }
    }
    return failure(ErrorCode::validation_failed,
                   "candidate failed pinned schema-v2 discovery");
  }
  const auto &candidate = report.plugins.front();
  revision::Result current_status;
  const auto current = lifecycle_.revisions().current(&current_status);
  if (!current_status.ok())
    return failure(ErrorCode::recovery_failed, current_status.detail);
  if (!current) {
    auto staged =
        lifecycle_.stage(source_root, directory, pinned_tree_sha256, fault);
    if (!staged.result.ok())
      return failure(ErrorCode::lifecycle_failed, staged.result.detail);
    return {.code = ErrorCode::ok,
            .compatibility = CompatibilityMode::secure_v2_candidate,
            .disposition = Disposition::fresh_install,
            .detail = "pinned schema-v2 revision staged",
            .stage = std::move(staged)};
  }
  if (current->active.plugin_id != candidate.manifest.id)
    return failure(ErrorCode::identity_change,
                   "an update cannot change the active plugin id");
  if (current->active.revision_sha256 == candidate.identity.tree_sha256) {
    lifecycle::StageOutcome unchanged;
    unchanged.result = {};
    unchanged.binding = permissions::ActivationBinding{
        .plugin = permissions::PluginId(current->active.plugin_id),
        .revision = permissions::Digest(current->active.revision_sha256),
        .policy_fingerprint =
            permissions::Digest(current->active.policy_sha256),
        .generation = current->active.generation};
    unchanged.already_active = true;
    return {.code = ErrorCode::ok,
            .compatibility = CompatibilityMode::secure_v2_candidate,
            .disposition = Disposition::exact_reinstall,
            .detail = "exact pinned revision is already active",
            .stage = std::move(unchanged)};
  }

  const auto active_path =
      lifecycle_.revisions().revision_path(current->active.revision_sha256);
  const std::array active_pins{discovery::IdentityPin{
      active_path.filename().string(), current->active.revision_sha256}};
  const auto active_report =
      discovery::discover(active_path.parent_path(), active_pins, {true});
  if (active_report.plugins.size() != 1 ||
      active_report.plugins.front().manifest.id != current->active.plugin_id)
    return failure(ErrorCode::recovery_failed,
                   "active immutable revision failed pinned rediscovery");
  const auto &active_manifest = active_report.plugins.front().manifest;
  if (active_manifest.id != candidate.manifest.id)
    return failure(ErrorCode::identity_change,
                   "stored manifest identity disagrees with update candidate");
  const auto active_version = parse_version(active_manifest.version);
  const auto candidate_version = parse_version(candidate.manifest.version);
  if (!active_version || !candidate_version)
    return failure(
        ErrorCode::unorderable_version,
        "secure automatic updates require a numeric major.minor.patch version");

  Disposition disposition = Disposition::staged_upgrade;
  if (*candidate_version < *active_version) {
    if (!approved(approval, ApprovalKind::downgrade,
                  current->active.revision_sha256,
                  candidate.identity.tree_sha256))
      return failure(
          approval ? ErrorCode::stale_approval
                   : ErrorCode::downgrade_requires_approval,
          "downgrade requires approval bound to both exact revisions");
    disposition = Disposition::staged_downgrade;
  } else if (*candidate_version == *active_version) {
    if (!approved(approval, ApprovalKind::same_version_rebuild,
                  current->active.revision_sha256,
                  candidate.identity.tree_sha256))
      return failure(
          approval ? ErrorCode::stale_approval
                   : ErrorCode::rebuild_requires_approval,
          "same-version content change requires exact-revision approval");
    disposition = Disposition::staged_rebuild;
  }

  auto staged =
      lifecycle_.stage(source_root, directory, pinned_tree_sha256, fault);
  if (!staged.result.ok())
    return failure(ErrorCode::lifecycle_failed, staged.result.detail);
  return {.code = ErrorCode::ok,
          .compatibility = CompatibilityMode::secure_v2_candidate,
          .disposition = disposition,
          .detail =
              "candidate remains staged until lifecycle approval and enable",
          .stage = std::move(staged)};
}

} // namespace omarchy::plugins::updates
