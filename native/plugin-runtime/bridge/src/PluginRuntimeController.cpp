#include "PluginRuntimeController.h"

#include <QQmlEngine>

#include <algorithm>
#include <chrono>
#include <ranges>

namespace omarchy::plugin_runtime::bridge::detail {
namespace {

constexpr int kCatalogScanIntervalMilliseconds = 2000;
constexpr int kActiveCompletionIntervalMilliseconds = 10;
constexpr int kIdleCompletionIntervalMilliseconds = 200;
constexpr int kInitialRetryMilliseconds = 250;
constexpr int kMaximumRetryMilliseconds = 30000;
constexpr std::uint8_t kMaximumRetryExponent = 7;

} // namespace

std::uint64_t PluginRuntimeController::MonotonicClock::now_nanoseconds() const {
  static_assert(std::chrono::steady_clock::is_steady);
  const auto elapsed = std::chrono::duration_cast<std::chrono::nanoseconds>(
                           std::chrono::steady_clock::now().time_since_epoch())
                           .count();
  return elapsed < 0 ? 0 : static_cast<std::uint64_t>(elapsed);
}

std::unique_ptr<PluginRuntimeController>
PluginRuntimeController::open(PluginManager &manager) noexcept {
  try {
    channel::RuntimeBootstrapError error{};
    auto bootstrap = channel::RuntimeBootstrap::open(error);
    if (!bootstrap)
      return {};
    return std::unique_ptr<PluginRuntimeController>(
        new PluginRuntimeController(manager, std::move(bootstrap)));
  } catch (...) {
    return {};
  }
}

PluginRuntimeController::PluginRuntimeController(
    PluginManager &manager,
    std::unique_ptr<channel::RuntimeBootstrap> bootstrap)
    : manager_(manager), bootstrap_(std::move(bootstrap)) {
  configureTimers();
  scan_timer_.start();
  QTimer::singleShot(0, &manager_, [this] { requestScan(); });
}

#ifdef OMARCHY_PLUGIN_MANAGER_TESTING
PluginRuntimeController::PluginRuntimeController(
    PluginManager &manager,
    std::unique_ptr<channel::RuntimeBootstrap> bootstrap, ManualTestTag)
    : manager_(manager), bootstrap_(std::move(bootstrap)), manual_test_(true) {
  configureTimers();
}
#endif

void PluginRuntimeController::configureTimers() {
  // A fixed bounded poll keeps catalog observation simple and
  // non-overlapping; each scan still proves freshness before reconciliation.
  scan_timer_.setInterval(kCatalogScanIntervalMilliseconds);
  QObject::connect(&scan_timer_, &QTimer::timeout, &manager_,
                   [this] { requestScan(); });
  QObject::connect(&retry_timer_, &QTimer::timeout, &manager_,
                   [this] { retryDue(); });
  QObject::connect(&completion_timer_, &QTimer::timeout, &manager_,
                   [this] { drainCompletions(); });
  retry_timer_.setSingleShot(true);
}

PluginRuntimeController::~PluginRuntimeController() noexcept {
  scan_timer_.stop();
  retry_timer_.stop();
  completion_timer_.stop();
  gate_->canceled.store(true, std::memory_order_release);
  for (auto &slot : slots_)
    stopRuntime(slot);
}

void PluginRuntimeController::drainCompletions() noexcept {
  std::shared_ptr<ScanResult> scan;
  std::array<std::shared_ptr<PreparationResult>, 2> preparations;
  std::array<std::shared_ptr<PermissionReadResult>, 2> permission_reads;
  std::array<std::shared_ptr<PermissionTransaction>, 2> permission_results;
  std::shared_ptr<InstallResult> install;
  {
    std::scoped_lock lock(gate_->mutex);
    scan = std::move(gate_->scan_result);
    preparations = std::move(gate_->preparation_results);
    permission_reads = std::move(gate_->permission_read_results);
    permission_results = std::move(gate_->permission_results);
    install = std::move(gate_->install_result);
  }
  if (scan) {
    gate_->scan_in_flight.store(false);
    acceptScan(std::move(scan->catalog));
  }
  if (install) {
    gate_->install_in_flight.store(false);
    if (install->error.empty()) {
      manager_.permissions_.invalidatePlugin(install->plugin);
      if (!install->catalog || !acceptScan(std::move(install->catalog)))
        install->error = "catalog-rejected";
    }
    manager_.completeInstall(install->serial, std::move(install->plugin),
                             std::move(install->revision),
                             std::move(install->error));
  }
  for (auto &result : preparations) {
    if (!result)
      continue;
    --gate_->preparations_in_flight;
    auto *slot = exact(result->plugin, result->epoch);
    if (slot == nullptr || slot->phase != Phase::preparing)
      continue;
    if (!result->permissions ||
        (slot->permissions && slot->permissions != result->permissions)) {
      fail(*slot);
      continue;
    }
    slot->permissions = std::move(result->permissions);
    if (result->permission_disabled) {
      slot->phase = Phase::permission_disabled;
      slot->expected_binding.reset();
      slot->retry_attempts = 0;
      slot->retry_due.reset();
      continue;
    }
    try {
      auto callback_state =
          std::make_shared<HookState>(slot->plugin, slot->epoch);
      auto hook = std::make_unique<Hook>(callback_state, manager_);
      auto root = channel::PluginRuntimeRoot::commit(
          std::move(result->prepared), *hook, manager_);
      if (!root) {
        if (slot->expected_binding)
          disable(*slot);
        else
          fail(*slot);
      } else {
        slot->callback_state = std::move(callback_state);
        slot->hook = std::move(hook);
        slot->root = std::move(root);
        slot->phase = Phase::starting;
      }
    } catch (...) {
      if (slot->expected_binding)
        disable(*slot);
      else
        fail(*slot);
    }
  }
  for (auto &result : permission_reads) {
    if (!result)
      continue;
    --gate_->permission_reads_in_flight;
    auto *slot = exact(result->plugin, result->epoch);
    if (!slot || slot->permissions != result->authority ||
        slot->permission_transaction ||
        slot->permission_read_serial != result->serial) {
      manager_.failPermissionControl(result->serial, "stale-context");
      continue;
    }
    slot->permission_read_serial = 0;
    manager_.completePermissionRead(result->serial, std::move(result->plugin),
                                    result->epoch, std::move(result->authority),
                                    std::move(result->view),
                                    std::move(result->review));
  }
  for (auto &slot : slots_) {
    const auto transaction = slot.permission_transaction;
    if (!transaction)
      continue;
    const auto delivery = transaction->delivery.load(std::memory_order_acquire);
    if ((delivery & PermissionTransaction::fenced) != 0 &&
        slot.phase != Phase::permission_changing)
      fencePermission(slot);
    if ((delivery & PermissionTransaction::complete) != 0) {
      completePermission(slot, *transaction);
      if (slot.permission_transaction == transaction)
        slot.permission_transaction.reset();
    }
  }
  for (auto &result : permission_results) {
    if (!result)
      continue;
    --gate_->permissions_in_flight;
    if (result->control_serial == 0)
      continue;
    const bool applied =
        result->kind == PermissionKind::apply_review
            ? result->review.publication ==
                      host_session::ConsentResult::applied &&
                  result->review.promotion ==
                      host_session::AuthorityMutationResult::applied &&
                  result->review.binding.has_value()
            : result->revocation.status ==
                  host_session::AuthorityMutationResult::applied;
    manager_.completePermissionMutation(
        result->control_serial, applied,
        applied ? std::string{} : std::string("authority-rejected"));
  }
  for (auto &slot : slots_) {
    const auto state = slot.callback_state;
    if (!state)
      continue;
    const auto encoded =
        state->lifecycle.exchange(0, std::memory_order_acq_rel);
    if (encoded == 0)
      continue;
    const auto packed = static_cast<std::uint16_t>(encoded - 1U);
    stateChanged(state->plugin, state->epoch,
                 static_cast<host_session::SessionState>(packed & 0xffU),
                 static_cast<host_session::SessionError>(packed >> 8U));
  }
  for (auto &slot : slots_)
    drainSurfaceIntents(slot);
  requestPreparations();
  armCompletionTimer();
}

void PluginRuntimeController::disable(Slot &slot) noexcept {
  stopRuntime(slot);
  slot.expected_binding.reset();
  slot.retry_attempts = 0;
  slot.retry_due.reset();
  slot.phase = Phase::permission_disabled;
}
void PluginRuntimeController::armCompletionTimer() noexcept {
#ifdef OMARCHY_PLUGIN_MANAGER_TESTING
  if (manual_test_)
    return;
#endif
  // A finished worker leaves its transaction attached until one UI drain
  // consumes it, so job accounting alone cannot decide timer liveness.
  const bool active = gate_->scan_in_flight.load() != 0 ||
                      gate_->preparations_in_flight.load() != 0 ||
                      gate_->permissions_in_flight.load() != 0 ||
                      gate_->permission_reads_in_flight.load() != 0 ||
                      gate_->install_in_flight.load() ||
                      std::ranges::any_of(slots_, [](const Slot &slot) {
                        return slot.phase == Phase::opening ||
                               slot.phase == Phase::preparing ||
                               slot.phase == Phase::starting ||
                               slot.permission_transaction != nullptr;
                      });
  const bool monitoring = std::ranges::any_of(
      slots_, [](const Slot &slot) { return slot.callback_state != nullptr; });
  if (!active && !monitoring) {
    completion_timer_.stop();
    return;
  }
  const int interval = active ? kActiveCompletionIntervalMilliseconds
                              : kIdleCompletionIntervalMilliseconds;
  if (!completion_timer_.isActive() || completion_timer_.interval() != interval)
    completion_timer_.start(interval);
}

PluginRuntimeController::Slot *
PluginRuntimeController::exact(std::string_view plugin,
                               std::uint64_t epoch) noexcept {
  const auto found = std::ranges::lower_bound(
      slots_, plugin, {}, [](const Slot &slot) { return slot.plugin; });
  return found != slots_.end() && found->plugin == plugin &&
                 found->epoch == epoch
             ? &*found
             : nullptr;
}

void PluginRuntimeController::fail(Slot &slot) noexcept {
  stopRuntime(slot);
  if (slot.retry_attempts < std::numeric_limits<std::uint8_t>::max())
    ++slot.retry_attempts;
  const auto exponent =
      std::min<int>(slot.retry_attempts - 1, kMaximumRetryExponent);
  const auto delay = std::min(kInitialRetryMilliseconds * (1 << exponent),
                              kMaximumRetryMilliseconds);
  slot.phase = Phase::retry_wait;
  slot.retry_due = Clock::now() + std::chrono::milliseconds(delay);
  armRetryTimer();
}

void PluginRuntimeController::stopRuntime(Slot &slot) noexcept {
  slot.phase = Phase::stopping;
  slot.epoch = nextEpoch();
  slot.retry_due.reset();
  slot.permission_transaction.reset();
  slot.permission_read_serial = 0;
  withdraw(slot);
  slot.root.reset();
  slot.hook.reset();
  slot.callback_state.reset();
}

std::uint64_t PluginRuntimeController::nextEpoch() noexcept {
  if (next_epoch_ == std::numeric_limits<std::uint64_t>::max())
    std::terminate();
  return ++next_epoch_;
}

} // namespace omarchy::plugin_runtime::bridge::detail
