#include "PluginManager.h"

#include "omarchy/plugin_runtime/Version.h"
#include "runtime_bootstrap.hpp"
#include "runtime_roots.hpp"
#include "remote_surface.hpp"

#include <QCoreApplication>
#include <QMetaMethod>
#include <QQmlEngine>

#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

#include <algorithm>
#include <atomic>
#include <barrier>
#include <chrono>
#include <condition_variable>
#include <filesystem>
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
  std::filesystem::path activations() const {
    return home_ / ".local/state/omarchy/plugin-security/v2/activations";
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
  require(bridge::PluginManagerTestAccess::publishSurfaces(
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
        bridge::PluginManagerTestAccess::withdrawSurfaces(manager, exact);
  });
  worker.join();
  require(
      !off_thread && manager.count() == 1 &&
          bridge::PluginManagerTestAccess::withdrawSurfaces(manager, exact) &&
          manager.count() == 0 && changes == 2,
      "projection seam escaped UI-thread or exact-binding confinement");
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

} // namespace

void run_plugin_manager_tests() {
  process_singleton_factory_is_exact_and_recoverable();
  concurrent_engines_have_one_process_winner();
  singleton_boundary_is_inert_and_not_configurable();
  private_projection_seam_preserves_fail_closed_boundary();
  last_good_reconciliation_and_stale_callback_are_fail_closed();
  bounded_mailbox_coalesces_and_recovers_without_backoff();
  mailbox_results_are_safe_across_replacement_and_destruction();
  lifecycle_mailbox_keeps_latest_exact_terminal_state();
  blocked_replacement_preserves_independent_plugin();
  runtime_jobs_enter_off_ui_and_commit_on_ui_drain();
}
