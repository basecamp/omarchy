#include "manifest_contract.hpp"

#include <QEventLoop>
#include <QGuiApplication>
#include <QQmlComponent>
#include <QQmlContext>
#include <QQmlEngine>
#include <QSet>
#include <QStringList>
#include <QTimer>
#include <QVariant>

#include <filesystem>
#include <fstream>
#include <iostream>
#include <memory>
#include <stdexcept>
#include <string>
#include <string_view>
#include <vector>

namespace {

namespace manifest = omarchy::plugins::manifest;

const std::filesystem::path kRoot{OMARCHY_PRODUCT_FIXTURE_ROOT};

void require(bool condition, std::string_view message) {
  if (!condition) {
    throw std::runtime_error(std::string(message));
  }
}

std::string read_text(const std::filesystem::path &path) {
  std::ifstream input(path, std::ios::binary);
  require(input.good(), "fixture file could not be opened");
  return {std::istreambuf_iterator<char>(input),
          std::istreambuf_iterator<char>()};
}

class FakeCall final : public QObject {
  Q_OBJECT
  Q_PROPERTY(bool finished READ finished NOTIFY finishedChanged)
  Q_PROPERTY(bool ok READ ok NOTIFY finishedChanged)
  Q_PROPERTY(QString error READ error NOTIFY finishedChanged)
  Q_PROPERTY(QVariant value READ value NOTIFY finishedChanged)
  Q_PROPERTY(qulonglong correlation READ correlation CONSTANT)

public:
  FakeCall(bool ok, QString error, QVariant value, qulonglong correlation,
           QObject *parent)
      : QObject(parent), ok_(ok), error_(std::move(error)),
        value_(std::move(value)), correlation_(correlation) {}

  [[nodiscard]] bool finished() const { return finished_; }
  [[nodiscard]] bool ok() const { return ok_; }
  [[nodiscard]] QString error() const { return error_; }
  [[nodiscard]] QVariant value() const { return value_; }
  [[nodiscard]] qulonglong correlation() const { return correlation_; }

  void complete() {
    finished_ = true;
    emit finishedChanged();
  }

signals:
  void finishedChanged();

private:
  bool finished_ = false;
  bool ok_;
  QString error_;
  QVariant value_;
  qulonglong correlation_ = 0;
};

class FakeRuntime final : public QObject {
  Q_OBJECT
  Q_PROPERTY(QVariantMap permissions READ permissions NOTIFY permissionsChanged)

public:
  explicit FakeRuntime(QSet<QString> allowed, bool asynchronous = false,
                       QObject *parent = nullptr)
      : QObject(parent), allowed_(std::move(allowed)),
        asynchronous_(asynchronous) {}

  Q_INVOKABLE QVariant invoke(const QString &operation,
                              const QVariantMap &payload) {
    if (!allowed_.contains(operation)) {
      denied_.push_back(operation);
      if (asynchronous_)
        return asynchronousCall(false, QStringLiteral("permission denied"), {});
      return false;
    }
    operations_.push_back(operation);
    payloads_.push_back(payload);
    if (asynchronous_) {
      const QVariant value = operation == QStringLiteral("storage_read")
                                 ? QVariant(QStringLiteral("encoded-result"))
                                 : QVariant();
      return asynchronousCall(true, {}, value);
    }
    return true;
  }

  [[nodiscard]] int count(const QString &operation) const {
    return operations_.count(operation);
  }

  [[nodiscard]] bool denied(const QString &operation) const {
    return denied_.contains(operation);
  }

  Q_INVOKABLE bool hasPermission(const QString &capability,
                                 const QString &operation) const {
    return capability == QStringLiteral("notifications.send") &&
           operation == QStringLiteral("send") &&
           allowed_.contains(QStringLiteral("notification_send"));
  }

  Q_INVOKABLE QString permissionState(const QString &capability,
                                      const QString &operation) const {
    return hasPermission(capability, operation) ? QStringLiteral("granted")
                                                : QStringLiteral("denied");
  }

  [[nodiscard]] QVariantMap permissions() const {
    return {{QStringLiteral("notifications.send"),
             QVariantMap{{QStringLiteral("send"),
                          allowed_.contains(QStringLiteral("notification_send"))},
                         {QStringLiteral("required"), false}}}};
  }

  void setNotificationGranted(bool granted) {
    if (granted)
      allowed_.insert(QStringLiteral("notification_send"));
    else
      allowed_.remove(QStringLiteral("notification_send"));
    emit permissionsChanged();
  }

signals:
  void callFinished(QObject *call);
  void permissionsChanged();

private:
  QVariant asynchronousCall(bool ok, QString error, QVariant value) {
    auto call = std::make_unique<FakeCall>(ok, std::move(error),
                                          std::move(value), next_correlation_++,
                                          this);
    auto *pointer = call.get();
    calls_.push_back(std::move(call));
    QTimer::singleShot(0, pointer, [this, pointer] {
      pointer->complete();
      emit callFinished(pointer);
    });
    return QVariant::fromValue(static_cast<QObject *>(pointer));
  }

  QSet<QString> allowed_;
  bool asynchronous_ = false;
  QStringList operations_;
  QStringList denied_;
  QList<QVariantMap> payloads_;
  std::vector<std::unique_ptr<FakeCall>> calls_;
  qulonglong next_correlation_ = 1;
};

struct LoadedFixture {
  QQmlEngine engine;
  std::unique_ptr<QObject> object;
};

std::unique_ptr<LoadedFixture> load(std::string_view name,
                                    FakeRuntime &runtime) {
  const auto directory = kRoot / name;
  const auto parsed =
      manifest::parse_manifest_v2(read_text(directory / "manifest.json"));
  require(parsed.runtime.api_version == 1,
          "fixture selected an unsupported runtime API");
  const auto qml = directory / parsed.runtime.qml;
  require(qml.lexically_normal().string().starts_with(directory.string()),
          "fixture entry point escaped its product directory");

  auto loaded = std::make_unique<LoadedFixture>();
  loaded->engine.rootContext()->setContextProperty(QStringLiteral("runtime"),
                                                    &runtime);
  QQmlComponent component(&loaded->engine,
                          QUrl::fromLocalFile(QString::fromStdString(qml)));
  if (!component.isReady()) {
    const auto errors = component.errorString().toStdString();
    throw std::runtime_error("fixture QML did not compile: " + errors);
  }
  loaded->object.reset(component.create());
  require(loaded->object != nullptr, "fixture QML did not instantiate");
  return loaded;
}

void test_live_evidence_fixtures() {
  FakeRuntime authorized({QStringLiteral("storage_read"),
                          QStringLiteral("storage_write")}, true);
  auto authorized_fixture = load("lab-authorized", authorized);
  QEventLoop authorized_loop;
  QTimer::singleShot(50, &authorized_loop, &QEventLoop::quit);
  authorized_loop.exec();
  require(authorized_fixture->object->property("phase").toString() ==
                  QStringLiteral("AUTHORIZED") &&
              authorized.count(QStringLiteral("storage_write")) == 1 &&
              authorized.count(QStringLiteral("storage_read")) == 1,
          "authorized live fixture did not follow async broker completions");

  FakeRuntime denied({QStringLiteral("storage_read"),
                      QStringLiteral("storage_write")}, true);
  auto denied_fixture = load("lab-denied", denied);
  QEventLoop denied_loop;
  QTimer::singleShot(50, &denied_loop, &QEventLoop::quit);
  denied_loop.exec();
  require(denied_fixture->object->property("phase").toString() ==
                  QStringLiteral("DENIED") &&
              denied.denied(QStringLiteral("notification_send")),
          "denial live fixture did not follow async broker denial");

  FakeRuntime permission({QStringLiteral("notification_send")});
  auto permission_fixture = load("lab-permission", permission);
  QEventLoop permission_startup_loop;
  QTimer::singleShot(5, &permission_startup_loop, &QEventLoop::quit);
  permission_startup_loop.exec();
  require(permission_fixture->object->property("permissionState").toString() ==
                  QStringLiteral("GRANTED") &&
              permission_fixture->object->property("observedChanges").toInt() == 0,
          "permission fixture did not render its initial availability");
  permission.setNotificationGranted(false);
  QEventLoop permission_revocation_loop;
  QTimer::singleShot(5, &permission_revocation_loop, &QEventLoop::quit);
  permission_revocation_loop.exec();
  require(permission_fixture->object->property("permissionState").toString() ==
              QStringLiteral("DENIED"),
          "permission fixture did not render revoked availability");
  require(permission_fixture->object->property("observedChanges").toInt() == 1,
          "permission fixture did not count exactly one revocation");
}

} // namespace

int main(int argc, char **argv) {
  QGuiApplication application(argc, argv);
  try {
    if (application.arguments().contains(QStringLiteral("--live-evidence-only"))) {
      test_live_evidence_fixtures();
      return 0;
    }
    test_live_evidence_fixtures();
  } catch (const std::exception &error) {
    std::cerr << error.what() << '\n';
    return 1;
  }
  return 0;
}

#include "product_fixtures_test.moc"
