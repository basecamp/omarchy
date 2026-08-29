#pragma once

#include "worker_channel.hpp"
#include "dynamic_activation.hpp"
#include "manifest_contract.hpp"

#include <QObject>
#include <QVariant>
#include <QVariantMap>
#include <QStringList>

#include <array>
#include <cstdint>
#include <memory>
#include <optional>
#include <string>
#include <vector>

namespace omarchy::plugin_runtime::worker {

struct EncodedInvoke {
  std::uint16_t message_type = 0;
  std::vector<std::byte> payload;
};

class InvokeEncoder {
public:
  virtual ~InvokeEncoder() = default;
  [[nodiscard]] virtual std::optional<EncodedInvoke>
  encode(std::string_view operation, const QVariantMap &arguments) const = 0;
};

class BootstrapInvokeEncoder final : public InvokeEncoder {
public:
  [[nodiscard]] std::optional<EncodedInvoke>
  encode(std::string_view operation, const QVariantMap &arguments) const override;
};

class ManifestInvokeEncoder final : public InvokeEncoder {
public:
  explicit ManifestInvokeEncoder(
      const omarchy::plugins::manifest::ManifestV2 &manifest);
  [[nodiscard]] std::optional<EncodedInvoke>
  encode(std::string_view operation, const QVariantMap &arguments) const override;

private:
  struct DynamicBinding {
    omarchy::plugins::definitions::CapabilityReference definition;
    std::vector<std::string> operations;
  };
  BootstrapInvokeEncoder bootstrap_;
  std::vector<DynamicBinding> dynamic_;
  bool ambiguous_ = false;
};

class BrokerCall final : public QObject {
  Q_OBJECT
  Q_PROPERTY(bool finished READ finished NOTIFY finishedChanged)
  Q_PROPERTY(bool ok READ ok NOTIFY finishedChanged)
  Q_PROPERTY(QVariant value READ value NOTIFY finishedChanged)
  Q_PROPERTY(QString error READ error NOTIFY finishedChanged)
  Q_PROPERTY(qulonglong correlation READ correlation CONSTANT)

public:
  explicit BrokerCall(std::uint64_t correlation, QObject *parent = nullptr);
  [[nodiscard]] bool finished() const;
  [[nodiscard]] bool ok() const;
  [[nodiscard]] QVariant value() const;
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
  Q_PROPERTY(QVariantMap permissions READ permissions NOTIFY permissionsChanged)
  Q_PROPERTY(qulonglong permissionGeneration READ permissionGeneration
             NOTIFY permissionsChanged)

public:
  QmlBrokerApi(WorkerEndpoint &endpoint,
               std::unique_ptr<InvokeEncoder> encoder,
               QObject *parent = nullptr);
  QmlBrokerApi(WorkerEndpoint &endpoint,
               std::unique_ptr<InvokeEncoder> encoder,
               const omarchy::plugins::manifest::ManifestV2 &manifest,
               std::uint64_t activation_generation,
               QObject *parent = nullptr);
  Q_INVOKABLE QVariant invoke(const QString &operation,
                              const QVariantMap &arguments);
  Q_INVOKABLE bool hasPermission(const QString &capability,
                                 const QString &operation) const;
  Q_INVOKABLE QString permissionState(const QString &capability,
                                      const QString &operation) const;
  [[nodiscard]] QVariantMap permissions() const;
  [[nodiscard]] qulonglong permissionGeneration() const;

  struct HostPermission {
    std::string capability;
    std::string operation;
    bool granted = false;
  };
  // This is accepted only from the authenticated host control path. It is a
  // UI hint; invoke() and the broker remain authoritative for every effect.
  [[nodiscard]] bool applyHostPermissionSnapshot(
      std::uint64_t activation_generation,
      std::span<const HostPermission> permissions);
  [[nodiscard]] bool receive(ReceivedPacket packet);
  [[nodiscard]] QString status() const;
  void disconnect(QString reason);

signals:
  void permissionsChanged();

private:
  static constexpr std::size_t kMaximumPending = 32;
  struct Pending {
    std::uint64_t correlation = 0;
    std::uint16_t message_type = 0;
    BrokerCall *call = nullptr;
  };
  Pending *find(std::uint64_t correlation);
  QVariant rejected(QString reason);

  WorkerEndpoint &endpoint_;
  std::unique_ptr<InvokeEncoder> encoder_;
  std::array<Pending, kMaximumPending> pending_{};
  std::uint64_t next_correlation_ = 1;
  QString status_ = QStringLiteral("ready");
  struct RequestedPermission {
    QString capability;
    QString operation;
    bool required = false;
    bool granted = false;
  };
  std::vector<RequestedPermission> requested_permissions_;
  std::uint64_t activation_generation_ = 0;
  bool host_snapshot_received_ = false;
};

} // namespace omarchy::plugin_runtime::worker
