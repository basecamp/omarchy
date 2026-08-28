#pragma once

#include "audit_store.hpp"
#include "omarchy/plugin_runtime/launcher/launcher.h"
#include "omarchy/plugin_runtime/surface/shared_layout.hpp"

#include <array>
#include <cstddef>
#include <cstdint>
#include <memory>

namespace omarchy::plugin_runtime::health {

namespace audit = omarchy::plugins::audit;
namespace launcher = omarchy::plugin_runtime::launcher;
namespace permissions = omarchy::plugins::permissions;
namespace surface = omarchy::plugin_runtime::surface;

inline constexpr std::size_t kMaximumManagedWorkers = 64;
inline constexpr std::size_t kMaximumTrackedRequests = 256;

struct HealthPolicy {
  std::size_t maximum_workers = 64;
  std::size_t maximum_requests_per_worker = 32;
  std::size_t maximum_requests_global = 256;
  std::size_t maximum_surfaces_per_worker = 4;
  std::size_t maximum_surfaces_global = 64;
  std::size_t maximum_request_bytes = 65576;
  std::size_t maximum_request_starts_per_window = 120;
  std::uint64_t request_rate_window_seconds = 1;
  std::uint64_t memory_max_bytes = 512ULL * 1024ULL * 1024ULL;
  std::uint64_t scratch_max_bytes = 64ULL * 1024ULL * 1024ULL;
  std::uint32_t tasks_max = 16;
  std::uint64_t hello_timeout_seconds = 3;
  std::uint64_t request_timeout_seconds = 30;
  std::uint64_t restart_window_seconds = 60;
  std::size_t restart_burst = 3;
  std::uint64_t restart_backoff_initial_seconds = 1;
  std::uint64_t restart_backoff_max_seconds = 30;
  std::uint64_t stable_reset_seconds = 300;
};

struct ResourceSample {
  std::uint64_t memory_bytes = 0;
  std::uint64_t scratch_bytes = 0;
  std::uint32_t tasks = 0;
};

enum class Status {
  accepted,
  denied,
  stale_generation,
  duplicate,
  limit_exceeded,
  not_ready,
  backoff,
  disabled,
  audit_failed,
  teardown_failed,
};

struct RestartDecision {
  Status status = Status::denied;
  std::uint64_t retry_after_seconds = 0;
};

class WorkerControl {
public:
  virtual ~WorkerControl() = default;
  [[nodiscard]] virtual const launcher::LaunchIdentity &identity() const = 0;
  [[nodiscard]] virtual bool alive() const = 0;
  [[nodiscard]] virtual bool terminate() = 0;
};

class LauncherWorkerControl final : public WorkerControl {
public:
  explicit LauncherWorkerControl(std::unique_ptr<launcher::Worker> worker);
  [[nodiscard]] const launcher::LaunchIdentity &identity() const override;
  [[nodiscard]] bool alive() const override;
  [[nodiscard]] bool terminate() override;

private:
  std::unique_ptr<launcher::Worker> worker_;
};

class HealthSupervisor {
public:
  HealthSupervisor(HealthPolicy policy, audit::AuditStore &audit_store);
  HealthSupervisor(const HealthSupervisor &) = delete;
  HealthSupervisor &operator=(const HealthSupervisor &) = delete;
  ~HealthSupervisor();

  [[nodiscard]] Status adopt(std::unique_ptr<WorkerControl> worker,
                             const permissions::ActivationBinding &binding,
                             std::uint64_t now_seconds);
  [[nodiscard]] Status
  adopt_candidate(std::unique_ptr<WorkerControl> worker,
                  const permissions::ActivationBinding &binding,
                  std::uint64_t now_seconds);
  [[nodiscard]] Status ready(const permissions::ActivationBinding &binding,
                             std::uint64_t now_seconds);
  [[nodiscard]] Status
  admit_request(const permissions::ActivationBinding &binding,
                std::uint64_t correlation, std::size_t request_bytes,
                std::uint64_t now_seconds);
  [[nodiscard]] Status
  complete_request(const permissions::ActivationBinding &binding,
                   std::uint64_t correlation);
  [[nodiscard]] Status
  open_surface(const permissions::ActivationBinding &binding,
               surface::SurfaceKey key);
  [[nodiscard]] Status
  close_surface(const permissions::ActivationBinding &binding,
                surface::SurfaceKey key);
  [[nodiscard]] Status
  observe_resources(const permissions::ActivationBinding &binding,
                    ResourceSample sample, std::uint64_t now_seconds);
  void tick(std::uint64_t now_seconds);
  [[nodiscard]] Status
  worker_exited(const permissions::ActivationBinding &binding,
                std::uint64_t now_seconds);
  [[nodiscard]] Status stop(const permissions::ActivationBinding &binding);
  [[nodiscard]] Status
  promote_candidate(const permissions::ActivationBinding &binding);
  [[nodiscard]] RestartDecision
  restart_decision(const permissions::PluginId &plugin,
                   const permissions::Digest &revision,
                   std::uint64_t now_seconds) const;

  [[nodiscard]] std::size_t worker_count() const;
  [[nodiscard]] std::size_t request_count() const;
  [[nodiscard]] std::size_t surface_count() const;
  [[nodiscard]] bool failed() const { return failed_; }

private:
  struct Request;
  struct Slot;
  struct CrashState;

  [[nodiscard]] Slot *find(const permissions::ActivationBinding &binding);
  [[nodiscard]] const Slot *
  find(const permissions::ActivationBinding &binding) const;
  [[nodiscard]] CrashState *crash_state(const permissions::PluginId &plugin,
                                        const permissions::Digest &revision,
                                        bool create);
  [[nodiscard]] bool recover_unresolved_workers();
  [[nodiscard]] Status adopt_impl(std::unique_ptr<WorkerControl> worker,
                                  const permissions::ActivationBinding &binding,
                                  std::uint64_t now_seconds, bool candidate);
  [[nodiscard]] bool append(permissions::AuditEvent event,
                            permissions::AuditOutcome outcome,
                            const permissions::ActivationBinding &binding,
                            permissions::GrantDecisionCode decision,
                            std::uint64_t retry_after = 0,
                            std::uint64_t item_count = 0);
  Status fail_slot(Slot &slot, std::uint64_t now_seconds,
                   permissions::AuditEvent event);
  void clear_slot(Slot &slot);

  HealthPolicy policy_;
  audit::AuditStore &audit_;
  std::array<std::unique_ptr<Slot>, kMaximumManagedWorkers> slots_{};
  std::array<std::unique_ptr<CrashState>, kMaximumManagedWorkers> crashes_{};
  std::size_t workers_ = 0;
  std::size_t requests_ = 0;
  std::size_t surfaces_ = 0;
  bool failed_ = false;
};

} // namespace omarchy::plugin_runtime::health
