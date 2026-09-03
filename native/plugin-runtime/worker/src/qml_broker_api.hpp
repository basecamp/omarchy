#pragma once

#include "worker_channel.hpp"
#include "dynamic_activation.hpp"
#include "manifest_contract.hpp"
#include "omarchy/plugin/wire/permission_snapshot.hpp"
#include "omarchy/plugin_runtime/surface/render_messages.hpp"

#include <QObject>
#include <QVariant>
#include <QVariantMap>
#include <QStringList>

#include <array>
#include <cstdint>
#include <filesystem>
#include <memory>
#include <optional>
#include <string>
#include <vector>

namespace omarchy::plugin_runtime::worker {

namespace surface = omarchy::plugin_runtime::surface;

class SurfaceIntentSink {
public:
  virtual ~SurfaceIntentSink() = default;
  [[nodiscard]] virtual bool request_surface_intent(
      std::optional<
          omarchy::plugins::definitions::DynamicInvocation::GestureClaim>
          source,
      std::string_view target_surface,
      surface::SurfaceIntentAction action, const QVariantMap &data) = 0;
};

struct EncodedInvoke {
  std::uint16_t message_type = 0;
  std::vector<std::byte> payload;
};

class InvokeEncoder {
public:
  virtual ~InvokeEncoder() = default;
  [[nodiscard]] virtual std::optional<EncodedInvoke>
  encode(std::string_view capability, std::string_view operation,
         const QVariantMap &arguments) const = 0;
};

class BuiltinInvokeEncoder final {
public:
  [[nodiscard]] std::optional<EncodedInvoke>
  encode(std::string_view capability, std::string_view operation,
         const QVariantMap &arguments) const;
};

class ManifestInvokeEncoder final : public InvokeEncoder {
public:
  explicit ManifestInvokeEncoder(
      const omarchy::plugins::manifest::ManifestV2 &manifest);
  [[nodiscard]] std::optional<EncodedInvoke>
  encode(std::string_view capability, std::string_view operation,
         const QVariantMap &arguments) const override;

private:
  struct Binding {
    std::string capability;
    std::vector<std::string> operations;
    std::optional<omarchy::plugins::definitions::CapabilityReference>
        definition;
  };
  BuiltinInvokeEncoder builtin_;
  std::vector<Binding> bindings_;
  bool valid_ = true;
};

class BrokerCall final : public QObject {
  Q_OBJECT
  Q_PROPERTY(bool finished READ finished NOTIFY finishedChanged)
  Q_PROPERTY(bool ok READ ok NOTIFY finishedChanged)
  Q_PROPERTY(QVariant value READ value NOTIFY finishedChanged)
  Q_PROPERTY(QString utf8Text READ utf8Text NOTIFY finishedChanged)
  Q_PROPERTY(QString error READ error NOTIFY finishedChanged)
  Q_PROPERTY(qulonglong correlation READ correlation CONSTANT)

public:
  explicit BrokerCall(std::uint64_t correlation, QObject *parent = nullptr);
  [[nodiscard]] bool finished() const;
  [[nodiscard]] bool ok() const;
  [[nodiscard]] QVariant value() const;
  [[nodiscard]] QString utf8Text() const;
  [[nodiscard]] QString error() const;
  [[nodiscard]] qulonglong correlation() const;
  void resolve(QVariant value);
  void reject(QString error);

signals:
  void finishedChanged();

private:
  std::uint64_t correlation_ = 0;
  QVariant value_;
  QString error_;
  bool finished_ = false;
  bool ok_ = false;
};

class QmlBrokerApi final : public QObject {
  Q_OBJECT
  Q_PROPERTY(QVariantMap permissions READ permissions CONSTANT)
  Q_PROPERTY(QVariantMap settings READ settings NOTIFY settingsChanged)
  Q_PROPERTY(qulonglong permissionGeneration READ permissionGeneration CONSTANT)
  Q_PROPERTY(bool brokerReady READ brokerReady NOTIFY brokerReadyChanged)

public:
  QmlBrokerApi(WorkerEndpoint &endpoint,
               std::unique_ptr<InvokeEncoder> encoder,
               const omarchy::plugins::manifest::ManifestV2 &manifest,
               std::uint64_t activation_generation,
               QObject *parent = nullptr, WorkerEndpoint *control = nullptr);
  Q_INVOKABLE QVariant invoke(const QString &capability,
                              const QString &operation,
                              const QVariantMap &arguments);
  Q_INVOKABLE bool hasPermission(const QString &capability,
                                 const QString &operation) const;
  // Presentation only: "granted" means the operation is delegated for some
  // broker-enforced effective scope. Resource, command, and demand scope stay
  // authoritative in the broker and are never implied by this projection.
  Q_INVOKABLE QString permissionState(const QString &capability,
                                      const QString &operation) const;
  Q_INVOKABLE QString readPackagedText(const QString &relativePath,
                                       int maximumBytes) const;
  Q_INVOKABLE bool requestSurfaceIntent(const QString &targetSurface,
                                        const QString &action);
  Q_INVOKABLE bool requestSurfaceIntent(const QString &targetSurface,
                                        const QString &action,
                                        const QVariantMap &data);
  Q_INVOKABLE bool updateSettings(const QVariantMap &entry);
  void setPackagedAssetRoot(std::filesystem::path root);
  [[nodiscard]] bool bindSurfaceIntentSink(SurfaceIntentSink &sink);
  [[nodiscard]] QVariantMap permissions() const;
  [[nodiscard]] QVariantMap settings() const;
  [[nodiscard]] qulonglong permissionGeneration() const;
  [[nodiscard]] bool brokerReady() const;
  // The worker calls this only after its permission-snapshot ACK has been
  // written to the control channel.
  [[nodiscard]] bool markBrokerReady();

  // This is accepted only from the authenticated host control path. It is a
  // UI hint; invoke() and the broker remain authoritative for every effect.
  [[nodiscard]] bool applyPermissionSnapshot(
      std::uint64_t envelope_generation, std::span<const std::byte> payload);
  [[nodiscard]] bool receive(ReceivedPacket packet);
  [[nodiscard]] bool applySettingsSnapshot(
      std::uint64_t envelope_generation, std::span<const std::byte> payload);
  [[nodiscard]] bool receiveSettingsResult(ReceivedPacket packet);
  [[nodiscard]] QString status() const;
  [[nodiscard]] bool
  beginTrustedGestureForInput(const surface::InputEvent &event);
  void beginTrustedGesture(std::uint64_t surface_id,
                           std::uint64_t surface_generation,
                           std::uint64_t input_sequence);
  void endTrustedGesture();
  void disconnect(QString reason);

signals:
  void callFinished(QObject *call);
  void brokerReadyChanged();
  void settingsChanged();

private:
  static constexpr std::size_t kMaximumPending = 32;
  struct Pending {
    std::uint64_t correlation = 0;
    std::uint16_t message_type = 0;
    BrokerCall *call = nullptr;
  };
  Pending *find(std::uint64_t correlation);
  QVariant rejected(QString reason);
  void notifyFinished(BrokerCall *call);

  WorkerEndpoint &endpoint_;
  WorkerEndpoint *control_ = nullptr;
  std::unique_ptr<InvokeEncoder> encoder_;
  std::array<Pending, kMaximumPending> pending_{};
  std::uint64_t next_correlation_ = 1;
  QString status_ = QStringLiteral("ready");
  bool broker_ready_ = false;
  struct RequestedPermission {
    QString capability;
    QStringList operations;
    bool required = false;
    std::vector<omarchy::plugin::wire::permission_snapshot::GrantState>
        operation_states;
  };
  enum class DeferredGestureKind : std::uint8_t { pointer, touch };
  // The host authorizes only this exact press/begin sequence. Keep it private
  // between dispatches, then expose it once during the matching release/end so
  // idiomatic QML click handlers work without granting timers ambient access.
  struct DeferredGesture {
    omarchy::plugins::definitions::DynamicInvocation::GestureClaim claim;
    DeferredGestureKind kind = DeferredGestureKind::pointer;
    std::uint32_t pointer_button = 0;
  };
  std::vector<RequestedPermission> requested_permissions_;
  std::string manifest_request_fingerprint_;
  std::uint64_t activation_generation_ = 0;
  omarchy::plugins::manifest::ManifestV2 manifest_;
  QVariantMap settings_;
  QVariantMap pending_settings_;
  std::uint64_t settings_correlation_ = 0;
  std::uint64_t next_settings_correlation_ = 1;
  std::filesystem::path packaged_asset_root_;
  bool host_snapshot_received_ = false;
  std::optional<omarchy::plugins::definitions::DynamicInvocation::GestureClaim>
      trusted_gesture_;
  std::optional<DeferredGesture> deferred_gesture_;
  SurfaceIntentSink *surface_intent_sink_ = nullptr;
};

} // namespace omarchy::plugin_runtime::worker
