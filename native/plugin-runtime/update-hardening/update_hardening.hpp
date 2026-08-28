#pragma once

#include "lifecycle.hpp"

#include <filesystem>
#include <optional>
#include <string>
#include <string_view>

namespace omarchy::plugins::updates {

namespace lifecycle = omarchy::plugins::lifecycle;
namespace revision = omarchy::plugins::store;

enum class CompatibilityMode {
  legacy_v1_unsafe_unmigrated,
  secure_v2_candidate,
};

enum class Disposition {
  rejected,
  unsafe_unmigrated,
  fresh_install,
  exact_reinstall,
  staged_upgrade,
  staged_downgrade,
  staged_rebuild,
};

enum class ErrorCode {
  ok,
  unsafe_legacy_schema,
  validation_failed,
  recovery_failed,
  identity_change,
  downgrade_requires_approval,
  rebuild_requires_approval,
  unorderable_version,
  stale_approval,
  lifecycle_failed,
};

enum class ApprovalKind { downgrade, same_version_rebuild };

struct Approval {
  ApprovalKind kind = ApprovalKind::downgrade;
  std::string active_revision_sha256;
  std::string candidate_revision_sha256;
};

struct Result {
  ErrorCode code = ErrorCode::ok;
  CompatibilityMode compatibility = CompatibilityMode::secure_v2_candidate;
  Disposition disposition = Disposition::rejected;
  std::string detail;
  std::optional<lifecycle::StageOutcome> stage;

  [[nodiscard]] bool ok() const { return code == ErrorCode::ok; }
  [[nodiscard]] bool granular_permissions_eligible() const {
    return ok() && compatibility == CompatibilityMode::secure_v2_candidate;
  }
  [[nodiscard]] bool sandbox_eligible() const {
    return granular_permissions_eligible();
  }
};

class UpdateManager {
public:
  UpdateManager(std::filesystem::path revision_store,
                std::filesystem::path grant_store);

  [[nodiscard]] Result
  stage(const std::filesystem::path &source_root, std::string_view directory,
        std::string_view pinned_tree_sha256,
        const std::optional<Approval> &approval = std::nullopt,
        revision::FaultPoint fault = revision::FaultPoint::none);

  [[nodiscard]] lifecycle::LifecycleManager &lifecycle() { return lifecycle_; }

private:
  lifecycle::LifecycleManager lifecycle_;
};

} // namespace omarchy::plugins::updates
