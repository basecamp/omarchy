#include "manifest_contract.hpp"

#include <QFile>
#include <QGuiApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QQmlComponent>
#include <QQmlContext>
#include <QQmlEngine>
#include <QSet>
#include <QStringList>
#include <QVariant>

#include <filesystem>
#include <fstream>
#include <memory>
#include <stdexcept>
#include <string>
#include <string_view>

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

class FakeRuntime final : public QObject {
  Q_OBJECT

public:
  explicit FakeRuntime(QSet<QString> allowed, QObject *parent = nullptr)
      : QObject(parent), allowed_(std::move(allowed)) {}

  void setStatuses(QVariantList statuses) { statuses_ = std::move(statuses); }

  Q_INVOKABLE QVariant invoke(const QString &operation,
                              const QVariantMap &payload) {
    if (!allowed_.contains(operation)) {
      denied_.push_back(operation);
      return false;
    }
    operations_.push_back(operation);
    payloads_.push_back(payload);
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

private:
  QSet<QString> allowed_;
  QStringList operations_;
  QStringList denied_;
  QList<QVariantMap> payloads_;
  QVariantList statuses_;
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

} // namespace

int main(int argc, char **argv) {
  QGuiApplication application(argc, argv);
  try {
    test_pomodoro();
    test_pet();
    test_fake_status();
  } catch (const std::exception &error) {
    qCritical("%s", error.what());
    return 1;
  }
  return 0;
}

#include "product_fixtures_test.moc"
