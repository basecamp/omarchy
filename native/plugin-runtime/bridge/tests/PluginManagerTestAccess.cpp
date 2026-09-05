#include "PluginRuntimeController.h"
#include "SurfaceEndpointOwner.h"

#ifdef OMARCHY_PLUGIN_MANAGER_TESTING

#include <algorithm>
#include <ranges>

namespace omarchy::plugin_runtime::bridge {

bool SurfaceProjectionModelTestAccess::publish(
    PluginManager &manager,
    const plugins::permissions::ActivationBinding &binding,
    std::vector<SurfaceProjectionModel::SurfaceDeclaration> declarations,
    qulonglong revision) {
  return manager.surfaces_.publishSurfaces(binding, std::move(declarations),
                                           revision);
}

bool SurfaceProjectionModelTestAccess::withdraw(
    PluginManager &manager,
    const plugins::permissions::ActivationBinding &binding) {
  return manager.surfaces_.withdrawSurfaces(binding);
}

void PluginManagerTestAccess::installRuntime(
    PluginManager &manager,
    std::unique_ptr<channel::RuntimeBootstrap> bootstrap) {
  manager.runtime_.reset();
  manager.available_ = false;
  if (bootstrap)
    manager.runtime_ = std::unique_ptr<detail::PluginRuntimeController>(
        new detail::PluginRuntimeController(
            manager, std::move(bootstrap),
            detail::PluginRuntimeController::ManualTestTag{}));
}

bool PluginManagerTestAccess::scanRuntime(PluginManager &manager) {
  if (!manager.runtime_)
    return false;
  channel::ActivationCatalogError error{};
  auto candidate = channel::RuntimeBootstrapTestAccess::scan_catalog(
      *manager.runtime_->bootstrap_, error);
  return manager.runtime_->acceptScan(std::move(candidate));
}

std::vector<PluginManagerTestAccess::SlotObservation>
PluginManagerTestAccess::runtimeSlots(const PluginManager &manager) {
  std::vector<SlotObservation> result;
  if (!manager.runtime_)
    return result;
  result.reserve(manager.runtime_->slots_.size());
  for (const auto &slot : manager.runtime_->slots_)
    result.push_back(
        {.plugin = slot.plugin,
         .epoch = slot.epoch,
         .retry_attempts = slot.retry_attempts,
         .retry_wait =
             slot.phase == detail::PluginRuntimeController::Phase::retry_wait,
         .opening =
             slot.phase == detail::PluginRuntimeController::Phase::opening,
         .preparing =
             slot.phase == detail::PluginRuntimeController::Phase::preparing,
         .starting =
             slot.phase == detail::PluginRuntimeController::Phase::starting,
         .running =
             slot.phase == detail::PluginRuntimeController::Phase::running,
         .permission_transaction = slot.permission_transaction != nullptr,
         .permission_changing =
             slot.phase ==
             detail::PluginRuntimeController::Phase::permission_changing,
         .permission_disabled =
             slot.phase ==
             detail::PluginRuntimeController::Phase::permission_disabled,
         .has_runtime_root = slot.root != nullptr,
         .has_endpoint_owner = slot.endpoint_owner != nullptr,
         .last_state = slot.last_state,
         .last_error = slot.last_error});
  return result;
}

bool PluginManagerTestAccess::retryRuntime(PluginManager &manager,
                                           std::string_view plugin) {
  if (!manager.runtime_)
    return false;
  const auto found = std::ranges::lower_bound(
      manager.runtime_->slots_, plugin, {},
      [](const detail::PluginRuntimeController::Slot &slot) {
        return slot.plugin;
      });
  if (found == manager.runtime_->slots_.end() || found->plugin != plugin ||
      found->phase != detail::PluginRuntimeController::Phase::retry_wait)
    return false;
  manager.runtime_->start(*found);
  manager.runtime_->requestPreparations();
  return true;
}

bool PluginManagerTestAccess::queueStaleRunningCallback(
    PluginManager &manager, std::string_view plugin) {
  if (!manager.runtime_)
    return false;
  const auto found = std::ranges::lower_bound(
      manager.runtime_->slots_, plugin, {},
      [](const detail::PluginRuntimeController::Slot &slot) {
        return slot.plugin;
      });
  if (found == manager.runtime_->slots_.end() || found->plugin != plugin)
    return false;
  try {
    auto state = std::make_shared<detail::PluginRuntimeController::HookState>(
        found->plugin, found->epoch);
    found->callback_state = state;
    detail::PluginRuntimeController::Hook hook(std::move(state), manager);
    hook.state_changed(host_session::SessionState::running,
                       host_session::SessionError::none);
    return true;
  } catch (...) {
    return false;
  }
}

void PluginManagerTestAccess::setJobSubmitter(PluginManager &manager,
                                              JobSubmitter submitter) {
  if (manager.runtime_)
    manager.runtime_->job_submitter_ = std::move(submitter);
}

void PluginManagerTestAccess::setJobEntryProbe(PluginManager &manager,
                                               JobEntryProbe probe) {
  if (manager.runtime_)
    manager.runtime_->job_entry_probe_ = std::move(probe);
}

void PluginManagerTestAccess::requestAsyncScan(PluginManager &manager) {
  if (manager.runtime_)
    manager.runtime_->requestScan();
}

void PluginManagerTestAccess::requestPreparations(PluginManager &manager) {
  if (manager.runtime_)
    manager.runtime_->requestPreparations();
}

void PluginManagerTestAccess::drainRuntime(PluginManager &manager) {
  if (manager.runtime_)
    manager.runtime_->drainCompletions();
}

std::optional<PluginManagerTestAccess::SurfaceIntentCallback>
PluginManagerTestAccess::surfaceIntentCallback(PluginManager &manager,
                                               std::string_view plugin,
                                               std::uint64_t epoch) {
  if (!manager.runtime_)
    return std::nullopt;
  auto *slot = manager.runtime_->exact(plugin, epoch);
  if (!slot)
    return std::nullopt;
  try {
    if (!slot->callback_state)
      slot->callback_state =
          std::make_shared<detail::PluginRuntimeController::HookState>(
              slot->plugin, slot->epoch);
    const auto state = slot->callback_state;
    return SurfaceIntentCallback{
        .deliver =
            [state, &manager](host_session::AdmittedSurfaceIntent intent) {
              detail::PluginRuntimeController::Hook hook(state, manager);
              return hook.accept(std::move(intent));
            },
        .pending =
            [state] {
              std::scoped_lock lock(state->intent_mutex);
              return state->intents.size();
            }};
  } catch (...) {
    return std::nullopt;
  }
}

bool PluginManagerTestAccess::stageRunningSurfaceIntentSlot(
    PluginManager &manager, std::string_view plugin, std::uint64_t epoch,
    const plugins::permissions::ActivationBinding &binding,
    std::vector<SurfaceProjectionModel::SurfaceDeclaration> declarations) {
  if (!manager.runtime_ || binding.plugin.view() != plugin)
    return false;
  auto *slot = manager.runtime_->exact(plugin, epoch);
  if (!slot || slot->root || slot->endpoint_owner ||
      !SurfaceProjectionModelTestAccess::publish(
          manager, binding, std::move(declarations), epoch))
    return false;
  slot->phase = detail::PluginRuntimeController::Phase::running;
  slot->test_running_binding = binding;
  slot->test_surface_endpoint = true;
  return true;
}

bool PluginManagerTestAccess::routeTrustedPointer(
    PluginManager &manager, std::string_view plugin, std::uint64_t epoch,
    QStringView surface_key, bool pressed) {
  if (!manager.runtime_)
    return false;
  auto *slot = manager.runtime_->exact(plugin, epoch);
  if (!slot || !slot->endpoint_owner)
    return false;
  return SurfaceEndpointOwnerTestAccess::route_input(
      *slot->endpoint_owner, surface_key,
      {.payload = surface::PointerButton{
           .position = {16U << surface::kQ16FractionBits,
                        16U << surface::kQ16FractionBits},
           .button = static_cast<std::uint32_t>(Qt::LeftButton),
           .state = pressed ? surface::ButtonState::pressed
                            : surface::ButtonState::released,
           .buttons = pressed ? static_cast<std::uint32_t>(Qt::LeftButton)
                              : 0U},
       .device = 1,
       .trusted_physical = true});
}

std::uint8_t
PluginManagerTestAccess::preparationCount(const PluginManager &manager) {
  return manager.runtime_
             ? manager.runtime_->gate_->preparations_in_flight.load()
             : 0;
}

std::uint8_t
PluginManagerTestAccess::executingPermissionJobs(const PluginManager &manager) {
  return manager.runtime_
             ? manager.runtime_->gate_->permissions_in_flight.load()
             : 0;
}

std::optional<plugins::permissions::DecisionActor>
PluginManagerTestAccess::pendingPermissionActor(const PluginManager &manager,
                                                std::string_view plugin) {
  if (!manager.runtime_)
    return std::nullopt;
  const auto found =
      std::ranges::find(manager.runtime_->slots_, plugin,
                        &detail::PluginRuntimeController::Slot::plugin);
  return found != manager.runtime_->slots_.end() &&
                 found->permission_transaction &&
                 found->permission_transaction->kind ==
                     detail::PluginRuntimeController::PermissionKind::
                         apply_review
             ? std::optional(found->permission_transaction->confirmation.actor)
             : std::nullopt;
}

bool PluginManagerTestAccess::scanInFlight(const PluginManager &manager) {
  return manager.runtime_ && manager.runtime_->gate_->scan_in_flight.load();
}

bool PluginManagerTestAccess::revokePermissionImmediatelyForTest(
    PluginManager &manager, std::string_view plugin, std::uint64_t epoch,
    const plugins::permissions::CapabilityKey &capability,
    std::uint64_t expected_sequence) {
  return manager.revokePermissionImmediatelyForTest(plugin, epoch, capability,
                                                    expected_sequence);
}

std::uint8_t PluginManagerTestAccess::occupiedPreparationLanes(
    const PluginManager &manager) {
  if (!manager.runtime_)
    return 0;
  std::scoped_lock lock(manager.runtime_->gate_->mutex);
  return static_cast<std::uint8_t>(std::ranges::count_if(
      manager.runtime_->gate_->preparation_results,
      [](const auto &result) { return result != nullptr; }));
}

bool PluginManagerTestAccess::deliverLifecycle(PluginManager &manager,
                                               std::string_view plugin,
                                               std::uint64_t epoch,
                                               std::uint8_t state,
                                               std::uint8_t error) {
  if (!manager.runtime_)
    return false;
  auto *slot = manager.runtime_->exact(plugin, epoch);
  if (!slot)
    return false;
  try {
    if (!slot->callback_state)
      slot->callback_state =
          std::make_shared<detail::PluginRuntimeController::HookState>(
              slot->plugin, slot->epoch);
    detail::PluginRuntimeController::Hook hook(slot->callback_state, manager);
    hook.state_changed(static_cast<host_session::SessionState>(state),
                       static_cast<host_session::SessionError>(error));
    return true;
  } catch (...) {
    return false;
  }
}

bool PluginManagerTestAccess::clockIsNondecreasing(PluginManager &manager) {
  if (!manager.runtime_)
    return false;
  const auto first = manager.runtime_->clock_.now_nanoseconds();
  const auto second = manager.runtime_->clock_.now_nanoseconds();
  return second >= first;
}

std::optional<host_session::AuthorityView>
PluginManagerTestAccess::permissionView(PluginManager &manager,
                                        std::string_view plugin,
                                        std::uint64_t epoch) {
  if (!manager.runtime_)
    return std::nullopt;
  return manager.runtime_->permissionView(plugin, epoch);
}

std::shared_ptr<const host_session::ConsentReview>
PluginManagerTestAccess::preparePermissionReview(PluginManager &manager,
                                                 std::string_view plugin,
                                                 std::uint64_t epoch) {
  if (!manager.runtime_)
    return {};
  return manager.runtime_->preparePermissionReview(plugin, epoch);
}

bool PluginManagerTestAccess::revokePermission(
    PluginManager &manager, std::string_view plugin, std::uint64_t epoch,
    const plugins::permissions::CapabilityKey &capability,
    std::uint64_t expected_sequence) {
  return manager.runtime_ && manager.runtime_->beginPermissionRevoke(
                                 plugin, epoch, capability, expected_sequence);
}

bool PluginManagerTestAccess::revokePermission(
    PluginManager &manager, std::string_view plugin, std::uint64_t epoch,
    const plugins::definitions::CapabilityReference &definition,
    std::uint64_t expected_sequence) {
  return manager.runtime_ && manager.runtime_->beginPermissionRevoke(
                                 plugin, epoch, definition, expected_sequence);
}

bool PluginManagerTestAccess::applyPermissionReview(
    PluginManager &manager, std::string_view plugin, std::uint64_t epoch,
    std::shared_ptr<const host_session::ConsentReview> review,
    const host_session::ConsentConfirmation &confirmation,
    std::span<const host_session::BuiltinConsentDecision> builtin_decisions,
    std::span<const host_session::DynamicConsentDecision> dynamic_decisions) {
  return manager.runtime_ && manager.runtime_->beginPermissionApply(
                                 plugin, epoch, std::move(review), confirmation,
                                 builtin_decisions, dynamic_decisions);
}

std::weak_ptr<const void>
PluginManagerTestAccess::deliveryGate(const PluginManager &manager) {
  return manager.runtime_ ? std::weak_ptr<const void>(manager.runtime_->gate_)
                          : std::weak_ptr<const void>{};
}

bool PluginManager::revokePermissionImmediatelyForTest(
    std::string_view plugin, std::uint64_t epoch,
    const plugins::permissions::CapabilityKey &capability,
    std::uint64_t expected_sequence) {
  if (!runtime_)
    return false;
  auto *slot = runtime_->exact(plugin, epoch);
  return slot && slot->permissions &&
         slot->permissions->revoke(capability, expected_sequence, nullptr)
                 .status == host_session::AuthorityMutationResult::applied;
}
} // namespace omarchy::plugin_runtime::bridge

#endif
