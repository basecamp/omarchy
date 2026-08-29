#include "manifest_contract.hpp"

#include <QFile>
#include <QEventLoop>
#include <QGuiApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
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

public:
  FakeCall(bool ok, QString error, QVariant value, QObject *parent)
      : QObject(parent), ok_(ok), error_(std::move(error)),
        value_(std::move(value)) {}

  [[nodiscard]] bool finished() const { return finished_; }
  [[nodiscard]] bool ok() const { return ok_; }
  [[nodiscard]] QString error() const { return error_; }
  [[nodiscard]] QVariant value() const { return value_; }

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
};

class FakeRuntime final : public QObject {
  Q_OBJECT

public:
  explicit FakeRuntime(QSet<QString> allowed, bool asynchronous = false,
                       QObject *parent = nullptr)
      : QObject(parent), allowed_(std::move(allowed)),
        asynchronous_(asynchronous) {}

  void setStatuses(QVariantList statuses) { statuses_ = std::move(statuses); }

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
    if (operation == QStringLiteral("fake_status_list")) {
      return statuses_;
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

  void setNotificationGranted(bool granted) {
    if (granted)
      allowed_.insert(QStringLiteral("notification_send"));
    else
      allowed_.remove(QStringLiteral("notification_send"));
    emit permissionsChanged();
  }

signals:
  void permissionsChanged();

private:
  QVariant asynchronousCall(bool ok, QString error, QVariant value) {
    auto call = std::make_unique<FakeCall>(ok, std::move(error),
                                          std::move(value), this);
    auto *pointer = call.get();
    calls_.push_back(std::move(call));
    QTimer::singleShot(0, pointer, [pointer] { pointer->complete(); });
    return QVariant::fromValue(static_cast<QObject *>(pointer));
  }

  QSet<QString> allowed_;
  bool asynchronous_ = false;
  QStringList operations_;
  QStringList denied_;
  QList<QVariantMap> payloads_;
  QVariantList statuses_;
  std::vector<std::unique_ptr<FakeCall>> calls_;
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

QVariantList load_statuses() {
  QFile input(QString::fromStdString(
      (kRoot / "fake-status/fake-status.json").string()));
  require(input.open(QIODevice::ReadOnly), "fake status data did not open");
  QJsonParseError error{};
  const auto document = QJsonDocument::fromJson(input.readAll(), &error);
  require(error.error == QJsonParseError::NoError && document.isArray(),
          "fake status data is malformed");
  return document.array().toVariantList();
}

void test_pomodoro() {
  FakeRuntime runtime({QStringLiteral("storage_read"),
                       QStringLiteral("storage_write"),
                       QStringLiteral("notification_send"),
                       QStringLiteral("audio_play_cue")});
  auto fixture = load("pomodoro", runtime);
  require(fixture->object->property("surfaceRole").toString() ==
                  QStringLiteral("bar-embedded") &&
              fixture->object->property("width").toInt() == 252 &&
              runtime.count(QStringLiteral("storage_read")) == 1,
          "Pomodoro did not load as a bounded custom bar scene");
  require(QMetaObject::invokeMethod(fixture->object.get(), "toggleForTest") &&
              fixture->object->property("active").toBool(),
          "Pomodoro did not preserve local interaction state");
  require(QMetaObject::invokeMethod(fixture->object.get(), "completeForTest") &&
              fixture->object->property("completedSessions").toInt() == 1 &&
              runtime.count(QStringLiteral("storage_write")) == 1 &&
              runtime.count(QStringLiteral("notification_send")) == 1 &&
              runtime.count(QStringLiteral("audio_play_cue")) == 1,
          "Pomodoro did not use the four named mock operations");
}

void test_pet() {
  FakeRuntime runtime({});
  auto fixture = load("pet", runtime);
  const auto before = fixture->object->property("petX").toReal();
  require(fixture->object->property("surfaceRole").toString() ==
                  QStringLiteral("desktop-overlay") &&
              !fixture->object->property("acceptsKeyboardFocus").toBool() &&
              fixture->object->property("maximumFramesPerSecond").toInt() ==
                  30 &&
              QMetaObject::invokeMethod(fixture->object.get(), "stepForTest") &&
              fixture->object->property("petX").toReal() > before &&
              fixture->object->property("inputRegions").toList().size() == 1,
          "transparent pet did not retain bounded motion and input geometry");
}

void test_fake_status() {
  FakeRuntime runtime({QStringLiteral("fake_status_list"),
                       QStringLiteral("fake_status_acknowledge")});
  runtime.setStatuses(load_statuses());
  auto fixture = load("fake-status", runtime);
  require(fixture->object->property("surfaceRole").toString() ==
                  QStringLiteral("panel") &&
              fixture->object->property("statuses").toList().size() == 3 &&
              runtime.count(QStringLiteral("fake_status_list")) == 1,
          "fake service list did not load through its named adapter operation");

  QVariant acknowledged;
  require(QMetaObject::invokeMethod(fixture->object.get(),
                                    "acknowledgeForTest",
                                    Q_RETURN_ARG(QVariant, acknowledged),
                                    Q_ARG(QVariant, QVariant(101))) &&
              acknowledged.toBool() &&
              runtime.count(QStringLiteral("fake_status_acknowledge")) == 1,
          "fake service acknowledgement did not use its enumerated operation");

  QVariant opened;
  require(QMetaObject::invokeMethod(
              fixture->object.get(), "openForTest", Q_RETURN_ARG(QVariant, opened),
              Q_ARG(QVariant, QVariant(QStringLiteral("https://example.test")))) &&
              !opened.toBool() &&
              fixture->object->property("undeclaredOpenDenied").toBool() &&
              runtime.denied(QStringLiteral("open_uri")),
          "undeclared URL action escaped the authority-free fake runtime");
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
  require(QMetaObject::invokeMethod(permission_fixture->object.get(),
                                    "refreshPermission") &&
              permission_fixture->object->property("permissionState").toString() ==
              QStringLiteral("GRANTED"),
          "permission fixture did not render its initial availability");
  permission.setNotificationGranted(false);
  require(permission_fixture->object->property("permissionState").toString() ==
              QStringLiteral("DENIED") &&
              permission_fixture->object->property("observedChanges").toInt() == 2,
          "permission fixture did not react visibly to permissionsChanged");
}

} // namespace

int main(int argc, char **argv) {
  QGuiApplication application(argc, argv);
  try {
    if (application.arguments().contains(QStringLiteral("--live-evidence-only"))) {
      test_live_evidence_fixtures();
      return 0;
    }
    test_pomodoro();
    test_pet();
    test_fake_status();
    test_live_evidence_fixtures();
  } catch (const std::exception &error) {
    std::cerr << error.what() << '\n';
    return 1;
  }
  return 0;
}

#include "product_fixtures_test.moc"
