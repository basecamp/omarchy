#include "authenticated_session_channel.hpp"

#include "structured_broker.hpp"
#include "audit_store.hpp"
#include "omarchy/plugin_runtime/surface/render_messages.hpp"

#include <QCoreApplication>
#include <QEventLoop>

#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

#include <algorithm>
#include <array>
#include <atomic>
#include <chrono>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <memory>
#include <optional>
#include <stdexcept>
#include <string>
#include <string_view>
#include <thread>
#include <utility>
#include <vector>

namespace audit = omarchy::plugins::audit;
namespace channel = omarchy::plugin_runtime::channel;
namespace definitions = omarchy::plugins::definitions;
namespace launcher = omarchy::plugin_runtime::launcher;
namespace permissions = omarchy::plugins::permissions;
namespace policy = omarchy::plugin_runtime::policy;
namespace providers = omarchy::plugin_runtime::providers;
namespace runtime = omarchy::plugin_runtime::runtime;
namespace sandbox = omarchy::plugin_runtime::sandbox;
namespace session = omarchy::plugin_runtime::host_session;
namespace surface = omarchy::plugin_runtime::surface;
namespace wire = omarchy::plugin::wire;

namespace {
using namespace std::chrono_literals;

void require(bool condition, std::string_view message) {
  if (!condition)
    throw std::runtime_error(std::string(message));
}

template <typename Predicate>
bool await(Predicate predicate, std::chrono::milliseconds timeout = 5s) {
  const auto deadline = std::chrono::steady_clock::now() + timeout;
  while (!predicate() && std::chrono::steady_clock::now() < deadline) {
    QCoreApplication::processEvents(QEventLoop::AllEvents, 10);
    std::this_thread::yield();
  }
  QCoreApplication::processEvents(QEventLoop::AllEvents, 10);
  return predicate();
}

permissions::Digest digest(char value) {
  return permissions::Digest(std::string(64, value));
}

permissions::TokenScope tokens() {
  permissions::TokenScope value;
  require(value.tokens.insert(permissions::ScopeToken("timer")),
          "duplicate audio token");
  return value;
}

policy::GrantSnapshot snapshot() {
  policy::GrantSnapshot value;
  const permissions::CapabilityKey audio{
      .id = permissions::CapabilityId("audio.play-cue"), .version = 1};
  const permissions::CapabilityKey storage{
      .id = permissions::CapabilityId("storage.private"), .version = 1};
  value.binding = {.plugin = permissions::PluginId("org.omarchy_d1"),
                   .revision = digest('d'),
                   .policy_fingerprint = digest('e'),
                   .generation = 47};
  value.requests.push_back(
      {.capability = audio, .scope = tokens(), .required = true});
  value.requests.push_back({.capability = storage,
                            .scope = permissions::QuotaScope{4096, 4096},
                            .required = true});
  value.binding.policy_fingerprint = permissions::Digest(
      permissions::policy_request_fingerprint(value.requests));
  value.grants.push_back({.capability = audio,
                          .scope = tokens(),
                          .state = permissions::GrantState::granted,
                          .epoch = 1});
  value.grants.push_back({.capability = storage,
                          .scope = permissions::QuotaScope{4096, 4096},
                          .state = permissions::GrantState::granted,
                          .epoch = 1});
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
                      launcher::Deadline deadline, std::string &) override {
    require(monitor_pid > 0 && worker_pid > 0 &&
                deadline > std::chrono::steady_clock::now() &&
                plan.worker_descriptors == std::vector<int>({3, 4, 5}),
            "resource scope received an invalid launch");
    name = unit;
    attached = true;
    return {.attached = true, .cleanup_required = true};
  }
  void kill(std::string_view unit, launcher::Deadline) noexcept override {
    if (unit == name)
      ++kills;
  }
  void remove(std::string_view unit, launcher::Deadline) noexcept override {
    if (unit == name)
      ++removes;
  }

  std::string name;
  bool attached = false;
  std::atomic<unsigned> kills = 0;
  std::atomic<unsigned> removes = 0;
};

class UnreachableDispatcher final : public channel::BrokerDispatcher {
public:
  bool
  accepts(const launcher::LaunchIdentity &identity) const noexcept override {
    return identity.plugin_id == "org.omarchy_d1" &&
           identity.revision_sha256 == std::string(64, 'd') &&
           identity.generation == 47;
  }
  bool dispatch(const wire::PacketView &) override {
    ++dispatches;
    return false;
  }
  std::optional<channel::BrokerReply> take_reply() override {
    ++replies;
    return {};
  }

  std::atomic<unsigned> dispatches = 0;
  std::atomic<unsigned> replies = 0;
};

class Generation final : public channel::GenerationAuthority {
public:
  bool
  is_current(const launcher::LaunchIdentity &identity) const noexcept override {
    return identity.plugin_id == "org.omarchy_d1" &&
           identity.revision_sha256 == std::string(64, 'd') &&
           identity.generation == 47;
  }
};

class Dispatch final : public session::DispatchAuthority {
  class Lease final : public session::DispatchAuthorityLease {
    bool current_at_effect() const noexcept override { return true; }
  };

public:
  std::unique_ptr<session::DispatchAuthorityLease>
  acquire(const permissions::ActivationBinding &, std::uint64_t,
          const wire::PacketView &) override {
    return std::make_unique<Lease>();
  }
  bool fence_builtin(const policy::Revocation &) noexcept override {
    return true;
  }
  bool
  fence_dynamic(const definitions::DynamicRevisionGrant &) noexcept override {
    return true;
  }
};

struct AudioProbe {
  static bool play(std::string_view cue, void *context) noexcept {
    auto &value = *static_cast<AudioProbe *>(context);
    ++value.calls;
    return cue == "timer";
  }
  std::atomic<unsigned> calls = 0;
};

struct StorageProbe {
  static bool read(std::string_view key, std::span<std::byte> output,
                   std::size_t &written, bool &found, void *context) noexcept {
    auto &value = *static_cast<StorageProbe *>(context);
    ++value.calls;
    if (key != "pressure" || output.size() != 4096)
      return false;
    std::fill(output.begin(), output.end(), std::byte{0x5a});
    written = output.size();
    found = true;
    return true;
  }
  std::atomic<unsigned> calls = 0;
};

struct DeadlineProbe {
  static bool read(std::string_view, std::span<std::byte>, std::size_t &,
                   bool &, void *context) noexcept {
    auto &value = *static_cast<DeadlineProbe *>(context);
    ++value.invocations;
    std::this_thread::sleep_for(25ms);
    return false;
  }

  std::atomic<unsigned> invocations = 0;
};

class Observer final : public session::SessionObserver {
public:
  void state_changed(session::SessionState state,
                     session::SessionError error) override {
    states.emplace_back(state, error);
  }
  void message_received(session::OwnedMessage message) override {
    messages.push_back(std::move(message));
  }

  std::vector<std::pair<session::SessionState, session::SessionError>> states;
  std::vector<session::OwnedMessage> messages;
};

class RevisionFixture final {
public:
  explicit RevisionFixture(std::string_view mode) {
    std::string pattern = "/tmp/omarchy-session-integration-XXXXXX";
    const char *created = mkdtemp(pattern.data());
    require(created != nullptr, "cannot create session fixture root");
    root_ = created;
    revision_ = root_ / "revision";
    state_ = root_ / "state";
    std::filesystem::create_directories(revision_);
    std::filesystem::create_directories(state_);
    std::ofstream(revision_ / "d1-mode") << mode << '\n';
    require(chmod((revision_ / "d1-mode").c_str(), 0444) == 0 &&
                chmod(revision_.c_str(), 0555) == 0,
            "cannot make session revision immutable");
    revision_fd_ = open(revision_.c_str(), O_RDONLY | O_DIRECTORY | O_CLOEXEC);
    state_fd_ = open(state_.c_str(), O_RDONLY | O_DIRECTORY | O_CLOEXEC);
    require(revision_fd_ >= 0 && state_fd_ >= 0,
            "cannot open session fixture descriptors");
  }

  ~RevisionFixture() {
    if (revision_fd_ >= 0)
      close(revision_fd_);
    if (state_fd_ >= 0)
      close(state_fd_);
    static_cast<void>(chmod(revision_.c_str(), 0755));
    std::error_code ignored;
    std::filesystem::remove_all(root_, ignored);
  }

  session::OwnedFd take_revision() {
    return session::OwnedFd(std::exchange(revision_fd_, -1));
  }
  session::OwnedFd take_state() {
    return session::OwnedFd(std::exchange(state_fd_, -1));
  }

private:
  std::filesystem::path root_;
  std::filesystem::path revision_;
  std::filesystem::path state_;
  int revision_fd_ = -1;
  int state_fd_ = -1;
};

std::vector<permissions::AuditRecord>
audit_records(audit::BoundedAuditLog &log, permissions::AuditEvent event) {
  const auto result =
      log.query({.plugin = std::nullopt,
                 .event = event,
                 .maximum_results = audit::kHardMaximumRecords});
  require(result.status.ok(), "broker audit query failed");
  return result.records;
}

void require_audit_record(
    const permissions::AuditRecord &record,
    const permissions::ActivationBinding &binding, std::uint64_t correlation,
    permissions::OperationId operation, std::string_view capability,
    permissions::AuditOutcome outcome = permissions::AuditOutcome::allowed,
    permissions::GrantDecisionCode decision =
        permissions::GrantDecisionCode::allowed) {
  require(
      record.producer == permissions::AuditProducer::broker &&
          record.outcome == outcome && record.plugin == binding.plugin &&
          record.revision == binding.revision &&
          record.generation == binding.generation &&
          record.correlation == correlation && record.operation == operation &&
          record.capability ==
              permissions::CapabilityKey{
                  .id = permissions::CapabilityId(capability), .version = 1} &&
          record.decision == decision,
      "broker audit identity was not exact");
}

std::optional<surface::FrameReady> rendered_frame(const Observer &observer) {
  for (const auto &message : observer.messages) {
    if (message.lane != session::ChannelLane::render)
      continue;
    surface::FrameReady frame{};
    require(surface::decode_frame_ready(message.payload, frame),
            "observer received an invalid frame-ready payload");
    return frame;
  }
  return std::nullopt;
}

void require_dispatcher_unreached(const UnreachableDispatcher &dispatcher) {
  require(dispatcher.dispatches.load() == 0 && dispatcher.replies.load() == 0,
          "transport dispatcher handled an authenticated session request");
}

bool has_visible_lanes(const Observer &observer) {
  bool control = false;
  bool render = false;
  for (const auto &message : observer.messages) {
    if (message.lane == session::ChannelLane::broker)
      return false;
    control = control || message.lane == session::ChannelLane::control;
    render = render || message.lane == session::ChannelLane::render;
  }
  return control && render;
}

void require_visible_lanes(const Observer &observer) {
  require(has_visible_lanes(observer),
          "visible lanes were missing or broker traffic was published");
}

session::OwnedMessage pressure_control(const session::SessionToken &token,
                                       std::uint64_t sequence,
                                       std::byte payload) {
  return {.token = token,
          .lane = session::ChannelLane::control,
          .message_type = wire::kPermissionSnapshotMessage,
          .correlation_id = 0,
          .sequence = sequence,
          .payload = {payload},
          .descriptors = {}};
}

void require_pressure_messages(const Observer &observer,
                               const session::SessionToken &token,
                               std::uint64_t sent, bool final_ack) {
  unsigned selection_acks = 0;
  unsigned permission_acks = 0;
  unsigned renders = 0;
  std::array<bool, 4> sequences{};
  for (const auto &message : observer.messages) {
    require(message.token == token && message.descriptors.empty() &&
                message.lane != session::ChannelLane::broker,
            "pressure message identity was inexact or broker traffic was "
            "published");
    require(message.sequence > 0 &&
                message.sequence <= observer.messages.size() &&
                !sequences[message.sequence],
            "pressure observer sequence was not exact");
    sequences[message.sequence] = true;
    if (message.lane == session::ChannelLane::control) {
      require(message.payload.empty() && message.correlation_id == 0,
              "pressure control acknowledgement was not exact");
      if (message.message_type == wire::kSurfaceSelectionAcceptedMessage)
        ++selection_acks;
      else if (message.message_type ==
                   wire::kPermissionSnapshotAcceptedMessage &&
               message.sequence == 3)
        ++permission_acks;
      else
        require(false, "pressure observer received an unexpected control type");
      continue;
    }
    require(message.lane == session::ChannelLane::render,
            "pressure observer received an unexpected lane");
    surface::FrameReady frame{};
    require(
        message.message_type == static_cast<std::uint16_t>(
                                    surface::RenderMessageType::frame_ready) &&
            surface::decode_frame_ready(message.payload, frame) &&
            frame.surface == surface::SurfaceKey{.id = 1, .generation = 1} &&
            frame.slot == 0 && frame.slot_sequence == 2 &&
            frame.frame_sequence == sent && message.correlation_id == 0,
        "pressure frame-ready message was not exact");
    ++renders;
  }
  require(selection_acks == 1 && renders == 1 &&
              permission_acks == (final_ack ? 1U : 0U) &&
              observer.messages.size() == (final_ack ? 3U : 2U),
          "pressure observer message set was not exact");
}

std::optional<unsigned> await_stable_effects(std::atomic<unsigned> &calls) {
  const auto deadline = std::chrono::steady_clock::now() + 5s;
  while (std::chrono::steady_clock::now() < deadline) {
    const auto candidate = calls.load();
    if (candidate == 0) {
      QCoreApplication::processEvents(QEventLoop::AllEvents, 10);
      continue;
    }
    const auto stable_until = std::chrono::steady_clock::now() + 200ms;
    while (calls.load() == candidate &&
           std::chrono::steady_clock::now() < stable_until)
      QCoreApplication::processEvents(QEventLoop::AllEvents, 10);
    if (calls.load() == candidate)
      return candidate;
  }
  return std::nullopt;
}

int run_case(std::string bwrap, std::string_view mode) {
  constexpr std::uint64_t nonce = 19;
  RevisionFixture files(mode);
  auto scope = std::make_shared<Scope>();
  auto unreachable_dispatcher = std::make_shared<UnreachableDispatcher>();
  auto generation = std::make_shared<Generation>();
  audit::BoundedAuditLog log(4096);
  auto grants = snapshot();
  AudioProbe audio;
  StorageProbe storage;
  DeadlineProbe deadline;
  const auto deadline_mode = mode == "session-deadline";
  runtime::AuditedBrokerRuntime builtin(
      grants,
      providers::ProviderConfiguration{
          .storage = {.read = deadline_mode ? DeadlineProbe::read
                                            : StorageProbe::read,
                      .context = deadline_mode ? static_cast<void *>(&deadline)
                                               : static_cast<void *>(&storage),
                      .maximum_total_bytes = 4096,
                      .maximum_item_bytes = 4096},
          .notification = {},
          .audio = {.play = AudioProbe::play, .context = &audio}},
      log);
  definitions::TrustedDefinitionRegistry registry;
  runtime::DynamicBrokerRuntime dynamic(registry, {}, log);
  Dispatch dispatch;
  auto broker = std::make_unique<session::StructuredBroker>(
      grants.binding, nonce, builtin, dynamic, dispatch);
  auto supervisor = launcher::Supervisor::forTestOnly(std::move(bwrap),
                                                      CHANNEL_PEER_PATH, scope);
  channel::AuthenticatedSessionLaunch launch{
      .binding = grants.binding,
      .revision_directory = files.take_revision(),
      .private_state_directory = files.take_state()};
  auto authenticated = std::make_unique<channel::AuthenticatedSessionChannel>(
      std::move(supervisor), std::move(launch), unreachable_dispatcher,
      generation,
      std::move(broker));
  const session::SessionToken token{
      .plugin_id = std::string(grants.binding.plugin.view()),
      .revision_sha256 = std::string(grants.binding.revision.view()),
      .generation = grants.binding.generation,
      .session_nonce = nonce};
  auto clock = std::make_shared<session::SteadySessionClock>();
  Observer observer;
  session::SessionLimits limits;
  if (deadline_mode)
    limits.io_timeout = 5ms;
  session::PluginSessionIo value(token, std::move(authenticated), clock,
                                 &observer, limits);
  try {
    value.start();
    const bool started = await([&] {
      return value.state() == session::SessionState::running ||
             value.state() == session::SessionState::failed;
    });
    if (!started || value.state() != session::SessionState::running) {
      throw std::runtime_error(
          "authenticated session did not start (state=" +
          std::to_string(static_cast<unsigned>(value.state())) + ", error=" +
          std::to_string(static_cast<unsigned>(value.error())) + ")");
    }
    if (mode == "session-replay") {
      require(
          await([&] { return value.state() == session::SessionState::failed; }),
          "replayed broker request did not fail the session");
      require(
          audio.calls.load() == 1 &&
              audit_records(log, permissions::AuditEvent::operation_decided)
                      .size() == 1 &&
              audit_records(log, permissions::AuditEvent::operation_completed)
                      .size() == 1,
          "replay caused a second broker effect or audit");
    } else if (mode == "session-pressure" ||
               mode == "session-revoke-pressure") {
      const auto stable_effects = await_stable_effects(storage.calls);
      require(stable_effects.has_value(),
              "pressure fixture did not establish blocked broker effects");
      if (mode == "session-revoke-pressure") {
        value.revoke();
        require(!value.enqueue(pressure_control(token, 1, std::byte{1})),
                "revoked session did not synchronously close admission");
        require(await([&] {
                  return value.state() == session::SessionState::revoked &&
                         scope->removes.load() == 1;
                }),
                "revoked pressure session did not finish cleanup");
        const auto effects_at_fence = *stable_effects;
        QCoreApplication::processEvents(QEventLoop::AllEvents, 50);
        require(storage.calls.load() == effects_at_fence &&
                    observer.messages.empty(),
                "broker work or visible messages crossed the revoke fence");
        require(observer.states ==
                        std::vector<std::pair<session::SessionState,
                                              session::SessionError>>{
                            {session::SessionState::starting,
                             session::SessionError::none},
                            {session::SessionState::running,
                             session::SessionError::none},
                            {session::SessionState::revoking,
                             session::SessionError::none},
                            {session::SessionState::revoked,
                             session::SessionError::none}} &&
                    scope->kills.load() == 1 && scope->attached,
                "revoked pressure session state or cleanup was not exact");
        const auto decided =
            audit_records(log, permissions::AuditEvent::operation_decided);
        const auto completed =
            audit_records(log, permissions::AuditEvent::operation_completed);
        require(decided.size() == effects_at_fence &&
                    completed.size() == effects_at_fence,
                "revoke did not settle every invoked operation exactly once");
        unsigned cancelled = 0;
        for (std::size_t index = 0; index < completed.size(); ++index) {
          require_audit_record(decided[index], grants.binding, index + 1,
                               permissions::OperationId::storage_read,
                               "storage.private");
          const auto outcome = completed[index].outcome;
          if (outcome == permissions::AuditOutcome::cancelled) {
            ++cancelled;
            require_audit_record(
                completed[index], grants.binding, index + 1,
                permissions::OperationId::storage_read, "storage.private",
                permissions::AuditOutcome::cancelled,
                permissions::GrantDecisionCode::activation_mismatch);
          } else {
            require_audit_record(completed[index], grants.binding, index + 1,
                                 permissions::OperationId::storage_read,
                                 "storage.private");
          }
        }
        require(
            cancelled == 1,
            "revoke did not cancel the one pending transaction exactly once");
        require_dispatcher_unreached(*unreachable_dispatcher);
        return 0;
      }
      require(value.enqueue(pressure_control(token, 1, std::byte{1})),
              "pressure visible-lane trigger was rejected");
      require(await([&] { return observer.messages.size() == 2; }),
              "pressure session did not deliver triggered visible lanes");
      require(storage.calls.load() == *stable_effects,
              "broker effects advanced before reply draining was authorized");
      const auto frame = rendered_frame(observer);
      require(frame && frame->frame_sequence >= 8 &&
                  *stable_effects < frame->frame_sequence,
              "pressure fixture did not reach bounded broker backpressure");
      const auto sent = frame->frame_sequence;
      require_pressure_messages(observer, token, sent, false);
      require(value.enqueue(pressure_control(token, 2, std::byte{2})),
              "pressure broker-drain trigger was rejected");
      require(await(
                  [&] {
                    return storage.calls.load() == sent &&
                           observer.messages.size() == 3;
                  },
                  15s),
              "pressure broker replies did not drain to an exact final ack");
      require_pressure_messages(observer, token, sent, true);
    } else if (mode == "session-deadline") {
      require(
          await([&] { return value.state() == session::SessionState::failed; }),
          "aggregate I/O deadline did not fail the authenticated session");
      require(value.error() == session::SessionError::io_deadline_expired &&
                  deadline.invocations.load() == 1 &&
                  observer.messages.empty(),
              "deadline failure published the slow provider result");
      require(await([&] { return scope->removes.load() == 1; }) &&
                  scope->kills.load() == 1 && scope->attached,
              "deadline failure cleanup was not exact");
      const auto decided =
          audit_records(log, permissions::AuditEvent::operation_decided);
      const auto completed =
          audit_records(log, permissions::AuditEvent::operation_completed);
      require(decided.size() == 1 && completed.size() == 1,
              "deadline failure did not settle its transaction exactly once");
      require_audit_record(decided.front(), grants.binding, 1,
                           permissions::OperationId::storage_read,
                           "storage.private");
      require_audit_record(completed.front(), grants.binding, 1,
                           permissions::OperationId::storage_read,
                           "storage.private",
                           permissions::AuditOutcome::cancelled,
                           permissions::GrantDecisionCode::activation_mismatch);
      require(
          observer.states ==
              std::vector<
                  std::pair<session::SessionState, session::SessionError>>{
                  {session::SessionState::starting,
                   session::SessionError::none},
                  {session::SessionState::running, session::SessionError::none},
                  {session::SessionState::failed,
                   session::SessionError::io_deadline_expired}},
          "deadline observer state sequence was not exact");
      require_dispatcher_unreached(*unreachable_dispatcher);
      return 0;
    } else {
      require(
          await([&] {
            return audio.calls.load() == 1 && observer.messages.size() == 2;
          }),
          "authenticated session did not deliver its effect and visible lanes");
      require_visible_lanes(observer);
      const auto frame = rendered_frame(observer);
      require(frame &&
                  frame->surface ==
                      surface::SurfaceKey{.id = 1, .generation = 1} &&
                  frame->slot == 0 && frame->slot_sequence == 2 &&
                  frame->frame_sequence == 1,
              "happy frame-ready semantics changed");
    }
    require_dispatcher_unreached(*unreachable_dispatcher);
    if (value.state() == session::SessionState::failed) {
      const auto decided =
          audit_records(log, permissions::AuditEvent::operation_decided);
      const auto completed =
          audit_records(log, permissions::AuditEvent::operation_completed);
      require(decided.size() == 1 && completed.size() == 1,
              "replay changed exact broker audit counts");
      require_audit_record(decided.front(), grants.binding, 1,
                           permissions::OperationId::audio_play_cue,
                           "audio.play-cue");
      require_audit_record(completed.front(), grants.binding, 1,
                           permissions::OperationId::audio_play_cue,
                           "audio.play-cue");
      require(
          await([&] { return observer.states.size() == 3; }) &&
              observer.states[0] == std::pair{session::SessionState::starting,
                                              session::SessionError::none} &&
              observer.states[1] == std::pair{session::SessionState::running,
                                              session::SessionError::none} &&
              observer.states[2].first == session::SessionState::failed &&
              observer.states[2].second ==
                  session::SessionError::channel_failed,
          "failed observer state sequence was not exact");
      require(await([&] { return scope->removes.load() == 1; }),
              "failed session sandbox cleanup did not finish");
      require(scope->kills.load() == 1 && scope->attached,
              "failed session sandbox cleanup was not exact");
      return 0;
    }
    value.stop();
    require(
        await([&] { return value.state() == session::SessionState::stopped; }),
        "authenticated session did not stop");
    require(await([&] { return observer.states.size() == 4; }) &&
                observer.states[0] == std::pair{session::SessionState::starting,
                                                session::SessionError::none} &&
                observer.states[1] == std::pair{session::SessionState::running,
                                                session::SessionError::none} &&
                observer.states[2] == std::pair{session::SessionState::stopping,
                                                session::SessionError::none} &&
                observer.states[3] == std::pair{session::SessionState::stopped,
                                                session::SessionError::none},
            "stopped observer state sequence was not exact");
    require(await([&] { return scope->removes.load() == 1; }) &&
                scope->kills.load() == 1 && scope->attached,
            "authenticated session sandbox cleanup was not exact");
    const auto decided =
        audit_records(log, permissions::AuditEvent::operation_decided);
    const auto completed =
        audit_records(log, permissions::AuditEvent::operation_completed);
    const auto pressure = mode == "session-pressure";
    const auto effects = pressure ? storage.calls.load() : audio.calls.load();
    require(decided.size() == effects && completed.size() == effects,
            "broker audits did not match exact provider effects");
    for (std::size_t index = 0; index < completed.size(); ++index) {
      const auto operation = pressure
                                 ? permissions::OperationId::storage_read
                                 : permissions::OperationId::audio_play_cue;
      const std::string_view capability =
          pressure ? "storage.private" : "audio.play-cue";
      require_audit_record(decided[index], grants.binding, index + 1, operation,
                           capability);
      require_audit_record(completed[index], grants.binding, index + 1,
                           operation, capability);
    }
    return 0;
  } catch (...) {
    value.stop();
    (void)await(
        [&] {
          const auto state = value.state();
          const bool terminal = state == session::SessionState::stopped ||
                                state == session::SessionState::failed ||
                                state == session::SessionState::revoked;
          return terminal && scope->removes.load() == 1;
        },
        5s);
    throw;
  }
}
} // namespace

int main(int argc, char **argv) {
  QCoreApplication application(argc, argv);
  try {
    require(argc == 2, "expected fake or bwrap suite selector");
    const auto run_modes = [](std::string_view launcher_path, auto modes) {
      for (const auto mode : modes) {
        try {
          require(run_case(std::string(launcher_path), mode) == 0,
                  "authenticated session case failed");
        } catch (const std::exception &error) {
          throw std::runtime_error(std::string(mode) + ": " + error.what());
        }
      }
    };
    if (std::string_view(argv[1]) == "fake") {
      run_modes(FAKE_BWRAP_PATH,
                std::array{"session-happy", "session-replay",
                           "session-pressure", "session-revoke-pressure",
                           "session-deadline"});
      return 0;
    }
    if (std::string_view(argv[1]) == "bwrap") {
      if (access(BWRAP_PATH, X_OK) < 0)
        return 77;
      run_modes(BWRAP_PATH,
                std::array{"session-happy", "session-replay",
                           "session-pressure", "session-revoke-pressure",
                           "session-deadline"});
      return 0;
    }
    throw std::runtime_error("unknown suite selector");
  } catch (const std::exception &error) {
    std::cerr << "authenticated session integration failed: " << error.what()
              << '\n';
    return 1;
  }
}
