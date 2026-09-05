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

struct QueueUsage {
  std::size_t messages = 0;
  std::size_t bytes = 0;
  std::size_t descriptors = 0;

  [[nodiscard]] static QueueUsage message(const OwnedMessage &value) noexcept {
    return {.messages = 1, .bytes = value.payload.size(),
            .descriptors = value.descriptors.size()};
  }

  [[nodiscard]] bool try_add(const QueueUsage &other,
                             const SessionLimits &limits) noexcept {
    const auto fits = [](std::size_t used, std::size_t added,
                         std::size_t maximum) {
      return used <= maximum && added <= maximum - used;
    };
    if (!fits(messages, other.messages, limits.maximum_queued_messages) ||
        !fits(bytes, other.bytes, limits.maximum_queued_bytes) ||
        !fits(descriptors, other.descriptors,
              limits.maximum_queued_descriptors))
      return false;
    messages += other.messages;
    bytes += other.bytes;
    descriptors += other.descriptors;
    return true;
  }

  [[nodiscard]] bool remove(const QueueUsage &other) noexcept {
    if (other.messages > messages || other.bytes > bytes ||
        other.descriptors > descriptors)
      return false;
    messages -= other.messages;
    bytes -= other.bytes;
    descriptors -= other.descriptors;
    return true;
  }
};

struct PluginSessionSharedState {
  SessionToken token;
  SessionLimits limits;
  std::shared_ptr<const SessionClock> clock;
  mutable std::mutex mutex;
  PluginSessionDeliveryProxy *delivery_target = nullptr;
  std::deque<OwnedMessage> outbound;
  QueueUsage outbound_usage;
  QueueUsage delivery_usage;
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
                             const QueueUsage &candidate) {
  auto aggregate = shared.outbound_usage;
  return aggregate.try_add(shared.delivery_usage, shared.limits) &&
         aggregate.try_add(candidate, shared.limits);
}

struct PumpTicketClaim {
  bool accepted = false;
  std::optional<std::uint64_t> ticket;
};

// The caller holds shared.mutex. An accepted claim without a ticket means a
// pump is already queued; this is successful coalescing, not a queue failure.
PumpTicketClaim claim_pump_locked(PluginSessionSharedState &shared,
                                  std::uint64_t epoch) {
  if (shared.epoch != epoch || !shared.accepting)
    return {};
  if (shared.pump_queued)
    return {.accepted = true, .ticket = std::nullopt};
  shared.pump_queued = true;
  return {.accepted = true, .ticket = ++shared.pump_ticket};
}

void rollback_pump_locked(PluginSessionSharedState &shared,
                          std::uint64_t ticket) noexcept {
  if (shared.pump_ticket == ticket)
    shared.pump_queued = false;
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
  auto *target = shared->delivery_target;
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
  const auto usage = QueueUsage::message(message);
  std::lock_guard lock(shared->mutex);
  if (shared->epoch != epoch || !shared->accepting)
    return true;
  if (shared->delivery_target == nullptr)
    return true;
  if (!combined_queue_has_room(*shared, usage) ||
      !shared->delivery_usage.try_add(usage, shared->limits))
    return false;
  auto *target = shared->delivery_target;
  const bool queued = QMetaObject::invokeMethod(
      target,
      [shared, target, epoch, message = std::move(message), usage]() mutable {
        bool deliver = false;
        {
          std::lock_guard lock(shared->mutex);
          const bool removed = shared->delivery_usage.remove(usage);
          Q_ASSERT(removed);
          deliver = removed && shared->epoch == epoch && shared->accepting &&
                    shared->delivery_target == target;
        }
        if (deliver)
          target->message(std::move(message));
      },
      Qt::QueuedConnection);
  if (!queued) {
    const bool removed = shared->delivery_usage.remove(usage);
    Q_ASSERT(removed);
    (void)removed;
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
    clear_wake_handler();
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
    if (!install_wake_handler(epoch)) {
      fail(epoch, SessionError::channel_failed);
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
    clear_wake_handler();
    const auto io_deadline = operation_deadline();
    if (channel_ && io_deadline)
      (void)channel_->revoke(shared_->token, *io_deadline);
    terminate_channel(io_deadline);
    terminal_ = true;
    if (!queue_state(shared_, epoch, SessionState::revoked, SessionError::none))
      host_lost();
  }

  void stop(std::uint64_t epoch, TerminationIntent intent) {
    clear_wake_handler();
    if (!terminal_)
      terminate_channel(operation_deadline());
    terminal_ = true;
    if (intent == TerminationIntent::stop)
      if (!queue_state(shared_, epoch, SessionState::stopped,
                       shared_->error.load()))
        host_lost();
    if (intent == TerminationIntent::destroy)
      thread_.quit();
  }

private:
  void finish_outgoing(std::uint64_t epoch, const OwnedMessage &message) {
    std::lock_guard lock(shared_->mutex);
    if (shared_->epoch != epoch || !shared_->accepting)
      return;
    const bool removed =
        shared_->outbound_usage.remove(QueueUsage::message(message));
    Q_ASSERT(removed);
    (void)removed;
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
    clear_wake_handler();
    terminate_channel(operation_deadline());
    terminal_ = true;
    if (!queue_state(shared_, epoch, SessionState::failed, error))
      thread_.quit();
  }

  void host_lost() {
    clear_wake_handler();
    terminate_channel(operation_deadline());
    terminal_ = true;
    thread_.quit();
  }

  void schedule_pump(std::uint64_t epoch) {
    PumpTicketClaim claim;
    {
      std::lock_guard lock(shared_->mutex);
      claim = claim_pump_locked(*shared_, epoch);
      if (!claim.accepted || !claim.ticket)
        return;
    }
    const auto ticket = *claim.ticket;
    if (!QMetaObject::invokeMethod(
            this, [this, epoch, ticket] { pump(epoch, ticket); },
            Qt::QueuedConnection)) {
      {
        std::lock_guard lock(shared_->mutex);
        rollback_pump_locked(*shared_, ticket);
      }
      host_lost();
    }
  }

  static void channel_wake(void *context) noexcept {
    auto *worker = static_cast<Worker *>(context);
    if (worker == nullptr)
      return;
    try {
      worker->schedule_pump(worker->wake_epoch_);
    } catch (...) {
      // A readiness callback is a C/Qt noexcept boundary. Allocation failure
      // while queuing the pump must fail the session, never abort the host.
      try {
        worker->host_lost();
      } catch (...) {
        worker->terminal_ = true;
        worker->shared_->error.store(SessionError::channel_failed);
        worker->shared_->state.store(SessionState::failed);
        try {
          worker->thread_.quit();
        } catch (...) {
        }
      }
    }
  }

  [[nodiscard]] bool install_wake_handler(std::uint64_t epoch) noexcept {
    if (!channel_ || wake_handler_installed_)
      return false;
    wake_epoch_ = epoch;
    wake_handler_installed_ = channel_->install_wake_handler(
        {.function = &Worker::channel_wake, .context = this});
    if (!wake_handler_installed_)
      wake_epoch_ = 0;
    return wake_handler_installed_;
  }

  void clear_wake_handler() noexcept {
    if (!wake_handler_installed_ || !channel_)
      return;
    // Clearing is synchronous by contract, so `this` cannot be observed after
    // this call even when teardown proceeds without waiting for I/O.
    channel_->clear_wake_handler();
    wake_handler_installed_ = false;
    wake_epoch_ = 0;
  }

  std::shared_ptr<PluginSessionSharedState> shared_;
  std::unique_ptr<SessionChannel> channel_;
  QThread &thread_;
  bool terminal_ = false;
  bool wake_handler_installed_ = false;
  std::uint64_t wake_epoch_ = 0;
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
  fence_and_queue(TerminationIntent::destroy);
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
  const auto usage = QueueUsage::message(message);
  if (!valid_message_shape(message, shared_->limits) ||
      !combined_queue_has_room(*shared_, usage) ||
      !shared_->outbound_usage.try_add(usage, shared_->limits)) {
    shared_->error.store(SessionError::queue_limit);
    return false;
  }
  shared_->last_outbound_sequence = message.sequence;
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

void PluginSessionIo::revoke() { fence_and_queue(TerminationIntent::revoke); }
void PluginSessionIo::stop() { fence_and_queue(TerminationIntent::stop); }
SessionState PluginSessionIo::state() const noexcept {
  return shared_->state.load();
}
SessionError PluginSessionIo::error() const noexcept {
  return shared_->error.load();
}
std::uint64_t PluginSessionIo::stale_messages_dropped() const noexcept {
  return shared_->stale_drops.load();
}
void PluginSessionIo::fence_and_queue(TerminationIntent intent) {
  const bool revoke = intent == TerminationIntent::revoke;
  const bool destruction = intent == TerminationIntent::destroy;
  std::uint64_t epoch = 0;
  {
    std::lock_guard lock(shared_->mutex);
    if (!shared_->accepting && !destruction)
      return;
    shared_->accepting = false;
    ++shared_->epoch;
    epoch = shared_->epoch;
    shared_->outbound.clear();
    shared_->outbound_usage = {};
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
    if (!queue_worker([epoch, intent](Worker &worker) {
          worker.stop(epoch, intent);
        })) {
      std::lock_guard lock(shared_->mutex);
      invocation_failed_locked();
      return;
    }
  }
}

bool PluginSessionIo::schedule_pump_locked(std::uint64_t epoch) {
  const auto claim = claim_pump_locked(*shared_, epoch);
  if (!claim.accepted)
    return false;
  if (!claim.ticket)
    return true;
  const auto ticket = *claim.ticket;
  if (queue_worker(
          [epoch, ticket](Worker &worker) { worker.pump(epoch, ticket); }))
    return true;
  rollback_pump_locked(*shared_, ticket);
  invocation_failed_locked();
  return false;
}

void PluginSessionIo::invocation_failed_locked() noexcept {
  shared_->accepting = false;
  ++shared_->epoch;
  shared_->pump_queued = false;
  shared_->outbound.clear();
  shared_->outbound_usage = {};
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

QThread *PluginSessionIoTestAccess::io_thread(
    PluginSessionIo &session) noexcept {
  std::lock_guard lock(session.runtime_->mutex);
  return session.runtime_->thread;
}
#endif

} // namespace omarchy::plugin_runtime::host_session
