#pragma once

#include <QObject>
#include <QThread>

#include <chrono>
#include <cstddef>
#include <cstdint>
#include <memory>
#include <string>
#include <vector>

namespace omarchy::plugin_runtime::host_session {

class OwnedFd final {
public:
  explicit OwnedFd(int descriptor = -1) noexcept;
  OwnedFd(OwnedFd &&other) noexcept;
  OwnedFd &operator=(OwnedFd &&other) noexcept;
  OwnedFd(const OwnedFd &) = delete;
  OwnedFd &operator=(const OwnedFd &) = delete;
  ~OwnedFd();
  [[nodiscard]] int get() const noexcept;
  [[nodiscard]] explicit operator bool() const noexcept;
  [[nodiscard]] int release() noexcept;
  void reset(int descriptor = -1) noexcept;

private:
  int descriptor_ = -1;
};

struct SessionToken {
  std::string plugin_id;
  std::string revision_sha256;
  std::uint64_t generation = 0;
  std::uint64_t session_nonce = 0;
  bool operator==(const SessionToken &) const = default;
};

enum class ChannelLane : std::uint8_t { control, broker, render };

struct OwnedMessage {
  SessionToken token;
  ChannelLane lane = ChannelLane::render;
  std::uint16_t message_type = 0;
  // Semantic request/reply correlation. The authenticated transport remains
  // the sole encoder of wire headers and lane sequence numbers.
  std::uint64_t correlation_id = 0;
  std::uint64_t sequence = 0;
  std::vector<std::byte> payload;
  std::vector<OwnedFd> descriptors;
};

enum class ChannelError : std::uint8_t {
  none,
  launch_failed,
  handshake_failed,
  protocol_failed,
};
enum class SendStatus : std::uint8_t {
  complete,
  would_block,
  peer_closed,
  fatal,
};
enum class ReceiveStatus : std::uint8_t {
  would_block,
  message,
  peer_closed,
  fatal,
};

struct ReceiveResult {
  ReceiveStatus status = ReceiveStatus::would_block;
  OwnedMessage message;
};

// Allocation-free readiness callback representation installed and invoked
// only on the PluginSessionIo worker thread. The callback may queue Qt work.
// SessionChannel::clear_wake_handler() synchronously fences future callbacks
// before terminal work continues.
struct SessionWakeHandler {
  using Function = void (*)(void *context) noexcept;

  Function function = nullptr;
  void *context = nullptr;

  [[nodiscard]] explicit operator bool() const noexcept {
    return function != nullptr;
  }
  void invoke() const noexcept {
    if (function != nullptr)
      function(context);
  }
};

// Every method runs only on PluginSessionIo's private thread. Implementations
// must perform bounded I/O and return no later than the absolute deadline. The
// authenticated adapter, never plugin code, stamps SessionToken and validates
// lane, type, sequence and descriptor semantics on inbound messages.
// Its destructor must also be nonblocking because it runs during thread exit.
class SessionChannel {
public:
  using TimePoint = std::chrono::steady_clock::time_point;
  virtual ~SessionChannel() = default;
  [[nodiscard]] virtual ChannelError launch(const SessionToken &token,
                                            TimePoint deadline) = 0;
  [[nodiscard]] virtual ChannelError handshake(TimePoint deadline) = 0;
  // would_block is atomic: it must make no transport progress and must not
  // close, duplicate, or retain any descriptor borrowed from message.
  [[nodiscard]] virtual SendStatus send(const OwnedMessage &message,
                                        TimePoint deadline) = 0;
  // A would_block result likewise consumes no bytes or descriptors.
  [[nodiscard]] virtual ReceiveResult receive(TimePoint deadline) = 0;
  // An implementation that returns true after retaining `handler` must make
  // clear_wake_handler() an infallible, idempotent synchronous fence.
  [[nodiscard]] virtual bool
  install_wake_handler(SessionWakeHandler handler) noexcept = 0;
  virtual void clear_wake_handler() noexcept = 0;
  [[nodiscard]] virtual bool revoke(const SessionToken &token,
                                    TimePoint deadline) noexcept = 0;
  virtual void terminate(TimePoint deadline) noexcept = 0;
};

class SessionClock {
public:
  using TimePoint = SessionChannel::TimePoint;
  virtual ~SessionClock() = default;
  [[nodiscard]] virtual TimePoint now() const noexcept = 0;
};

class SteadySessionClock final : public SessionClock {
public:
  [[nodiscard]] TimePoint now() const noexcept override;
};

enum class SessionState : std::uint8_t {
  idle,
  starting,
  running,
  revoking,
  revoked,
  stopping,
  stopped,
  failed,
};
enum class SessionError : std::uint8_t {
  none,
  invalid_configuration,
  invalid_token,
  startup_deadline_expired,
  io_deadline_expired,
  launch_failed,
  handshake_failed,
  channel_failed,
  queue_limit,
};

struct SessionLimits {
  static constexpr std::size_t kMaximumMessages = 1024;
  static constexpr std::size_t kMaximumBytes = 16ULL * 1024 * 1024;
  static constexpr std::size_t kMaximumDescriptors = 256;
  static constexpr std::size_t kMaximumPumpBatch = 256;
  static constexpr std::chrono::milliseconds kMaximumStartupTimeout{30500};
  static constexpr std::chrono::milliseconds kMaximumIoTimeout{30500};

  std::size_t maximum_queued_messages = 64;
  std::size_t maximum_queued_bytes = 1024ULL * 1024;
  std::size_t maximum_descriptors_per_message = 8;
  std::size_t maximum_queued_descriptors = 64;
  std::size_t maximum_pump_batch = 32;
  std::chrono::milliseconds startup_timeout{5000};
  std::chrono::milliseconds io_timeout{10};
};

class SessionObserver : public QObject {
public:
  using QObject::QObject;
  virtual ~SessionObserver() = default;
  // The observer must remain on the session's owning thread. If it is moved
  // after construction, delivery is detached before the affinity change.
  virtual void state_changed(SessionState state, SessionError error) = 0;
  virtual void message_received(OwnedMessage message) = 0;
};

struct PluginSessionSharedState;
struct PluginSessionRuntimeOwner;
class PluginSessionDeliveryProxy;
#ifdef OMARCHY_PLUGIN_SESSION_IO_TESTING
class PluginSessionIoTestAccess;
#endif

// Owns one asynchronous channel lifecycle for one plugin activation. Public
// teardown closes admission and queues bounded worker-thread termination; it
// never waits for launch, I/O or QThread shutdown on the UI thread.
class PluginSessionIo final : public QObject {
public:
  PluginSessionIo(SessionToken token, std::unique_ptr<SessionChannel> channel,
                  std::shared_ptr<const SessionClock> clock,
                  SessionObserver *observer = nullptr,
                  SessionLimits limits = {}, QObject *parent = nullptr);
  ~PluginSessionIo() override;
  PluginSessionIo(const PluginSessionIo &) = delete;
  PluginSessionIo &operator=(const PluginSessionIo &) = delete;

  void start();
  [[nodiscard]] bool enqueue(OwnedMessage message);
  void wake();
  void revoke();
  void stop();
  [[nodiscard]] SessionState state() const noexcept;
  [[nodiscard]] SessionError error() const noexcept;
  [[nodiscard]] std::uint64_t stale_messages_dropped() const noexcept;

private:
  enum class TerminationIntent : std::uint8_t { revoke, stop, destroy };
  class Worker;
  void fence_and_queue(TerminationIntent intent);
  [[nodiscard]] bool schedule_pump_locked(std::uint64_t epoch);
  template <typename Operation>
  [[nodiscard]] bool queue_worker(Operation operation);
  void invocation_failed_locked() noexcept;
  void detach_runtime() noexcept;

  std::shared_ptr<PluginSessionSharedState> shared_;
  std::shared_ptr<PluginSessionRuntimeOwner> runtime_;
  PluginSessionDeliveryProxy *delivery_ = nullptr;

#ifdef OMARCHY_PLUGIN_SESSION_IO_TESTING
  friend class PluginSessionIoTestAccess;
#endif
};

#ifdef OMARCHY_PLUGIN_SESSION_IO_TESTING
// Narrow deterministic fault injection used by the standalone lifecycle tests.
class PluginSessionIoTestAccess final {
public:
  static void fail_next_thread_start() noexcept;
  static void fail_next_invocation(PluginSessionIo &session) noexcept;
  [[nodiscard]] static QThread *io_thread(PluginSessionIo &session) noexcept;
};
#endif

} // namespace omarchy::plugin_runtime::host_session
