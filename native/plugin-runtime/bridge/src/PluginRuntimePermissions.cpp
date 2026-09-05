#include "PluginRuntimeController.h"

#include <algorithm>
#include <ranges>

namespace omarchy::plugin_runtime::bridge::detail {

PluginRuntimeController::PermissionFenceObserver::PermissionFenceObserver(
    std::shared_ptr<PermissionTransaction> transaction)
    : transaction(std::move(transaction)) {}

void PluginRuntimeController::PermissionFenceObserver::
    live_generation_closed() noexcept {
  transaction->delivery.fetch_or(PermissionTransaction::fenced,
                                 std::memory_order_release);
}

bool PluginRuntimeController::beginPermissionRevoke(
    std::string_view plugin, std::uint64_t epoch,
    const plugins::permissions::CapabilityKey &capability,
    std::uint64_t expected_sequence) noexcept {
  try {
    auto result = std::make_shared<PermissionTransaction>();
    result->kind = PermissionKind::revoke_builtin;
    result->builtin = capability;
    result->expected_sequence = expected_sequence;
    return beginPermissionMutation(plugin, epoch, std::move(result));
  } catch (...) {
    return false;
  }
}

bool PluginRuntimeController::beginPermissionRead(
    std::uint64_t serial, std::string plugin, bool review,
    std::optional<plugins::permissions::Digest> expected_revision) noexcept {
  constexpr std::uint8_t kMaximumConcurrentPermissionReads = 2;
  if (serial == 0 || gate_->permission_reads_in_flight.load() >=
                         kMaximumConcurrentPermissionReads)
    return false;
  const auto found = std::ranges::lower_bound(
      slots_, plugin, {}, [](const Slot &slot) { return slot.plugin; });
  if (found == slots_.end() || found->plugin != plugin || !found->permissions ||
      found->permission_transaction || found->permission_read_serial != 0 ||
      (found->phase != Phase::running &&
       found->phase != Phase::permission_disabled))
    return false;
  bool counted = false;
  try {
    auto result = std::make_shared<PermissionReadResult>();
    result->serial = serial;
    result->plugin = std::move(plugin);
    result->epoch = found->epoch;
    result->authority = found->permissions;
    result->expected_revision = std::move(expected_revision);
    found->permission_read_serial = serial;
    ++gate_->permission_reads_in_flight;
    counted = true;
    const auto gate = gate_;
#ifdef OMARCHY_PLUGIN_MANAGER_TESTING
    const auto entry_probe = job_entry_probe_;
#endif
    const bool started = submit(JobKind::permission, [gate, result, review
#ifdef OMARCHY_PLUGIN_MANAGER_TESTING
                                                      ,
                                                      entry_probe
#endif
    ] {
#ifdef OMARCHY_PLUGIN_MANAGER_TESTING
      if (entry_probe)
        entry_probe(PluginManagerTestAccess::TestJobKind::permission);
#endif
      try {
        result->view = result->authority->list();
        if (review)
          result->review = result->authority->prepare_review();
        if (result->review && result->expected_revision &&
            result->review->candidate_binding.revision !=
                *result->expected_revision)
          result->review.reset();
      } catch (...) {
        result->view.reset();
        result->review.reset();
      }
      std::scoped_lock lock(gate->mutex);
      if (gate->canceled.load(std::memory_order_acquire)) {
        --gate->permission_reads_in_flight;
        return;
      }
      const auto destination =
          std::ranges::find(gate->permission_read_results,
                            std::shared_ptr<PermissionReadResult>{});
      if (destination == gate->permission_read_results.end()) {
        --gate->permission_reads_in_flight;
        return;
      }
      *destination = std::move(result);
    });
    if (!started) {
      --gate_->permission_reads_in_flight;
      counted = false;
      found->permission_read_serial = 0;
      return false;
    }
    armCompletionTimer();
    return true;
  } catch (...) {
    if (counted)
      --gate_->permission_reads_in_flight;
    if (found->permission_read_serial == serial)
      found->permission_read_serial = 0;
    return false;
  }
}

std::optional<host_session::AuthorityView>
PluginRuntimeController::permissionView(std::string_view plugin,
                                        std::uint64_t epoch) const {
  const auto found = std::ranges::lower_bound(
      slots_, plugin, {}, [](const Slot &slot) { return slot.plugin; });
  return found != slots_.end() && found->plugin == plugin &&
                 found->epoch == epoch && found->permissions &&
                 !found->permission_transaction
             ? found->permissions->list()
             : std::nullopt;
}

std::shared_ptr<const host_session::ConsentReview>
PluginRuntimeController::preparePermissionReview(std::string_view plugin,
                                                 std::uint64_t epoch) {
  auto *slot = exact(plugin, epoch);
  return slot && slot->permissions && !slot->permission_transaction
             ? slot->permissions->prepare_review()
             : nullptr;
}

bool PluginRuntimeController::beginPermissionRevoke(
    std::string_view plugin, std::uint64_t epoch,
    const plugins::definitions::CapabilityReference &definition,
    std::uint64_t expected_sequence) noexcept {
  try {
    auto result = std::make_shared<PermissionTransaction>();
    result->kind = PermissionKind::revoke_dynamic;
    result->dynamic = definition;
    result->expected_sequence = expected_sequence;
    return beginPermissionMutation(plugin, epoch, std::move(result));
  } catch (...) {
    return false;
  }
}

bool PluginRuntimeController::beginPermissionApply(
    std::string_view plugin, std::uint64_t epoch,
    std::shared_ptr<const host_session::ConsentReview> review,
    const host_session::ConsentConfirmation &confirmation,
    std::span<const host_session::BuiltinConsentDecision> builtin_decisions,
    std::span<const host_session::DynamicConsentDecision>
        dynamic_decisions) noexcept {
  try {
    if (!review)
      return false;
    auto result = std::make_shared<PermissionTransaction>();
    result->kind = PermissionKind::apply_review;
    result->consent_review = std::move(review);
    result->confirmation = confirmation;
    result->builtin_decisions.assign(builtin_decisions.begin(),
                                     builtin_decisions.end());
    result->dynamic_decisions.assign(dynamic_decisions.begin(),
                                     dynamic_decisions.end());
    return beginPermissionMutation(plugin, epoch, std::move(result));
  } catch (...) {
    return false;
  }
}

bool PluginRuntimeController::beginControlledPermissionApply(
    std::uint64_t serial, std::string_view plugin, std::uint64_t epoch,
    const std::shared_ptr<channel::PluginPermissionAuthority> &authority,
    std::shared_ptr<const host_session::ConsentReview> review,
    const host_session::ConsentConfirmation &confirmation,
    std::span<const host_session::BuiltinConsentDecision> builtin_decisions,
    std::span<const host_session::DynamicConsentDecision>
        dynamic_decisions) noexcept {
  auto *slot = exact(plugin, epoch);
  if (serial == 0 || !review || !slot || slot->permissions != authority)
    return false;
  try {
    auto result = std::make_shared<PermissionTransaction>();
    result->control_serial = serial;
    result->kind = PermissionKind::apply_review;
    result->consent_review = std::move(review);
    result->confirmation = confirmation;
    result->builtin_decisions.assign(builtin_decisions.begin(),
                                     builtin_decisions.end());
    result->dynamic_decisions.assign(dynamic_decisions.begin(),
                                     dynamic_decisions.end());
    return beginPermissionMutation(plugin, epoch, std::move(result));
  } catch (...) {
    return false;
  }
}

bool PluginRuntimeController::beginControlledPermissionRevoke(
    std::uint64_t serial, std::string_view plugin, std::uint64_t epoch,
    const std::shared_ptr<channel::PluginPermissionAuthority> &authority,
    bool dynamic,
    const std::optional<plugins::permissions::CapabilityKey> &builtin,
    const std::optional<plugins::definitions::CapabilityReference> &definition,
    std::uint64_t expected_sequence) noexcept {
  auto *slot = exact(plugin, epoch);
  if (serial == 0 || !slot || slot->permissions != authority)
    return false;
  try {
    auto result = std::make_shared<PermissionTransaction>();
    result->control_serial = serial;
    result->expected_sequence = expected_sequence;
    if (dynamic && definition) {
      result->kind = PermissionKind::revoke_dynamic;
      result->dynamic = *definition;
    } else if (!dynamic && builtin) {
      result->kind = PermissionKind::revoke_builtin;
      result->builtin = *builtin;
    } else {
      return false;
    }
    return beginPermissionMutation(plugin, epoch, std::move(result));
  } catch (...) {
    return false;
  }
}

bool PluginRuntimeController::beginPermissionMutation(
    std::string_view plugin, std::uint64_t epoch,
    std::shared_ptr<PermissionTransaction> result) noexcept {
  constexpr std::uint8_t kMaximumConcurrentPermissionMutations = 2;
  if (!result || gate_->permissions_in_flight.load() >=
                     kMaximumConcurrentPermissionMutations)
    return false;
  auto *slot = exact(plugin, epoch);
  const bool running = slot && slot->phase == Phase::running;
  const bool review = result->kind == PermissionKind::apply_review;
  if (!slot || !slot->permissions || slot->permission_transaction ||
      slot->permission_read_serial != 0 ||
      (review ? !(running || slot->phase == Phase::permission_disabled)
              : !running))
    return false;

  result->authority = slot->permissions;
  slot->permission_transaction = result;

  ++gate_->permissions_in_flight;
  const auto gate = gate_;
#ifdef OMARCHY_PLUGIN_MANAGER_TESTING
  const auto entry_probe = job_entry_probe_;
#endif
  bool started = false;
  try {
    started = submit(JobKind::permission, [gate, result
#ifdef OMARCHY_PLUGIN_MANAGER_TESTING
                                           ,
                                           entry_probe
#endif
    ] {
#ifdef OMARCHY_PLUGIN_MANAGER_TESTING
      if (entry_probe)
        entry_probe(PluginManagerTestAccess::TestJobKind::permission);
#endif
      try {
        PermissionFenceObserver observer(result);
        switch (result->kind) {
        case PermissionKind::revoke_builtin:
          result->revocation = result->authority->revoke(
              result->builtin, result->expected_sequence, &observer);
          break;
        case PermissionKind::revoke_dynamic:
          result->revocation = result->authority->revoke(
              result->dynamic, result->expected_sequence, &observer);
          break;
        case PermissionKind::apply_review:
          result->review = result->authority->apply_review(
              *result->consent_review, result->confirmation,
              result->builtin_decisions, result->dynamic_decisions, &observer);
          break;
        }
      } catch (...) {
        result->revocation.status =
            host_session::AuthorityMutationResult::io_error;
      }
      result->delivery.fetch_or(PermissionTransaction::complete,
                                std::memory_order_release);
      try {
        std::scoped_lock lock(gate->mutex);
        if (gate->canceled.load(std::memory_order_acquire)) {
          --gate->permissions_in_flight;
          return;
        }
        const auto destination = std::ranges::find(
            gate->permission_results, std::shared_ptr<PermissionTransaction>{});
        if (destination == gate->permission_results.end())
          std::terminate();
        *destination = result;
      } catch (...) {
        std::terminate();
      }
    });
  } catch (...) {
    --gate_->permissions_in_flight;
    if (slot->permission_transaction == result)
      slot->permission_transaction.reset();
    return false;
  }
  if (!started) {
    --gate_->permissions_in_flight;
    if (slot->permission_transaction == result)
      slot->permission_transaction.reset();
    return false;
  }
  armCompletionTimer();
  return true;
}

void PluginRuntimeController::fencePermission(Slot &slot) noexcept {
  slot.epoch = nextEpoch();
  slot.phase = Phase::permission_changing;
  withdraw(slot);
}

void PluginRuntimeController::completePermission(
    Slot &slot, const PermissionTransaction &result) noexcept {
  std::optional<plugins::permissions::ActivationBinding> binding;
  bool applied = false;
  if (result.kind == PermissionKind::apply_review) {
    if (result.review.publication != host_session::ConsentResult::applied) {
      if (slot.phase == Phase::permission_changing)
        disable(slot);
      return;
    }
    applied = result.review.promotion ==
              host_session::AuthorityMutationResult::applied;
    binding = result.review.binding;
  } else {
    applied = result.revocation.status ==
              host_session::AuthorityMutationResult::applied;
    if (result.revocation.status ==
            host_session::AuthorityMutationResult::invalid ||
        result.revocation.status ==
            host_session::AuthorityMutationResult::stale_sequence) {
      if (slot.phase == Phase::permission_changing)
        disable(slot);
      return;
    }
    if (result.revocation.activatable)
      binding = result.revocation.binding;
  }
  if (!applied || !binding) {
    disable(slot);
    return;
  }
  stopRuntime(slot);
  slot.expected_binding = std::move(binding);
  start(slot);
}

} // namespace omarchy::plugin_runtime::bridge::detail
