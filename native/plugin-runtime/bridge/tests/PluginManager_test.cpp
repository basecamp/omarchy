#include "PluginManager.h"

#include "omarchy/plugin_runtime/Version.h"
#include "omarchy/plugin_runtime/runtime_paths.hpp"
#include "runtime_bootstrap.hpp"
#include "runtime_roots.hpp"
#include "runtime_roots_test_access.hpp"
#include "remote_surface.hpp"
#include "revision_verifier_adapter.hpp"
#include "authority_store.hpp"

#include <QCoreApplication>
#include <QColor>
#include <QImage>
#include <QJSValue>
#include <QMetaMethod>
#include <QPainter>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QQuickItem>
#include <QQuickWindow>
#include <QUrl>
#include <QtQml/qqml.h>

#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

#include <algorithm>
#include <atomic>
#include <barrier>
#include <chrono>
#include <condition_variable>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <functional>
#include <ranges>
#include <mutex>
#include <stdexcept>
#include <string>
#include <string_view>
#include <thread>

namespace {

namespace bridge = omarchy::plugin_runtime::bridge;
namespace permissions = omarchy::plugins::permissions;
namespace channel = omarchy::plugin_runtime::channel;
namespace host = omarchy::plugin_runtime::host_session;
namespace policy = omarchy::plugin_runtime::policy;
namespace definitions = omarchy::plugins::definitions;

void require(bool condition, std::string_view message) {
  if (!condition)
    throw std::runtime_error(std::string(message));
}

void process_singleton_factory_is_exact_and_recoverable() {
  require(bridge::PluginManagerTestAccess::processClaimAvailable(),
          "process singleton claim was not initially available");
  QQmlEngine first_engine;
  QQmlEngine second_engine;
  require(!bridge::PluginManager::create(nullptr, nullptr) &&
              !bridge::PluginManager::create(&first_engine, nullptr) &&
              !bridge::PluginManager::create(nullptr, &first_engine) &&
              !bridge::PluginManager::create(&first_engine, &second_engine) &&
              bridge::PluginManagerTestAccess::processClaimAvailable(),
          "invalid engine pair consumed the process singleton claim");

  std::atomic<bridge::PluginManager *> wrong_thread_result = nullptr;
  std::thread wrong_thread([&] {
    wrong_thread_result.store(
        bridge::PluginManager::create(&first_engine, &first_engine),
        std::memory_order_release);
  });
  wrong_thread.join();
  require(!wrong_thread_result.load(std::memory_order_acquire) &&
              bridge::PluginManagerTestAccess::processClaimAvailable(),
          "wrong-thread factory call consumed the process singleton claim");

  bridge::PluginManagerTestAccess::failNextConstruction();
  require(!bridge::PluginManager::create(&first_engine, &first_engine) &&
              bridge::PluginManagerTestAccess::processClaimAvailable(),
          "constructor failure did not roll back the process singleton claim");

  auto *first = bridge::PluginManager::create(&first_engine, &first_engine);
  require(first && first->parent() == &first_engine &&
              !bridge::PluginManagerTestAccess::processClaimAvailable() &&
              !bridge::PluginManager::create(&first_engine, &first_engine) &&
              !bridge::PluginManager::create(&second_engine, &second_engine),
          "live manager did not exclusively retain its exact engine claim");
  delete first;
  require(bridge::PluginManagerTestAccess::processClaimAvailable(),
          "manager teardown did not release the process singleton claim");

  auto *replacement =
      bridge::PluginManager::create(&second_engine, &second_engine);
  require(replacement && replacement->parent() == &second_engine,
          "a replacement engine could not claim the process singleton");
  delete replacement;
  require(bridge::PluginManagerTestAccess::processClaimAvailable(),
          "replacement teardown did not release the process singleton claim");
}

void concurrent_engines_have_one_process_winner() {
  for (int iteration = 0; iteration < 32; ++iteration) {
    std::barrier enter_factory(2);
    std::barrier hold_winner(2);
    std::atomic<int> successes = 0;
    auto contender = [&] {
      QQmlEngine engine;
      enter_factory.arrive_and_wait();
      auto *manager = bridge::PluginManager::create(&engine, &engine);
      if (manager)
        successes.fetch_add(1, std::memory_order_relaxed);
      hold_winner.arrive_and_wait();
      delete manager;
    };
    std::thread first(contender);
    std::thread second(contender);
    first.join();
    second.join();
    require(successes.load(std::memory_order_relaxed) == 1 &&
                bridge::PluginManagerTestAccess::processClaimAvailable(),
            "concurrent engines did not produce one exact process winner");
  }
}

template <typename Predicate> bool await(Predicate predicate) {
  const auto deadline =
      std::chrono::steady_clock::now() + std::chrono::seconds(2);
  while (std::chrono::steady_clock::now() < deadline) {
    QCoreApplication::processEvents();
    if (predicate())
      return true;
    std::this_thread::sleep_for(std::chrono::milliseconds(1));
  }
  return predicate();
}

permissions::ActivationBinding binding() {
  return {
      .plugin = permissions::PluginId("org.example.singleton"),
      .revision = permissions::Digest(std::string(64, 'a')),
      .policy_fingerprint = permissions::Digest(std::string(64, 'b')),
      .generation = 4,
  };
}

std::string activationRecord(std::string_view plugin, char digest = 'a') {
  return "format=omarchy-plugin-activation-v2\nplugin=" + std::string(plugin) +
         "\nrevision-directory=revision\nrevision-sha256=" +
         std::string(64, digest) + "\nstate-directory=" + std::string(plugin) +
         "\n";
}

std::string readyActivationRecord(std::string_view plugin,
                                  std::string_view revision_directory,
                                  std::string_view revision_sha256) {
  return "format=omarchy-plugin-activation-v2\nplugin=" +
         std::string(plugin) + "\nrevision-directory=" +
         std::string(revision_directory) + "\nrevision-sha256=" +
         std::string(revision_sha256) +
         "\nstate-directory=" + std::string(plugin) + "\n";
}

class RuntimeFixture final {
public:
  RuntimeFixture() {
    std::string pattern = "/tmp/omarchy-manager-runtime.XXXXXX";
    const auto *created = ::mkdtemp(pattern.data());
    require(created != nullptr, "manager runtime fixture creation failed");
    root_ = created;
    require(::chmod(root_.c_str(), 0755) == 0,
            "manager runtime fixture root mode failed");
    home_ = root_ / "home";
    create(home_, 0700);
    create(home_ / ".local/share/omarchy/plugin-security/v2/revisions", 0700);
    create(home_ / ".local/state/omarchy/plugin-security/v2/activations", 0700);
    create(home_ / ".local/state/omarchy/plugin-security/v2/authority", 0700);
    create(home_ / ".local/state/omarchy/plugin-security/v2/state", 0700);
    create(root_ / "usr/lib/omarchy/plugin-security" /
               std::string(omarchy::plugin_runtime::build_version()) /
               "capabilities.d",
           0755);
  }

  ~RuntimeFixture() {
    std::error_code ignored;
    std::filesystem::remove_all(root_, ignored);
  }

  void put(std::string_view plugin, char digest = 'a') {
    write(plugin, activationRecord(plugin, digest), O_CREAT | O_EXCL);
  }

  void overwrite(std::string_view plugin, char digest) {
    write(plugin, activationRecord(plugin, digest), O_TRUNC);
  }

  void putInvalid() { write("!", "invalid\n", O_CREAT | O_EXCL); }

  permissions::ActivationBinding seedRuntime(
      std::string_view plugin,
      std::string_view qml = "import QtQuick\nItem {}\n") {
    const auto binding = stageRuntime(plugin, 1, qml);
    promoteRuntime(binding, 0);
    write(plugin,
          readyActivationRecord(plugin, revisionDirectory(plugin, 1),
                                binding.revision.view()),
          O_CREAT | O_EXCL);
    return binding;
  }

  permissions::ActivationBinding stageRuntime(std::string_view plugin,
                                              std::uint64_t generation,
                                              std::string_view qml) {
    const auto revision_name = revisionDirectory(plugin, generation);
    const auto revision = revisions() / revision_name;
    create(revision / "ui", 0755);
    {
      std::ofstream manifest_file(revision / "manifest.json");
      manifest_file
          << "{\n  \"schemaVersion\": 2,\n  \"id\": \"" << plugin
          << "\",\n  \"name\": \"Manager fixture\",\n"
             "  \"version\": \"1.0.0\",\n"
             "  \"runtime\": {\"apiVersion\": 1, \"qml\": "
             "\"ui/Main.qml\"},\n  \"surfaces\": {\"bar\": {"
             "\"role\": \"bar-embedded\", \"defaultSection\": "
             "\"right\", \"maximumWidth\": 320, \"maximumHeight\": 64, "
             "\"maximumFramesPerSecond\": 60}},\n  \"permissions\": {"
             "\"required\": [], "
             "\"optional\": []}\n}\n";
    }
    std::ofstream(revision / "ui/Main.qml") << qml;
    for (const auto &entry :
         std::filesystem::recursive_directory_iterator(revision))
      require(::chmod(entry.path().c_str(),
                      entry.is_directory() ? 0555 : 0444) == 0,
              "manager ready revision mode failed");
    require(::chmod(revision.c_str(), 0555) == 0,
            "manager ready revision root mode failed");
    if (generation == 1) {
      create(state() / std::string(plugin), 0700);
      create(authority() / std::string(plugin), 0700);
    }

    const int revision_fd = ::open(
        revision.c_str(), O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
    require(revision_fd >= 0, "manager ready revision open failed");
    host::DescriptorRevisionVerifier verifier;
    auto verified = verifier.verify_open_revision(revision_fd);
    ::close(revision_fd);
    require(verified && verified->manifest.id == plugin,
            "manager ready revision verification failed");

    return {
        .plugin = permissions::PluginId(plugin),
        .revision = permissions::Digest(verified->tree_sha256),
        .policy_fingerprint = permissions::Digest(
            permissions::policy_request_fingerprint(
                permissions::requests_from_manifest(verified->manifest))),
        .generation = generation,
    };
  }

  void promoteRuntime(const permissions::ActivationBinding &binding,
                      std::uint64_t expected_sequence) {
    const int authority_fd = ::open(
        (authority() / std::string(binding.plugin.view())).c_str(),
        O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
    require(authority_fd >= 0, "manager ready authority open failed");
    auto store = host::AuthorityStore::open(
        authority_fd, ::getuid(), binding.plugin);
    ::close(authority_fd);
    require(store != nullptr, "manager ready authority store failed");

    const auto revision = revisions() /
                          revisionDirectory(binding.plugin.view(),
                                            binding.generation);
    const int revision_fd = ::open(
        revision.c_str(), O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
    require(revision_fd >= 0, "manager ready revision reopen failed");
    host::DescriptorRevisionVerifier verifier;
    auto verified = verifier.verify_open_revision(revision_fd);
    ::close(revision_fd);
    require(verified && verified->tree_sha256 == binding.revision.view(),
            "manager staged revision identity changed");
    policy::GrantSnapshot snapshot;
    snapshot.requests =
        permissions::requests_from_manifest(verified->manifest);
    snapshot.binding = binding;
    snapshot.source_request_fingerprint =
        permissions::Digest(verified->request_sha256);
    definitions::TrustedDefinitionRegistry registry;
    require(store->publish_candidate(*verified, snapshot, expected_sequence,
                                     registry, {}) ==
                    host::AuthorityMutationResult::applied &&
                store->promote_candidate(snapshot.binding,
                                         expected_sequence + 1) ==
                    host::AuthorityMutationResult::applied,
            "manager ready authority activation failed");
  }

  void selectReplacement(const permissions::ActivationBinding &binding) {
    require(std::filesystem::remove(activations() /
                                    std::string(binding.plugin.view())),
            "manager ready activation replacement unlink failed");
    write(binding.plugin.view(),
          readyActivationRecord(binding.plugin.view(),
                                revisionDirectory(binding.plugin.view(),
                                                  binding.generation),
                                binding.revision.view()),
          O_CREAT | O_EXCL);
  }

  void erase(std::string_view name) {
    require(std::filesystem::remove(activations() / std::string(name)),
            "manager runtime fixture erase failed");
  }

  std::unique_ptr<channel::RuntimeBootstrap> bootstrap() const {
    const int home =
        ::open(home_.c_str(), O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
    require(home >= 0, "manager runtime fixture home unavailable");
    channel::RuntimeRootsError roots_error{};
    auto roots = channel::RuntimeRootsTestAccess::open_from_home_fd(
        home, static_cast<std::uint32_t>(::getuid()), roots_error);
    ::close(home);
    require(roots && roots_error == channel::RuntimeRootsError::none,
            "manager runtime fixture roots rejected");
    const int filesystem_root =
        ::open(root_.c_str(), O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
    require(filesystem_root >= 0,
            "manager runtime fixture filesystem root unavailable");
    channel::RuntimeBootstrapError bootstrap_error{};
    auto result =
        channel::RuntimeBootstrapTestAccess::open_from_filesystem_root(
            std::move(roots), filesystem_root,
            static_cast<std::uint32_t>(::getuid()), bootstrap_error);
    ::close(filesystem_root);
    require(result && bootstrap_error ==
                          channel::RuntimeBootstrapError::none,
            "manager runtime fixture bootstrap rejected");
    return result;
  }

private:
  static std::string revisionDirectory(std::string_view plugin,
                                       std::uint64_t generation) {
    return std::string(plugin) + "-g" + std::to_string(generation);
  }

  std::filesystem::path activations() const {
    return home_ / ".local/state/omarchy/plugin-security/v2/activations";
  }
  std::filesystem::path revisions() const {
    return home_ / ".local/share/omarchy/plugin-security/v2/revisions";
  }
  std::filesystem::path authority() const {
    return home_ / ".local/state/omarchy/plugin-security/v2/authority";
  }
  std::filesystem::path state() const {
    return home_ / ".local/state/omarchy/plugin-security/v2/state";
  }

  void create(const std::filesystem::path &path, mode_t leaf_mode) {
    auto current = root_;
    for (const auto &component : path.lexically_relative(root_)) {
      current /= component;
      const bool created = std::filesystem::create_directory(current);
      const bool leaf = current == path;
      if (created || leaf)
        require(::chmod(current.c_str(), leaf ? leaf_mode : 0755) == 0,
                "manager runtime fixture directory mode failed");
    }
  }

  void write(std::string_view name, std::string_view bytes, int flags) {
    const auto path = activations() / std::string(name);
    const int descriptor =
        ::open(path.c_str(), O_WRONLY | O_CLOEXEC | O_NOFOLLOW | flags, 0600);
    require(descriptor >= 0, "manager runtime fixture record open failed");
    std::size_t offset = 0;
    while (offset < bytes.size()) {
      const auto count =
          ::write(descriptor, bytes.data() + offset, bytes.size() - offset);
      require(count > 0, "manager runtime fixture record write failed");
      offset += static_cast<std::size_t>(count);
    }
    require(::close(descriptor) == 0,
            "manager runtime fixture record close failed");
  }

  std::filesystem::path root_;
  std::filesystem::path home_;
};

class DeterministicJobs final {
public:
  bool submit(bridge::PluginManagerTestAccess::TestJobKind kind,
              std::function<void()> job) {
    if (throws)
      throw std::runtime_error("injected submit failure");
    if (refuses)
      return false;
    kinds.push_back(kind);
    jobs.push_back(std::move(job));
    peak = std::max(peak, jobs.size());
    return true;
  }

  void runOne() {
    runAt(0);
  }

  void runAt(std::size_t index) {
    require(!jobs.empty(), "deterministic scheduler had no queued job");
    require(index < jobs.size(), "deterministic scheduler index was invalid");
    auto job = std::move(jobs[index]);
    jobs.erase(jobs.begin() + static_cast<std::ptrdiff_t>(index));
    kinds.erase(kinds.begin() + static_cast<std::ptrdiff_t>(index));
    job();
  }

  std::vector<bridge::PluginManagerTestAccess::TestJobKind> kinds;
  std::vector<std::function<void()>> jobs;
  std::size_t peak = 0;
  bool refuses = false;
  bool throws = false;
};

const bridge::PluginManagerTestAccess::SlotObservation &
observed(const std::vector<bridge::PluginManagerTestAccess::SlotObservation>
             &observations,
         std::string_view plugin) {
  const auto found = std::ranges::find(
      observations, plugin,
      &bridge::PluginManagerTestAccess::SlotObservation::plugin);
  require(found != observations.end(), "expected manager runtime slot absent");
  return *found;
}

std::vector<bridge::SurfaceProjectionModel::SurfaceDeclaration>
barDeclaration() {
  using Model = bridge::SurfaceProjectionModel;
  std::vector<Model::SurfaceDeclaration> declarations;
  declarations.push_back({.surface_name = "bar",
                          .role = Model::Role::Bar,
                          .screen_name = {},
                          .initially_visible = false,
                          .maximum_width = 64,
                          .maximum_height = 64,
                          .dynamic_input_regions = false,
                          .default_bar_section = Model::BarSection::Right});
  return declarations;
}

QString barSurfaceKey(bridge::PluginManager &manager,
                      std::string_view plugin) {
  using Model = bridge::SurfaceProjectionModel;
  const auto expected = QString::fromUtf8(plugin.data(), plugin.size());
  auto *model = manager.barSurfaces();
  for (int row = 0; row < model->rowCount(); ++row) {
    const auto index = model->index(row, 0);
    if (model->data(index, Model::PluginIdRole).toString() == expected)
      return model->data(index, Model::SurfaceKeyRole).toString();
  }
  return {};
}

QImage paintedFrame(bridge::RemotePluginSurface &remote) {
  QImage image(64, 64, QImage::Format_RGBA8888_Premultiplied);
  image.fill(Qt::transparent);
  QPainter painter(&image);
  remote.paint(&painter);
  painter.end();
  return image;
}

bool redSignature(const QImage &image) {
  const auto color = image.pixelColor(32, 32);
  return color.alpha() >= 250 && color.red() >= 160 &&
         color.red() >= color.green() + 90 &&
         color.red() >= color.blue() + 80;
}

bool blueSignature(const QImage &image) {
  const auto color = image.pixelColor(32, 32);
  return color.alpha() >= 250 && color.blue() >= 170 &&
         color.blue() >= color.red() + 100 &&
         color.blue() >= color.green() + 90;
}

bool greenSignature(const QImage &image) {
  const auto center = image.pixelColor(32, 32);
  const auto border = image.pixelColor(2, 2);
  return center.alpha() >= 250 && center.green() >= 140 &&
         center.green() >= center.red() + 90 &&
         center.green() >= center.blue() + 100 && border.red() >= 190 &&
         border.green() >= 150 && border.blue() <= 100;
}

constexpr std::string_view animatedRedQml = R"QML(import QtQuick
Item {
  property real phase: 0
  NumberAnimation on phase { from: 0; to: 1; duration: 240; loops: Animation.Infinite }
  Rectangle { anchors.fill: parent; color: Qt.rgba(0.65 + parent.phase * 0.35, 0.05, 0.08, 1) }
}
)QML";

constexpr std::string_view animatedBlueQml = R"QML(import QtQuick
Item {
  property real phase: 0
  NumberAnimation on phase { from: 0; to: 1; duration: 300; loops: Animation.Infinite }
  Rectangle { anchors.fill: parent; color: Qt.rgba(0.04, 0.08 + parent.phase * 0.2, 0.7 + parent.phase * 0.25, 1) }
}
)QML";

constexpr std::string_view animatedGreenQml = R"QML(import QtQuick
Item {
  property real phase: 0
  SequentialAnimation on phase {
    loops: Animation.Infinite
    NumberAnimation { to: 1; duration: 180; easing.type: Easing.InOutQuad }
    NumberAnimation { to: 0; duration: 180; easing.type: Easing.InOutQuad }
  }
  Rectangle {
    anchors.fill: parent
    color: Qt.rgba(0.12, 0.55 + parent.phase * 0.4, 0.06, 1)
    border.width: 6
    border.color: "#ffdc39"
  }
}
)QML";

std::filesystem::path secureBarQmlPath() {
  return std::filesystem::path(__FILE__)
             .parent_path()
             .parent_path()
             .parent_path() /
         "shell/SecureBarSurface.qml";
}

std::unique_ptr<QObject>
createSecureBar(QQmlComponent &component, QObject &service, QString surface_key,
                std::uint64_t generation, QQuickItem &parent) {
  QVariantMap properties{
      {QStringLiteral("surfaceService"),
       QVariant::fromValue(static_cast<QObject *>(&service))},
      {QStringLiteral("surfaceKey"), std::move(surface_key)},
      {QStringLiteral("generation"), QString::number(generation)},
      {QStringLiteral("maximumWidth"), 64},
      {QStringLiteral("maximumHeight"), 64},
  };
  std::unique_ptr<QObject> object(
      component.createWithInitialProperties(properties));
  require(object != nullptr, "secure bar wrapper did not instantiate");
  auto *item = qobject_cast<QQuickItem *>(object.get());
  require(item != nullptr, "secure bar wrapper root was not a QQuickItem");
  item->setParentItem(&parent);
  item->setWidth(64);
  item->setHeight(64);
  require(item->width() == 64 && item->height() == 64,
          "secure bar wrapper geometry did not settle");
  return object;
}

void secure_bar_retries_only_on_readiness_events() {
  QQmlEngine engine;
  QQmlComponent component(
      &engine,
      QUrl::fromLocalFile(QString::fromStdString(secureBarQmlPath())));
  if (!component.isReady()) {
    std::string errors = "secure bar QML component did not load:";
    for (const auto &error : component.errors())
      errors += "\n" + error.toString().toStdString();
    throw std::runtime_error(errors);
  }
  QJSValue service = engine.evaluate(
      "({ attempts: 0, lastKey: '', lastSurface: null, "
      "attach: function(key, surface) { this.attempts += 1; "
      "this.lastKey = key; this.lastSurface = surface; return false; } })");
  require(!service.isError(), "counting surface service did not initialize");
  QVariantMap properties{
      {QStringLiteral("surfaceService"), QVariant::fromValue(service)},
      {QStringLiteral("surfaceKey"), QStringLiteral("first-key")},
      {QStringLiteral("generation"), QStringLiteral("1")},
      {QStringLiteral("maximumWidth"), 0},
      {QStringLiteral("maximumHeight"), 0},
  };
  std::unique_ptr<QObject> object(
      component.createWithInitialProperties(properties));
  require(object != nullptr, "secure bar QML component did not instantiate");
  auto *item = qobject_cast<QQuickItem *>(object.get());
  auto *remote = object->findChild<bridge::RemotePluginSurface *>();
  require(item && remote && item->width() == 0 && item->height() == 0 &&
              service.property("attempts").toInt() == 0,
          "zero-geometry secure bar attempted attachment on completion");

  QQuickWindow window;
  window.resize(128, 64);
  window.show();
  item->setParentItem(window.contentItem());
  QCoreApplication::processEvents();
  require(remote->window() == &window && remote->width() == 0 &&
              remote->height() == 0 &&
              service.property("attempts").toInt() == 0,
          "window readiness bypassed zero-geometry attachment guard");
  item->setWidth(64);
  QCoreApplication::processEvents();
  require(service.property("attempts").toInt() == 0,
          "partial geometry triggered attachment");
  item->setHeight(64);
  QCoreApplication::processEvents();
  require(service.property("attempts").toInt() == 1 &&
              service.property("lastKey").toString() ==
                  QStringLiteral("first-key") &&
              service.property("lastSurface").toQObject() == remote,
          "settled geometry did not make one exact attachment attempt");

  require(item->setProperty("surfaceKey", QStringLiteral("replacement-key")) &&
              service.property("attempts").toInt() == 2 &&
              service.property("lastKey").toString() ==
                  QStringLiteral("replacement-key"),
          "replacement surface key did not make one retry attempt");
  const auto deadline =
      std::chrono::steady_clock::now() + std::chrono::milliseconds(100);
  while (std::chrono::steady_clock::now() < deadline) {
    QCoreApplication::processEvents();
    std::this_thread::sleep_for(std::chrono::milliseconds(1));
  }
  require(service.property("attempts").toInt() == 2,
          "secure bar polled or retried without a readiness event");
}

void singleton_boundary_is_inert_and_not_configurable() {
  auto manager_owner = bridge::PluginManagerTestAccess::create();
  auto &manager = *manager_owner;
  const auto version = omarchy::plugin_runtime::build_version();
  require(!manager.available() && manager.count() == 0 &&
              manager.barSurfaces()->rowCount() == 0 &&
              manager.panelSurfaces()->rowCount() == 0 &&
              manager.overlaySurfaces()->rowCount() == 0 &&
              manager.runtimeVersion() ==
                  QString::fromLatin1(version.data(), version.size()),
          "singleton boundary did not start inert");

  const auto *meta = manager.metaObject();
  for (int index = meta->methodOffset(); index < meta->methodCount(); ++index) {
    const auto name = meta->method(index).name();
    require(name != "publishSurfaces" && name != "withdrawSurfaces" &&
                name != "publishIntent" && name != "bindBackend",
            "authority/configuration method escaped into the QML metaobject");
  }
  bridge::RemotePluginSurface remote;
  require(!manager.attach(QStringLiteral("missing"), &remote),
          "inert singleton accepted an unpublished surface");
  QCoreApplication::processEvents();
  require(!manager.available(),
          "test-only inert singleton unexpectedly installed a runtime");
}

void private_projection_seam_preserves_fail_closed_boundary() {
  using Service = bridge::SurfaceProjectionModel;
  auto manager_owner = bridge::PluginManagerTestAccess::create();
  auto &manager = *manager_owner;
  int changes = 0;
  QObject::connect(&manager, &bridge::PluginManager::surfacesChanged,
                   [&changes] { ++changes; });
  std::vector<Service::SurfaceDeclaration> declarations;
  declarations.push_back({.surface_name = "panel",
                          .role = Service::Role::Panel,
                          .screen_name = QStringLiteral("DP-1"),
                          .initially_visible = false,
                          .maximum_width = 640,
                          .maximum_height = 480,
                          .dynamic_input_regions = true});
  const auto exact = binding();
  require(bridge::SurfaceProjectionModelTestAccess::publish(
              manager, exact, std::move(declarations), 1) &&
              manager.count() == 1 && changes == 1 && !manager.available(),
          "private readiness seam did not project one exact row");

  const auto key =
      manager.panelSurfaces()
          ->data(manager.panelSurfaces()->index(0, 0), Service::SurfaceKeyRole)
          .toString();
  bridge::RemotePluginSurface remote;
  require(!manager.attach(key, &remote),
          "projection without an exact endpoint owner accepted attachment");

  bool off_thread = true;
  std::thread worker([&] {
    off_thread =
        bridge::SurfaceProjectionModelTestAccess::withdraw(manager, exact);
  });
  worker.join();
  require(
      !off_thread && manager.count() == 1 &&
          bridge::SurfaceProjectionModelTestAccess::withdraw(manager, exact) &&
          manager.count() == 0 && changes == 2,
      "projection seam escaped UI-thread or exact-binding confinement");
}

void manager_policy_is_fixed_and_fail_closed() {
  RuntimeFixture fixture;
  auto manager = bridge::PluginManagerTestAccess::create();
  bridge::PluginManagerTestAccess::installRuntime(*manager,
                                                  fixture.bootstrap());
  require(bridge::PluginManagerTestAccess::clockIsNondecreasing(*manager),
          "manager clock was not monotonic");
}

void last_good_reconciliation_and_stale_callback_are_fail_closed() {
  RuntimeFixture fixture;
  fixture.put("a.plugin");
  auto manager_owner = bridge::PluginManagerTestAccess::create();
  auto &manager = *manager_owner;
  bridge::PluginManagerTestAccess::installRuntime(manager, fixture.bootstrap());
  require(bridge::PluginManagerTestAccess::scanRuntime(manager) &&
              manager.available() && manager.count() == 0,
          "first good catalog did not establish unpublished service health");
  require(await([&] {
            bridge::PluginManagerTestAccess::drainRuntime(manager);
            const auto observations =
                bridge::PluginManagerTestAccess::runtimeSlots(manager);
            return observations.size() == 1 && observations[0].retry_wait;
          }),
          "missing plugin authority did not settle into isolated retry");
  const auto first = bridge::PluginManagerTestAccess::runtimeSlots(manager);
  require(first.size() == 1 && observed(first, "a.plugin").retry_wait,
          "missing plugin authority did not enter isolated retry");
  const auto a_epoch = observed(first, "a.plugin").epoch;
  const auto a_attempts = observed(first, "a.plugin").retry_attempts;

  require(bridge::PluginManagerTestAccess::scanRuntime(manager),
          "same-epoch catalog scan failed");
  const auto same = bridge::PluginManagerTestAccess::runtimeSlots(manager);
  require(observed(same, "a.plugin").epoch == a_epoch &&
              observed(same, "a.plugin").retry_attempts == a_attempts,
          "same catalog epoch recreated retry state");

  fixture.putInvalid();
  require(!bridge::PluginManagerTestAccess::scanRuntime(manager),
          "failed catalog scan was accepted");
  const auto failed = bridge::PluginManagerTestAccess::runtimeSlots(manager);
  require(observed(failed, "a.plugin").epoch == a_epoch && manager.available(),
          "failed scan replaced the last-good catalog or service health");
  fixture.erase("!");

  fixture.put("b.plugin");
  require(bridge::PluginManagerTestAccess::scanRuntime(manager),
          "independent plugin addition failed");
  require(await([&] {
            bridge::PluginManagerTestAccess::drainRuntime(manager);
            const auto observations =
                bridge::PluginManagerTestAccess::runtimeSlots(manager);
            return observations.size() == 2 &&
                   observed(observations, "b.plugin").retry_wait;
          }),
          "independent B preparation did not settle");
  const auto added = bridge::PluginManagerTestAccess::runtimeSlots(manager);
  require(added.size() == 2 && observed(added, "a.plugin").epoch == a_epoch,
          "adding B recreated unchanged A");
  const auto b_epoch = observed(added, "b.plugin").epoch;
  require(bridge::PluginManagerTestAccess::queueStaleRunningCallback(
              manager, "b.plugin"),
          "exact B epoch callback could not be queued through Hook");
  require(bridge::PluginManagerTestAccess::retryRuntime(manager, "b.plugin"),
          "missing-authority B retry was not independently runnable");
  require(await([&] {
            bridge::PluginManagerTestAccess::drainRuntime(manager);
            const auto observations =
                bridge::PluginManagerTestAccess::runtimeSlots(manager);
            return observed(observations, "b.plugin").retry_wait;
          }),
          "independent B retry did not settle");
  const auto retried = bridge::PluginManagerTestAccess::runtimeSlots(manager);
  require(observed(retried, "a.plugin").epoch == a_epoch &&
              observed(retried, "b.plugin").epoch != b_epoch,
          "retrying B recreated independent A");

  const auto current_b = observed(retried, "b.plugin").epoch;
  fixture.overwrite("a.plugin", 'b');
  require(bridge::PluginManagerTestAccess::scanRuntime(manager),
          "changed A catalog epoch failed");
  require(await([&] {
            bridge::PluginManagerTestAccess::drainRuntime(manager);
            const auto observations =
                bridge::PluginManagerTestAccess::runtimeSlots(manager);
            return observed(observations, "a.plugin").retry_wait;
          }),
          "changed A preparation did not settle");
  const auto replaced = bridge::PluginManagerTestAccess::runtimeSlots(manager);
  require(observed(replaced, "a.plugin").epoch != a_epoch &&
              observed(replaced, "b.plugin").epoch == current_b,
          "changing A replaced an independent B slot");

  fixture.erase("a.plugin");
  require(bridge::PluginManagerTestAccess::scanRuntime(manager),
          "successful plugin absence failed");
  const auto removed = bridge::PluginManagerTestAccess::runtimeSlots(manager);
  require(removed.size() == 1 && removed[0].plugin == "b.plugin" &&
              removed[0].epoch == current_b,
          "successful A absence disturbed retained B");
  QCoreApplication::processEvents();
  const auto late = bridge::PluginManagerTestAccess::runtimeSlots(manager);
  require(late[0].epoch == current_b && late[0].retry_wait &&
              manager.count() == 0,
          "stale hook callback altered its replacement or published QML");
  bridge::RemotePluginSurface remote;
  require(!manager.attach(QStringLiteral("anything"), &remote),
          "running-unpublished manager admitted attachment without readiness");
}

void bounded_mailbox_coalesces_and_recovers_without_backoff() {
  {
    RuntimeFixture fixture;
    DeterministicJobs scheduler;
    auto manager = bridge::PluginManagerTestAccess::create();
    bridge::PluginManagerTestAccess::installRuntime(*manager,
                                                    fixture.bootstrap());
    bridge::PluginManagerTestAccess::setJobSubmitter(
        *manager, [&](auto kind, auto job) {
          return scheduler.submit(kind, std::move(job));
        });
    for (int index = 0; index < 1000; ++index)
      bridge::PluginManagerTestAccess::requestAsyncScan(*manager);
    require(scheduler.jobs.size() == 1 &&
                scheduler.kinds.front() ==
                    bridge::PluginManagerTestAccess::TestJobKind::scan &&
                bridge::PluginManagerTestAccess::scanInFlight(*manager),
            "catalog scans did not coalesce to one exact mailbox lane");
    scheduler.runOne();
    for (int index = 0; index < 1000; ++index)
      bridge::PluginManagerTestAccess::requestAsyncScan(*manager);
    require(scheduler.jobs.empty() &&
                bridge::PluginManagerTestAccess::scanInFlight(*manager),
            "undrained catalog result admitted another scan");
    bridge::PluginManagerTestAccess::drainRuntime(*manager);
    require(!bridge::PluginManagerTestAccess::scanInFlight(*manager) &&
                manager->available(),
            "catalog mailbox drain did not release exact scan accounting");
  }

  {
    RuntimeFixture fixture;
    fixture.put("a.plugin");
    fixture.put("b.plugin");
    fixture.put("c.plugin");
    DeterministicJobs scheduler;
    auto manager = bridge::PluginManagerTestAccess::create();
    bridge::PluginManagerTestAccess::installRuntime(*manager,
                                                    fixture.bootstrap());
    bridge::PluginManagerTestAccess::setJobSubmitter(
        *manager, [&](auto kind, auto job) {
          return scheduler.submit(kind, std::move(job));
        });
    require(bridge::PluginManagerTestAccess::scanRuntime(*manager) &&
                scheduler.jobs.size() == 2 &&
                std::ranges::all_of(scheduler.kinds, [](auto kind) {
                  return kind == bridge::PluginManagerTestAccess::TestJobKind::
                                     preparation;
                }) &&
                bridge::PluginManagerTestAccess::preparationCount(*manager) ==
                    2,
            "preparation scheduler did not enforce its two-lane bound");
    scheduler.runOne();
    scheduler.runOne();
    require(bridge::PluginManagerTestAccess::preparationCount(*manager) == 2 &&
                bridge::PluginManagerTestAccess::occupiedPreparationLanes(
                    *manager) == 2,
            "undrained preparations escaped mailbox accounting");
    bridge::PluginManagerTestAccess::drainRuntime(*manager);
    require(scheduler.jobs.size() == 1 && scheduler.peak == 2 &&
                bridge::PluginManagerTestAccess::preparationCount(*manager) ==
                    1,
            "third plugin was not scheduled only after two-lane drain");
  }

  for (const bool inject_throw : {false, true}) {
    RuntimeFixture fixture;
    fixture.put("a.plugin");
    DeterministicJobs scheduler;
    scheduler.refuses = !inject_throw;
    scheduler.throws = inject_throw;
    auto manager = bridge::PluginManagerTestAccess::create();
    bridge::PluginManagerTestAccess::installRuntime(*manager,
                                                    fixture.bootstrap());
    bridge::PluginManagerTestAccess::setJobSubmitter(
        *manager, [&](auto kind, auto job) {
          return scheduler.submit(kind, std::move(job));
        });
    require(bridge::PluginManagerTestAccess::scanRuntime(*manager),
            "submit-failure fixture catalog was rejected");
    const auto refused = bridge::PluginManagerTestAccess::runtimeSlots(*manager);
    require(refused.size() == 1 && refused[0].opening && !refused[0].preparing &&
                refused[0].retry_attempts == 0 &&
                bridge::PluginManagerTestAccess::preparationCount(*manager) ==
                    0,
            "scheduler refusal/throw consumed plugin failure backoff");
    scheduler.refuses = false;
    scheduler.throws = false;
    bridge::PluginManagerTestAccess::drainRuntime(*manager);
    require(scheduler.jobs.size() == 1 &&
                bridge::PluginManagerTestAccess::preparationCount(*manager) ==
                    1,
            "opening slot did not recover after scheduler refusal/throw");
  }
}

void mailbox_results_are_safe_across_replacement_and_destruction() {
  RuntimeFixture fixture;
  fixture.put("a.plugin");
  DeterministicJobs scheduler;
  auto manager = bridge::PluginManagerTestAccess::create();
  bridge::PluginManagerTestAccess::installRuntime(*manager,
                                                  fixture.bootstrap());
  bridge::PluginManagerTestAccess::setJobSubmitter(
      *manager, [&](auto kind, auto job) {
        return scheduler.submit(kind, std::move(job));
      });
  require(bridge::PluginManagerTestAccess::scanRuntime(*manager) &&
              scheduler.jobs.size() == 1,
          "blocked preparation was not scheduled");
  const auto old_epoch =
      bridge::PluginManagerTestAccess::runtimeSlots(*manager).front().epoch;
  fixture.overwrite("a.plugin", 'b');
  require(bridge::PluginManagerTestAccess::scanRuntime(*manager) &&
              scheduler.jobs.size() == 2 &&
              bridge::PluginManagerTestAccess::runtimeSlots(*manager)
                      .front()
                      .epoch != old_epoch,
          "changed plugin did not replace a blocked preparation epoch");
  scheduler.runOne();
  bridge::PluginManagerTestAccess::drainRuntime(*manager);
  require(scheduler.jobs.size() == 1 &&
              bridge::PluginManagerTestAccess::preparationCount(*manager) == 1,
          "stale replaced preparation disturbed its exact replacement");
  fixture.erase("a.plugin");
  require(bridge::PluginManagerTestAccess::scanRuntime(*manager) &&
              bridge::PluginManagerTestAccess::runtimeSlots(*manager).empty(),
          "plugin removal did not invalidate blocked preparation epoch");
  scheduler.runOne();
  bridge::PluginManagerTestAccess::drainRuntime(*manager);
  require(bridge::PluginManagerTestAccess::runtimeSlots(*manager).empty() &&
              bridge::PluginManagerTestAccess::preparationCount(*manager) == 0,
          "stale blocked preparation altered removed slot");

  bridge::PluginManagerTestAccess::requestAsyncScan(*manager);
  require(scheduler.jobs.size() == 1, "destruction scan was not queued");
  const auto completed_gate =
      bridge::PluginManagerTestAccess::deliveryGate(*manager);
  scheduler.runOne();
  manager.reset();
  require(completed_gate.expired(),
          "completed undrained mailbox retained manager lifetime");

  DeterministicJobs blocked_scheduler;
  auto blocked_manager = bridge::PluginManagerTestAccess::create();
  bridge::PluginManagerTestAccess::installRuntime(*blocked_manager,
                                                  fixture.bootstrap());
  bridge::PluginManagerTestAccess::setJobSubmitter(
      *blocked_manager,
      [&](auto kind, auto job) {
        return blocked_scheduler.submit(kind, std::move(job));
      });
  std::mutex block_mutex;
  std::condition_variable block_changed;
  bool entered = false;
  bool release = false;
  bool correct_kind = false;
  bridge::PluginManagerTestAccess::setJobEntryProbe(
      *blocked_manager, [&](auto kind) {
        std::unique_lock lock(block_mutex);
        correct_kind =
            kind == bridge::PluginManagerTestAccess::TestJobKind::scan;
        entered = true;
        block_changed.notify_all();
        block_changed.wait(lock, [&] { return release; });
      });
  bridge::PluginManagerTestAccess::requestAsyncScan(*blocked_manager);
  const auto blocked_gate =
      bridge::PluginManagerTestAccess::deliveryGate(*blocked_manager);
  auto blocked_job = std::move(blocked_scheduler.jobs.front());
  blocked_scheduler.jobs.clear();
  blocked_scheduler.kinds.clear();
  std::thread worker([&, job = std::move(blocked_job)]() mutable {
    job();
    job = {};
  });
  {
    std::unique_lock lock(block_mutex);
    block_changed.wait(lock, [&] { return entered; });
  }
  require(correct_kind, "actual worker entered with the wrong typed job kind");
  blocked_manager.reset();
  require(!blocked_gate.expired(),
          "blocked worker did not retain only its detached delivery gate");
  {
    std::scoped_lock lock(block_mutex);
    release = true;
  }
  block_changed.notify_all();
  worker.join();
  require(blocked_gate.expired(),
          "completed canceled worker retained delivery gate");
}

void lifecycle_mailbox_keeps_latest_exact_terminal_state() {
  RuntimeFixture fixture;
  fixture.put("a.plugin");
  auto manager = bridge::PluginManagerTestAccess::create();
  bridge::PluginManagerTestAccess::installRuntime(*manager,
                                                  fixture.bootstrap());
  require(bridge::PluginManagerTestAccess::scanRuntime(*manager) &&
              await([&] {
                bridge::PluginManagerTestAccess::drainRuntime(*manager);
                return bridge::PluginManagerTestAccess::runtimeSlots(*manager)
                    .front()
                    .retry_wait;
              }),
          "lifecycle mailbox fixture did not reach retry state");
  const auto before = bridge::PluginManagerTestAccess::runtimeSlots(*manager);
  const auto epoch = before.front().epoch;
  const auto attempts = before.front().retry_attempts;
  require(bridge::PluginManagerTestAccess::deliverLifecycle(
              *manager, "a.plugin", epoch,
              static_cast<std::uint8_t>(host::SessionState::running),
              static_cast<std::uint8_t>(host::SessionError::none)) &&
              bridge::PluginManagerTestAccess::deliverLifecycle(
                  *manager, "a.plugin", epoch,
                  static_cast<std::uint8_t>(host::SessionState::failed),
                  static_cast<std::uint8_t>(host::SessionError::channel_failed)),
          "exact lifecycle callbacks were not accepted by HookState");
  bridge::PluginManagerTestAccess::drainRuntime(*manager);
  const auto terminal =
      bridge::PluginManagerTestAccess::runtimeSlots(*manager).front();
  require(terminal.retry_wait && terminal.retry_attempts == attempts + 1 &&
              manager->count() == 0,
          "latest terminal lifecycle was not delivered exactly once");
  require(bridge::PluginManagerTestAccess::retryRuntime(*manager, "a.plugin"),
          "lifecycle stale-epoch fixture could not advance epoch");
  require(!bridge::PluginManagerTestAccess::deliverLifecycle(
              *manager, "a.plugin", epoch,
              static_cast<std::uint8_t>(host::SessionState::running),
              static_cast<std::uint8_t>(host::SessionError::none)) &&
              manager->count() == 0,
          "stale lifecycle epoch altered unpublished manager state");
}

void blocked_replacement_preserves_independent_plugin() {
  RuntimeFixture fixture;
  fixture.put("a.plugin");
  fixture.put("b.plugin");
  DeterministicJobs scheduler;
  auto manager = bridge::PluginManagerTestAccess::create();
  bridge::PluginManagerTestAccess::installRuntime(*manager,
                                                  fixture.bootstrap());
  bridge::PluginManagerTestAccess::setJobSubmitter(
      *manager, [&](auto kind, auto job) {
        return scheduler.submit(kind, std::move(job));
      });
  require(bridge::PluginManagerTestAccess::scanRuntime(*manager) &&
              scheduler.jobs.size() == 2,
          "two-plugin replacement fixture did not schedule exact prepares");
  const auto original =
      bridge::PluginManagerTestAccess::runtimeSlots(*manager);
  const auto old_a = observed(original, "a.plugin").epoch;
  const auto old_b = observed(original, "b.plugin").epoch;
  fixture.overwrite("a.plugin", 'b');
  require(bridge::PluginManagerTestAccess::scanRuntime(*manager) &&
              scheduler.jobs.size() == 2,
          "replacement scan disturbed the two original preparations");
  auto replaced = bridge::PluginManagerTestAccess::runtimeSlots(*manager);
  const auto replacement_a = observed(replaced, "a.plugin").epoch;
  require(replacement_a != old_a &&
              observed(replaced, "b.plugin").epoch == old_b,
          "replacement A recreated independent in-flight B");

  scheduler.runAt(1);
  bridge::PluginManagerTestAccess::drainRuntime(*manager);
  replaced = bridge::PluginManagerTestAccess::runtimeSlots(*manager);
  const auto accepted_b = observed(replaced, "b.plugin");
  const auto accepted_b_epoch = accepted_b.epoch;
  require(accepted_b.retry_wait && accepted_b.retry_attempts == 1 &&
              observed(replaced, "a.plugin").epoch == replacement_a &&
              scheduler.jobs.size() == 2,
          "original B result was not accepted independently of replacement A");

  scheduler.runAt(0);
  bridge::PluginManagerTestAccess::drainRuntime(*manager);
  replaced = bridge::PluginManagerTestAccess::runtimeSlots(*manager);
  require(observed(replaced, "a.plugin").epoch == replacement_a &&
              observed(replaced, "b.plugin").epoch == accepted_b_epoch &&
              observed(replaced, "b.plugin").retry_attempts == 1 &&
              scheduler.jobs.size() == 1,
          "stale original A result disturbed replacement A or retained B");

  scheduler.runOne();
  bridge::PluginManagerTestAccess::drainRuntime(*manager);
  replaced = bridge::PluginManagerTestAccess::runtimeSlots(*manager);
  require(observed(replaced, "a.plugin").retry_wait &&
              observed(replaced, "a.plugin").retry_attempts == 1 &&
              observed(replaced, "b.plugin").epoch == accepted_b_epoch &&
              observed(replaced, "b.plugin").retry_attempts == 1,
          "replacement A result disturbed independently accepted B");
}

void runtime_jobs_enter_off_ui_and_commit_on_ui_drain() {
  RuntimeFixture fixture;
  fixture.put("a.plugin");
  auto manager = bridge::PluginManagerTestAccess::create();
  bridge::PluginManagerTestAccess::installRuntime(*manager,
                                                  fixture.bootstrap());
  const auto ui_thread = std::this_thread::get_id();
  std::mutex observed_mutex;
  std::thread::id scan_thread;
  std::thread::id preparation_thread;
  bridge::PluginManagerTestAccess::setJobEntryProbe(
      *manager, [&](auto kind) {
        std::scoped_lock lock(observed_mutex);
        if (kind == bridge::PluginManagerTestAccess::TestJobKind::scan)
          scan_thread = std::this_thread::get_id();
        else
          preparation_thread = std::this_thread::get_id();
      });
  bridge::PluginManagerTestAccess::requestAsyncScan(*manager);
  require(await([&] {
            bridge::PluginManagerTestAccess::drainRuntime(*manager);
            std::scoped_lock lock(observed_mutex);
            return scan_thread != std::thread::id{} &&
                   preparation_thread != std::thread::id{};
          }),
          "runtime scan/preparation jobs did not both enter");
  require(await([&] {
            bridge::PluginManagerTestAccess::drainRuntime(*manager);
            return bridge::PluginManagerTestAccess::runtimeSlots(*manager)
                .front()
                .retry_wait;
          }),
          "UI drain did not commit runtime preparation failure");
  std::scoped_lock lock(observed_mutex);
  require(scan_thread != ui_thread && preparation_thread != ui_thread,
          "runtime scan or preparation executed on the UI thread");
}

void real_root_publishes_attaches_and_tears_down_exactly() {
  if (std::getenv("OMARCHY_REQUIRE_PACKAGED_WORKER_TEST") == nullptr)
    return;
  const bool packaged_worker_available =
      ::access(std::string(omarchy::plugin_runtime::kPackagedWorkerPath).c_str(),
               X_OK) == 0;
  require(packaged_worker_available,
          "required packaged worker integration test was unavailable");
  using Model = bridge::SurfaceProjectionModel;
  constexpr std::string_view plugin = "org.example.status";
  RuntimeFixture fixture;
  const auto exact_binding = fixture.seedRuntime(plugin);
  DeterministicJobs scheduler;
  auto manager = bridge::PluginManagerTestAccess::create();
  bridge::PluginManagerTestAccess::installRuntime(*manager,
                                                  fixture.bootstrap());
  bridge::PluginManagerTestAccess::setJobSubmitter(
      *manager, [&](auto kind, auto job) {
        return scheduler.submit(kind, std::move(job));
      });
  require(bridge::PluginManagerTestAccess::scanRuntime(*manager) &&
              scheduler.jobs.size() == 1 &&
              scheduler.kinds.front() ==
                  bridge::PluginManagerTestAccess::TestJobKind::preparation,
          "real root preparation did not enter the bounded manager lane");
  std::thread preparation([&] { scheduler.runOne(); });
  preparation.join();
  bridge::PluginManagerTestAccess::drainRuntime(*manager);
  const bool reached_running = await([&] {
    bridge::PluginManagerTestAccess::drainRuntime(*manager);
    const auto observations =
        bridge::PluginManagerTestAccess::runtimeSlots(*manager);
    return observations.size() == 1 &&
           observations.front().running_unpublished;
  });
  if (!reached_running) {
    const auto observations =
        bridge::PluginManagerTestAccess::runtimeSlots(*manager);
    require(!observations.empty(), "real committed root slot disappeared");
    const auto &failure = observations.front();
    throw std::runtime_error(
        "real root lifecycle failure: state=" +
        std::to_string(failure.last_state) +
        " error=" + std::to_string(failure.last_error) +
        " opening=" + std::to_string(failure.opening) +
        " starting=" + std::to_string(failure.starting) +
        " retry=" + std::to_string(failure.retry_wait));
  }
  const auto slot =
      bridge::PluginManagerTestAccess::runtimeSlots(*manager).front();
  require(manager->count() == 0 && !slot.has_endpoint_owner,
          "running transport published before typed readiness");

  QQuickWindow window;
  window.resize(320, 64);
  window.show();
  bridge::RemotePluginSurface remote(window.contentItem());
  remote.setWidth(320);
  remote.setHeight(64);
  bool attached_in_signal = false;
  QObject::connect(manager.get(), &bridge::PluginManager::surfacesChanged,
                   [&] {
                     if (manager->count() != 1)
                       return;
                     const auto key = manager->barSurfaces()
                                          ->data(manager->barSurfaces()->index(0, 0),
                                                 Model::SurfaceKeyRole)
                                          .toString();
                     attached_in_signal = manager->attach(key, &remote);
                   });
  const auto declarations = [] {
    std::vector<Model::SurfaceDeclaration> value;
    value.push_back({.surface_name = "bar",
                     .role = Model::Role::Bar,
                     .screen_name = {},
                     .initially_visible = false,
                     .maximum_width = 320,
                     .maximum_height = 64,
                     .dynamic_input_regions = false,
                     .default_bar_section = Model::BarSection::Right});
    return value;
  }();
  auto wrong_binding = exact_binding;
  wrong_binding.revision = permissions::Digest(std::string(64, 'c'));
  require(!bridge::PluginManagerTestAccess::publishReady(
              *manager, plugin, slot.epoch + 1, exact_binding, declarations) &&
              !bridge::PluginManagerTestAccess::publishReady(
                  *manager, plugin, slot.epoch, wrong_binding, declarations) &&
              manager->count() == 0 &&
              !bridge::PluginManagerTestAccess::runtimeSlots(*manager)
                   .front()
                   .has_endpoint_owner,
          "wrong readiness epoch or full binding created publication state");
  const auto throwing_publication = QObject::connect(
      manager.get(), &bridge::PluginManager::surfacesChanged,
      [] { throw std::runtime_error("injected publication signal failure"); });
  require(!bridge::PluginManagerTestAccess::publishReady(
              *manager, plugin, slot.epoch, exact_binding, declarations) &&
              manager->count() == 0 &&
              bridge::PluginManagerTestAccess::runtimeSlots(*manager)
                  .front()
                  .running_unpublished &&
              !bridge::PluginManagerTestAccess::runtimeSlots(*manager)
                   .front()
                   .has_endpoint_owner,
          "throwing publication signal escaped noexcept rollback");
  QObject::disconnect(throwing_publication);
  require(bridge::PluginManagerTestAccess::publishReady(
              *manager, plugin, slot.epoch, exact_binding, declarations) &&
              attached_in_signal && remote.connected() && manager->count() == 1,
          "exact readiness did not install owner before row publication");
  require(!bridge::PluginManagerTestAccess::publishReady(
              *manager, plugin, slot.epoch, exact_binding, declarations),
          "second readiness event replaced an active publication");

  const auto published_key = manager->barSurfaces()
                                 ->data(manager->barSurfaces()->index(0, 0),
                                        Model::SurfaceKeyRole)
                                 .toString();
  bool detached_before_withdraw_signal = false;
  bool reentrant_old_key_rejected = false;
  QObject::connect(manager.get(), &bridge::PluginManager::surfacesChanged,
                   [&] {
                     if (manager->count() != 0)
                       return;
                     detached_before_withdraw_signal = !remote.connected();
                     reentrant_old_key_rejected =
                         !manager->attach(published_key, &remote);
                   });
  fixture.erase(plugin);
  require(bridge::PluginManagerTestAccess::scanRuntime(*manager) &&
              manager->count() == 0 && !remote.connected() &&
              bridge::PluginManagerTestAccess::runtimeSlots(*manager).empty() &&
              detached_before_withdraw_signal && reentrant_old_key_rejected,
          "catalog removal did not close endpoint before withdrawing rows");
  manager.reset();
}

void joined_runtimes_replace_and_render_without_cross_routing() {
  if (std::getenv("OMARCHY_REQUIRE_PACKAGED_WORKER_TEST") == nullptr &&
      std::getenv("OMARCHY_REQUIRE_PACKAGED_WORKER_N8E_TEST") == nullptr)
    return;
  require(::access(std::string(omarchy::plugin_runtime::kPackagedWorkerPath)
                       .c_str(),
                   X_OK) == 0,
          "joined packaged worker integration test was unavailable");
  constexpr std::string_view plugin_a = "a.plugin";
  constexpr std::string_view plugin_b = "b.plugin";

  RuntimeFixture fixture;
  const auto first_a = fixture.seedRuntime(plugin_a, animatedRedQml);
  const auto binding_b = fixture.seedRuntime(plugin_b, animatedBlueQml);
  const auto replacement_a =
      fixture.stageRuntime(plugin_a, 2, animatedGreenQml);
  require(first_a.revision != replacement_a.revision &&
              first_a.generation != replacement_a.generation,
          "replacement A did not name a distinct immutable generation");

  DeterministicJobs scheduler;
  auto manager = bridge::PluginManagerTestAccess::create();
  bridge::PluginManagerTestAccess::installRuntime(*manager,
                                                  fixture.bootstrap());
  bridge::PluginManagerTestAccess::setJobSubmitter(
      *manager, [&](auto kind, auto job) {
        return scheduler.submit(kind, std::move(job));
      });
  require(bridge::PluginManagerTestAccess::scanRuntime(*manager) &&
              scheduler.jobs.size() == 2,
          "joined fixture did not schedule two packaged runtimes");
  while (!scheduler.jobs.empty()) {
    std::thread preparation([&] { scheduler.runOne(); });
    preparation.join();
    bridge::PluginManagerTestAccess::drainRuntime(*manager);
  }
  const bool both_running = await([&] {
    bridge::PluginManagerTestAccess::drainRuntime(*manager);
    const auto observations =
        bridge::PluginManagerTestAccess::runtimeSlots(*manager);
    return observations.size() == 2 &&
           observed(observations, plugin_a).running_unpublished &&
           observed(observations, plugin_b).running_unpublished;
  });
  if (!both_running) {
    const auto observations =
        bridge::PluginManagerTestAccess::runtimeSlots(*manager);
    const auto &a = observed(observations, plugin_a);
    const auto &b = observed(observations, plugin_b);
    throw std::runtime_error(
        "two packaged workers did not coexist: A state/error=" +
        std::to_string(a.last_state) + "/" + std::to_string(a.last_error) +
        ", B state/error=" + std::to_string(b.last_state) + "/" +
        std::to_string(b.last_error));
  }
  const auto initial_slots =
      bridge::PluginManagerTestAccess::runtimeSlots(*manager);
  const auto first_a_epoch = observed(initial_slots, plugin_a).epoch;
  const auto b_epoch = observed(initial_slots, plugin_b).epoch;

  require(bridge::PluginManagerTestAccess::publishReady(
              *manager, plugin_a, first_a_epoch, first_a, barDeclaration()) &&
              bridge::PluginManagerTestAccess::publishReady(
                  *manager, plugin_b, b_epoch, binding_b, barDeclaration()) &&
              manager->count() == 2,
          "two exact runtime bindings did not publish independently");

  QQmlEngine shell_engine;
  QQmlComponent bar_component(
      &shell_engine,
      QUrl::fromLocalFile(QString::fromStdString(secureBarQmlPath())));
  require(bar_component.isReady(),
          "joined secure bar QML component did not load");
  QQuickWindow window;
  window.resize(128, 64);
  window.show();
  const auto first_a_key = barSurfaceKey(*manager, plugin_a);
  const auto b_key = barSurfaceKey(*manager, plugin_b);
  require(!first_a_key.isEmpty() && !b_key.isEmpty(),
          "two published runtimes omitted their secure bar keys");
  auto bar_a = createSecureBar(bar_component, *manager, first_a_key,
                               first_a.generation, *window.contentItem());
  auto bar_b = createSecureBar(bar_component, *manager, b_key,
                               binding_b.generation, *window.contentItem());
  auto *stale_a = bar_a->findChild<bridge::RemotePluginSurface *>();
  auto *remote_b = bar_b->findChild<bridge::RemotePluginSurface *>();
  require(stale_a && remote_b,
          "secure bar wrappers omitted their real Remote surfaces");
  qobject_cast<QQuickItem *>(bar_b.get())->setX(64);
  require(await([&] {
            return stale_a->ready() && remote_b->ready() &&
                   stale_a->frameSequence() >= 2 &&
                   remote_b->frameSequence() >= 2;
          }),
          "secure bar wrappers did not attach two real framed runtimes");
  const auto first_a_image = paintedFrame(*stale_a);
  const auto first_a_sequence = stale_a->frameSequence();
  const auto first_b_image = paintedFrame(*remote_b);
  const auto first_b_sequence = remote_b->frameSequence();
  require(await([&] {
            return stale_a->frameSequence() > first_a_sequence &&
                   remote_b->frameSequence() > first_b_sequence &&
                   paintedFrame(*stale_a) != first_a_image &&
                   paintedFrame(*remote_b) != first_b_image;
          }),
          "animated arbitrary QML did not change its painted frame pixels");
  require(redSignature(paintedFrame(*stale_a)) &&
              blueSignature(paintedFrame(*remote_b)),
          "A1/B frame content crossed its red/blue runtime route");

  const auto b_surface_id = remote_b->surfaceId();
  const auto b_surface_generation = remote_b->surfaceGeneration();
  const auto b_before_replacement = remote_b->frameSequence();
  fixture.selectReplacement(replacement_a);
  require(bridge::PluginManagerTestAccess::scanRuntime(*manager) &&
              scheduler.jobs.size() == 1 && manager->count() == 1 &&
              !stale_a->connected() && remote_b->connected() &&
              barSurfaceKey(*manager, plugin_b) == b_key &&
              remote_b->surfaceId() == b_surface_id &&
              remote_b->surfaceGeneration() == b_surface_generation,
          "replacement A disturbed the exact published B runtime");
  const auto replacement_slots =
      bridge::PluginManagerTestAccess::runtimeSlots(*manager);
  const auto replacement_a_epoch = observed(replacement_slots, plugin_a).epoch;
  require(replacement_a_epoch != first_a_epoch &&
              observed(replacement_slots, plugin_b).epoch == b_epoch &&
              !manager->attach(first_a_key, stale_a),
          "stale A retained attachment authority after replacement");

  // The stopped root released its authority lock. Install the already staged,
  // immutable generation before allowing its bounded preparation to execute.
  fixture.promoteRuntime(replacement_a, 2);
  std::thread replacement_preparation([&] { scheduler.runOne(); });
  replacement_preparation.join();
  require(await([&] {
            bridge::PluginManagerTestAccess::drainRuntime(*manager);
            const auto observations =
                bridge::PluginManagerTestAccess::runtimeSlots(*manager);
            return observed(observations, plugin_a).running_unpublished &&
                   observed(observations, plugin_b).running_published;
          }),
          "replacement A did not start alongside unchanged B");
  require(bridge::PluginManagerTestAccess::publishReady(
              *manager, plugin_a, replacement_a_epoch, replacement_a,
              barDeclaration()) &&
              manager->count() == 2,
          "replacement A did not publish its distinct binding");
  const auto replacement_a_key = barSurfaceKey(*manager, plugin_a);
  require(!replacement_a_key.isEmpty() &&
              replacement_a_key != first_a_key &&
              !manager->attach(replacement_a_key, stale_a),
          "replacement A accepted its stale disconnected Remote");

  bar_a.reset();
  auto replacement_bar_a =
      createSecureBar(bar_component, *manager, replacement_a_key,
                      replacement_a.generation, *window.contentItem());
  auto *remote_a =
      replacement_bar_a->findChild<bridge::RemotePluginSurface *>();
  require(remote_a && await([&] { return remote_a->ready(); }),
          "replacement secure bar did not attach its real Remote");
  replacement_bar_a.reset();
  require(remote_b->connected() &&
              await([&] {
                return remote_b->frameSequence() > b_before_replacement;
              }),
          "secure bar A destruction disturbed independent B frames");

  auto fresh_bar_a =
      createSecureBar(bar_component, *manager, replacement_a_key,
                      replacement_a.generation, *window.contentItem());
  auto *fresh_a = fresh_bar_a->findChild<bridge::RemotePluginSurface *>();
  require(fresh_a && await([&] { return fresh_a->ready(); }) &&
              remote_b->connected(),
          "destroyed secure bar A did not permit a fresh exact attachment");
  const auto fresh_sequence = fresh_a->frameSequence();
  const auto fresh_image = paintedFrame(*fresh_a);
  const auto b_before_comparison = remote_b->frameSequence();
  require(fresh_sequence != 0 &&
              await([&] {
                return fresh_a->frameSequence() > fresh_sequence &&
                       paintedFrame(*fresh_a) != fresh_image &&
                       remote_b->frameSequence() > b_before_comparison;
              }),
          "distinct animated A2 and B did not both advance");
  const auto a2_image = paintedFrame(*fresh_a);
  const auto continued_b_image = paintedFrame(*remote_b);
  require(greenSignature(a2_image) && blueSignature(continued_b_image) &&
              a2_image != continued_b_image &&
              remote_b->surfaceId() == b_surface_id &&
              remote_b->surfaceGeneration() == b_surface_generation &&
              remote_b->frameSequence() > b_before_replacement,
          "A2/B frame content or exact B identity crossed runtime routes");

  manager.reset();
  require(!fresh_a->connected() && !remote_b->connected(),
          "joined manager teardown left a Remote transport connected");
}

} // namespace

void run_plugin_manager_tests() {
  require(qmlRegisterType<bridge::RemotePluginSurface>(
              "Omarchy.PluginHost", 1, 0, "RemotePluginSurface") >= 0,
          "real RemotePluginSurface QML type registration failed");
  secure_bar_retries_only_on_readiness_events();
  process_singleton_factory_is_exact_and_recoverable();
  concurrent_engines_have_one_process_winner();
  singleton_boundary_is_inert_and_not_configurable();
  private_projection_seam_preserves_fail_closed_boundary();
  manager_policy_is_fixed_and_fail_closed();
  last_good_reconciliation_and_stale_callback_are_fail_closed();
  bounded_mailbox_coalesces_and_recovers_without_backoff();
  mailbox_results_are_safe_across_replacement_and_destruction();
  lifecycle_mailbox_keeps_latest_exact_terminal_state();
  blocked_replacement_preserves_independent_plugin();
  runtime_jobs_enter_off_ui_and_commit_on_ui_drain();
  real_root_publishes_attaches_and_tears_down_exactly();
  joined_runtimes_replace_and_render_without_cross_routing();
}
