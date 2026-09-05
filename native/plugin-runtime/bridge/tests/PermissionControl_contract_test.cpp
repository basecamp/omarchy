#include "PermissionControl.h"
#include "PluginManager.h"

#include "authority_store.hpp"
#include "authority_store_test_access.hpp"
#include "capability_definition.hpp"
#include "omarchy/plugin_runtime/Version.h"
#include "revision_verifier_adapter.hpp"
#include "runtime_bootstrap.hpp"
#include "runtime_roots.hpp"
#include "runtime_roots_test_access.hpp"

#include <QCoreApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonValue>

#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

#include <algorithm>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <functional>
#include <ranges>
#include <stdexcept>
#include <string>
#include <string_view>
#include <thread>
#include <vector>

namespace {

namespace bridge = omarchy::plugin_runtime::bridge;
namespace channel = omarchy::plugin_runtime::channel;
namespace definitions = omarchy::plugins::definitions;
namespace host = omarchy::plugin_runtime::host_session;
namespace permissions = omarchy::plugins::permissions;
namespace policy = omarchy::plugin_runtime::policy;

void require(bool condition, std::string_view message) {
  if (!condition)
    throw std::runtime_error(std::string(message));
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

class Jobs final {
public:
  bool submit(bridge::PluginManagerTestAccess::TestJobKind kind,
              std::function<void()> job) {
    kinds.push_back(kind);
    jobs.push_back(std::move(job));
    return true;
  }

  void run(std::size_t index = 0) {
    require(index < jobs.size(), "permission contract job disappeared");
    auto job = std::move(jobs[index]);
    jobs.erase(jobs.begin() + static_cast<std::ptrdiff_t>(index));
    kinds.erase(kinds.begin() + static_cast<std::ptrdiff_t>(index));
    job();
  }

  std::vector<bridge::PluginManagerTestAccess::TestJobKind> kinds;
  std::vector<std::function<void()>> jobs;
};

definitions::CapabilityDefinition collisionDefinition() {
  definitions::CapabilityDefinition definition{
      .canonical_name = definitions::Name("write"),
      .authority_identity = definitions::Name("test.write-v1"),
      .enforcement_family = definitions::EnforcementFamily::cli_harness,
      .display_category_id = definitions::Name("test.contract"),
      .display_category_label = definitions::Label("Contract tests"),
      .scope_schema = definitions::ScopeSchema::exact_cli_profile,
      .title = definitions::Label("Run the contract harness"),
      .risk_text = definitions::Label("Exercises an inert test adapter"),
      .risk = definitions::RiskLevel::moderate,
      .revocation = definitions::RevocationPolicy::deny_new,
      .audit = {},
      .adapter = {.adapter_class = definitions::Name("contract-adapter"),
                  .contract_digest =
                      definitions::Digest(std::string(64, 'c')),
                  .abi_version = 1},
      .operations = {}};
  require(definition.operations.insert(
              {.name = definitions::Name("remove"),
               .label = definitions::Label("Remove through harness")}) &&
              definition.operations.insert(
                  {.name = definitions::Name("storage.private"),
                   .label = definitions::Label("Inspect private storage")}),
          "dynamic collision definition was invalid");
  return definition;
}

definitions::DynamicScopeRelation
compareScope(const definitions::CapabilityDefinition &, std::string_view left,
             std::string_view right, void *) noexcept {
  return left == right ? definitions::DynamicScopeRelation::equal
                       : definitions::DynamicScopeRelation::incomparable;
}

bool inertDispatch(const definitions::AuthorizedDynamicRequest &,
                   std::span<std::byte>, std::size_t &written,
                   void *) noexcept {
  written = 0;
  return true;
}

class RuntimeFixture final {
public:
  RuntimeFixture() {
    std::string pattern = "/tmp/omarchy-permission-contract.XXXXXX";
    const auto *created = ::mkdtemp(pattern.data());
    require(created, "permission contract fixture creation failed");
    root_ = created;
    require(::chmod(root_.c_str(), 0755) == 0,
            "permission contract fixture root mode failed");
    home_ = root_ / "home";
    create(home_, 0700);
    create(revisions(), 0700);
    create(activations(), 0700);
    create(authority(), 0700);
    create(state(), 0700);
    create(root_ / "usr/lib/omarchy/plugin-security" /
               std::string(omarchy::plugin_runtime::build_version()) /
               "capabilities.d",
           0755);

    auto registry = std::make_shared<definitions::TrustedDefinitionRegistry>();
    const auto definition = collisionDefinition();
    require(registry->install(
                definition, definitions::DefinitionSource::omarchy_package, 3),
            "dynamic collision definition was not installed");
    const auto installed = registry->find("write");
    require(installed.has_value(), "dynamic collision definition disappeared");
    definition_digest_ = std::string(installed->digest.view());
    registry_ = std::move(registry);
  }

  ~RuntimeFixture() {
    std::error_code ignored;
    std::filesystem::remove_all(root_, ignored);
  }

  void seed(std::string_view plugin, bool start_running = true) {
    const auto revision_name = std::string(plugin) + "-g1";
    const auto revision = revisions() / revision_name;
    create(revision / "ui", 0755);
    const std::string storage =
        "{\"capability\":\"storage.private\",\"reason\":\"builtin row\","
        "\"quotaBytes\":8192}";
    const std::string dynamic =
        "{\"capability\":\"write\",\"reason\":\"dynamic row\","
        "\"definitionGeneration\":3,\"definitionDigest\":\"" +
        definition_digest_ +
        "\",\"operations\":[\"remove\",\"storage.private\"],"
        "\"profile\":\"contract\"}";
    const auto permissions_json =
        start_running
            ? "{\"required\":[],\"optional\":[" + storage + ',' + dynamic + "]}"
            : "{\"required\":[" + storage + "],\"optional\":[" + dynamic + "]}";
    {
      std::ofstream manifest(revision / "manifest.json");
      manifest << "{\"schemaVersion\":2,\"id\":\"" << plugin
               << "\",\"name\":\"Permission contract\",\"version\":\"1\","
                  "\"runtime\":{\"apiVersion\":1,\"qml\":\"ui/Main.qml\"},"
                  "\"surfaces\":{},\"permissions\":"
               << permissions_json << "}";
    }
    std::ofstream(revision / "ui/Main.qml") << "import QtQuick\nItem {}\n";
    for (const auto &entry :
         std::filesystem::recursive_directory_iterator(revision))
      require(::chmod(entry.path().c_str(),
                      entry.is_directory() ? 0555 : 0444) == 0,
              "permission contract revision mode failed");
    require(::chmod(revision.c_str(), 0555) == 0,
            "permission contract revision root mode failed");
    create(state() / std::string(plugin), 0700);
    create(authority() / std::string(plugin), 0700);

    const int revision_fd = ::open(
        revision.c_str(), O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
    require(revision_fd >= 0, "permission contract revision open failed");
    host::SourceRevisionVerifier verifier;
    auto verified = verifier.verify_open_revision(revision_fd);
    ::close(revision_fd);
    require(verified && verified->manifest.id == plugin,
            "permission contract revision verification failed");

    policy::GrantSnapshot snapshot;
    snapshot.requests = permissions::requests_from_manifest(verified->manifest);
    snapshot.binding = {
        .plugin = permissions::PluginId(plugin),
        .revision = permissions::Digest(verified->tree_sha256),
        .policy_fingerprint = permissions::Digest(
            permissions::policy_request_fingerprint(snapshot.requests)),
        .generation = 1};
    snapshot.source_request_fingerprint =
        permissions::Digest(verified->request_sha256);
    for (const auto &request : snapshot.requests.values())
      snapshot.grants.push_back({.capability = request.capability,
                                 .scope = request.scope,
                                 .state = permissions::GrantState::granted,
                                 .epoch = 1});
    for (const auto &manifest_request : verified->manifest.requests) {
      auto request = definitions::dynamic_request_from_manifest(
          manifest_request, *registry_);
      if (!request)
        continue;
      definitions::DynamicGrant grant{.definition = request->definition,
                                      .operations = request->operations,
                                      .scope = request->scope,
                                      .state = permissions::GrantState::granted,
                                      .epoch = 1};
      snapshot.dynamic_grants.push_back({.binding = snapshot.binding,
                                         .request = std::move(*request),
                                         .grant = std::move(grant)});
    }
    require(snapshot.requests.size() == 1 &&
                snapshot.dynamic_grants.size() == 1,
            "builtin and dynamic rows did not remain distinct");

    const int authority_fd =
        ::open((authority() / std::string(plugin)).c_str(),
               O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
    require(authority_fd >= 0, "permission contract authority open failed");
    auto store = host::AuthorityStore::open(authority_fd, ::getuid(),
                                            permissions::PluginId(plugin));
    ::close(authority_fd);
    require(store &&
                store->publish_candidate(*verified, snapshot, 0, *registry_,
                                         {.compare = compareScope}) ==
                    host::AuthorityMutationResult::applied &&
                store->promote_candidate(snapshot.binding, 1) ==
                    host::AuthorityMutationResult::applied,
            "permission contract authority activation failed");
    if (!start_running) {
      const auto view = store->read_authority_view();
      require(view && view->active && snapshot.requests.size() == 1 &&
                  host::AuthorityStoreTestAccess::revoke_active(
                      *store, snapshot.requests.values().front().capability,
                      view->authority_slots.sequence)
                          .status == host::AuthorityMutationResult::applied,
              "permission contract disabled authority setup failed");
    }
    writeActivation(plugin, revision_name, verified->tree_sha256);
  }

  std::unique_ptr<channel::RuntimeBootstrap>
  bootstrap(bool dynamic_provider = true) const {
    const int home =
        ::open(home_.c_str(), O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
    require(home >= 0, "permission contract home unavailable");
    channel::RuntimeRootsError roots_error{};
    auto roots = channel::RuntimeRootsTestAccess::open_from_home_fd(
        home, static_cast<std::uint32_t>(::getuid()), roots_error);
    ::close(home);
    require(roots && roots_error == channel::RuntimeRootsError::none,
            "permission contract roots rejected");
    auto services = std::make_shared<channel::RuntimeServices>();
    services->context = std::make_shared<int>(0);
    services->compare_scope = compareScope;
    if (dynamic_provider) {
      services->dynamic_services.push_back(
          {.binding = collisionDefinition().adapter,
           .dispatch = inertDispatch});
    }
    return channel::RuntimeBootstrapTestAccess::compose_with_context(
        std::move(roots), registry_, std::move(services));
  }

private:
  std::filesystem::path revisions() const {
    return home_ / ".local/share/omarchy-plugin-security/v2/revisions";
  }
  std::filesystem::path activations() const {
    return home_ / ".local/state/omarchy/plugin-security/v2/activations";
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
      const bool made = std::filesystem::create_directory(current);
      if (made || current == path)
        require(::chmod(current.c_str(), current == path ? leaf_mode : 0755) ==
                    0,
                "permission contract directory mode failed");
    }
  }

  void writeActivation(std::string_view plugin, std::string_view revision,
                       std::string_view digest) {
    const auto path = activations() / std::string(plugin);
    {
      std::ofstream output(path);
      output << "format=omarchy-plugin-activation-v2\nplugin=" << plugin
             << "\nrevision-directory=" << revision
             << "\nrevision-sha256=" << digest << "\nstate-directory=" << plugin
             << "\n";
    }
    require(::chmod(path.c_str(), 0600) == 0,
            "permission contract activation mode failed");
  }

  std::filesystem::path root_;
  std::filesystem::path home_;
  std::shared_ptr<const definitions::TrustedDefinitionRegistry> registry_;
  std::string definition_digest_;
};

QJsonObject poll(bridge::PermissionControl &control, const QString &id) {
  const auto document = QJsonDocument::fromJson(control.poll(id).toUtf8());
  require(document.isObject(), "permission control returned invalid JSON");
  return document.object();
}

void runPermission(Jobs &jobs, bridge::PluginManager &manager) {
  require(!jobs.jobs.empty() &&
              jobs.kinds.front() ==
                  bridge::PluginManagerTestAccess::TestJobKind::permission,
          "expected permission job was not queued");
  jobs.run();
  bridge::PluginManagerTestAccess::drainRuntime(manager);
}

QJsonArray rows(const QJsonObject &operation) {
  require(operation.value("state") == "succeeded" &&
              operation.value("result").isObject(),
          "permission read did not succeed");
  return operation.value("result").toObject().value("permissions").toArray();
}

QJsonObject rowNamed(const QJsonArray &values, std::string_view name) {
  const auto expected = QString::fromUtf8(name);
  for (const auto &value : values) {
    const auto row = value.toObject();
    if (row.value("name") == expected)
      return row;
  }
  return {};
}

QJsonObject choice(const QJsonObject &row, bool grant,
                   QJsonArray operations = {}) {
  QJsonObject result{{"rowId", row.value("rowId")},
                     {"decision", grant ? "grant" : "deny"}};
  if (row.value("kind") == "dynamic" && grant)
    result.insert("operations", operations);
  return result;
}

QString choices(const QJsonObject &builtin, const QJsonObject &dynamic,
                const QJsonArray &operations) {
  return QString::fromUtf8(
      QJsonDocument(QJsonObject{{"choices", QJsonArray{choice(builtin, true),
                                                       choice(dynamic, true,
                                                              operations)}}})
          .toJson(QJsonDocument::Compact));
}

void requireKeys(const QJsonObject &object,
                 std::initializer_list<std::string_view> expected,
                 std::string_view context) {
  std::vector<std::string> actual;
  for (auto it = object.begin(); it != object.end(); ++it)
    actual.push_back(it.key().toStdString());
  std::vector<std::string> wanted;
  for (const auto key : expected)
    wanted.emplace_back(key);
  std::ranges::sort(actual);
  std::ranges::sort(wanted);
  require(actual == wanted, std::string(context) + " JSON keys changed");
}

void requireNoAuthorityMetadata(const QJsonValue &value) {
  constexpr std::string_view forbidden[] = {"epoch",
                                            "sequence",
                                            "fingerprint",
                                            "version",
                                            "definitionGeneration",
                                            "definitionDigest",
                                            "adapter",
                                            "actor",
                                            "confirmedWallSeconds",
                                            "slotEpoch",
                                            "authoritySequence",
                                            "binding",
                                            "generation"};
  if (value.isArray()) {
    for (const auto &entry : value.toArray())
      requireNoAuthorityMetadata(entry);
    return;
  }
  if (!value.isObject())
    return;
  const auto object = value.toObject();
  for (auto it = object.begin(); it != object.end(); ++it) {
    require(std::ranges::find(forbidden, it.key().toStdString()) ==
                std::end(forbidden),
            "permission JSON exposed authority metadata");
    requireNoAuthorityMetadata(it.value());
  }
}

void publicPermissionContract() {
  constexpr std::string_view plugin_a = "a.permission-contract";
  constexpr std::string_view plugin_b = "b.permission-contract";
  RuntimeFixture fixture;
  fixture.seed(plugin_a);
  fixture.seed(plugin_b);
  Jobs jobs;
  auto manager = bridge::PluginManagerTestAccess::create();
  bridge::PluginManagerTestAccess::installRuntime(*manager,
                                                  fixture.bootstrap());
  bridge::PluginManagerTestAccess::setJobSubmitter(
      *manager,
      [&](auto kind, auto job) { return jobs.submit(kind, std::move(job)); });
  require(bridge::PluginManagerTestAccess::scanRuntime(*manager) &&
              jobs.jobs.size() == 2,
          "permission contract runtimes did not queue preparation");
  while (!jobs.jobs.empty()) {
    jobs.run();
    bridge::PluginManagerTestAccess::drainRuntime(*manager);
  }
  const bool both_running = await([&] {
    bridge::PluginManagerTestAccess::drainRuntime(*manager);
    const auto observations =
        bridge::PluginManagerTestAccess::runtimeSlots(*manager);
    return observations.size() == 2 &&
           std::ranges::all_of(observations,
                               [](const auto &slot) { return slot.running; });
  });
  if (!both_running) {
    const auto observations =
        bridge::PluginManagerTestAccess::runtimeSlots(*manager);
    std::string detail = "permission contract runtimes did not reach running";
    for (const auto &entry : observations)
      detail += " [" + entry.plugin +
                " opening=" + std::to_string(entry.opening) +
                " preparing=" + std::to_string(entry.preparing) +
                " starting=" + std::to_string(entry.starting) +
                " retry=" + std::to_string(entry.retry_wait) +
                " state=" + std::to_string(entry.last_state) +
                " error=" + std::to_string(entry.last_error) + "]";
    throw std::runtime_error(detail);
  }

  auto &control = *manager->permissions();
  const auto pending_id = control.beginReview(QString::fromUtf8(plugin_a));
  require(!pending_id.isEmpty(), "public review did not queue");
  const auto pending = poll(control, pending_id);
  requireKeys(pending, {"operationId", "kind", "state"}, "pending operation");
  requireNoAuthorityMetadata(pending);
  runPermission(jobs, *manager);
  const auto review_a = poll(control, pending_id);
  requireKeys(review_a, {"operationId", "kind", "state", "result"},
              "successful review");
  requireKeys(review_a.value("result").toObject(), {"plugin", "permissions"},
              "review result");
  requireNoAuthorityMetadata(review_a);
  const auto review_rows_a = rows(review_a);
  const auto builtin_a = rowNamed(review_rows_a, "storage.private");
  const auto dynamic_a = rowNamed(review_rows_a, "write");
  require(!builtin_a.isEmpty() && !dynamic_a.isEmpty() &&
              builtin_a.value("kind") == "builtin" &&
              dynamic_a.value("kind") == "dynamic",
          "builtin and dynamic name namespaces collided");
  requireKeys(builtin_a,
              {"rowId", "kind", "name", "required", "available", "state",
               "scope", "operations", "delta", "reason"},
              "builtin review row");
  requireKeys(dynamic_a,
              {"rowId", "kind", "name", "required", "available", "state",
               "scope", "operations", "title", "category", "delta", "reason"},
              "dynamic review row");
  const auto operation_rows = dynamic_a.value("operations").toArray();
  require(operation_rows.size() == 2,
          "dynamic review did not expose requested operation breadth");
  for (const auto &value : operation_rows)
    requireKeys(value.toObject(), {"operationId", "name", "label"},
                "dynamic operation");

  QString chosen_id;
  QString foreign_operation_id;
  for (const auto &value : operation_rows) {
    const auto operation = value.toObject();
    if (operation.value("name") == "storage.private")
      chosen_id = operation.value("operationId").toString();
    else
      foreign_operation_id = operation.value("operationId").toString();
  }
  require(!chosen_id.isEmpty() && !foreign_operation_id.isEmpty() &&
              chosen_id != "storage.private",
          "dynamic operation was not represented by an opaque selector");
  const QJsonArray chosen_only{QJsonValue(chosen_id)};
  const QJsonArray chosen_duplicate{QJsonValue(chosen_id),
                                    QJsonValue(chosen_id)};

  const auto review_b_id = control.beginReview(QString::fromUtf8(plugin_b));
  require(!review_b_id.isEmpty(), "plugin B review did not queue");
  runPermission(jobs, *manager);
  const auto review_b = poll(control, review_b_id);
  const auto review_rows_b = rows(review_b);
  const auto builtin_b = rowNamed(review_rows_b, "storage.private");
  const auto dynamic_b = rowNamed(review_rows_b, "write");
  const auto operation_b = dynamic_b.value("operations")
                               .toArray()
                               .at(0)
                               .toObject()
                               .value("operationId")
                               .toString();
  const QJsonArray operation_b_only{QJsonValue(operation_b)};
  require(
      control.revoke(pending_id, builtin_b.value("rowId").toString())
              .isEmpty() &&
          control.revoke(review_b_id, builtin_a.value("rowId").toString())
              .isEmpty() &&
          control
              .apply(review_b_id, choices(builtin_a, dynamic_a,
                                          QJsonArray{QJsonValue(chosen_id)}))
              .isEmpty(),
      "plugin row IDs crossed exact review ownership");

  const auto badChoices = [&](const QJsonArray &selected) {
    return choices(builtin_a, dynamic_a, selected);
  };
  require(
      control.apply(pending_id, badChoices(QJsonArray{"storage.private"}))
              .isEmpty() &&
          control.apply(pending_id, badChoices(QJsonArray{"foreign"}))
              .isEmpty() &&
          control.apply(pending_id, badChoices(chosen_duplicate)).isEmpty() &&
          control.apply(pending_id, badChoices(operation_b_only)).isEmpty() &&
          control
              .apply(
                  pending_id,
                  QString::fromUtf8(
                      QJsonDocument(
                          QJsonObject{
                              {"choices",
                               QJsonArray{
                                   choice(builtin_a, true),
                                   choice(dynamic_a, true, chosen_only),
                                   choice(dynamic_b, true, operation_b_only)}}})
                          .toJson(QJsonDocument::Compact)))
              .isEmpty(),
      "raw, foreign, duplicate, cross-row, or plugin-B selectors applied");

  const auto cli_review =
      control.beginInteractiveCliReview(QString::fromUtf8(plugin_b));
  require(!cli_review.isEmpty(), "CLI review did not queue");
  runPermission(jobs, *manager);
  const auto cli_rows = rows(poll(control, cli_review));
  const auto cli_builtin = rowNamed(cli_rows, "storage.private");
  const auto cli_dynamic = rowNamed(cli_rows, "write");
  QJsonArray cli_operations;
  for (const auto &value : cli_dynamic.value("operations").toArray())
    cli_operations.push_back(value.toObject().value("operationId"));
  const auto cli_choices = choices(cli_builtin, cli_dynamic, cli_operations);
  QJsonArray all_a_operations;
  for (const auto &value : operation_rows)
    all_a_operations.push_back(value.toObject().value("operationId"));
  require(control.apply(cli_review, cli_choices).isEmpty() &&
              control
                  .applyInteractiveCli(pending_id, choices(builtin_a, dynamic_a,
                                                           all_a_operations))
                  .isEmpty(),
          "trusted UI and interactive CLI ingress crossed");

  const auto apply_id =
      control.apply(pending_id, choices(builtin_a, dynamic_a, chosen_only));
  require(
      !apply_id.isEmpty() &&
          control.apply(pending_id, choices(builtin_a, dynamic_a, chosen_only))
              .isEmpty() &&
          control.revoke(pending_id, builtin_a.value("rowId").toString())
              .isEmpty(),
      "consumed review ID was replayable");
  runPermission(jobs, *manager);
  const auto applied = poll(control, apply_id);
  requireKeys(applied, {"operationId", "kind", "state", "result"},
              "successful apply");
  requireKeys(applied.value("result").toObject(), {"applied"}, "apply result");
  require(applied.value("state") == "succeeded" &&
              applied.value("result").toObject().value("applied") == true,
          "opaque dynamic subset did not apply");
  requireNoAuthorityMetadata(applied);

  require(!jobs.jobs.empty() &&
              jobs.kinds.front() ==
                  bridge::PluginManagerTestAccess::TestJobKind::preparation,
          "permission apply did not queue exact generation preparation");
  jobs.run();
  bridge::PluginManagerTestAccess::drainRuntime(*manager);
  require(await([&] {
            bridge::PluginManagerTestAccess::drainRuntime(*manager);
            const auto observations =
                bridge::PluginManagerTestAccess::runtimeSlots(*manager);
            return std::ranges::any_of(observations, [](const auto &slot) {
              return slot.plugin == plugin_a && slot.running;
            });
          }),
          "narrowed generation did not return to running");

  const auto effective_id = control.beginList(QString::fromUtf8(plugin_a));
  require(!effective_id.isEmpty(), "effective list did not queue");
  runPermission(jobs, *manager);
  const auto effective = poll(control, effective_id);
  const auto effective_dynamic = rowNamed(rows(effective), "write");
  requireKeys(effective_dynamic,
              {"rowId", "kind", "name", "required", "available", "state",
               "scope", "operations"},
              "dynamic effective row");
  require(effective_dynamic.value("operations").toArray() ==
              QJsonArray{"storage.private"},
          "effective list exposed requested rather than narrowed operations");
  requireNoAuthorityMetadata(effective);

  const auto requested_id = control.beginReview(QString::fromUtf8(plugin_a));
  require(!requested_id.isEmpty(), "post-narrowing review did not queue");
  runPermission(jobs, *manager);
  const auto requested = poll(control, requested_id);
  const auto requested_dynamic = rowNamed(rows(requested), "write");
  require(requested_dynamic.value("operations").toArray().size() == 2,
          "review stopped presenting requested operation breadth");
  requireNoAuthorityMetadata(requested);
  QString requested_chosen_id;
  for (const auto &value : requested_dynamic.value("operations").toArray()) {
    const auto operation = value.toObject();
    if (operation.value("name") == "storage.private")
      requested_chosen_id = operation.value("operationId").toString();
  }
  require(!requested_chosen_id.isEmpty(),
          "post-narrowing review lost its exact operation selector");

  const auto revoke_id = control.revoke(
      effective_id,
      rowNamed(rows(effective), "storage.private").value("rowId").toString());
  require(!revoke_id.isEmpty(), "public revoke did not queue");
  runPermission(jobs, *manager);
  require(poll(control, revoke_id).value("state") == "succeeded" &&
              control
                  .apply(requested_id,
                         choices(rowNamed(rows(requested), "storage.private"),
                                 requested_dynamic,
                                 QJsonArray{QJsonValue(requested_chosen_id)}))
                  .isEmpty(),
          "stale exact review ID survived a public authority mutation");
}

void unavailableProviderReviewContract() {
  constexpr std::string_view plugin = "unavailable.permission-contract";
  RuntimeFixture fixture;
  fixture.seed(plugin, false);
  Jobs jobs;
  auto manager = bridge::PluginManagerTestAccess::create();
  bridge::PluginManagerTestAccess::installRuntime(*manager,
                                                  fixture.bootstrap(false));
  bridge::PluginManagerTestAccess::setJobSubmitter(
      *manager,
      [&](auto kind, auto job) { return jobs.submit(kind, std::move(job)); });
  require(bridge::PluginManagerTestAccess::scanRuntime(*manager) &&
              jobs.jobs.size() == 1,
          "missing-provider activation did not queue exact preparation");
  jobs.run();
  bridge::PluginManagerTestAccess::drainRuntime(*manager);
  const auto initial = bridge::PluginManagerTestAccess::runtimeSlots(*manager);
  if (initial.size() != 1 || !initial.front().permission_disabled) {
    std::string detail =
        "permission-disabled authority did not retain a reviewable slot";
    for (const auto &entry : initial)
      detail += " [preparing=" + std::to_string(entry.preparing) +
                " retry=" + std::to_string(entry.retry_wait) +
                " state=" + std::to_string(entry.last_state) +
                " error=" + std::to_string(entry.last_error) + "]";
    throw std::runtime_error(detail);
  }

  auto &control = *manager->permissions();
  const auto review_id = control.beginReview(QString::fromUtf8(plugin));
  require(!review_id.isEmpty(),
          "missing-provider definition was not reviewable");
  runPermission(jobs, *manager);
  const auto review_rows = rows(poll(control, review_id));
  const auto builtin = rowNamed(review_rows, "storage.private");
  const auto dynamic = rowNamed(review_rows, "write");
  require(!builtin.isEmpty() && !dynamic.isEmpty() &&
              dynamic.value("state") == "granted" &&
              dynamic.value("available") == false,
          "review did not separate durable grant from provider availability");
  QJsonArray dynamic_operations;
  for (const auto &value : dynamic.value("operations").toArray())
    dynamic_operations.push_back(value.toObject().value("operationId"));
  require(
      control.apply(review_id, choices(builtin, dynamic, dynamic_operations))
          .isEmpty(),
      "review granted an unavailable provider");
  const auto deny_choices = QString::fromUtf8(
      QJsonDocument(
          QJsonObject{{"choices", QJsonArray{choice(builtin, true),
                                             choice(dynamic, false)}}})
          .toJson(QJsonDocument::Compact));
  const auto apply_id = control.apply(review_id, deny_choices);
  require(!apply_id.isEmpty(),
          "optional unavailable permission could not be explicitly denied");
  runPermission(jobs, *manager);
  require(poll(control, apply_id).value("state") == "succeeded" &&
              jobs.jobs.size() == 1,
          "optional denial did not publish one exact authority generation");
  const auto promoted = bridge::PluginManagerTestAccess::runtimeSlots(*manager);
  require(promoted.size() == 1 && promoted.front().preparing,
          "optional denial did not queue exact degraded preparation");
  const auto authority = bridge::PluginManagerTestAccess::permissionView(
      *manager, plugin, promoted.front().epoch);
  require(authority && authority->active &&
              authority->active->dynamic_grants.size() == 1 &&
              authority->active->dynamic_grants.front().grant.state ==
                  permissions::GrantState::denied,
          "optional unavailable denial did not persist exact authority");
}

} // namespace

int main(int argc, char **argv) {
  QCoreApplication application(argc, argv);
  try {
    unavailableProviderReviewContract();
    if (std::getenv("OMARCHY_REQUIRE_PACKAGED_WORKER_TEST") != nullptr)
      publicPermissionContract();
  } catch (const std::exception &error) {
    std::fprintf(stderr, "permission control contract test failed: %s\n",
                 error.what());
    return 1;
  }
  return 0;
}
