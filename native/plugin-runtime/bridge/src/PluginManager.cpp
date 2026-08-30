#include "PluginManager.h"

#include "SurfaceEndpointOwner.h"
#include "omarchy/plugin_runtime/Version.h"
#include "remote_surface.hpp"
#include "runtime_bootstrap.hpp"
#include "surface_host.hpp"

#include <QQmlEngine>
#include <QThread>
#include <QThreadPool>
#include <QTimer>

#include <algorithm>
#include <array>
#include <atomic>
#include <chrono>
#ifdef OMARCHY_PLUGIN_MANAGER_TESTING
#include <functional>
#endif
#include <limits>
#include <mutex>
#include <new>
#include <optional>
#include <ranges>
#include <span>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace omarchy::plugin_runtime::bridge {
namespace {

constexpr int kCatalogScanIntervalMilliseconds = 2000;
constexpr int kActiveCompletionIntervalMilliseconds = 10;
constexpr int kIdleCompletionIntervalMilliseconds = 200;
constexpr int kInitialRetryMilliseconds = 250;
constexpr int kMaximumRetryMilliseconds = 30000;
constexpr std::uint8_t kMaximumRetryExponent = 7;

std::atomic<QQmlEngine *> claimed_engine = nullptr;

class ManagerMonotonicClock final : public surface_host::MonotonicClock {
public:
  std::uint64_t now_nanoseconds() const override {
    static_assert(std::chrono::steady_clock::is_steady);
    const auto elapsed = std::chrono::duration_cast<std::chrono::nanoseconds>(
                             std::chrono::steady_clock::now().time_since_epoch())
                             .count();
    return elapsed < 0 ? 0 : static_cast<std::uint64_t>(elapsed);
  }
};

#ifdef OMARCHY_PLUGIN_MANAGER_TESTING
std::atomic_bool fail_next_manager_construction = false;
#endif

} // namespace

struct PluginManager::Runtime final {
  using Clock = std::chrono::steady_clock;

  enum class Phase : std::uint8_t {
    opening,
    starting,
    running_unpublished,
    running_published,
    permission_changing,
    permission_disabled,
    retry_wait,
    stopping,
  };
  enum class JobKind : std::uint8_t { scan, preparation, permission };
  enum class PermissionKind : std::uint8_t {
    revoke_builtin,
    revoke_dynamic,
    apply_review,
  };

  struct HookState final {
    explicit HookState(std::string plugin, std::uint64_t epoch)
        : plugin(std::move(plugin)), epoch(epoch) {}

    const std::string plugin;
    const std::uint64_t epoch;
    // Zero means no pending callback; nonzero is packed state/error plus one.
    std::atomic<std::uint16_t> lifecycle = 0;
  };

  struct Hook final : channel::PluginRuntimeHooks {
    explicit Hook(std::shared_ptr<HookState> state) : state(std::move(state)) {}

    void state_changed(host_session::SessionState state,
                       host_session::SessionError error) override {
      const auto packed = static_cast<std::uint16_t>(state) |
                          (static_cast<std::uint16_t>(error) << 8U);
      this->state->lifecycle.store(static_cast<std::uint16_t>(packed + 1U),
                                   std::memory_order_release);
    }

    void control_received(const host_session::OwnedMessage &) override {}
    void render_rejected(host_session::RouteResult) override {}
    bool accept(host_session::AdmittedSurfaceIntent) override {
      // A running transport is not typed publication readiness, so this
      // transport-only composition keeps surface intents inert.
      return false;
    }

    std::shared_ptr<HookState> state;
  };

  struct Slot final {
    std::string plugin;
    std::uint64_t epoch = 0;
    Phase phase = Phase::opening;
    std::uint8_t retry_attempts = 0;
    std::optional<Clock::time_point> retry_due;
    bool preparing = false;
    bool permission_in_flight = false;
    std::uint64_t permission_epoch = 0;
    std::shared_ptr<HookState> callback_state;
    std::unique_ptr<Hook> hook;
    std::shared_ptr<channel::PluginPermissionAuthority> permissions;
    std::optional<plugins::permissions::ActivationBinding> expected_binding;
    std::unique_ptr<channel::PluginRuntimeRoot> root;
    std::unique_ptr<SurfaceEndpointOwner> endpoint_owner;
#ifdef OMARCHY_PLUGIN_MANAGER_TESTING
    std::uint8_t last_state = 0;
    std::uint8_t last_error = 0;
#endif
  };

  struct ScanResult final {
    std::unique_ptr<channel::ActivationCatalog> catalog;
  };

  struct PreparationResult final {
    std::string plugin;
    std::uint64_t epoch = 0;
    std::shared_ptr<channel::PluginPermissionAuthority> permissions;
    std::unique_ptr<channel::PreparedPluginRuntime> prepared;
    bool permission_disabled = false;
  };

  struct PermissionResult final {
    std::string plugin;
    std::uint64_t epoch = 0;
    PermissionKind kind = PermissionKind::revoke_builtin;
    std::shared_ptr<channel::PluginPermissionAuthority> permissions;
    plugins::permissions::CapabilityKey builtin;
    plugins::definitions::CapabilityReference dynamic;
    std::uint64_t expected_sequence = 0;
    host_session::ConsentConfirmation confirmation;
    std::vector<host_session::BuiltinConsentDecision> builtin_decisions;
    std::vector<host_session::DynamicConsentDecision> dynamic_decisions;
    host_session::AuthorityRevocationResult revocation;
    channel::ReviewedPermissionApplyResult review;
  };

  struct DeliveryGate final {
    std::mutex mutex;
    std::atomic<bool> canceled = false;
    std::atomic<bool> scan_in_flight = false;
    std::atomic<std::uint8_t> preparations_in_flight = 0;
    std::atomic<std::uint8_t> permissions_in_flight = 0;
    std::shared_ptr<ScanResult> scan_result;
    std::array<std::shared_ptr<PreparationResult>, 2> preparation_results;
    std::array<std::shared_ptr<PermissionResult>, 2> permission_results;
    std::array<std::shared_ptr<PermissionResult>, 2> permission_fences;
  };

  struct PermissionFenceObserver final
      : host_session::AuthorityFenceObserver {
    PermissionFenceObserver(std::shared_ptr<DeliveryGate> gate,
                            std::shared_ptr<PermissionResult> result)
        : gate(std::move(gate)), result(std::move(result)) {}

    std::shared_ptr<DeliveryGate> gate;
    std::shared_ptr<PermissionResult> result;

    void live_generation_closed() noexcept override {
      try {
        std::scoped_lock lock(gate->mutex);
        if (gate->canceled.load(std::memory_order_acquire))
          return;
        const auto empty = std::ranges::find(
            gate->permission_fences, std::shared_ptr<PermissionResult>{});
        if (empty == gate->permission_fences.end())
          std::terminate();
        *empty = result;
      } catch (...) {
        std::terminate();
      }
    }
  };

  static std::unique_ptr<Runtime> open(PluginManager &manager) noexcept {
    try {
      channel::RuntimeBootstrapError error{};
      auto bootstrap = channel::RuntimeBootstrap::open(error);
      if (!bootstrap)
        return {};
      return std::unique_ptr<Runtime>(
          new Runtime(manager, std::move(bootstrap)));
    } catch (...) {
      return {};
    }
  }

  Runtime(PluginManager &manager,
          std::unique_ptr<channel::RuntimeBootstrap> bootstrap)
      : manager_(manager), bootstrap_(std::move(bootstrap)) {
    configureTimers();
    scan_timer_.start();
    QTimer::singleShot(0, &manager_, [this] { requestScan(); });
  }

#ifdef OMARCHY_PLUGIN_MANAGER_TESTING
  struct ManualTestTag final {};
  Runtime(PluginManager &manager,
          std::unique_ptr<channel::RuntimeBootstrap> bootstrap,
          ManualTestTag)
      : manager_(manager), bootstrap_(std::move(bootstrap)),
        manual_test_(true) {
    configureTimers();
  }
#endif

  void configureTimers() {
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

  ~Runtime() noexcept {
    scan_timer_.stop();
    retry_timer_.stop();
    completion_timer_.stop();
    gate_->canceled.store(true, std::memory_order_release);
    for (auto &slot : slots_)
      stopRuntime(slot);
  }

  void requestScan() noexcept {
    if (gate_->scan_in_flight.exchange(true))
      return;
    try {
      auto result = std::make_shared<ScanResult>();
      const auto bootstrap = bootstrap_;
      const auto gate = gate_;
#ifdef OMARCHY_PLUGIN_MANAGER_TESTING
      const auto entry_probe = job_entry_probe_;
#endif
      const bool started = submit(
          JobKind::scan,
          [bootstrap, gate, result
#ifdef OMARCHY_PLUGIN_MANAGER_TESTING
           , entry_probe
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

  void drainCompletions() noexcept {
    std::shared_ptr<ScanResult> scan;
    std::array<std::shared_ptr<PreparationResult>, 2> preparations;
    std::array<std::shared_ptr<PermissionResult>, 2> permissions;
    std::array<std::shared_ptr<PermissionResult>, 2> permission_fences;
    {
      std::scoped_lock lock(gate_->mutex);
      scan = std::move(gate_->scan_result);
      preparations = std::move(gate_->preparation_results);
      permissions = std::move(gate_->permission_results);
      permission_fences = std::move(gate_->permission_fences);
    }
    if (scan) {
      gate_->scan_in_flight.store(false);
      acceptScan(std::move(scan->catalog));
    }
    for (auto &result : preparations) {
      if (!result)
        continue;
      --gate_->preparations_in_flight;
      auto *slot = exact(result->plugin, result->epoch);
      if (slot == nullptr || !slot->preparing)
        continue;
      slot->preparing = false;
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
        auto hook = std::make_unique<Hook>(callback_state);
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
    for (auto &result : permission_fences)
      if (result)
        fencePermission(*result);
    for (auto &result : permissions) {
      if (!result)
        continue;
      --gate_->permissions_in_flight;
      completePermission(*result);
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
    requestPreparations();
    armCompletionTimer();
  }

  bool reconcile(
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

  Slot makeSlot(std::string_view plugin) {
    Slot slot;
    slot.plugin = std::string(plugin);
    return slot;
  }

  bool acceptScan(
      std::unique_ptr<channel::ActivationCatalog> candidate) noexcept {
    if (!candidate || !reconcile(std::move(candidate)))
      return false;
    if (!manager_.available_) {
      manager_.available_ = true;
      emit manager_.availableChanged();
    }
    return true;
  }

  void start(Slot &slot) noexcept {
    slot.retry_due.reset();
    slot.epoch = nextEpoch();
    slot.phase = Phase::opening;
    slot.preparing = false;
  }

  void requestPreparations() noexcept {
    constexpr std::uint8_t kMaximumConcurrentPreparations = 2;
    while (gate_->preparations_in_flight.load() <
           kMaximumConcurrentPreparations) {
      auto found = std::ranges::find_if(slots_, [](const Slot &slot) {
        return slot.phase == Phase::opening && !slot.preparing;
      });
      if (found == slots_.end())
        break;
      found->preparing = true;
      bool counted = false;
      try {
        auto result = std::make_shared<PreparationResult>();
        result->plugin = found->plugin;
        result->epoch = found->epoch;
        result->permissions = found->permissions;
        const auto bootstrap = bootstrap_;
        const auto gate = gate_;
#ifdef OMARCHY_PLUGIN_MANAGER_TESTING
        const auto entry_probe = job_entry_probe_;
#endif
        ++gate_->preparations_in_flight;
        counted = true;
        const bool started = submit(
            JobKind::preparation,
            [bootstrap, gate, result
#ifdef OMARCHY_PLUGIN_MANAGER_TESTING
             , entry_probe
#endif
        ] {
#ifdef OMARCHY_PLUGIN_MANAGER_TESTING
              if (entry_probe)
                entry_probe(
                    PluginManagerTestAccess::TestJobKind::preparation);
#endif
              try {
                const plugins::permissions::PluginId plugin(result->plugin);
                if (!result->permissions)
                  result->permissions =
                      bootstrap->open_permissions(result->plugin, plugin);
                if (result->permissions) {
                  auto preparation =
                      bootstrap->prepare_runtime(result->permissions);
                  result->prepared = std::move(preparation.runtime);
                  result->permission_disabled =
                      preparation.status ==
                      channel::PluginRuntimePreparationStatus::permission_disabled;
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
          found->preparing = false;
          break;
        }
      } catch (...) {
        if (counted)
          --gate_->preparations_in_flight;
        found->preparing = false;
        break;
      }
    }
    armCompletionTimer();
  }

  bool beginPermissionRevoke(
      std::string_view plugin, std::uint64_t epoch,
      const plugins::permissions::CapabilityKey &capability,
      std::uint64_t expected_sequence) noexcept {
    try {
      auto result = std::make_shared<PermissionResult>();
      result->kind = PermissionKind::revoke_builtin;
      result->builtin = capability;
      result->expected_sequence = expected_sequence;
      return beginPermissionMutation(plugin, epoch, std::move(result));
    } catch (...) {
      return false;
    }
  }

  std::optional<host_session::AuthorityView>
  permissionView(std::string_view plugin, std::uint64_t epoch) const {
    const auto found = std::ranges::lower_bound(
        slots_, plugin, {}, [](const Slot &slot) { return slot.plugin; });
    return found != slots_.end() && found->plugin == plugin &&
                   found->epoch == epoch && found->permissions &&
                   !found->permission_in_flight
               ? found->permissions->list()
               : std::nullopt;
  }

  std::shared_ptr<const host_session::ConsentReview>
  preparePermissionReview(std::string_view plugin, std::uint64_t epoch) {
    auto *slot = exact(plugin, epoch);
    return slot && slot->permissions && !slot->permission_in_flight
               ? slot->permissions->prepare_review()
                                     : nullptr;
  }

  bool beginPermissionRevoke(
      std::string_view plugin, std::uint64_t epoch,
      const plugins::definitions::CapabilityReference &definition,
      std::uint64_t expected_sequence) noexcept {
    try {
      auto result = std::make_shared<PermissionResult>();
      result->kind = PermissionKind::revoke_dynamic;
      result->dynamic = definition;
      result->expected_sequence = expected_sequence;
      return beginPermissionMutation(plugin, epoch, std::move(result));
    } catch (...) {
      return false;
    }
  }

  bool beginPermissionApply(
      std::string_view plugin, std::uint64_t epoch,
      const host_session::ConsentConfirmation &confirmation,
      std::span<const host_session::BuiltinConsentDecision> builtin_decisions,
      std::span<const host_session::DynamicConsentDecision> dynamic_decisions)
      noexcept {
    try {
      auto result = std::make_shared<PermissionResult>();
      result->kind = PermissionKind::apply_review;
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

  bool beginPermissionMutation(std::string_view plugin, std::uint64_t epoch,
                               std::shared_ptr<PermissionResult> result) noexcept {
    constexpr std::uint8_t kMaximumConcurrentPermissionMutations = 2;
    if (!result || gate_->permissions_in_flight.load() >=
                       kMaximumConcurrentPermissionMutations)
      return false;
    auto *slot = exact(plugin, epoch);
    const bool running = slot &&
                         (slot->phase == Phase::running_unpublished ||
                          slot->phase == Phase::running_published);
    const bool review = result->kind == PermissionKind::apply_review;
    if (!slot || !slot->permissions || slot->permission_in_flight ||
        (review ? !(running || slot->phase == Phase::permission_disabled)
                : !running))
      return false;

    result->plugin = slot->plugin;
    result->permissions = slot->permissions;
    result->epoch = slot->epoch;

    ++gate_->permissions_in_flight;
    const auto gate = gate_;
#ifdef OMARCHY_PLUGIN_MANAGER_TESTING
    const auto entry_probe = job_entry_probe_;
#endif
    bool started = false;
    try {
      started = submit(
          JobKind::permission,
          [gate, result
#ifdef OMARCHY_PLUGIN_MANAGER_TESTING
           , entry_probe
#endif
      ] {
#ifdef OMARCHY_PLUGIN_MANAGER_TESTING
          if (entry_probe)
            entry_probe(PluginManagerTestAccess::TestJobKind::permission);
#endif
          try {
            PermissionFenceObserver observer(gate, result);
            switch (result->kind) {
            case PermissionKind::revoke_builtin:
              result->revocation = result->permissions->revoke(
                  result->builtin, result->expected_sequence, &observer);
              break;
            case PermissionKind::revoke_dynamic:
              result->revocation = result->permissions->revoke(
                  result->dynamic, result->expected_sequence, &observer);
              break;
            case PermissionKind::apply_review:
              result->review = result->permissions->apply_review(
                  result->confirmation, result->builtin_decisions,
                  result->dynamic_decisions, &observer);
              break;
            }
          } catch (...) {
            result->revocation.status =
                host_session::AuthorityMutationResult::io_error;
          }
          try {
            std::scoped_lock lock(gate->mutex);
            if (!gate->canceled.load(std::memory_order_acquire)) {
              const auto empty = std::ranges::find(
                  gate->permission_results,
                  std::shared_ptr<PermissionResult>{});
              if (empty == gate->permission_results.end())
                std::terminate();
              *empty = std::move(result);
            } else {
              --gate->permissions_in_flight;
            }
          } catch (...) {
            std::terminate();
          }
          });
    } catch (...) {
      --gate_->permissions_in_flight;
      return false;
    }
    if (!started) {
      --gate_->permissions_in_flight;
      return false;
    }
    slot->permission_in_flight = true;
    slot->permission_epoch = result->epoch;
    armCompletionTimer();
    return true;
  }

  Slot *permissionSlot(const PermissionResult &result) noexcept {
    const auto found = std::ranges::lower_bound(
        slots_, result.plugin, {}, [](const Slot &slot) { return slot.plugin; });
    return found != slots_.end() && found->plugin == result.plugin &&
                   found->permission_in_flight &&
                   found->permission_epoch == result.epoch &&
                   found->permissions == result.permissions
               ? &*found
               : nullptr;
  }

  void fencePermission(const PermissionResult &result) noexcept {
    auto *slot = permissionSlot(result);
    if (!slot || slot->phase == Phase::permission_changing)
      return;
    slot->epoch = nextEpoch();
    slot->phase = Phase::permission_changing;
    slot->preparing = false;
    withdraw(*slot);
  }

  void completePermission(const PermissionResult &result) noexcept {
    auto *slot = permissionSlot(result);
    if (!slot || !slot->permission_in_flight ||
        slot->permissions != result.permissions)
      return;
    slot->permission_in_flight = false;
    slot->permission_epoch = 0;
    std::optional<plugins::permissions::ActivationBinding> binding;
    bool applied = false;
    if (result.kind == PermissionKind::apply_review) {
      if (result.review.publication != host_session::ConsentResult::applied) {
        if (slot->phase == Phase::permission_changing)
          disable(*slot);
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
        if (slot->phase == Phase::permission_changing)
          disable(*slot);
        return;
      }
      if (result.revocation.activatable)
        binding = result.revocation.binding;
    }
    if (!applied || !binding) {
      disable(*slot);
      return;
    }
    stopRuntime(*slot);
    slot->expected_binding = std::move(binding);
    start(*slot);
  }

  void withdraw(Slot &slot) noexcept {
    if (!slot.endpoint_owner)
      return;
    slot.endpoint_owner->close_all();
    try {
      static_cast<void>(manager_.surfaces_.withdrawSurfaces(
          slot.endpoint_owner->binding_));
    } catch (...) {
    }
    slot.endpoint_owner.reset();
  }

  void disable(Slot &slot) noexcept {
    stopRuntime(slot);
    slot.expected_binding.reset();
    slot.retry_attempts = 0;
    slot.retry_due.reset();
    slot.phase = Phase::permission_disabled;
  }

  template <typename Job>
  bool submit(JobKind kind, Job &&job) {
#ifdef OMARCHY_PLUGIN_MANAGER_TESTING
    if (job_submitter_)
      return job_submitter_(kind == JobKind::scan
                                ? PluginManagerTestAccess::TestJobKind::scan
                                : kind == JobKind::preparation
                                      ? PluginManagerTestAccess::TestJobKind::preparation
                                      : PluginManagerTestAccess::TestJobKind::permission,
                            std::function<void()>(std::forward<Job>(job)));
#endif
    (void)kind;
    return QThreadPool::globalInstance()->tryStart(std::forward<Job>(job));
  }

  void armCompletionTimer() noexcept {
#ifdef OMARCHY_PLUGIN_MANAGER_TESTING
    if (manual_test_)
      return;
#endif
    const bool active = gate_->scan_in_flight.load() != 0 ||
                        gate_->preparations_in_flight.load() != 0 ||
                        gate_->permissions_in_flight.load() != 0 ||
                        std::ranges::any_of(slots_, [](const Slot &slot) {
                          return slot.phase == Phase::opening ||
                                 slot.phase == Phase::starting;
                        });
    const bool monitoring = std::ranges::any_of(
        slots_, [](const Slot &slot) { return slot.callback_state != nullptr; });
    if (!active && !monitoring) {
      completion_timer_.stop();
      return;
    }
    const int interval = active ? kActiveCompletionIntervalMilliseconds
                                : kIdleCompletionIntervalMilliseconds;
    if (!completion_timer_.isActive() ||
        completion_timer_.interval() != interval)
      completion_timer_.start(interval);
  }

  void stateChanged(std::string_view plugin, std::uint64_t epoch,
                    host_session::SessionState state,
                    host_session::SessionError error) noexcept {
    auto *slot = exact(plugin, epoch);
    if (slot == nullptr)
      return;
#ifdef OMARCHY_PLUGIN_MANAGER_TESTING
    slot->last_state = static_cast<std::uint8_t>(state);
    slot->last_error = static_cast<std::uint8_t>(error);
#endif
    if (state == host_session::SessionState::running &&
        error == host_session::SessionError::none) {
      try {
        const plugins::permissions::PluginId expected(slot->plugin);
        const auto binding =
            slot->root ? slot->root->session_binding() : std::nullopt;
        if (!binding || binding->plugin != expected) {
          if (slot->expected_binding)
            disable(*slot);
          else
            fail(*slot);
          return;
        }
        if (slot->expected_binding && *binding != *slot->expected_binding) {
          disable(*slot);
          return;
        }
        slot->expected_binding.reset();
        slot->phase = Phase::running_unpublished;
        slot->retry_attempts = 0;
      } catch (...) {
        fail(*slot);
      }
      return;
    }
    if (state == host_session::SessionState::failed ||
        state == host_session::SessionState::stopped ||
        state == host_session::SessionState::revoked) {
      if (slot->expected_binding)
        disable(*slot);
      else
        fail(*slot);
    }
  }

  bool publishReady(
      std::string_view plugin, std::uint64_t epoch,
      const plugins::permissions::ActivationBinding &binding,
      std::vector<SurfaceProjectionModel::SurfaceDeclaration> declarations)
      noexcept {
    if (QThread::currentThread() != manager_.thread() || epoch == 0)
      return false;
    auto *slot = exact(plugin, epoch);
    if (slot == nullptr || slot->phase != Phase::running_unpublished ||
        slot->plugin != binding.plugin.view() || !slot->root || !slot->hook ||
        slot->endpoint_owner ||
        (slot->expected_binding && *slot->expected_binding != binding))
      return false;
    const auto rollback = [&]() noexcept {
      slot->phase = Phase::running_unpublished;
      if (slot->endpoint_owner)
        slot->endpoint_owner->close_all();
      try {
        static_cast<void>(manager_.surfaces_.withdrawSurfaces(binding));
      } catch (...) {
      }
      slot->endpoint_owner.reset();
    };
    try {
      const auto live_binding = slot->root->session_binding();
      if (!live_binding || *live_binding != binding)
        return false;
      auto owner = std::unique_ptr<SurfaceEndpointOwner>(new SurfaceEndpointOwner(
          clock_, binding, epoch, slot->root->surface_session()));
      slot->endpoint_owner = std::move(owner);
      slot->phase = Phase::running_published;
      if (!manager_.surfaces_.publishSurfaces(binding, std::move(declarations),
                                              epoch)) {
        rollback();
        return false;
      }
      return true;
    } catch (...) {
      rollback();
      return false;
    }
  }

  Slot *exact(std::string_view plugin, std::uint64_t epoch) noexcept {
    const auto found = std::ranges::lower_bound(
        slots_, plugin, {}, [](const Slot &slot) { return slot.plugin; });
    return found != slots_.end() && found->plugin == plugin &&
                   found->epoch == epoch
               ? &*found
               : nullptr;
  }

  void fail(Slot &slot) noexcept {
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

  void retryDue() noexcept {
    const auto now = Clock::now();
    for (auto &slot : slots_)
      if (slot.phase == Phase::retry_wait && slot.retry_due &&
          *slot.retry_due <= now)
        start(slot);
    armRetryTimer();
    requestPreparations();
  }

  void armRetryTimer() noexcept {
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
    const auto remaining =
        std::chrono::duration_cast<std::chrono::milliseconds>(*earliest -
                                                              Clock::now());
    retry_timer_.start(
        static_cast<int>(std::max<std::int64_t>(1, remaining.count())));
  }

  void stopRuntime(Slot &slot) noexcept {
    slot.phase = Phase::stopping;
    slot.epoch = nextEpoch();
    slot.retry_due.reset();
    slot.preparing = false;
    slot.permission_in_flight = false;
    slot.permission_epoch = 0;
    withdraw(slot);
    slot.root.reset();
    slot.hook.reset();
    slot.callback_state.reset();
  }

  std::uint64_t nextEpoch() noexcept {
    if (next_epoch_ == std::numeric_limits<std::uint64_t>::max())
      std::terminate();
    return ++next_epoch_;
  }

  PluginManager &manager_;
  std::shared_ptr<const channel::RuntimeBootstrap> bootstrap_;
  std::shared_ptr<DeliveryGate> gate_ = std::make_shared<DeliveryGate>();
  std::unique_ptr<channel::ActivationCatalog> catalog_;
  ManagerMonotonicClock clock_;
  std::vector<Slot> slots_;
  QTimer scan_timer_;
  QTimer retry_timer_;
  QTimer completion_timer_;
  std::uint64_t next_epoch_ = 0;
#ifdef OMARCHY_PLUGIN_MANAGER_TESTING
  bool manual_test_ = false;
  PluginManagerTestAccess::JobSubmitter job_submitter_;
  PluginManagerTestAccess::JobEntryProbe job_entry_probe_;
#endif
};

#ifdef OMARCHY_PLUGIN_MANAGER_TESTING
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
    manager.runtime_ = std::unique_ptr<PluginManager::Runtime>(
        new PluginManager::Runtime(manager, std::move(bootstrap),
                                   PluginManager::Runtime::ManualTestTag{}));
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
    result.push_back({.plugin = slot.plugin,
                      .epoch = slot.epoch,
                      .retry_attempts = slot.retry_attempts,
                      .retry_wait = slot.phase ==
                                    PluginManager::Runtime::Phase::retry_wait,
                      .opening = slot.phase ==
                                 PluginManager::Runtime::Phase::opening,
                      .starting = slot.phase ==
                                  PluginManager::Runtime::Phase::starting,
                      .preparing = slot.preparing,
                      .running_unpublished =
                          slot.phase == PluginManager::Runtime::Phase::running_unpublished,
                      .running_published =
                          slot.phase == PluginManager::Runtime::Phase::running_published,
                      .permission_in_flight = slot.permission_in_flight,
                      .permission_changing =
                          slot.phase == PluginManager::Runtime::Phase::permission_changing,
                      .permission_disabled =
                          slot.phase == PluginManager::Runtime::Phase::permission_disabled,
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
      [](const PluginManager::Runtime::Slot &slot) { return slot.plugin; });
  if (found == manager.runtime_->slots_.end() || found->plugin != plugin ||
      found->phase != PluginManager::Runtime::Phase::retry_wait)
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
      [](const PluginManager::Runtime::Slot &slot) { return slot.plugin; });
  if (found == manager.runtime_->slots_.end() || found->plugin != plugin)
    return false;
  try {
    auto state = std::make_shared<PluginManager::Runtime::HookState>(
        found->plugin, found->epoch);
    found->callback_state = state;
    PluginManager::Runtime::Hook hook(std::move(state));
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

std::uint8_t
PluginManagerTestAccess::preparationCount(const PluginManager &manager) {
  return manager.runtime_
             ? manager.runtime_->gate_->preparations_in_flight.load()
             : 0;
}

std::uint8_t
PluginManagerTestAccess::permissionCount(const PluginManager &manager) {
  return manager.runtime_
             ? manager.runtime_->gate_->permissions_in_flight.load()
             : 0;
}

bool PluginManagerTestAccess::scanInFlight(const PluginManager &manager) {
  return manager.runtime_ && manager.runtime_->gate_->scan_in_flight.load();
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

bool PluginManagerTestAccess::deliverLifecycle(
    PluginManager &manager, std::string_view plugin, std::uint64_t epoch,
    std::uint8_t state, std::uint8_t error) {
  if (!manager.runtime_)
    return false;
  auto *slot = manager.runtime_->exact(plugin, epoch);
  if (!slot)
    return false;
  try {
    if (!slot->callback_state)
      slot->callback_state =
          std::make_shared<PluginManager::Runtime::HookState>(slot->plugin,
                                                              slot->epoch);
    PluginManager::Runtime::Hook hook(slot->callback_state);
    hook.state_changed(static_cast<host_session::SessionState>(state),
                       static_cast<host_session::SessionError>(error));
    return true;
  } catch (...) {
    return false;
  }
}

bool PluginManagerTestAccess::publishReady(
    PluginManager &manager, std::string_view plugin, std::uint64_t epoch,
    const plugins::permissions::ActivationBinding &binding,
    std::vector<SurfaceProjectionModel::SurfaceDeclaration> declarations) {
  return manager.runtime_ && manager.runtime_->publishReady(
                                 plugin, epoch, binding,
                                 std::move(declarations));
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
    const host_session::ConsentConfirmation &confirmation,
    std::span<const host_session::BuiltinConsentDecision> builtin_decisions,
    std::span<const host_session::DynamicConsentDecision> dynamic_decisions) {
  return manager.runtime_ && manager.runtime_->beginPermissionApply(
                                 plugin, epoch, confirmation, builtin_decisions,
                                 dynamic_decisions);
}

std::weak_ptr<const void>
PluginManagerTestAccess::deliveryGate(const PluginManager &manager) {
  return manager.runtime_
             ? std::weak_ptr<const void>(manager.runtime_->gate_)
             : std::weak_ptr<const void>{};
}

void PluginManagerTestAccess::failNextConstruction() noexcept {
  fail_next_manager_construction.store(true, std::memory_order_release);
}

bool PluginManagerTestAccess::processClaimAvailable() noexcept {
  return claimed_engine.load(std::memory_order_acquire) == nullptr;
}
#endif

PluginManager::ProcessClaim::ProcessClaim(QQmlEngine *engine) noexcept
    : engine_(engine) {}

PluginManager::ProcessClaim::ProcessClaim(ProcessClaim &&other) noexcept
    : engine_(std::exchange(other.engine_, nullptr)) {}

PluginManager::ProcessClaim::~ProcessClaim() noexcept {
  if (!engine_)
    return;
  QQmlEngine *expected = engine_;
  if (!claimed_engine.compare_exchange_strong(expected, nullptr,
                                              std::memory_order_acq_rel,
                                              std::memory_order_acquire))
    std::terminate();
}

PluginManager *PluginManager::create(QQmlEngine *qml_engine,
                                     QJSEngine *js_engine) noexcept {
  if (!qml_engine || !js_engine ||
      js_engine != static_cast<QJSEngine *>(qml_engine) ||
      qml_engine->thread() != QThread::currentThread())
    return nullptr;

  QQmlEngine *expected = nullptr;
  if (!claimed_engine.compare_exchange_strong(expected, qml_engine,
                                              std::memory_order_acq_rel,
                                              std::memory_order_acquire))
    return nullptr;

  ProcessClaim claim(qml_engine);
  try {
    return new PluginManager(qml_engine, std::move(claim));
  } catch (...) {
    return nullptr;
  }
}

PluginManager::PluginManager(QObject *parent, ProcessClaim claim)
    : QObject(parent), process_claim_(std::move(claim)), surfaces_(this) {
#ifdef OMARCHY_PLUGIN_MANAGER_TESTING
  if (fail_next_manager_construction.exchange(false, std::memory_order_acq_rel))
    throw std::bad_alloc();
#endif
  connect(&surfaces_, &SurfaceProjectionModel::surfacesChanged, this,
          &PluginManager::surfacesChanged);
  connect(&surfaces_, &SurfaceProjectionModel::openRequested, this,
          &PluginManager::openRequested);
  connect(&surfaces_, &SurfaceProjectionModel::toggleRequested, this,
          &PluginManager::toggleRequested);
  connect(&surfaces_, &SurfaceProjectionModel::dismissRequested, this,
          &PluginManager::dismissRequested);
#ifndef OMARCHY_PLUGIN_MANAGER_TESTING
  // Trust roots and definitions are immutable for this singleton lifetime.
  // Installation/update provisions them before an explicit shell restart.
  runtime_ = Runtime::open(*this);
#endif
}

PluginManager::~PluginManager() = default;

bool PluginManager::available() const noexcept { return available_; }

QString PluginManager::runtimeVersion() const {
  const std::string_view version = plugin_runtime::build_version();
  return QString::fromLatin1(version.data(),
                             static_cast<qsizetype>(version.size()));
}

QAbstractItemModel *PluginManager::barSurfaces() {
  return surfaces_.barSurfaces();
}

QAbstractItemModel *PluginManager::panelSurfaces() {
  return surfaces_.panelSurfaces();
}

QAbstractItemModel *PluginManager::overlaySurfaces() {
  return surfaces_.overlaySurfaces();
}

int PluginManager::count() const noexcept { return surfaces_.count(); }

bool PluginManager::attach(const QString &surface_key,
                           QObject *surface) noexcept {
  constexpr qsizetype kMaximumPublishedSurfaceKeyCharacters = 512;
  if (QThread::currentThread() != thread() || !runtime_ || !surface ||
      surface_key.isEmpty() ||
      surface_key.size() > kMaximumPublishedSurfaceKeyCharacters)
    return false;
  auto *remote = qobject_cast<RemotePluginSurface *>(surface);
  if (!remote)
    return false;
  try {
    auto published = surfaces_.resolve(surface_key);
    if (!published)
      return false;
    const auto plugin = published->binding_.plugin.view();
    const auto found = std::ranges::lower_bound(
        runtime_->slots_, plugin, {},
        [](const Runtime::Slot &slot) { return slot.plugin; });
    if (found == runtime_->slots_.end() || found->plugin != plugin ||
        found->phase != Runtime::Phase::running_published ||
        found->epoch != published->publication_revision_ || !found->root ||
        !found->endpoint_owner)
      return false;
    const auto binding = found->root->session_binding();
    if (!binding || *binding != published->binding_)
      return false;
    return found->endpoint_owner->attach(*published, surface_key, *remote) ==
           SurfaceEndpointAttachResult::attached;
  } catch (...) {
    return false;
  }
}

bool PluginManager::publishIntent(host_session::AdmittedSurfaceIntent intent) {
  return surfaces_.publishIntent(std::move(intent));
}

} // namespace omarchy::plugin_runtime::bridge
