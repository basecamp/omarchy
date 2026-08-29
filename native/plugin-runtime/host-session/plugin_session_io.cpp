#include "plugin_session_io.hpp"

#include <QCoreApplication>
#include <QEvent>
#include <QMetaObject>
#include <QPointer>

#include <algorithm>
#include <atomic>
#include <deque>
#include <mutex>
#include <optional>
#include <utility>

#include <unistd.h>

namespace omarchy::plugin_runtime::host_session {

OwnedFd::OwnedFd(int descriptor) noexcept : descriptor_(descriptor) {}
OwnedFd::OwnedFd(OwnedFd &&other) noexcept : descriptor_(other.release()) {}
OwnedFd &OwnedFd::operator=(OwnedFd &&other) noexcept {
  if (this != &other)
    reset(other.release());
  return *this;
}
OwnedFd::~OwnedFd() { reset(); }
int OwnedFd::get() const noexcept { return descriptor_; }
OwnedFd::operator bool() const noexcept { return descriptor_ >= 0; }
int OwnedFd::release() noexcept { return std::exchange(descriptor_, -1); }
void OwnedFd::reset(int descriptor) noexcept {
  if (descriptor_ >= 0)
    ::close(descriptor_);
  descriptor_ = descriptor;
}

SessionClock::TimePoint SteadySessionClock::now() const noexcept {
  return std::chrono::steady_clock::now();
}

struct PluginSessionSharedState {
  SessionToken token;
  SessionLimits limits;
  std::shared_ptr<const SessionClock> clock;
  mutable std::mutex mutex;
  QObject *delivery_target = nullptr;
  std::deque<OwnedMessage> outbound;
  std::size_t outbound_in_flight = 0;
  std::size_t outbound_bytes = 0;
  std::size_t outbound_descriptors = 0;
  std::size_t delivery_messages = 0;
  std::size_t delivery_bytes = 0;
  std::size_t delivery_descriptors = 0;
  std::uint64_t epoch = 1;
  std::uint64_t last_outbound_sequence = 0;
  std::uint64_t last_inbound_sequence = 0;
  bool accepting = true;
  bool pump_queued = false;
  bool configuration_valid = true;
  std::uint64_t pump_ticket = 0;
  std::atomic<SessionState> state{SessionState::idle};
  std::atomic<SessionError> error{SessionError::none};
  std::atomic<std::uint64_t> stale_drops{0};
};

struct PluginSessionRuntimeOwner {
  std::mutex mutex;
  QObject *worker = nullptr;
  QThread *thread = nullptr;
  bool thread_finished = false;
  bool owner_detached = false;
  bool reap_queued = false;
#ifdef OMARCHY_PLUGIN_SESSION_IO_TESTING
  bool fail_next_invocation = false;
#endif
};

class PluginSessionDeliveryProxy final : public QObject {
public:
  PluginSessionDeliveryProxy(SessionObserver *observer, QObject *parent)
      : QObject(parent), observer_(observer), observer_identity_(observer) {
    if (observer_identity_ != nullptr)
      observer_identity_->installEventFilter(this);
  }

  void state(SessionState state, SessionError error) {
    if (observer_ && observer_->thread() == QThread::currentThread())
      observer_->state_changed(state, error);
  }

  void message(OwnedMessage value) {
    if (observer_ && observer_->thread() == QThread::currentThread())
      observer_->message_received(std::move(value));
  }

private:
  bool eventFilter(QObject *watched, QEvent *event) override {
    if (watched == observer_identity_ &&
        event->type() == QEvent::ThreadChange) {
      watched->removeEventFilter(this);
      observer_.clear();
      observer_identity_ = nullptr;
    }
    return false;
  }

  QPointer<SessionObserver> observer_;
  QObject *observer_identity_ = nullptr;
};

namespace {

bool valid_token(const SessionToken &token) {
  return !token.plugin_id.empty() && token.revision_sha256.size() == 64 &&
         token.generation != 0 && token.session_nonce != 0;
}

bool valid_limits(const SessionLimits &limits) {
  return limits.maximum_queued_messages != 0 &&
         limits.maximum_queued_messages <= SessionLimits::kMaximumMessages &&
         limits.maximum_queued_bytes != 0 &&
         limits.maximum_queued_bytes <= SessionLimits::kMaximumBytes &&
         limits.maximum_descriptors_per_message != 0 &&
         limits.maximum_descriptors_per_message <=
             SessionLimits::kMaximumDescriptors &&
         limits.maximum_queued_descriptors != 0 &&
         limits.maximum_queued_descriptors <=
             SessionLimits::kMaximumDescriptors &&
         limits.maximum_descriptors_per_message <=
             limits.maximum_queued_descriptors &&
         limits.maximum_pump_batch >= 2 && limits.startup_timeout.count() > 0 &&
         limits.maximum_pump_batch <= SessionLimits::kMaximumPumpBatch &&
         limits.startup_timeout <= SessionLimits::kMaximumStartupTimeout &&
         limits.io_timeout.count() > 0 &&
         limits.io_timeout <= SessionLimits::kMaximumIoTimeout;
}

bool valid_message_shape(const OwnedMessage &message,
                         const SessionLimits &limits) {
  return message.message_type != 0 && message.sequence != 0 &&
         message.payload.size() <= limits.maximum_queued_bytes &&
         message.descriptors.size() <= limits.maximum_descriptors_per_message &&
         (message.lane == ChannelLane::render || message.descriptors.empty());
}

bool combined_queue_has_room(const PluginSessionSharedState &shared,
                             std::size_t messages, std::size_t bytes,
                             std::size_t descriptors) {
  const auto &limits = shared.limits;
  const auto outbound_messages =
      shared.outbound.size() + shared.outbound_in_flight;
  return outbound_messages <= limits.maximum_queued_messages &&
         shared.delivery_messages <=
             limits.maximum_queued_messages - outbound_messages &&
         messages <= limits.maximum_queued_messages - outbound_messages -
                         shared.delivery_messages &&
         shared.outbound_bytes <= limits.maximum_queued_bytes &&
         shared.delivery_bytes <=
             limits.maximum_queued_bytes - shared.outbound_bytes &&
         bytes <= limits.maximum_queued_bytes - shared.outbound_bytes -
                      shared.delivery_bytes &&
         shared.outbound_descriptors <= limits.maximum_queued_descriptors &&
         shared.delivery_descriptors <=
             limits.maximum_queued_descriptors - shared.outbound_descriptors &&
         descriptors <= limits.maximum_queued_descriptors -
                            shared.outbound_descriptors -
                            shared.delivery_descriptors;
}

SessionError map_error(ChannelError error) {
  switch (error) {
  case ChannelError::launch_failed:
    return SessionError::launch_failed;
  case ChannelError::handshake_failed:
    return SessionError::handshake_failed;
  case ChannelError::protocol_failed:
    return SessionError::channel_failed;
  case ChannelError::none:
    break;
  }
  return SessionError::none;
}

std::optional<SessionChannel::TimePoint>
make_deadline(const SessionClock &clock, std::chrono::milliseconds duration) {
  if (duration.count() <= 0 || duration > SessionLimits::kMaximumStartupTimeout)
    return std::nullopt;
  const auto now = clock.now();
  const auto delta =
      std::chrono::duration_cast<SessionChannel::TimePoint::duration>(duration);
  if (now.time_since_epoch() >
      SessionChannel::TimePoint::max().time_since_epoch() - delta)
    return std::nullopt;
  return now + delta;
}

bool queue_state(const std::shared_ptr<PluginSessionSharedState> &shared,
                 std::uint64_t epoch, SessionState state, SessionError error) {
  std::lock_guard lock(shared->mutex);
  if (shared->epoch != epoch)
    return true;
  shared->error.store(error);
  // State is the publication flag; readers that observe it also see error.
  shared->state.store(state);
  if (shared->delivery_target == nullptr)
    return true;
  auto *target =
      static_cast<PluginSessionDeliveryProxy *>(shared->delivery_target);
  return QMetaObject::invokeMethod(
      target,
      [shared, target, epoch, state, error] {
        bool deliver = false;
        {
          std::lock_guard lock(shared->mutex);
          deliver = shared->epoch == epoch && shared->delivery_target == target;
        }
        if (deliver)
          target->state(state, error);
      },
      Qt::QueuedConnection);
}

bool queue_delivery(const std::shared_ptr<PluginSessionSharedState> &shared,
                    std::uint64_t epoch, OwnedMessage message) {
  const auto bytes = message.payload.size();
  const auto descriptors = message.descriptors.size();
  std::lock_guard lock(shared->mutex);
  if (shared->epoch != epoch || !shared->accepting)
    return true;
  if (shared->delivery_target == nullptr)
    return true;
  if (!combined_queue_has_room(*shared, 1, bytes, descriptors))
    return false;
  ++shared->delivery_messages;
  shared->delivery_bytes += bytes;
  shared->delivery_descriptors += descriptors;
  auto *target =
      static_cast<PluginSessionDeliveryProxy *>(shared->delivery_target);
  const bool queued = QMetaObject::invokeMethod(
      target,
      [shared, target, epoch, message = std::move(message), bytes,
       descriptors]() mutable {
        bool deliver = false;
        {
          std::lock_guard lock(shared->mutex);
          --shared->delivery_messages;
          shared->delivery_bytes -= bytes;
          shared->delivery_descriptors -= descriptors;
          deliver = shared->epoch == epoch && shared->accepting &&
                    shared->delivery_target == target;
        }
        if (deliver)
          target->message(std::move(message));
      },
      Qt::QueuedConnection);
  if (!queued) {
    --shared->delivery_messages;
    shared->delivery_bytes -= bytes;
    shared->delivery_descriptors -= descriptors;
  }
  return queued;
}

// QThread objects are reaped on this process-lifetime runtime thread. Session
// destruction therefore never blocks and does not depend on UI event dispatch.
struct RuntimeReaper {
  QThread thread;
  QObject context;
  RuntimeReaper() {
    context.moveToThread(&thread);
    thread.start();
  }
};

RuntimeReaper &runtime_reaper() {
  static auto *value = new RuntimeReaper;
  return *value;
}

#ifdef OMARCHY_PLUGIN_SESSION_IO_TESTING
std::atomic<bool> force_thread_start_failure{false};
#endif

void queue_reap(const std::shared_ptr<PluginSessionRuntimeOwner> &runtime,
                QThread *thread) {
  auto &reaper = runtime_reaper();
  if (!QMetaObject::invokeMethod(
          &reaper.context, [runtime, thread] { delete thread; },
          Qt::QueuedConnection)) {
    // The process-lifetime reaper is deliberately never stopped. If Qt still
    // refuses the queue, leaking is safer than deleting a foreign-affinity
    // QThread or exposing a dangling owner pointer.
    std::lock_guard lock(runtime->mutex);
    runtime->reap_queued = false;
  }
}

} // namespace

class PluginSessionIo::Worker final : public QObject {
public:
  Worker(std::shared_ptr<PluginSessionSharedState> shared,
         std::unique_ptr<SessionChannel> channel, QThread &thread)
      : shared_(std::move(shared)), channel_(std::move(channel)),
        thread_(thread) {}
  ~Worker() override {
    if (!terminal_)
      terminate_channel(operation_deadline());
  }

  void start(std::uint64_t epoch) {
    if (terminal_ || !current(epoch, true) ||
        shared_->state.load() != SessionState::idle)
      return;
    if (!channel_ || !shared_->clock || !shared_->configuration_valid ||
        !valid_token(shared_->token) || !valid_limits(shared_->limits)) {
      fail(epoch, !valid_token(shared_->token)
                      ? SessionError::invalid_token
                      : SessionError::invalid_configuration);
      return;
    }
    if (!queue_state(shared_, epoch, SessionState::starting,
                     SessionError::none)) {
      host_lost();
      return;
    }
    const auto startup_deadline =
        make_deadline(*shared_->clock, shared_->limits.startup_timeout);
    if (!startup_deadline) {
      fail(epoch, SessionError::invalid_configuration);
      return;
    }
    auto result = channel_->launch(shared_->token, *startup_deadline);
    if (!current(epoch, true))
      return;
    if (shared_->clock->now() >= *startup_deadline) {
      fail(epoch, SessionError::startup_deadline_expired);
      return;
    }
    if (result != ChannelError::none) {
      fail(epoch, map_error(result));
      return;
    }
    result = channel_->handshake(*startup_deadline);
    if (!current(epoch, true))
      return;
    if (shared_->clock->now() >= *startup_deadline) {
      fail(epoch, SessionError::startup_deadline_expired);
      return;
    }
    if (result != ChannelError::none) {
      fail(epoch, map_error(result));
      return;
    }
    if (!queue_state(shared_, epoch, SessionState::running,
                     SessionError::none)) {
      host_lost();
      return;
    }
    schedule_pump(epoch);
  }

  void pump(std::uint64_t epoch, std::uint64_t ticket) {
    {
      std::lock_guard lock(shared_->mutex);
      if (!shared_->pump_queued || shared_->pump_ticket != ticket)
        return;
      shared_->pump_queued = false;
    }
    if (terminal_ || !current(epoch, true) ||
        shared_->state.load() != SessionState::running || !channel_)
      return;

    // One absolute deadline bounds the entire pump slice, including every
    // send and receive. Control work therefore waits for at most one I/O
    // timeout rather than one timeout per item in a maximum-sized batch.
    const auto pump_deadline = operation_deadline();
    if (!pump_deadline) {
      fail(epoch, SessionError::invalid_configuration);
      return;
    }

    const auto outbound_budget = shared_->limits.maximum_pump_batch / 2;
    const auto inbound_budget =
        shared_->limits.maximum_pump_batch - outbound_budget;
    bool outbound_blocked = false;
    bool outbound_remaining = false;
    for (std::size_t work = 0; work < outbound_budget; ++work) {
      OwnedMessage outgoing;
      bool has_outgoing = false;
      {
        std::lock_guard lock(shared_->mutex);
        if (shared_->epoch != epoch || !shared_->accepting)
          return;
        if (!shared_->outbound.empty()) {
          outgoing = std::move(shared_->outbound.front());
          shared_->outbound.pop_front();
          ++shared_->outbound_in_flight;
          has_outgoing = true;
        }
      }
      if (!has_outgoing)
        break;
      if (!current(epoch, true))
        return;
      const auto sent = channel_->send(outgoing, *pump_deadline);
      if (!current(epoch, true))
        return;
      if (shared_->clock->now() >= *pump_deadline) {
        finish_outgoing(epoch, outgoing);
        fail(epoch, SessionError::io_deadline_expired);
        return;
      }
      if (sent == SendStatus::would_block) {
        std::lock_guard lock(shared_->mutex);
        if (shared_->epoch == epoch && shared_->accepting) {
          --shared_->outbound_in_flight;
          shared_->outbound.push_front(std::move(outgoing));
        }
        outbound_blocked = true;
        break;
      }
      if (sent != SendStatus::complete) {
        finish_outgoing(epoch, outgoing);
        fail(epoch, SessionError::channel_failed);
        return;
      }
      finish_outgoing(epoch, outgoing);
    }
    {
      std::lock_guard lock(shared_->mutex);
      outbound_remaining = !shared_->outbound.empty();
    }

    bool inbound_full = true;
    for (std::size_t work = 0; work < inbound_budget; ++work) {
      if (!current(epoch, true))
        return;
      auto incoming = channel_->receive(*pump_deadline);
      if (!current(epoch, true))
        return;
      if (shared_->clock->now() >= *pump_deadline) {
        fail(epoch, SessionError::io_deadline_expired);
        return;
      }
      if (incoming.status == ReceiveStatus::would_block) {
        inbound_full = false;
        break;
      }
      if (incoming.status != ReceiveStatus::message) {
        fail(epoch, SessionError::channel_failed);
        return;
      }
      if (!(incoming.message.token == shared_->token) ||
          incoming.message.sequence <= shared_->last_inbound_sequence) {
        ++shared_->stale_drops;
      } else if (!valid_message_shape(incoming.message, shared_->limits)) {
        fail(epoch, SessionError::channel_failed);
        return;
      } else {
        shared_->last_inbound_sequence = incoming.message.sequence;
        if (!queue_delivery(shared_, epoch, std::move(incoming.message))) {
          fail(epoch, SessionError::queue_limit);
          return;
        }
      }
    }
    // A blocked send needs a readiness wake; rescheduling it would busy-spin.
    // A full receive slice or remaining writable outbound work gets one ticket.
    if ((!outbound_blocked && outbound_remaining) || inbound_full)
      schedule_pump(epoch);
  }

  void revoke(std::uint64_t epoch) {
    if (terminal_)
      return;
    const auto io_deadline = operation_deadline();
    if (channel_ && io_deadline)
      (void)channel_->revoke(shared_->token, *io_deadline);
    terminate_channel(io_deadline);
    terminal_ = true;
    if (!queue_state(shared_, epoch, SessionState::revoked, SessionError::none))
      host_lost();
  }

  void stop(std::uint64_t epoch, bool destruction) {
    if (!terminal_)
      terminate_channel(operation_deadline());
    terminal_ = true;
    if (!destruction)
      if (!queue_state(shared_, epoch, SessionState::stopped,
                       shared_->error.load()))
        host_lost();
    if (destruction)
      thread_.quit();
  }

private:
  void finish_outgoing(std::uint64_t epoch, const OwnedMessage &message) {
    std::lock_guard lock(shared_->mutex);
    if (shared_->epoch != epoch || !shared_->accepting)
      return;
    --shared_->outbound_in_flight;
    shared_->outbound_bytes -= message.payload.size();
    shared_->outbound_descriptors -= message.descriptors.size();
  }

  bool current(std::uint64_t epoch, bool require_accepting) const {
    std::lock_guard lock(shared_->mutex);
    return shared_->epoch == epoch &&
           (!require_accepting || shared_->accepting);
  }

  std::optional<SessionChannel::TimePoint> operation_deadline() const {
    if (!shared_->clock)
      return std::nullopt;
    return make_deadline(*shared_->clock, shared_->limits.io_timeout);
  }

  void terminate_channel(std::optional<SessionChannel::TimePoint> value) {
    if (channel_ && value)
      channel_->terminate(*value);
  }

  void fail(std::uint64_t epoch, SessionError error) {
    terminate_channel(operation_deadline());
    terminal_ = true;
    if (!queue_state(shared_, epoch, SessionState::failed, error))
      thread_.quit();
  }

  void host_lost() {
    terminate_channel(operation_deadline());
    terminal_ = true;
    thread_.quit();
  }

  void schedule_pump(std::uint64_t epoch) {
    std::uint64_t ticket = 0;
    {
      std::lock_guard lock(shared_->mutex);
      if (shared_->epoch != epoch || !shared_->accepting ||
          shared_->pump_queued)
        return;
      shared_->pump_queued = true;
      ticket = ++shared_->pump_ticket;
    }
    if (!QMetaObject::invokeMethod(
            this, [this, epoch, ticket] { pump(epoch, ticket); },
            Qt::QueuedConnection)) {
      {
        std::lock_guard lock(shared_->mutex);
        if (shared_->pump_ticket == ticket)
          shared_->pump_queued = false;
      }
      host_lost();
    }
  }

  std::shared_ptr<PluginSessionSharedState> shared_;
  std::unique_ptr<SessionChannel> channel_;
  QThread &thread_;
  bool terminal_ = false;
};

PluginSessionIo::PluginSessionIo(SessionToken token,
                                 std::unique_ptr<SessionChannel> channel,
                                 std::shared_ptr<const SessionClock> clock,
                                 SessionObserver *observer,
                                 SessionLimits limits, QObject *parent)
    : QObject(parent), shared_(std::make_shared<PluginSessionSharedState>()),
      runtime_(std::make_shared<PluginSessionRuntimeOwner>()) {
  shared_->token = std::move(token);
  shared_->limits = limits;
  shared_->clock = std::move(clock);
  shared_->configuration_valid =
      observer == nullptr || observer->thread() == thread();
  delivery_ = new PluginSessionDeliveryProxy(
      shared_->configuration_valid ? observer : nullptr, this);
  shared_->delivery_target = delivery_;
#ifdef OMARCHY_PLUGIN_SESSION_IO_TESTING
  if (force_thread_start_failure.exchange(false)) {
    shared_->accepting = false;
    shared_->error.store(SessionError::channel_failed);
    shared_->state.store(SessionState::failed);
    return;
  }
#endif
  auto &reaper = runtime_reaper();
  auto *io_thread = new QThread;
  io_thread->moveToThread(&reaper.thread);
  auto *worker = new Worker(shared_, std::move(channel), *io_thread);
  worker->moveToThread(io_thread);
  {
    std::lock_guard lock(runtime_->mutex);
    runtime_->thread = io_thread;
    runtime_->worker = worker;
  }
  QObject::connect(io_thread, &QThread::finished, worker,
                   &QObject::deleteLater);
  const auto runtime = runtime_;
  QObject::connect(
      io_thread, &QThread::finished, io_thread,
      [runtime, worker, io_thread] {
        bool reap = false;
        {
          std::lock_guard lock(runtime->mutex);
          if (runtime->worker == worker)
            runtime->worker = nullptr;
          runtime->thread_finished = true;
          if (runtime->owner_detached && !runtime->reap_queued) {
            runtime->thread = nullptr;
            runtime->reap_queued = true;
            reap = true;
          }
        }
        if (reap)
          queue_reap(runtime, io_thread);
      },
      Qt::DirectConnection);
  io_thread->start();
}

PluginSessionIo::~PluginSessionIo() {
  fence_and_queue(false, true);
  QCoreApplication::removePostedEvents(delivery_);
  detach_runtime();
}

void PluginSessionIo::start() {
  std::lock_guard lock(shared_->mutex);
  if (!shared_->accepting || shared_->state.load() != SessionState::idle)
    return;
  const auto epoch = shared_->epoch;
  if (!queue_worker([epoch](Worker &worker) { worker.start(epoch); }))
    invocation_failed_locked();
}

bool PluginSessionIo::enqueue(OwnedMessage message) {
  std::lock_guard lock(shared_->mutex);
  const auto current = shared_->state.load();
  if (!shared_->accepting ||
      (current != SessionState::idle && current != SessionState::starting &&
       current != SessionState::running))
    return false;
  if (!(message.token == shared_->token) ||
      message.sequence <= shared_->last_outbound_sequence) {
    ++shared_->stale_drops;
    return false;
  }
  if (!valid_message_shape(message, shared_->limits) ||
      !combined_queue_has_room(*shared_, 1, message.payload.size(),
                               message.descriptors.size())) {
    shared_->error.store(SessionError::queue_limit);
    return false;
  }
  shared_->last_outbound_sequence = message.sequence;
  shared_->outbound_bytes += message.payload.size();
  shared_->outbound_descriptors += message.descriptors.size();
  shared_->outbound.push_back(std::move(message));
  const auto epoch = shared_->epoch;
  if (current == SessionState::running && !schedule_pump_locked(epoch))
    return false;
  return true;
}

void PluginSessionIo::wake() {
  std::lock_guard lock(shared_->mutex);
  if (!shared_->accepting || shared_->state.load() != SessionState::running)
    return;
  (void)schedule_pump_locked(shared_->epoch);
}

void PluginSessionIo::revoke() { fence_and_queue(true, false); }
void PluginSessionIo::stop() { fence_and_queue(false, false); }
SessionState PluginSessionIo::state() const noexcept {
  return shared_->state.load();
}
SessionError PluginSessionIo::error() const noexcept {
  return shared_->error.load();
}
std::uint64_t PluginSessionIo::stale_messages_dropped() const noexcept {
  return shared_->stale_drops.load();
}
QThread *PluginSessionIo::io_thread() const noexcept {
  std::lock_guard lock(runtime_->mutex);
  return runtime_->thread;
}

void PluginSessionIo::fence_and_queue(bool revoke, bool destruction) {
  std::uint64_t epoch = 0;
  {
    std::lock_guard lock(shared_->mutex);
    if (!shared_->accepting && !destruction)
      return;
    shared_->accepting = false;
    ++shared_->epoch;
    epoch = shared_->epoch;
    shared_->outbound.clear();
    shared_->outbound_in_flight = 0;
    shared_->outbound_bytes = 0;
    shared_->outbound_descriptors = 0;
    shared_->pump_queued = false;
    if (revoke)
      shared_->error.store(SessionError::none);
    shared_->state.store(revoke ? SessionState::revoking
                                : SessionState::stopping);
    if (destruction) {
      shared_->delivery_target = nullptr;
    }
  }
  if (revoke) {
    if (!queue_state(shared_, epoch, SessionState::revoking,
                     SessionError::none)) {
      std::lock_guard lock(shared_->mutex);
      invocation_failed_locked();
      return;
    }
    if (!queue_worker([epoch](Worker &worker) { worker.revoke(epoch); })) {
      std::lock_guard lock(shared_->mutex);
      invocation_failed_locked();
      return;
    }
  } else {
    if (!destruction)
      if (!queue_state(shared_, epoch, SessionState::stopping,
                       shared_->error.load())) {
        std::lock_guard lock(shared_->mutex);
        invocation_failed_locked();
        return;
      }
    if (!queue_worker([epoch, destruction](Worker &worker) {
          worker.stop(epoch, destruction);
        })) {
      std::lock_guard lock(shared_->mutex);
      invocation_failed_locked();
      return;
    }
  }
}

bool PluginSessionIo::schedule_pump_locked(std::uint64_t epoch) {
  if (shared_->pump_queued)
    return true;
  shared_->pump_queued = true;
  const auto ticket = ++shared_->pump_ticket;
  if (queue_worker(
          [epoch, ticket](Worker &worker) { worker.pump(epoch, ticket); }))
    return true;
  shared_->pump_queued = false;
  invocation_failed_locked();
  return false;
}

void PluginSessionIo::invocation_failed_locked() noexcept {
  shared_->accepting = false;
  ++shared_->epoch;
  shared_->pump_queued = false;
  shared_->outbound.clear();
  shared_->outbound_in_flight = 0;
  shared_->outbound_bytes = 0;
  shared_->outbound_descriptors = 0;
  shared_->error.store(SessionError::channel_failed);
  shared_->state.store(SessionState::failed);
  std::lock_guard runtime_lock(runtime_->mutex);
  runtime_->worker = nullptr;
  if (runtime_->thread) {
    auto *thread = runtime_->thread;
    thread->requestInterruption();
    thread->quit();
  }
}

template <typename Operation>
bool PluginSessionIo::queue_worker(Operation operation) {
  std::lock_guard lock(runtime_->mutex);
#ifdef OMARCHY_PLUGIN_SESSION_IO_TESTING
  if (runtime_->fail_next_invocation) {
    runtime_->fail_next_invocation = false;
    return false;
  }
#endif
  if (runtime_->worker == nullptr || runtime_->thread_finished)
    return false;
  auto *worker = static_cast<Worker *>(runtime_->worker);
  return QMetaObject::invokeMethod(
      worker,
      [worker, operation = std::move(operation)]() mutable {
        operation(*worker);
      },
      Qt::QueuedConnection);
}

void PluginSessionIo::detach_runtime() noexcept {
  QThread *thread = nullptr;
  {
    std::lock_guard lock(runtime_->mutex);
    runtime_->owner_detached = true;
    runtime_->worker = nullptr;
    if (runtime_->thread_finished && runtime_->thread != nullptr &&
        !runtime_->reap_queued) {
      thread = runtime_->thread;
      runtime_->thread = nullptr;
      runtime_->reap_queued = true;
    }
  }
  if (thread != nullptr)
    queue_reap(runtime_, thread);
}

#ifdef OMARCHY_PLUGIN_SESSION_IO_TESTING
void PluginSessionIoTestAccess::fail_next_thread_start() noexcept {
  force_thread_start_failure.store(true);
}

void PluginSessionIoTestAccess::fail_next_invocation(
    PluginSessionIo &session) noexcept {
  std::lock_guard lock(session.runtime_->mutex);
  session.runtime_->fail_next_invocation = true;
}
#endif

} // namespace omarchy::plugin_runtime::host_session
