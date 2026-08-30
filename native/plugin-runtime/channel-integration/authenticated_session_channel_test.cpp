#ifndef OMARCHY_AUTHENTICATED_SESSION_CHANNEL_TESTING
#error "adapter test seam must not be compiled into production"
#endif

#include "authenticated_session_channel.hpp"
#include "authenticated_session_backend_p.hpp"

#include <QCoreApplication>
#include <QEventLoop>

#include <fcntl.h>
#include <unistd.h>

#include <algorithm>
#include <chrono>
#include <condition_variable>
#include <deque>
#include <iostream>
#include <mutex>
#include <stdexcept>
#include <string_view>
#include <thread>

namespace {

namespace channel = omarchy::plugin_runtime::channel;
namespace launcher = omarchy::plugin_runtime::launcher;
namespace session = omarchy::plugin_runtime::host_session;
namespace wire = omarchy::plugin::wire;

using namespace std::chrono_literals;

static_assert(!std::is_copy_constructible_v<channel::AuthenticatedSessionChannel> &&
              !std::is_move_constructible_v<channel::AuthenticatedSessionChannel>);
static_assert(!std::is_copy_constructible_v<channel::AuthenticatedMessage> &&
              std::is_move_constructible_v<channel::AuthenticatedMessage>);

void require(bool condition, std::string_view message) {
  if (!condition)
    throw std::runtime_error(std::string(message));
}

template <typename Predicate>
void await(Predicate predicate, std::string_view message) {
  const auto deadline = std::chrono::steady_clock::now() + 2s;
  while (!predicate() && std::chrono::steady_clock::now() < deadline) {
    QCoreApplication::processEvents(QEventLoop::AllEvents, 10);
    std::this_thread::yield();
  }
  require(predicate(), message);
}

session::SessionToken token(std::uint64_t nonce = 17) {
  return {.plugin_id = "org.omarchy.adapter-fixture",
          .revision_sha256 = std::string(64, 'b'),
          .generation = 9,
          .session_nonce = nonce};
}

struct BackendState final {
  BackendState() {
    require(::pipe2(readiness, O_CLOEXEC | O_NONBLOCK) == 0,
            "readiness pipe creation failed");
  }
  ~BackendState() {
    ::close(readiness[0]);
    ::close(readiness[1]);
  }

  void signal(unsigned count = 1) {
    std::vector<std::byte> bytes(count, std::byte{1});
    require(::write(readiness[1], bytes.data(), bytes.size()) ==
                static_cast<ssize_t>(bytes.size()),
            "readiness signal failed");
  }

  std::mutex mutex;
  std::condition_variable condition;
  int readiness[2]{-1, -1};
  std::deque<channel::AuthenticatedReceiveResult> incoming;
  std::deque<session::SendStatus> send_results;
  std::vector<launcher::Deadline> deadlines;
  std::vector<std::thread::id> operation_threads;
  std::size_t sent_descriptor_count = 0;
  bool sent_descriptors_valid = true;
  std::vector<std::byte> prepared_payload;
  session::SessionToken launched_token;
  wire::EndpointRole prepared_role = wire::EndpointRole::control;
  std::uint16_t prepared_type = 0;
  std::uint64_t prepared_correlation = 0;
  std::size_t prepared_descriptor_count = 0;
  std::size_t prepare_count = 0;
  std::size_t send_count = 0;
  std::size_t receive_count = 0;
  std::size_t arm_count = 0;
  std::size_t terminate_count = 0;
  int readiness_override = -2;
  launcher::EndpointMask last_reads = launcher::EndpointMask::none;
  launcher::EndpointMask last_writes = launcher::EndpointMask::none;
  launcher::Deadline launch_deadline{};
  launcher::Deadline handshake_deadline{};
  launcher::Deadline terminate_deadline{};
  bool prepared = false;
  bool block_receive = false;
  bool receive_entered = false;
  bool release_receive = false;
  bool expire_launch = false;
  bool expire_handshake = false;
  bool expire_receive = false;
};

class FakeBackend final : public channel::AuthenticatedSessionBackend {
public:
  explicit FakeBackend(std::shared_ptr<BackendState> state)
      : state_(std::move(state)) {}

  session::ChannelError launch(const session::SessionToken &identity,
                               launcher::Deadline deadline) override {
    if (state_->expire_launch)
      while (std::chrono::steady_clock::now() < deadline) {
      }
    std::lock_guard lock(state_->mutex);
    state_->launched_token = identity;
    state_->launch_deadline = deadline;
    state_->operation_threads.push_back(std::this_thread::get_id());
    return session::ChannelError::none;
  }

  session::ChannelError handshake(launcher::Deadline deadline) override {
    if (state_->expire_handshake)
      while (std::chrono::steady_clock::now() < deadline) {
      }
    std::lock_guard lock(state_->mutex);
    state_->handshake_deadline = deadline;
    state_->operation_threads.push_back(std::this_thread::get_id());
    return session::ChannelError::none;
  }

  bool prepare(wire::EndpointRole role, std::uint16_t type,
               std::uint64_t correlation, std::span<const std::byte> payload,
               std::size_t descriptors) override {
    std::lock_guard lock(state_->mutex);
    if (state_->prepared)
      return false;
    state_->prepared = true;
    ++state_->prepare_count;
    state_->prepared_role = role;
    state_->prepared_type = type;
    state_->prepared_correlation = correlation;
    state_->prepared_payload.assign(payload.begin(), payload.end());
    state_->prepared_descriptor_count = descriptors;
    return true;
  }

  session::SendStatus
  try_send(std::span<const int> descriptors,
           launcher::Deadline deadline) override {
    std::lock_guard lock(state_->mutex);
    state_->deadlines.push_back(deadline);
    state_->sent_descriptor_count = descriptors.size();
    state_->sent_descriptors_valid = std::all_of(
        descriptors.begin(), descriptors.end(),
        [](int descriptor) { return ::fcntl(descriptor, F_GETFD) >= 0; });
    ++state_->send_count;
    const auto result = state_->send_results.empty()
                            ? session::SendStatus::complete
                            : state_->send_results.front();
    if (!state_->send_results.empty())
      state_->send_results.pop_front();
    if (result != session::SendStatus::would_block)
      state_->prepared = false;
    return result;
  }

  channel::AuthenticatedReceiveResult
  receive(launcher::EndpointMask, launcher::Deadline deadline) override {
    if (state_->expire_receive)
      while (std::chrono::steady_clock::now() < deadline) {
      }
    std::unique_lock lock(state_->mutex);
    state_->deadlines.push_back(deadline);
    state_->operation_threads.push_back(std::this_thread::get_id());
    ++state_->receive_count;
    if (state_->block_receive) {
      state_->receive_entered = true;
      state_->condition.notify_all();
      state_->condition.wait(lock, [&] { return state_->release_receive; });
      state_->block_receive = false;
    }
    std::byte drain[256];
    while (::read(state_->readiness[0], drain, sizeof(drain)) > 0) {
    }
    if (state_->incoming.empty())
      return {.status = channel::AuthenticatedReceiveStatus::would_block,
              .message = {}};
    auto result = std::move(state_->incoming.front());
    state_->incoming.pop_front();
    return result;
  }

  int readiness_fd() const noexcept override {
    return state_->readiness_override == -2 ? state_->readiness[0]
                                            : state_->readiness_override;
  }

  bool arm(launcher::EndpointMask reads,
           launcher::EndpointMask writes) noexcept override {
    std::lock_guard lock(state_->mutex);
    ++state_->arm_count;
    state_->last_reads = reads;
    state_->last_writes = writes;
    return true;
  }

  void terminate(launcher::Deadline deadline) noexcept override {
    std::lock_guard lock(state_->mutex);
    ++state_->terminate_count;
    state_->terminate_deadline = deadline;
    state_->prepared = false;
  }

private:
  std::shared_ptr<BackendState> state_;
};

std::unique_ptr<session::SessionChannel>
adapter(const std::shared_ptr<BackendState> &state) {
  return std::make_unique<channel::AuthenticatedSessionChannel>(
      std::make_unique<FakeBackend>(state));
}

session::OwnedMessage outbound(session::SessionToken identity,
                               std::uint64_t sequence) {
  return {.token = std::move(identity),
          .lane = session::ChannelLane::broker,
          .message_type = 0x0100,
          .correlation_id = 41,
          .sequence = sequence,
          .payload = {std::byte{0x5a}},
          .descriptors = {}};
}

void start_direct(channel::AuthenticatedSessionChannel &adapter,
                  launcher::Deadline deadline) {
  require(adapter.launch(token(), deadline) == session::ChannelError::none,
          "direct adapter launch failed");
  require(adapter.handshake(deadline) == session::ChannelError::none,
          "direct adapter handshake failed");
}

void test_deadline_and_exact_would_block_retry() {
  auto state = std::make_shared<BackendState>();
  state->send_results = {session::SendStatus::would_block,
                         session::SendStatus::complete};
  channel::AuthenticatedSessionChannel value(
      std::make_unique<FakeBackend>(state));
  const auto deadline = std::chrono::steady_clock::now() + 5s;
  start_direct(value, deadline);
  int descriptors[2]{};
  require(::pipe2(descriptors, O_CLOEXEC) == 0, "descriptor fixture failed");
  auto message = outbound(token(), 1);
  message.lane = session::ChannelLane::render;
  message.message_type = 0x2010;
  message.payload.assign(96, std::byte{0x5a});
  message.descriptors.emplace_back(descriptors[0]);
  require(value.send(message, deadline) == session::SendStatus::would_block,
          "first prepared send did not report would-block");
  require(value.send(message, deadline) == session::SendStatus::complete,
          "prepared send did not retry to completion");
  ::close(descriptors[1]);
  value.terminate(deadline);
  std::lock_guard lock(state->mutex);
  require(state->launch_deadline == deadline &&
              state->handshake_deadline == deadline &&
              state->deadlines ==
                  std::vector<launcher::Deadline>({deadline, deadline}) &&
              state->prepare_count == 1 && state->send_count == 2 &&
              state->prepared_role == wire::EndpointRole::render &&
              state->prepared_type == 0x2010 &&
              state->prepared_correlation == 41 &&
              state->prepared_payload ==
                  std::vector<std::byte>(96, std::byte{0x5a}) &&
              state->prepared_descriptor_count == 1 &&
              state->terminate_count == 1 &&
              state->terminate_deadline == deadline,
          "aggregate deadline or byte-identical prepared retry changed");
}

void test_broker_retry_has_no_descriptor_authority() {
  auto state = std::make_shared<BackendState>();
  state->send_results = {session::SendStatus::would_block,
                         session::SendStatus::complete};
  channel::AuthenticatedSessionChannel value(
      std::make_unique<FakeBackend>(state));
  const auto deadline = std::chrono::steady_clock::now() + 5s;
  start_direct(value, deadline);
  auto message = outbound(token(), 1);
  require(value.send(message, deadline) == session::SendStatus::would_block &&
              value.send(message, deadline) == session::SendStatus::complete,
          "descriptor-free broker retry did not preserve prepared bytes");
  std::lock_guard lock(state->mutex);
  require(state->prepare_count == 1 && state->send_count == 2 &&
              state->prepared_descriptor_count == 0 &&
              state->sent_descriptor_count == 0 &&
              state->sent_descriptors_valid,
          "broker retry acquired descriptor authority");
}

class Observer final : public session::SessionObserver {
public:
  void state_changed(session::SessionState state,
                     session::SessionError) override {
    states.push_back(state);
  }
  void message_received(session::OwnedMessage message) override {
    tokens.push_back(message.token);
    lanes.push_back(message.lane);
    types.push_back(message.message_type);
    correlations.push_back(message.correlation_id);
    sequences.push_back(message.sequence);
    for (const auto &descriptor : message.descriptors)
      descriptors_cloexec.push_back(
          descriptor && (::fcntl(descriptor.get(), F_GETFD) & FD_CLOEXEC));
  }
  std::vector<session::SessionState> states;
  std::vector<session::SessionToken> tokens;
  std::vector<session::ChannelLane> lanes;
  std::vector<std::uint16_t> types;
  std::vector<std::uint64_t> correlations;
  std::vector<std::uint64_t> sequences;
  std::vector<bool> descriptors_cloexec;
};

channel::AuthenticatedReceiveResult incoming(wire::EndpointRole role,
                                             std::uint16_t type,
                                             std::uint64_t correlation) {
  channel::AuthenticatedMessage message;
  message.role = role;
  message.message_type = type;
  message.correlation_id = correlation;
  message.payload = {std::byte{0x01}};
  return {.status = channel::AuthenticatedReceiveStatus::message,
          .message = std::move(message)};
}

void test_live_readiness_stamping_and_revoke_fence() {
  auto state = std::make_shared<BackendState>();
  Observer observer;
  auto clock = std::make_shared<session::SteadySessionClock>();
  session::PluginSessionIo io(token(), adapter(state), clock, &observer);
  const auto ui_thread = std::this_thread::get_id();
  io.start();
  await([&] { return io.state() == session::SessionState::running; },
        "live adapter did not start");
  std::size_t before = 0;
  {
    std::lock_guard lock(state->mutex);
    before = state->receive_count;
    state->incoming.push_back(incoming(wire::EndpointRole::control, 0x0100, 3));
    state->incoming.push_back(incoming(wire::EndpointRole::broker, 0x0101, 4));
    state->incoming.push_back(incoming(wire::EndpointRole::render, 0x0102, 5));
  }
  state->signal(100);
  await([&] { return observer.sequences.size() == 3; },
        "level-triggered wake did not deliver arbitrary lanes");
  io.revoke();
  await([&] { return io.state() == session::SessionState::revoked; },
        "live adapter revoke did not complete");
  std::size_t after_revoke = 0;
  {
    std::lock_guard lock(state->mutex);
    after_revoke = state->receive_count;
  }
  state->signal();
  QCoreApplication::processEvents(QEventLoop::AllEvents, 20);
  std::lock_guard lock(state->mutex);
  require(observer.tokens == std::vector<session::SessionToken>(3, token()) &&
              observer.lanes ==
                  std::vector<session::ChannelLane>(
                      {session::ChannelLane::control,
                       session::ChannelLane::broker,
                       session::ChannelLane::render}) &&
              observer.correlations ==
                  std::vector<std::uint64_t>({3, 4, 5}) &&
              observer.sequences ==
                  std::vector<std::uint64_t>({1, 2, 3}) &&
              state->operation_threads.front() != ui_thread &&
              std::all_of(state->operation_threads.begin(),
                          state->operation_threads.end(),
                          [&](auto thread) {
                            return thread == state->operation_threads.front();
                          }) &&
              state->receive_count >= before + 3 &&
              state->receive_count <= before + 4 &&
              state->receive_count == after_revoke &&
              state->terminate_count == 1,
          "token stamping, worker affinity, coalescing, or revoke fence failed");
}

void test_invalid_lane_and_stale_token_fail_closed() {
  auto state = std::make_shared<BackendState>();
  {
    channel::AuthenticatedSessionChannel value(
        std::make_unique<FakeBackend>(state));
    const auto deadline = std::chrono::steady_clock::now() + 5s;
    start_direct(value, deadline);
    auto message = outbound(token(), 1);
    message.lane = static_cast<session::ChannelLane>(255);
    require(value.send(message, deadline) == session::SendStatus::fatal,
            "invalid lane escaped fail-closed mapping");
    require(value.send(outbound(token(), 2), deadline) ==
                session::SendStatus::fatal,
            "terminal adapter performed work after invalid lane");
  }
  std::lock_guard lock(state->mutex);
  require(state->prepare_count == 0 && state->terminate_count == 1,
          "invalid semantic identity retained transport authority");
}

void test_seventeen_transport_descriptors_fail_before_effect() {
  auto state = std::make_shared<BackendState>();
  channel::AuthenticatedSessionChannel value(
      std::make_unique<FakeBackend>(state));
  const auto deadline = std::chrono::steady_clock::now() + 5s;
  start_direct(value, deadline);
  auto message = outbound(token(), 1);
  for (std::size_t index = 0;
       index <= launcher::kMaximumTransportDescriptors; ++index) {
    const int descriptor = ::open("/dev/null", O_RDONLY | O_CLOEXEC);
    require(descriptor >= 0, "outbound descriptor-bound fixture failed");
    message.descriptors.emplace_back(descriptor);
  }
  require(value.send(message, deadline) == session::SendStatus::fatal,
          "oversized outbound descriptor set reached preparation");
  {
    std::lock_guard lock(state->mutex);
    require(state->prepare_count == 0 && state->send_count == 0 &&
                state->terminate_count == 1,
            "oversized outbound descriptor set made transport progress");
  }

  auto inbound_state = std::make_shared<BackendState>();
  channel::AuthenticatedSessionChannel inbound_value(
      std::make_unique<FakeBackend>(inbound_state));
  start_direct(inbound_value, deadline);
  auto inbound_message = incoming(wire::EndpointRole::render, 0x2020, 0);
  std::vector<int> transferred;
  for (std::size_t index = 0;
       index <= launcher::kMaximumTransportDescriptors; ++index) {
    const int descriptor = ::open("/dev/null", O_RDONLY | O_CLOEXEC);
    require(descriptor >= 0, "inbound descriptor-bound fixture failed");
    transferred.push_back(descriptor);
    inbound_message.message->descriptors.emplace_back(descriptor);
  }
  {
    std::lock_guard inbound_lock(inbound_state->mutex);
    inbound_state->incoming.push_back(std::move(inbound_message));
  }
  require(inbound_value.receive(deadline).status ==
              session::ReceiveStatus::fatal,
          "oversized inbound descriptor set reached publication");
  require(std::all_of(transferred.begin(), transferred.end(), [](int fd) {
            return ::fcntl(fd, F_GETFD) == -1;
          }),
          "rejected inbound descriptors were not closed");
  std::lock_guard lock(inbound_state->mutex);
  require(inbound_state->terminate_count == 1,
          "oversized inbound descriptor set retained transport authority");
}

void test_each_token_field_is_bound_before_effect() {
  for (int field = 0; field < 4; ++field) {
    auto state = std::make_shared<BackendState>();
    channel::AuthenticatedSessionChannel value(
        std::make_unique<FakeBackend>(state));
    const auto deadline = std::chrono::steady_clock::now() + 5s;
    start_direct(value, deadline);
    auto identity = token();
    if (field == 0)
      identity.plugin_id += ".spoof";
    else if (field == 1)
      identity.revision_sha256[0] = 'c';
    else if (field == 2)
      ++identity.generation;
    else
      ++identity.session_nonce;
    require(value.send(outbound(identity, 1), deadline) ==
                session::SendStatus::fatal,
            "a mismatched token field reached transport preparation");
    std::lock_guard lock(state->mutex);
    require(state->prepare_count == 0 && state->send_count == 0 &&
                state->terminate_count == 1,
            "token mismatch retained effect authority");
  }
}

void test_changed_would_block_retry_is_rejected_without_fd_ownership() {
  enum class Change { sequence, payload, correlation, descriptors };
  for (const auto change : {Change::sequence, Change::payload,
                            Change::correlation, Change::descriptors}) {
    auto state = std::make_shared<BackendState>();
    state->send_results = {session::SendStatus::would_block};
    channel::AuthenticatedSessionChannel value(
        std::make_unique<FakeBackend>(state));
    const auto deadline = std::chrono::steady_clock::now() + 5s;
    start_direct(value, deadline);
    int first_pipe[2]{};
    int second_pipe[2]{};
    require(::pipe2(first_pipe, O_CLOEXEC) == 0 &&
                ::pipe2(second_pipe, O_CLOEXEC) == 0,
            "retry descriptor fixtures failed");
    auto message = outbound(token(), 1);
    message.lane = session::ChannelLane::render;
    message.message_type = 0x2010;
    message.payload.assign(96, std::byte{0x11});
    message.descriptors.emplace_back(first_pipe[0]);
    require(value.send(message, deadline) == session::SendStatus::would_block,
            "retry mutation fixture did not block");
    if (change == Change::sequence)
      ++message.sequence;
    else if (change == Change::payload)
      message.payload[0] = std::byte{0x22};
    else if (change == Change::correlation)
      ++message.correlation_id;
    else
      message.descriptors.emplace_back(second_pipe[0]);
    require(value.send(message, deadline) == session::SendStatus::fatal &&
                ::fcntl(first_pipe[0], F_GETFD) >= 0,
            "changed retry consumed transport bytes or borrowed FD ownership");
    if (change != Change::descriptors)
      ::close(second_pipe[0]);
    ::close(first_pipe[1]);
    ::close(second_pipe[1]);
    std::lock_guard lock(state->mutex);
    require(state->prepare_count == 1 && state->send_count == 1 &&
                state->terminate_count == 1,
            "changed retry made partial transport progress");
  }
}

void test_install_failure_and_idempotent_direct_teardown() {
  auto state = std::make_shared<BackendState>();
  state->readiness_override = -1;
  {
    channel::AuthenticatedSessionChannel value(
        std::make_unique<FakeBackend>(state));
    const auto deadline = std::chrono::steady_clock::now() + 5s;
    start_direct(value, deadline);
    require(!value.install_wake_handler(
                {.function = [](void *) noexcept {}, .context = nullptr}),
            "invalid readiness descriptor installed a wake handler");
    require(value.revoke(token(), deadline), "direct revoke failed");
    value.terminate(deadline);
  }
  std::lock_guard lock(state->mutex);
  require(state->terminate_count == 1,
          "revoke, terminate, and destruction terminated backend repeatedly");
}

void test_install_failure_fails_plugin_session() {
  auto state = std::make_shared<BackendState>();
  state->readiness_override = -1;
  auto clock = std::make_shared<session::SteadySessionClock>();
  session::PluginSessionIo io(token(), adapter(state), clock);
  io.start();
  await([&] { return io.state() == session::SessionState::failed; },
        "wake installation failure left a running plugin session");
  std::lock_guard lock(state->mutex);
  require(io.error() == session::SessionError::channel_failed &&
              state->terminate_count == 1,
          "wake installation failure did not fail-stop exactly once");
}

void test_inbound_descriptor_transfers_once_and_closes() {
  auto state = std::make_shared<BackendState>();
  channel::AuthenticatedSessionChannel value(
      std::make_unique<FakeBackend>(state));
  const auto deadline = std::chrono::steady_clock::now() + 5s;
  start_direct(value, deadline);
  int descriptors[2]{};
  require(::pipe2(descriptors, O_CLOEXEC) == 0,
          "inbound descriptor fixture failed");
  const int transferred = ::fcntl(descriptors[0], F_DUPFD_CLOEXEC, 100);
  require(transferred >= 0, "inbound descriptor duplication failed");
  auto message = incoming(wire::EndpointRole::render, 0x2020, 0);
  message.message->descriptors.emplace_back(transferred);
  {
    std::lock_guard lock(state->mutex);
    state->incoming.push_back(std::move(message));
  }
  {
    auto received = value.receive(deadline);
    const int flags = ::fcntl(transferred, F_GETFD);
    require(received.status == session::ReceiveStatus::message &&
                received.message.descriptors.size() == 1 &&
                received.message.descriptors.front().get() == transferred &&
                flags >= 0 && (flags & FD_CLOEXEC) != 0,
            "authenticated descriptor did not transfer exactly once");
  }
  require(::fcntl(transferred, F_GETFD) == -1,
          "dropped inbound message leaked its owned descriptor");
  ::close(descriptors[0]);
  ::close(descriptors[1]);
}

void test_deadline_crossing_never_publishes_authority() {
  {
    auto state = std::make_shared<BackendState>();
    state->expire_launch = true;
    channel::AuthenticatedSessionChannel value(
        std::make_unique<FakeBackend>(state));
    const auto deadline = std::chrono::steady_clock::now() + 2ms;
    require(value.launch(token(), deadline) ==
                session::ChannelError::launch_failed,
            "late launch published process authority");
    std::lock_guard lock(state->mutex);
    require(state->terminate_count == 1,
            "late launch was not terminally cleaned");
  }
  {
    auto state = std::make_shared<BackendState>();
    state->expire_handshake = true;
    channel::AuthenticatedSessionChannel value(
        std::make_unique<FakeBackend>(state));
    const auto deadline = std::chrono::steady_clock::now() + 3ms;
    require(value.launch(token(), deadline) == session::ChannelError::none &&
                value.handshake(deadline) ==
                    session::ChannelError::handshake_failed,
            "late handshake published ready authority");
    std::lock_guard lock(state->mutex);
    require(state->terminate_count == 1,
            "late handshake was not terminally cleaned");
  }
  {
    auto state = std::make_shared<BackendState>();
    channel::AuthenticatedSessionChannel value(
        std::make_unique<FakeBackend>(state));
    start_direct(value, std::chrono::steady_clock::now() + 5s);
    state->expire_receive = true;
    const auto deadline = std::chrono::steady_clock::now() + 2ms;
    require(value.receive(deadline).status == session::ReceiveStatus::fatal,
            "late would-block receive escaped aggregate deadline");
    std::lock_guard lock(state->mutex);
    require(state->terminate_count == 1,
            "late receive retained authenticated authority");
  }
}

void test_blocked_receive_cannot_cross_revoke_epoch() {
  auto state = std::make_shared<BackendState>();
  {
    std::lock_guard lock(state->mutex);
    state->block_receive = true;
    state->incoming.push_back(incoming(wire::EndpointRole::broker, 0x0100, 8));
  }
  Observer observer;
  auto clock = std::make_shared<session::SteadySessionClock>();
  session::PluginSessionIo io(token(), adapter(state), clock, &observer);
  io.start();
  await(
      [&] {
        std::lock_guard lock(state->mutex);
        return state->receive_entered;
      },
      "revoke-race receive did not block");
  io.revoke();
  {
    std::lock_guard lock(state->mutex);
    state->release_receive = true;
    state->condition.notify_all();
  }
  await([&] { return io.state() == session::SessionState::revoked; },
        "revoke-race session did not finish");
  std::lock_guard lock(state->mutex);
  require(observer.sequences.empty() && state->terminate_count == 1,
          "blocked authenticated message crossed the revoke epoch");
}

void run() {
  test_deadline_and_exact_would_block_retry();
  test_broker_retry_has_no_descriptor_authority();
  test_live_readiness_stamping_and_revoke_fence();
  test_invalid_lane_and_stale_token_fail_closed();
  test_seventeen_transport_descriptors_fail_before_effect();
  test_each_token_field_is_bound_before_effect();
  test_changed_would_block_retry_is_rejected_without_fd_ownership();
  test_install_failure_and_idempotent_direct_teardown();
  test_install_failure_fails_plugin_session();
  test_inbound_descriptor_transfers_once_and_closes();
  test_deadline_crossing_never_publishes_authority();
  test_blocked_receive_cannot_cross_revoke_epoch();
}

} // namespace

int main(int argc, char **argv) {
  QCoreApplication application(argc, argv);
  try {
    run();
  } catch (const std::exception &error) {
    std::cerr << "authenticated session adapter test failed: " << error.what()
              << '\n';
    return 1;
  }
  std::cout << "authenticated session adapter test passed\n";
  return 0;
}
