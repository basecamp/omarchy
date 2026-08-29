#include "worker_runtime.hpp"

#include <QFile>
#include <QGuiApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QObject>
#include <QStringList>
#include <QVariantMap>

#include <fcntl.h>
#include <linux/memfd.h>
#include <sys/mman.h>
#include <sys/syscall.h>
#include <unistd.h>

#include <algorithm>
#include <cstddef>
#include <filesystem>
#include <iostream>
#include <map>
#include <ranges>
#include <set>
#include <span>
#include <stdexcept>
#include <string>
#include <vector>

namespace {

namespace surface = omarchy::plugin_runtime::surface;
namespace worker = omarchy::plugin_runtime::worker;

void require(bool condition, const std::string &message) {
  if (!condition)
    throw std::runtime_error(message);
}

class StrictRuntime final : public QObject {
  Q_OBJECT

public:
  explicit StrictRuntime(std::set<std::string> declared)
      : declared_(std::move(declared)) {}

  void register_adapter(std::string operation, std::string capability) {
    adapters_.emplace(std::move(operation), std::move(capability));
  }

  Q_INVOKABLE QVariant invoke(const QString &operation,
                              const QVariantMap &arguments) {
    (void)arguments;
    const auto name = operation.toStdString();
    calls_.push_back(name);
    const auto adapter = adapters_.find(name);
    const bool allowed =
        adapter != adapters_.end() && declared_.contains(adapter->second);
    return QVariantMap{
        {QStringLiteral("ok"), allowed},
        {QStringLiteral("error"), allowed ? QString()
                                  : adapter == adapters_.end()
                                      ? QStringLiteral("unknown-operation")
                                      : QStringLiteral("permission-denied")}};
  }

  [[nodiscard]] bool saw(std::string_view operation) const {
    return std::ranges::find(calls_, operation) != calls_.end();
  }

private:
  std::set<std::string> declared_;
  std::map<std::string, std::string> adapters_;
  std::vector<std::string> calls_;
};

std::set<std::string> declared_permissions(const std::filesystem::path &root) {
  QFile file(QString::fromStdString((root / "manifest.json").string()));
  require(file.open(QIODevice::ReadOnly), "manifest.json cannot be read");
  QJsonParseError error;
  const auto document = QJsonDocument::fromJson(file.readAll(), &error);
  require(error.error == QJsonParseError::NoError && document.isObject(),
          "manifest.json is invalid JSON");
  const auto object = document.object();
  require(object.value(QStringLiteral("schemaVersion")).toInt() == 2,
          "external fixture is not schema v2");
  std::set<std::string> result;
  const auto permissions =
      object.value(QStringLiteral("permissions")).toObject();
  for (const auto &kind :
       {QStringLiteral("required"), QStringLiteral("optional")}) {
    for (const auto &entry : permissions.value(kind).toArray()) {
      const auto capability =
          entry.toObject().value(QStringLiteral("capability")).toString();
      require(!capability.isEmpty(), "permission has no capability");
      result.insert(capability.toStdString());
    }
  }
  return result;
}

class Mapping {
public:
  Mapping(int descriptor, std::size_t size) : size_(size) {
    address_ = static_cast<std::byte *>(
        mmap(nullptr, size, PROT_READ | PROT_WRITE, MAP_SHARED, descriptor, 0));
    require(address_ != MAP_FAILED, "frame mapping failed");
  }
  ~Mapping() {
    if (address_ != MAP_FAILED)
      munmap(address_, size_);
  }
  [[nodiscard]] std::span<const std::byte> bytes() const {
    return {address_, size_};
  }

private:
  std::byte *address_ = reinterpret_cast<std::byte *>(MAP_FAILED);
  std::size_t size_ = 0;
};

void run(const std::filesystem::path &root, std::string_view function) {
  auto permissions = declared_permissions(root);
  StrictRuntime provider(permissions);
  provider.register_adapter("fixture.denied", "desktop.input.inject");
  const auto denied =
      provider.invoke(QStringLiteral("fixture.denied"), {}).toMap();
  require(!denied.value(QStringLiteral("ok")).toBool() &&
              denied.value(QStringLiteral("error")).toString() ==
                  QStringLiteral("permission-denied") &&
              provider.saw("fixture.denied"),
          "strict provider did not deny an undeclared operation");
  const auto unknown =
      provider.invoke(QStringLiteral("winner.magic"), {}).toMap();
  require(!unknown.value(QStringLiteral("ok")).toBool() &&
              unknown.value(QStringLiteral("error")).toString() ==
                  QStringLiteral("unknown-operation"),
          "unregistered winner operation acquired authority");
  if (!permissions.empty()) {
    provider.register_adapter("fixture.declared", *permissions.begin());
    require(provider.invoke(QStringLiteral("fixture.declared"), {})
                .toMap()
                .value(QStringLiteral("ok"))
                .toBool(),
            "registered adapter did not consume a declared generic grant");
  }

  worker::WorkerRuntime runtime(root);
  require(static_cast<bool>(runtime.bind_runtime_api(provider)),
          "strict runtime provider binding failed");
  const auto loaded = runtime.load_manifest_entry();
  require(static_cast<bool>(loaded),
          "fixture QML failed to load: " + loaded.detail);
  require(runtime.object_count() > 1, "fixture did not retain a QML scene");
  require(runtime.invoke_test_function(function),
          "named deterministic test function was absent or rejected");
  require(!runtime.invoke_test_function("toString") &&
              !runtime.invoke_test_function("../stepForTest") &&
              !runtime.invoke_test_function("stepForTest;quit"),
          "test-function allowlist accepted a non-test method");

  require(static_cast<bool>(runtime.select_software_profile(
              surface::software_profile_offer())),
          "fixture rejected the software render profile");
  const auto page_size = sysconf(_SC_PAGESIZE);
  require(page_size > 0, "page size unavailable");
  const auto allocation = surface::make_allocation(
      {.id = 700, .generation = 1}, 1280, 720, 1280, 720, 1, 1,
      static_cast<std::uint64_t>(page_size));
  require(allocation.has_value(), "fixture frame allocation failed");
  const int descriptor = static_cast<int>(
      syscall(SYS_memfd_create, "external-fixture-frame", MFD_CLOEXEC));
  require(descriptor >= 0 &&
              ftruncate(descriptor,
                        static_cast<off_t>(allocation->mapping_bytes)) == 0,
          "fixture frame memfd failed");
  Mapping mapping(descriptor,
                  static_cast<std::size_t>(allocation->mapping_bytes));
  const int worker_descriptor = fcntl(descriptor, F_DUPFD_CLOEXEC, 64);
  close(descriptor);
  require(worker_descriptor >= 0 && static_cast<bool>(runtime.allocate(
                                        *allocation, worker_descriptor)),
          "worker rejected fixture allocation");
  const auto frame = runtime.render();
  auto consumer = surface::FrameConsumer::create(*allocation);
  require(frame.has_value() && consumer.has_value() &&
              consumer->consume(mapping.bytes(), frame->ready) ==
                  surface::ConsumeResult::accepted,
          "fixture did not publish a consumable frame");
  const auto *pixels = consumer->last_frame();
  require(pixels != nullptr && std::ranges::any_of(pixels->pixels,
                                                   [](std::byte value) {
                                                     return value !=
                                                            std::byte{0};
                                                   }),
          "fixture rendered only transparent pixels");
}

} // namespace

int main(int argc, char **argv) {
  try {
    QGuiApplication application(argc, argv);
    const QStringList arguments = application.arguments();
    require(arguments.size() == 5 &&
                arguments.at(1) == QStringLiteral("--root") &&
                arguments.at(3) == QStringLiteral("--function"),
            "usage: external-fixture-test --root PATH --function NAME");
    run(arguments.at(2).toStdString(), arguments.at(4).toStdString());
    std::cout << "external plugin fixture: ok\n";
    return 0;
  } catch (const std::exception &error) {
    std::cerr << "external plugin fixture: " << error.what() << '\n';
    return 1;
  }
}

#include "external_fixture_test.moc"
