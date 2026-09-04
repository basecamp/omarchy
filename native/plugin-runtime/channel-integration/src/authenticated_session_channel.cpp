#include "authenticated_session_channel.hpp"
#include "authenticated_session_backend_p.hpp"
#include "broker_session_settlement_p.hpp"

#include <QSocketNotifier>

#include <algorithm>
#include <cerrno>
#include <limits>
#include <optional>
#include <utility>

#include <poll.h>

namespace omarchy::plugin_runtime::channel {

namespace {

bool valid_lane(session::ChannelLane lane) noexcept {
  return lane == session::ChannelLane::control ||
         lane == session::ChannelLane::broker ||
         lane == session::ChannelLane::render;
}

bool valid_role(wire::EndpointRole role) noexcept {
  return role == wire::EndpointRole::control ||
         role == wire::EndpointRole::broker ||
         role == wire::EndpointRole::render;
}

wire::EndpointRole wire_role(session::ChannelLane lane) noexcept {
  switch (lane) {
  case session::ChannelLane::control:
    return wire::EndpointRole::control;
  case session::ChannelLane::broker:
    return wire::EndpointRole::broker;
  case session::ChannelLane::render:
    return wire::EndpointRole::render;
  }
  return wire::EndpointRole::control;
}

session::ChannelLane session_lane(wire::EndpointRole role) noexcept {
  switch (role) {
  case wire::EndpointRole::control:
    return session::ChannelLane::control;
  case wire::EndpointRole::broker:
    return session::ChannelLane::broker;
  case wire::EndpointRole::render:
    return session::ChannelLane::render;
  }
  return session::ChannelLane::control;
}

launcher::EndpointMask lane_mask(wire::EndpointRole role) noexcept {
  switch (role) {
  case wire::EndpointRole::control:
    return launcher::EndpointMask::control;
  case wire::EndpointRole::broker:
    return launcher::EndpointMask::broker;
  case wire::EndpointRole::render:
    return launcher::EndpointMask::render;
  }
  return launcher::EndpointMask::none;
}

launcher::EndpointMask intersect(launcher::EndpointMask left,
                                 launcher::EndpointMask right) noexcept {
  return static_cast<launcher::EndpointMask>(static_cast<std::uint8_t>(left) &
                                             static_cast<std::uint8_t>(right));
}

session::SendStatus map_send(ChannelSendStatus status) noexcept {
  switch (status) {
  case ChannelSendStatus::complete:
    return session::SendStatus::complete;
  case ChannelSendStatus::would_block:
    return session::SendStatus::would_block;
  case ChannelSendStatus::peer_closed:
    return session::SendStatus::peer_closed;
  case ChannelSendStatus::fatal:
  case ChannelSendStatus::not_ready:
    return session::SendStatus::fatal;
  }
  return session::SendStatus::fatal;
}

bool wait_for_channel(AuthenticatedSessionBackend &backend,
                      launcher::EndpointMask reads,
                      launcher::EndpointMask writes,
                      launcher::Deadline deadline) noexcept {
  if (std::chrono::steady_clock::now() >= deadline ||
      !backend.arm(reads, writes))
    return false;
  pollfd event{.fd = backend.readiness_fd(), .events = POLLIN, .revents = 0};
  if (event.fd < 0)
    return false;
  int ready = -1;
  do {
    const auto now = std::chrono::steady_clock::now();
    if (now >= deadline)
      return false;
    const auto remaining = deadline - now;
    const auto timeout = static_cast<int>(std::min<std::int64_t>(
        std::chrono::duration_cast<std::chrono::milliseconds>(remaining)
                .count() +
            1,
        std::numeric_limits<int>::max()));
    ready = ::poll(&event, 1, timeout);
  } while (ready < 0 && errno == EINTR);
  return ready == 1 && (event.revents & POLLIN) != 0 &&
         (event.revents & (POLLERR | POLLHUP | POLLNVAL)) == 0 &&
         std::chrono::steady_clock::now() < deadline;
}

bool establish_startup_snapshot(AuthenticatedSessionBackend &backend,
                                std::uint16_t message_type,
                                std::uint16_t accepted_type,
                                std::span<const std::byte> snapshot,
                                launcher::Deadline deadline) {
  if (snapshot.empty() ||
      snapshot.size() > wire::payload_cap(wire::EndpointRole::control) ||
      std::chrono::steady_clock::now() >= deadline ||
      !backend.prepare(wire::EndpointRole::control,
                       message_type, 0, snapshot, 0))
    return false;

  for (;;) {
    const auto sent = backend.try_send({}, deadline);
    if (sent == session::SendStatus::complete)
      break;
    if (sent != session::SendStatus::would_block ||
        !wait_for_channel(backend, launcher::EndpointMask::none,
                          launcher::EndpointMask::control, deadline))
      return false;
  }

  for (;;) {
    if (std::chrono::steady_clock::now() >= deadline ||
        !backend.arm(launcher::EndpointMask::control,
                     launcher::EndpointMask::none))
      return false;
    auto reply = backend.receive(launcher::EndpointMask::control, deadline);
    if (reply.status == AuthenticatedReceiveStatus::message && reply.message) {
      return reply.message->role == wire::EndpointRole::control &&
             reply.message->message_type ==
                 accepted_type &&
             reply.message->correlation_id == 0 &&
             reply.message->payload.empty() &&
             reply.message->descriptors.empty() &&
             std::chrono::steady_clock::now() < deadline;
    }
    if (reply.status != AuthenticatedReceiveStatus::would_block ||
        !wait_for_channel(backend, launcher::EndpointMask::control,
                          launcher::EndpointMask::none, deadline))
      return false;
  }
}

class LauncherSessionBackend final : public AuthenticatedSessionBackend {
public:
  LauncherSessionBackend(
      launcher::Supervisor supervisor, AuthenticatedSessionLaunch launch,
      std::shared_ptr<const GenerationAuthority> authority,
      std::unique_ptr<AuthenticatedSessionRuntime> runtime,
      std::shared_ptr<runtime::GestureEligibilityLatch> gesture_eligibility)
      : supervisor_(std::move(supervisor)), launch_(std::move(launch)),
        authority_(std::move(authority)), runtime_(std::move(runtime)),
        gesture_eligibility_(std::move(gesture_eligibility)) {}

  ~LauncherSessionBackend() override {
    terminate(std::chrono::steady_clock::now());
  }

  session::ChannelError launch(const session::SessionToken &token,
                               launcher::Deadline deadline) override {
    if (channel_ || token.plugin_id != launch_.binding.plugin.view() ||
        token.revision_sha256 != launch_.binding.revision.view() ||
        token.generation != launch_.binding.generation ||
        !launch_.revision_directory || !launch_.private_state_directory ||
        !authority_ || !runtime_ ||
        !runtime_->broker().accepts(launch_.binding, token.session_nonce))
      return session::ChannelError::launch_failed;
    const launcher::TrustedLaunchRequest request{
        .plugin_id = std::string(launch_.binding.plugin.view()),
        .revision_sha256 = std::string(launch_.binding.revision.view()),
        .generation = launch_.binding.generation,
        .revision_directory_fd = launch_.revision_directory.get(),
        .private_state_directory_fd = launch_.private_state_directory.get()};
    auto opened = AuthenticatedBrokerChannel::open(supervisor_, request,
                                                   authority_, deadline);
    if (!opened)
      return session::ChannelError::launch_failed;
    channel_ = std::move(opened.channel);
    auto extracted = runtime_->broker().take_admission();
    if (!extracted) {
      (void)channel_->terminate(deadline);
      channel_.reset();
      return session::ChannelError::launch_failed;
    }
    try {
      settlement_.emplace(*channel_, runtime_->broker(),
                          std::move(*extracted.admission),
                          gesture_eligibility_.get());
    } catch (...) {
      (void)channel_->terminate(deadline);
      channel_.reset();
      return session::ChannelError::launch_failed;
    }
    launch_.revision_directory.reset();
    launch_.private_state_directory.reset();
    return session::ChannelError::none;
  }

  session::ChannelError handshake(launcher::Deadline deadline) override {
    if (!channel_ || !channel_->negotiate(deadline))
      return session::ChannelError::handshake_failed;
    return session::ChannelError::none;
  }

  bool prepare(wire::EndpointRole role, std::uint16_t message_type,
               std::uint64_t correlation_id, std::span<const std::byte> payload,
               std::size_t) override {
    if (!channel_ || prepared_ || role == wire::EndpointRole::broker)
      return false;
    auto prepared =
        channel_->prepare_send(role, message_type, correlation_id, payload);
    if (!prepared)
      return false;
    prepared_.emplace(std::move(*prepared));
    return true;
  }

  session::SendStatus try_send(std::span<const int> descriptors,
                               launcher::Deadline deadline) override {
    if (!channel_ || !prepared_)
      return session::SendStatus::fatal;
    const auto status =
        map_send(channel_->try_send(*prepared_, deadline, descriptors));
    if (status != session::SendStatus::would_block)
      prepared_.reset();
    return status;
  }

  AuthenticatedReceiveResult receive(launcher::EndpointMask allowed_lanes,
                                     launcher::Deadline deadline) override {
    if (!channel_ || !settlement_)
      return {};
    if (settlement_->pending()) {
      const auto flushed = settlement_->flush(deadline);
      if (flushed == BrokerSettlementStatus::fatal)
        return {.status = AuthenticatedReceiveStatus::fatal,
                .message = std::nullopt};
      // Completion expands the readable lanes. Yield so PluginSessionIo can
      // re-arm that mask before this readiness-driven backend receives again.
      if (flushed == BrokerSettlementStatus::complete)
        return {.status = AuthenticatedReceiveStatus::would_block,
                .message = std::nullopt};
    }
    const auto effective = intersect(allowed_lanes, settlement_->read_lanes());
    if (effective == launcher::EndpointMask::none)
      return {.status = AuthenticatedReceiveStatus::would_block,
              .message = std::nullopt};
    auto received = channel_->try_receive_authenticated(effective);
    if (!received || received.message->role != wire::EndpointRole::broker)
      return received;
    const auto settled =
        settlement_->dispatch(std::move(*received.message), deadline);
    if (settled == BrokerSettlementStatus::fatal)
      return {.status = AuthenticatedReceiveStatus::fatal,
              .message = std::nullopt};
    return {.status = AuthenticatedReceiveStatus::would_block,
            .message = std::nullopt};
  }

  int readiness_fd() const noexcept override {
    return channel_ ? channel_->readiness_fd() : -1;
  }

  bool arm(launcher::EndpointMask reads,
           launcher::EndpointMask writes) noexcept override {
    if (!channel_ || !settlement_)
      return false;
    return channel_->arm_readiness(intersect(reads, settlement_->read_lanes()),
                                   writes | settlement_->write_lanes());
  }

  void terminate(launcher::Deadline deadline) noexcept override {
    if (settlement_)
      (void)settlement_->abort();
    settlement_.reset();
    prepared_.reset();
    if (channel_)
      (void)channel_->terminate(deadline);
    channel_.reset();
    launch_.revision_directory.reset();
    launch_.private_state_directory.reset();
    authority_.reset();
    runtime_.reset();
    gesture_eligibility_.reset();
  }

private:
  launcher::Supervisor supervisor_;
  AuthenticatedSessionLaunch launch_;
  std::shared_ptr<const GenerationAuthority> authority_;
  std::unique_ptr<AuthenticatedSessionRuntime> runtime_;
  std::shared_ptr<runtime::GestureEligibilityLatch> gesture_eligibility_;
  std::unique_ptr<AuthenticatedBrokerChannel> channel_;
  std::optional<BrokerSessionSettlement> settlement_;
  std::optional<PreparedSend> prepared_;
};

} // namespace

struct AuthenticatedSessionChannel::Impl final {
  struct Pending final {
    session::SessionToken token;
    session::ChannelLane lane = session::ChannelLane::control;
    std::uint16_t message_type = 0;
    std::uint64_t correlation_id = 0;
    std::uint64_t sequence = 0;
    std::vector<std::byte> payload;
    std::size_t descriptor_count = 0;

    [[nodiscard]] bool matches(const session::OwnedMessage &message) const {
      if (!(token == message.token) || lane != message.lane ||
          message_type != message.message_type ||
          correlation_id != message.correlation_id ||
          sequence != message.sequence || payload != message.payload ||
          descriptor_count != message.descriptors.size())
        return false;
      return true;
    }
  };

  Impl(std::unique_ptr<AuthenticatedSessionBackend> value,
       std::vector<std::byte> permission, std::vector<std::byte> settings,
       std::vector<std::byte> presentation)
      : backend(std::move(value)), permission_snapshot(std::move(permission)),
        settings_snapshot(std::move(settings)),
        presentation_snapshot(std::move(presentation)) {}

  ~Impl() { terminate(std::chrono::steady_clock::now()); }

  [[nodiscard]] bool arm_wait() noexcept {
    if (!backend)
      return false;
    const auto writes = pending ? lane_mask(wire_role(pending->lane))
                                : launcher::EndpointMask::none;
    if (!backend->arm(launcher::EndpointMask::all, writes))
      return false;
    if (notifier)
      notifier->setEnabled(true);
    return true;
  }

  void terminate(launcher::Deadline deadline) noexcept {
    if (terminal)
      return;
    terminal = true;
    clear_wake();
    pending.reset();
    permission_snapshot.clear();
    settings_snapshot.clear();
    presentation_snapshot.clear();
    if (backend)
      backend->terminate(deadline);
    token.reset();
  }

  void clear_wake() noexcept {
    ++wake_generation;
    wake_pending = false;
    if (notifier)
      notifier->setEnabled(false);
    notifier.reset();
    wake = {};
  }

  std::unique_ptr<AuthenticatedSessionBackend> backend;
  std::vector<std::byte> permission_snapshot;
  std::vector<std::byte> settings_snapshot;
  std::vector<std::byte> presentation_snapshot;
  std::optional<session::SessionToken> token;
  std::optional<Pending> pending;
  std::optional<launcher::Deadline> startup_deadline;
  std::unique_ptr<QSocketNotifier> notifier;
  std::unique_ptr<QObject> wake_context;
  session::SessionWakeHandler wake;
  std::uint64_t wake_generation = 0;
  bool wake_pending = false;
  std::uint64_t last_outbound_sequence = 0;
  std::uint64_t last_inbound_sequence = 0;
  bool launched = false;
  bool ready = false;
  bool terminal = false;
};

AuthenticatedSessionChannel::AuthenticatedSessionChannel(
    launcher::Supervisor supervisor, AuthenticatedSessionLaunch launch,
    std::shared_ptr<const GenerationAuthority> authority,
    std::unique_ptr<AuthenticatedSessionRuntime> runtime,
    std::shared_ptr<runtime::GestureEligibilityLatch> gesture_eligibility) {
  auto permission_snapshot = std::move(launch.permission_snapshot);
  auto settings_snapshot = std::move(launch.settings_snapshot);
  auto presentation_snapshot = std::move(launch.presentation_snapshot);
  implementation_ = std::make_unique<Impl>(
      std::make_unique<LauncherSessionBackend>(
          std::move(supervisor), std::move(launch), std::move(authority),
          std::move(runtime), std::move(gesture_eligibility)),
      std::move(permission_snapshot), std::move(settings_snapshot),
      std::move(presentation_snapshot));
}

#ifdef OMARCHY_AUTHENTICATED_SESSION_CHANNEL_TESTING
AuthenticatedSessionChannel::AuthenticatedSessionChannel(
    std::unique_ptr<AuthenticatedSessionBackend> backend,
    std::vector<std::byte> permission_snapshot)
    : implementation_(std::make_unique<Impl>(std::move(backend),
                                             std::move(permission_snapshot),
                                             std::vector<std::byte>{
                                                 std::byte{0x7b},
                                                 std::byte{0x7d}},
                                             std::vector<std::byte>{
                                                 std::byte{0x7b},
                                                 std::byte{0x7d}})) {}
#endif

AuthenticatedSessionChannel::~AuthenticatedSessionChannel() = default;

session::ChannelError
AuthenticatedSessionChannel::launch(const session::SessionToken &token,
                                    TimePoint deadline) {
  auto &value = *implementation_;
  if (!value.backend || value.launched || value.terminal ||
      value.permission_snapshot.empty() || value.settings_snapshot.empty() ||
      value.presentation_snapshot.empty() ||
      value.permission_snapshot.size() >
          wire::payload_cap(wire::EndpointRole::control) ||
      value.settings_snapshot.size() >
          wire::payload_cap(wire::EndpointRole::control) ||
      value.presentation_snapshot.size() >
          wire::payload_cap(wire::EndpointRole::control) ||
      token.plugin_id.empty() || token.revision_sha256.empty() ||
      token.generation == 0 || token.session_nonce == 0 ||
      std::chrono::steady_clock::now() >= deadline)
    return session::ChannelError::launch_failed;
  const auto result = value.backend->launch(token, deadline);
  if (result != session::ChannelError::none) {
    value.terminate(deadline);
    return result;
  }
  if (std::chrono::steady_clock::now() >= deadline) {
    value.terminate(deadline);
    return session::ChannelError::launch_failed;
  }
  value.token = token;
  value.startup_deadline = deadline;
  value.launched = true;
  return session::ChannelError::none;
}

session::ChannelError
AuthenticatedSessionChannel::handshake(TimePoint deadline) {
  auto &value = *implementation_;
  if (!value.backend || !value.launched || value.ready || value.terminal ||
      !value.startup_deadline || deadline != *value.startup_deadline)
    return session::ChannelError::handshake_failed;
  const auto result = value.backend->handshake(deadline);
  if (result != session::ChannelError::none) {
    value.terminate(deadline);
    return result;
  }
  if (std::chrono::steady_clock::now() >= deadline) {
    value.terminate(deadline);
    return session::ChannelError::handshake_failed;
  }
  if (!establish_startup_snapshot(
          *value.backend, wire::kSettingsSnapshotMessage,
          wire::kSettingsSnapshotAcceptedMessage, value.settings_snapshot,
          deadline) ||
      !establish_startup_snapshot(
          *value.backend, wire::kPresentationSnapshotMessage,
          wire::kPresentationSnapshotAcceptedMessage,
          value.presentation_snapshot, deadline) ||
      !establish_startup_snapshot(
          *value.backend, wire::kPermissionSnapshotMessage,
          wire::kPermissionSnapshotAcceptedMessage,
          value.permission_snapshot, deadline)) {
    value.terminate(deadline);
    return session::ChannelError::protocol_failed;
  }
  value.permission_snapshot.clear();
  value.settings_snapshot.clear();
  value.presentation_snapshot.clear();
  value.ready = true;
  return session::ChannelError::none;
}

session::SendStatus
AuthenticatedSessionChannel::send(const session::OwnedMessage &message,
                                  TimePoint deadline) {
  auto &value = *implementation_;
  try {
    const auto fail = [&value, deadline] {
      value.terminate(deadline);
      return session::SendStatus::fatal;
    };
    if (!value.backend || !value.ready || value.terminal || !value.token ||
        !(message.token == *value.token) || !valid_lane(message.lane) ||
        message.lane == session::ChannelLane::broker ||
        (message.lane == session::ChannelLane::control &&
         (message.message_type == wire::kPermissionSnapshotMessage ||
          message.message_type == wire::kSettingsSnapshotMessage ||
          message.message_type == wire::kPresentationSnapshotMessage)) ||
        message.message_type == 0 || message.sequence == 0 ||
        message.descriptors.size() > launcher::kMaximumTransportDescriptors ||
        message.payload.size() > wire::payload_cap(wire_role(message.lane)) ||
        std::chrono::steady_clock::now() >= deadline)
      return fail();

    if (value.pending) {
      if (!value.pending->matches(message))
        return fail();
    } else {
      if (message.sequence <= value.last_outbound_sequence)
        return fail();
      Impl::Pending pending{.token = message.token,
                            .lane = message.lane,
                            .message_type = message.message_type,
                            .correlation_id = message.correlation_id,
                            .sequence = message.sequence,
                            .payload = message.payload,
                            .descriptor_count = message.descriptors.size()};
      for (const auto &descriptor : message.descriptors) {
        if (!descriptor)
          return fail();
      }
      if (!value.backend->prepare(wire_role(message.lane), message.message_type,
                                  message.correlation_id, message.payload,
                                  message.descriptors.size()))
        return fail();
      value.last_outbound_sequence = message.sequence;
      value.pending = std::move(pending);
    }
    std::vector<int> descriptors;
    descriptors.reserve(message.descriptors.size());
    for (const auto &descriptor : message.descriptors) {
      if (!descriptor)
        return fail();
      descriptors.push_back(descriptor.get());
    }
    const auto status = value.backend->try_send(descriptors, deadline);
    if (std::chrono::steady_clock::now() >= deadline) {
      value.terminate(deadline);
      return session::SendStatus::fatal;
    }
    if (status == session::SendStatus::would_block) {
      if (!value.arm_wait())
        return fail();
      if (std::chrono::steady_clock::now() >= deadline)
        return fail();
      return status;
    }
    value.pending.reset();
    if (status != session::SendStatus::complete)
      value.terminate(deadline);
    return status;
  } catch (...) {
    value.terminate(deadline);
    return session::SendStatus::fatal;
  }
}

session::ReceiveResult
AuthenticatedSessionChannel::receive(TimePoint deadline) {
  auto &value = *implementation_;
  try {
    const auto fail = [&value, deadline] {
      value.terminate(deadline);
      return session::ReceiveResult{.status = session::ReceiveStatus::fatal,
                                    .message = {}};
    };
    if (!value.backend || !value.ready || value.terminal || !value.token ||
        std::chrono::steady_clock::now() >= deadline)
      return fail();
    if (!value.arm_wait())
      return fail();
    if (std::chrono::steady_clock::now() >= deadline)
      return fail();
    auto result = value.backend->receive(launcher::EndpointMask::all, deadline);
    if (result.status == AuthenticatedReceiveStatus::would_block) {
      if (!value.arm_wait())
        return fail();
      if (std::chrono::steady_clock::now() >= deadline)
        return fail();
      return {.status = session::ReceiveStatus::would_block, .message = {}};
    }
    if (result.status != AuthenticatedReceiveStatus::message ||
        !result.message) {
      const auto status =
          result.status == AuthenticatedReceiveStatus::peer_closed
              ? session::ReceiveStatus::peer_closed
              : session::ReceiveStatus::fatal;
      if (status != session::ReceiveStatus::would_block)
        value.terminate(deadline);
      return {.status = status, .message = {}};
    }
    if (value.last_inbound_sequence ==
            std::numeric_limits<std::uint64_t>::max() ||
        !valid_role(result.message->role) ||
        result.message->role == wire::EndpointRole::broker ||
        (result.message->role == wire::EndpointRole::control &&
         (result.message->message_type ==
              wire::kPermissionSnapshotAcceptedMessage ||
          result.message->message_type ==
              wire::kSettingsSnapshotAcceptedMessage)) ||
        result.message->descriptors.size() >
            launcher::kMaximumTransportDescriptors)
      return fail();

    session::OwnedMessage message;
    message.token = *value.token;
    message.lane = session_lane(result.message->role);
    message.message_type = result.message->message_type;
    message.correlation_id = result.message->correlation_id;
    message.sequence = ++value.last_inbound_sequence;
    message.payload = std::move(result.message->payload);
    message.descriptors.reserve(result.message->descriptors.size());
    for (auto &descriptor : result.message->descriptors)
      message.descriptors.emplace_back(descriptor.release());
    if (std::chrono::steady_clock::now() >= deadline) {
      return fail();
    }
    return {.status = session::ReceiveStatus::message,
            .message = std::move(message)};
  } catch (...) {
    value.terminate(deadline);
    return {.status = session::ReceiveStatus::fatal, .message = {}};
  }
}

bool AuthenticatedSessionChannel::install_wake_handler(
    session::SessionWakeHandler handler) noexcept {
  auto &value = *implementation_;
  if (!handler || value.wake || value.notifier || !value.ready ||
      value.terminal || !value.backend)
    return false;
  const int descriptor = value.backend->readiness_fd();
  if (descriptor < 0)
    return false;
  try {
    if (!value.wake_context)
      value.wake_context = std::make_unique<QObject>();
    value.wake = handler;
    ++value.wake_generation;
    value.notifier =
        std::make_unique<QSocketNotifier>(descriptor, QSocketNotifier::Read);
    value.notifier->setEnabled(false);
    auto *impl = &value;
    QObject::connect(value.notifier.get(), &QSocketNotifier::activated,
                     [impl](QSocketDescriptor, QSocketNotifier::Type) {
                       if (!impl->notifier || !impl->wake || impl->wake_pending)
                         return;
                       impl->notifier->setEnabled(false);
                       impl->wake_pending = true;
                       const auto generation = impl->wake_generation;
                       bool queued = false;
                       try {
                         queued = QMetaObject::invokeMethod(
                             impl->wake_context.get(),
                             [impl, generation] {
                               if (generation != impl->wake_generation)
                                 return;
                               impl->wake_pending = false;
                               if (impl->wake)
                                 impl->wake.invoke();
                             },
                             Qt::QueuedConnection);
                       } catch (...) {
                       }
                       if (!queued) {
                         impl->wake_pending = false;
                         // The relay could not be queued. Keep the currently
                         // executing notifier alive through signal return,
                         // then wake the Worker and terminally fence transport
                         // authority. The queued pump observes fatal state.
                         auto *active = impl->notifier.release();
                         active->disconnect();
                         active->setParent(impl->wake_context.get());
                         active->deleteLater();
                         impl->wake.invoke();
                         impl->terminate(std::chrono::steady_clock::now());
                       }
                     });
    return true;
  } catch (...) {
    value.clear_wake();
    return false;
  }
}

void AuthenticatedSessionChannel::clear_wake_handler() noexcept {
  implementation_->clear_wake();
}

bool AuthenticatedSessionChannel::revoke(const session::SessionToken &token,
                                         TimePoint deadline) noexcept {
  auto &value = *implementation_;
  if (!value.token || !(token == *value.token) || value.terminal)
    return false;
  value.terminate(deadline);
  return true;
}

void AuthenticatedSessionChannel::terminate(TimePoint deadline) noexcept {
  implementation_->terminate(deadline);
}

} // namespace omarchy::plugin_runtime::channel
