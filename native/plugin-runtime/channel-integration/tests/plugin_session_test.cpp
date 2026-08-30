#include "audit_store.hpp"
#include "broker_runtime.hpp"
#include "dynamic_broker_runtime.hpp"
#include "omarchy/plugin_runtime/surface/render_messages.hpp"
#include "plugin_activation_coordinator.hpp"
#include "plugin_permission_controller.hpp"
#include "plugin_session.hpp"
#include "plugin_runtime_root.hpp"
#include "structured_broker.hpp"

#include <QCoreApplication>
#include <QEvent>
#include <QEventLoop>

#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

#include <array>
#include <atomic>
#include <barrier>
#include <cerrno>
#include <chrono>
#include <condition_variable>
#include <deque>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <mutex>
#include <stdexcept>
#include <string_view>
#include <thread>

void session_runtime_factory_tests();

namespace channel = omarchy::plugin_runtime::channel;
namespace audit = omarchy::plugins::audit;
namespace definitions = omarchy::plugins::definitions;
namespace host = omarchy::plugin_runtime::host_session;
namespace launcher = omarchy::plugin_runtime::launcher;
namespace manifest = omarchy::plugins::manifest;
namespace permissions = omarchy::plugins::permissions;
namespace policy = omarchy::plugin_runtime::policy;
namespace providers = omarchy::plugin_runtime::providers;
namespace runtime = omarchy::plugin_runtime::runtime;
namespace sandbox = omarchy::plugin_runtime::sandbox;
namespace surface = omarchy::plugin_runtime::surface;
namespace wire = omarchy::plugin::wire;

namespace {

void require(bool condition, std::string_view message) {
  if (!condition)
    throw std::runtime_error(std::string(message));
}

template <typename Predicate>
void await(Predicate predicate, std::string_view message) {
  const auto deadline =
      std::chrono::steady_clock::now() + std::chrono::seconds(2);
  while (!predicate() && std::chrono::steady_clock::now() < deadline) {
    QCoreApplication::processEvents(QEventLoop::AllEvents, 10);
    std::this_thread::yield();
  }
  require(predicate(), message);
}

permissions::ActivationBinding binding() {
  permissions::RequestSet requests;
  return {
      .plugin = permissions::PluginId("fixture.product-session"),
      .revision = permissions::Digest(std::string(64, 'a')),
      .policy_fingerprint = permissions::Digest(
          permissions::policy_request_fingerprint(requests)),
      .generation = 17,
  };
}

policy::GrantSnapshot grants() {
  policy::GrantSnapshot value;
  value.binding = binding();
  value.source_request_fingerprint =
      permissions::Digest(manifest::requested_capability_fingerprint({}));
  return value;
}

class Scope final : public launcher::ResourceScopeController {
public:
  bool probe(launcher::Deadline, std::string &) override { return true; }
  bool prepare_cleanup(launcher::Deadline, std::string &) override {
    return true;
  }
  AttachResult attach(std::string_view unit, pid_t monitor_pid,
                      pid_t worker_pid, const sandbox::SandboxPlan &plan,
                      launcher::Deadline, std::string &) override {
    if (monitor_pid <= 0 || worker_pid <= 0 ||
        plan.worker_descriptors != std::vector<int>({3, 4, 5}))
      return {};
    name = unit;
    ++attachments;
    return {.attached = true, .cleanup_required = true};
  }
  void kill(std::string_view, launcher::Deadline) noexcept override {}
  void remove(std::string_view, launcher::Deadline) noexcept override {}

  std::string name;
  std::atomic<int> attachments{0};
};

struct EffectBarrier final {
  std::mutex mutex;
  std::condition_variable changed;
  bool checking = false;
  bool proceed = false;
};

class Dispatch final : public host::DispatchAuthority {
  class Lease final : public host::DispatchAuthorityLease {
  public:
    Lease(permissions::ActivationBinding binding,
          std::shared_ptr<host::LiveGenerationState> live,
          std::shared_ptr<EffectBarrier> barrier)
        : binding_(std::move(binding)), live_(std::move(live)),
          barrier_(std::move(barrier)) {}

    bool current_at_effect() const noexcept override {
      if (barrier_) {
        std::unique_lock lock(barrier_->mutex);
        barrier_->checking = true;
        barrier_->changed.notify_all();
        barrier_->changed.wait(lock, [&] { return barrier_->proceed; });
      }
      return live_ && live_->current(binding_);
    }

  private:
    permissions::ActivationBinding binding_;
    std::shared_ptr<host::LiveGenerationState> live_;
    std::shared_ptr<EffectBarrier> barrier_;
  };

public:
  explicit Dispatch(std::shared_ptr<host::LiveGenerationState> live,
                    std::shared_ptr<EffectBarrier> barrier = {})
      : live_(std::move(live)), barrier_(std::move(barrier)) {}

  std::unique_ptr<host::DispatchAuthorityLease>
  acquire(const permissions::ActivationBinding &binding, std::uint64_t,
          const wire::PacketView &) override {
    return std::make_unique<Lease>(binding, live_, barrier_);
  }
  bool fence_builtin(const policy::Revocation &) noexcept override {
    return true;
  }
  bool
  fence_dynamic(const definitions::DynamicRevisionGrant &) noexcept override {
    return true;
  }

private:
  std::shared_ptr<host::LiveGenerationState> live_;
  std::shared_ptr<EffectBarrier> barrier_;
};

class RuntimeOwner final : public channel::AuthenticatedSessionRuntime {
public:
  RuntimeOwner(
      policy::GrantSnapshot snapshot, std::uint64_t nonce,
               std::shared_ptr<std::atomic<int>> destructions,
               std::shared_ptr<host::LiveGenerationState> live_generation,
      std::shared_ptr<runtime::GestureEligibilityLatch> gesture_eligibility)
      : destructions_(std::move(destructions)),
        live_generation_(std::move(live_generation)),
        gesture_eligibility_(std::move(gesture_eligibility)),
        dispatch_(live_generation_), builtin_(snapshot, {}, audit_),
        dynamic_(definitions_, {}, audit_),
        broker_(snapshot.binding, nonce, builtin_, dynamic_, dispatch_) {}
  ~RuntimeOwner() override { ++*destructions_; }
  host::StructuredBroker &broker() noexcept override { return broker_; }

private:
  std::shared_ptr<std::atomic<int>> destructions_;
  std::shared_ptr<host::LiveGenerationState> live_generation_;
  std::shared_ptr<runtime::GestureEligibilityLatch> gesture_eligibility_;
  audit::BoundedAuditLog audit_;
  definitions::TrustedDefinitionRegistry definitions_;
  Dispatch dispatch_;
  runtime::AuditedBrokerRuntime builtin_;
  runtime::DynamicBrokerRuntime dynamic_;
  host::StructuredBroker broker_;
};

class RuntimeFactory final
    : public channel::AuthenticatedSessionRuntimeFactory {
public:
  std::unique_ptr<channel::AuthenticatedSessionRuntime>
  create(const manifest::ManifestV2 &verified_manifest,
         const policy::GrantSnapshot &snapshot, int revision_directory_fd,
         int private_state_directory_fd, std::uint64_t nonce,
         std::shared_ptr<host::LiveGenerationState> live_generation,
         std::shared_ptr<runtime::GestureEligibilityLatch> gesture_eligibility)
      override {
    ++calls;
    if (on_create)
      on_create();
    if (throw_on_create)
      throw std::runtime_error("injected runtime construction failure");
    if (return_null)
      return {};
    const int marker = ::openat(revision_directory_fd, "d1-mode",
                                O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
    if (marker >= 0) {
      std::array<char, 64> bytes{};
      const auto count = ::read(marker, bytes.data(), bytes.size());
      ::close(marker);
      if (count > 0)
        revision_mode.assign(bytes.data(), static_cast<std::size_t>(count));
    }
    const int state_marker = ::openat(private_state_directory_fd, "identity",
                                      O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
    if (state_marker >= 0) {
      std::array<char, 64> bytes{};
      const auto count = ::read(state_marker, bytes.data(), bytes.size());
      ::close(state_marker);
      if (count > 0)
        state_identity.assign(bytes.data(), static_cast<std::size_t>(count));
    }
    saw_manifest = verified_manifest.surface_names ==
                   std::vector<std::string>({"bar", "panel", "overlay"});
    descriptors_valid = ::fcntl(revision_directory_fd, F_GETFD) >= 0 &&
        ::fcntl(private_state_directory_fd, F_GETFD) >= 0;
    gesture_authority_valid = gesture_eligibility != nullptr;
    live_generation_valid =
        live_generation && live_generation->current(snapshot.binding);
    last_live = live_generation;
    gesture_lifetime = gesture_eligibility;
    return std::make_unique<RuntimeOwner>(snapshot, nonce, destructions,
                                          std::move(live_generation),
                                          std::move(gesture_eligibility));
  }

  std::shared_ptr<std::atomic<int>> destructions =
      std::make_shared<std::atomic<int>>(0);
  int calls = 0;
  std::function<void()> on_create;
  bool throw_on_create = false;
  bool return_null = false;
  std::string revision_mode;
  std::string state_identity;
  bool saw_manifest = false;
  bool descriptors_valid = false;
  bool gesture_authority_valid = false;
  bool live_generation_valid = false;
  std::weak_ptr<runtime::GestureEligibilityLatch> gesture_lifetime;
  std::shared_ptr<host::LiveGenerationState> last_live;
};

class ActivationFixture final {
public:
  ActivationFixture() {
    std::string pattern = "/tmp/omarchy-product-session-XXXXXX";
    const char *created = ::mkdtemp(pattern.data());
    require(created != nullptr, "cannot create product session fixture");
    root_ = created;
    revision_ = root_ / "revision";
    state_ = root_ / "state";
    std::filesystem::create_directories(revision_);
    std::filesystem::create_directories(state_);
    std::ofstream(revision_ / "d1-mode") << "session-happy\n";
    require(::chmod((revision_ / "d1-mode").c_str(), 0444) == 0 &&
                ::chmod(revision_.c_str(), 0555) == 0,
            "cannot make product revision immutable");
  }

  ~ActivationFixture() {
    static_cast<void>(::chmod(revision_.c_str(), 0755));
    std::error_code ignored;
    std::filesystem::remove_all(root_, ignored);
  }

  host::ActivationSnapshot snapshot() const {
    auto snapshot_grants = grants();
    manifest::ManifestV2 verified_manifest;
    verified_manifest.id = std::string(snapshot_grants.binding.plugin.view());
    verified_manifest.surface_names = {"bar", "panel", "overlay"};
    const int record =
        ::open((revision_ / "d1-mode").c_str(), O_RDONLY | O_CLOEXEC);
    const int revision =
        ::open(revision_.c_str(), O_RDONLY | O_DIRECTORY | O_CLOEXEC);
    const int state =
        ::open(state_.c_str(), O_RDONLY | O_DIRECTORY | O_CLOEXEC);
    require(record >= 0 && revision >= 0 && state >= 0,
            "cannot open exact product activation descriptors");
    return {
        .record = {.plugin_id =
                       std::string(snapshot_grants.binding.plugin.view()),
                   .revision_directory = "revision",
                   .revision_sha256 =
                       std::string(snapshot_grants.binding.revision.view()),
                   .state_directory = "state"},
        .manifest = std::move(verified_manifest),
        .grants = snapshot_grants,
        .activation_record = host::OwnedDescriptor(record),
        .revision_directory = host::OwnedDescriptor(revision),
        .state_directory = host::OwnedDescriptor(state),
        .live = std::make_shared<host::LiveGenerationState>(
            snapshot_grants.binding),
    };
  }

private:
  std::filesystem::path root_;
  std::filesystem::path revision_;
  std::filesystem::path state_;
};

class CoordinatorFixture final {
public:
  explicit CoordinatorFixture(std::string_view worker_mode = "session-happy") {
    std::string pattern = "/tmp/omarchy-product-activation-XXXXXX";
    const char *created = ::mkdtemp(pattern.data());
    require(created != nullptr, "cannot create coordinator fixture");
    root_ = created;
    activation_ = root_ / "activation";
    revisions_ = root_ / "revisions";
    state_ = root_ / "state";
    authority_ = root_ / "authority";
    revision_ = revisions_ / "installed";
    state_directory_ = state_ / plugin_;
    std::filesystem::create_directory(activation_);
    std::filesystem::create_directory(revisions_);
    std::filesystem::create_directory(state_);
    std::filesystem::create_directory(authority_);
    std::filesystem::copy(COORDINATOR_REVISION_FIXTURE, revision_,
                          std::filesystem::copy_options::recursive);
    std::ofstream(revision_ / "d1-mode") << worker_mode << '\n';
    for (const auto &entry :
         std::filesystem::recursive_directory_iterator(revision_)) {
      const mode_t mode = entry.is_directory() ? 0555 : 0444;
      require(::chmod(entry.path().c_str(), mode) == 0,
              "cannot make verified revision immutable");
    }
    require(::chmod(revision_.c_str(), 0555) == 0,
            "cannot make revision root immutable");
    std::filesystem::create_directory(state_directory_);
    std::ofstream(state_directory_ / "identity") << "pinned\n";
    require(::chmod(authority_.c_str(), 0700) == 0 &&
                ::chmod(state_directory_.c_str(), 0700) == 0,
            "cannot secure coordinator authority roots");

    activation_fd_ = open_directory(activation_);
    revisions_fd_ = open_directory(revisions_);
    state_fd_ = open_directory(state_);
    authority_fd_ = open_directory(authority_);
    store_ = host::AuthorityStore::open(authority_fd_, ::getuid(),
                                        permissions::PluginId(plugin_));
    require(store_ != nullptr, "cannot open coordinator authority store");
    const int revision_fd = open_directory(revision_);
    host::DescriptorRevisionVerifier verifier;
    verified_ = verifier.verify_open_revision(revision_fd);
    ::close(revision_fd);
    require(verified_ && verified_->manifest.id == plugin_,
            "cannot descriptor-verify coordinator fixture");
  }

  ~CoordinatorFixture() {
    store_.reset();
    for (const int fd :
         {activation_fd_, revisions_fd_, state_fd_, authority_fd_})
      if (fd >= 0)
        ::close(fd);
    for (const auto &entry :
         std::filesystem::recursive_directory_iterator(revisions_))
      if (entry.is_directory())
        static_cast<void>(::chmod(entry.path().c_str(), 0755));
    static_cast<void>(::chmod(revision_.c_str(), 0755));
    std::error_code ignored;
    std::filesystem::remove_all(root_, ignored);
  }

  policy::GrantSnapshot snapshot(std::uint64_t generation) const {
    policy::GrantSnapshot value;
    value.requests = permissions::requests_from_manifest(verified_->manifest);
    value.binding = {
        .plugin = permissions::PluginId(plugin_),
        .revision = permissions::Digest(verified_->tree_sha256),
        .policy_fingerprint = permissions::Digest(
            permissions::policy_request_fingerprint(value.requests)),
        .generation = generation};
    value.source_request_fingerprint =
        permissions::Digest(verified_->request_sha256);
    for (const auto &request : value.requests.values())
      value.grants.push_back({.capability = request.capability,
                              .scope = request.scope,
                              .state = permissions::GrantState::granted,
                              .epoch = generation});
    return value;
  }

  policy::GrantSnapshot publish(std::uint64_t generation,
                                std::uint64_t sequence,
                                bool deny_notifications = false) {
    auto value = snapshot(generation);
    if (deny_notifications)
      for (auto &grant : value.grants.values())
        if (grant.capability.id.view() == "notifications.send")
          grant.state = permissions::GrantState::denied;
    require(store_->publish_candidate(*verified_, value, sequence, definitions_,
                                      {}) ==
                host::AuthorityMutationResult::applied,
            "cannot publish coordinator candidate");
    return value;
  }

  void promote(const policy::GrantSnapshot &value, std::uint64_t sequence) {
    require(store_->promote_candidate(value.binding, sequence) ==
                host::AuthorityMutationResult::applied,
            "cannot promote coordinator candidate");
  }

  void record(std::string revision_sha256 = {}) const {
    if (revision_sha256.empty())
      revision_sha256 = verified_->tree_sha256;
    const auto bytes =
        "format=omarchy-plugin-activation-v2\nplugin=" + plugin_ +
        "\nrevision-directory=installed\nrevision-sha256=" + revision_sha256 +
        "\nstate-directory=" + plugin_ + "\n";
    std::ofstream file(activation_ / "current", std::ios::trunc);
    file << bytes;
    file.close();
    require(::chmod((activation_ / "current").c_str(), 0600) == 0,
            "cannot secure activation record");
  }


  std::unique_ptr<channel::PreparedPluginRuntime> prepare_root(
      channel::RuntimeServices services = {},
      std::function<launcher::Supervisor()> supervisor_factory = {},
      std::string activation_record = "current",
      std::uint32_t trusted_uid = static_cast<std::uint32_t>(::getuid()),
      bool valid_authority = true,
      void (*before_final_fence)(host::AuthorityStore &, void *) noexcept =
          nullptr,
      void *before_final_fence_context = nullptr) {
    store_.reset();
    auto authority =
        valid_authority
            ? host::OwnedDescriptor(
                  ::fcntl(authority_fd_, F_DUPFD_CLOEXEC, 0))
            : host::OwnedDescriptor{};
    return channel::PluginRuntimeRootTestAccess::prepare_from_parts(
        activation_fd_, revisions_fd_, state_fd_, std::move(authority),
        permissions::PluginId(plugin_), trusted_uid,
        std::move(activation_record),
        std::make_shared<const definitions::TrustedDefinitionRegistry>(
            definitions_),
        std::make_shared<const channel::RuntimeServices>(std::move(services)),
        {}, {}, std::move(supervisor_factory), before_final_fence,
        before_final_fence_context);
  }

  void close_borrowed_roots() {
    for (int *fd :
         {&activation_fd_, &revisions_fd_, &state_fd_, &authority_fd_}) {
      if (*fd >= 0)
        ::close(*fd);
      *fd = -1;
    }
  }

  void corrupt_active() {
    const auto authority_state = store_->read_slots();
    require(authority_state && authority_state->active,
            "active coordinator slot missing");
    const auto file =
        authority_ /
        ("grant-" +
         std::string(authority_state->active->snapshot_digest.view()));
    std::fstream stream(file, std::ios::in | std::ios::out | std::ios::binary);
    stream.put('X');
  }

  void corrupt_prepared_backing() {
    std::ofstream activation(activation_ / "current", std::ios::trunc);
    activation << "invalid\n";
    activation.close();
    std::ofstream slots_file(authority_ / "slots", std::ios::trunc);
    slots_file << "invalid\n";
    slots_file.close();
  }

  void authority_writable(bool writable) {
    require(::chmod(authority_.c_str(), writable ? 0700 : 0500) == 0,
            "cannot change authority root mode");
  }

  void corrupt_record() const {
    std::ofstream file(activation_ / "current", std::ios::trunc);
    file << "invalid\n";
    file.close();
  }

  void replace_selected_paths() {
    const auto replacement_revision = revisions_ / "replacement";
    const auto pinned_revision = revisions_ / "pinned";
    std::filesystem::create_directory(replacement_revision);
    std::ofstream(replacement_revision / "d1-mode") << "replacement\n";
    require(::chmod((replacement_revision / "d1-mode").c_str(), 0444) == 0 &&
                ::chmod(replacement_revision.c_str(), 0555) == 0,
            "cannot secure replacement revision");
    std::filesystem::rename(revision_, pinned_revision);
    std::filesystem::rename(replacement_revision, revision_);

    const auto replacement_state = state_ / "replacement";
    const auto pinned_state = state_ / "pinned";
    std::filesystem::create_directory(replacement_state);
    std::ofstream(replacement_state / "identity") << "replacement\n";
    require(::chmod(replacement_state.c_str(), 0700) == 0,
            "cannot secure replacement state");
    std::filesystem::rename(state_directory_, pinned_state);
    std::filesystem::rename(replacement_state, state_directory_);
  }

  host::AuthorityStore &store() { return *store_; }
  const host::VerifiedRevision &verified() const { return *verified_; }

private:
  static int open_directory(const std::filesystem::path &path) {
    const int fd = ::open(path.c_str(), O_RDONLY | O_DIRECTORY | O_CLOEXEC);
    require(fd >= 0, "cannot open coordinator directory");
    return fd;
  }

  const std::string plugin_ = "org.example.status";
  std::filesystem::path root_;
  std::filesystem::path activation_;
  std::filesystem::path revisions_;
  std::filesystem::path state_;
  std::filesystem::path authority_;
  std::filesystem::path revision_;
  std::filesystem::path state_directory_;
  int activation_fd_ = -1;
  int revisions_fd_ = -1;
  int state_fd_ = -1;
  int authority_fd_ = -1;
  definitions::TrustedDefinitionRegistry definitions_;
  std::unique_ptr<host::AuthorityStore> store_;
  std::optional<host::VerifiedRevision> verified_;
};

host::SessionToken token() {
  const auto value = binding();
  return {
      .plugin_id = std::string(value.plugin.view()),
      .revision_sha256 = std::string(value.revision.view()),
      .generation = value.generation,
      .session_nonce = 73,
  };
}

struct ChannelState {
  std::atomic<int> launches{0};
  std::atomic<int> handshakes{0};
  std::atomic<int> revocations{0};
  std::atomic<int> terminations{0};
  std::atomic<int> destructions{0};
  std::mutex mutex;
  std::deque<host::OwnedMessage> incoming;
  host::SessionWakeHandler wake;
  host::ChannelError launch_error = host::ChannelError::none;

  void publish(host::OwnedMessage message) {
    host::SessionWakeHandler notify;
    {
      std::lock_guard lock(mutex);
      incoming.push_back(std::move(message));
      notify = wake;
    }
    if (notify)
      notify.invoke();
  }
};

class FakeChannel final : public host::SessionChannel {
public:
  explicit FakeChannel(std::shared_ptr<ChannelState> state)
      : state_(std::move(state)) {}
  ~FakeChannel() override { ++state_->destructions; }

  host::ChannelError launch(const host::SessionToken &identity,
                            TimePoint deadline) override {
    ++state_->launches;
    startup_deadline_ = deadline;
    if (identity != token())
      return host::ChannelError::launch_failed;
    return state_->launch_error;
  }

  host::ChannelError handshake(TimePoint deadline) override {
    ++state_->handshakes;
    return deadline == startup_deadline_ ? host::ChannelError::none
                                         : host::ChannelError::handshake_failed;
  }

  host::SendStatus send(const host::OwnedMessage &, TimePoint) override {
    return host::SendStatus::complete;
  }

  host::ReceiveResult receive(TimePoint) override {
    std::lock_guard lock(state_->mutex);
    if (state_->incoming.empty())
      return {.status = host::ReceiveStatus::would_block, .message = {}};
    auto next = std::move(state_->incoming.front());
    state_->incoming.pop_front();
    return {.status = host::ReceiveStatus::message, .message = std::move(next)};
  }

  bool
  install_wake_handler(host::SessionWakeHandler handler) noexcept override {
    std::lock_guard lock(state_->mutex);
    state_->wake = handler;
    return bool(state_->wake);
  }

  void clear_wake_handler() noexcept override {
    std::lock_guard lock(state_->mutex);
    state_->wake = {};
  }

  bool revoke(const host::SessionToken &identity, TimePoint) noexcept override {
    ++state_->revocations;
    return identity == token();
  }

  void terminate(TimePoint) noexcept override { ++state_->terminations; }

private:
  std::shared_ptr<ChannelState> state_;
  TimePoint startup_deadline_{};
};

host::OwnedMessage render_message(const host::SessionToken &identity,
                                  std::uint64_t sequence,
                                  std::uint64_t correlation,
                                  surface::SurfaceKey key) {
  const auto encoded = surface::encode_frame_ready({
      .surface = key,
      .slot = 0,
      .slot_sequence = 2,
      .frame_sequence = sequence,
  });
  return {
      .token = identity,
      .lane = host::ChannelLane::render,
      .message_type =
          static_cast<std::uint16_t>(surface::RenderMessageType::frame_ready),
      .correlation_id = correlation,
      .sequence = sequence,
      .payload = {encoded.begin(), encoded.end()},
      .descriptors = {},
  };
}

host::OwnedMessage allocation_message(const host::SessionToken &identity,
                                      std::uint64_t sequence,
                                      std::uint64_t correlation,
                                      surface::SurfaceKey key, int descriptor) {
  const auto encoded_key = surface::encode_surface_key(key);
  std::vector<std::byte> payload(96);
  std::copy(encoded_key.begin(), encoded_key.end(), payload.begin());
  std::vector<host::OwnedFd> descriptors;
  descriptors.emplace_back(descriptor);
  return {
      .token = identity,
      .lane = host::ChannelLane::render,
      .message_type = static_cast<std::uint16_t>(
          surface::RenderMessageType::surface_allocate),
      .correlation_id = correlation,
      .sequence = sequence,
      .payload = std::move(payload),
      .descriptors = std::move(descriptors),
  };
}

bool descriptor_closed(int descriptor) {
  errno = 0;
  return ::fcntl(descriptor, F_GETFD) == -1 && errno == EBADF;
}

struct Endpoint final : host::SurfaceEndpoint {
  std::size_t deliveries = 0;
  std::optional<host::OwnedAuthenticatedRenderMessage> last;
  bool receive(host::OwnedAuthenticatedRenderMessage message) override {
    ++deliveries;
    last.emplace(std::move(message));
    return true;
  }
};

struct Events final : channel::PluginSessionEvents {
  host::SessionState last_state = host::SessionState::idle;
  std::vector<host::RouteResult> rejected;
  std::size_t controls = 0;
  void state_changed(host::SessionState state, host::SessionError) override {
    last_state = state;
  }
  void control_received(const host::OwnedMessage &) override { ++controls; }
  void render_rejected(host::RouteResult result) override {
    rejected.push_back(result);
  }
};

class GestureClock final : public runtime::GestureEligibilityClock {
public:
  [[nodiscard]] std::uint64_t now_nanoseconds() const override { return now; }
  std::uint64_t now = 1'000;
};

struct IntentSink final : channel::SurfaceIntentSink {
  bool accept(host::AdmittedSurfaceIntent intent) override {
    ++accepted;
    auto publication = intent.take_if_fresh();
    was_fresh = publication.has_value();
    if (!publication)
      return false;
    source = std::string(publication->source_name());
    target = std::string(publication->target_name());
    action = publication->action();
    input_sequence = publication->input_sequence();
    return was_fresh;
  }

  std::size_t accepted = 0;
  bool was_fresh = false;
  std::string source;
  std::string target;
  surface::SurfaceIntentAction action = surface::SurfaceIntentAction::open;
  std::uint64_t input_sequence = 0;
};

host::OwnedMessage
intent_message(const host::SessionToken &identity, std::uint64_t sequence,
                                  const surface::SurfaceIntentRequest &request) {
  const auto encoded = surface::encode_surface_intent(request);
  return {
      .token = identity,
      .lane = host::ChannelLane::render,
      .message_type = static_cast<std::uint16_t>(
          surface::RenderMessageType::surface_intent),
      .correlation_id = 0,
      .sequence = sequence,
      .payload = {encoded.begin(), encoded.end()},
      .descriptors = {},
  };
}

void shared_gesture_authority_has_one_concurrent_winner() {
  const auto activation = binding();
  const surface::SurfaceKey source{.id = 1,
                                   .generation = activation.generation};
  const surface::SurfaceKey target{.id = 2,
                                   .generation = activation.generation};
  for (std::uint64_t iteration = 1; iteration <= 100; ++iteration) {
    auto clock = std::make_shared<GestureClock>();
    auto latch = std::make_shared<runtime::GestureEligibilityLatch>(clock);
    host::GestureIntentAuthority intents(activation, *latch);
    require(intents.declare_surface(source, "bar") ==
                    host::SurfaceDeclarationResult::declared &&
                intents.declare_surface(target, "panel") ==
                    host::SurfaceDeclarationResult::declared &&
                intents.arm(source, iteration),
            "concurrent gesture fixture did not arm");
    const definitions::DynamicInvocation::GestureClaim claim{
        .surface_id = source.id,
        .surface_generation = source.generation,
        .input_sequence = iteration,
    };
    const surface::SurfaceIntentRequest request{
        .source = source,
        .target = target,
        .input_sequence = iteration,
        .action = surface::SurfaceIntentAction::open,
    };
    std::barrier start(3);
    bool broker_won = false;
    bool surface_won = false;
    std::thread broker([&] {
      start.arrive_and_wait();
      broker_won = latch->consume(activation, claim).has_value();
    });
    std::thread surface_request([&] {
      start.arrive_and_wait();
      auto admitted = intents.admit(request);
      surface_won =
          admitted.intent && admitted.intent->take_if_fresh().has_value();
    });
    start.arrive_and_wait();
    broker.join();
    surface_request.join();
    require(broker_won != surface_won,
            "concurrent broker and surface intent did not have one winner");
    require(!latch->consume(activation, claim) &&
                !intents.admit(request).intent,
            "concurrent gesture winner left a replayable eligibility");
  }
}

permissions::TokenScope token_scope(std::string_view value) {
  permissions::TokenScope scope;
  require(scope.tokens.insert(permissions::ScopeToken(value)),
          "duplicate effect-fence token");
  return scope;
}

void put16(std::vector<std::byte> &bytes, std::size_t offset,
           std::uint16_t value) {
  bytes[offset] = static_cast<std::byte>(value >> 8U);
  bytes[offset + 1] = static_cast<std::byte>(value);
}

void put32(std::vector<std::byte> &bytes, std::size_t offset,
           std::uint32_t value) {
  for (std::size_t index = 0; index < 4; ++index)
    bytes[offset + index] =
        static_cast<std::byte>(value >> ((3U - index) * 8U));
}

std::vector<std::byte> audio_request(std::string_view cue) {
  std::vector<std::byte> bytes(10 + cue.size());
  const auto operation =
      static_cast<std::uint16_t>(permissions::OperationId::audio_play_cue);
  put16(bytes, 0, operation);
  put16(bytes, 2, static_cast<std::uint16_t>(2 + cue.size()));
  put32(bytes, 4, 0);
  put16(bytes, 8, static_cast<std::uint16_t>(cue.size()));
  for (std::size_t index = 0; index < cue.size(); ++index)
    bytes[10 + index] = static_cast<std::byte>(cue[index]);
  return bytes;
}

bool count_audio_effect(std::string_view, void *context) noexcept {
  ++*static_cast<std::atomic<int> *>(context);
  return true;
}

void effect_time_revocation_fences_an_authenticated_request() {
  policy::GrantSnapshot snapshot;
  const permissions::CapabilityKey capability{
      .id = permissions::CapabilityId("audio.play-cue"), .version = 1};
  snapshot.requests.push_back({.capability = capability,
                               .scope = token_scope("complete"),
                               .required = true});
  snapshot.binding = {
      .plugin = permissions::PluginId("fixture.effect-fence"),
      .revision = permissions::Digest(std::string(64, 'e')),
      .policy_fingerprint = permissions::Digest(
          permissions::policy_request_fingerprint(snapshot.requests)),
      .generation = 23,
  };
  snapshot.grants.push_back({.capability = capability,
                             .scope = token_scope("complete"),
                             .state = permissions::GrantState::granted,
                             .epoch = 1});
  const auto activation = snapshot.binding;
  auto live = std::make_shared<host::LiveGenerationState>(activation);
  auto barrier = std::make_shared<EffectBarrier>();
  Dispatch dispatch(live, barrier);
  std::atomic<int> provider_effects{0};
  audit::BoundedAuditLog audit_log;
  definitions::TrustedDefinitionRegistry definitions;
  runtime::AuditedBrokerRuntime builtin(
      snapshot,
      providers::ProviderConfiguration{
          .binding = {},
          .storage_epoch = 0,
          .notification_epoch = 0,
          .audio_epoch = 0,
          .storage = {},
          .notification = {},
          .audio = {.play = count_audio_effect, .context = &provider_effects}},
      audit_log);
  runtime::DynamicBrokerRuntime dynamic(definitions, {}, audit_log);
  host::StructuredBroker broker(snapshot.binding, 91, builtin, dynamic,
                                dispatch);
  auto extracted = broker.take_admission();
  require(extracted && extracted.admission,
          "effect-fence broker did not provide admission");
  const auto payload = audio_request("complete");
  auto authenticated = extracted.admission->admit_authenticated({
      .message_type =
          static_cast<std::uint16_t>(permissions::OperationId::audio_play_cue),
      .correlation_id = 1,
      .payload = payload,
  });
  require(authenticated && authenticated.request,
          "effect-fence request was not authenticated");
  bool authority_stale = false;
  std::thread effect([&] {
    std::array<std::byte, 64> response{};
    auto transaction =
        broker.dispatch(std::move(*authenticated.request), 100, response);
    authority_stale =
        transaction.state() == host::TransactionState::fatal &&
        transaction.fatal() == host::DispatchFatal::authority_stale;
  });
  {
    std::unique_lock lock(barrier->mutex);
    barrier->changed.wait(lock, [&] { return barrier->checking; });
  }
  (void)live->revoke_and_drain();
  {
    std::lock_guard lock(barrier->mutex);
    barrier->proceed = true;
  }
  barrier->changed.notify_all();
  effect.join();
  require(authority_stale && provider_effects == 0,
          "revocation after authenticated acquire reached provider effect");
}

void product_session_intercepts_gesture_intents_before_render_routing() {
  auto identity = token();
  auto revision = grants();
  auto live = std::make_shared<host::LiveGenerationState>(revision.binding);
  auto channel_state = std::make_shared<ChannelState>();
  manifest::ManifestV2 verified_manifest;
  verified_manifest.id = identity.plugin_id;
  verified_manifest.surface_names = {"barWidget", "panel"};
  Events events;
  IntentSink sink;
  auto clock = std::make_shared<GestureClock>();
  auto shared_gesture =
      std::make_shared<runtime::GestureEligibilityLatch>(clock);
  auto prepared = channel::PluginSessionTestAccess::prepare_from_parts(
      identity, std::move(verified_manifest), std::move(revision), live,
      std::make_unique<FakeChannel>(channel_state), {}, clock, shared_gesture);
  channel::PluginSessionCreateError create_error{};
  auto product = channel::PluginSessionTestAccess::commit(
      std::move(prepared), create_error, &events, &sink);
  require(product && create_error == channel::PluginSessionCreateError::none,
          "intent prepared session did not commit");
  product->start();
  await([&] { return product->state() == host::SessionState::running; },
        "intent product session did not start");

  Endpoint bar;
  Endpoint panel;
  const std::array<std::uint64_t, 1> bar_correlations{701};
  const std::array<std::uint64_t, 1> panel_correlations{702};
  const auto bar_attachment =
      product->attach("barWidget", bar_correlations, bar);
  const auto panel_attachment =
      product->attach("panel", panel_correlations, panel);
  require(bar_attachment && panel_attachment, "intent surfaces did not attach");
  const surface::SurfaceIntentRequest request{
      .source = bar_attachment.key,
      .target = panel_attachment.key,
      .input_sequence = 91,
      .action = surface::SurfaceIntentAction::toggle,
  };

  channel_state->publish(intent_message(identity, 1, request));
  await([&] { return events.rejected.size() == 1; },
        "intent without a gesture was not rejected");

  require(product->arm_surface_intent(bar_attachment.key, 90),
          "trusted input path could not arm intent eligibility");
  auto malformed = intent_message(identity, 2, request);
  malformed.payload.pop_back();
  channel_state->publish(std::move(malformed));
  await([&] { return events.rejected.size() == 2; },
        "malformed intent was not rejected");
  require(
      product->arm_surface_intent(bar_attachment.key, request.input_sequence),
          "malformed intent did not safely clear its eligibility");
  product->clear_surface_intent_eligibility();
  channel_state->publish(intent_message(identity, 3, request));
  await([&] { return events.rejected.size() == 3; },
        "failed input delivery did not clear intent eligibility");
  require(
      product->arm_surface_intent(bar_attachment.key, request.input_sequence),
          "trusted path could not re-arm after a failed input delivery");
  const definitions::DynamicInvocation::GestureClaim claim{
      .surface_id = bar_attachment.key.id,
      .surface_generation = bar_attachment.key.generation,
      .input_sequence = request.input_sequence,
  };
  require(shared_gesture->consume(product->binding(), claim).has_value(),
          "dynamic broker view did not receive the session gesture arm");
  channel_state->publish(intent_message(identity, 4, request));
  await([&] { return events.rejected.size() == 4; },
        "surface intent reused a gesture consumed by the broker");
  require(
      product->arm_surface_intent(bar_attachment.key, request.input_sequence),
          "trusted path could not re-arm after broker consumption");

  channel_state->publish(intent_message(identity, 5, request));
  await([&] { return sink.accepted == 1; },
        "eligible intent did not reach the shell sink");
  require(sink.was_fresh && sink.source == "barWidget" &&
              sink.target == "panel" &&
              sink.action == surface::SurfaceIntentAction::toggle &&
              sink.input_sequence == request.input_sequence,
          "admitted intent lost trusted surface semantics");
  require(!shared_gesture->consume(product->binding(), claim),
          "broker reused a gesture consumed by a surface intent");
  channel_state->publish(intent_message(identity, 6, request));
  await([&] { return events.rejected.size() == 5; },
        "replayed intent was not rejected");

  require(product->detach("panel", panel) &&
              product->arm_surface_intent(bar_attachment.key, 92),
          "detach setup failed");
  auto detached_target = request;
  detached_target.input_sequence = 92;
  channel_state->publish(intent_message(identity, 7, detached_target));
  await([&] { return events.rejected.size() == 6; },
        "intent targeting a detached surface was not rejected");

  require(product->attach("panel", panel_correlations, panel) &&
              product->arm_surface_intent(bar_attachment.key, 93) &&
              product->detach("barWidget", bar),
          "source detach setup failed");
  auto detached_source = request;
  detached_source.input_sequence = 93;
  channel_state->publish(intent_message(identity, 8, detached_source));
  await([&] { return events.rejected.size() == 7; },
        "source detach did not clear intent eligibility");

  product->revoke();
  await([&] { return product->state() == host::SessionState::revoked; },
        "intent session did not revoke");
  require(!product->arm_surface_intent(bar_attachment.key, 94),
          "revoked session armed an intent");
  auto revoked = request;
  revoked.input_sequence = 94;
  channel_state->publish(intent_message(identity, 9, revoked));
  QCoreApplication::processEvents(QEventLoop::AllEvents, 10);
  require(sink.accepted == 1 && bar.deliveries == 0 && panel.deliveries == 0 &&
              events.controls == 0,
          "intent escaped through the render router or control path");
}

void product_session_routes_two_surfaces_over_one_launch() {
  auto identity = token();
  auto revision = grants();
  auto live = std::make_shared<host::LiveGenerationState>(revision.binding);
  auto channel_state = std::make_shared<ChannelState>();
  omarchy::plugins::manifest::ManifestV2 manifest;
  manifest.id = identity.plugin_id;
  manifest.surface_names = {"barWidget", "panel"};
  Events events;
  auto prepared = channel::PluginSessionTestAccess::prepare_from_parts(
      identity, std::move(manifest), std::move(revision), live,
      std::make_unique<FakeChannel>(channel_state));
  channel::PluginSessionCreateError create_error{};
  auto product = channel::PluginSessionTestAccess::commit(
      std::move(prepared), create_error, &events);
  require(product && create_error == channel::PluginSessionCreateError::none,
          "two-surface prepared session did not commit");

  Endpoint first;
  Endpoint second;
  const std::array<std::uint64_t, 1> first_correlations{101};
  const std::array<std::uint64_t, 1> second_correlations{202};
  require(product->attach("barWidget", first_correlations, first).status ==
              channel::SurfaceAttachStatus::session_not_running,
          "surface attached before the authenticated session was running");

  product->start();
  await([&] { return product->state() == host::SessionState::running; },
        "product session did not start");
  channel::PluginSessionTestAccess::set_surface_attach_fault(
      *product, channel::SurfaceAttachFault::after_router);
  require(product->attach("barWidget", first_correlations, first).status ==
                  channel::SurfaceAttachStatus::allocation_failed &&
              product->surface_count() == 0,
          "surface attach fault retained a router registration");
  require(product->attach("missing", first_correlations, first).status ==
              channel::SurfaceAttachStatus::undeclared_surface,
          "undeclared manifest surface attached");
  const auto first_attachment =
      product->attach("barWidget", first_correlations, first);
  require(first_attachment.status == channel::SurfaceAttachStatus::attached,
          "first surface did not attach");
  const auto second_attachment =
      product->attach("panel", second_correlations, second);
  require(second_attachment.status == channel::SurfaceAttachStatus::attached,
          "second surface did not attach");
  require(first_attachment.key ==
                  surface::SurfaceKey{.id = 1, .generation = 17} &&
              second_attachment.key ==
                  surface::SurfaceKey{.id = 2, .generation = 17},
          "session did not issue stable manifest-derived surface keys");
  require(product->attach("barWidget", first_correlations, second).status ==
              channel::SurfaceAttachStatus::already_attached,
          "duplicate surface owner replaced the original endpoint");
  require(!product->detach("barWidget", second),
          "foreign endpoint detached a surface owner");

  channel_state->publish(
      render_message(identity, 1, 101, first_attachment.key));
  channel_state->publish(
      render_message(identity, 2, 202, second_attachment.key));
  channel_state->publish(render_message(
      identity, 3, 101, {.id = 99, .generation = identity.generation}));
  channel_state->publish(
      render_message(identity, 4, 101, second_attachment.key));
  channel_state->publish(
      render_message(identity, 5, 101,
      {.id = first_attachment.key.id,
       .generation = first_attachment.key.generation + 1}));
  auto malformed = render_message(identity, 6, 101, first_attachment.key);
  malformed.payload.pop_back();
  channel_state->publish(std::move(malformed));
  await([&] { return first.deliveries == 1 && second.deliveries == 1; },
        "render traffic did not reach both attached surfaces");
  await([&] { return events.rejected.size() == 4; },
        "hostile render destinations were not rejected");
  require(channel_state->launches == 1 && channel_state->handshakes == 1,
          "multiple surfaces launched more than one worker channel");
  require(events.rejected[0] == host::RouteResult::unknown_surface &&
              events.rejected[1] ==
                  host::RouteResult::conflicting_destination &&
              events.rejected[2] == host::RouteResult::stale_generation &&
              events.rejected[3] == host::RouteResult::endpoint_rejected,
          "render destination failures lost their exact reason");
  require(product->surface_count() == 2, "surface registry lost an endpoint");

  int allocation_fds[2] = {-1, -1};
  require(::pipe2(allocation_fds, O_CLOEXEC) == 0,
          "could not create allocation descriptor");
  ::close(allocation_fds[1]);
  channel_state->publish(allocation_message(
      identity, 7, 101, first_attachment.key, allocation_fds[0]));
  await([&] { return first.deliveries == 2; },
        "surface allocation did not reach its endpoint");
  require(first.last &&
              first.last->message_type ==
                  static_cast<std::uint16_t>(
                      surface::RenderMessageType::surface_allocate) &&
              first.last->payload.size() == 96 &&
              first.last->descriptors.size() == 1 &&
              first.last->descriptors.front().get() == allocation_fds[0],
          "surface allocation lost its exact type, payload, or frame fd");
  first.last.reset();
  require(descriptor_closed(allocation_fds[0]),
          "endpoint release did not close the routed frame fd");

  product->revoke();
  await([&] { return product->state() == host::SessionState::revoked; },
        "product session did not revoke");
  require(!live->current(product->binding()),
          "revocation left generation authority current");
  require(product->surface_count() == 0,
          "revocation did not detach every surface");
  require(channel_state->revocations == 1,
          "revocation did not reach the sole channel exactly once");
  require(product->attach("barWidget", first_correlations, first).status ==
              channel::SurfaceAttachStatus::session_not_running,
          "revoked session accepted a new surface");
  channel_state->publish(
      render_message(identity, 8, 101, first_attachment.key));
  QCoreApplication::processEvents(QEventLoop::AllEvents, 10);
  require(first.deliveries == 2,
          "late render traffic reached a revoked surface");
  product.reset();
  await([&] { return channel_state->destructions == 1; },
        "session worker was not reaped before test teardown");
}

void prepared_commit_retains_activation_and_reuses_one_launch() {
  ActivationFixture fixture;
  RuntimeFactory runtime_factory;
  auto scope = std::make_shared<Scope>();
  channel::PluginSessionCreateError create_error{};
  auto prepared = channel::PluginSessionTestAccess::prepare_from_activation(
      launcher::Supervisor::forTestOnly(FAKE_BWRAP_PATH, CHANNEL_PEER_PATH,
                                        scope),
      fixture.snapshot(), runtime_factory, create_error);
  require(prepared &&
              create_error == channel::PluginSessionCreateError::none,
          "product session preparation failed");
  auto product = channel::PluginSessionTestAccess::commit(
      std::move(prepared), create_error);
  require(product && create_error == channel::PluginSessionCreateError::none,
          "prepared product session commit failed");
  require(runtime_factory.calls == 1 && runtime_factory.saw_manifest &&
              runtime_factory.descriptors_valid &&
              runtime_factory.gesture_authority_valid &&
              runtime_factory.live_generation_valid,
          "runtime factory did not receive the exact verified activation");
  require(product->manifest().surface_names ==
              std::vector<std::string>({"bar", "panel", "overlay"}) &&
              product->binding() == grants().binding &&
              ::fcntl(channel::PluginSessionTestAccess::activation_record_fd(
                          *product),
                      F_GETFD) >= 0,
          "product session did not retain its activation authority");

  product->start();
  await([&] { return product->state() == host::SessionState::running; },
        "public product session did not reach running");
  Endpoint bar;
  Endpoint panel;
  Endpoint overlay;
  Endpoint panel_replacement;
  const std::array<std::uint64_t, 1> bar_correlations{501};
  const std::array<std::uint64_t, 1> panel_correlations{502};
  const std::array<std::uint64_t, 1> overlay_correlations{503};
  require(product->attach("bar", bar_correlations, bar) &&
              product->attach("panel", panel_correlations, panel) &&
              product->attach("overlay", overlay_correlations, overlay),
          "public product session did not attach three declared surfaces");
  require(scope->attachments == 1,
          "surface attachment relaunched the sandbox worker");
  require(product->detach("panel", panel) &&
              product->attach("panel", panel_correlations, panel_replacement),
          "surface did not detach and reattach on the existing session");
  require(scope->attachments == 1,
          "surface reattachment relaunched the sandbox worker");

  product->stop();
  await([&] { return product->state() == host::SessionState::stopped; },
        "public product session did not stop");
  require(product->surface_count() == 0 &&
              product->attach("bar", bar_correlations, bar).status ==
                  channel::SurfaceAttachStatus::session_not_running,
          "stopped product session retained or accepted surfaces");
  product.reset();
  await(
      [&] {
    return *runtime_factory.destructions == 1 &&
           runtime_factory.gesture_lifetime.expired();
  },
        "owned broker/provider runtime outlived session teardown");
}

void prepared_session_is_thread_agnostic_before_commit() {
  ActivationFixture fixture;
  RuntimeFactory runtime_factory;
  channel::PluginSessionCreateError create_error{};
  auto prepared = channel::PluginSessionTestAccess::prepare_from_activation(
      launcher::Supervisor::forTestOnly(FAKE_BWRAP_PATH, CHANNEL_PEER_PATH,
                                        std::make_shared<Scope>()),
      fixture.snapshot(), runtime_factory, create_error);
  require(prepared && create_error == channel::PluginSessionCreateError::none &&
              runtime_factory.calls == 1 && *runtime_factory.destructions == 0,
          "side-effect-free session preparation failed");
  const auto destructions = runtime_factory.destructions;
  std::thread discard(
      [prepared = std::move(prepared)]() mutable { prepared.reset(); });
  discard.join();
  require(*destructions == 1,
          "unlaunched prepared channel was not thread-agnostic at discard");
}

void preparation_rejects_invalid_grant_snapshots() {
  ActivationFixture fixture;
  const auto rejected = [&](host::ActivationSnapshot snapshot,
                            std::string_view message) {
    RuntimeFactory runtime_factory;
    channel::PluginSessionCreateError create_error{};
    auto prepared = channel::PluginSessionTestAccess::prepare_from_activation(
        launcher::Supervisor::forTestOnly(FAKE_BWRAP_PATH, CHANNEL_PEER_PATH,
                                          std::make_shared<Scope>()),
        std::move(snapshot), runtime_factory, create_error);
    require(!prepared &&
                create_error ==
                    channel::PluginSessionCreateError::invalid_activation &&
                runtime_factory.calls == 0,
            message);
  };

  auto source_mismatch = fixture.snapshot();
  source_mismatch.grants.source_request_fingerprint =
      permissions::Digest(std::string(64, 'b'));
  rejected(std::move(source_mismatch),
           "manifest/grant source mismatch reached runtime creation");

  auto invalid_requests = fixture.snapshot();
  invalid_requests.grants.requests.push_back({
      .capability = {.id = permissions::CapabilityId("storage.private"),
                     .version = 1},
      .scope = permissions::NoScope{},
      .required = true,
  });
  rejected(std::move(invalid_requests),
           "invalid request set reached runtime creation");

  auto invalid_grants = fixture.snapshot();
  invalid_grants.grants.grants.push_back({
      .capability = {.id = permissions::CapabilityId("audio.play-cue"),
                     .version = 1},
      .scope = token_scope("complete"),
      .state = permissions::GrantState::granted,
      .epoch = 1,
  });
  rejected(std::move(invalid_grants),
           "undeclared grant set reached runtime creation");

  auto policy_mismatch = fixture.snapshot();
  policy_mismatch.grants.binding.policy_fingerprint =
      permissions::Digest(std::string(64, 'c'));
  policy_mismatch.live = std::make_shared<host::LiveGenerationState>(
      policy_mismatch.grants.binding);
  rejected(std::move(policy_mismatch),
           "policy request fingerprint mismatch reached runtime creation");
}


struct BlockingNotificationProbe final {
  std::mutex mutex;
  std::condition_variable changed;
  bool entered = false;
  bool release = false;
  std::size_t calls = 0;
};

class NotificationReleaseGuard final {
public:
  explicit NotificationReleaseGuard(
      std::shared_ptr<BlockingNotificationProbe> probe)
      : probe_(std::move(probe)) {}
  ~NotificationReleaseGuard() {
    {
      std::scoped_lock lock(probe_->mutex);
      probe_->release = true;
    }
    probe_->changed.notify_all();
  }

private:
  std::shared_ptr<BlockingNotificationProbe> probe_;
};

bool blocking_notification(std::string_view category, std::string_view title,
                           std::string_view body, void *context) noexcept {
  auto &probe = *static_cast<BlockingNotificationProbe *>(context);
  std::unique_lock lock(probe.mutex);
  if (category != "timer" || title != "T" || body != "OK")
    return false;
  ++probe.calls;
  probe.entered = true;
  probe.changed.notify_all();
  probe.changed.wait(lock, [&] { return probe.release; });
  return true;
}


class CountingRuntimeHooks final
    : public channel::PluginRuntimeHooks {
public:
  void state_changed(host::SessionState state, host::SessionError error) override {
    if (state == host::SessionState::running &&
        error == host::SessionError::none)
      running.fetch_add(1, std::memory_order_release);
  }
  void control_received(const host::OwnedMessage &) override {}
  void render_rejected(host::RouteResult) override {}
  bool accept(host::AdmittedSurfaceIntent) override {
    intents.fetch_add(1, std::memory_order_release);
    return false;
  }

  std::atomic<int> running = 0;
  std::atomic<int> intents = 0;
};

struct FinalFenceMutation final {
  permissions::ActivationBinding binding;
  std::atomic<int> calls = 0;
};

void invalidate_final_fence(host::AuthorityStore &store,
                            void *opaque) noexcept {
  auto &mutation = *static_cast<FinalFenceMutation *>(opaque);
  mutation.calls.fetch_add(1, std::memory_order_release);
  (void)store.discard_candidate(mutation.binding, UINT64_MAX);
}

void prepared_root_commits_on_ui_with_exact_hooks() {
  CoordinatorFixture fixture;
  fixture.record();
  const auto active = fixture.publish(1, 0, true);
  fixture.promote(active, 1);
  auto scope = std::make_shared<Scope>();
  auto supervisor = [scope] {
    return launcher::Supervisor::forTestOnly(FAKE_BWRAP_PATH,
                                             CHANNEL_PEER_PATH, scope);
  };
  std::unique_ptr<channel::PreparedPluginRuntime> prepared;
  const auto ui_thread = std::this_thread::get_id();
  std::thread::id worker_thread;
  std::thread worker([&] {
    worker_thread = std::this_thread::get_id();
    prepared = fixture.prepare_root({}, std::move(supervisor));
  });
  worker.join();
  require(prepared && worker_thread != ui_thread && scope->attachments == 0,
          "worker preparation launched or failed to remain off the UI thread");
  CountingRuntimeHooks hooks;
  auto root = channel::PluginRuntimeRootTestAccess::commit(
      std::move(prepared), hooks, *QCoreApplication::instance());
  require(root != nullptr &&
              channel::PluginRuntimeRootTestAccess::ui_affine(
                  *root, *QCoreApplication::instance()),
          "prepared runtime did not commit with exact UI QObject affinity");
  await([&] { return hooks.running.load(std::memory_order_acquire) == 1; },
        "prepared runtime did not deliver its exact running Hook");
  require(channel::PluginRuntimeRootTestAccess::hooks_are(*root,
                                                          hooks),
          "prepared runtime commit lost its lifecycle/intent Hook pair");
}

void prepared_root_final_fence_rejects_intervening_mutation() {
  CoordinatorFixture fixture;
  fixture.record();
  const auto active = fixture.publish(1, 0, true);
  fixture.promote(active, 1);
  auto scope = std::make_shared<Scope>();
  FinalFenceMutation mutation{.binding = active.binding};
  auto supervisor = [scope] {
    return launcher::Supervisor::forTestOnly(FAKE_BWRAP_PATH,
                                             CHANNEL_PEER_PATH, scope);
  };
  auto prepared = fixture.prepare_root({}, std::move(supervisor), "current",
                                       ::getuid(), true,
                                       invalidate_final_fence, &mutation);
  CountingRuntimeHooks hooks;
  auto root = channel::PluginRuntimeRootTestAccess::commit(
      std::move(prepared), hooks, *QCoreApplication::instance());
  require(!root && mutation.calls.load(std::memory_order_acquire) == 1 &&
              scope->attachments == 0 &&
              hooks.running.load(std::memory_order_acquire) == 0,
          "intervening authority mutation crossed the final start fence");
}

void prepared_root_commit_is_ui_only_and_path_independent() {
  {
    CoordinatorFixture fixture;
    fixture.record();
    const auto active = fixture.publish(1, 0, true);
    fixture.promote(active, 1);
    auto scope = std::make_shared<Scope>();
    auto supervisor = [scope] {
      return launcher::Supervisor::forTestOnly(FAKE_BWRAP_PATH,
                                               CHANNEL_PEER_PATH, scope);
    };
    auto prepared = fixture.prepare_root({}, std::move(supervisor));
    CountingRuntimeHooks hooks;
    std::unique_ptr<channel::PluginRuntimeRoot> rejected;
    std::thread wrong_thread([&] {
      rejected = channel::PluginRuntimeRootTestAccess::commit(
          std::move(prepared), hooks, *QCoreApplication::instance());
    });
    wrong_thread.join();
    require(!rejected && scope->attachments == 0 &&
                hooks.running.load(std::memory_order_acquire) == 0,
            "off-UI prepared commit launched or retained a runtime");
  }

  CoordinatorFixture fixture;
  fixture.record();
  const auto active = fixture.publish(1, 0, true);
  fixture.promote(active, 1);
  auto scope = std::make_shared<Scope>();
  auto supervisor = [scope] {
    return launcher::Supervisor::forTestOnly(FAKE_BWRAP_PATH,
                                             CHANNEL_PEER_PATH, scope);
  };
  std::unique_ptr<channel::PreparedPluginRuntime> prepared;
  std::thread worker([&] {
    prepared = fixture.prepare_root({}, std::move(supervisor));
  });
  worker.join();
  require(prepared != nullptr && scope->attachments == 0,
          "path-independence worker preparation failed");
  fixture.close_borrowed_roots();
  fixture.corrupt_prepared_backing();
  CountingRuntimeHooks hooks;
  auto root = channel::PluginRuntimeRootTestAccess::commit(
      std::move(prepared), hooks, *QCoreApplication::instance());
  require(root != nullptr,
          "UI commit reread corrupted activation/authority backing paths");
  await([&] { return hooks.running.load(std::memory_order_acquire) == 1; },
        "path-independent UI commit did not start its pinned runtime");
}

void composed_root_is_the_composed_authority_path() {
  using namespace std::chrono_literals;
  CoordinatorFixture fixture("session-notification");
  fixture.record();
  const auto active = fixture.publish(1, 0);
  fixture.promote(active, 1);
  auto probe = std::make_shared<BlockingNotificationProbe>();
  auto prepared = fixture.prepare_root(
      {.context = probe,
       .notification_send = blocking_notification,
       .audio_play = nullptr,
       .compare_scope = nullptr,
       .dynamic_services = {}},
      [] {
        return launcher::Supervisor::forTestOnly(
            FAKE_BWRAP_PATH, CHANNEL_PEER_PATH, std::make_shared<Scope>());
      });
  NotificationReleaseGuard release_on_exit(probe);
  CountingRuntimeHooks hooks;
  auto root = channel::PluginRuntimeRootTestAccess::commit(
      std::move(prepared), hooks, *QCoreApplication::instance());
  require(root != nullptr, "prepared runtime composition did not commit");

  auto locked = fixture.prepare_root(
      {.context = probe,
       .notification_send = blocking_notification,
       .audio_play = nullptr,
       .compare_scope = nullptr,
       .dynamic_services = {}},
      [] {
        return launcher::Supervisor::forTestOnly(
            FAKE_BWRAP_PATH, CHANNEL_PEER_PATH, std::make_shared<Scope>());
      });
  require(!locked, "a second composed root acquired the same authority");
  fixture.close_borrowed_roots();
  {
    std::unique_lock lock(probe->mutex);
    require(probe->changed.wait_for(lock, 2s, [&] { return probe->entered; }),
            "trusted notification provider was not reached");
  }

  const auto initial = channel::PluginRuntimeRootTestAccess::list(*root);
  require(initial && initial->active &&
              initial->active->binding.generation == 1,
          "composed G1 authority was not durable");
  const auto notification = std::ranges::find_if(
      initial->active->grants.values(), [](const auto &grant) {
        return grant.capability.id.view() == "notifications.send";
      });
  require(notification != initial->active->grants.values().end(),
          "optional notification grant missing from composed authority");
  const auto original_live =
      channel::PluginRuntimeRootTestAccess::live_generation(*root);
  require(original_live && original_live->generation() == 1,
          "composed root did not retain exact G1 live authority");
  auto &surface_session = channel::PluginRuntimeRootTestAccess::surface_session(*root);
  const auto g1_surface = surface_session.describe("barWidget");
  require(g1_surface && g1_surface->binding.generation == 1 &&
              g1_surface->key ==
                  surface::SurfaceKey{.id = 1, .generation = 1} &&
              g1_surface->plugin_id == "org.example.status" &&
              g1_surface->surface_name == "barWidget" &&
              !g1_surface->canonical_surfaces.empty() &&
              !surface_session.describe("BarWidget"),
          "root surface port did not expose the exact G1 declaration");
  Endpoint stale_g1_endpoint;
  require(surface_session.attach(*g1_surface, stale_g1_endpoint),
          "G1 surface endpoint did not attach");

  std::atomic<bool> revoke_returned = false;
  channel::PermissionRevokeApplyResult optional;
  std::thread revoker([&] {
    optional = channel::PluginRuntimeRootTestAccess::revoke(
        *root, notification->capability, initial->authority_slots.sequence);
    revoke_returned.store(true, std::memory_order_release);
  });
  const auto fence_deadline = std::chrono::steady_clock::now() + 2s;
  while (original_live->generation() != 0 &&
         std::chrono::steady_clock::now() < fence_deadline)
    std::this_thread::yield();
  const bool fence_closed = original_live->generation() == 0;
  const bool returned_before_release =
      revoke_returned.load(std::memory_order_acquire);
  {
    std::scoped_lock lock(probe->mutex);
    probe->release = true;
  }
  probe->changed.notify_all();
  revoker.join();
  require(fence_closed && !returned_before_release,
          "optional revoke acknowledged before its provider effect drained");
  require(optional.revocation.status ==
                  host::AuthorityMutationResult::applied &&
              optional.revocation.activatable && optional.activation &&
              *optional.activation,
          "optional revoke did not replace the composed session");
  await(
      [&] {
    const auto current =
        channel::PluginRuntimeRootTestAccess::session_binding(*root);
    return current && current->generation == 2;
      },
      "optional revoke did not produce one running G2 session");
  const auto g2_surface = surface_session.describe("barWidget");
  require(g2_surface && g2_surface->binding.generation == 2 &&
              g2_surface->key ==
                  surface::SurfaceKey{.id = 1, .generation = 2} &&
              g2_surface->key != g1_surface->key,
          "replacement session retained the stale surface generation");
  Endpoint endpoint;
  require(surface_session.detach(*g1_surface, stale_g1_endpoint) &&
              surface_session.attach(*g2_surface, endpoint) &&
              surface_session.detach(*g2_surface, endpoint) &&
              !surface_session.detach(*g2_surface, endpoint),
          "root surface port did not own exact attach/detach identity");
  {
    std::scoped_lock lock(probe->mutex);
    require(probe->calls == 1,
            "a notification effect began after revoke acknowledgement");
  }

  const auto replacement = channel::PluginRuntimeRootTestAccess::list(*root);
  require(replacement && replacement->active,
          "G2 authority disappeared after optional revoke");
  const auto storage = std::ranges::find_if(
      replacement->active->grants.values(), [](const auto &grant) {
        return grant.capability.id.view() == "storage.private";
      });
  require(storage != replacement->active->grants.values().end(),
          "required storage grant missing from G2");
  const auto required = channel::PluginRuntimeRootTestAccess::revoke(
      *root, storage->capability, replacement->authority_slots.sequence);
  require(required.revocation.status ==
                  host::AuthorityMutationResult::applied &&
              !required.revocation.activatable && !required.activation &&
              !channel::PluginRuntimeRootTestAccess::session_binding(*root),
          "required revoke left a composed product session running");
}

void composed_root_rejects_unusable_authority_and_providers() {
  CoordinatorFixture bad_fd;
  {
    require(!bad_fd.prepare_root({}, {}, "current", ::getuid(), false),
            "invalid authority descriptor opened a product root");
  }
  {
    require(!bad_fd.prepare_root(
                {}, {}, "current", std::numeric_limits<std::uint32_t>::max()),
            "omitted trusted uid opened a product root");
  }

  {
    CoordinatorFixture wrong_record;
    wrong_record.record();
    require(!wrong_record.prepare_root({}, {}, "../current"),
            "non-canonical fixed activation record prepared a runtime");
  }

  CoordinatorFixture missing_provider("session-notification");
  missing_provider.record();
  const auto active = missing_provider.publish(1, 0);
  missing_provider.promote(active, 1);
  auto scope = std::make_shared<Scope>();
  auto rejected = missing_provider.prepare_root(
      {}, [scope] {
        return launcher::Supervisor::forTestOnly(FAKE_BWRAP_PATH,
                                                 CHANNEL_PEER_PATH, scope);
      });
  require(!rejected && scope->attachments == 0,
          "granted optional permission bypassed its missing trusted provider");
}



void failed_session_rejects_surfaces() {
  auto identity = token();
  auto revision = grants();
  auto live = std::make_shared<host::LiveGenerationState>(revision.binding);
  auto channel_state = std::make_shared<ChannelState>();
  channel_state->launch_error = host::ChannelError::launch_failed;
  manifest::ManifestV2 verified_manifest;
  verified_manifest.id = identity.plugin_id;
  verified_manifest.surface_names = {"bar"};
  auto prepared = channel::PluginSessionTestAccess::prepare_from_parts(
      identity, std::move(verified_manifest), std::move(revision), live,
      std::make_unique<FakeChannel>(channel_state));
  channel::PluginSessionCreateError create_error{};
  auto product = channel::PluginSessionTestAccess::commit(
      std::move(prepared), create_error);
  require(product && create_error == channel::PluginSessionCreateError::none,
          "failed-channel prepared session did not commit");
  product->start();
  await([&] { return product->state() == host::SessionState::failed; },
        "failed product channel did not fail its session");
  Endpoint endpoint;
  const std::array<std::uint64_t, 1> correlations{101};
  require(product->attach("bar", correlations, endpoint).status ==
              channel::SurfaceAttachStatus::session_not_running,
          "failed session accepted a surface");
  product.reset();
  await([&] { return channel_state->destructions == 1; },
        "failed session worker was not reaped before test teardown");
  QCoreApplication::sendPostedEvents(nullptr, QEvent::DeferredDelete);
  QCoreApplication::processEvents(QEventLoop::AllEvents, 10);
}

} // namespace

int main(int argc, char **argv) {
  QCoreApplication application(argc, argv);
  try {
    if (argc == 2 &&
        std::string_view(argv[1]) == "--session-runtime-factory-only") {
      session_runtime_factory_tests();
      std::cout << "session runtime factory tests passed\n";
      return 0;
    }
    if (argc == 2 && std::string_view(argv[1]) == "--composed-root-only") {
      composed_root_is_the_composed_authority_path();
      composed_root_rejects_unusable_authority_and_providers();
      prepared_root_commits_on_ui_with_exact_hooks();
      prepared_root_final_fence_rejects_intervening_mutation();
      prepared_root_commit_is_ui_only_and_path_independent();
      std::cout << "composed root tests passed\n";
      return 0;
    }
    if (argc == 2 && std::string_view(argv[1]) == "--prepared-session-only") {
      prepared_session_is_thread_agnostic_before_commit();
      std::cout << "prepared session test passed\n";
      return 0;
    }
    product_session_routes_two_surfaces_over_one_launch();
    effect_time_revocation_fences_an_authenticated_request();
    shared_gesture_authority_has_one_concurrent_winner();
    product_session_intercepts_gesture_intents_before_render_routing();
    preparation_rejects_invalid_grant_snapshots();
    prepared_commit_retains_activation_and_reuses_one_launch();
    prepared_session_is_thread_agnostic_before_commit();
    composed_root_is_the_composed_authority_path();
    composed_root_rejects_unusable_authority_and_providers();
    prepared_root_commits_on_ui_with_exact_hooks();
    prepared_root_final_fence_rejects_intervening_mutation();
    prepared_root_commit_is_ui_only_and_path_independent();
    session_runtime_factory_tests();
    failed_session_rejects_surfaces();
  } catch (const std::exception &error) {
    std::cerr << "FAIL: " << error.what() << '\n';
    return 1;
  }
  std::cout << "plugin product session tests passed\n";
  return 0;
}
