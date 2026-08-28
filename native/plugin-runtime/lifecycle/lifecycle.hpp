#pragma once

#include "discovery.hpp"
#include "grant_store.hpp"
#include "revision_store.hpp"

#include <filesystem>
#include <optional>
#include <string>
#include <string_view>

namespace omarchy::plugins::lifecycle {

namespace grant = omarchy::plugins::grants;
namespace permission = omarchy::plugins::permissions;
namespace revision = omarchy::plugins::store;

enum class ErrorCode {
  ok,
  unsafe_legacy_schema,
  validation_failed,
  store_failed,
  grants_incomplete,
  binding_mismatch,
  no_candidate,
  no_rollback,
  recovery_failed,
};

struct Result {
  ErrorCode code = ErrorCode::ok;
  std::string detail;

  [[nodiscard]] bool ok() const { return code == ErrorCode::ok; }
};

struct StageOutcome {
  Result result;
  std::optional<permission::ActivationBinding> binding;
  permission::DeltaSet delta;
  bool permission_review_required = false;
  bool already_active = false;
};

struct RevocationOutcome {
  Result result;
  std::optional<grant::RevocationResult> revocation;
};

class LifecycleManager {
public:
  LifecycleManager(std::filesystem::path revision_store,
                   std::filesystem::path grant_store);

  [[nodiscard]] Result recover();
  [[nodiscard]] StageOutcome
  stage(const std::filesystem::path &source_root, std::string_view directory,
        std::string_view pinned_tree_sha256,
        revision::FaultPoint fault = revision::FaultPoint::none);
  [[nodiscard]] Result
  enable(const permission::PluginId &plugin,
         revision::FaultPoint fault = revision::FaultPoint::none);
  [[nodiscard]] Result
  rollback(revision::FaultPoint fault = revision::FaultPoint::none);
  [[nodiscard]] RevocationOutcome
  revoke(const permission::PluginId &plugin,
         const permission::CapabilityKey &capability,
         revision::FaultPoint fault = revision::FaultPoint::none);
  [[nodiscard]] Result discard(const permission::PluginId &plugin);

  [[nodiscard]] revision::RevisionStore &revisions() { return revisions_; }
  [[nodiscard]] grant::GrantStore &grants() { return grants_; }

private:
  [[nodiscard]] std::optional<omarchy::plugins::discovery::VerifiedPlugin>
  stored_plugin(const grant::RevisionGrants &revision, Result &result) const;

  revision::RevisionStore revisions_;
  grant::GrantStore grants_;
};

[[nodiscard]] permission::RequestSet
translate_requests(const omarchy::plugins::manifest::ManifestV2 &manifest);

} // namespace omarchy::plugins::lifecycle
