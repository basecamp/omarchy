#include "authenticated_channel.hpp"
#include "broker_runtime.hpp"

#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

#include <chrono>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <memory>
#include <string_view>

namespace action = omarchy::plugin_runtime::channel;
namespace audit = omarchy::plugins::audit;
namespace broker = omarchy::plugin_runtime::broker;
namespace grant = omarchy::plugins::grants;
namespace launcher = omarchy::plugin_runtime::launcher;
namespace permissions = omarchy::plugins::permissions;
namespace providers = omarchy::plugin_runtime::providers;
namespace runtime = omarchy::plugin_runtime::runtime;
namespace sandbox = omarchy::plugin_runtime::sandbox;

namespace {
using namespace std::chrono_literals;
void require(bool condition, std::string_view message) {
  if (!condition)
    throw std::runtime_error(std::string(message));
}

class Fd {
public:
  explicit Fd(int value = -1) : value_(value) {}
  ~Fd() {
    if (value_ >= 0)
      close(value_);
  }
  Fd(const Fd &) = delete;
  Fd &operator=(const Fd &) = delete;
  int get() const { return value_; }

private:
  int value_;
};

class Temp {
public:
  Temp() {
    std::string pattern = "/tmp/omarchy-e3-XXXXXX";
    const char *created = mkdtemp(pattern.data());
    require(created != nullptr, "mkdtemp failed");
    path_ = created;
  }
  ~Temp() {
    std::error_code ignored;
    std::filesystem::remove_all(path_, ignored);
  }
  const std::filesystem::path &path() const { return path_; }

private:
  std::filesystem::path path_;
};

class Scope final : public launcher::ResourceScopeController {
public:
  bool probe(std::string &) override { return true; }
  bool attach(std::string_view unit, pid_t monitor, pid_t worker,
              const sandbox::SandboxPlan &, std::chrono::milliseconds,
              std::string &) override {
    require(monitor > 0 && worker > 0, "invalid scope identities");
    name = unit;
    return true;
  }
  void kill(std::string_view) noexcept override {}
  void remove(std::string_view unit) noexcept override {
    if (unit == name)
      ++removes;
  }
  std::string name;
  unsigned removes = 0;
};

permissions::Digest digest(char value) {
  return permissions::Digest(std::string(64, value));
}
permissions::CapabilityKey key(std::string_view id) {
  return {permissions::CapabilityId(id), 1};
}
permissions::QuotaScope quota() { return {4096, 1024}; }
permissions::TokenScope token() {
  permissions::TokenScope value;
  require(value.tokens.insert(permissions::ScopeToken("timer")), "token");
  return value;
}

grant::RevisionGrants revision() {
  grant::RevisionGrants value;
  value.binding.plugin = permissions::PluginId("org.example.secure");
  value.binding.revision = digest('a');
  value.binding.generation = 11;
  value.source_request_fingerprint = digest('c');
  value.requests.push_back({key("storage.private"), quota(), true});
  value.requests.push_back({key("notifications.send"), token(), false});
  value.grants.push_back(
      {key("storage.private"), quota(), permissions::GrantState::granted, 4});
  value.grants.push_back(
      {key("notifications.send"), token(), permissions::GrantState::denied, 2});
  value.binding.policy_fingerprint = permissions::Digest(
      permissions::policy_request_fingerprint(value.requests));
  return value;
}

struct Backend {
  static bool write(std::string_view key_name, std::span<const std::byte> value,
                    void *opaque) noexcept {
    auto &self = *static_cast<Backend *>(opaque);
    const auto records = self.store->query({});
    static const std::string revision_digest(64, 'a');
    self.audited_before_effect =
        records.status.ok() && !records.records.empty() &&
        records.records.back().event ==
            permissions::AuditEvent::operation_decided &&
        records.records.back().outcome == permissions::AuditOutcome::allowed &&
        records.records.back().plugin.view() == "org.example.secure" &&
        records.records.back().revision.view() == revision_digest &&
        records.records.back().generation == 11;
    ++self.writes;
    self.value.assign(reinterpret_cast<const char *>(value.data()),
                      value.size());
    self.key.assign(key_name);
    return true;
  }
  static bool notify(std::string_view, std::string_view, std::string_view,
                     void *opaque) noexcept {
    ++static_cast<Backend *>(opaque)->notifications;
    return true;
  }
  audit::AuditStore *store;
  unsigned writes = 0;
  unsigned notifications = 0;
  bool audited_before_effect = false;
  std::string key;
  std::string value;
};

providers::ProviderConfiguration configuration(Backend &backend) {
  providers::ProviderConfiguration value;
  value.storage.write = Backend::write;
  value.storage.context = &backend;
  value.storage.maximum_total_bytes = 4096;
  value.storage.maximum_item_bytes = 1024;
  value.notification.send = Backend::notify;
  value.notification.context = &backend;
  return value;
}

class Authority final : public action::GenerationAuthority {
public:
  bool
  is_current(const launcher::LaunchIdentity &identity) const noexcept override {
    return identity.plugin_id == "org.example.secure" &&
           identity.revision_sha256 == std::string(64, 'a') &&
           identity.generation == 11;
  }
};

class Dispatcher final : public action::BrokerDispatcher {
public:
  explicit Dispatcher(runtime::AuditedBrokerRuntime &value) : runtime(value) {}
  bool dispatch(const omarchy::plugin::wire::PacketView &packet) override {
    result = runtime.dispatch(packet, 100);
    return result.outcome == broker::DispatchOutcome::dispatched ||
           result.outcome == broker::DispatchOutcome::denied;
  }
  runtime::AuditedBrokerRuntime &runtime;
  broker::DispatchResult result;
};

class Fixture {
public:
  Fixture(Temp &temp, std::string_view mode)
      : revision_(temp.path() / "revision"), state_(temp.path() / "state") {
    std::filesystem::create_directories(revision_);
    std::filesystem::create_directories(state_);
    std::ofstream(revision_ / "d1-mode") << mode << '\n';
    std::ofstream(revision_ / "Main.qml")
        << "import QtQml\nQtObject { readonly property string action: \""
        << (mode == "denied" ? "notification.send" : "storage.write")
        << "\"; readonly property string value: \"from-qml\" }\n";
    chmod((revision_ / "d1-mode").c_str(), 0444);
    chmod((revision_ / "Main.qml").c_str(), 0444);
    require(chmod(revision_.c_str(), 0555) == 0, "immutable revision failed");
    revision_fd = std::make_unique<Fd>(
        open(revision_.c_str(), O_RDONLY | O_DIRECTORY | O_CLOEXEC));
    state_fd = std::make_unique<Fd>(
        open(state_.c_str(), O_RDONLY | O_DIRECTORY | O_CLOEXEC));
    require(revision_fd->get() >= 0 && state_fd->get() >= 0,
            "fixture fd failed");
  }
  ~Fixture() { chmod(revision_.c_str(), 0755); }
  launcher::TrustedLaunchRequest request() const {
    return {.plugin_id = "org.example.secure",
            .revision_sha256 = std::string(64, 'a'),
            .generation = 11,
            .revision_directory_fd = revision_fd->get(),
            .private_state_directory_fd = state_fd->get()};
  }

private:
  std::filesystem::path revision_, state_;
  std::unique_ptr<Fd> revision_fd, state_fd;
};

permissions::HandleId handle() {
  permissions::HandleId id;
  id.bytes.fill(std::byte{'h'});
  return id;
}

void run_case(std::string_view mode, broker::DispatchOutcome expected,
              bool poison_audit, std::string_view bwrap) {
  Temp temp;
  Fixture fixture(temp, mode);
  audit::AuditStore store(temp.path() / "audit", {.maximum_records = 64});
  Backend backend{.store = &store,
                  .writes = 0,
                  .notifications = 0,
                  .audited_before_effect = false,
                  .key = {},
                  .value = {}};
  auto grants = revision();
  runtime::AuditedBrokerRuntime audited(grants, configuration(backend), store);
  auto dispatcher = std::make_shared<Dispatcher>(audited);
  auto scope = std::make_shared<Scope>();
  auto authority = std::make_shared<Authority>();
  auto supervisor = launcher::Supervisor::forTestOnly(
      std::string(bwrap), QML_ACTION_PEER_PATH, scope);
  auto opened = action::AuthenticatedBrokerChannel::open(
      supervisor, fixture.request(), dispatcher, authority);
  require(opened && opened.channel->negotiate(2s),
          "authenticated QML peer failed negotiation");
  if (poison_audit) {
    require(store.recover().ok(), "audit setup failed");
    std::filesystem::permissions(temp.path() / "audit",
                                 std::filesystem::perms::owner_read |
                                     std::filesystem::perms::owner_exec,
                                 std::filesystem::perm_options::replace);
  }
  const auto status = opened.channel->dispatch_one(2s);
  require(dispatcher->result.outcome == expected, "unexpected D4 outcome");
  if (poison_audit) {
    require(status == action::DispatchStatus::fatal && backend.writes == 0 &&
                scope->removes == 1,
            "audit failure escaped teardown containment");
    std::filesystem::permissions(temp.path() / "audit",
                                 std::filesystem::perms::owner_all,
                                 std::filesystem::perm_options::replace);
    return;
  }
  require(status == action::DispatchStatus::dispatched,
          "recoverable D4 outcome killed channel");
  if (mode == "denied") {
    require(backend.notifications == 0 && backend.writes == 0,
            "denied QML action had an effect");
    const auto records = store.query({});
    require(records.status.ok() && !records.records.empty() &&
                records.records.back().outcome ==
                    permissions::AuditOutcome::denied &&
                records.records.back().correlation == 42 &&
                records.records.back().generation == 11,
            "denied QML action was not bound to an exact audit denial");
  } else {
    require(backend.writes == 1 && backend.audited_before_effect &&
                backend.key == "k" && backend.value == "from-qml",
            "QML effect or payload preceded exact audit admission");
    require(audited.issue_handle(handle(), 41,
                                 permissions::OperationId::storage_write,
                                 quota(), 1000)
                    .status == runtime::RuntimeStatus::accepted,
            "authorized action did not issue bound handle");
    grant::RevocationResult revoked{
        .mutation_sequence = 5,
        .target = grant::TargetRevision::active,
        .grant = {key("storage.private"), quota(),
                  permissions::GrantState::revoked, 5},
        .action = permissions::RevocationMode::cancel_inflight,
        .grant_fingerprint = "fixture"};
    require(audited.apply_revocation(revoked).status ==
                    runtime::RuntimeStatus::accepted &&
                audited.resolve_handle(handle(), 71,
                                       permissions::OperationId::storage_write,
                                       quota(), 200)
                        .decision == permissions::HandleDecision::stale_grant,
            "revoked action handle remained live");
  }
  require(opened.channel->terminate() && scope->removes == 1,
          "action channel teardown failed");
}
} // namespace

int main(int argc, char **argv) {
  try {
    require(argc == 2, "expected fake or bwrap selector");
    if (std::string_view(argv[1]) == "bwrap") {
      if (access(BWRAP_PATH, X_OK) < 0)
        return 77;
      run_case("allowed", broker::DispatchOutcome::dispatched, false,
               BWRAP_PATH);
      run_case("denied", broker::DispatchOutcome::denied, false, BWRAP_PATH);
    } else {
      require(std::string_view(argv[1]) == "fake", "invalid selector");
      run_case("allowed", broker::DispatchOutcome::dispatched, false,
               FAKE_BWRAP_PATH);
      run_case("denied", broker::DispatchOutcome::denied, false,
               FAKE_BWRAP_PATH);
      run_case("audit-fail", broker::DispatchOutcome::core_failed, true,
               FAKE_BWRAP_PATH);
    }
  } catch (const std::exception &error) {
    std::cerr << "FAIL: " << error.what() << '\n';
    return 1;
  }
  return 0;
}
