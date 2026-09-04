#pragma once

#include "PermissionControl.h"
#include "PluginInstallControl.h"
#include "SurfaceProjectionModel.h"
#include "gesture_intent.hpp"

#include <QObject>
#include <QPointer>
#include <QString>
#include <QtQml/qqmlregistration.h>

#include <memory>
#include <optional>
#include <utility>
#include <vector>

#ifdef OMARCHY_PLUGIN_MANAGER_TESTING
#include "consent_review.hpp"

#include <cstdint>
#include <functional>
#include <span>
#include <string>
#include <string_view>
#endif

class QJSEngine;
class QQmlEngine;

#ifdef OMARCHY_PLUGIN_MANAGER_TESTING
namespace omarchy::plugin_runtime::channel {
class RuntimeBootstrap;
}
#endif

namespace omarchy::plugin_runtime::bridge {

namespace detail {
class PluginRuntimeController;
}

class PluginManager final : public QObject {
  Q_OBJECT
  QML_NAMED_ELEMENT(PluginManager)
  QML_SINGLETON
  Q_PROPERTY(bool available READ available NOTIFY availableChanged)
  Q_PROPERTY(QString runtimeVersion READ runtimeVersion CONSTANT)
  Q_PROPERTY(omarchy::plugin_runtime::bridge::PermissionControl *permissions
                 READ permissions CONSTANT)
  Q_PROPERTY(omarchy::plugin_runtime::bridge::PluginInstallControl *installer
                 READ installer CONSTANT)
  Q_PROPERTY(QAbstractItemModel *barSurfaces READ barSurfaces CONSTANT)
  Q_PROPERTY(QAbstractItemModel *panelSurfaces READ panelSurfaces CONSTANT)
  Q_PROPERTY(QAbstractItemModel *overlaySurfaces READ overlaySurfaces CONSTANT)
  Q_PROPERTY(int count READ count NOTIFY surfacesChanged)

public:
  // Qt owns the one QML singleton instance. The constructor is unavailable to
  // QML and ordinary C++ callers; Qt enters through this factory only.
  [[nodiscard]] static PluginManager *create(QQmlEngine *qml_engine,
                                             QJSEngine *js_engine) noexcept;
  ~PluginManager() override;

  [[nodiscard]] bool available() const noexcept;
  [[nodiscard]] QString runtimeVersion() const;
  [[nodiscard]] PermissionControl *permissions() noexcept;
  [[nodiscard]] PluginInstallControl *installer() noexcept;
  [[nodiscard]] QAbstractItemModel *barSurfaces();
  [[nodiscard]] QAbstractItemModel *panelSurfaces();
  [[nodiscard]] QAbstractItemModel *overlaySurfaces();
  [[nodiscard]] int count() const noexcept;

  // This is the complete QML attachment boundary. It resolves only opaque
  // published keys to manager-owned roots and endpoints; without exact typed
  // readiness, attachment and publication stay inert.
  Q_INVOKABLE bool attach(const QString &surface_key,
                          QObject *surface) noexcept;
  Q_INVOKABLE bool configureSettingsHost(QObject *host) noexcept;
  Q_INVOKABLE bool configurePresentationHost(QObject *host) noexcept;

signals:
  void availableChanged();
  void surfacesChanged();
  void openRequested(QString sourceSurface, QString targetSurface,
                     QString generation, QString inputSequence,
                     QString requestedOutput);
  void toggleRequested(QString sourceSurface, QString targetSurface,
                       QString generation, QString inputSequence,
                       QString requestedOutput);
  void dismissRequested(QString sourceSurface, QString targetSurface,
                        QString generation, QString inputSequence);

private:
  class ProcessClaim final {
  public:
    ProcessClaim(const ProcessClaim &) = delete;
    ProcessClaim &operator=(const ProcessClaim &) = delete;
    ProcessClaim(ProcessClaim &&other) noexcept;
    ProcessClaim &operator=(ProcessClaim &&) = delete;
    ~ProcessClaim() noexcept;

  private:
    ProcessClaim() noexcept = default;
    explicit ProcessClaim(QQmlEngine *engine) noexcept;

    QQmlEngine *engine_ = nullptr;

    friend class PluginManager;
    friend class PluginManagerTestAccess;
  };

  PluginManager(QObject *parent, ProcessClaim claim);
  [[nodiscard]] bool publishIntent(host_session::AdmittedSurfaceIntent intent);
  [[nodiscard]] std::optional<std::string>
  currentSettings(std::string_view plugin) const noexcept;
  [[nodiscard]] std::optional<std::string>
  currentPresentation() const noexcept;
  [[nodiscard]] bool persistSettings(std::string_view plugin,
                                     std::string_view canonical_entry) noexcept;
  [[nodiscard]] bool beginPermissionRead(std::uint64_t serial,
                                         std::string plugin,
                                         bool review,
                                         std::optional<plugins::permissions::Digest>
                                             expected_revision = std::nullopt) noexcept;
  [[nodiscard]] bool beginInstall(std::uint64_t serial, int archive_fd) noexcept;
  void completeInstall(std::uint64_t serial, std::string plugin,
                       std::string revision, std::string error) noexcept;
  [[nodiscard]] bool beginPermissionApply(
      std::uint64_t serial,
      const PermissionControl::ExactContext &context,
      std::shared_ptr<const host_session::ConsentReview> review,
      const host_session::ConsentConfirmation &confirmation,
      std::span<const host_session::BuiltinConsentDecision> builtin_decisions,
      std::span<const host_session::DynamicConsentDecision>
          dynamic_decisions) noexcept;
  [[nodiscard]] bool beginPermissionRevoke(
      std::uint64_t serial, const PermissionControl::ExactContext &context,
      const PermissionControl::Row &row) noexcept;
  void failPermissionControl(std::uint64_t serial,
                             std::string error) noexcept;
  void completePermissionRead(
      std::uint64_t serial, std::string plugin, std::uint64_t slot_epoch,
      std::shared_ptr<channel::PluginPermissionAuthority> authority,
      std::optional<host_session::AuthorityView> view,
      std::shared_ptr<const host_session::ConsentReview> review) noexcept;
  void completePermissionMutation(std::uint64_t serial, bool applied,
                                  std::string error) noexcept;
#ifdef OMARCHY_PLUGIN_MANAGER_TESTING
  [[nodiscard]] bool revokePermissionImmediatelyForTest(
      std::string_view plugin, std::uint64_t epoch,
      const plugins::permissions::CapabilityKey &capability,
      std::uint64_t expected_sequence);
#endif

  // Declared first so all authority-bearing state is destroyed before the
  // process claim is released and another engine can create a manager.
  ProcessClaim process_claim_;
  SurfaceProjectionModel surfaces_;
  PermissionControl permissions_;
  PluginInstallControl installer_;
  std::unique_ptr<detail::PluginRuntimeController> runtime_;
  bool available_ = false;
  QPointer<QObject> settings_host_;
  QPointer<QObject> presentation_host_;

#ifdef OMARCHY_PLUGIN_MANAGER_TESTING
  friend class PluginManagerTestAccess;
  friend class SurfaceProjectionModelTestAccess;
#endif
  friend class PermissionControl;
  friend class PluginInstallControl;
  friend class detail::PluginRuntimeController;
};

#ifdef OMARCHY_PLUGIN_MANAGER_TESTING
class PluginManagerTestAccess final {
public:
  enum class TestJobKind : std::uint8_t { scan, preparation, permission, install };
  struct SlotObservation final {
    std::string plugin;
    std::uint64_t epoch = 0;
    std::uint8_t retry_attempts = 0;
    bool retry_wait = false;
    bool opening = false;
    bool preparing = false;
    bool starting = false;
    bool running = false;
    bool permission_transaction = false;
    bool permission_changing = false;
    bool permission_disabled = false;
    bool has_runtime_root = false;
    bool has_endpoint_owner = false;
    std::uint8_t last_state = 0;
    std::uint8_t last_error = 0;
  };

  // Focused unit tests exercise manager internals without consuming the one
  // process claim. This path is compiled out of the QML module.
  [[nodiscard]] static std::unique_ptr<PluginManager> create() {
    return std::unique_ptr<PluginManager>(
        new PluginManager(nullptr, PluginManager::ProcessClaim{}));
  }
  static void failNextConstruction() noexcept;
  [[nodiscard]] static bool processClaimAvailable() noexcept;
  [[nodiscard]] static SurfaceProjectionModel &model(PluginManager &manager) {
    return manager.surfaces_;
  }
  static void
  installRuntime(PluginManager &manager,
                 std::unique_ptr<channel::RuntimeBootstrap> bootstrap);
  [[nodiscard]] static bool scanRuntime(PluginManager &manager);
  [[nodiscard]] static std::vector<SlotObservation>
  runtimeSlots(const PluginManager &manager);
  [[nodiscard]] static bool retryRuntime(PluginManager &manager,
                                         std::string_view plugin);
  [[nodiscard]] static bool queueStaleRunningCallback(PluginManager &manager,
                                                      std::string_view plugin);
  using JobSubmitter =
      std::function<bool(TestJobKind, std::function<void()>)>;
  using JobEntryProbe = std::function<void(TestJobKind)>;
  struct SurfaceIntentCallback final {
    std::function<bool(host_session::AdmittedSurfaceIntent)> deliver;
    std::function<std::size_t()> pending;
  };
  static void setJobSubmitter(PluginManager &manager, JobSubmitter submitter);
  static void setJobEntryProbe(PluginManager &manager, JobEntryProbe probe);
  static void requestAsyncScan(PluginManager &manager);
  static void requestPreparations(PluginManager &manager);
  static void drainRuntime(PluginManager &manager);
  [[nodiscard]] static std::optional<SurfaceIntentCallback>
  surfaceIntentCallback(PluginManager &manager, std::string_view plugin,
                        std::uint64_t epoch);
  [[nodiscard]] static bool stageRunningSurfaceIntentSlot(
      PluginManager &manager, std::string_view plugin, std::uint64_t epoch,
      const plugins::permissions::ActivationBinding &binding,
      std::vector<SurfaceProjectionModel::SurfaceDeclaration> declarations);
  [[nodiscard]] static bool routeTrustedPointer(
      PluginManager &manager, std::string_view plugin, std::uint64_t epoch,
      QStringView surface_key, bool pressed);
  [[nodiscard]] static std::uint8_t
  preparationCount(const PluginManager &manager);
  [[nodiscard]] static std::uint8_t
  executingPermissionJobs(const PluginManager &manager);
  [[nodiscard]] static std::optional<plugins::permissions::DecisionActor>
  pendingPermissionActor(const PluginManager &manager, std::string_view plugin);
  [[nodiscard]] static bool scanInFlight(const PluginManager &manager);
  [[nodiscard]] static std::uint8_t occupiedPreparationLanes(
      const PluginManager &manager);
  [[nodiscard]] static bool deliverLifecycle(
      PluginManager &manager, std::string_view plugin, std::uint64_t epoch,
      std::uint8_t state, std::uint8_t error);
  [[nodiscard]] static bool clockIsNondecreasing(PluginManager &manager);
  [[nodiscard]] static std::optional<host_session::AuthorityView>
  permissionView(PluginManager &manager, std::string_view plugin,
                 std::uint64_t epoch);
  [[nodiscard]] static std::shared_ptr<const host_session::ConsentReview>
  preparePermissionReview(PluginManager &manager, std::string_view plugin,
                          std::uint64_t epoch);
  [[nodiscard]] static bool revokePermission(
      PluginManager &manager, std::string_view plugin, std::uint64_t epoch,
      const plugins::permissions::CapabilityKey &capability,
      std::uint64_t expected_sequence);
  [[nodiscard]] static bool revokePermission(
      PluginManager &manager, std::string_view plugin, std::uint64_t epoch,
      const plugins::definitions::CapabilityReference &definition,
      std::uint64_t expected_sequence);
  [[nodiscard]] static bool revokePermissionImmediatelyForTest(
      PluginManager &manager, std::string_view plugin, std::uint64_t epoch,
      const plugins::permissions::CapabilityKey &capability,
      std::uint64_t expected_sequence);
  [[nodiscard]] static bool applyPermissionReview(
      PluginManager &manager, std::string_view plugin, std::uint64_t epoch,
      std::shared_ptr<const host_session::ConsentReview> review,
      const host_session::ConsentConfirmation &confirmation,
      std::span<const host_session::BuiltinConsentDecision> builtin_decisions,
      std::span<const host_session::DynamicConsentDecision> dynamic_decisions);
  [[nodiscard]] static std::weak_ptr<const void>
  deliveryGate(const PluginManager &manager);
  [[nodiscard]] static bool
  publishIntent(PluginManager &manager,
                host_session::AdmittedSurfaceIntent intent) {
    return manager.publishIntent(std::move(intent));
  }
  [[nodiscard]] static std::optional<std::string>
  currentSettings(const PluginManager &manager, std::string_view plugin) {
    return manager.currentSettings(plugin);
  }
  [[nodiscard]] static bool persistSettings(PluginManager &manager,
                                            std::string_view plugin,
                                            std::string_view settings) {
    return manager.persistSettings(plugin, settings);
  }
};
#endif

} // namespace omarchy::plugin_runtime::bridge
