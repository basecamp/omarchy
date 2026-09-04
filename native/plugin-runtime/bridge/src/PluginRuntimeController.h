#pragma once

#include "PluginManager.h"
#include "SurfaceEndpointOwner.h"
#include "runtime_bootstrap.hpp"
#include "surface_host.hpp"

#include <QThreadPool>
#include <QTimer>

#include <array>
#include <atomic>
#include <chrono>
#include <deque>
#include <limits>
#include <memory>
#include <mutex>
#include <optional>
#include <span>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace omarchy::plugin_runtime::bridge::detail {

class Q_DECL_HIDDEN PluginRuntimeController final {
public:
  using Clock = std::chrono::steady_clock;

  static std::unique_ptr<PluginRuntimeController>
  open(PluginManager &manager) noexcept;
  PluginRuntimeController(PluginManager &manager,
                          std::unique_ptr<channel::RuntimeBootstrap> bootstrap);
  ~PluginRuntimeController() noexcept;

  bool beginPermissionRead(
      std::uint64_t serial, std::string plugin, bool review,
      std::optional<plugins::permissions::Digest> expected_revision) noexcept;
  bool beginInstall(std::uint64_t serial, int archive_fd) noexcept;
  bool beginControlledPermissionApply(
      std::uint64_t serial, std::string_view plugin, std::uint64_t epoch,
      const std::shared_ptr<channel::PluginPermissionAuthority> &authority,
      std::shared_ptr<const host_session::ConsentReview> review,
      const host_session::ConsentConfirmation &confirmation,
      std::span<const host_session::BuiltinConsentDecision> builtin_decisions,
      std::span<const host_session::DynamicConsentDecision>
          dynamic_decisions) noexcept;
  bool beginControlledPermissionRevoke(
      std::uint64_t serial, std::string_view plugin, std::uint64_t epoch,
      const std::shared_ptr<channel::PluginPermissionAuthority> &authority,
      bool dynamic,
      const std::optional<plugins::permissions::CapabilityKey> &builtin,
      const std::optional<plugins::definitions::CapabilityReference>
          &definition,
      std::uint64_t expected_sequence) noexcept;
  bool attach(const QString &surface_key, QObject *surface) noexcept;

private:
  enum class Phase : std::uint8_t {
    opening,
    preparing,
    starting,
    running,
    permission_changing,
    permission_disabled,
    retry_wait,
    stopping,
  };
  enum class JobKind : std::uint8_t { scan, preparation, permission, install };
  enum class PermissionKind : std::uint8_t {
    revoke_builtin,
    revoke_dynamic,
    apply_review,
  };

  class MonotonicClock final : public surface_host::MonotonicClock {
  public:
    std::uint64_t now_nanoseconds() const override;
  };

  struct HookState final {
    static constexpr std::size_t maximum_pending_surface_intents = 64;
    explicit HookState(std::string plugin, std::uint64_t epoch);

    const std::string plugin;
    const std::uint64_t epoch;
    std::atomic<std::uint16_t> lifecycle = 0;
    std::mutex intent_mutex;
    std::deque<host_session::AdmittedSurfaceIntent> intents;
  };

  struct Hook final : channel::PluginRuntimeHooks {
    Hook(std::shared_ptr<HookState> state, PluginManager &manager);
    void state_changed(host_session::SessionState state,
                       host_session::SessionError error) override;
    void render_rejected(host_session::RouteResult) override;
    bool accept(host_session::AdmittedSurfaceIntent intent) override;
    bool update_settings(
        const plugins::permissions::ActivationBinding &binding,
        std::string_view canonical_entry) override;
    std::shared_ptr<HookState> state;
    PluginManager &manager;
  };

  struct ScanResult final {
    std::unique_ptr<channel::ActivationCatalog> catalog;
  };
  struct PreparationResult final {
    std::string plugin;
    std::uint64_t epoch = 0;
    std::shared_ptr<channel::PluginPermissionAuthority> permissions;
    std::optional<std::string> settings;
    std::optional<std::string> presentation;
    std::unique_ptr<channel::PreparedPluginRuntime> prepared;
    bool permission_disabled = false;
  };
  struct PermissionReadResult final {
    std::uint64_t serial = 0;
    std::string plugin;
    std::uint64_t epoch = 0;
    std::shared_ptr<channel::PluginPermissionAuthority> authority;
    std::optional<host_session::AuthorityView> view;
    std::shared_ptr<const host_session::ConsentReview> review;
    std::optional<plugins::permissions::Digest> expected_revision;
  };
  struct InstallResult final {
    std::uint64_t serial = 0;
    std::string plugin;
    std::string revision;
    std::string error;
    std::unique_ptr<channel::ActivationCatalog> catalog;
  };
  struct PermissionTransaction final {
    static constexpr std::uint8_t fenced = 1U << 0U;
    static constexpr std::uint8_t complete = 1U << 1U;

    std::atomic<std::uint8_t> delivery = 0;
    std::uint64_t control_serial = 0;
    PermissionKind kind = PermissionKind::revoke_builtin;
    std::shared_ptr<channel::PluginPermissionAuthority> authority;
    plugins::permissions::CapabilityKey builtin;
    plugins::definitions::CapabilityReference dynamic;
    std::uint64_t expected_sequence = 0;
    std::shared_ptr<const host_session::ConsentReview> consent_review;
    host_session::ConsentConfirmation confirmation;
    std::vector<host_session::BuiltinConsentDecision> builtin_decisions;
    std::vector<host_session::DynamicConsentDecision> dynamic_decisions;
    host_session::AuthorityRevocationResult revocation;
    channel::ReviewedPermissionApplyResult review;
  };
  struct Slot final {
    std::string plugin;
    std::uint64_t epoch = 0;
    Phase phase = Phase::opening;
    std::uint8_t retry_attempts = 0;
    std::optional<Clock::time_point> retry_due;
    std::shared_ptr<HookState> callback_state;
    std::unique_ptr<Hook> hook;
    std::shared_ptr<channel::PluginPermissionAuthority> permissions;
    std::uint64_t permission_read_serial = 0;
    std::shared_ptr<PermissionTransaction> permission_transaction;
    std::optional<plugins::permissions::ActivationBinding> expected_binding;
    std::unique_ptr<channel::PluginRuntimeRoot> root;
    std::unique_ptr<SurfaceEndpointOwner> endpoint_owner;
#ifdef OMARCHY_PLUGIN_MANAGER_TESTING
    std::optional<plugins::permissions::ActivationBinding> test_running_binding;
    bool test_surface_endpoint = false;
    std::uint8_t last_state = 0;
    std::uint8_t last_error = 0;
#endif
  };
  struct DeliveryGate final {
    std::mutex mutex;
    std::atomic<bool> canceled = false;
    std::atomic<bool> scan_in_flight = false;
    std::atomic<std::uint8_t> preparations_in_flight = 0;
    std::atomic<std::uint8_t> permissions_in_flight = 0;
    std::atomic<std::uint8_t> permission_reads_in_flight = 0;
    std::atomic<bool> install_in_flight = false;
    std::shared_ptr<ScanResult> scan_result;
    std::array<std::shared_ptr<PreparationResult>, 2> preparation_results;
    std::array<std::shared_ptr<PermissionReadResult>, 2>
        permission_read_results;
    std::array<std::shared_ptr<PermissionTransaction>, 2> permission_results;
    std::shared_ptr<InstallResult> install_result;
  };
  struct PermissionFenceObserver final : host_session::AuthorityFenceObserver {
    explicit PermissionFenceObserver(
        std::shared_ptr<PermissionTransaction> transaction);
    void live_generation_closed() noexcept override;
    std::shared_ptr<PermissionTransaction> transaction;
  };

#ifdef OMARCHY_PLUGIN_MANAGER_TESTING
  struct ManualTestTag final {};
  PluginRuntimeController(PluginManager &manager,
                          std::unique_ptr<channel::RuntimeBootstrap> bootstrap,
                          ManualTestTag);
#endif

  void configureTimers();
  void requestScan() noexcept;
  void drainCompletions() noexcept;
  bool
  reconcile(std::unique_ptr<channel::ActivationCatalog> candidate) noexcept;
  Slot makeSlot(std::string_view plugin);
  bool
  acceptScan(std::unique_ptr<channel::ActivationCatalog> candidate) noexcept;
  void start(Slot &slot) noexcept;
  void requestPreparations() noexcept;
  bool
  beginPermissionRevoke(std::string_view plugin, std::uint64_t epoch,
                        const plugins::permissions::CapabilityKey &capability,
                        std::uint64_t expected_sequence) noexcept;
  std::optional<host_session::AuthorityView>
  permissionView(std::string_view plugin, std::uint64_t epoch) const;
  std::shared_ptr<const host_session::ConsentReview>
  preparePermissionReview(std::string_view plugin, std::uint64_t epoch);
  bool beginPermissionRevoke(
      std::string_view plugin, std::uint64_t epoch,
      const plugins::definitions::CapabilityReference &definition,
      std::uint64_t expected_sequence) noexcept;
  bool beginPermissionApply(
      std::string_view plugin, std::uint64_t epoch,
      std::shared_ptr<const host_session::ConsentReview> review,
      const host_session::ConsentConfirmation &confirmation,
      std::span<const host_session::BuiltinConsentDecision> builtin_decisions,
      std::span<const host_session::DynamicConsentDecision>
          dynamic_decisions) noexcept;
  bool beginPermissionMutation(
      std::string_view plugin, std::uint64_t epoch,
      std::shared_ptr<PermissionTransaction> result) noexcept;
  void fencePermission(Slot &slot) noexcept;
  void completePermission(Slot &slot,
                          const PermissionTransaction &result) noexcept;
  void withdraw(Slot &slot) noexcept;
  void disable(Slot &slot) noexcept;

  template <typename Job> bool submit(JobKind kind, Job &&job) {
#ifdef OMARCHY_PLUGIN_MANAGER_TESTING
    if (job_submitter_)
      return job_submitter_(
          kind == JobKind::scan ? PluginManagerTestAccess::TestJobKind::scan
          : kind == JobKind::preparation
              ? PluginManagerTestAccess::TestJobKind::preparation
          : kind == JobKind::permission
              ? PluginManagerTestAccess::TestJobKind::permission
              : PluginManagerTestAccess::TestJobKind::install,
          std::function<void()>(std::forward<Job>(job)));
#endif
    (void)kind;
    return QThreadPool::globalInstance()->tryStart(std::forward<Job>(job));
  }

  void armCompletionTimer() noexcept;
  void stateChanged(std::string_view plugin, std::uint64_t epoch,
                    host_session::SessionState state,
                    host_session::SessionError error) noexcept;
  void drainSurfaceIntents(Slot &slot) noexcept;
  static std::optional<std::vector<SurfaceProjectionModel::SurfaceDeclaration>>
  publicationDeclarations(
      channel::PluginRuntimeRoot &root,
      const plugins::permissions::ActivationBinding &binding);
  bool publishRunning(std::string_view plugin, std::uint64_t epoch,
                      const plugins::permissions::ActivationBinding &binding,
                      std::vector<SurfaceProjectionModel::SurfaceDeclaration>
                          declarations) noexcept;
  Slot *exact(std::string_view plugin, std::uint64_t epoch) noexcept;
  void fail(Slot &slot) noexcept;
  void retryDue() noexcept;
  void armRetryTimer() noexcept;
  void stopRuntime(Slot &slot) noexcept;
  std::uint64_t nextEpoch() noexcept;

  PluginManager &manager_;
  std::shared_ptr<const channel::RuntimeBootstrap> bootstrap_;
  std::shared_ptr<DeliveryGate> gate_ = std::make_shared<DeliveryGate>();
  std::unique_ptr<channel::ActivationCatalog> catalog_;
  MonotonicClock clock_;
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

#ifdef OMARCHY_PLUGIN_MANAGER_TESTING
  friend class ::omarchy::plugin_runtime::bridge::PluginManagerTestAccess;
#endif
  friend class ::omarchy::plugin_runtime::bridge::PluginManager;
};

} // namespace omarchy::plugin_runtime::bridge::detail
