#include "plugin_session_io.hpp"

#include <QCoreApplication>
#include <QEventLoop>
#include <QPointer>

#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

#include <chrono>
#include <condition_variable>
#include <deque>
#include <iostream>
#include <mutex>
#include <stdexcept>
#include <string_view>
#include <thread>

namespace {

using namespace omarchy::plugin_runtime::host_session;

void require(bool condition, std::string_view message) {
  if (!condition)
    throw std::runtime_error(std::string(message));
}

template <typename Predicate>
void await(Predicate predicate, std::string_view failure) {
  const auto deadline =
      std::chrono::steady_clock::now() + std::chrono::seconds(2);
  while (!predicate() && std::chrono::steady_clock::now() < deadline) {
    QCoreApplication::processEvents(QEventLoop::AllEvents, 10);
    std::this_thread::yield();
  }
  require(predicate(), failure);
}

template <typename Predicate>
void await_without_ui_dispatch(Predicate predicate, std::string_view failure) {
  const auto deadline =
      std::chrono::steady_clock::now() + std::chrono::seconds(2);
  while (!predicate() && std::chrono::steady_clock::now() < deadline)
    std::this_thread::yield();
  require(predicate(), failure);
}

void await_state(PluginSessionIo &session, SessionState expected,
                 std::string_view failure) {
  await([&] { return session.state() == expected; }, failure);
}

void await_state_without_ui(PluginSessionIo &session, SessionState expected,
                            std::string_view failure) {
  await_without_ui_dispatch(
      [&] { return session.state() == expected; }, failure);
}

void start_and_await_running(PluginSessionIo &session,
                             std::string_view failure) {
  session.start();
  await_state(session, SessionState::running, failure);
}

void start_and_await_running_without_ui(PluginSessionIo &session,
                                        std::string_view failure) {
  session.start();
  await_state_without_ui(session, SessionState::running, failure);
}

SessionToken token(std::uint64_t generation = 7, std::uint64_t nonce = 11) {
  return {.plugin_id = "org.omarchy.fixture",
          .revision_sha256 = std::string(64, 'a'),
          .generation = generation,
          .session_nonce = nonce};
}

OwnedMessage message(SessionToken identity, std::uint64_t sequence,
                     std::size_t bytes = 1) {
  return {.token = std::move(identity),
          .lane = ChannelLane::render,
          .message_type = 1,
          .sequence = sequence,
          .payload = std::vector<std::byte>(bytes),
          .descriptors = {}};
}

class FakeClock final : public SessionClock {
public:
  TimePoint now() const noexcept override {
    calls_.fetch_add(1);
    return TimePoint(std::chrono::nanoseconds(now_ns_.load()));
  }
  void advance(std::chrono::milliseconds duration) {
    now_ns_.fetch_add(
        std::chrono::duration_cast<std::chrono::nanoseconds>(duration).count());
  }
  void set(TimePoint value) {
    now_ns_.store(std::chrono::duration_cast<std::chrono::nanoseconds>(
                      value.time_since_epoch())
                      .count());
  }
  [[nodiscard]] std::uint64_t calls() const noexcept { return calls_.load(); }

private:
  std::atomic<std::int64_t> now_ns_{0};
  mutable std::atomic<std::uint64_t> calls_{0};
};

struct ChannelState {
  std::mutex mutex;
  std::condition_variable condition;
  std::vector<std::string> calls;
  std::vector<std::uint64_t> sent_sequences;
  std::vector<int> sent_descriptors;
  std::vector<bool> sent_descriptors_valid;
  std::vector<SessionChannel::TimePoint> send_deadlines;
  std::vector<SessionChannel::TimePoint> receive_deadlines;
  std::vector<SessionChannel::TimePoint> revoke_deadlines;
  std::vector<SessionChannel::TimePoint> terminate_deadlines;
  std::deque<ReceiveResult> incoming;
  SessionWakeHandler wake_handler;
  std::thread::id caller;
  std::thread::id wake_callback_thread;
  std::thread::id wake_install_thread;
  std::thread::id wake_clear_thread;
  SessionChannel::TimePoint deadline{};
  ChannelError launch_error = ChannelError::none;
  ChannelError handshake_error = ChannelError::none;
  SendStatus send_status = SendStatus::complete;
  std::size_t receive_calls = 0;
  int revoke_count = 0;
  int terminate_count = 0;
  int destroy_count = 0;
  int wake_install_count = 0;
  int wake_clear_count = 0;
  bool destroyed_with_wake_handler = false;
  bool trigger_wake_on_receive = false;
  bool block_send = false;
  bool send_entered = false;
  bool release_send = false;
  bool block_receive = false;
  bool receive_entered = false;
  bool release_receive = false;
  bool block_terminate = false;
  bool terminate_entered = false;
  bool release_terminate = false;
  std::chrono::milliseconds receive_cost{};
};

struct ChannelFixture {
  std::shared_ptr<ChannelState> state = std::make_shared<ChannelState>();
  std::shared_ptr<FakeClock> clock = std::make_shared<FakeClock>();
};

class FakeChannel final : public SessionChannel {
public:
  FakeChannel(std::shared_ptr<ChannelState> state,
              std::shared_ptr<FakeClock> clock = {},
              std::chrono::milliseconds startup_cost = {})
      : state_(std::move(state)), clock_(std::move(clock)),
        startup_cost_(startup_cost) {}
  ~FakeChannel() override {
    std::lock_guard lock(state_->mutex);
    state_->destroyed_with_wake_handler = bool(state_->wake_handler);
    ++state_->destroy_count;
  }

  ChannelError launch(const SessionToken &, TimePoint deadline) override {
    record("launch");
    state_->deadline = deadline;
    if (clock_)
      clock_->advance(startup_cost_);
    return state_->launch_error;
  }

  ChannelError handshake(TimePoint deadline) override {
    record("handshake");
    require(deadline == state_->deadline,
            "handshake reset the aggregate startup deadline");
    return state_->handshake_error;
  }

  SendStatus send(const OwnedMessage &value, TimePoint deadline) override {
    record("send");
    std::unique_lock lock(state_->mutex);
    require(deadline > TimePoint{}, "send received an empty deadline");
    state_->send_deadlines.push_back(deadline);
    state_->sent_sequences.push_back(value.sequence);
    const int descriptor =
        value.descriptors.empty() ? -1 : value.descriptors.front().get();
    state_->sent_descriptors.push_back(descriptor);
    struct stat identity{};
    state_->sent_descriptors_valid.push_back(
        descriptor < 0 || ::fstat(descriptor, &identity) == 0);
    if (state_->block_send) {
      state_->send_entered = true;
      state_->condition.notify_all();
      state_->condition.wait(lock, [&] { return state_->release_send; });
      state_->block_send = false;
    }
    return state_->send_status;
  }

  ReceiveResult receive(TimePoint deadline) override {
    record("receive");
    std::unique_lock lock(state_->mutex);
    require(deadline > TimePoint{}, "receive received an empty deadline");
    state_->receive_deadlines.push_back(deadline);
    if (clock_)
      clock_->advance(state_->receive_cost);
    ++state_->receive_calls;
    const auto wake = state_->trigger_wake_on_receive
                          ? state_->wake_handler
                          : SessionWakeHandler{};
    state_->trigger_wake_on_receive = false;
    if (state_->block_receive) {
      state_->receive_entered = true;
      state_->condition.notify_all();
      state_->condition.wait(lock, [&] { return state_->release_receive; });
      state_->block_receive = false;
    }
    if (wake) {
      state_->wake_callback_thread = std::this_thread::get_id();
      lock.unlock();
      wake.invoke();
      lock.lock();
    }
    if (state_->incoming.empty())
      return {};
    auto result = std::move(state_->incoming.front());
    state_->incoming.pop_front();
    return result;
  }

  bool install_wake_handler(SessionWakeHandler handler) noexcept override {
    record("install_wake");
    std::lock_guard lock(state_->mutex);
    if (!handler || state_->wake_handler)
      return false;
    state_->wake_handler = handler;
    state_->wake_install_thread = std::this_thread::get_id();
    ++state_->wake_install_count;
    return true;
  }

  void clear_wake_handler() noexcept override {
    record("clear_wake");
    std::lock_guard lock(state_->mutex);
    state_->wake_handler = {};
    state_->wake_clear_thread = std::this_thread::get_id();
    ++state_->wake_clear_count;
  }

  bool revoke(const SessionToken &, TimePoint deadline) noexcept override {
    record("revoke");
    std::lock_guard lock(state_->mutex);
    state_->revoke_deadlines.push_back(deadline);
    ++state_->revoke_count;
    return true;
  }
  void terminate(TimePoint deadline) noexcept override {
    record("terminate");
    std::unique_lock lock(state_->mutex);
    state_->terminate_deadlines.push_back(deadline);
    if (state_->block_terminate) {
      state_->terminate_entered = true;
      state_->condition.notify_all();
      state_->condition.wait(lock, [&] { return state_->release_terminate; });
      state_->block_terminate = false;
    }
    ++state_->terminate_count;
  }

private:
  void record(std::string value) noexcept {
    std::lock_guard lock(state_->mutex);
    state_->caller = std::this_thread::get_id();
    state_->calls.push_back(std::move(value));
  }

  std::shared_ptr<ChannelState> state_;
  std::shared_ptr<FakeClock> clock_;
  std::chrono::milliseconds startup_cost_;
};

class Observer final : public SessionObserver {
public:
  void state_changed(SessionState state, SessionError error) override {
    observe_thread();
    states.emplace_back(state, error);
  }
  void message_received(OwnedMessage message) override {
    observe_thread();
    received.push_back(message.sequence);
  }

  void observe_thread() {
    const auto current = std::this_thread::get_id();
    if (callback_thread == std::thread::id{})
      callback_thread = current;
    else if (callback_thread != current)
      wrong_thread = true;
  }

  std::vector<std::pair<SessionState, SessionError>> states;
  std::vector<std::uint64_t> received;
  std::thread::id callback_thread;
  bool wrong_thread = false;
};

std::unique_ptr<SessionChannel>
fake(const std::shared_ptr<ChannelState> &state,
     const std::shared_ptr<FakeClock> &clock = {},
     std::chrono::milliseconds startup_cost = {}) {
  return std::make_unique<FakeChannel>(state, clock, startup_cost);
}

void test_thread_and_ordering() {
  auto [state, clock] = ChannelFixture{};
  Observer observer;
  PluginSessionIo session(token(), fake(state), clock, &observer);
  const auto ui_thread = std::this_thread::get_id();
  require(session.enqueue(message(token(), 1)) &&
              session.enqueue(message(token(), 2)),
          "valid queued messages were rejected");
  start_and_await_running(session, "session did not become running");
  await(
      [&] {
        std::lock_guard lock(state->mutex);
        return state->sent_sequences.size() == 2;
      },
      "queued messages were not sent");
  await([&] { return observer.callback_thread != std::thread::id{}; },
        "observer did not receive the queued running-state callback");
  std::lock_guard lock(state->mutex);
  require(state->caller != ui_thread, "channel work ran on the UI thread");
  require(observer.callback_thread == ui_thread && !observer.wrong_thread,
          "observer callback escaped its owning UI thread");
  require(state->calls.size() >= 2 && state->calls[0] == "launch" &&
              state->calls[1] == "handshake",
          "launch/handshake ordering changed");
  require(state->sent_sequences == std::vector<std::uint64_t>({1, 2}),
          "outbound FIFO ordering changed");
  require(state->deadline == clock->now() + std::chrono::seconds(5),
          "startup did not use one absolute aggregate deadline");
}

void test_queue_bounds_and_fd_ownership() {
  auto [state, clock] = ChannelFixture{};
  SessionLimits limits;
  limits.maximum_queued_messages = 2;
  limits.maximum_queued_bytes = 4;
  limits.maximum_descriptors_per_message = 1;
  limits.maximum_queued_descriptors = 1;
  limits.maximum_pump_batch = 2;
  limits.startup_timeout = std::chrono::seconds(1);
  PluginSessionIo session(token(), fake(state), clock, nullptr, limits);
  int descriptors[2]{};
  require(::pipe2(descriptors, O_CLOEXEC) == 0, "pipe fixture failed");
  auto first = message(token(), 1, 2);
  const int transferred = descriptors[0];
  struct stat transferred_identity{};
  require(::fstat(transferred, &transferred_identity) == 0,
          "could not identify transferred descriptor");
  first.descriptors.emplace_back(descriptors[0]);
  require(session.enqueue(std::move(first)) &&
              session.enqueue(message(token(), 2, 2)),
          "messages within queue bounds were rejected");
  require(!session.enqueue(message(token(), 3, 1)) &&
              session.error() == SessionError::queue_limit,
          "message-count/byte limit did not reject overflow");
  session.revoke();
  require((session.state() == SessionState::revoking ||
           session.state() == SessionState::revoked) &&
              session.error() == SessionError::none,
          "revocation published state before clearing the prior error");
  await_state(session, SessionState::revoked, "revoke did not complete");
  struct stat after_clear{};
  const bool same_descriptor =
      ::fstat(transferred, &after_clear) == 0 &&
      after_clear.st_dev == transferred_identity.st_dev &&
      after_clear.st_ino == transferred_identity.st_ino;
  require(!same_descriptor,
          "clearing the owning queue leaked a transferred descriptor");
  ::close(descriptors[1]);
}

void test_deadline_is_aggregate() {
  auto [state, clock] = ChannelFixture{};
  SessionLimits limits;
  limits.startup_timeout = std::chrono::milliseconds(50);
  PluginSessionIo session(token(),
                          fake(state, clock, std::chrono::milliseconds(50)),
                          clock, nullptr, limits);
  session.start();
  await_state(session, SessionState::failed,
              "expired aggregate startup deadline was accepted");
  require(session.error() == SessionError::startup_deadline_expired,
          "deadline failure was not classified");
}

void test_limits_and_deadline_overflow_are_rejected() {
  auto [state, clock] = ChannelFixture{};
  SessionLimits limits;
  limits.maximum_queued_bytes = SessionLimits::kMaximumBytes + 1;
  PluginSessionIo oversized(token(), fake(state), clock, nullptr, limits);
  oversized.start();
  await_state_without_ui(oversized, SessionState::failed,
                         "hard queue ceiling was not rejected");
  require(oversized.error() == SessionError::invalid_configuration,
          "hard queue ceiling failure was misclassified");

  auto overflow_state = std::make_shared<ChannelState>();
  auto overflow_clock = std::make_shared<FakeClock>();
  overflow_clock->set(SessionChannel::TimePoint::max() -
                      std::chrono::milliseconds(1));
  PluginSessionIo overflow(token(), fake(overflow_state), overflow_clock);
  overflow.start();
  await_state_without_ui(overflow, SessionState::failed,
                         "overflowing absolute deadline was admitted");
  require(overflow.error() == SessionError::invalid_configuration,
          "overflowing deadline failure was misclassified");
}

void test_null_channel_and_no_start_are_safe() {
  auto clock = std::make_shared<FakeClock>();
  {
    PluginSessionIo session(token(), nullptr, clock);
    session.stop();
    await_state_without_ui(session, SessionState::stopped,
                           "null-channel stop did not complete safely");
  }
  {
    PluginSessionIo session(token(), nullptr, clock);
    session.revoke();
    await_state_without_ui(session, SessionState::revoked,
                           "null-channel revoke did not complete safely");
  }

  auto state = std::make_shared<ChannelState>();
  {
    PluginSessionIo session(token(), fake(state), clock);
  }
  await(
      [&] {
        std::lock_guard lock(state->mutex);
        return state->terminate_count == 1;
      },
      "never-started channel was not asynchronously terminated");
}

void test_observer_affinity_mismatch_is_rejected() {
  auto [state, clock] = ChannelFixture{};
  QThread observer_thread;
  observer_thread.start();
  Observer observer;
  observer.moveToThread(&observer_thread);
  {
    PluginSessionIo session(token(), fake(state), clock, &observer);
    session.start();
    await_state_without_ui(session, SessionState::failed,
                           "cross-thread observer affinity was accepted");
    require(session.error() == SessionError::invalid_configuration,
            "observer affinity failure was misclassified");
  }
  auto *ui_thread = QCoreApplication::instance()->thread();
  require(QMetaObject::invokeMethod(
              &observer,
              [&observer, ui_thread] { observer.moveToThread(ui_thread); },
              Qt::BlockingQueuedConnection),
          "observer fixture could not restore affinity");
  observer_thread.quit();
  observer_thread.wait();
}

void test_inbound_delivery_queue_is_bounded() {
  auto [state, clock] = ChannelFixture{};
  Observer observer;
  SessionLimits limits;
  limits.maximum_queued_messages = 1;
  limits.maximum_pump_batch = 2;
  PluginSessionIo session(token(), fake(state), clock, &observer, limits);
  start_and_await_running_without_ui(
      session, "session did not start for delivery-bound test");
  {
    std::lock_guard lock(state->mutex);
    state->incoming.push_back(
        {.status = ReceiveStatus::message, .message = message(token(), 1)});
    state->incoming.push_back(
        {.status = ReceiveStatus::message, .message = message(token(), 2)});
  }
  session.wake();
  await_state_without_ui(session, SessionState::failed,
                         "an unbounded UI delivery queue was admitted");
  require(session.error() == SessionError::queue_limit,
          "delivery backpressure was not classified");
  QCoreApplication::processEvents();
}

void test_stale_drop_and_delivery() {
  auto [state, clock] = ChannelFixture{};
  Observer observer;
  PluginSessionIo session(token(), fake(state), clock, &observer);
  start_and_await_running(session, "session did not start for inbound test");
  {
    std::lock_guard lock(state->mutex);
    state->incoming.push_back({.status = ReceiveStatus::message,
                               .message = message(token(8, 11), 40)});
    state->incoming.push_back(
        {.status = ReceiveStatus::message, .message = message(token(), 41)});
  }
  session.wake();
  await([&] { return observer.received.size() == 1; },
        "current inbound message was not delivered");
  require(observer.received.front() == 41 &&
              session.stale_messages_dropped() == 1,
          "stale generation was delivered or not accounted");
  require(!session.enqueue(message(token(7, 12), 42)) &&
              session.stale_messages_dropped() == 2,
          "cross-session outbound message was admitted");
}

void test_queued_delivery_is_fenced_before_revoke() {
  auto [state, clock] = ChannelFixture{};
  Observer observer;
  PluginSessionIo session(token(), fake(state), clock, &observer);
  start_and_await_running_without_ui(
      session, "session did not start for delivery-fence test");
  std::size_t before = 0;
  {
    std::lock_guard lock(state->mutex);
    before = state->receive_calls;
    state->incoming.push_back(
        {.status = ReceiveStatus::message, .message = message(token(), 50)});
  }
  session.wake();
  await_without_ui_dispatch(
      [&] {
        std::lock_guard lock(state->mutex);
        return state->receive_calls >= before + 2;
      },
      "inbound message was not queued before revoke");
  session.revoke();
  QCoreApplication::processEvents();
  require(observer.received.empty(),
          "a pre-revoke queued delivery crossed the epoch fence");
  await_state(session, SessionState::revoked,
              "delivery-fence revoke did not terminate");
}

void test_enqueue_is_fenced_synchronously() {
  auto [state, clock] = ChannelFixture{};
  PluginSessionIo session(token(), fake(state), clock);
  require(session.enqueue(message(token(), 1)),
          "pre-start enqueue fixture was rejected");
  session.revoke();
  require(!session.enqueue(message(token(), 2)),
          "enqueue raced through the synchronous revoke fence");
  session.start();
  await_state_without_ui(session, SessionState::revoked,
                         "queued-work revoke did not complete");
  std::lock_guard lock(state->mutex);
  require(state->sent_sequences.empty(),
          "queued work was sent after the revoke fence");
}

void test_pump_requests_are_coalesced_and_batched() {
  auto [state, clock] = ChannelFixture{};
  PluginSessionIo session(token(), fake(state), clock);
  start_and_await_running_without_ui(
      session, "session did not start for coalescing test");
  for (int iteration = 0; iteration < 100; ++iteration) {
    std::size_t before = 0;
    {
      std::lock_guard lock(state->mutex);
      before = state->receive_calls;
      state->block_receive = true;
      state->receive_entered = false;
      state->release_receive = false;
    }
    session.wake();
    await_without_ui_dispatch(
        [&] {
          std::lock_guard lock(state->mutex);
          return state->receive_entered;
        },
        "coalescing fixture did not enter receive");
    for (int index = 0; index < 100; ++index)
      session.wake();
    {
      std::lock_guard lock(state->mutex);
      state->release_receive = true;
      state->condition.notify_all();
    }
    await_without_ui_dispatch(
        [&] {
          std::lock_guard lock(state->mutex);
          return state->receive_calls == before + 2;
        },
        "coalesced wake was not serviced exactly once");
  }
  session.stop();
  await_state_without_ui(session, SessionState::stopped,
                         "coalescing test did not stop");
}

void test_receive_is_fair_under_sustained_outbound() {
  auto [state, clock] = ChannelFixture{};
  Observer observer;
  SessionLimits limits;
  limits.maximum_pump_batch = 4;
  limits.maximum_queued_messages = 16;
  PluginSessionIo session(token(), fake(state), clock, &observer, limits);
  for (std::uint64_t sequence = 1; sequence <= 8; ++sequence)
    require(session.enqueue(message(token(), sequence)),
            "fairness fixture outbound admission failed");
  {
    std::lock_guard lock(state->mutex);
    state->incoming.push_back(
        {.status = ReceiveStatus::message, .message = message(token(), 50)});
  }
  session.start();
  await([&] { return !observer.received.empty(); },
        "inbound traffic starved behind outbound traffic");
  std::lock_guard lock(state->mutex);
  const auto first_receive =
      std::find(state->calls.begin(), state->calls.end(), "receive");
  require(first_receive != state->calls.end() &&
              std::count(state->calls.begin(), first_receive, "send") <= 2,
          "pump failed to reserve its inbound fairness slice");
}

void test_would_block_makes_no_progress_and_keeps_fd_owned() {
  auto [state, clock] = ChannelFixture{};
  state->send_status = SendStatus::would_block;
  PluginSessionIo session(token(), fake(state), clock);
  int descriptors[2]{};
  require(::pipe2(descriptors, O_CLOEXEC) == 0, "would-block pipe failed");
  auto first = message(token(), 1);
  first.descriptors.emplace_back(descriptors[0]);
  require(session.enqueue(std::move(first)) &&
              session.enqueue(message(token(), 2)),
          "would-block fixture admission failed");
  session.start();
  await_without_ui_dispatch(
      [&] {
        std::lock_guard lock(state->mutex);
        return state->sent_sequences.size() == 1;
      },
      "would-block send was not attempted");
  {
    std::lock_guard lock(state->mutex);
    require(state->sent_sequences == std::vector<std::uint64_t>{1} &&
                state->sent_descriptors_valid.front(),
            "would-block send consumed sequence or descriptor ownership");
    state->send_status = SendStatus::complete;
  }
  session.wake();
  await_without_ui_dispatch(
      [&] {
        std::lock_guard lock(state->mutex);
        return state->sent_sequences.size() == 3;
      },
      "retried send did not resume FIFO progress");
  {
    std::lock_guard lock(state->mutex);
    require(state->sent_sequences == std::vector<std::uint64_t>({1, 1, 2}) &&
                state->sent_descriptors[0] == state->sent_descriptors[1] &&
                state->sent_descriptors_valid[1],
            "would-block retry changed FIFO or descriptor ownership");
  }
  ::close(descriptors[1]);
}

void test_revoke_and_teardown_are_deterministic() {
  auto [state, clock] = ChannelFixture{};
  {
    PluginSessionIo session(token(), fake(state), clock);
    start_and_await_running(session, "session did not start for revoke test");
    session.revoke();
    await_state(session, SessionState::revoked,
                "session did not enter revoked state");
    std::lock_guard lock(state->mutex);
    const auto revoke =
        std::find(state->calls.begin(), state->calls.end(), "revoke");
    const auto clear =
        std::find(state->calls.begin(), state->calls.end(), "clear_wake");
    const auto terminate =
        std::find(state->calls.begin(), state->calls.end(), "terminate");
    require(clear != state->calls.end() && revoke != state->calls.end() &&
                terminate != state->calls.end() && clear < revoke &&
                revoke < terminate,
            "wake fence, revocation, and termination were misordered");
  }
  std::lock_guard lock(state->mutex);
  require(state->terminate_count == 1,
          "destruction terminated an already-revoked channel twice");
}

void test_channel_wake_is_worker_affine_and_fenced() {
  auto [state, clock] = ChannelFixture{};
  {
    std::lock_guard lock(state->mutex);
    state->trigger_wake_on_receive = true;
  }
  PluginSessionIo session(token(), fake(state), clock);
  start_and_await_running_without_ui(
      session, "readiness-callback fixture did not start");
  await_without_ui_dispatch(
      [&] {
        std::lock_guard lock(state->mutex);
        return state->receive_calls >= 2;
      },
      "worker-thread readiness callback did not schedule another pump");
  session.stop();
  await_state_without_ui(session, SessionState::stopped,
                         "readiness-callback fixture did not stop");
  std::lock_guard lock(state->mutex);
  const auto install =
      std::find(state->calls.begin(), state->calls.end(), "install_wake");
  const auto clear =
      std::find(state->calls.begin(), state->calls.end(), "clear_wake");
  const auto terminate =
      std::find(state->calls.begin(), state->calls.end(), "terminate");
  require(state->wake_install_count == 1 && state->wake_clear_count == 1 &&
              !state->wake_handler && install < clear && clear < terminate &&
              state->wake_callback_thread == state->wake_install_thread &&
              state->wake_clear_thread == state->wake_install_thread,
          "readiness callback was not synchronously fenced before stop");
}

void test_destructor_stops_live_channel() {
  auto [state, clock] = ChannelFixture{};
  std::atomic<bool> thread_destroyed = false;
  {
    PluginSessionIo session(token(), fake(state), clock);
    QObject::connect(PluginSessionIoTestAccess::io_thread(session),
                     &QObject::destroyed,
                     [&] { thread_destroyed.store(true); });
    start_and_await_running(session,
                            "session did not start for destruction test");
  }
  await_without_ui_dispatch(
      [&] {
        std::lock_guard lock(state->mutex);
        return state->terminate_count == 1 && state->destroy_count == 1 &&
               thread_destroyed.load();
      },
      "no-UI teardown did not destroy channel, worker, and QThread");
  std::lock_guard lock(state->mutex);
  require(state->wake_install_count == 1 && state->wake_clear_count == 1 &&
              !state->destroyed_with_wake_handler,
          "destruction retained a callback into the destroyed worker");
}

void test_destructor_does_not_wait_for_termination() {
  auto [state, clock] = ChannelFixture{};
  {
    PluginSessionIo session(token(), fake(state), clock);
    start_and_await_running_without_ui(
        session, "session did not start for asynchronous teardown test");
    std::lock_guard lock(state->mutex);
    state->block_terminate = true;
  }
  await_without_ui_dispatch(
      [&] {
        std::lock_guard lock(state->mutex);
        return state->terminate_entered;
      },
      "asynchronous termination did not begin");
  {
    std::lock_guard lock(state->mutex);
    state->release_terminate = true;
    state->condition.notify_all();
  }
  await(
      [&] {
        std::lock_guard lock(state->mutex);
        return state->terminate_count == 1;
      },
      "asynchronous termination did not finish");
}

void test_public_stop_is_ordered() {
  auto [state, clock] = ChannelFixture{};
  PluginSessionIo session(token(), fake(state), clock);
  start_and_await_running_without_ui(session,
                                     "session did not start for stop test");
  session.stop();
  await_state_without_ui(
      session, SessionState::stopped,
      "public stop did not reach a deterministic terminal state");
  std::lock_guard lock(state->mutex);
  require(state->terminate_count == 1,
          "public stop did not terminate the channel exactly once");
}

void test_revocation_preempts_remaining_receive_batch() {
  auto [state, clock] = ChannelFixture{};
  SessionLimits limits;
  limits.maximum_pump_batch = SessionLimits::kMaximumPumpBatch;
  // Keep this scheduling fixture short. The product ceiling also covers
  // explicitly profiled network providers and is not its latency budget.
  limits.io_timeout = std::chrono::milliseconds(1000);
  PluginSessionIo session(token(), fake(state), clock, nullptr, limits);
  start_and_await_running_without_ui(
      session, "revocation-latency fixture did not start");
  std::size_t before = 0;
  {
    std::lock_guard lock(state->mutex);
    before = state->receive_calls;
    for (std::uint64_t sequence = 1; sequence <= 128; ++sequence)
      state->incoming.push_back({.status = ReceiveStatus::message,
                                 .message = message(token(), sequence)});
    state->block_receive = true;
    state->receive_entered = false;
    state->release_receive = false;
  }
  session.wake();
  await_without_ui_dispatch(
      [&] {
        std::lock_guard lock(state->mutex);
        return state->receive_entered;
      },
      "revocation-latency fixture did not enter receive");
  session.revoke();
  {
    std::lock_guard lock(state->mutex);
    state->release_receive = true;
    state->condition.notify_all();
  }
  await_state_without_ui(session, SessionState::revoked,
                         "revocation remained behind the receive batch");
  std::lock_guard lock(state->mutex);
  require(state->receive_calls == before + 1,
          "pump performed receive work after the synchronous revoke fence");
}

void test_stale_blocked_send_cannot_override_revoke() {
  auto [state, clock] = ChannelFixture{};
  SessionLimits limits;
  limits.io_timeout = std::chrono::milliseconds(10);
  {
    std::lock_guard lock(state->mutex);
    state->block_send = true;
  }
  PluginSessionIo session(token(), fake(state, clock), clock, nullptr, limits);
  require(session.enqueue(message(token(), 1)),
          "blocked-send revoke fixture enqueue failed");
  session.start();
  await_without_ui_dispatch(
      [&] {
        std::lock_guard lock(state->mutex);
        return state->send_entered;
      },
      "blocked-send revoke fixture did not enter send");
  const auto calls_before_release = clock->calls();
  session.revoke();
  clock->advance(std::chrono::milliseconds(11));
  {
    std::lock_guard lock(state->mutex);
    state->send_status = SendStatus::fatal;
    state->release_send = true;
    state->condition.notify_all();
  }
  await_state_without_ui(
      session, SessionState::revoked,
      "stale expired/fatal send suppressed queued revoke");
  std::lock_guard lock(state->mutex);
  require(session.error() == SessionError::none && state->revoke_count == 1 &&
              state->terminate_count == 1 &&
              state->revoke_deadlines.size() == 1 &&
              state->terminate_deadlines.size() == 1 &&
              state->revoke_deadlines.front() ==
                  state->terminate_deadlines.front() &&
              clock->calls() == calls_before_release + 1,
          "stale send performed failure/deadline work after epoch changed");
}

void test_stale_blocked_receive_cannot_override_revoke() {
  auto [state, clock] = ChannelFixture{};
  SessionLimits limits;
  limits.io_timeout = std::chrono::milliseconds(10);
  {
    std::lock_guard lock(state->mutex);
    state->block_receive = true;
    state->incoming.push_back(
        {.status = ReceiveStatus::fatal, .message = OwnedMessage{}});
  }
  PluginSessionIo session(token(), fake(state, clock), clock, nullptr, limits);
  session.start();
  await_without_ui_dispatch(
      [&] {
        std::lock_guard lock(state->mutex);
        return state->receive_entered;
      },
      "blocked-receive revoke fixture did not enter receive");
  const auto calls_before_release = clock->calls();
  session.revoke();
  clock->advance(std::chrono::milliseconds(11));
  {
    std::lock_guard lock(state->mutex);
    state->release_receive = true;
    state->condition.notify_all();
  }
  await_state_without_ui(
      session, SessionState::revoked,
      "stale expired/fatal receive suppressed queued revoke");
  std::lock_guard lock(state->mutex);
  require(session.error() == SessionError::none && state->revoke_count == 1 &&
              state->terminate_count == 1 &&
              state->revoke_deadlines.size() == 1 &&
              state->terminate_deadlines.size() == 1 &&
              state->revoke_deadlines.front() ==
                  state->terminate_deadlines.front() &&
              clock->calls() == calls_before_release + 1,
          "stale receive performed failure/deadline work after epoch changed");
}

void test_in_flight_send_remains_inside_aggregate_queue_limit() {
  enum class Ceiling { messages, bytes, descriptors };
  const auto exercise = [](Ceiling ceiling) {
    auto [state, clock] = ChannelFixture{};
    SessionLimits limits;
    limits.maximum_queued_messages = ceiling == Ceiling::messages ? 1 : 2;
    limits.maximum_queued_bytes = ceiling == Ceiling::bytes ? 1 : 2;
    limits.maximum_descriptors_per_message = 1;
    limits.maximum_queued_descriptors =
        ceiling == Ceiling::descriptors ? 1 : 2;
    limits.maximum_pump_batch = 2;
    {
      std::lock_guard lock(state->mutex);
      state->block_send = true;
      state->send_status = SendStatus::would_block;
    }
    PluginSessionIo session(token(), fake(state), clock, nullptr, limits);
    int first_pipe[2]{-1, -1};
    int second_pipe[2]{-1, -1};
    const auto payload_bytes = ceiling == Ceiling::bytes ? 1U : 0U;
    auto first = message(token(), 1, payload_bytes);
    if (ceiling == Ceiling::descriptors) {
      require(::pipe2(first_pipe, O_CLOEXEC) == 0 &&
                  ::pipe2(second_pipe, O_CLOEXEC) == 0,
              "in-flight queue pipe fixture failed");
      first.descriptors.emplace_back(first_pipe[0]);
    }
    require(session.enqueue(std::move(first)),
            "bounded in-flight message was rejected");
    session.start();
    await_without_ui_dispatch(
        [&] {
          std::lock_guard lock(state->mutex);
          return state->send_entered;
        },
        "in-flight queue fixture did not enter send");
    auto second = message(token(), 2, payload_bytes);
    if (ceiling == Ceiling::descriptors)
      second.descriptors.emplace_back(second_pipe[0]);
    require(!session.enqueue(std::move(second)) &&
                session.error() == SessionError::queue_limit,
            "an in-flight send escaped its aggregate queue ceiling");
    if (ceiling == Ceiling::descriptors) {
      struct stat identity {};
      require(::fstat(second_pipe[0], &identity) != 0,
              "rejected in-flight descriptor was not released");
    }
    {
      std::lock_guard lock(state->mutex);
      state->release_send = true;
      state->condition.notify_all();
    }
    await_without_ui_dispatch(
        [&] {
          std::lock_guard lock(state->mutex);
          return !state->block_send;
        },
        "would-block send did not return ownership to the queue");
    {
      std::lock_guard lock(state->mutex);
      state->send_status = SendStatus::complete;
    }
    session.wake();
    await_without_ui_dispatch(
        [&] {
          std::lock_guard lock(state->mutex);
          return state->sent_sequences == std::vector<std::uint64_t>({1, 1});
        },
        "would-block in-flight message was not retried exactly once");
    session.stop();
    await_state_without_ui(session, SessionState::stopped,
                           "in-flight queue fixture did not stop");
    if (ceiling == Ceiling::descriptors) {
      ::close(first_pipe[1]);
      ::close(second_pipe[1]);
    }
  };
  exercise(Ceiling::messages);
  exercise(Ceiling::bytes);
  exercise(Ceiling::descriptors);
}

void test_pump_uses_one_absolute_deadline() {
  auto [state, clock] = ChannelFixture{};
  SessionLimits limits;
  limits.maximum_pump_batch = 4;
  limits.io_timeout = std::chrono::milliseconds(10);
  state->receive_cost = std::chrono::milliseconds(1);
  PluginSessionIo session(token(), fake(state, clock), clock, nullptr, limits);
  start_and_await_running_without_ui(
      session, "aggregate-pump-deadline fixture did not start");
  std::size_t before = 0;
  {
    std::lock_guard lock(state->mutex);
    before = state->receive_deadlines.size();
    state->incoming.push_back(
        {.status = ReceiveStatus::message, .message = message(token(), 1)});
    state->incoming.push_back(
        {.status = ReceiveStatus::message, .message = message(token(), 2)});
  }
  session.wake();
  await_without_ui_dispatch(
      [&] {
        std::lock_guard lock(state->mutex);
        return state->receive_deadlines.size() >= before + 2;
      },
      "aggregate-pump-deadline fixture did not fill its receive slice");
  std::lock_guard lock(state->mutex);
  require(state->receive_deadlines[before] ==
              state->receive_deadlines[before + 1],
          "receive slice refreshed its absolute deadline");
}

void test_queue_limit_is_aggregate_across_directions() {
  auto [state, clock] = ChannelFixture{};
  Observer observer;
  SessionLimits limits;
  limits.maximum_queued_messages = 1;
  limits.maximum_pump_batch = 2;
  PluginSessionIo session(token(), fake(state), clock, &observer, limits);
  start_and_await_running_without_ui(
      session, "aggregate-queue fixture did not start");
  std::size_t before = 0;
  {
    std::lock_guard lock(state->mutex);
    before = state->receive_calls;
    state->incoming.push_back(
        {.status = ReceiveStatus::message, .message = message(token(), 1)});
  }
  session.wake();
  await_without_ui_dispatch(
      [&] {
        std::lock_guard lock(state->mutex);
        return state->receive_calls >= before + 2;
      },
      "inbound delivery was not held for aggregate queue test");
  require(!session.enqueue(message(token(), 2)) &&
              session.error() == SessionError::queue_limit,
          "outbound queue exceeded the shared pending-delivery limit");
  QCoreApplication::processEvents();
}

void test_forced_start_and_invoke_failures_are_reaped() {
  auto clock = std::make_shared<FakeClock>();
  auto start_state = std::make_shared<ChannelState>();
  PluginSessionIoTestAccess::fail_next_thread_start();
  {
    PluginSessionIo session(token(), fake(start_state), clock);
    require(session.state() == SessionState::failed &&
                session.error() == SessionError::channel_failed &&
                PluginSessionIoTestAccess::io_thread(session) == nullptr,
            "forced thread-start failure was not fail-closed");
  }
  require(start_state->destroy_count == 1,
          "thread-start failure leaked the unlaunched channel");

  auto invoke_state = std::make_shared<ChannelState>();
  std::atomic<bool> thread_destroyed = false;
  {
    PluginSessionIo session(token(), fake(invoke_state), clock);
    auto *thread = PluginSessionIoTestAccess::io_thread(session);
    require(thread != nullptr, "invoke-failure fixture has no thread");
    QObject::connect(thread, &QObject::destroyed,
                     [&] { thread_destroyed.store(true); });
    start_and_await_running_without_ui(
        session, "invoke-failure fixture did not start");
    PluginSessionIoTestAccess::fail_next_invocation(session);
    session.stop();
    require(session.state() == SessionState::failed &&
                session.error() == SessionError::channel_failed,
            "forced invoke failure was not fail-closed");
    await_without_ui_dispatch(
        [&] {
          std::lock_guard lock(invoke_state->mutex);
          return invoke_state->terminate_count == 1 &&
                 invoke_state->destroy_count == 1;
        },
        "invoke failure did not terminate and destroy its worker/channel");
  }
  await_without_ui_dispatch(
      [&] { return thread_destroyed.load(); },
      "invoke-failure QThread was not reaped without UI events");
}

void test_observer_move_detaches_before_affinity_change() {
  auto [state, clock] = ChannelFixture{};
  QThread observer_thread;
  observer_thread.start();
  Observer observer;
  {
    PluginSessionIo session(token(), fake(state), clock, &observer);
    observer.moveToThread(&observer_thread);
    start_and_await_running(
        session, "session failed after safely detaching a moved observer");
    require(observer.states.empty() && observer.received.empty(),
            "callbacks followed an observer across an affinity change");
  }
  auto *ui_thread = QCoreApplication::instance()->thread();
  require(QMetaObject::invokeMethod(
              &observer,
              [&observer, ui_thread] { observer.moveToThread(ui_thread); },
              Qt::BlockingQueuedConnection),
          "moved observer fixture could not restore affinity");
  observer_thread.quit();
  observer_thread.wait();
}

void run() {
  test_thread_and_ordering();
  test_queue_bounds_and_fd_ownership();
  test_deadline_is_aggregate();
  test_limits_and_deadline_overflow_are_rejected();
  test_null_channel_and_no_start_are_safe();
  test_observer_affinity_mismatch_is_rejected();
  test_inbound_delivery_queue_is_bounded();
  test_stale_drop_and_delivery();
  test_queued_delivery_is_fenced_before_revoke();
  test_enqueue_is_fenced_synchronously();
  test_pump_requests_are_coalesced_and_batched();
  test_receive_is_fair_under_sustained_outbound();
  test_would_block_makes_no_progress_and_keeps_fd_owned();
  test_revoke_and_teardown_are_deterministic();
  test_channel_wake_is_worker_affine_and_fenced();
  test_destructor_stops_live_channel();
  test_destructor_does_not_wait_for_termination();
  test_public_stop_is_ordered();
  test_revocation_preempts_remaining_receive_batch();
  test_stale_blocked_send_cannot_override_revoke();
  test_stale_blocked_receive_cannot_override_revoke();
  test_in_flight_send_remains_inside_aggregate_queue_limit();
  test_pump_uses_one_absolute_deadline();
  test_queue_limit_is_aggregate_across_directions();
  test_forced_start_and_invoke_failures_are_reaped();
  test_observer_move_detaches_before_affinity_change();
}

} // namespace

int main(int argc, char **argv) {
  QCoreApplication application(argc, argv);
  try {
    run();
  } catch (const std::exception &error) {
    std::cerr << "plugin session I/O test failed: " << error.what() << '\n';
    return 1;
  }
  std::cout << "plugin session I/O test passed\n";
  return 0;
}
