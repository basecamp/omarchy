#pragma once

#include "worker_channel.hpp"

#include <QObject>
#include <QVariant>
#include <QVariantMap>

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

public:
  QmlBrokerApi(WorkerEndpoint &endpoint,
               std::unique_ptr<InvokeEncoder> encoder,
               QObject *parent = nullptr);
  Q_INVOKABLE QVariant invoke(const QString &operation,
                              const QVariantMap &arguments);
  [[nodiscard]] bool receive(ReceivedPacket packet);
  [[nodiscard]] QString status() const;
  void disconnect(QString reason);

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
};

} // namespace omarchy::plugin_runtime::worker
