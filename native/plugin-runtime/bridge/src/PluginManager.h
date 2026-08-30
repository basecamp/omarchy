#pragma once

#include "SurfaceProjectionModel.h"
#include "gesture_intent.hpp"

#include <QObject>
#include <QString>
#include <QtQml/qqmlregistration.h>

#include <memory>
#include <utility>
#include <vector>

#ifdef OMARCHY_PLUGIN_MANAGER_TESTING
#include "consent_review.hpp"

#include <cstdint>
#include <functional>
#include <optional>
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

class PluginManager final : public QObject {
  Q_OBJECT
  QML_NAMED_ELEMENT(PluginManager)
  QML_SINGLETON
  Q_PROPERTY(bool available READ available NOTIFY availableChanged)
  Q_PROPERTY(QString runtimeVersion READ runtimeVersion CONSTANT)
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
  [[nodiscard]] QAbstractItemModel *barSurfaces();
  [[nodiscard]] QAbstractItemModel *panelSurfaces();
  [[nodiscard]] QAbstractItemModel *overlaySurfaces();
  [[nodiscard]] int count() const noexcept;

  // This is the complete QML attachment boundary. It resolves only opaque
  // published keys to manager-owned roots and endpoints; without exact typed
  // readiness, attachment and publication stay inert.
  Q_INVOKABLE bool attach(const QString &surface_key,
                          QObject *surface) noexcept;

signals:
  void availableChanged();
  void surfacesChanged();
  void openRequested(QString sourceSurface, QString targetSurface,
                     QString generation);
  void toggleRequested(QString sourceSurface, QString targetSurface,
                       QString generation);
  void dismissRequested(QString sourceSurface, QString targetSurface,
                        QString generation);

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

  struct Runtime;

  // Declared first so all authority-bearing state is destroyed before the
  // process claim is released and another engine can create a manager.
  ProcessClaim process_claim_;
  SurfaceProjectionModel surfaces_;
  std::unique_ptr<Runtime> runtime_;
  bool available_ = false;

#ifdef OMARCHY_PLUGIN_MANAGER_TESTING
  friend class PluginManagerTestAccess;
  friend class SurfaceProjectionModelTestAccess;
#endif
};

#ifdef OMARCHY_PLUGIN_MANAGER_TESTING
class PluginManagerTestAccess final {
public:
  enum class TestJobKind : std::uint8_t { scan, preparation, permission };
  struct SlotObservation final {
    std::string plugin;
    std::uint64_t epoch = 0;
    std::uint8_t retry_attempts = 0;
    bool retry_wait = false;
    bool opening = false;
    bool starting = false;
    bool preparing = false;
    bool running = false;
    bool permission_in_flight = false;
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
  static void setJobSubmitter(PluginManager &manager, JobSubmitter submitter);
  static void setJobEntryProbe(PluginManager &manager, JobEntryProbe probe);
  static void requestAsyncScan(PluginManager &manager);
  static void requestPreparations(PluginManager &manager);
  static void drainRuntime(PluginManager &manager);
  [[nodiscard]] static std::uint8_t
  preparationCount(const PluginManager &manager);
  [[nodiscard]] static std::uint8_t
  permissionCount(const PluginManager &manager);
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
  [[nodiscard]] static bool applyPermissionReview(
      PluginManager &manager, std::string_view plugin, std::uint64_t epoch,
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
};
#endif

} // namespace omarchy::plugin_runtime::bridge
