#include "update_transition.hpp"

#include <algorithm>
#include <stdexcept>
#include <utility>

namespace omarchy::plugin_runtime::transition {

namespace revision = omarchy::plugins::store;

namespace {

bool exact_binding(const revision::PolicyBinding &active,
                   const permissions::ActivationBinding &binding) {
  return active.plugin_id == binding.plugin.view() &&
         active.revision_sha256 == binding.revision.view() &&
         active.policy_sha256 == binding.policy_fingerprint.view() &&
         active.generation == binding.generation;
}

bool exact_grants(const grant::RevisionGrants &left,
                  const grant::RevisionGrants &right) {
  return permissions::grant_fingerprint(
             left.binding.plugin, left.binding.revision,
             left.binding.policy_fingerprint, left.grants) ==
         permissions::grant_fingerprint(
             right.binding.plugin, right.binding.revision,
             right.binding.policy_fingerprint, right.grants);
}

grant::RequestBundle bundle_from(const grant::RevisionGrants &revision) {
  return grant::make_bundle(grant::kSecurePluginSchemaVersion,
                            revision.binding.plugin, revision.binding.revision,
                            revision.source_request_fingerprint,
                            revision.binding.generation, revision.requests);
}

bool review_kind(permissions::DeltaKind kind) {
  return kind == permissions::DeltaKind::added ||
         kind == permissions::DeltaKind::expanded ||
         kind == permissions::DeltaKind::incomparable ||
         kind == permissions::DeltaKind::requirement_changed;
}

} // namespace

AuthenticatedChannelWorker::AuthenticatedChannelWorker(
    std::unique_ptr<channel::AuthenticatedBrokerChannel> channel)
    : channel_(std::move(channel)) {
  if (!channel_ || !channel_->ready() || !channel_->alive())
    throw std::invalid_argument("authenticated channel is not ready and alive");
}

const launcher::LaunchIdentity &AuthenticatedChannelWorker::identity() const {
  return channel_->identity();
}

bool AuthenticatedChannelWorker::alive() const { return channel_->alive(); }

bool AuthenticatedChannelWorker::terminate() { return channel_->terminate(); }

UpdateTransition::UpdateTransition(lifecycle::LifecycleManager &lifecycle,
                                   health::HealthSupervisor &health,
                                   permissions::PluginId plugin)
    : lifecycle_(lifecycle), health_(health), plugin_(std::move(plugin)) {}

Result UpdateTransition::bind_active(
    std::unique_ptr<health::WorkerControl> worker,
    std::shared_ptr<runtime::AuditedBrokerRuntime> broker,
    std::uint64_t now_seconds) {
  if (active_binding_ || !worker || !broker || broker->failed())
    return {Status::denied, "active session is absent or already bound"};
  try {
    const auto activation = lifecycle_.revisions().current();
    const auto state = lifecycle_.grants().read();
    const auto *plugin = plugin_state(state);
    if (!activation || !activation->enabled || activation->removed ||
        plugin == nullptr || !plugin->active ||
        broker->binding() != plugin->active->binding ||
        !exact_grants(broker->revision(), *plugin->active) ||
        !exact_binding(activation->active, broker->binding())) {
      (void)worker->terminate();
      return {Status::stale,
              "active lifecycle, grant, and runtime bindings differ"};
    }
    const auto binding = broker->binding();
    if (health_.adopt(std::move(worker), binding, now_seconds) !=
            health::Status::accepted ||
        health_.ready(binding, now_seconds) != health::Status::accepted)
      return {Status::health_failed, "active worker failed health admission"};
    active_binding_ = binding;
    active_runtime_ = std::move(broker);
    return {Status::accepted, {}};
  } catch (const std::exception &error) {
    if (worker)
      (void)worker->terminate();
    return {Status::lifecycle_failed, error.what()};
  }
}

lifecycle::StageOutcome UpdateTransition::stage(
    const std::filesystem::path &source_root, std::string_view directory,
    std::string_view pinned_tree_sha256, revision::FaultPoint fault) {
  lifecycle::StageOutcome outcome;
  if (!active_binding_ || candidate_binding_) {
    outcome.result = {lifecycle::ErrorCode::binding_mismatch,
                      "transition already staged or active session absent"};
    return outcome;
  }
  outcome = lifecycle_.stage(source_root, directory, pinned_tree_sha256, fault);
  if (!outcome.result.ok() || !outcome.binding || outcome.already_active)
    return outcome;
  if (outcome.binding->plugin != plugin_ ||
      outcome.binding->generation <= active_binding_->generation) {
    (void)lifecycle_.discard(plugin_);
    outcome.result = {lifecycle::ErrorCode::binding_mismatch,
                      "candidate is not a fresh binding for the active plugin"};
    return outcome;
  }
  candidate_binding_ = outcome.binding;
  candidate_delta_ = outcome.delta;
  return outcome;
}

Result UpdateTransition::decide_candidate(
    const permissions::CapabilityKey &capability,
    const std::optional<permissions::Scope> &scope,
    permissions::UserDecision decision, std::uint64_t wall_seconds) {
  if (!candidate_binding_ || candidate_attached_)
    return {Status::denied,
            "candidate is absent, running, or decision is unset"};
  try {
    const auto state = lifecycle_.grants().read();
    const auto *plugin = plugin_state(state);
    if (plugin == nullptr || !plugin->candidate ||
        plugin->candidate->binding != *candidate_binding_)
      return {Status::stale, "candidate grant binding changed"};
    const auto bundle = bundle_from(*plugin->candidate);
    const auto preview = lifecycle_.grants().preview(bundle, capability);
    if (preview.target != grant::TargetRevision::candidate ||
        preview.binding != *candidate_binding_)
      return {Status::stale, "decision preview is not the staged candidate"};
    (void)lifecycle_.grants().decide(bundle, capability, scope, decision,
                                     permissions::DecisionActor::trusted_ui,
                                     wall_seconds,
                                     preview.expected_mutation_sequence);
    return {Status::accepted, {}};
  } catch (const std::exception &error) {
    return {Status::lifecycle_failed, error.what()};
  }
}

Result UpdateTransition::prepare_candidate(
    std::unique_ptr<health::WorkerControl> worker,
    std::shared_ptr<runtime::AuditedBrokerRuntime> broker,
    std::uint64_t now_seconds) {
  if (!candidate_binding_ || candidate_attached_ || !worker || !broker ||
      broker->failed() || broker->binding() != *candidate_binding_ ||
      !candidate_review_complete()) {
    if (worker)
      (void)worker->terminate();
    return {Status::denied,
            "candidate lacks an exact reviewed runtime and worker"};
  }
  try {
    const auto state = lifecycle_.grants().read();
    const auto *plugin = plugin_state(state);
    if (plugin == nullptr || !plugin->candidate ||
        !exact_grants(broker->revision(), *plugin->candidate)) {
      (void)worker->terminate();
      return {Status::stale, "candidate runtime grant epochs changed"};
    }
  } catch (const std::exception &error) {
    (void)worker->terminate();
    return {Status::lifecycle_failed, error.what()};
  }
  const auto adopted = health_.adopt_candidate(
      std::move(worker), *candidate_binding_, now_seconds);
  if (adopted != health::Status::accepted)
    return {Status::health_failed, "candidate worker admission failed"};
  candidate_runtime_ = std::move(broker);
  candidate_attached_ = true;
  return {Status::accepted, {}};
}

Result UpdateTransition::candidate_ready(std::uint64_t now_seconds) {
  if (!candidate_binding_ || !candidate_attached_ || candidate_is_ready_)
    return {Status::denied, "candidate is absent or readiness was replayed"};
  if (health_.ready(*candidate_binding_, now_seconds) !=
      health::Status::accepted) {
    const auto discarded = lifecycle_.discard(plugin_);
    if (!discarded.ok())
      return {Status::lifecycle_failed, discarded.detail};
    clear_candidate();
    return {Status::health_failed, "candidate failed readiness health gate"};
  }
  candidate_is_ready_ = true;
  return {Status::accepted, {}};
}

Result UpdateTransition::activate(revision::FaultPoint fault) {
  if (!active_binding_ || !active_runtime_ || !candidate_binding_ ||
      !candidate_runtime_ || !candidate_is_ready_ ||
      !candidate_review_complete() || !candidate_runtime_current())
    return {Status::denied, "candidate is not reviewed and healthy"};
  const auto enabled = lifecycle_.enable(plugin_, fault);
  if (!enabled.ok())
    return {Status::lifecycle_failed, enabled.detail};
  try {
    const auto state = lifecycle_.grants().read();
    const auto *plugin = plugin_state(state);
    if (plugin == nullptr || !plugin->active ||
        plugin->active->binding != *candidate_binding_ ||
        !exact_grants(candidate_runtime_->revision(), *plugin->active)) {
      const auto rolled_back = lifecycle_.rollback();
      (void)health_.stop(*candidate_binding_);
      clear_candidate();
      if (!rolled_back.ok())
        return {Status::rollback_failed, rolled_back.detail};
      return {Status::stale, "candidate grants changed across atomic "
                             "activation; prior revision restored"};
    }
  } catch (const std::exception &error) {
    const auto rolled_back = lifecycle_.rollback();
    (void)health_.stop(*candidate_binding_);
    clear_candidate();
    return rolled_back.ok()
               ? Result{Status::stale, error.what()}
               : Result{Status::rollback_failed, rolled_back.detail};
  }
  const auto promoted = health_.promote_candidate(*candidate_binding_);
  if (promoted != health::Status::accepted) {
    const auto rolled_back = lifecycle_.rollback();
    clear_candidate();
    if (!rolled_back.ok())
      return {Status::rollback_failed, rolled_back.detail};
    active_runtime_.reset();
    active_binding_.reset();
    return {Status::health_failed, "candidate promotion failed; prior revision "
                                   "was rolled back with a fresh generation"};
  }
  active_binding_ = candidate_binding_;
  active_runtime_ = std::move(candidate_runtime_);
  candidate_binding_.reset();
  candidate_delta_ = {};
  candidate_attached_ = false;
  candidate_is_ready_ = false;
  return {Status::accepted, {}};
}

Result UpdateTransition::abort_candidate() {
  if (!candidate_binding_)
    return {Status::stale, "candidate is absent"};
  if (candidate_attached_) {
    const auto stopped = health_.stop(*candidate_binding_);
    if (stopped != health::Status::accepted) {
      (void)lifecycle_.discard(plugin_);
      clear_candidate();
      return {Status::health_failed, "candidate teardown was not confirmed"};
    }
  }
  const auto discarded = lifecycle_.discard(plugin_);
  clear_candidate();
  return discarded.ok() ? Result{Status::accepted, {}}
                        : Result{Status::lifecycle_failed, discarded.detail};
}

Result UpdateTransition::disable() {
  if (!active_binding_)
    return {Status::stale, "active session is absent"};
  const auto disabled = lifecycle_.disable();
  if (!disabled.ok())
    return {Status::lifecycle_failed, disabled.detail};
  bool stopped = health_.stop(*active_binding_) == health::Status::accepted;
  if (candidate_binding_ && candidate_attached_)
    stopped = health_.stop(*candidate_binding_) == health::Status::accepted &&
              stopped;
  if (candidate_binding_) {
    const auto discarded = lifecycle_.discard(plugin_);
    active_binding_.reset();
    active_runtime_.reset();
    clear_candidate();
    if (!discarded.ok())
      return {Status::lifecycle_failed, discarded.detail};
  } else {
    active_binding_.reset();
    active_runtime_.reset();
    clear_candidate();
  }
  return stopped
             ? Result{Status::accepted, {}}
             : Result{
                   Status::health_failed,
                   "disable persisted but worker teardown was not confirmed"};
}

Result UpdateTransition::remove() {
  if (!active_binding_)
    return {Status::stale, "active session is absent"};
  const auto binding = *active_binding_;
  const auto disabled = lifecycle_.disable();
  if (!disabled.ok())
    return {Status::lifecycle_failed, disabled.detail};
  bool stopped = health_.stop(binding) == health::Status::accepted;
  if (candidate_binding_ && candidate_attached_)
    stopped = health_.stop(*candidate_binding_) == health::Status::accepted &&
              stopped;
  active_binding_.reset();
  active_runtime_.reset();
  clear_candidate();
  const auto removed = lifecycle_.remove(plugin_);
  if (!removed.ok())
    return {Status::lifecycle_failed, removed.detail};
  return stopped
             ? Result{Status::accepted, {}}
             : Result{
                   Status::health_failed,
                   "removal persisted but worker teardown was not confirmed"};
}

runtime::RevocationResult
UpdateTransition::revoke(const permissions::CapabilityKey &capability) {
  runtime::RevocationResult result;
  if (!active_binding_ || !active_runtime_) {
    result.status = runtime::RuntimeStatus::binding_mismatch;
    return result;
  }
  const auto persisted = lifecycle_.revoke(plugin_, capability);
  if (!persisted.result.ok() || !persisted.revocation) {
    result.status = runtime::RuntimeStatus::failed;
    return result;
  }
  result = active_runtime_->apply_revocation(*persisted.revocation);
  if (result.status != runtime::RuntimeStatus::accepted) {
    (void)health_.stop(*active_binding_);
    active_binding_.reset();
    active_runtime_.reset();
    return result;
  }
  if (result.restart_worker) {
    const auto stopped = health_.stop(*active_binding_);
    active_binding_.reset();
    active_runtime_.reset();
    if (stopped != health::Status::accepted)
      result.status = runtime::RuntimeStatus::failed;
  }
  return result;
}

const grant::PluginGrants *
UpdateTransition::plugin_state(const grant::StoreState &state) const {
  const auto found =
      std::find_if(state.plugins.begin(), state.plugins.end(),
                   [&](const auto &entry) { return entry.plugin == plugin_; });
  return found == state.plugins.end() ? nullptr : &*found;
}

bool UpdateTransition::candidate_review_complete() const {
  if (!candidate_binding_)
    return false;
  try {
    const auto state = lifecycle_.grants().read();
    const auto *plugin = plugin_state(state);
    if (plugin == nullptr || !plugin->candidate ||
        plugin->candidate->binding != *candidate_binding_)
      return false;
    for (const auto &delta : candidate_delta_.values()) {
      if (!review_kind(delta.kind))
        continue;
      const auto decision = std::find_if(
          state.decisions.rbegin(), state.decisions.rend(),
          [&](const auto &record) {
            return record.plugin == plugin_ &&
                   record.revision == candidate_binding_->revision &&
                   record.policy_request_fingerprint ==
                       candidate_binding_->policy_fingerprint &&
                   record.capability == delta.capability &&
                   record.actor == permissions::DecisionActor::trusted_ui;
          });
      if (decision == state.decisions.rend())
        return false;
      const auto grant = std::find_if(
          plugin->candidate->grants.values().begin(),
          plugin->candidate->grants.values().end(), [&](const auto &record) {
            return record.capability == delta.capability;
          });
      if (grant == plugin->candidate->grants.values().end() ||
          grant->scope != decision->decided_scope ||
          (decision->decision == permissions::UserDecision::grant &&
           grant->state != permissions::GrantState::granted) ||
          (decision->decision == permissions::UserDecision::deny &&
           grant->state != permissions::GrantState::denied))
        return false;
    }
    return true;
  } catch (const std::exception &) {
    return false;
  }
}

bool UpdateTransition::candidate_runtime_current() const {
  if (!candidate_binding_ || !candidate_runtime_ ||
      candidate_runtime_->binding() != *candidate_binding_)
    return false;
  try {
    const auto state = lifecycle_.grants().read();
    const auto *plugin = plugin_state(state);
    return plugin != nullptr && plugin->candidate &&
           plugin->candidate->binding == *candidate_binding_ &&
           exact_grants(candidate_runtime_->revision(), *plugin->candidate);
  } catch (const std::exception &) {
    return false;
  }
}

void UpdateTransition::clear_candidate() {
  candidate_binding_.reset();
  candidate_delta_ = {};
  candidate_runtime_.reset();
  candidate_attached_ = false;
  candidate_is_ready_ = false;
}

} // namespace omarchy::plugin_runtime::transition
