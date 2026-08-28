#include "supervisor_health.hpp"

#include <algorithm>
#include <limits>
#include <stdexcept>
#include <utility>

namespace omarchy::plugin_runtime::health {

struct HealthSupervisor::Request {
  std::uint64_t correlation = 0;
  std::uint64_t deadline = 0;
  bool occupied = false;
};

struct HealthSupervisor::Slot {
  permissions::ActivationBinding binding;
  std::unique_ptr<WorkerControl> worker;
  std::array<Request, 32> requests{};
  std::array<surface::SurfaceKey, 16> surfaces{};
  std::array<bool, 16> surface_occupied{};
  std::size_t request_count = 0;
  std::size_t surface_count = 0;
  std::uint64_t startup_deadline = 0;
  std::uint64_t healthy_since = 0;
  std::uint64_t request_window_started = 0;
  std::size_t request_starts = 0;
  bool ready = false;
  bool active = false;
  bool candidate = false;
};

struct HealthSupervisor::CrashState {
  permissions::PluginId plugin;
  permissions::Digest revision;
  std::array<std::uint64_t, 16> times{};
  std::size_t count = 0;
  std::uint64_t retry_at = 0;
  bool disabled = false;
};

namespace {

bool add_deadline(std::uint64_t now, std::uint64_t duration,
                  std::uint64_t &output) {
  if (duration > std::numeric_limits<std::uint64_t>::max() - now)
    return false;
  output = now + duration;
  return true;
}

bool identity_matches(const launcher::LaunchIdentity &identity,
                      const permissions::ActivationBinding &binding) {
  return identity.plugin_id == binding.plugin.view() &&
         identity.revision_sha256 == binding.revision.view() &&
         identity.generation == binding.generation;
}

} // namespace

LauncherWorkerControl::LauncherWorkerControl(
    std::unique_ptr<launcher::Worker> worker)
    : worker_(std::move(worker)) {
  if (!worker_)
    throw std::invalid_argument("launcher worker is absent");
}

const launcher::LaunchIdentity &LauncherWorkerControl::identity() const {
  return worker_->identity();
}

bool LauncherWorkerControl::alive() const { return worker_->alive(); }

bool LauncherWorkerControl::terminate() { return worker_->terminate(); }

HealthSupervisor::HealthSupervisor(HealthPolicy policy,
                                   audit::AuditStore &audit_store)
    : policy_(policy), audit_(audit_store) {
  if (policy_.maximum_workers == 0 ||
      policy_.maximum_workers > kMaximumManagedWorkers ||
      policy_.maximum_requests_per_worker == 0 ||
      policy_.maximum_requests_per_worker > 32 ||
      policy_.maximum_requests_global == 0 ||
      policy_.maximum_requests_global > kMaximumTrackedRequests ||
      policy_.maximum_surfaces_per_worker == 0 ||
      policy_.maximum_surfaces_per_worker > 16 ||
      policy_.maximum_surfaces_global == 0 ||
      policy_.maximum_surfaces_global > kMaximumManagedWorkers * 16 ||
      policy_.maximum_request_bytes == 0 ||
      policy_.maximum_request_starts_per_window == 0 ||
      policy_.request_rate_window_seconds == 0 ||
      policy_.memory_max_bytes == 0 || policy_.scratch_max_bytes == 0 ||
      policy_.tasks_max == 0 || policy_.hello_timeout_seconds == 0 ||
      policy_.request_timeout_seconds == 0 ||
      policy_.restart_window_seconds == 0 || policy_.restart_burst == 0 ||
      policy_.restart_burst > 16 ||
      policy_.restart_backoff_initial_seconds == 0 ||
      policy_.restart_backoff_max_seconds == 0 ||
      policy_.restart_backoff_initial_seconds >
          policy_.restart_backoff_max_seconds ||
      policy_.restart_backoff_max_seconds >
          static_cast<std::uint64_t>(
              std::numeric_limits<std::int64_t>::max()) ||
      policy_.stable_reset_seconds == 0)
    throw std::invalid_argument("invalid bounded health policy");
  failed_ = !audit_.recover().ok();
  if (!failed_)
    failed_ = !recover_unresolved_workers();
}

HealthSupervisor::~HealthSupervisor() {
  for (auto &slot : slots_) {
    if (slot && slot->worker)
      (void)slot->worker->terminate();
  }
}

Status HealthSupervisor::adopt(std::unique_ptr<WorkerControl> worker,
                               const permissions::ActivationBinding &binding,
                               std::uint64_t now_seconds) {
  return adopt_impl(std::move(worker), binding, now_seconds, false);
}

Status
HealthSupervisor::adopt_candidate(std::unique_ptr<WorkerControl> worker,
                                  const permissions::ActivationBinding &binding,
                                  std::uint64_t now_seconds) {
  return adopt_impl(std::move(worker), binding, now_seconds, true);
}

Status
HealthSupervisor::adopt_impl(std::unique_ptr<WorkerControl> worker,
                             const permissions::ActivationBinding &binding,
                             std::uint64_t now_seconds, bool candidate) {
  if (failed_) {
    if (worker)
      (void)worker->terminate();
    return Status::audit_failed;
  }
  if (!worker)
    return Status::denied;
  if (!identity_matches(worker->identity(), binding) || !worker->alive()) {
    (void)worker->terminate();
    return Status::denied;
  }
  const auto restart =
      restart_decision(binding.plugin, binding.revision, now_seconds);
  if (restart.status != Status::accepted) {
    (void)worker->terminate();
    return restart.status;
  }
  for (const auto &slot : slots_) {
    if (slot && slot->active &&
        (slot->binding == binding || (slot->binding.plugin == binding.plugin &&
                                      slot->candidate == candidate))) {
      (void)worker->terminate();
      return Status::duplicate;
    }
  }
  if (workers_ >= policy_.maximum_workers) {
    (void)worker->terminate();
    return Status::limit_exceeded;
  }
  auto target = std::find_if(slots_.begin(), slots_.end(),
                             [](const auto &slot) { return !slot; });
  std::uint64_t deadline = 0;
  if (target == slots_.end() ||
      !add_deadline(now_seconds, policy_.hello_timeout_seconds, deadline)) {
    (void)worker->terminate();
    return Status::limit_exceeded;
  }
  auto slot = std::make_unique<Slot>();
  slot->binding = binding;
  slot->worker = std::move(worker);
  slot->startup_deadline = deadline;
  slot->active = true;
  slot->candidate = candidate;
  *target = std::move(slot);
  ++workers_;
  if (!append(permissions::AuditEvent::worker_started,
              permissions::AuditOutcome::allowed, binding,
              permissions::GrantDecisionCode::allowed)) {
    auto &inserted = **target;
    clear_slot(inserted);
    const bool terminated = inserted.worker && inserted.worker->terminate();
    if (terminated)
      target->reset();
    return Status::audit_failed;
  }
  return Status::accepted;
}

Status HealthSupervisor::ready(const permissions::ActivationBinding &binding,
                               std::uint64_t now_seconds) {
  auto *slot = find(binding);
  if (slot == nullptr)
    return Status::stale_generation;
  if (slot->ready)
    return Status::duplicate;
  if (!slot->worker->alive() || now_seconds > slot->startup_deadline)
    return fail_slot(*slot, now_seconds,
                     permissions::AuditEvent::worker_health);
  if (!append(permissions::AuditEvent::worker_health,
              permissions::AuditOutcome::allowed, binding,
              permissions::GrantDecisionCode::allowed))
    return fail_slot(*slot, now_seconds,
                     permissions::AuditEvent::worker_health);
  slot->ready = true;
  slot->healthy_since = now_seconds;
  slot->request_window_started = now_seconds;
  slot->request_starts = 0;
  return Status::accepted;
}

Status HealthSupervisor::admit_request(
    const permissions::ActivationBinding &binding, std::uint64_t correlation,
    std::size_t request_bytes, std::uint64_t now_seconds) {
  auto *slot = find(binding);
  if (slot == nullptr)
    return Status::stale_generation;
  if (!slot->ready)
    return Status::not_ready;
  if (slot->candidate)
    return Status::not_ready;
  if (correlation == 0 || request_bytes > policy_.maximum_request_bytes)
    return Status::denied;
  if (now_seconds < slot->request_window_started)
    return fail_slot(*slot, now_seconds,
                     permissions::AuditEvent::worker_health);
  if (now_seconds - slot->request_window_started >=
      policy_.request_rate_window_seconds) {
    slot->request_window_started = now_seconds;
    slot->request_starts = 0;
  }
  if (slot->request_starts >= policy_.maximum_request_starts_per_window)
    return fail_slot(*slot, now_seconds,
                     permissions::AuditEvent::worker_health);
  if (std::any_of(slot->requests.begin(), slot->requests.end(),
                  [correlation](const auto &request) {
                    return request.occupied &&
                           request.correlation == correlation;
                  }))
    return Status::duplicate;
  if (slot->request_count >= policy_.maximum_requests_per_worker ||
      requests_ >= policy_.maximum_requests_global)
    return Status::limit_exceeded;
  auto request =
      std::find_if(slot->requests.begin(), slot->requests.end(),
                   [](const auto &entry) { return !entry.occupied; });
  std::uint64_t deadline = 0;
  if (request == slot->requests.end() ||
      !add_deadline(now_seconds, policy_.request_timeout_seconds, deadline))
    return Status::limit_exceeded;
  *request = {
      .correlation = correlation, .deadline = deadline, .occupied = true};
  ++slot->request_count;
  ++requests_;
  ++slot->request_starts;
  return Status::accepted;
}

Status HealthSupervisor::complete_request(
    const permissions::ActivationBinding &binding, std::uint64_t correlation) {
  auto *slot = find(binding);
  if (slot == nullptr)
    return Status::stale_generation;
  auto request =
      std::find_if(slot->requests.begin(), slot->requests.end(),
                   [correlation](const auto &entry) {
                     return entry.occupied && entry.correlation == correlation;
                   });
  if (request == slot->requests.end())
    return Status::denied;
  *request = {};
  --slot->request_count;
  --requests_;
  return Status::accepted;
}

Status
HealthSupervisor::open_surface(const permissions::ActivationBinding &binding,
                               surface::SurfaceKey key) {
  auto *slot = find(binding);
  if (slot == nullptr)
    return Status::stale_generation;
  if (!slot->ready)
    return Status::not_ready;
  if (slot->candidate)
    return Status::not_ready;
  if (key.generation != binding.generation)
    return Status::stale_generation;
  if (key.id == 0)
    return Status::denied;
  for (std::size_t index = 0; index < slot->surfaces.size(); ++index) {
    if (slot->surface_occupied[index] && slot->surfaces[index] == key)
      return Status::duplicate;
  }
  if (slot->surface_count >= policy_.maximum_surfaces_per_worker ||
      surfaces_ >= policy_.maximum_surfaces_global)
    return Status::limit_exceeded;
  const auto free = std::find(slot->surface_occupied.begin(),
                              slot->surface_occupied.end(), false);
  if (free == slot->surface_occupied.end())
    return Status::limit_exceeded;
  const auto index = static_cast<std::size_t>(
      std::distance(slot->surface_occupied.begin(), free));
  slot->surfaces[index] = key;
  slot->surface_occupied[index] = true;
  ++slot->surface_count;
  ++surfaces_;
  return Status::accepted;
}

Status
HealthSupervisor::close_surface(const permissions::ActivationBinding &binding,
                                surface::SurfaceKey key) {
  auto *slot = find(binding);
  if (slot == nullptr)
    return Status::stale_generation;
  if (key.generation != binding.generation)
    return Status::stale_generation;
  std::size_t index = 0;
  for (; index < slot->surfaces.size(); ++index) {
    if (slot->surface_occupied[index] && slot->surfaces[index] == key)
      break;
  }
  if (index == slot->surfaces.size())
    return Status::denied;
  slot->surface_occupied[index] = false;
  slot->surfaces[index] = {};
  --slot->surface_count;
  --surfaces_;
  return Status::accepted;
}

Status HealthSupervisor::observe_resources(
    const permissions::ActivationBinding &binding, ResourceSample sample,
    std::uint64_t now_seconds) {
  auto *slot = find(binding);
  if (slot == nullptr)
    return Status::stale_generation;
  if (sample.memory_bytes > policy_.memory_max_bytes ||
      sample.scratch_bytes > policy_.scratch_max_bytes ||
      sample.tasks > policy_.tasks_max)
    return fail_slot(*slot, now_seconds,
                     permissions::AuditEvent::worker_health);
  return Status::accepted;
}

void HealthSupervisor::tick(std::uint64_t now_seconds) {
  if (failed_)
    return;
  for (std::size_t index = 0; index < slots_.size(); ++index) {
    auto *slot = slots_[index].get();
    if (slot == nullptr || !slot->active)
      continue;
    bool expired = !slot->worker->alive() ||
                   (!slot->ready && now_seconds > slot->startup_deadline);
    if (!expired && slot->ready) {
      expired = std::any_of(slot->requests.begin(), slot->requests.end(),
                            [now_seconds](const auto &request) {
                              return request.occupied &&
                                     now_seconds > request.deadline;
                            });
    }
    if (expired) {
      (void)fail_slot(*slot, now_seconds,
                      permissions::AuditEvent::worker_crashed);
      continue;
    }
    if (slot->ready && now_seconds >= slot->healthy_since &&
        now_seconds - slot->healthy_since >= policy_.stable_reset_seconds) {
      for (auto &state : crashes_) {
        if (state && state->plugin == slot->binding.plugin &&
            state->revision == slot->binding.revision) {
          state.reset();
          break;
        }
      }
    }
  }
}

Status
HealthSupervisor::worker_exited(const permissions::ActivationBinding &binding,
                                std::uint64_t now_seconds) {
  auto *slot = find(binding);
  if (slot == nullptr)
    return Status::stale_generation;
  if (slot->worker->alive())
    return Status::denied;
  return fail_slot(*slot, now_seconds, permissions::AuditEvent::worker_crashed);
}

Status HealthSupervisor::stop(const permissions::ActivationBinding &binding) {
  auto *slot = find(binding);
  if (slot == nullptr)
    return Status::stale_generation;
  const auto saved = slot->binding;
  clear_slot(*slot);
  const bool terminated = slot->worker && slot->worker->terminate();
  for (auto &entry : slots_) {
    if (entry.get() == slot) {
      if (terminated)
        entry.reset();
      break;
    }
  }
  const bool audited =
      append(permissions::AuditEvent::worker_stopped,
             terminated ? permissions::AuditOutcome::allowed
                        : permissions::AuditOutcome::failed,
             saved,
             terminated ? permissions::GrantDecisionCode::allowed
                        : permissions::GrantDecisionCode::ungranted);
  if (!terminated)
    failed_ = true;
  if (!audited)
    return Status::audit_failed;
  return terminated ? Status::accepted : Status::teardown_failed;
}

Status HealthSupervisor::promote_candidate(
    const permissions::ActivationBinding &binding) {
  auto *candidate = find(binding);
  if (candidate == nullptr || !candidate->candidate)
    return Status::stale_generation;
  if (!candidate->ready || !candidate->worker->alive())
    return Status::not_ready;
  std::optional<permissions::ActivationBinding> prior;
  for (const auto &slot : slots_) {
    if (slot && slot->active && !slot->candidate &&
        slot->binding.plugin == binding.plugin) {
      prior = slot->binding;
      break;
    }
  }
  if (prior) {
    const auto stopped = stop(*prior);
    if (stopped != Status::accepted) {
      auto *still_candidate = find(binding);
      if (still_candidate != nullptr) {
        clear_slot(*still_candidate);
        (void)still_candidate->worker->terminate();
      }
      return stopped;
    }
  }
  candidate = find(binding);
  if (candidate == nullptr || failed_)
    return failed_ ? Status::audit_failed : Status::stale_generation;
  candidate->candidate = false;
  return Status::accepted;
}

RestartDecision
HealthSupervisor::restart_decision(const permissions::PluginId &plugin,
                                   const permissions::Digest &revision,
                                   std::uint64_t now_seconds) const {
  if (failed_)
    return {.status = Status::audit_failed};
  for (const auto &state : crashes_) {
    if (!state || state->plugin != plugin || state->revision != revision)
      continue;
    if (state->disabled)
      return {.status = Status::disabled};
    if (now_seconds < state->retry_at)
      return {.status = Status::backoff,
              .retry_after_seconds = state->retry_at - now_seconds};
    break;
  }
  return {.status = Status::accepted};
}

std::size_t HealthSupervisor::worker_count() const { return workers_; }
std::size_t HealthSupervisor::request_count() const { return requests_; }
std::size_t HealthSupervisor::surface_count() const { return surfaces_; }

HealthSupervisor::Slot *
HealthSupervisor::find(const permissions::ActivationBinding &binding) {
  for (auto &slot : slots_) {
    if (slot && slot->active && slot->binding == binding)
      return slot.get();
  }
  return nullptr;
}

const HealthSupervisor::Slot *
HealthSupervisor::find(const permissions::ActivationBinding &binding) const {
  for (const auto &slot : slots_) {
    if (slot && slot->active && slot->binding == binding)
      return slot.get();
  }
  return nullptr;
}

HealthSupervisor::CrashState *
HealthSupervisor::crash_state(const permissions::PluginId &plugin,
                              const permissions::Digest &revision,
                              bool create) {
  for (auto &state : crashes_) {
    if (state && state->plugin == plugin && state->revision == revision)
      return state.get();
  }
  if (!create)
    return nullptr;
  auto target = std::find_if(crashes_.begin(), crashes_.end(),
                             [](const auto &state) { return !state; });
  if (target == crashes_.end())
    return nullptr;
  *target = std::make_unique<CrashState>();
  (*target)->plugin = plugin;
  (*target)->revision = revision;
  return target->get();
}

bool HealthSupervisor::recover_unresolved_workers() {
  audit::Query query;
  query.producer = permissions::AuditProducer::supervisor;
  query.maximum_results = audit::kHardMaximumRecords;
  const auto result = audit_.query(query);
  if (!result.status.ok())
    return false;
  for (const auto &record : result.records) {
    bool unresolved = false;
    switch (record.event) {
    case permissions::AuditEvent::worker_started:
    case permissions::AuditEvent::worker_health:
    case permissions::AuditEvent::worker_crashed:
    case permissions::AuditEvent::worker_disabled:
      unresolved = true;
      break;
    case permissions::AuditEvent::worker_stopped:
      unresolved = record.outcome != permissions::AuditOutcome::allowed;
      break;
    default:
      continue;
    }
    if (!unresolved) {
      for (auto &state : crashes_) {
        if (state && state->plugin == record.plugin &&
            state->revision == record.revision) {
          state.reset();
          break;
        }
      }
      continue;
    }
    auto *state = crash_state(record.plugin, record.revision, true);
    if (state == nullptr)
      return false;
    state->count = policy_.restart_burst;
    state->disabled = true;
  }
  return true;
}

bool HealthSupervisor::append(permissions::AuditEvent event,
                              permissions::AuditOutcome outcome,
                              const permissions::ActivationBinding &binding,
                              permissions::GrantDecisionCode decision,
                              std::uint64_t retry_after,
                              std::uint64_t item_count) {
  permissions::AuditDraft draft{.event = event,
                                .outcome = outcome,
                                .plugin = binding.plugin,
                                .revision = binding.revision,
                                .generation = binding.generation,
                                .correlation = 0,
                                .operation = std::nullopt,
                                .capability = std::nullopt,
                                .decision = decision,
                                .metadata = {}};
  if (retry_after > 0)
    draft.metadata.push_back({permissions::AuditMetric::retry_after_seconds,
                              static_cast<std::int64_t>(retry_after)});
  if (item_count > 0)
    draft.metadata.push_back({permissions::AuditMetric::item_count,
                              static_cast<std::int64_t>(item_count)});
  const auto result =
      audit_.append(permissions::AuditProducer::supervisor, std::move(draft));
  if (!result.status.ok())
    failed_ = true;
  return result.status.ok();
}

Status HealthSupervisor::fail_slot(Slot &slot, std::uint64_t now_seconds,
                                   permissions::AuditEvent event) {
  const auto binding = slot.binding;
  clear_slot(slot);
  auto *state = crash_state(binding.plugin, binding.revision, true);
  if (state == nullptr) {
    if (slot.worker)
      (void)slot.worker->terminate();
    failed_ = true;
    return Status::limit_exceeded;
  }
  std::array<std::uint64_t, 16> retained{};
  std::size_t retained_count = 0;
  for (std::size_t index = 0; index < state->count; ++index) {
    if (now_seconds >= state->times[index] &&
        now_seconds - state->times[index] <= policy_.restart_window_seconds)
      retained[retained_count++] = state->times[index];
  }
  if (retained_count < retained.size())
    retained[retained_count++] = now_seconds;
  state->times = retained;
  state->count = retained_count;
  state->disabled = state->count >= policy_.restart_burst;
  std::uint64_t backoff = policy_.restart_backoff_initial_seconds;
  for (std::size_t count = 1; count < state->count; ++count) {
    backoff = std::min(policy_.restart_backoff_max_seconds,
                       backoff > policy_.restart_backoff_max_seconds / 2
                           ? policy_.restart_backoff_max_seconds
                           : backoff * 2);
  }
  if (!add_deadline(now_seconds, backoff, state->retry_at))
    state->disabled = true;
  const bool terminated = slot.worker && slot.worker->terminate();
  for (auto &entry : slots_) {
    if (entry.get() == &slot) {
      if (terminated)
        entry.reset();
      break;
    }
  }
  bool audited =
      append(event, permissions::AuditOutcome::failed, binding,
             permissions::GrantDecisionCode::ungranted, backoff, state->count);
  if (state->disabled)
    audited =
        append(permissions::AuditEvent::worker_disabled,
               permissions::AuditOutcome::denied, binding,
               permissions::GrantDecisionCode::revoked, 0, state->count) &&
        audited;
  if (!terminated)
    failed_ = true;
  if (!audited)
    return Status::audit_failed;
  return terminated ? (state->disabled ? Status::disabled : Status::backoff)
                    : Status::teardown_failed;
}

void HealthSupervisor::clear_slot(Slot &slot) {
  if (!slot.active)
    return;
  requests_ -= slot.request_count;
  surfaces_ -= slot.surface_count;
  --workers_;
  slot.active = false;
  slot.ready = false;
  slot.candidate = false;
  slot.request_count = 0;
  slot.surface_count = 0;
  slot.surface_occupied.fill(false);
  slot.surfaces.fill({});
  for (auto &request : slot.requests)
    request = {};
}

} // namespace omarchy::plugin_runtime::health
