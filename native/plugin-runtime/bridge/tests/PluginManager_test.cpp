#include "PluginManager.h"

#include "authority_store.hpp"
#include "desktop_notification_service.hpp"
#include "omarchy/plugin_runtime/Version.h"
#include "omarchy/plugin_runtime/runtime_paths.hpp"
#include "remote_surface.hpp"
#include "revision_verifier_adapter.hpp"
#include "runtime_bootstrap.hpp"
#include "runtime_roots.hpp"
#include "runtime_roots_test_access.hpp"

#include <QColor>
#include <QCoreApplication>
#include <QImage>
#include <QJSValue>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
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
#include <sys/wait.h>
#include <unistd.h>

#include <algorithm>
#include <array>
#include <atomic>
#include <barrier>
#include <chrono>
#include <condition_variable>
#include <cstdlib>
#include <exception>
#include <filesystem>
#include <fstream>
#include <functional>
#include <mutex>
#include <ranges>
#include <set>
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
namespace runtime = omarchy::plugin_runtime::runtime;
namespace surface = omarchy::plugin_runtime::surface;

class SettingsHost final : public QObject {
  Q_OBJECT

public:
  QVariantMap current;
  QString updated_plugin;
  QVariantMap updated_settings;

  Q_INVOKABLE QVariant readSecurePluginSettings(const QVariant &plugin) {
    return plugin.toString() == QStringLiteral("org.example.widget")
               ? QVariant(current)
               : QVariant{};
  }

  Q_INVOKABLE QVariant updateSecurePluginSettings(const QVariant &plugin,
                                                  const QVariant &settings) {
    updated_plugin = plugin.toString();
    updated_settings = settings.toMap();
    return true;
  }
};

void require(bool condition, std::string_view message) {
  if (!condition)
    throw std::runtime_error(std::string(message));
}

void host_owned_settings_are_read_and_replaced_atomically() {
  auto manager = bridge::PluginManagerTestAccess::create();
  SettingsHost host;
  host.current = {{QStringLiteral("enabled"), true},
                  {QStringLiteral("mode"), QStringLiteral("full")}};
  require(manager->configureSettingsHost(&host) &&
              !manager->configureSettingsHost(&host),
          "settings host was not configured exactly once");
  const auto current = bridge::PluginManagerTestAccess::currentSettings(
      *manager, "org.example.widget");
  require(current && *current == R"({"enabled":true,"mode":"full"})" &&
              !bridge::PluginManagerTestAccess::currentSettings(
                  *manager, "org.example.other"),
          "manager did not read the exact host-owned settings entry");
  require(bridge::PluginManagerTestAccess::persistSettings(
              *manager, "org.example.widget",
              R"({"enabled":false,"mode":"compact"})") &&
              host.updated_plugin == QStringLiteral("org.example.widget") &&
              host.updated_settings.value(QStringLiteral("enabled")) == false &&
              host.updated_settings.value(QStringLiteral("mode")) ==
                  QStringLiteral("compact") &&
              !bridge::PluginManagerTestAccess::persistSettings(
                  *manager, "org.example.widget", "[]"),
          "manager did not atomically replace host-owned settings");
}

std::size_t openDescriptorCount() {
  return static_cast<std::size_t>(
      std::distance(std::filesystem::directory_iterator("/proc/self/fd"),
                    std::filesystem::directory_iterator{}));
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

template <typename Predicate>
bool awaitFor(std::chrono::milliseconds timeout, Predicate predicate) {
  const auto deadline = std::chrono::steady_clock::now() + timeout;
  while (std::chrono::steady_clock::now() < deadline) {
    QCoreApplication::processEvents();
    if (predicate())
      return true;
    std::this_thread::sleep_for(std::chrono::milliseconds(1));
  }
  return predicate();
}

template <typename Predicate> bool await(Predicate predicate) {
  return awaitFor(std::chrono::seconds(2), std::move(predicate));
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
  return "format=omarchy-plugin-activation-v2\nplugin=" + std::string(plugin) +
         "\nrevision-directory=" + std::string(revision_directory) +
         "\nrevision-sha256=" + std::string(revision_sha256) +
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
    create(home_ / ".local/share/omarchy-plugin-security/v2/revisions", 0700);
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
      std::string_view qml = "import QtQuick\nItem {}\n",
      std::string_view permission_json = "{\"required\": [], \"optional\": []}",
      bool declares_surface = true,
      std::optional<std::string_view> denied_capability = std::nullopt) {
    const auto binding =
        stageRuntime(plugin, 1, qml, permission_json, declares_surface);
    promoteRuntime(binding, 0, denied_capability);
    write(plugin,
          readyActivationRecord(plugin, revisionDirectory(plugin, 1),
                                binding.revision.view()),
          O_CREAT | O_EXCL);
    return binding;
  }

  permissions::ActivationBinding
  seedCheckedFixture(std::string_view plugin,
                     const std::filesystem::path &source) {
    const auto binding = stageCheckedFixture(plugin, 1, source);
    promoteRuntime(binding, 0);
    activateStaged(binding);
    return binding;
  }

  permissions::ActivationBinding
  stageCheckedFixture(std::string_view plugin, std::uint64_t generation,
                      const std::filesystem::path &source) {
    require(std::filesystem::is_directory(source),
            "checked product fixture directory was unavailable");
    const auto revision = revisions() / revisionDirectory(plugin, generation);
    create(revision, 0755);
    for (const auto &entry :
         std::filesystem::recursive_directory_iterator(source)) {
      const auto destination = revision / entry.path().lexically_relative(source);
      if (entry.is_directory()) {
        create(destination, 0755);
      } else {
        require(entry.is_regular_file() &&
                    std::filesystem::copy_file(entry.path(), destination),
                "checked product fixture copy failed");
      }
    }
    return freezeAndVerify(plugin, generation, revision);
  }

  permissions::ActivationBinding stageRuntime(
      std::string_view plugin, std::uint64_t generation, std::string_view qml,
      std::string_view permission_json = "{\"required\": [], \"optional\": []}",
      bool declares_surface = true) {
    const auto revision_name = revisionDirectory(plugin, generation);
    const auto revision = revisions() / revision_name;
    create(revision / "ui", 0755);
    {
      std::ofstream manifest_file(revision / "manifest.json");
      manifest_file << "{\n  \"schemaVersion\": 2,\n  \"id\": \"" << plugin
                    << "\",\n  \"name\": \"Manager fixture\",\n"
                       "  \"version\": \"1.0.0\",\n"
                       "  \"runtime\": {\"apiVersion\": 1, \"qml\": "
                       "\"ui/Main.qml\"},\n  \"surfaces\": ";
      if (declares_surface) {
        manifest_file
            << "{\"bar\": {\"role\": \"bar-embedded\", "
               "\"defaultSection\": \"right\", \"maximumWidth\": 320, "
               "\"maximumHeight\": 64, \"maximumFramesPerSecond\": 60}}";
      } else {
        manifest_file << "{}";
      }
      manifest_file << ",\n  \"permissions\": " << permission_json << "\n}\n";
    }
    std::ofstream(revision / "ui/Main.qml") << qml;
    return freezeAndVerify(plugin, generation, revision);
  }

  std::filesystem::path archive(
      std::string_view plugin, std::string_view suffix,
      std::string_view permission_json =
          "{\"required\": [{\"capability\": \"storage.private\", \"quotaBytes\": 1024, \"reason\": \"state\"}], \"optional\": []}") {
    const auto source = root_ / ("archive-" + std::string(suffix));
    create(source / "ui", 0755);
    std::ofstream manifest(source / "manifest.json");
    manifest << "{\"schemaVersion\":2,\"id\":\"" << plugin
             << "\",\"name\":\"Install fixture\",\"version\":\"1.0.0\","
                "\"runtime\":{\"apiVersion\":1,\"qml\":\"ui/Main.qml\"},"
                "\"surfaces\":{\"overlay\":{\"role\":\"overlay\"}},"
                "\"permissions\":"
             << permission_json << "}";
    manifest.close();
    std::ofstream(source / "ui/Main.qml")
        << "import QtQuick\nItem { property string fixture: \"" << suffix
        << "\" }\n";
    const auto output = root_ / ("plugin-" + std::string(suffix) + ".tar");
    const pid_t child = ::fork();
    require(child >= 0, "manager archive tar fork failed");
    if (child == 0) {
      ::execlp("tar", "tar", "--format=ustar", "-cf", output.c_str(), "-C",
               source.c_str(), "ui", "manifest.json", nullptr);
      ::_exit(127);
    }
    int status = 0;
    require(::waitpid(child, &status, 0) == child && WIFEXITED(status) &&
                WEXITSTATUS(status) == 0,
            "manager archive tar creation failed");
    return output;
  }

  void promoteRuntime(
      const permissions::ActivationBinding &binding,
      std::uint64_t expected_sequence,
      std::optional<std::string_view> denied_capability = std::nullopt) {
    const int authority_fd =
        ::open((authority() / std::string(binding.plugin.view())).c_str(),
               O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
    require(authority_fd >= 0, "manager ready authority open failed");
    auto store =
        host::AuthorityStore::open(authority_fd, ::getuid(), binding.plugin);
    ::close(authority_fd);
    require(store != nullptr, "manager ready authority store failed");

    const auto revision = revisions() / revisionDirectory(binding.plugin.view(),
                                                          binding.generation);
    const int revision_fd = ::open(
        revision.c_str(), O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
    require(revision_fd >= 0, "manager ready revision reopen failed");
    host::SourceRevisionVerifier verifier;
    auto verified = verifier.verify_open_revision(revision_fd);
    ::close(revision_fd);
    require(verified && verified->tree_sha256 == binding.revision.view(),
            "manager staged revision identity changed");
    policy::GrantSnapshot snapshot;
    snapshot.requests = permissions::requests_from_manifest(verified->manifest);
    snapshot.binding = binding;
    snapshot.source_request_fingerprint =
        permissions::Digest(verified->request_sha256);
    for (const auto &request : snapshot.requests.values())
      snapshot.grants.push_back(
          {.capability = request.capability,
           .scope = request.scope,
           .state = denied_capability &&
                            request.capability.id.view() == *denied_capability
                        ? permissions::GrantState::denied
                        : permissions::GrantState::granted,
           .epoch = binding.generation});
    definitions::TrustedDefinitionRegistry registry;
    require(
        store->publish_candidate(*verified, snapshot, expected_sequence,
                                 registry, {}) ==
                host::AuthorityMutationResult::applied &&
            store->promote_candidate(snapshot.binding, expected_sequence + 1) ==
                host::AuthorityMutationResult::applied,
        "manager ready authority activation failed");
  }

  void selectReplacement(const permissions::ActivationBinding &binding) {
    require(std::filesystem::remove(activations() /
                                    std::string(binding.plugin.view())),
            "manager ready activation replacement unlink failed");
    write(binding.plugin.view(),
          readyActivationRecord(
              binding.plugin.view(),
              revisionDirectory(binding.plugin.view(), binding.generation),
              binding.revision.view()),
          O_CREAT | O_EXCL);
  }

  void activateStaged(const permissions::ActivationBinding &binding) {
    write(binding.plugin.view(),
          readyActivationRecord(
              binding.plugin.view(),
              revisionDirectory(binding.plugin.view(), binding.generation),
              binding.revision.view()),
          O_CREAT | O_EXCL);
  }

  void erase(std::string_view name) {
    require(std::filesystem::remove(activations() / std::string(name)),
            "manager runtime fixture erase failed");
  }

  std::unique_ptr<channel::RuntimeBootstrap> bootstrap(
      std::optional<channel::RuntimeServices> services = std::nullopt) const {
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
    require(result && bootstrap_error == channel::RuntimeBootstrapError::none,
            "manager runtime fixture bootstrap rejected");
    if (services)
      channel::RuntimeBootstrapTestAccess::set_services(*result,
                                                        std::move(*services));
    return result;
  }

private:
  permissions::ActivationBinding
  freezeAndVerify(std::string_view plugin, std::uint64_t generation,
                  const std::filesystem::path &revision) {
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
    host::SourceRevisionVerifier verifier;
    auto verified = verifier.verify_open_revision(revision_fd);
    ::close(revision_fd);
    require(verified && verified->manifest.id == plugin,
            "manager ready revision verification failed");

    return {
        .plugin = permissions::PluginId(plugin),
        .revision = permissions::Digest(verified->tree_sha256),
        .policy_fingerprint =
            permissions::Digest(permissions::policy_request_fingerprint(
                permissions::requests_from_manifest(verified->manifest))),
        .generation = generation,
    };
  }

  static std::string revisionDirectory(std::string_view plugin,
                                       std::uint64_t generation) {
    return std::string(plugin) + "-g" + std::to_string(generation);
  }

  std::filesystem::path activations() const {
    return home_ / ".local/state/omarchy/plugin-security/v2/activations";
  }
  std::filesystem::path revisions() const {
    return home_ / ".local/share/omarchy-plugin-security/v2/revisions";
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

  void runOne() { runAt(0); }

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

class BlockingNotifications final {
public:
  static bool send(std::string_view, std::string_view category,
                   std::string_view, std::string_view,
                   void *context) noexcept {
    auto &self = *static_cast<BlockingNotifications *>(context);
    std::unique_lock lock(self.mutex_);
    auto &effect = self.effect(category);
    ++effect.calls;
    effect.entered = true;
    self.changed_.notify_all();
    self.changed_.wait(lock, [&] { return effect.released; });
    return true;
  }

  void hold(std::string_view category) {
    std::scoped_lock lock(mutex_);
    auto &effect = this->effect(category);
    effect.entered = false;
    effect.released = false;
  }

  void release(std::string_view category) {
    {
      std::scoped_lock lock(mutex_);
      effect(category).released = true;
    }
    changed_.notify_all();
  }

  bool awaitEntered(std::string_view category) {
    std::unique_lock lock(mutex_);
    return changed_.wait_for(lock, std::chrono::seconds(2),
                             [&] { return effect(category).entered; });
  }

  std::size_t calls(std::string_view category) {
    std::scoped_lock lock(mutex_);
    return effect(category).calls;
  }

private:
  struct Effect final {
    std::string_view category;
    std::size_t calls = 0;
    bool entered = false;
    bool released = true;
  };

  Effect &effect(std::string_view category) {
    auto found = std::ranges::find(effects_, category, &Effect::category);
    if (found == effects_.end())
      std::terminate();
    return *found;
  }

  std::mutex mutex_;
  std::condition_variable changed_;
  std::array<Effect, 3> effects_{
      {{.category = "status"}, {.category = "a"}, {.category = "b"}}};
};

class LifecycleNotificationState final {
public:
  bool send(const channel::DesktopNotification &notification) noexcept {
    try {
      std::unique_lock lock(mutex_);
      notifications_.push_back(notification);
      entered_ = true;
      changed_.notify_all();
      return changed_.wait_for(lock, std::chrono::seconds(5),
                               [&] { return !held_; });
    } catch (...) {
      return false;
    }
  }

  void hold() {
    std::scoped_lock lock(mutex_);
    held_ = true;
    entered_ = false;
  }

  void release() noexcept {
    try {
      {
        std::scoped_lock lock(mutex_);
        held_ = false;
      }
      changed_.notify_all();
    } catch (...) {
    }
  }

  bool awaitEntered() {
    std::unique_lock lock(mutex_);
    return changed_.wait_for(lock, std::chrono::seconds(2),
                             [&] { return entered_; });
  }

  std::size_t calls() const {
    std::scoped_lock lock(mutex_);
    return notifications_.size();
  }

  channel::DesktopNotification last() const {
    std::scoped_lock lock(mutex_);
    require(!notifications_.empty(),
            "notification lifecycle transport had no call");
    return notifications_.back();
  }

private:
  mutable std::mutex mutex_;
  std::condition_variable changed_;
  std::vector<channel::DesktopNotification> notifications_;
  bool held_ = false;
  bool entered_ = false;
};

class LifecycleNotificationHold final {
public:
  explicit LifecycleNotificationHold(
      std::shared_ptr<LifecycleNotificationState> state)
      : state_(std::move(state)) {}
  ~LifecycleNotificationHold() { release(); }

  void hold() {
    if (held_)
      return;
    state_->hold();
    held_ = true;
  }

  void release() noexcept {
    if (!held_)
      return;
    state_->release();
    held_ = false;
  }

private:
  std::shared_ptr<LifecycleNotificationState> state_;
  bool held_ = false;
};

class LifecycleNotificationTransport final
    : public channel::DesktopNotificationTransport {
public:
  explicit LifecycleNotificationTransport(
      std::shared_ptr<LifecycleNotificationState> state)
      : state_(std::move(state)) {}

  bool
  send(const channel::DesktopNotification &notification) noexcept override {
    return state_->send(notification);
  }

private:
  std::shared_ptr<LifecycleNotificationState> state_;
};

constexpr std::string_view permissionAwareQml = R"QML(import QtQuick
import QtQml
Item {
  width: 64
  height: 64
  readonly property bool notificationsGranted:
    runtime.hasPermission("notifications.send", "send")
  property var notificationCall
  function invokeNotification() {
    if (notificationsGranted)
      notificationCall = runtime.invoke("notifications.send", "send", {
        category: "status",
        title: "Permission generation",
        body: "The optional feature is enabled"
      })
  }
  Timer {
    interval: 1
    running: true
    repeat: false
    onTriggered: parent.invokeNotification()
  }
  Rectangle {
    anchors.fill: parent
    color: parent.notificationsGranted ? "#20c060" : "#d02020"
  }
}
)QML";

std::string permissionAwareQmlFor(std::string_view category) {
  auto qml = std::string(permissionAwareQml);
  const auto marker = qml.find("category: \"status\"");
  require(marker != std::string::npos,
          "permission-aware QML category marker disappeared");
  qml.replace(marker,
              std::string_view("category: \"").size() +
                  std::string_view("status").size(),
              "category: \"" + std::string(category));
  return qml;
}

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

QString barSurfaceKey(bridge::PluginManager &manager, std::string_view plugin) {
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

QJsonObject permissionOperation(bridge::PermissionControl &control,
                                const QString &operation_id) {
  const auto document =
      QJsonDocument::fromJson(control.poll(operation_id).toUtf8());
  require(document.isObject(), "permission control returned invalid JSON");
  return document.object();
}

QJsonArray permissionRows(bridge::PermissionControl &control,
                          const QString &operation_id) {
  const auto operation = permissionOperation(control, operation_id);
  require(operation.value("state") == "succeeded" &&
              operation.value("result").isObject(),
          "permission control operation did not succeed");
  return operation.value("result").toObject().value("permissions").toArray();
}

QString permissionRow(const QJsonArray &rows, std::string_view name) {
  const auto expected = QString::fromUtf8(name.data(), name.size());
  for (const auto value : rows) {
    const auto row = value.toObject();
    if (row.value("name") == expected)
      return row.value("rowId").toString();
  }
  return {};
}

QString grantEveryAvailablePermission(const QJsonArray &rows) {
  QJsonArray choices;
  for (const auto value : rows) {
    const auto row = value.toObject();
    QJsonObject choice{
        {"rowId", row.value("rowId")},
        {"decision", row.value("available").toBool() ? "grant" : "deny"}};
    if (row.value("kind") == "dynamic" && row.value("available").toBool()) {
      QJsonArray selected;
      for (const auto operation : row.value("operations").toArray())
        selected.push_back(
            operation.toObject().value("operationId").toString());
      choice.insert("operations", selected);
    }
    choices.push_back(choice);
  }
  return QString::fromUtf8(QJsonDocument(QJsonObject{{"choices", choices}})
                               .toJson(QJsonDocument::Compact));
}

QString decidePermissions(const QJsonArray &rows,
                          std::span<const std::string_view> denied) {
  QJsonArray choices;
  for (const auto value : rows) {
    const auto row = value.toObject();
    const auto name = row.value("name").toString().toStdString();
    const bool deny =
        std::ranges::find(denied, std::string_view(name)) != denied.end();
    QJsonObject choice{{"rowId", row.value("rowId")},
                       {"decision", deny ? "deny" : "grant"}};
    if (!deny && row.value("kind") == "dynamic") {
      QJsonArray selected;
      for (const auto operation : row.value("operations").toArray())
        selected.push_back(
            operation.toObject().value("operationId").toString());
      choice.insert("operations", selected);
    }
    choices.push_back(choice);
  }
  return QString::fromUtf8(QJsonDocument(QJsonObject{{"choices", choices}})
                               .toJson(QJsonDocument::Compact));
}
QImage paintedFrame(bridge::RemotePluginSurface &remote) {
  QImage image(64, 64, QImage::Format_RGBA8888_Premultiplied);
  image.fill(Qt::transparent);
  QPainter painter(&image);
  remote.paint(&painter);
  painter.end();
  return image;
}

std::set<std::string>
pluginScopePaths(const permissions::ActivationBinding &binding) {
  const std::string marker = "app-omarchy-plugin-worker-" +
                             std::string(binding.plugin.view()) + "-" +
                             std::string(binding.revision.view().substr(0, 12)) +
                             "-" + std::to_string(binding.generation) + "-m";
  std::set<std::string> scopes;
  std::error_code error;
  for (const auto &entry : std::filesystem::directory_iterator("/proc", error)) {
    if (error)
      break;
    const auto name = entry.path().filename().string();
    if (name.empty() || !std::ranges::all_of(name, [](unsigned char value) {
          return value >= '0' && value <= '9';
        }))
      continue;
    std::ifstream cgroup(entry.path() / "cgroup");
    for (std::string line; std::getline(cgroup, line);) {
      const auto path_start = line.rfind(':');
      if (path_start == std::string::npos)
        continue;
      const auto path = line.substr(path_start + 1);
      if (path.find(marker) != std::string::npos && path.ends_with(".scope"))
        scopes.insert(path);
    }
  }
  return scopes;
}

bool redSignature(const QImage &image) {
  const auto color = image.pixelColor(32, 32);
  return color.alpha() >= 250 && color.red() >= 160 &&
         color.red() >= color.green() + 90 && color.red() >= color.blue() + 80;
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

std::unique_ptr<QObject> createSecureBar(QQmlComponent &component,
                                         QObject &service, QString surface_key,
                                         std::uint64_t generation,
                                         QQuickItem &parent) {
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
      &engine, QUrl::fromLocalFile(QString::fromStdString(secureBarQmlPath())));
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
  const int bounded_attempts =
      2 + item->property("maximumAttachAttempts").toInt();
  require(await([&] {
            return service.property("attempts").toInt() == bounded_attempts;
          }),
          "replacement secure bar did not exhaust its bounded attach retry");
  const auto settled_attempts = service.property("attempts").toInt();
  require(!awaitFor(std::chrono::milliseconds(100), [&] {
            return service.property("attempts").toInt() != settled_attempts;
          }),
          "secure bar continued polling after its bounded attach retry");
}

void secure_bar_cannot_expand_the_host_bar() {
  QQmlEngine engine;
  QQmlComponent bar_component(
      &engine, QUrl::fromLocalFile(QString::fromStdString(secureBarQmlPath())));
  require(bar_component.isReady(), "secure bar QML component did not load");

  QJSValue service = engine.evaluate(
      "({ attach: function(key, surface) { return false; } })");
  require(!service.isError(), "inert surface service did not initialize");
  const QVariantMap properties{
      {QStringLiteral("surfaceService"), QVariant::fromValue(service)},
      {QStringLiteral("surfaceKey"), QStringLiteral("bounded-bar")},
      {QStringLiteral("generation"), QStringLiteral("1")},
      {QStringLiteral("maximumWidth"), 64},
      {QStringLiteral("maximumHeight"), 64},
  };
  std::unique_ptr<QObject> secure_object(
      bar_component.createWithInitialProperties(properties));
  auto *secure_item = qobject_cast<QQuickItem *>(secure_object.get());
  require(secure_item && secure_item->implicitWidth() == 0 &&
              secure_item->implicitHeight() == 0,
          "secure bar exposed manifest geometry before host injection");
  secure_item->setProperty("bar", QVariant{});
  QCoreApplication::processEvents();
  require(secure_item->implicitWidth() == 0 &&
              secure_item->implicitHeight() == 0,
          "undefined bar contract exposed plugin geometry");
  secure_item->setProperty(
      "bar", QVariantMap{{QStringLiteral("vertical"), false}});
  QCoreApplication::processEvents();
  require(secure_item->implicitWidth() == 0 &&
              secure_item->implicitHeight() == 0,
          "incomplete bar contract exposed plugin geometry");
  secure_item->setProperty(
      "bar", QVariantMap{{QStringLiteral("vertical"), false},
                          {QStringLiteral("barSize"), -1}});
  QCoreApplication::processEvents();
  require(secure_item->implicitWidth() == 0 &&
              secure_item->implicitHeight() == 0,
          "invalid bar thickness exposed plugin geometry");

  QQmlComponent host_component(&engine);
  host_component.setData(R"QML(
import QtQuick
Item {
  width: 256
  height: 26
  Row {
    objectName: "rowModules"
    anchors.verticalCenter: parent.verticalCenter
    Item { objectName: "ordinaryRow"; implicitWidth: 40; implicitHeight: 26 }
  }
  Column {
    objectName: "columnModules"
    x: 128
    Item { objectName: "ordinaryColumn"; implicitWidth: 32; implicitHeight: 40 }
  }
}
)QML",
                         QUrl());
  require(host_component.isReady(), "host bar geometry fixture did not load");
  std::unique_ptr<QObject> host_object(host_component.create());
  auto *row = host_object->findChild<QQuickItem *>("rowModules");
  auto *ordinary_row = host_object->findChild<QQuickItem *>("ordinaryRow");
  auto *column = host_object->findChild<QQuickItem *>("columnModules");
  auto *ordinary_column =
      host_object->findChild<QQuickItem *>("ordinaryColumn");
  require(row && ordinary_row && column && ordinary_column,
          "host bar geometry fixture omitted its items");
  secure_item->setParentItem(row);
  QCoreApplication::processEvents();
  require(row->implicitHeight() == 26 && row->y() == 0 &&
              ordinary_row->y() == 0,
          "uninjected secure surface displaced the horizontal host bar");

  const QVariantMap horizontal_bar{{QStringLiteral("vertical"), false},
                                   {QStringLiteral("barSize"), 26}};
  secure_item->setProperty("bar", horizontal_bar);
  QCoreApplication::processEvents();

  require(secure_item->implicitWidth() == 64 &&
              secure_item->implicitHeight() == 26 &&
              row->implicitHeight() == 26 && row->y() == 0 &&
              ordinary_row->y() == 0,
          "64px secure surface expanded or displaced the 26px host bar");

  const QVariantMap vertical_bar{{QStringLiteral("vertical"), true},
                                 {QStringLiteral("barSize"), 32}};
  secure_item->setParentItem(column);
  secure_item->setProperty("bar", vertical_bar);
  QCoreApplication::processEvents();
  require(secure_item->implicitWidth() == 32 &&
              secure_item->implicitHeight() == 64 &&
              column->implicitWidth() == 32 && ordinary_column->x() == 0,
          "vertical secure bar expanded or displaced its host column");
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
          "inert singleton accepted a surface without runtime authority");
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
          "first good catalog did not establish service health");
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
          "manager admitted attachment without authenticated readiness");
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
                std::ranges::all_of(scheduler.kinds,
                                    [](auto kind) {
                                      return kind ==
                                             bridge::PluginManagerTestAccess::
                                                 TestJobKind::preparation;
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
    const auto refused =
        bridge::PluginManagerTestAccess::runtimeSlots(*manager);
    require(refused.size() == 1 && refused[0].opening &&
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
      *blocked_manager, [&](auto kind, auto job) {
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
  require(bridge::PluginManagerTestAccess::scanRuntime(*manager) && await([&] {
            bridge::PluginManagerTestAccess::drainRuntime(*manager);
            return bridge::PluginManagerTestAccess::runtimeSlots(*manager)
                .front()
                .retry_wait;
          }),
          "lifecycle mailbox fixture did not reach retry state");
  const auto before = bridge::PluginManagerTestAccess::runtimeSlots(*manager);
  const auto epoch = before.front().epoch;
  const auto attempts = before.front().retry_attempts;
  require(
      bridge::PluginManagerTestAccess::deliverLifecycle(
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
          "stale lifecycle epoch altered manager publication state");
}

host::AdmittedSurfaceIntent admittedIntent(
    const permissions::ActivationBinding &binding, std::uint64_t sequence,
    surface::SurfaceIntentAction action = surface::SurfaceIntentAction::toggle) {
  class IntentClock final : public runtime::GestureEligibilityClock {
  public:
    std::uint64_t now_nanoseconds() const override { return 100; }
  };
  auto clock = std::make_shared<IntentClock>();
  runtime::GestureEligibilityLatch eligibility(clock);
  host::GestureIntentAuthority authority(binding, eligibility);
  const surface::SurfaceKey key{.id = 1, .generation = binding.generation};
  require(authority.declare_surface(key, "bar") ==
                  host::SurfaceDeclarationResult::declared &&
              authority.attach_surface(key) &&
              authority.arm(key, sequence),
          "surface intent fixture did not arm");
  auto admission = authority.admit({.source = key,
                                    .target = key,
                                    .input_sequence = sequence,
                                    .action = action});
  require(admission.intent.has_value(),
          "surface intent fixture was not admitted");
  return std::move(*admission.intent);
}

void surface_intent_mailbox_is_bounded_thread_safe_and_inert_when_stale() {
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
  require(bridge::PluginManagerTestAccess::scanRuntime(*manager),
          "surface intent mailbox fixture catalog was rejected");
  const auto observation =
      bridge::PluginManagerTestAccess::runtimeSlots(*manager).front();
  auto callback = bridge::PluginManagerTestAccess::surfaceIntentCallback(
      *manager, observation.plugin, observation.epoch);
  require(callback.has_value(),
          "surface intent callback did not bind to the exact slot");

  const auto exact_binding = permissions::ActivationBinding{
      .plugin = permissions::PluginId(observation.plugin),
      .revision = permissions::Digest(std::string(64, '1')),
      .policy_fingerprint = permissions::Digest(std::string(64, '2')),
      .generation = 1};
  std::atomic_bool accepted_on_worker = true;
  std::thread worker([&] {
    for (std::uint64_t sequence = 1; sequence <= 64; ++sequence)
      if (!callback->deliver(admittedIntent(exact_binding, sequence)))
        accepted_on_worker = false;
  });
  worker.join();
  require(accepted_on_worker && callback->pending() == 64 &&
              !callback->deliver(admittedIntent(exact_binding, 65)),
          "surface intent FIFO did not enforce its exact 64-entry bound");

  int toggles = 0;
  QObject::connect(manager.get(), &bridge::PluginManager::toggleRequested,
                   [&] { ++toggles; });
  bridge::PluginManagerTestAccess::drainRuntime(*manager);
  require(callback->pending() == 0 && toggles == 0,
          "non-running slot published queued surface intents");

  const auto wrong_binding = permissions::ActivationBinding{
      .plugin = permissions::PluginId("other.plugin"),
      .revision = permissions::Digest(std::string(64, '1')),
      .policy_fingerprint = permissions::Digest(std::string(64, '2')),
      .generation = 1};
  require(!callback->deliver(admittedIntent(wrong_binding, 1)),
          "callback mailbox accepted another plugin identity");

  fixture.overwrite(observation.plugin, 'b');
  require(bridge::PluginManagerTestAccess::scanRuntime(*manager) &&
              bridge::PluginManagerTestAccess::runtimeSlots(*manager)
                      .front()
                      .epoch != observation.epoch &&
              callback->deliver(admittedIntent(exact_binding, 66)),
          "replacement did not detach the old surface intent callback");
  bridge::PluginManagerTestAccess::drainRuntime(*manager);
  require(callback->pending() == 1 && toggles == 0,
          "detached replacement callback reached the new slot");

  manager.reset();
  require(callback->deliver(admittedIntent(exact_binding, 67)) &&
              callback->pending() == 2,
          "detached callback state used destroyed manager memory");
}

void surface_intent_mailbox_delivers_fifo_for_running_published_slot() {
  constexpr std::string_view plugin = "org.example.intent-fifo";
  RuntimeFixture fixture;
  const auto binding = fixture.seedRuntime(plugin);
  DeterministicJobs scheduler;
  auto manager = bridge::PluginManagerTestAccess::create();
  bridge::PluginManagerTestAccess::installRuntime(*manager,
                                                  fixture.bootstrap());
  bridge::PluginManagerTestAccess::setJobSubmitter(
      *manager, [&](auto kind, auto job) {
        return scheduler.submit(kind, std::move(job));
      });
  require(bridge::PluginManagerTestAccess::scanRuntime(*manager),
          "positive surface intent fixture catalog was rejected");
  const auto slot =
      bridge::PluginManagerTestAccess::runtimeSlots(*manager).front();
  std::vector<bridge::SurfaceProjectionModel::SurfaceDeclaration>
      declarations{{.surface_name = "bar",
                    .role = bridge::SurfaceProjectionModel::Role::Bar,
                    .maximum_width = 320,
                    .maximum_height = 64,
                    .default_bar_section =
                        bridge::SurfaceProjectionModel::BarSection::Right}};
  require(bridge::PluginManagerTestAccess::stageRunningSurfaceIntentSlot(
              *manager, slot.plugin, slot.epoch, binding,
              std::move(declarations)) &&
              manager->count() == 1 &&
              bridge::PluginManagerTestAccess::runtimeSlots(*manager)
                  .front()
                  .running,
          "positive surface intent fixture was not running and published");

  class IntentClock final : public runtime::GestureEligibilityClock {
  public:
    std::uint64_t now_nanoseconds() const override { return 100; }
  };
  auto clock = std::make_shared<IntentClock>();
  runtime::GestureEligibilityLatch eligibility(clock);
  host::GestureIntentAuthority authority(binding, eligibility);
  const surface::SurfaceKey key{.id = 1,
                                .generation = binding.generation};
  require(authority.declare_surface(key, "bar") ==
                  host::SurfaceDeclarationResult::declared &&
              authority.attach_surface(key),
          "positive surface intent fixture did not declare its source");
  const auto admit = [&](std::uint64_t sequence,
                         surface::SurfaceIntentAction action) {
    require(authority.arm(key, sequence),
            "positive surface intent fixture did not arm");
    auto admission = authority.admit({.source = key,
                                      .target = key,
                                      .input_sequence = sequence,
                                      .action = action});
    require(admission.intent.has_value(),
            "positive surface intent fixture was not admitted");
    return std::move(*admission.intent);
  };
  auto open = admit(1, surface::SurfaceIntentAction::open);
  auto first_toggle = admit(2, surface::SurfaceIntentAction::toggle);
  auto second_toggle = admit(3, surface::SurfaceIntentAction::toggle);
  auto dismiss = admit(4, surface::SurfaceIntentAction::dismiss);
  auto callback = bridge::PluginManagerTestAccess::surfaceIntentCallback(
      *manager, slot.plugin, slot.epoch);
  require(callback.has_value(),
          "positive running slot lacked its exact callback mailbox");
  auto *bar_model = manager->barSurfaces();
  const auto surface_key =
      bar_model
          ->data(bar_model->index(0, 0),
                 bridge::SurfaceProjectionModel::SurfaceKeyRole)
          .toString();
  const auto generation = QString::number(binding.generation);
  QQmlEngine intent_engine;
  QQmlComponent intent_component(&intent_engine);
  intent_component.setData(R"(
    import QtQml
    QtObject {
      id: root
      required property var service
      required property string targetSurface
      required property string targetGeneration
      property bool opened: false
      property string history: ""
      property string lastInputSequence: ""
      function apply(action, source, target, generation, inputSequence) {
        if (target !== targetSurface || generation !== targetGeneration) return
        history += (history.length === 0 ? "" : ",") + action + "|" + source
          + "|" + target + "|" + generation + "|" + inputSequence
        lastInputSequence = inputSequence
        if (action === "open") opened = true
        else if (action === "toggle") opened = !opened
        else if (action === "dismiss") opened = false
      }
      property Connections serviceConnections: Connections {
        target: root.service
        function onOpenRequested(source, target, generation, inputSequence) {
          root.apply("open", source, target, generation, inputSequence)
        }
        function onToggleRequested(source, target, generation, inputSequence) {
          root.apply("toggle", source, target, generation, inputSequence)
        }
        function onDismissRequested(source, target, generation, inputSequence) {
          root.apply("dismiss", source, target, generation, inputSequence)
        }
      }
    }
  )", QUrl());
  std::unique_ptr<QObject> qml_state(
      intent_component.createWithInitialProperties(
          {{QStringLiteral("service"), QVariant::fromValue(manager.get())},
           {QStringLiteral("targetSurface"), surface_key},
           {QStringLiteral("targetGeneration"), generation}}));
  if (qml_state == nullptr)
    throw std::runtime_error(
        "end-to-end QML intent state fixture did not load: " +
        intent_component.errorString().toStdString());

  auto wrong_binding = binding;
  wrong_binding.plugin = permissions::PluginId("org.example.wrong");
  auto stale_binding = binding;
  ++stale_binding.generation;
  require(!callback->deliver(admittedIntent(wrong_binding, 1)) &&
              callback->deliver(admittedIntent(stale_binding, 1)) &&
              callback->pending() == 1,
          "intent mailbox identity and epoch fences changed");
  bridge::PluginManagerTestAccess::drainRuntime(*manager);
  require(callback->pending() == 0 &&
              qml_state->property("history").toString().isEmpty() &&
              !qml_state->property("opened").toBool(),
          "wrong or stale tuple changed QML state");
  bool queued = false;
  std::thread worker([&] {
    queued = callback->deliver(std::move(open)) &&
             callback->deliver(std::move(first_toggle)) &&
             callback->deliver(std::move(second_toggle)) &&
             callback->deliver(std::move(dismiss));
  });
  worker.join();
  require(queued && callback->pending() == 4 &&
              qml_state->property("history").toString().isEmpty(),
          "callback thread bypassed the positive slot UI mailbox");
  bridge::PluginManagerTestAccess::drainRuntime(*manager);
  const auto tuple_prefix = surface_key + u'|' + surface_key + u'|' +
                            generation + u'|';
  const auto expected_history =
      QStringLiteral("open|") + tuple_prefix + QStringLiteral("1,toggle|") +
      tuple_prefix + QStringLiteral("2,toggle|") + tuple_prefix +
      QStringLiteral("3,dismiss|") + tuple_prefix + QStringLiteral("4");
  require(qml_state->property("history").toString() == expected_history &&
              !qml_state->property("opened").toBool() &&
              qml_state->property("lastInputSequence").toString() ==
                  QStringLiteral("4") &&
              callback->pending() == 0,
          "host intent lost tuple order or final QML state");
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
  const auto original = bridge::PluginManagerTestAccess::runtimeSlots(*manager);
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
  bridge::PluginManagerTestAccess::setJobEntryProbe(*manager, [&](auto kind) {
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

void manager_owns_permission_generation_replacement() {
  if (std::getenv("OMARCHY_REQUIRE_PACKAGED_WORKER_TEST") == nullptr)
    return;
  require(::access(
              std::string(omarchy::plugin_runtime::kPackagedWorkerPath).c_str(),
              X_OK) == 0,
          "permission replacement packaged worker was unavailable");
  constexpr std::string_view plugin = "org.example.permissions";
  constexpr std::string_view permission_json =
      R"({"required":[{"capability":"storage.private","reason":"state","quotaBytes":4096}],"optional":[{"capability":"notifications.send","reason":"alerts","categories":["status"]},{"capability":"audio.play-cue","reason":"sounds","cues":["ready"]}]})";
  const permissions::CapabilityKey notifications{
      .id = permissions::CapabilityId("notifications.send"), .version = 1};
  const permissions::CapabilityKey absent{
      .id = permissions::CapabilityId("audio.play-cue"), .version = 2};
  const definitions::CapabilityReference absent_dynamic{
      .canonical_name = definitions::Name("harness.example"),
      .definition_generation = 1,
      .definition_digest = definitions::Digest(std::string(64, 'd'))};

  RuntimeFixture fixture;
  const auto first_binding = fixture.seedRuntime(
      plugin, permissionAwareQml, permission_json, true, "audio.play-cue");
  DeterministicJobs scheduler;
  auto manager = bridge::PluginManagerTestAccess::create();
  auto notification_backend = std::make_shared<BlockingNotifications>();
  struct ReleaseNotification final {
    std::shared_ptr<BlockingNotifications> backend;
    ~ReleaseNotification() { backend->release("status"); }
  } release_notification{notification_backend};
  notification_backend->hold("status");
  channel::RuntimeServices services{.context = notification_backend,
                                    .notification_send =
                                        BlockingNotifications::send,
                                    .audio_play = nullptr,
                                    .compare_scope = nullptr,
                                    .provider_catalog = {}};
  bridge::PluginManagerTestAccess::installRuntime(
      *manager, fixture.bootstrap(std::move(services)));
  bridge::PluginManagerTestAccess::setJobSubmitter(
      *manager, [&](auto kind, auto job) {
        return scheduler.submit(kind, std::move(job));
      });
  const auto run_job = [&] {
    std::thread worker([&] { scheduler.runOne(); });
    worker.join();
    bridge::PluginManagerTestAccess::drainRuntime(*manager);
  };
  const auto await_running = [&] {
    return await([&] {
      bridge::PluginManagerTestAccess::drainRuntime(*manager);
      const auto observations =
          bridge::PluginManagerTestAccess::runtimeSlots(*manager);
      return observations.size() == 1 && observations.front().running;
    });
  };
  const auto run_preparation = [&] {
    require(!scheduler.jobs.empty() &&
                scheduler.kinds.front() ==
                    bridge::PluginManagerTestAccess::TestJobKind::preparation,
            "permission replacement did not enqueue exact preparation");
    run_job();
    if (!await_running()) {
      const auto observations =
          bridge::PluginManagerTestAccess::runtimeSlots(*manager);
      require(!observations.empty(),
              "permission replacement generation slot disappeared");
      const auto &failed = observations.front();
      throw std::runtime_error(
          "permission replacement generation did not reach running: state=" +
          std::to_string(failed.last_state) +
          " error=" + std::to_string(failed.last_error));
    }
  };
  const auto current_slot = [&] {
    const auto observations =
        bridge::PluginManagerTestAccess::runtimeSlots(*manager);
    require(observations.size() == 1,
            "permission replacement slot disappeared");
    return observations.front();
  };
  const auto current_view = [&] {
    const auto slot = current_slot();
    auto view = bridge::PluginManagerTestAccess::permissionView(
        *manager, plugin, slot.epoch);
    require(view && view->active,
            "permission replacement authority view unavailable");
    return *view;
  };
  const auto review_decisions = [](const host::ConsentReview &review) {
    std::vector<host::BuiltinConsentDecision> decisions;
    for (const auto &row : review.builtin_rows) {
      require(row.requested.has_value(),
              "permission review row lacked canonical request");
      decisions.push_back(
          {.capability = row.requested->capability,
           .decided_scope = row.requested->scope,
           .decision = row.requested->capability.id.view() == "audio.play-cue"
                           ? permissions::UserDecision::deny
                           : permissions::UserDecision::grant});
    }
    return decisions;
  };
  const auto confirmation =
      [](const host::ConsentReview &review,
         std::span<const host::BuiltinConsentDecision> decisions) {
        return host::ConsentConfirmation{
            .review_fingerprint = review.fingerprint,
            .decision_fingerprint =
                host::consent_decision_fingerprint(review, decisions, {}),
            .actor = permissions::DecisionActor::trusted_ui,
            .confirmed_wall_seconds = 1};
      };
  require(bridge::PluginManagerTestAccess::scanRuntime(*manager) &&
              scheduler.jobs.size() == 1,
          "permission replacement initial preparation was not queued");
  run_preparation();
  require(notification_backend->awaitEntered("status") &&
              notification_backend->calls("status") == 1,
          "packaged QML did not select and enter its granted optional effect");
  auto slot = current_slot();
  require(current_view().active->binding == first_binding,
          "permission replacement started the wrong initial binding");
  require(manager->count() == 1,
          "permission replacement fixture did not publish G1 automatically");
  const auto stale_surface_key = barSurfaceKey(*manager, plugin);
  require(!stale_surface_key.isEmpty(),
          "permission replacement fixture lacked a G1 surface key");
  QQuickWindow permission_window;
  permission_window.resize(64, 64);
  permission_window.show();
  bridge::RemotePluginSurface live_remote(permission_window.contentItem());
  live_remote.setWidth(64);
  live_remote.setHeight(64);
  require(manager->attach(stale_surface_key, &live_remote) &&
              live_remote.connected(),
          "permission replacement fixture did not attach G1");

  auto view = current_view();
  scheduler.refuses = true;
  require(!bridge::PluginManagerTestAccess::revokePermission(
              *manager, plugin, slot.epoch, notifications,
              view.authority_slots.sequence) &&
              !current_slot().permission_transaction &&
              current_slot().epoch == slot.epoch && manager->count() == 1,
          "permission scheduler refusal changed live G1");
  scheduler.refuses = false;
  scheduler.throws = true;
  require(!bridge::PluginManagerTestAccess::revokePermission(
              *manager, plugin, slot.epoch, notifications,
              view.authority_slots.sequence) &&
              !current_slot().permission_transaction &&
              current_slot().epoch == slot.epoch && manager->count() == 1,
          "permission scheduler throw changed live G1");
  scheduler.throws = false;

  require(bridge::PluginManagerTestAccess::revokePermission(
              *manager, plugin, slot.epoch, absent,
              view.authority_slots.sequence) &&
              current_slot().permission_transaction,
          "invalid selector did not enter the bounded permission lane");
  std::thread invalid_selector_worker([&] { scheduler.runOne(); });
  invalid_selector_worker.join();
  require(bridge::PluginManagerTestAccess::executingPermissionJobs(*manager) ==
                  1 &&
              current_slot().permission_transaction,
          "completed permission transaction was not retained for UI drain");
  bridge::PluginManagerTestAccess::drainRuntime(*manager);
  require(current_slot().epoch == slot.epoch && current_slot().running &&
              !current_slot().permission_transaction && manager->count() == 1,
          "invalid selector fenced or replaced live G1");
  require(bridge::PluginManagerTestAccess::revokePermission(
              *manager, plugin, slot.epoch, absent_dynamic,
              view.authority_slots.sequence),
          "dynamic permission selector did not enter Manager ingress");
  run_job();
  require(current_slot().epoch == slot.epoch && current_slot().running &&
              manager->count() == 1,
          "invalid dynamic selector fenced or replaced live G1");
  require(bridge::PluginManagerTestAccess::revokePermission(
              *manager, plugin, slot.epoch, notifications,
              view.authority_slots.sequence + 1),
          "stale permission request was not queued for authoritative check");
  run_job();
  require(current_slot().epoch == slot.epoch && current_slot().running &&
              manager->count() == 1,
          "stale permission sequence fenced or replaced live G1");

  auto *control = manager->permissions();
  require(control != nullptr && control->parent() == manager.get(),
          "permission control was not manager-owned");
  const auto optional_list = control->beginList(QString::fromUtf8(plugin));
  require(!optional_list.isEmpty() && scheduler.jobs.size() == 1,
          "public permission list was not queued asynchronously");
  run_job();
  const auto optional_rows = permissionRows(*control, optional_list);
  require(std::ranges::none_of(optional_rows,
                               [](const QJsonValue &value) {
                                 return value.toObject().contains("version");
                               }),
          "permission presentation exposed internal capability versions");
  const auto optional_row = permissionRow(optional_rows, "notifications.send");
  require(!optional_row.isEmpty(),
          "public list omitted the exact optional capability");
  const auto stale_list = control->beginList(QString::fromUtf8(plugin));
  require(!stale_list.isEmpty(), "second exact list was not queued");
  run_job();
  const auto stale_optional_row =
      permissionRow(permissionRows(*control, stale_list), "notifications.send");
  const auto optional_revoke = control->revoke(optional_list, optional_row);
  require(!optional_revoke.isEmpty(), "public optional revoke was not queued");
  bool reentrant_attach_attempted = false;
  bool reentrant_attach_succeeded = false;
  QObject::connect(&live_remote,
                   &bridge::RemotePluginSurface::connectionChanged, [&] {
                     if (live_remote.connected())
                       return;
                     reentrant_attach_attempted = true;
                     reentrant_attach_succeeded =
                         manager->attach(stale_surface_key, &live_remote);
                   });
  std::thread mutation([&] { scheduler.runOne(); });
  require(await([&] {
            bridge::PluginManagerTestAccess::drainRuntime(*manager);
            return current_slot().permission_changing;
          }),
          "valid optional revoke did not deliver its pre-drain fence");
  bridge::RemotePluginSurface stale_remote;
  require(current_slot().permission_changing &&
              current_slot().permission_transaction &&
              current_slot().has_runtime_root && scheduler.jobs.empty() &&
              bridge::PluginManagerTestAccess::executingPermissionJobs(
                  *manager) == 1 &&
              manager->count() == 0 && !live_remote.connected() &&
              reentrant_attach_attempted && !reentrant_attach_succeeded &&
              !manager->attach(stale_surface_key, &stale_remote),
          "pre-drain fence did not retain only the stopped-admission G1 root");
  notification_backend->release("status");
  mutation.join();
  bridge::PluginManagerTestAccess::drainRuntime(*manager);
  require(permissionOperation(*control, optional_revoke).value("state") ==
                  "succeeded" &&
              control->revoke(optional_list, optional_row).isEmpty(),
          "public optional revoke was not exact and one-shot");
  require(current_slot().preparing && scheduler.jobs.size() == 1,
          "settled optional revoke did not enter exact generation preparation");
  run_preparation();
  slot = current_slot();
  view = current_view();
  auto expected_binding = first_binding;
  expected_binding.generation = first_binding.generation + 1;
  require(view.active->binding == expected_binding,
          "optional revoke did not publish one exact fresh generation");
  const auto revoked_optional =
      std::ranges::find(view.active->grants.values(), notifications,
                        &permissions::GrantRecord::capability);
  require(revoked_optional != view.active->grants.values().end() &&
              revoked_optional->state == permissions::GrantState::revoked,
          "optional revoke did not persist revoked authority");
  require(manager->count() == 1,
          "revoked optional generation did not publish automatically");
  require(control->revoke(stale_list, stale_optional_row).isEmpty(),
          "stale public list crossed the replacement generation");
  bridge::RemotePluginSurface denied_remote(permission_window.contentItem());
  denied_remote.setWidth(64);
  denied_remote.setHeight(64);
  const auto denied_key = barSurfaceKey(*manager, plugin);
  require(manager->attach(denied_key, &denied_remote) &&
              await([&] { return denied_remote.ready(); }) &&
              redSignature(paintedFrame(denied_remote)) &&
              notification_backend->calls("status") == 1,
          "fresh QML generation did not hide its revoked optional feature");

  auto review = bridge::PluginManagerTestAccess::preparePermissionReview(
      *manager, plugin, slot.epoch);
  require(review != nullptr, "running optional regrant review was unavailable");
  const auto later_review =
      bridge::PluginManagerTestAccess::preparePermissionReview(*manager, plugin,
                                                               slot.epoch);
  require(later_review && later_review != review,
          "permission authority did not return independently owned reviews");
  auto decisions = review_decisions(*review);
  auto confirmed = confirmation(*review, decisions);
  require(!bridge::PluginManagerTestAccess::applyPermissionReview(
              *manager, plugin, slot.epoch, {}, confirmed, decisions, {}) &&
              current_slot().running,
          "permission apply accepted an absent manager-owned review");
  require(bridge::PluginManagerTestAccess::applyPermissionReview(
              *manager, plugin, slot.epoch, review, confirmed, decisions, {}),
          "an exact earlier immutable review was not queued");
  run_job();
  require(current_slot().preparing && scheduler.jobs.size() == 1,
          "exact immutable review did not enter generation preparation");
  run_preparation();
  require(await([&] { return notification_backend->calls("status") == 2; }),
          "exact immutable review generation did not settle its live effect");
  slot = current_slot();
  view = current_view();

  const auto optional_review = control->beginReview(QString::fromUtf8(plugin));
  require(!optional_review.isEmpty(),
          "running optional regrant review was unavailable");
  run_job();
  const auto optional_review_rows = permissionRows(*control, optional_review);
  const auto unavailable_audio_row =
      permissionRow(optional_review_rows, "audio.play-cue");
  require(!unavailable_audio_row.isEmpty(),
          "review omitted the unavailable audio route");
  auto unavailable_choices =
      QJsonDocument::fromJson(
          grantEveryAvailablePermission(optional_review_rows).toUtf8())
          .object();
  auto unavailable_array = unavailable_choices.value("choices").toArray();
  for (qsizetype index = 0; index < unavailable_array.size(); ++index) {
    auto choice = unavailable_array[index].toObject();
    if (choice.value("rowId") == unavailable_audio_row) {
      choice.insert("decision", "grant");
      unavailable_array[index] = choice;
    }
  }
  unavailable_choices.insert("choices", unavailable_array);
  auto extra_key_choices =
      QJsonDocument::fromJson(
          grantEveryAvailablePermission(optional_review_rows).toUtf8())
          .object();
  auto extra_key_array = extra_key_choices.value("choices").toArray();
  auto extra_key_choice = extra_key_array.first().toObject();
  extra_key_choice.insert("operations", QJsonArray{});
  extra_key_array[0] = extra_key_choice;
  extra_key_choices.insert("choices", extra_key_array);
  require(
      control->apply(optional_review, "{}").isEmpty() &&
          control
              ->applyInteractiveCli(
                  optional_review,
                  grantEveryAvailablePermission(optional_review_rows))
              .isEmpty() &&
          control
              ->apply(optional_review,
                      QStringLiteral("{\"choices\":[{\"rowId\":\"foreign\","
                                     "\"decision\":\"grant\"}]}"))
              .isEmpty() &&
          control
              ->apply(optional_review,
                      QString::fromUtf8(QJsonDocument(extra_key_choices)
                                            .toJson(QJsonDocument::Compact)))
              .isEmpty() &&
          control
              ->apply(optional_review,
                      QString::fromUtf8(QJsonDocument(unavailable_choices)
                                            .toJson(QJsonDocument::Compact)))
              .isEmpty(),
      "public review accepted the wrong ingress, malformed, foreign, or extra "
      "choice keys, or an unavailable grant");
  const auto optional_apply = control->apply(
      optional_review, grantEveryAvailablePermission(optional_review_rows));
  require(!optional_apply.isEmpty() &&
              control
                  ->apply(optional_review,
                          grantEveryAvailablePermission(optional_review_rows))
                  .isEmpty(),
          "public review apply was not exact and one-shot");
  run_job();
  require(permissionOperation(*control, optional_apply).value("state") ==
              "succeeded",
          "public optional regrant did not settle successfully");
  require(current_slot().preparing && scheduler.jobs.size() == 1,
          "running optional regrant did not replace its generation");
  notification_backend->hold("status");
  run_preparation();
  require(notification_backend->awaitEntered("status") &&
              notification_backend->calls("status") == 3,
          "fresh QML generation did not expose its regranted optional feature");
  notification_backend->release("status");
  slot = current_slot();
  view = current_view();
  expected_binding.generation = first_binding.generation + 3;
  require(view.active->binding == expected_binding,
          "optional regrant did not commit the next exact generation");
  require(manager->count() == 1,
          "regranted optional generation did not publish automatically");
  bridge::RemotePluginSurface granted_remote(permission_window.contentItem());
  granted_remote.setWidth(64);
  granted_remote.setHeight(64);
  require(manager->attach(barSurfaceKey(*manager, plugin), &granted_remote) &&
              await([&] { return granted_remote.ready(); }) &&
              paintedFrame(granted_remote).pixelColor(32, 32).green() >= 150,
          "regranted QML generation did not render its enabled feature");

  const auto required_list = control->beginList(QString::fromUtf8(plugin));
  require(!required_list.isEmpty(), "required list was not queued");
  run_job();
  const auto required_row =
      permissionRow(permissionRows(*control, required_list), "storage.private");
  const auto required_revoke = control->revoke(required_list, required_row);
  require(!required_revoke.isEmpty(), "public required revoke was not queued");
  run_job();
  require(permissionOperation(*control, required_revoke).value("state") ==
              "succeeded",
          "public required revoke did not settle successfully");
  slot = current_slot();
  require(slot.permission_disabled && scheduler.jobs.empty(),
          "required revoke did not retain a permission-only disabled slot");
  manager.reset();

  manager = bridge::PluginManagerTestAccess::create();
  services.context = notification_backend;
  services.notification_send = BlockingNotifications::send;
  bridge::PluginManagerTestAccess::installRuntime(
      *manager, fixture.bootstrap(std::move(services)));
  bridge::PluginManagerTestAccess::setJobSubmitter(
      *manager, [&](auto kind, auto job) {
        return scheduler.submit(kind, std::move(job));
      });
  require(bridge::PluginManagerTestAccess::scanRuntime(*manager) &&
              scheduler.jobs.size() == 1,
          "disabled process restart did not open canonical authority");
  run_job();
  slot = current_slot();
  require(slot.permission_disabled && scheduler.jobs.empty(),
          "required-denied process restart attempted to start a session");
  control = manager->permissions();
  const auto required_review = control->beginReview(QString::fromUtf8(plugin));
  require(!required_review.isEmpty(),
          "required-denied restart did not retain an administrable review");
  run_job();
  const auto required_apply = control->apply(
      required_review,
      grantEveryAvailablePermission(permissionRows(*control, required_review)));
  require(!required_apply.isEmpty(),
          "required regrant was not queued from permission-only root");
  run_job();
  require(permissionOperation(*control, required_apply).value("state") ==
              "succeeded",
          "public required regrant did not settle successfully");
  require(current_slot().preparing && scheduler.jobs.size() == 1,
          "required regrant did not enqueue exact preparation");
  notification_backend->hold("status");
  run_preparation();
  require(notification_backend->awaitEntered("status"),
          "restored generation did not enter its granted optional effect");
  view = current_view();
  expected_binding.generation = first_binding.generation + 5;
  require(view.active->binding == expected_binding,
          "required regrant did not restore the exact next generation");

  slot = current_slot();
  view = current_view();
  require(bridge::PluginManagerTestAccess::revokePermission(
              *manager, plugin, slot.epoch, notifications,
              view.authority_slots.sequence) &&
              scheduler.jobs.size() == 1,
          "post-fence destruction mutation was not queued");
  auto blocked_job = std::move(scheduler.jobs.front());
  scheduler.jobs.clear();
  scheduler.kinds.clear();
  const auto delivery_gate =
      bridge::PluginManagerTestAccess::deliveryGate(*manager);
  std::thread blocked_worker([job = std::move(blocked_job)]() mutable {
    job();
    job = {};
  });
  require(await([&] {
            bridge::PluginManagerTestAccess::drainRuntime(*manager);
            return current_slot().permission_changing;
          }) &&
              current_slot().has_runtime_root &&
              bridge::PluginManagerTestAccess::executingPermissionJobs(
                  *manager) == 1,
          "destruction proof did not reach post-observer effect drain");
  std::atomic<bool> destruction_started = false;
  std::thread release_effect([&] {
    while (!destruction_started.load(std::memory_order_acquire))
      std::this_thread::yield();
    notification_backend->release("status");
  });
  destruction_started.store(true, std::memory_order_release);
  manager.reset();
  release_effect.join();
  blocked_worker.join();
  require(delivery_gate.expired(),
          "post-fence canceled permission worker retained delivery state");
}

void public_permission_lifecycle_is_closed_until_exact_consent() {
  if (std::getenv("OMARCHY_REQUIRE_PACKAGED_WORKER_TEST") == nullptr)
    return;
  require(::access(
              std::string(omarchy::plugin_runtime::kPackagedWorkerPath).c_str(),
              X_OK) == 0,
          "public lifecycle packaged worker was unavailable");

  constexpr std::string_view plugin_a = "org.example.lifecycle-a";
  constexpr std::string_view plugin_b = "org.example.lifecycle-b";
  constexpr std::string_view permissions_a =
      R"({"required":[{"capability":"storage.private","reason":"state","quotaBytes":4096}],"optional":[{"capability":"notifications.send","reason":"alerts","categories":["a"]}]})";
  constexpr std::string_view permissions_b =
      R"({"required":[],"optional":[{"capability":"notifications.send","reason":"alerts","categories":["b"]}]})";

  RuntimeFixture fixture;
  const auto binding_a = fixture.stageRuntime(
      plugin_a, 1, permissionAwareQmlFor("a"), permissions_a);
  const auto binding_b = fixture.stageRuntime(
      plugin_b, 1, permissionAwareQmlFor("b"), permissions_b);
  fixture.activateStaged(binding_a);
  fixture.activateStaged(binding_b);

  auto notification_state = std::make_shared<LifecycleNotificationState>();
  auto notification_service =
      std::make_shared<channel::DesktopNotificationService>(
          std::make_unique<LifecycleNotificationTransport>(notification_state));
  const auto services = [&] {
    return channel::RuntimeServices{
        .context = notification_service,
        .notification_send = channel::DesktopNotificationService::send,
        .audio_play = nullptr,
        .compare_scope = nullptr,
        .provider_catalog = {}};
  };

  DeterministicJobs scheduler;
  auto manager = bridge::PluginManagerTestAccess::create();
  bridge::PluginManagerTestAccess::installRuntime(
      *manager, fixture.bootstrap(services()));
  bridge::PluginManagerTestAccess::setJobSubmitter(
      *manager, [&](auto kind, auto job) {
        return scheduler.submit(kind, std::move(job));
      });
  const auto run_job_at = [&](std::size_t index) {
    std::thread worker([&] { scheduler.runAt(index); });
    worker.join();
  };
  const auto run_job = [&] { run_job_at(0); };
  const auto drain = [&] {
    bridge::PluginManagerTestAccess::drainRuntime(*manager);
  };
  const auto observe_slots = [&] {
    return bridge::PluginManagerTestAccess::runtimeSlots(*manager);
  };

  require(bridge::PluginManagerTestAccess::scanRuntime(*manager) &&
              scheduler.jobs.size() == 2,
          "staged initial activations did not queue exact preparations");
  run_job_at(1);
  run_job_at(0);
  drain();
  auto observations = observe_slots();
  require(observations.size() == 2 &&
              observed(observations, plugin_a).permission_disabled &&
              observed(observations, plugin_b).permission_disabled &&
              manager->count() == 0 && scheduler.jobs.empty(),
          "unreviewed staged activations started or lost consent authority");

  auto *control = manager->permissions();
  const auto review_a = control->beginReview(QString::fromUtf8(plugin_a));
  const auto review_b = control->beginReview(QString::fromUtf8(plugin_b));
  require(!review_a.isEmpty() && !review_b.isEmpty() &&
              scheduler.jobs.size() == 2,
          "two public initial reviews were not admitted independently");
  run_job_at(1);
  run_job_at(0);
  drain();
  const auto rows_a = permissionRows(*control, review_a);
  const auto rows_b = permissionRows(*control, review_b);
  constexpr std::array<std::string_view, 1> deny_required{"storage.private"};
  require(control->apply(review_a, decidePermissions(rows_a, deny_required))
                  .isEmpty() &&
              scheduler.jobs.empty(),
          "required denial crossed the public validation boundary");
  observations = observe_slots();
  require(observed(observations, plugin_a).permission_disabled &&
              observed(observations, plugin_b).permission_disabled &&
              manager->count() == 0,
          "rejected required denial mutated or activated a staged plugin");

  constexpr std::array<std::string_view, 1> deny_notifications{
      "notifications.send"};
  const auto apply_a =
      control->apply(review_a, decidePermissions(rows_a, deny_notifications));
  const auto apply_b = control->apply(review_b, decidePermissions(rows_b, {}));
  require(!apply_a.isEmpty() && !apply_b.isEmpty() &&
              scheduler.jobs.size() == 2,
          "valid public initial consent did not queue two opaque operations");
  run_job_at(1);
  run_job_at(0);
  drain();
  require(permissionOperation(*control, apply_a).value("state") ==
                  "succeeded" &&
              permissionOperation(*control, apply_b).value("state") ==
                  "succeeded" &&
              scheduler.jobs.size() == 2,
          "reordered public consent operations crossed plugin identity");

  std::jthread revocation;
  LifecycleNotificationHold notification_hold(notification_state);
  notification_hold.hold();
  run_job_at(1);
  run_job_at(0);
  drain();
  const bool initial_running = await([&] {
    drain();
    const auto current = observe_slots();
    return observed(current, plugin_a).running &&
           observed(current, plugin_b).running && manager->count() == 2;
  });
  if (!initial_running) {
    const auto current = observe_slots();
    const auto &a = observed(current, plugin_a);
    const auto &b = observed(current, plugin_b);
    throw std::runtime_error(
        "consented runtimes did not start: A state/error=" +
        std::to_string(a.last_state) + "/" + std::to_string(a.last_error) +
        ", B state/error=" + std::to_string(b.last_state) + "/" +
        std::to_string(b.last_error));
  }
  require(notification_state->awaitEntered(),
          "consented runtime did not enter the real notification service");
  const auto first_notification = notification_state->last();
  require(first_notification.plugin == QString::fromUtf8(plugin_b) &&
              first_notification.category == "b" &&
              notification_state->calls() == 1,
          "optional denial or reordered consent crossed notification identity");

  QQuickWindow window;
  window.resize(128, 64);
  window.show();
  bridge::RemotePluginSurface remote_a(window.contentItem());
  bridge::RemotePluginSurface remote_b(window.contentItem());
  remote_a.setWidth(64);
  remote_a.setHeight(64);
  remote_b.setX(64);
  remote_b.setWidth(64);
  remote_b.setHeight(64);
  const auto key_a = barSurfaceKey(*manager, plugin_a);
  const auto key_b = barSurfaceKey(*manager, plugin_b);
  require(!key_a.isEmpty() && !key_b.isEmpty() &&
              manager->attach(key_a, &remote_a) &&
              manager->attach(key_b, &remote_b) &&
              await([&] { return remote_a.ready(); }) && remote_b.connected() &&
              redSignature(paintedFrame(remote_a)),
          "optional denial was not visible to live QML through permissions");

  const auto list_b = control->beginList(QString::fromUtf8(plugin_b));
  require(!list_b.isEmpty() && scheduler.jobs.size() == 1,
          "public notification list was not queued");
  run_job();
  drain();
  const auto row_b =
      permissionRow(permissionRows(*control, list_b), "notifications.send");
  const auto revoke_b = control->revoke(list_b, row_b);
  require(!revoke_b.isEmpty() && scheduler.jobs.size() == 1,
          "public notification revoke was not queued");
  revocation = std::jthread([&] { scheduler.runOne(); });
  require(await([&] {
            drain();
            return observed(observe_slots(), plugin_b).permission_changing;
          }),
          "notification revoke did not close admission before effect drain");
  require(
      manager->count() == 1 && remote_a.connected() && !remote_b.connected() &&
          bridge::PluginManagerTestAccess::executingPermissionJobs(*manager) ==
              1,
      "revocation drain left publication open or disturbed plugin A");
  notification_hold.release();
  revocation.join();
  drain();
  require(permissionOperation(*control, revoke_b).value("state") ==
                  "succeeded" &&
              observed(observe_slots(), plugin_b).preparing &&
              scheduler.jobs.size() == 1,
          "drained notification revoke did not queue one fresh generation");
  run_job();
  drain();
  require(await([&] {
            drain();
            return observed(observe_slots(), plugin_b).running &&
                   manager->count() == 2;
          }),
          "revoked optional generation did not restart safely");
  bridge::RemotePluginSurface denied_b(window.contentItem());
  denied_b.setWidth(64);
  denied_b.setHeight(64);
  require(manager->attach(barSurfaceKey(*manager, plugin_b), &denied_b) &&
              await([&] { return denied_b.ready(); }) &&
              redSignature(paintedFrame(denied_b)) &&
              notification_state->calls() == 1,
          "restarted QML did not hide its revoked notification feature");

  const auto list_a = control->beginList(QString::fromUtf8(plugin_a));
  require(!list_a.isEmpty() && scheduler.jobs.size() == 1,
          "public storage list was not queued");
  run_job();
  drain();
  const auto storage_row =
      permissionRow(permissionRows(*control, list_a), "storage.private");
  const auto revoke_a = control->revoke(list_a, storage_row);
  require(!revoke_a.isEmpty() && scheduler.jobs.size() == 1,
          "public required storage revoke was not queued");
  run_job();
  drain();
  require(permissionOperation(*control, revoke_a).value("state") ==
                  "succeeded" &&
              observed(observe_slots(), plugin_a).permission_disabled &&
              manager->count() == 1 && !remote_a.connected() &&
              denied_b.connected(),
          "required storage revoke did not disable only its exact plugin");

  manager.reset();
  require(!denied_b.connected(),
          "manager restart left an old generation attached");
  manager = bridge::PluginManagerTestAccess::create();
  bridge::PluginManagerTestAccess::installRuntime(
      *manager, fixture.bootstrap(services()));
  bridge::PluginManagerTestAccess::setJobSubmitter(
      *manager, [&](auto kind, auto job) {
        return scheduler.submit(kind, std::move(job));
      });
  require(bridge::PluginManagerTestAccess::scanRuntime(*manager) &&
              scheduler.jobs.size() == 2,
          "manager restart did not reopen two exact authorities");
  run_job_at(1);
  run_job_at(0);
  drain();
  require(await([&] {
            drain();
            const auto current = observe_slots();
            return observed(current, plugin_a).permission_disabled &&
                   observed(current, plugin_b).running && manager->count() == 1;
          }),
          "restart activated required-revoked storage or lost plugin B");

  control = manager->permissions();
  const auto regrant_review = control->beginReview(QString::fromUtf8(plugin_a));
  require(!regrant_review.isEmpty() && scheduler.jobs.size() == 1,
          "required-disabled restart was not publicly reviewable");
  run_job();
  drain();
  const auto regrant = control->apply(
      regrant_review,
      grantEveryAvailablePermission(permissionRows(*control, regrant_review)));
  require(!regrant.isEmpty() && scheduler.jobs.size() == 1,
          "public regrant was not queued from permission-only state");
  run_job();
  drain();
  require(permissionOperation(*control, regrant).value("state") ==
                  "succeeded" &&
              observed(observe_slots(), plugin_a).preparing &&
              scheduler.jobs.size() == 1,
          "public regrant did not queue exact recovery preparation");
  notification_hold.hold();
  run_job();
  drain();
  require(await([&] {
            drain();
            return observed(observe_slots(), plugin_a).running &&
                   manager->count() == 2;
          }) &&
              notification_state->awaitEntered(),
          "public regrant did not recover runtime and notification provider");
  const auto recovered_notification = notification_state->last();
  require(recovered_notification.plugin == QString::fromUtf8(plugin_a) &&
              recovered_notification.category == "a" &&
              notification_state->calls() == 2,
          "regrant notification escaped its plugin/category identity");
  notification_hold.release();
}

void public_archive_install_is_closed_until_exact_consent() {
  constexpr std::string_view plugin = "org.example.secure-install";
  RuntimeFixture fixture;
  const auto archive = fixture.archive(plugin, "first");
  const auto descriptor_count = openDescriptorCount();
  {
    auto no_runtime = bridge::PluginManagerTestAccess::create();
    require(no_runtime->installer()
                ->begin(QString::fromStdString(archive.string()))
                .isEmpty() &&
                openDescriptorCount() == descriptor_count,
            "no-runtime install leaked its consumed archive descriptor");
  }
  const auto symlink = archive.parent_path() / "archive-link.tar";
  std::filesystem::create_symlink(archive, symlink);
  {
    auto no_runtime = bridge::PluginManagerTestAccess::create();
    QString embedded_nul = QStringLiteral("/tmp/archive");
    embedded_nul.append(QChar(0));
    embedded_nul.append(QStringLiteral("tail"));
    require(no_runtime->installer()->begin(embedded_nul).isEmpty(),
            "native archive ingress accepted an embedded NUL");
  }
  DeterministicJobs scheduler;
  auto manager = bridge::PluginManagerTestAccess::create();
  bridge::PluginManagerTestAccess::installRuntime(*manager,
                                                  fixture.bootstrap());
  bridge::PluginManagerTestAccess::setJobSubmitter(
      *manager, [&](auto kind, auto job) {
        return scheduler.submit(kind, std::move(job));
      });

  const auto runtime_descriptor_count = openDescriptorCount();
  require(manager->installer()
              ->begin(QString::fromStdString(symlink.string()))
              .isEmpty() &&
              scheduler.jobs.empty() &&
              openDescriptorCount() == runtime_descriptor_count,
          "native archive ingress followed a symlink or leaked its descriptor");
  scheduler.refuses = true;
  require(manager->installer()
              ->begin(QString::fromStdString(archive.string()))
              .isEmpty() &&
              openDescriptorCount() == runtime_descriptor_count,
          "refused install submission leaked its consumed descriptor");
  scheduler.refuses = false;
  scheduler.throws = true;
  require(manager->installer()
              ->begin(QString::fromStdString(archive.string()))
              .isEmpty() &&
              openDescriptorCount() == runtime_descriptor_count,
          "throwing install submission leaked its consumed descriptor");
  scheduler.throws = false;

  const auto install = manager->installer()->begin(
      QString::fromStdString(archive.string()));
  require(!install.isEmpty() && scheduler.jobs.size() == 1 &&
              scheduler.kinds.front() ==
                  bridge::PluginManagerTestAccess::TestJobKind::install &&
              manager->count() == 0,
          "public archive entrypoint did not queue exactly one off-UI job");
  std::thread worker([&] { scheduler.runOne(); });
  worker.join();
  bridge::PluginManagerTestAccess::drainRuntime(*manager);
  const auto installed = QJsonDocument::fromJson(
                             manager->installer()->poll(install).toUtf8())
                             .object();
  require(installed.value("state") == "succeeded" &&
              installed.value("result").toObject().value("plugin") ==
                  QString::fromUtf8(plugin) &&
              !installed.value("result").toObject().contains("revision") &&
              scheduler.jobs.size() == 1 && manager->count() == 0,
          "staged archive leaked revision authority or published before review");

  auto observations = bridge::PluginManagerTestAccess::runtimeSlots(*manager);
  require(observations.size() == 1 && observed(observations, plugin).preparing &&
              !observed(observations, plugin).has_runtime_root &&
              !observed(observations, plugin).has_endpoint_owner,
          "candidate reconciliation created runtime authority before review");
  worker = std::thread([&] { scheduler.runOne(); });
  worker.join();
  bridge::PluginManagerTestAccess::drainRuntime(*manager);
  observations = bridge::PluginManagerTestAccess::runtimeSlots(*manager);
  const auto view = bridge::PluginManagerTestAccess::permissionView(
      *manager, plugin, observed(observations, plugin).epoch);
  require(observed(observations, plugin).permission_disabled && view &&
              view->authority_slots.sequence == 0 && !view->active &&
              manager->count() == 0,
          "fresh archive candidate had grants, an active slot, or a surface");

  const auto review = manager->installer()->beginReview(install);
  require(!review.isEmpty() && scheduler.jobs.size() == 1,
          "opaque install handle did not begin exact candidate review");
  worker = std::thread([&] { scheduler.runOne(); });
  worker.join();
  bridge::PluginManagerTestAccess::drainRuntime(*manager);
  const auto review_result = permissionOperation(*manager->permissions(), review);
  require(review_result.value("state") == "succeeded" &&
              review_result.value("result").toObject().value("plugin") ==
                  QString::fromUtf8(plugin) &&
              manager->installer()->beginReview(install).isEmpty() &&
              manager->count() == 0,
          "exact review replayed or activated without an apply transaction");
  const auto install_rows = permissionRows(*manager->permissions(), review);
  require(install_rows.size() == 1 &&
              install_rows.at(0).toObject().value("required").toBool() &&
              manager->permissions()
                  ->applyInteractiveCli(review,
                                        QStringLiteral("{\"choices\":[]}"))
                  .isEmpty() &&
              scheduler.jobs.empty(),
          "nonempty install review accepted an empty decision set");
  QJsonArray denied_choices;
  denied_choices.push_back(
      QJsonObject{{QStringLiteral("rowId"),
                   install_rows.at(0).toObject().value("rowId")},
                  {QStringLiteral("decision"), QStringLiteral("deny")}});
  const auto denied_required = QString::fromUtf8(
      QJsonDocument(QJsonObject{{QStringLiteral("choices"), denied_choices}})
          .toJson(QJsonDocument::Compact));
  require(manager->permissions()
              ->applyInteractiveCli(review, denied_required)
              .isEmpty() &&
              scheduler.jobs.empty(),
          "required install permission accepted an explicit denial");
  const auto stale_choices =
      grantEveryAvailablePermission(install_rows);
  observations = bridge::PluginManagerTestAccess::runtimeSlots(*manager);
  const auto canceled_view = bridge::PluginManagerTestAccess::permissionView(
      *manager, plugin, observed(observations, plugin).epoch);
  require(observed(observations, plugin).permission_disabled && canceled_view &&
              canceled_view->authority_slots.sequence == 0 &&
              !canceled_view->active,
          "cancelled archive review changed authority or activation state");

  const auto invalid_archive = archive.parent_path() / "invalid.tar";
  std::ofstream(invalid_archive) << "not a tar archive";
  const auto rejected = manager->installer()->begin(
      QString::fromStdString(invalid_archive.string()));
  require(!rejected.isEmpty() && scheduler.jobs.size() == 1,
          "invalid archive did not enter bounded asynchronous verification");
  worker = std::thread([&] { scheduler.runOne(); });
  worker.join();
  bridge::PluginManagerTestAccess::drainRuntime(*manager);
  const auto rejected_result = QJsonDocument::fromJson(
                                   manager->installer()->poll(rejected).toUtf8())
                                   .object();
  require(rejected_result.value("state") == "failed" &&
              rejected_result.value("error") == "archive-rejected" &&
              permissionOperation(*manager->permissions(), review)
                      .value("state") == "succeeded" &&
              scheduler.jobs.empty() && manager->count() == 0,
          "rejected archive changed the existing review or authority state");

  const auto update_archive = fixture.archive(plugin, "update");
  const auto update = manager->installer()->begin(
      QString::fromStdString(update_archive.string()));
  require(!update.isEmpty() && scheduler.jobs.size() == 1,
          "secure update did not queue one exact archive job");
  worker = std::thread([&] { scheduler.runOne(); });
  worker.join();
  bridge::PluginManagerTestAccess::drainRuntime(*manager);
  const auto update_state = QJsonDocument::fromJson(
                                manager->installer()->poll(update).toUtf8())
                  .object()
                  .value("state");
  const auto stale_apply = manager->permissions()->applyInteractiveCli(
      review, stale_choices);
  if (update_state != "succeeded" || !stale_apply.isEmpty() ||
      manager->count() != 0 || scheduler.jobs.size() != 1)
    throw std::runtime_error(
        "secure update admitted a stale prior-revision review: state=" +
        update_state.toString().toStdString() + " apply=" +
        stale_apply.toStdString() + " count=" +
        std::to_string(manager->count()) + " jobs=" +
        std::to_string(scheduler.jobs.size()));
  worker = std::thread([&] { scheduler.runOne(); });
  worker.join();
  bridge::PluginManagerTestAccess::drainRuntime(*manager);
  observations = bridge::PluginManagerTestAccess::runtimeSlots(*manager);
  const auto updated_view = bridge::PluginManagerTestAccess::permissionView(
      *manager, plugin, observed(observations, plugin).epoch);
  require(observed(observations, plugin).permission_disabled && updated_view &&
              updated_view->authority_slots.sequence == 0 &&
              !updated_view->active && manager->count() == 0,
          "secure update ran or granted its new revision before consent");
  const auto update_review = manager->installer()->beginReview(update);
  require(!update_review.isEmpty() && scheduler.jobs.size() == 1,
          "secure update could not review its exact replacement revision");
  worker = std::thread([&] { scheduler.runOne(); });
  worker.join();
  bridge::PluginManagerTestAccess::drainRuntime(*manager);
  require(permissionOperation(*manager->permissions(), update_review)
                  .value("state") == "succeeded" &&
              manager->count() == 0,
          "exact update review activated without the sole apply transaction");
  observations = bridge::PluginManagerTestAccess::runtimeSlots(*manager);
  const auto exact_candidate =
      bridge::PluginManagerTestAccess::preparePermissionReview(
          *manager, plugin, observed(observations, plugin).epoch);
  require(exact_candidate != nullptr,
          "exact update candidate was unavailable before apply proof");
  const auto apply = manager->permissions()->applyInteractiveCli(
      update_review,
      grantEveryAvailablePermission(
          permissionRows(*manager->permissions(), update_review)));
  require(!apply.isEmpty() && scheduler.jobs.size() == 1,
          "exact install review did not enter the sole apply transaction");
  worker = std::thread([&] { scheduler.runOne(); });
  worker.join();
  bridge::PluginManagerTestAccess::drainRuntime(*manager);
  observations = bridge::PluginManagerTestAccess::runtimeSlots(*manager);
  const auto active_view = bridge::PluginManagerTestAccess::permissionView(
      *manager, plugin, observed(observations, plugin).epoch);
  require(permissionOperation(*manager->permissions(), apply).value("state") ==
                  "succeeded" &&
              observed(observations, plugin).preparing && active_view &&
              active_view->active &&
              active_view->active->binding ==
                  exact_candidate->candidate_binding &&
              active_view->authority_slots.sequence > 0 &&
              manager->count() == 0 && scheduler.jobs.size() == 1 &&
              manager->permissions()
                  ->applyInteractiveCli(update_review, stale_choices)
                  .isEmpty(),
          "apply did not exclusively promote the exact reviewed binding");
}

void public_zero_permission_archive_activates_with_empty_decisions() {
  constexpr std::string_view plugin = "org.example.zero-permission-install";
  constexpr std::string_view no_permissions =
      R"({"required":[],"optional":[]})";
  RuntimeFixture fixture;
  const auto archive = fixture.archive(plugin, "zero-permission",
                                       no_permissions);
  DeterministicJobs scheduler;
  auto manager = bridge::PluginManagerTestAccess::create();
  bridge::PluginManagerTestAccess::installRuntime(*manager,
                                                  fixture.bootstrap());
  bridge::PluginManagerTestAccess::setJobSubmitter(
      *manager, [&](auto kind, auto job) {
        return scheduler.submit(kind, std::move(job));
      });
  const auto run_job = [&] {
    require(!scheduler.jobs.empty(), "zero-permission job disappeared");
    std::thread worker([&] { scheduler.runOne(); });
    worker.join();
    bridge::PluginManagerTestAccess::drainRuntime(*manager);
  };

  const auto install = manager->installer()->begin(
      QString::fromStdString(archive.string()));
  require(!install.isEmpty() && scheduler.jobs.size() == 1,
          "zero-permission archive did not enter public secure install");
  run_job();
  const auto installed = QJsonDocument::fromJson(
                             manager->installer()->poll(install).toUtf8())
                             .object();
  require(installed.value("state") == "succeeded" &&
              installed.value("result").toObject().value("plugin") ==
                  QString::fromUtf8(plugin) &&
              scheduler.jobs.size() == 1,
          "zero-permission archive was not staged as an exact candidate");

  run_job();
  auto observations =
      bridge::PluginManagerTestAccess::runtimeSlots(*manager);
  require(observations.size() == 1 &&
              observed(observations, plugin).permission_disabled,
          "zero-permission candidate bypassed the inactive review state");
  const auto before = bridge::PluginManagerTestAccess::permissionView(
      *manager, plugin, observed(observations, plugin).epoch);
  require(before && before->authority_slots.sequence == 0 && !before->active,
          "zero-permission candidate fabricated pre-review authority");

  const auto review = manager->installer()->beginReview(install);
  require(!review.isEmpty() && scheduler.jobs.size() == 1,
          "zero-permission candidate did not expose its exact review");
  run_job();
  const auto reviewed =
      permissionOperation(*manager->permissions(), review);
  require(reviewed.value("state") == "succeeded" &&
              permissionRows(*manager->permissions(), review).isEmpty() &&
              scheduler.jobs.empty(),
          "zero-permission review fabricated a permission row");

  const auto exact_review =
      bridge::PluginManagerTestAccess::preparePermissionReview(
          *manager, plugin, observed(observations, plugin).epoch);
  require(exact_review && exact_review->builtin_rows.empty() &&
              exact_review->dynamic_rows.empty(),
          "zero-permission native review was not exactly empty");
  const auto apply = manager->permissions()->applyInteractiveCli(
      review, QStringLiteral("{\"choices\":[]}"));
  require(!apply.isEmpty() && scheduler.jobs.size() == 1,
          "exact empty decision set did not enter the sole apply transaction");
  run_job();

  observations = bridge::PluginManagerTestAccess::runtimeSlots(*manager);
  const auto active = bridge::PluginManagerTestAccess::permissionView(
      *manager, plugin, observed(observations, plugin).epoch);
  require(permissionOperation(*manager->permissions(), apply).value("state") ==
                  "succeeded" &&
              observed(observations, plugin).preparing && active &&
              active->active &&
              active->active->binding == exact_review->candidate_binding &&
              active->active->requests.empty() &&
              active->active->grants.empty() &&
              active->active->dynamic_grants.empty() &&
              active->authority_slots.sequence > 0 &&
              scheduler.jobs.size() == 1 &&
              manager->permissions()
                  ->applyInteractiveCli(
                      review, QStringLiteral("{\"choices\":[]}"))
                  .isEmpty(),
          "zero-permission install did not exclusively activate its exact "
          "empty authority snapshot");
}

void permission_control_is_bounded_and_destruction_safe() {
  if (std::getenv("OMARCHY_REQUIRE_PACKAGED_WORKER_TEST") == nullptr)
    return;
  constexpr std::string_view plugin = "org.example.bounded-permissions";
  constexpr std::string_view permission_json =
      R"({"required":[],"optional":[]})";
  RuntimeFixture fixture;
  fixture.seedRuntime(plugin, permissionAwareQml, permission_json);
  DeterministicJobs scheduler;
  auto manager = bridge::PluginManagerTestAccess::create();
  auto services = channel::RuntimeServices{.context = std::make_shared<int>(0),
                                           .notification_send = nullptr,
                                           .audio_play = nullptr,
                                           .compare_scope = nullptr,
                                           .provider_catalog = {}};
  bridge::PluginManagerTestAccess::installRuntime(
      *manager, fixture.bootstrap(std::move(services)));
  bridge::PluginManagerTestAccess::setJobSubmitter(
      *manager, [&](auto kind, auto job) {
        return scheduler.submit(kind, std::move(job));
      });
  const auto run_job = [&] {
    require(!scheduler.jobs.empty(), "bounded-control job disappeared");
    scheduler.runOne();
    bridge::PluginManagerTestAccess::drainRuntime(*manager);
  };

  require(bridge::PluginManagerTestAccess::scanRuntime(*manager) &&
              scheduler.jobs.size() == 1,
          "bounded-control fixture did not queue preparation");
  run_job();
  require(await([&] {
            bridge::PluginManagerTestAccess::drainRuntime(*manager);
            const auto state =
                bridge::PluginManagerTestAccess::runtimeSlots(*manager);
            return state.size() == 1 && state.front().running;
          }),
          "bounded-control fixture did not activate safely");
  auto observations = bridge::PluginManagerTestAccess::runtimeSlots(*manager);

  auto *control = manager->permissions();
  const auto review =
      control->beginInteractiveCliReview(QString::fromUtf8(plugin));
  require(!review.isEmpty(), "bounded plugin did not expose a CLI review");
  run_job();
  const auto rows = permissionRows(*control, review);
  require(
      rows.isEmpty() &&
          control->apply(review, grantEveryAvailablePermission(rows))
              .isEmpty() &&
          control->apply(review, QString(32 + 256 * 1024 + 1, 'x')).isEmpty(),
      "UI ingress or oversized choice crossed the CLI review boundary");

  const auto apply =
      control->applyInteractiveCli(review, grantEveryAvailablePermission(rows));
  require(!apply.isEmpty(), "empty CLI review could not be confirmed");
  require(!scheduler.jobs.empty(), "CLI apply job disappeared");
  scheduler.runOne();
  require(bridge::PluginManagerTestAccess::pendingPermissionActor(
              *manager, plugin) == permissions::DecisionActor::interactive_cli,
          "CLI actor did not persist through the asynchronous manager lane");
  bridge::PluginManagerTestAccess::drainRuntime(*manager);
  require(permissionOperation(*control, apply).value("state") == "succeeded" &&
              scheduler.jobs.size() == 1,
          "CLI review did not enter exact preparation");
  run_job();
  require(await([&] {
            bridge::PluginManagerTestAccess::drainRuntime(*manager);
            observations =
                bridge::PluginManagerTestAccess::runtimeSlots(*manager);
            return observations.size() == 1 && observations.front().running;
          }),
          "bounded review did not permit activation");

  const auto ttl_review = control->beginReview(QString::fromUtf8(plugin));
  require(!ttl_review.isEmpty(), "review TTL proof did not queue");
  run_job();
  bridge::PermissionControlTestAccess::ageOperation(*control, ttl_review,
                                                    std::chrono::minutes(2));
  require(permissionOperation(*control, ttl_review).value("state") ==
              "succeeded",
          "interactive review expired at ordinary operation TTL");
  bridge::PermissionControlTestAccess::ageOperation(*control, ttl_review,
                                                    std::chrono::minutes(16));
  require(control->poll(ttl_review).isEmpty(),
          "interactive review survived its bounded review TTL");

  std::size_t accepted = 0;
  for (; accepted < 40; ++accepted) {
    const auto list = control->beginList(QString::fromUtf8(plugin));
    if (list.isEmpty())
      break;
    run_job();
    require(permissionOperation(*control, list).value("state") == "succeeded",
            "bounded list operation failed before registry saturation");
  }
  require(accepted > 0 && accepted < 40 &&
              control->beginList(QString::fromUtf8(plugin)).isEmpty(),
          "permission operation registry did not enforce its hard bound");

  manager.reset();
  manager = bridge::PluginManagerTestAccess::create();
  services = channel::RuntimeServices{.context = std::make_shared<int>(0),
                                      .notification_send = nullptr,
                                      .audio_play = nullptr,
                                      .compare_scope = nullptr,
                                      .provider_catalog = {}};
  bridge::PluginManagerTestAccess::installRuntime(
      *manager, fixture.bootstrap(std::move(services)));
  bridge::PluginManagerTestAccess::setJobSubmitter(
      *manager, [&](auto kind, auto job) {
        return scheduler.submit(kind, std::move(job));
      });
  require(bridge::PluginManagerTestAccess::scanRuntime(*manager) &&
              scheduler.jobs.size() == 1,
          "permission-read destruction fixture did not queue preparation");
  run_job();
  require(await([&] {
            bridge::PluginManagerTestAccess::drainRuntime(*manager);
            const auto state =
                bridge::PluginManagerTestAccess::runtimeSlots(*manager);
            return state.size() == 1 && state.front().running;
          }),
          "permission-read destruction fixture did not become readable");
  std::mutex read_mutex;
  std::condition_variable read_changed;
  bool read_entered = false;
  bool release_read = false;
  bridge::PluginManagerTestAccess::setJobEntryProbe(*manager, [&](auto kind) {
    if (kind != bridge::PluginManagerTestAccess::TestJobKind::permission)
      return;
    std::unique_lock lock(read_mutex);
    read_entered = true;
    read_changed.notify_all();
    read_changed.wait(lock, [&] { return release_read; });
  });
  control = manager->permissions();
  require(!control->beginList(QString::fromUtf8(plugin)).isEmpty() &&
              scheduler.jobs.size() == 1,
          "permission read was not queued for destruction proof");
  const auto delivery_gate =
      bridge::PluginManagerTestAccess::deliveryGate(*manager);
  auto blocked_read = std::move(scheduler.jobs.front());
  scheduler.jobs.clear();
  scheduler.kinds.clear();
  std::thread read_worker([job = std::move(blocked_read)]() mutable { job(); });
  {
    std::unique_lock lock(read_mutex);
    read_changed.wait(lock, [&] { return read_entered; });
  }
  manager.reset();
  {
    std::scoped_lock lock(read_mutex);
    release_read = true;
  }
  read_changed.notify_all();
  read_worker.join();
  require(delivery_gate.expired(),
          "outstanding permission read retained destroyed manager state");
}

void controlled_mutations_settle_after_slot_loss() {
  if (std::getenv("OMARCHY_REQUIRE_PACKAGED_WORKER_TEST") == nullptr)
    return;
  constexpr std::string_view permission_json =
      R"({"required":[],"optional":[{"capability":"storage.private","reason":"state","quotaBytes":4096}]})";
  const auto start = [](bridge::PluginManager &manager,
                        DeterministicJobs &scheduler) {
    require(bridge::PluginManagerTestAccess::scanRuntime(manager) &&
                scheduler.jobs.size() == 1,
            "slot-loss fixture did not queue preparation");
    scheduler.runOne();
    require(await([&] {
              bridge::PluginManagerTestAccess::drainRuntime(manager);
              const auto state =
                  bridge::PluginManagerTestAccess::runtimeSlots(manager);
              return state.size() == 1 && state.front().running;
            }),
            "slot-loss fixture did not reach running");
  };

  {
    constexpr std::string_view plugin = "org.example.removed-permission";
    RuntimeFixture fixture;
    fixture.seedRuntime(plugin, "import QtQuick\nItem {}\n", permission_json);
    DeterministicJobs scheduler;
    auto manager = bridge::PluginManagerTestAccess::create();
    bridge::PluginManagerTestAccess::installRuntime(*manager,
                                                    fixture.bootstrap());
    bridge::PluginManagerTestAccess::setJobSubmitter(
        *manager, [&](auto kind, auto job) {
          return scheduler.submit(kind, std::move(job));
        });
    start(*manager, scheduler);
    auto *control = manager->permissions();
    const auto list = control->beginList(QString::fromUtf8(plugin));
    require(!list.isEmpty(), "removal revoke list was not queued");
    scheduler.runOne();
    bridge::PluginManagerTestAccess::drainRuntime(*manager);
    const auto row =
        permissionRow(permissionRows(*control, list), "storage.private");
    const auto revoke = control->revoke(list, row);
    require(!revoke.isEmpty() && scheduler.jobs.size() == 1,
            "removal revoke was not queued");
    fixture.erase(plugin);
    require(bridge::PluginManagerTestAccess::scanRuntime(*manager) &&
                bridge::PluginManagerTestAccess::runtimeSlots(*manager).empty(),
            "plugin removal retained its manager slot");
    scheduler.runOne();
    bridge::PluginManagerTestAccess::drainRuntime(*manager);
    require(permissionOperation(*control, revoke).value("state") == "succeeded",
            "committed revoke was orphaned by slot removal");
  }

  {
    constexpr std::string_view plugin = "org.example.replaced-permission";
    RuntimeFixture fixture;
    fixture.seedRuntime(plugin, "import QtQuick\nItem {}\n", permission_json);
    DeterministicJobs scheduler;
    auto manager = bridge::PluginManagerTestAccess::create();
    bridge::PluginManagerTestAccess::installRuntime(*manager,
                                                    fixture.bootstrap());
    bridge::PluginManagerTestAccess::setJobSubmitter(
        *manager, [&](auto kind, auto job) {
          return scheduler.submit(kind, std::move(job));
        });
    start(*manager, scheduler);
    auto *control = manager->permissions();
    const auto review = control->beginReview(QString::fromUtf8(plugin));
    require(!review.isEmpty(), "replacement review was not queued");
    scheduler.runOne();
    bridge::PluginManagerTestAccess::drainRuntime(*manager);
    const auto apply = control->apply(
        review,
        grantEveryAvailablePermission(permissionRows(*control, review)));
    require(!apply.isEmpty() && scheduler.jobs.size() == 1,
            "replacement apply was not queued");
    const auto replacement = fixture.stageRuntime(
        plugin, 2, "import QtQuick\nItem {}\n", permission_json);
    fixture.selectReplacement(replacement);
    require(bridge::PluginManagerTestAccess::scanRuntime(*manager),
            "replacement scan was rejected");
    scheduler.runAt(0);
    bridge::PluginManagerTestAccess::drainRuntime(*manager);
    const auto outcome = permissionOperation(*control, apply);
    require(outcome.value("state") == "succeeded" &&
                outcome.value("result").toObject().value("applied") == true,
            "committed apply was orphaned by slot replacement");
  }

  {
    constexpr std::string_view plugin = "org.example.rejected-permission";
    constexpr std::string_view required_permission_json =
        R"({"required":[{"capability":"storage.private","reason":"state","quotaBytes":4096}],"optional":[]})";
    RuntimeFixture fixture;
    fixture.seedRuntime(plugin, "import QtQuick\nItem {}\n",
                        required_permission_json);
    DeterministicJobs scheduler;
    auto manager = bridge::PluginManagerTestAccess::create();
    bridge::PluginManagerTestAccess::installRuntime(*manager,
                                                    fixture.bootstrap());
    bridge::PluginManagerTestAccess::setJobSubmitter(
        *manager, [&](auto kind, auto job) {
          return scheduler.submit(kind, std::move(job));
        });
    start(*manager, scheduler);

    auto *control = manager->permissions();
    const auto review = control->beginReview(QString::fromUtf8(plugin));
    require(!review.isEmpty(), "stale-authority review was not queued");
    scheduler.runOne();
    bridge::PluginManagerTestAccess::drainRuntime(*manager);
    const auto rows = permissionRows(*control, review);
    require(rows.size() == 1, "stale-authority review row was missing");
    const auto slot = bridge::PluginManagerTestAccess::runtimeSlots(*manager)
                          .front();
    const auto view = bridge::PluginManagerTestAccess::permissionView(
        *manager, plugin, slot.epoch);
    require(view.has_value(),
            "stale-authority fixture lacked an authority view");
    const auto apply = control->apply(
        review, grantEveryAvailablePermission(rows));
    require(!apply.isEmpty() && scheduler.jobs.size() == 1,
            "stale-authority apply was not queued");
    const permissions::CapabilityKey storage{
        .id = permissions::CapabilityId("storage.private"), .version = 1};
    require(view && bridge::PluginManagerTestAccess::
                        revokePermissionImmediatelyForTest(
                            *manager, plugin, slot.epoch, storage,
                            view->authority_slots.sequence),
            "stale-authority fixture did not advance exact authority");
    const auto replacement = fixture.stageRuntime(
        plugin, 2, "import QtQuick\nItem {}\n", required_permission_json);
    fixture.selectReplacement(replacement);
    require(bridge::PluginManagerTestAccess::scanRuntime(*manager),
            "stale-authority replacement scan was rejected");
    scheduler.runAt(0);
    bridge::PluginManagerTestAccess::drainRuntime(*manager);
    const auto outcome = permissionOperation(*control, apply);
    require(outcome.value("state") == "failed" &&
                outcome.value("error") == "authority-rejected",
            "authoritative rejection was orphaned by slot replacement");
  }
}

void concurrent_permission_fences_route_exactly() {
  if (std::getenv("OMARCHY_REQUIRE_PACKAGED_WORKER_TEST") == nullptr)
    return;
  constexpr std::string_view plugin_a = "a.permission-plugin";
  constexpr std::string_view plugin_b = "b.permission-plugin";
  constexpr std::string_view permissions_a =
      R"({"required":[],"optional":[{"capability":"notifications.send","reason":"A alerts","categories":["a"]}]})";
  constexpr std::string_view permissions_b =
      R"({"required":[],"optional":[{"capability":"notifications.send","reason":"B alerts","categories":["b"]}]})";
  RuntimeFixture fixture;
  const auto binding_a =
      fixture.seedRuntime(plugin_a, permissionAwareQmlFor("a"), permissions_a);
  const auto binding_b =
      fixture.seedRuntime(plugin_b, permissionAwareQmlFor("b"), permissions_b);
  auto effects = std::make_shared<BlockingNotifications>();
  effects->hold("a");
  effects->hold("b");
  channel::RuntimeServices services{.context = effects,
                                    .notification_send =
                                        BlockingNotifications::send,
                                    .audio_play = nullptr,
                                    .compare_scope = nullptr,
                                    .provider_catalog = {}};
  DeterministicJobs scheduler;
  auto manager = bridge::PluginManagerTestAccess::create();
  struct ReleaseEffects final {
    std::shared_ptr<BlockingNotifications> effects;

    ~ReleaseEffects() {
      effects->release("a");
      effects->release("b");
    }
  } release_effects{effects};
  bridge::PluginManagerTestAccess::installRuntime(
      *manager, fixture.bootstrap(std::move(services)));
  bridge::PluginManagerTestAccess::setJobSubmitter(
      *manager, [&](auto kind, auto job) {
        return scheduler.submit(kind, std::move(job));
      });
  require(bridge::PluginManagerTestAccess::scanRuntime(*manager) &&
              scheduler.jobs.size() == 2,
          "two-plugin permission fixture did not enqueue preparations");
  while (!scheduler.jobs.empty()) {
    std::thread worker([&] { scheduler.runOne(); });
    worker.join();
    bridge::PluginManagerTestAccess::drainRuntime(*manager);
  }
  require(await([&] {
            bridge::PluginManagerTestAccess::drainRuntime(*manager);
            const auto observations =
                bridge::PluginManagerTestAccess::runtimeSlots(*manager);
            return observations.size() == 2 &&
                   observed(observations, plugin_a).running &&
                   observed(observations, plugin_b).running;
          }) &&
              effects->awaitEntered("a") && effects->awaitEntered("b"),
          "two packaged QML effects did not enter independently");

  auto observations = bridge::PluginManagerTestAccess::runtimeSlots(*manager);
  require(manager->count() == 2,
          "two permission generations did not publish independently");
  const auto key_a = barSurfaceKey(*manager, plugin_a);
  const auto key_b = barSurfaceKey(*manager, plugin_b);
  QQuickWindow permission_window;
  permission_window.resize(128, 64);
  permission_window.show();
  bridge::RemotePluginSurface remote_a(permission_window.contentItem());
  bridge::RemotePluginSurface remote_b(permission_window.contentItem());
  remote_a.setWidth(64);
  remote_a.setHeight(64);
  remote_b.setWidth(64);
  remote_b.setHeight(64);
  remote_b.setX(64);
  const bool attached_a = manager->attach(key_a, &remote_a);
  const bool attached_b = manager->attach(key_b, &remote_b);
  require(attached_a && attached_b,
          "two permission generations did not attach independently: A=" +
              std::to_string(attached_a) + " key=" + key_a.toStdString() +
              ", B=" + std::to_string(attached_b) +
              " key=" + key_b.toStdString());
  auto *control = manager->permissions();
  const auto list_a = control->beginList(QString::fromUtf8(plugin_a));
  const auto list_b = control->beginList(QString::fromUtf8(plugin_b));
  require(!list_a.isEmpty() && !list_b.isEmpty() && scheduler.jobs.size() == 2,
          "two public permission reads did not enter bounded lanes");
  scheduler.runOne();
  bridge::PluginManagerTestAccess::drainRuntime(*manager);
  scheduler.runOne();
  bridge::PluginManagerTestAccess::drainRuntime(*manager);
  const auto row_a =
      permissionRow(permissionRows(*control, list_a), "notifications.send");
  const auto row_b =
      permissionRow(permissionRows(*control, list_b), "notifications.send");
  require(!row_a.isEmpty() && !row_b.isEmpty() && row_a != row_b &&
              control->revoke(list_a, row_b).isEmpty() &&
              control->revoke(list_b, row_a).isEmpty(),
          "opaque rows collided or crossed their exact plugin context");
  const auto revoke_a = control->revoke(list_a, row_a);
  const auto revoke_b = control->revoke(list_b, row_b);
  require(!revoke_a.isEmpty() && !revoke_b.isEmpty() &&
              scheduler.jobs.size() == 2,
          "two public permission mutations did not enter bounded lanes");

  auto job_a = std::move(scheduler.jobs.at(0));
  auto job_b = std::move(scheduler.jobs.at(1));
  scheduler.jobs.clear();
  scheduler.kinds.clear();
  std::thread worker_a([job = std::move(job_a)]() mutable { job(); });
  std::thread worker_b([job = std::move(job_b)]() mutable { job(); });
  require(await([&] {
            bridge::PluginManagerTestAccess::drainRuntime(*manager);
            const auto current =
                bridge::PluginManagerTestAccess::runtimeSlots(*manager);
            return observed(current, plugin_a).permission_changing &&
                   observed(current, plugin_b).permission_changing;
          }),
          "concurrent authority fences did not both reach the Manager");
  observations = bridge::PluginManagerTestAccess::runtimeSlots(*manager);
  bridge::RemotePluginSurface stale_a;
  bridge::RemotePluginSurface stale_b;
  require(
      manager->count() == 0 && !remote_a.connected() && !remote_b.connected() &&
          observed(observations, plugin_a).has_runtime_root &&
          observed(observations, plugin_b).has_runtime_root &&
          bridge::PluginManagerTestAccess::executingPermissionJobs(*manager) ==
              2 &&
          !manager->attach(key_a, &stale_a) &&
          !manager->attach(key_b, &stale_b),
      "concurrent fences crossed or failed to withdraw exact generations");

  effects->release("b");
  worker_b.join();
  bridge::PluginManagerTestAccess::drainRuntime(*manager);
  require(
      permissionOperation(*control, revoke_b).value("state") == "succeeded" &&
          permissionOperation(*control, revoke_a).value("state") == "pending",
      "reordered B completion crossed public operation identity");
  observations = bridge::PluginManagerTestAccess::runtimeSlots(*manager);
  require(observed(observations, plugin_a).permission_changing &&
              observed(observations, plugin_a).has_runtime_root &&
              observed(observations, plugin_b).preparing &&
              scheduler.jobs.size() == 1,
          "settled B permission result disturbed blocked A");
  std::thread prepare_b([&] { scheduler.runOne(); });
  prepare_b.join();
  require(await([&] {
            bridge::PluginManagerTestAccess::drainRuntime(*manager);
            const auto current =
                bridge::PluginManagerTestAccess::runtimeSlots(*manager);
            return observed(current, plugin_b).running;
          }),
          "settled B did not start its exact replacement");
  auto current_b = bridge::PluginManagerTestAccess::permissionView(
      *manager, plugin_b,
      observed(bridge::PluginManagerTestAccess::runtimeSlots(*manager),
               plugin_b)
          .epoch);
  auto expected_b = binding_b;
  ++expected_b.generation;
  require(current_b && current_b->active &&
              current_b->active->binding == expected_b &&
              effects->calls("b") == 1,
          "B replacement binding or revoked QML selector was not exact");

  effects->release("a");
  worker_a.join();
  bridge::PluginManagerTestAccess::drainRuntime(*manager);
  require(permissionOperation(*control, revoke_a).value("state") == "succeeded",
          "reordered A completion did not settle its exact operation");
  observations = bridge::PluginManagerTestAccess::runtimeSlots(*manager);
  require(observed(observations, plugin_b).running &&
              observed(observations, plugin_a).preparing &&
              scheduler.jobs.size() == 1,
          "settled A permission result disturbed replacement B");
  std::thread prepare_a([&] { scheduler.runOne(); });
  prepare_a.join();
  require(await([&] {
            bridge::PluginManagerTestAccess::drainRuntime(*manager);
            const auto current =
                bridge::PluginManagerTestAccess::runtimeSlots(*manager);
            return observed(current, plugin_a).running &&
                   observed(current, plugin_b).running;
          }),
          "A replacement did not converge beside replacement B");
  const auto final_slots =
      bridge::PluginManagerTestAccess::runtimeSlots(*manager);
  auto current_a = bridge::PluginManagerTestAccess::permissionView(
      *manager, plugin_a, observed(final_slots, plugin_a).epoch);
  auto expected_a = binding_a;
  ++expected_a.generation;
  require(current_a && current_a->active &&
              current_a->active->binding == expected_a &&
              effects->calls("a") == 1,
          "A replacement binding or revoked QML selector was not exact");
}

void real_root_publishes_attaches_and_tears_down_exactly() {
  if (std::getenv("OMARCHY_REQUIRE_PACKAGED_WORKER_TEST") == nullptr)
    return;
  const bool packaged_worker_available =
      ::access(
          std::string(omarchy::plugin_runtime::kPackagedWorkerPath).c_str(),
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

  QQuickWindow window;
  window.resize(320, 64);
  window.show();
  bridge::RemotePluginSurface rollback_remote(window.contentItem());
  rollback_remote.setWidth(320);
  rollback_remote.setHeight(64);
  bridge::RemotePluginSurface *attachment_remote = &rollback_remote;
  bool attached_in_signal = false;
  QObject::connect(manager.get(), &bridge::PluginManager::surfacesChanged, [&] {
    if (manager->count() != 1)
      return;
    const auto key =
        manager->barSurfaces()
            ->data(manager->barSurfaces()->index(0, 0), Model::SurfaceKeyRole)
            .toString();
    attached_in_signal = manager->attach(key, attachment_remote);
  });
  const auto throwing_publication = QObject::connect(
      manager.get(), &bridge::PluginManager::surfacesChanged,
      [] { throw std::runtime_error("injected publication signal failure"); });

  require(bridge::PluginManagerTestAccess::scanRuntime(*manager) &&
              scheduler.jobs.size() == 1 &&
              scheduler.kinds.front() ==
                  bridge::PluginManagerTestAccess::TestJobKind::preparation,
          "real root preparation did not enter the bounded manager lane");
  const auto first_epoch =
      bridge::PluginManagerTestAccess::runtimeSlots(*manager).front().epoch;
  std::thread preparation([&] { scheduler.runOne(); });
  preparation.join();
  bridge::PluginManagerTestAccess::drainRuntime(*manager);
  require(manager->count() == 0,
          "prepared runtime published before authenticated startup readiness");
  const bool rolled_back = await([&] {
    bridge::PluginManagerTestAccess::drainRuntime(*manager);
    const auto observations =
        bridge::PluginManagerTestAccess::runtimeSlots(*manager);
    return observations.size() == 1 && observations.front().retry_wait;
  });
  if (!rolled_back) {
    const auto observations =
        bridge::PluginManagerTestAccess::runtimeSlots(*manager);
    require(!observations.empty(), "real committed root slot disappeared");
    const auto &failure = observations.front();
    throw std::runtime_error("publication rollback did not settle: state=" +
                             std::to_string(failure.last_state) +
                             " error=" + std::to_string(failure.last_error) +
                             " opening=" + std::to_string(failure.opening) +
                             " starting=" + std::to_string(failure.starting) +
                             " retry=" + std::to_string(failure.retry_wait));
  }
  require(manager->count() == 0 && attached_in_signal &&
              !rollback_remote.connected() &&
              !bridge::PluginManagerTestAccess::runtimeSlots(*manager)
                   .front()
                   .has_endpoint_owner,
          "automatic publication failure retained rows, endpoint, or Remote");
  QObject::disconnect(throwing_publication);

  bridge::RemotePluginSurface remote(window.contentItem());
  remote.setWidth(320);
  remote.setHeight(64);
  attachment_remote = &remote;
  attached_in_signal = false;
  require(!bridge::PluginManagerTestAccess::deliverLifecycle(
              *manager, plugin, first_epoch,
              static_cast<std::uint8_t>(host::SessionState::running),
              static_cast<std::uint8_t>(host::SessionError::none)) &&
              bridge::PluginManagerTestAccess::retryRuntime(*manager, plugin) &&
              scheduler.jobs.size() == 1,
          "stale readiness epoch survived automatic-publication rollback");
  std::thread retry_preparation([&] { scheduler.runOne(); });
  retry_preparation.join();
  require(await([&] {
            bridge::PluginManagerTestAccess::drainRuntime(*manager);
            const auto observations =
                bridge::PluginManagerTestAccess::runtimeSlots(*manager);
            return observations.size() == 1 && observations.front().running &&
                   manager->count() == 1;
          }) &&
              attached_in_signal && remote.connected(),
          "authenticated retry did not publish and attach automatically");

  class IntentClock final : public runtime::GestureEligibilityClock {
  public:
    std::uint64_t now_nanoseconds() const override { return 100; }
  };
  auto intent_clock = std::make_shared<IntentClock>();
  runtime::GestureEligibilityLatch eligibility(intent_clock);
  host::GestureIntentAuthority intent_authority(exact_binding, eligibility);
  const surface::SurfaceKey source{.id = 1,
                                   .generation = exact_binding.generation};
  require(intent_authority.declare_surface(source, "bar") ==
                  host::SurfaceDeclarationResult::declared &&
              intent_authority.attach_surface(source),
          "running surface intent fixture did not declare its exact source");
  const auto admit = [&](std::uint64_t sequence,
                         surface::SurfaceIntentAction action) {
    require(intent_authority.arm(source, sequence),
            "running surface intent fixture did not arm");
    auto admission = intent_authority.admit({.source = source,
                                             .target = source,
                                             .input_sequence = sequence,
                                             .action = action});
    require(admission.intent.has_value(),
            "running surface intent fixture was not admitted");
    return std::move(*admission.intent);
  };
  auto open = admit(1, surface::SurfaceIntentAction::open);
  auto first_toggle = admit(2, surface::SurfaceIntentAction::toggle);
  auto second_toggle = admit(3, surface::SurfaceIntentAction::toggle);
  auto dismiss = admit(4, surface::SurfaceIntentAction::dismiss);
  const auto running =
      bridge::PluginManagerTestAccess::runtimeSlots(*manager).front();
  auto callback = bridge::PluginManagerTestAccess::surfaceIntentCallback(
      *manager, running.plugin, running.epoch);
  require(callback.has_value(),
          "running slot did not expose its exact callback mailbox in test");
  std::vector<std::string> delivered;
  QObject::connect(manager.get(), &bridge::PluginManager::openRequested,
                   [&] { delivered.emplace_back("open"); });
  QObject::connect(manager.get(), &bridge::PluginManager::toggleRequested,
                   [&] { delivered.emplace_back("toggle"); });
  QObject::connect(manager.get(), &bridge::PluginManager::dismissRequested,
                   [&] { delivered.emplace_back("dismiss"); });
  bool queued = false;
  std::thread intent_worker([&] {
    queued = callback->deliver(std::move(open)) &&
             callback->deliver(std::move(first_toggle)) &&
             callback->deliver(std::move(second_toggle)) &&
             callback->deliver(std::move(dismiss));
  });
  intent_worker.join();
  require(queued && callback->pending() == 4 && delivered.empty(),
          "callback-thread surface intents bypassed the bounded UI mailbox");
  bridge::PluginManagerTestAccess::drainRuntime(*manager);
  require(delivered ==
              std::vector<std::string>{"open", "toggle", "toggle", "dismiss"} &&
              callback->pending() == 0,
          "running exact slot did not preserve FIFO surface intent effects");

  const auto row = manager->barSurfaces()->index(0, 0);
  require(
      manager->barSurfaces()->data(row, Model::GenerationRole).toString() ==
              QString::number(exact_binding.generation) &&
          manager->barSurfaces()->data(row, Model::MaximumWidthRole).toUInt() ==
              320 &&
          manager->barSurfaces()
                  ->data(row, Model::MaximumHeightRole)
                  .toUInt() == 64 &&
          manager->barSurfaces()
                  ->data(row, Model::DefaultSectionRole)
                  .toString() == QStringLiteral("right"),
      "automatic publication did not preserve exact manifest policy");

  const auto published_key =
      manager->barSurfaces()
          ->data(manager->barSurfaces()->index(0, 0), Model::SurfaceKeyRole)
          .toString();
  bool detached_before_withdraw_signal = false;
  bool reentrant_old_key_rejected = false;
  QObject::connect(manager.get(), &bridge::PluginManager::surfacesChanged, [&] {
    if (manager->count() != 0)
      return;
    detached_before_withdraw_signal = !remote.connected();
    reentrant_old_key_rejected = !manager->attach(published_key, &remote);
  });
  fixture.erase(plugin);
  require(bridge::PluginManagerTestAccess::scanRuntime(*manager) &&
              manager->count() == 0 && !remote.connected() &&
              bridge::PluginManagerTestAccess::runtimeSlots(*manager).empty() &&
              detached_before_withdraw_signal && reentrant_old_key_rejected,
          "catalog removal did not close endpoint before withdrawing rows");
  manager.reset();
}

void neutral_surfaces_share_one_real_sandbox_and_teardown() {
  require(std::getenv("OMARCHY_REQUIRE_PACKAGED_WORKER_TEST") != nullptr,
          "neutral surface integration gate was not opted in");
  require(::access(std::string(omarchy::plugin_runtime::kPackagedWorkerPath)
                       .c_str(),
                   X_OK) == 0,
          "required packaged worker integration test was unavailable");

  using Model = bridge::SurfaceProjectionModel;
  constexpr std::string_view plugin =
      "org.omarchy.fixture.neutral-surfaces";
  const std::filesystem::path fixture_source =
      std::filesystem::path(OMARCHY_NEUTRAL_SURFACE_FIXTURE_ROOT);
  RuntimeFixture fixture;
  const auto exact_binding =
      fixture.seedCheckedFixture(plugin, fixture_source);
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
          "neutral fixture did not enter one preparation lane");
  std::exception_ptr preparation_error;
  std::jthread preparation([&] {
    try {
      scheduler.runOne();
    } catch (...) {
      preparation_error = std::current_exception();
    }
  });
  preparation.join();
  if (preparation_error)
    std::rethrow_exception(preparation_error);
  require(await([&] {
            bridge::PluginManagerTestAccess::drainRuntime(*manager);
            const auto observations =
                bridge::PluginManagerTestAccess::runtimeSlots(*manager);
            return observations.size() == 1 && observations.front().running &&
                   observations.front().has_runtime_root &&
                   observations.front().has_endpoint_owner &&
                   manager->count() == 3;
          }),
          "one neutral fixture runtime did not publish three ready surfaces");

  auto *bar_model = manager->barSurfaces();
  auto *panel_model = manager->panelSurfaces();
  auto *overlay_model = manager->overlaySurfaces();
  require(bar_model->rowCount() == 1 && panel_model->rowCount() == 1 &&
              overlay_model->rowCount() == 1,
          "neutral fixture roles were not published exactly once");
  const auto assert_row = [&](QAbstractItemModel *model,
                              std::string_view surface,
                              Model::Role expected_role,
                              std::uint32_t width, std::uint32_t height) {
    const auto row = model->index(0, 0);
    require(model->data(row, Model::PluginIdRole).toString() ==
                    QString::fromUtf8(plugin.data(), plugin.size()) &&
                model->data(row, Model::SurfaceNameRole).toString() ==
                    QString::fromUtf8(surface.data(), surface.size()) &&
                model->data(row, Model::SurfaceRoleRole).toInt() ==
                    static_cast<int>(expected_role) &&
                model->data(row, Model::GenerationRole).toString() ==
                    QString::number(exact_binding.generation) &&
                model->data(row, Model::MaximumWidthRole).toUInt() == width &&
                model->data(row, Model::MaximumHeightRole).toUInt() == height,
            "neutral fixture model row lost identity, role, or bounds");
    const auto key = model->data(row, Model::SurfaceKeyRole).toString();
    require(!key.isEmpty(), "neutral fixture model row had no surface key");
    return key;
  };
  const auto bar_key =
      assert_row(bar_model, "bar", Model::Role::Bar, 280, 64);
  const auto panel_key =
      assert_row(panel_model, "panel", Model::Role::Panel, 360, 720);
  const auto overlay_key = assert_row(overlay_model, "overlay",
                                      Model::Role::Overlay, 480, 320);
  require(bar_key != panel_key && bar_key != overlay_key &&
              panel_key != overlay_key &&
              bar_model->data(bar_model->index(0, 0),
                              Model::DefaultSectionRole)
                      .toString() == QStringLiteral("right"),
          "neutral fixture keys or bar placement were not distinct and exact");

  QQuickWindow window;
  window.resize(208, 64);
  window.show();
  require(qmlRegisterType<bridge::RemotePluginSurface>(
              "Omarchy.PluginHost", 1, 0, "RemotePluginSurface") >= 0,
          "neutral fixture could not register the real Remote surface type");
  QQmlEngine surface_engine;
  QQmlComponent remote_component(&surface_engine);
  remote_component.setData(
      "import QtQuick\nimport Omarchy.PluginHost 1.0\n"
      "Item { width: 64; height: 64; "
      "RemotePluginSurface { anchors.fill: parent } }\n",
      QUrl());
  require(remote_component.isReady(),
          "neutral fixture Remote surface component did not compile");
  std::array<std::unique_ptr<QObject>, 3> wrappers;
  std::array<bridge::RemotePluginSurface *, 3> remotes{};
  for (std::size_t index = 0; index < remotes.size(); ++index) {
    wrappers[index].reset(remote_component.create());
    auto *root = qobject_cast<QQuickItem *>(wrappers[index].get());
    remotes[index] =
        wrappers[index]->findChild<bridge::RemotePluginSurface *>();
    require(root && remotes[index],
            "neutral fixture omitted a QML-completed Remote surface");
    root->setX(static_cast<qreal>(index * 72));
    root->setParentItem(window.contentItem());
  }
  const std::array keys = {bar_key, panel_key, overlay_key};
  for (std::size_t index = 0; index < remotes.size(); ++index) {
    require(manager->attach(keys[index], remotes[index]),
            "neutral fixture surface did not attach through its trusted key");
    if (!awaitFor(std::chrono::seconds(5), [&] {
          return remotes[index]->connected() && remotes[index]->ready() &&
                 remotes[index]->frameSequence() > 0;
        })) {
      const auto after_attach =
          bridge::PluginManagerTestAccess::runtimeSlots(*manager);
      const auto state =
          after_attach.empty() ? 255 : after_attach.front().last_state;
      const auto error =
          after_attach.empty() ? 255 : after_attach.front().last_error;
      throw std::runtime_error(
          "neutral fixture surface did not complete sequential attachment: " +
          std::string(index == 0 ? "bar" : index == 1 ? "panel" : "overlay") +
          " connected=" + std::to_string(remotes[index]->connected()) +
          " ready=" + std::to_string(remotes[index]->ready()) +
          " sequence=" + std::to_string(remotes[index]->frameSequence()) +
          " inspection=" +
          remotes[index]->inspectionState().toStdString() +
          " state=" + std::to_string(state) +
          " error=" + std::to_string(error));
    }
  }
  if (!awaitFor(std::chrono::seconds(10), [&] {
        return std::ranges::all_of(remotes, [](const auto *remote) {
          return remote->connected() && remote->ready() &&
                 remote->frameSequence() > 0;
        });
      })) {
    std::string detail;
    for (const auto *remote : remotes)
      detail += " connected=" + std::to_string(remote->connected()) +
                " ready=" + std::to_string(remote->ready()) +
                " sequence=" + std::to_string(remote->frameSequence()) +
                " inspection=" + remote->inspectionState().toStdString();
    throw std::runtime_error(
        "neutral fixture surfaces did not render authenticated frames:" +
        detail);
  }
  const std::array<qulonglong, 3> expected_surface_ids = {1, 3, 2};
  for (std::size_t index = 0; index < remotes.size(); ++index)
    require(remotes[index]->surfaceId() == expected_surface_ids[index] &&
                remotes[index]->surfaceGeneration() ==
                    exact_binding.generation,
            "neutral fixture host and worker surface identity disagreed");

  const std::array expected = {QColor(QStringLiteral("#52677a")),
                               QColor(QStringLiteral("#7a6652")),
                               QColor(QStringLiteral("#647052"))};
  std::array<QColor, 3> actual;
  for (std::size_t index = 0; index < remotes.size(); ++index) {
    actual[index] = paintedFrame(*remotes[index]).pixelColor(32, 32);
    require(actual[index].alpha() == 255 && actual[index] == expected[index],
            "neutral fixture surface did not render its exact opaque pixel");
  }
  require(actual[0] != actual[1] && actual[0] != actual[2] &&
              actual[1] != actual[2],
          "neutral fixture surface frames were not visually distinct");

  const auto running_epoch =
      bridge::PluginManagerTestAccess::runtimeSlots(*manager).front().epoch;
  QString intent_source;
  QString intent_target;
  QString intent_generation;
  QString intent_input_sequence;
  QObject::connect(manager.get(), &bridge::PluginManager::toggleRequested,
                   [&](const QString &source, const QString &target,
                       const QString &generation, const QString &input_sequence) {
                     intent_source = source;
                     intent_target = target;
                     intent_generation = generation;
                     intent_input_sequence = input_sequence;
                   });
  require(bridge::PluginManagerTestAccess::routeTrustedPointer(
              *manager, plugin, running_epoch, bar_key, true),
          "neutral fixture trusted pointer press was not routed");
  require(awaitFor(std::chrono::seconds(5), [&] {
            bridge::PluginManagerTestAccess::drainRuntime(*manager);
            return !intent_target.isEmpty();
          }) &&
              intent_source == bar_key && intent_target == panel_key &&
              intent_generation == QString::number(exact_binding.generation) &&
              intent_input_sequence == QStringLiteral("1"),
          "neutral fixture trusted press did not publish its panel intent");
  require(bridge::PluginManagerTestAccess::routeTrustedPointer(
              *manager, plugin, running_epoch, bar_key, false),
          "neutral fixture trusted pointer release was not routed");

  require(await([&] { return pluginScopePaths(exact_binding).size() == 1; }),
          "neutral fixture did not occupy exactly one systemd sandbox scope");

  manager.reset();
  require(std::ranges::none_of(remotes, [](const auto *remote) {
            return remote->connected();
          }),
          "manager teardown left a neutral surface transport connected");
  require(awaitFor(std::chrono::seconds(5),
                   [&] { return pluginScopePaths(exact_binding).empty(); }),
          "manager teardown did not reap the sole neutral fixture worker");
}

void zero_surface_runtime_has_no_publication_authority() {
  if (std::getenv("OMARCHY_REQUIRE_PACKAGED_WORKER_TEST") == nullptr)
    return;
  constexpr std::string_view plugin = "org.example.sidecar-only";
  RuntimeFixture fixture;
  static_cast<void>(fixture.seedRuntime(
      plugin, "import QtQuick\nItem { objectName: \"no-surface\" }\n",
      "{\"required\": [], \"optional\": []}", false));
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
          "zero-surface runtime did not schedule preparation");
  std::thread preparation([&] { scheduler.runOne(); });
  preparation.join();
  const bool running = await([&] {
    bridge::PluginManagerTestAccess::drainRuntime(*manager);
    const auto observations =
        bridge::PluginManagerTestAccess::runtimeSlots(*manager);
    return observations.size() == 1 && observations.front().running;
  });
  if (!running) {
    const auto observation =
        bridge::PluginManagerTestAccess::runtimeSlots(*manager).front();
    throw std::runtime_error(
        "zero-surface startup failed: state=" +
        std::to_string(observation.last_state) +
        " error=" + std::to_string(observation.last_error) +
        " retry=" + std::to_string(observation.retry_wait));
  }
  const auto observation =
      bridge::PluginManagerTestAccess::runtimeSlots(*manager).front();
  bridge::RemotePluginSurface remote;
  require(manager->count() == 0 && !observation.has_endpoint_owner &&
              !manager->attach(QStringLiteral("anything"), &remote),
          "zero-surface runtime acquired model or endpoint authority");
}

void reentrant_publication_replacement_rechecks_exact_epoch() {
  if (std::getenv("OMARCHY_REQUIRE_PACKAGED_WORKER_TEST") == nullptr)
    return;
  constexpr std::string_view plugin = "org.example.reentrant";
  RuntimeFixture fixture;
  const auto first = fixture.seedRuntime(plugin, animatedRedQml);
  const auto replacement = fixture.stageRuntime(plugin, 2, animatedGreenQml);
  DeterministicJobs scheduler;
  auto manager = bridge::PluginManagerTestAccess::create();
  bridge::PluginManagerTestAccess::installRuntime(*manager,
                                                  fixture.bootstrap());
  bridge::PluginManagerTestAccess::setJobSubmitter(
      *manager, [&](auto kind, auto job) {
        return scheduler.submit(kind, std::move(job));
      });

  bool replacement_started_in_publication = false;
  bool replacement_scan_succeeded = false;
  QObject::connect(manager.get(), &bridge::PluginManager::surfacesChanged, [&] {
    if (replacement_started_in_publication || manager->count() != 1)
      return;
    replacement_started_in_publication = true;
    fixture.selectReplacement(replacement);
    replacement_scan_succeeded =
        bridge::PluginManagerTestAccess::scanRuntime(*manager);
    if (replacement_scan_succeeded)
      fixture.promoteRuntime(replacement, 2);
  });

  require(bridge::PluginManagerTestAccess::scanRuntime(*manager) &&
              scheduler.jobs.size() == 1,
          "reentrant replacement fixture did not schedule G1");
  const auto first_epoch =
      bridge::PluginManagerTestAccess::runtimeSlots(*manager).front().epoch;
  std::thread first_preparation([&] { scheduler.runOne(); });
  first_preparation.join();
  require(await([&] {
            bridge::PluginManagerTestAccess::drainRuntime(*manager);
            const auto observations =
                bridge::PluginManagerTestAccess::runtimeSlots(*manager);
            return replacement_started_in_publication &&
                   replacement_scan_succeeded && observations.size() == 1 &&
                   observations.front().epoch != first_epoch &&
                   scheduler.jobs.size() == 1;
          }) &&
              manager->count() == 0,
          "reentrant G1 publication did not leave only not-yet-ready G2");
  require(!bridge::PluginManagerTestAccess::deliverLifecycle(
              *manager, plugin, first_epoch,
              static_cast<std::uint8_t>(host::SessionState::running),
              static_cast<std::uint8_t>(host::SessionError::none)),
          "stale G1 readiness survived reentrant replacement");

  std::thread replacement_preparation([&] { scheduler.runOne(); });
  replacement_preparation.join();
  require(await([&] {
            bridge::PluginManagerTestAccess::drainRuntime(*manager);
            const auto observations =
                bridge::PluginManagerTestAccess::runtimeSlots(*manager);
            return observations.size() == 1 && observations.front().running &&
                   manager->count() == 1;
          }),
          "reentrant replacement did not publish exact G2 readiness");
  const auto row = manager->barSurfaces()->index(0, 0);
  require(
      manager->barSurfaces()
                  ->data(row, bridge::SurfaceProjectionModel::GenerationRole)
                  .toString() == QString::number(replacement.generation) &&
          replacement.generation != first.generation,
      "reentrant replacement published stale G1 surface identity");
}

void joined_runtimes_replace_and_render_without_cross_routing() {
  if (std::getenv("OMARCHY_REQUIRE_PACKAGED_WORKER_TEST") == nullptr)
    return;
  require(::access(
              std::string(omarchy::plugin_runtime::kPackagedWorkerPath).c_str(),
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
           observed(observations, plugin_a).running &&
           observed(observations, plugin_b).running && manager->count() == 2;
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
  require(manager->count() == 2,
          "two authenticated runtimes did not publish independently");

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
            return observed(observations, plugin_a).running &&
                   observed(observations, plugin_b).running &&
                   manager->count() == 2;
          }),
          "replacement A did not publish automatically alongside unchanged B");
  const auto replacement_a_key = barSurfaceKey(*manager, plugin_a);
  require(!replacement_a_key.isEmpty() && replacement_a_key != first_a_key &&
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
  require(remote_b->connected() && await([&] {
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
  require(fresh_sequence != 0 && await([&] {
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
  secure_bar_cannot_expand_the_host_bar();
  host_owned_settings_are_read_and_replaced_atomically();
  process_singleton_factory_is_exact_and_recoverable();
  concurrent_engines_have_one_process_winner();
  singleton_boundary_is_inert_and_not_configurable();
  private_projection_seam_preserves_fail_closed_boundary();
  manager_policy_is_fixed_and_fail_closed();
  last_good_reconciliation_and_stale_callback_are_fail_closed();
  bounded_mailbox_coalesces_and_recovers_without_backoff();
  mailbox_results_are_safe_across_replacement_and_destruction();
  lifecycle_mailbox_keeps_latest_exact_terminal_state();
  surface_intent_mailbox_is_bounded_thread_safe_and_inert_when_stale();
  surface_intent_mailbox_delivers_fifo_for_running_published_slot();
  blocked_replacement_preserves_independent_plugin();
  runtime_jobs_enter_off_ui_and_commit_on_ui_drain();
  manager_owns_permission_generation_replacement();
  permission_control_is_bounded_and_destruction_safe();
  controlled_mutations_settle_after_slot_loss();
  public_archive_install_is_closed_until_exact_consent();
  public_zero_permission_archive_activates_with_empty_decisions();
  concurrent_permission_fences_route_exactly();
  real_root_publishes_attaches_and_tears_down_exactly();
  zero_surface_runtime_has_no_publication_authority();
  reentrant_publication_replacement_rechecks_exact_epoch();
  joined_runtimes_replace_and_render_without_cross_routing();
}

void run_public_permission_lifecycle_test() {
  public_permission_lifecycle_is_closed_until_exact_consent();
}

void run_neutral_surfaces_real_bwrap_test() {
  neutral_surfaces_share_one_real_sandbox_and_teardown();
}

#include "PluginManager_test.moc"
