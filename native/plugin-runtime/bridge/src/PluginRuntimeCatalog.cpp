#include "PluginRuntimeController.h"

#include <algorithm>
#include <ranges>
#include <stdexcept>
#include <unistd.h>

namespace omarchy::plugin_runtime::bridge::detail {
void PluginRuntimeController::requestScan() noexcept {
  if (gate_->scan_in_flight.exchange(true))
    return;
  try {
    auto result = std::make_shared<ScanResult>();
    const auto bootstrap = bootstrap_;
    const auto gate = gate_;
#ifdef OMARCHY_PLUGIN_MANAGER_TESTING
    const auto entry_probe = job_entry_probe_;
#endif
    const bool started = submit(JobKind::scan, [bootstrap, gate, result
#ifdef OMARCHY_PLUGIN_MANAGER_TESTING
                                                ,
                                                entry_probe
#endif
    ] {
#ifdef OMARCHY_PLUGIN_MANAGER_TESTING
      if (entry_probe)
        entry_probe(PluginManagerTestAccess::TestJobKind::scan);
#endif
      try {
        channel::ActivationCatalogError error{};
        result->catalog = bootstrap->scan_catalog(error);
        std::scoped_lock lock(gate->mutex);
        if (!gate->canceled.load(std::memory_order_acquire)) {
          gate->scan_result = std::move(result);
        } else {
          gate->scan_in_flight.store(false);
        }
      } catch (...) {
        gate->scan_in_flight.store(false);
      }
    });
    if (!started)
      gate_->scan_in_flight.store(false);
  } catch (...) {
    gate_->scan_in_flight.store(false);
  }
  armCompletionTimer();
}

bool PluginRuntimeController::reconcile(
    std::unique_ptr<channel::ActivationCatalog> candidate) noexcept {
  try {
    if (catalog_ && catalog_->same_epoch(*candidate))
      return candidate->unchanged();
    const auto incoming = candidate->entries();
    const auto previous =
        catalog_ ? catalog_->entries()
                 : std::span<const channel::ActivationCatalogEntry>{};
    std::vector<std::optional<Slot>> additions(incoming.size());
    for (std::size_t index = 0; index < incoming.size(); ++index) {
      const auto old = std::ranges::lower_bound(
          slots_, incoming[index].plugin_id(), {},
          [](const Slot &slot) { return slot.plugin; });
      const auto old_index =
          static_cast<std::size_t>(std::distance(slots_.begin(), old));
      const bool retained = old != slots_.end() &&
                            old->plugin == incoming[index].plugin_id() &&
                            old_index < previous.size() &&
                            previous[old_index].same_epoch(incoming[index]);
      if (!retained)
        additions[index].emplace(makeSlot(incoming[index].plugin_id()));
    }
    std::vector<Slot> replacement;
    replacement.reserve(incoming.size());

    // This final predicate protects membership-plan coherence. Runtime open
    // verifies live authority again, and later filesystem changes are
    // observed by the next scan rather than trusted from this catalog.
    if (!candidate->unchanged())
      return false;

    std::size_t old_index = 0;
    std::size_t new_index = 0;
    while (old_index < slots_.size() || new_index < incoming.size()) {
      if (new_index == incoming.size() ||
          (old_index < slots_.size() &&
           slots_[old_index].plugin < incoming[new_index].plugin_id())) {
        stopRuntime(slots_[old_index++]);
        continue;
      }
      if (old_index == slots_.size() ||
          incoming[new_index].plugin_id() < slots_[old_index].plugin) {
        replacement.push_back(std::move(*additions[new_index++]));
        continue;
      }
      if (old_index >= previous.size() ||
          !previous[old_index].same_epoch(incoming[new_index])) {
        stopRuntime(slots_[old_index]);
        replacement.push_back(std::move(*additions[new_index]));
      } else {
        replacement.push_back(std::move(slots_[old_index]));
      }
      ++old_index;
      ++new_index;
    }
    slots_ = std::move(replacement);
    catalog_ = std::move(candidate);
    for (auto &slot : slots_)
      if (slot.phase == Phase::opening && slot.epoch == 0)
        start(slot);
    armRetryTimer();
    requestPreparations();
    return true;
  } catch (...) {
    return false;
  }
}

PluginRuntimeController::Slot
PluginRuntimeController::makeSlot(std::string_view plugin) {
  Slot slot;
  slot.plugin = std::string(plugin);
  return slot;
}

bool PluginRuntimeController::acceptScan(
    std::unique_ptr<channel::ActivationCatalog> candidate) noexcept {
  if (!candidate || !reconcile(std::move(candidate)))
    return false;
  if (!manager_.available_) {
    manager_.available_ = true;
    emit manager_.availableChanged();
  }
  return true;
}

void PluginRuntimeController::start(Slot &slot) noexcept {
  slot.retry_due.reset();
  slot.epoch = nextEpoch();
  slot.phase = Phase::opening;
}

void PluginRuntimeController::requestPreparations() noexcept {
  constexpr std::uint8_t kMaximumConcurrentPreparations = 2;
  while (gate_->preparations_in_flight.load() <
         kMaximumConcurrentPreparations) {
    auto found = std::ranges::find_if(
        slots_, [](const Slot &slot) { return slot.phase == Phase::opening; });
    if (found == slots_.end())
      break;
    found->phase = Phase::preparing;
    bool counted = false;
    try {
      auto result = std::make_shared<PreparationResult>();
      result->plugin = found->plugin;
      result->epoch = found->epoch;
      result->permissions = found->permissions;
      result->settings = manager_.currentSettings(found->plugin);
      result->presentation = manager_.currentPresentation();
      const auto bootstrap = bootstrap_;
      const auto gate = gate_;
#ifdef OMARCHY_PLUGIN_MANAGER_TESTING
      const auto entry_probe = job_entry_probe_;
#endif
      ++gate_->preparations_in_flight;
      counted = true;
      const bool started = submit(JobKind::preparation, [bootstrap, gate, result
#ifdef OMARCHY_PLUGIN_MANAGER_TESTING
                                                         ,
                                                         entry_probe
#endif
      ] {
#ifdef OMARCHY_PLUGIN_MANAGER_TESTING
        if (entry_probe)
          entry_probe(PluginManagerTestAccess::TestJobKind::preparation);
#endif
        try {
          const plugins::permissions::PluginId plugin(result->plugin);
          if (!result->permissions)
            result->permissions =
                bootstrap->open_permissions(result->plugin, plugin);
          if (result->permissions) {
            auto preparation = bootstrap->prepare_runtime(
                result->permissions, result->settings, result->presentation);
            result->prepared = std::move(preparation.runtime);
            result->permission_disabled = preparation.permission_disabled;
          }
        } catch (...) {
          result->prepared.reset();
        }
        try {
          std::scoped_lock lock(gate->mutex);
          if (!gate->canceled.load(std::memory_order_acquire)) {
            const auto empty =
                std::ranges::find(gate->preparation_results,
                                  std::shared_ptr<PreparationResult>{});
            if (empty != gate->preparation_results.end()) {
              *empty = std::move(result);
            } else {
              // The in-flight bound includes occupied lanes, so this is
              // an internal accounting violation, not plugin failure.
              std::terminate();
            }
          } else {
            --gate->preparations_in_flight;
          }
        } catch (...) {
          std::terminate();
        }
      });
      if (!started) {
        --gate_->preparations_in_flight;
        counted = false;
        found->phase = Phase::opening;
        break;
      }
    } catch (...) {
      if (counted)
        --gate_->preparations_in_flight;
      found->phase = Phase::opening;
      break;
    }
  }
  armCompletionTimer();
}

bool PluginRuntimeController::beginInstall(std::uint64_t serial,
                                           int archive_fd) noexcept {
  host_session::OwnedDescriptor owned(archive_fd);
  try {
    if (serial == 0 || archive_fd < 0 ||
        gate_->install_in_flight.exchange(true))
      return false;
    auto descriptor = std::make_shared<host_session::OwnedDescriptor>();
    *descriptor = std::move(owned);
    auto result = std::make_shared<InstallResult>();
    result->serial = serial;
    const auto bootstrap = bootstrap_;
    const auto gate = gate_;
#ifdef OMARCHY_PLUGIN_MANAGER_TESTING
    const auto entry_probe = job_entry_probe_;
#endif
    const bool started =
        submit(JobKind::install, [bootstrap, gate, descriptor, result
#ifdef OMARCHY_PLUGIN_MANAGER_TESTING
                                  ,
                                  entry_probe
#endif
    ] {
#ifdef OMARCHY_PLUGIN_MANAGER_TESTING
          if (entry_probe)
            entry_probe(PluginManagerTestAccess::TestJobKind::install);
#endif
          try {
            auto published =
                bootstrap->stage_revision_for_review(descriptor->get());
            result->plugin = published.verified().manifest.id;
            result->revision = published.verified().identity.tree_sha256;
            channel::ActivationCatalogError error{};
            result->catalog = bootstrap->scan_catalog(error);
            if (!result->catalog || !result->catalog->unchanged())
              throw std::runtime_error("catalog unavailable");
          } catch (...) {
            result->plugin.clear();
            result->revision.clear();
            result->catalog.reset();
            result->error = "archive-rejected";
          }
          std::scoped_lock lock(gate->mutex);
          if (!gate->canceled.load(std::memory_order_acquire))
            gate->install_result = std::move(result);
          else
            gate->install_in_flight.store(false);
        });
    if (!started) {
      gate_->install_in_flight.store(false);
      return false;
    }
    armCompletionTimer();
    return true;
  } catch (...) {
    gate_->install_in_flight.store(false);
    return false;
  }
}

void PluginRuntimeController::retryDue() noexcept {
  const auto now = Clock::now();
  for (auto &slot : slots_)
    if (slot.phase == Phase::retry_wait && slot.retry_due &&
        *slot.retry_due <= now)
      start(slot);
  armRetryTimer();
  requestPreparations();
}

void PluginRuntimeController::armRetryTimer() noexcept {
#ifdef OMARCHY_PLUGIN_MANAGER_TESTING
  if (manual_test_)
    return;
#endif
  std::optional<Clock::time_point> earliest;
  for (const auto &slot : slots_)
    if (slot.phase == Phase::retry_wait && slot.retry_due &&
        (!earliest || *slot.retry_due < *earliest))
      earliest = slot.retry_due;
  if (!earliest) {
    retry_timer_.stop();
    return;
  }
  const auto remaining = std::chrono::duration_cast<std::chrono::milliseconds>(
      *earliest - Clock::now());
  retry_timer_.start(
      static_cast<int>(std::max<std::int64_t>(1, remaining.count())));
}

} // namespace omarchy::plugin_runtime::bridge::detail
