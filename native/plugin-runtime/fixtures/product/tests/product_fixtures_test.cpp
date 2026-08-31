#include "manifest_contract.hpp"

#include <QEventLoop>
#include <QGuiApplication>
#include <QColor>
#include <QQmlComponent>
#include <QQmlContext>
#include <QQmlEngine>
#include <QQuickItem>
#include <QSet>
#include <QStringList>
#include <QTimer>
#include <QVariant>

#include <array>
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
  Q_PROPERTY(QVariantMap permissions READ permissions CONSTANT)

public:
  explicit FakeRuntime(QSet<QString> allowed, bool asynchronous = false,
                       QObject *parent = nullptr)
      : QObject(parent), allowed_(std::move(allowed)),
        asynchronous_(asynchronous) {}

  Q_INVOKABLE QVariant invoke(const QString &capability,
                              const QString &operation,
                              const QVariantMap &payload) {
    const auto request = capability + QStringLiteral("/") + operation;
    if (!allowed_.contains(request)) {
      denied_.push_back(request);
      if (asynchronous_)
        return asynchronousCall(false, QStringLiteral("permission denied"), {});
      return false;
    }
    operations_.push_back(request);
    payloads_.push_back(payload);
    if (asynchronous_) {
      const QVariant value = request == QStringLiteral("storage.private/read")
                                 ? QVariant(QStringLiteral("encoded-result"))
                                 : QVariant();
      return asynchronousCall(true, {}, value);
    }
    return true;
  }

  [[nodiscard]] int count(const QString &request) const {
    return operations_.count(request);
  }

  [[nodiscard]] bool denied(const QString &request) const {
    return denied_.contains(request);
  }

  Q_INVOKABLE bool hasPermission(const QString &capability,
                                 const QString &operation) const {
    return capability == QStringLiteral("notifications.send") &&
           operation == QStringLiteral("send") &&
           allowed_.contains(QStringLiteral("notifications.send/send"));
  }

  Q_INVOKABLE QString permissionState(const QString &capability,
                                      const QString &operation) const {
    return hasPermission(capability, operation) ? QStringLiteral("granted")
                                                : QStringLiteral("denied");
  }

  [[nodiscard]] QVariantMap permissions() const {
    return {{QStringLiteral("notifications.send"),
             QVariantMap{
                 {QStringLiteral("required"), false},
                 {QStringLiteral("state"),
                  allowed_.contains(QStringLiteral("notifications.send/send"))
                      ? QStringLiteral("granted")
                      : QStringLiteral("denied")},
                 {QStringLiteral("operations"),
                  QVariantMap{{QStringLiteral("send"),
                               allowed_.contains(QStringLiteral(
                                   "notifications.send/send"))
                                   ? QStringLiteral("granted")
                                   : QStringLiteral("denied")}}}}}};
  }

signals:
  void callFinished(QObject *call);

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

std::unique_ptr<LoadedFixture> loadEntry(std::string_view name,
                                         std::string_view relative_qml,
                                         FakeRuntime &runtime);

std::unique_ptr<LoadedFixture> load(std::string_view name,
                                    FakeRuntime &runtime) {
  const auto directory = kRoot / name;
  const auto parsed =
      manifest::parse_manifest_v2(read_text(directory / "manifest.json"));
  require(parsed.runtime.api_version == 1,
          "fixture selected an unsupported runtime API");
  return loadEntry(name, parsed.runtime.qml, runtime);
}

std::unique_ptr<LoadedFixture> loadEntry(std::string_view name,
                                         std::string_view relative_qml,
                                         FakeRuntime &runtime) {
  const auto directory = kRoot / name;
  const auto qml = (directory / relative_qml).lexically_normal();
  require(qml.string().starts_with(directory.string()),
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

void test_neutral_surface_fixture() {
  constexpr std::string_view name = "neutral-surfaces";
  const auto directory = kRoot / name;
  const auto parsed =
      manifest::parse_manifest_v2(read_text(directory / "manifest.json"));
  require(parsed.id == "org.omarchy.fixture.neutral-surfaces" &&
              parsed.requests.empty() && parsed.surface_names.size() == 3 &&
              parsed.runtime.surface_qml.size() == 3,
          "neutral fixture did not declare one zero-permission three-surface runtime");

  FakeRuntime runtime({});
  const std::array expected_names = {std::string_view("bar"),
                                     std::string_view("overlay"),
                                     std::string_view("panel")};
  const std::array expected_colors = {QColor(QStringLiteral("#52677a")),
                                      QColor(QStringLiteral("#647052")),
                                      QColor(QStringLiteral("#7a6652"))};
  for (std::size_t index = 0; index < parsed.runtime.surface_qml.size();
       ++index) {
    const auto &entry = parsed.runtime.surface_qml[index];
    require(entry.surface == expected_names[index],
            "neutral fixture surface names were not canonical and exact");
    auto loaded = loadEntry(name, entry.qml, runtime);
    auto *item = qobject_cast<QQuickItem *>(loaded->object.get());
    require(item && item->width() > 0 && item->height() > 0 &&
                item->property("color").value<QColor>() ==
                    expected_colors[index],
            "neutral fixture root was not a visible distinct QQuickItem");
    if (entry.surface != "bar") {
      require(QMetaObject::invokeMethod(item, "open") &&
                  item->property("opened").toBool() &&
                  QMetaObject::invokeMethod(item, "close") &&
                  !item->property("opened").toBool(),
              "neutral panel or overlay did not expose open and close");
    }
  }
}

void test_permission_aware_fixtures() {
  FakeRuntime authorized({QStringLiteral("storage.private/read"),
                          QStringLiteral("storage.private/write")}, true);
  auto authorized_fixture = load("lab-authorized", authorized);
  QEventLoop authorized_loop;
  QTimer::singleShot(50, &authorized_loop, &QEventLoop::quit);
  authorized_loop.exec();
  require(authorized_fixture->object->property("phase").toString() ==
                  QStringLiteral("AUTHORIZED") &&
              authorized.count(QStringLiteral("storage.private/write")) == 1 &&
              authorized.count(QStringLiteral("storage.private/read")) == 1,
          "authorized fixture did not follow async broker completions");

  FakeRuntime denied({QStringLiteral("storage.private/read"),
                      QStringLiteral("storage.private/write")}, true);
  auto denied_fixture = load("lab-denied", denied);
  QEventLoop denied_loop;
  QTimer::singleShot(50, &denied_loop, &QEventLoop::quit);
  denied_loop.exec();
  require(denied_fixture->object->property("phase").toString() ==
                  QStringLiteral("DENIED") &&
              denied.denied(QStringLiteral("notifications.send/send")),
          "denial fixture did not follow async broker denial");

  FakeRuntime permission({QStringLiteral("notifications.send/send")});
  require(permission.permissions()
                  .value(QStringLiteral("notifications.send"))
                  .toMap()
                  .value(QStringLiteral("operations"))
                  .toMap()
                  .value(QStringLiteral("send"))
                  .toString() == QStringLiteral("granted"),
          "permission fixture fake did not expose nested operation state");
  auto permission_fixture = load("lab-permission", permission);
  QEventLoop permission_startup_loop;
  QTimer::singleShot(5, &permission_startup_loop, &QEventLoop::quit);
  permission_startup_loop.exec();
  require(permission_fixture->object->property("permissionState").toString() ==
              QStringLiteral("GRANTED"),
          "permission fixture did not render its initial availability");
}

} // namespace

int main(int argc, char **argv) {
  QGuiApplication application(argc, argv);
  try {
    test_permission_aware_fixtures();
    test_neutral_surface_fixture();
  } catch (const std::exception &error) {
    std::cerr << error.what() << '\n';
    return 1;
  }
  return 0;
}

#include "product_fixtures_test.moc"
