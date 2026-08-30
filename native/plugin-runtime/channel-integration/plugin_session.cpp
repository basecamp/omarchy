#include "plugin_session.hpp"

#include "omarchy/plugin/wire/surface_name.hpp"
#include "omarchy/plugin_runtime/surface/render_messages.hpp"

#include <sys/random.h>

#include <algorithm>
#include <chrono>
#include <cerrno>
#include <limits>
#include <utility>

namespace omarchy::plugin_runtime::channel {
namespace wire = omarchy::plugin::wire;
namespace {

class SteadyGestureClock final : public runtime::GestureEligibilityClock {
public:
  [[nodiscard]] std::uint64_t now_nanoseconds() const override {
    return static_cast<std::uint64_t>(
        std::chrono::duration_cast<std::chrono::nanoseconds>(
            std::chrono::steady_clock::now().time_since_epoch())
            .count());
  }
};

std::uint64_t session_nonce() noexcept {
  std::uint64_t nonce = 0;
  std::byte *cursor = reinterpret_cast<std::byte *>(&nonce);
  std::size_t remaining = sizeof(nonce);
  while (remaining != 0) {
    const auto count = ::getrandom(cursor, remaining, GRND_NONBLOCK);
    if (count < 0 && errno == EINTR)
      continue;
    if (count <= 0)
      return 0;
    cursor += static_cast<std::size_t>(count);
    remaining -= static_cast<std::size_t>(count);
  }
  return nonce;
}

bool valid_snapshot(const session::ActivationSnapshot &snapshot) {
  if (!(snapshot.activation_record && snapshot.revision_directory &&
         snapshot.state_directory && snapshot.live &&
         snapshot.record.plugin_id == snapshot.grants.binding.plugin.view() &&
         snapshot.record.revision_sha256 ==
             snapshot.grants.binding.revision.view() &&
         snapshot.record.generation == snapshot.grants.binding.generation &&
         snapshot.live->current(snapshot.grants.binding) &&
         snapshot.manifest.id == snapshot.record.plugin_id &&
         plugins::manifest::requested_capability_fingerprint(
             snapshot.manifest.requests) ==
             snapshot.grants.source_request_fingerprint.view() &&
         snapshot.manifest.surface_names.size() <=
             wire::kMaximumPluginSurfaces))
    return false;
  permissions::validate_requests(snapshot.grants.requests);
  permissions::validate_grants(snapshot.grants.grants,
                               snapshot.grants.requests);
  return permissions::policy_request_fingerprint(snapshot.grants.requests) ==
         snapshot.grants.binding.policy_fingerprint.view();
}

struct RenderDestination final {
  std::optional<session::surface::SurfaceKey> surface;
  bool valid = true;
};

RenderDestination render_destination(const session::OwnedMessage &message) {
  using session::surface::RenderMessageType;
  const auto type = static_cast<RenderMessageType>(message.message_type);
  session::surface::SurfaceKey key{};
  const bool allocation = type == RenderMessageType::surface_allocate;
  const bool key_only = type == RenderMessageType::surface_release ||
      type == RenderMessageType::surface_suspend ||
      type == RenderMessageType::surface_resume;
  if (allocation || key_only) {
    if (message.payload.size() != (allocation ? 96U : 16U) ||
        !session::surface::decode_surface_key(
            std::span(message.payload).first<16>(), key))
      return {.surface = std::nullopt, .valid = false};
    return {.surface = key, .valid = true};
  }
  if (type == RenderMessageType::frame_ready) {
    session::surface::FrameReady frame{};
    if (!session::surface::decode_frame_ready(message.payload, frame))
      return {.surface = std::nullopt, .valid = false};
    return {.surface = frame.surface, .valid = true};
  }
  if (type == RenderMessageType::input_regions) {
    session::surface::InputRegionUpdate regions{};
    if (!session::surface::decode_input_region_update(message.payload,
                                                       regions))
      return {.surface = std::nullopt, .valid = false};
    return {.surface = regions.surface, .valid = true};
  }
  if (message.message_type ==
      static_cast<std::uint16_t>(wire::CommonMessageType::typed_error)) {
    session::surface::RenderTypedError error{};
    if (!session::surface::decode_render_error(message.payload, error))
      return {.surface = std::nullopt, .valid = false};
    return {.surface = error.surface, .valid = true};
  }
  return {.surface = std::nullopt, .valid = true};
}

} // namespace

class PluginSession::LiveAuthority final : public GenerationAuthority {
public:
  LiveAuthority(permissions::ActivationBinding binding,
                std::shared_ptr<session::LiveGenerationState> live)
      : binding_(std::move(binding)), live_(std::move(live)) {}

  [[nodiscard]] bool
  is_current(const launcher::LaunchIdentity &identity) const noexcept override {
    return identity.plugin_id == binding_.plugin.view() &&
           identity.revision_sha256 == binding_.revision.view() &&
           identity.generation == binding_.generation && live_ &&
           live_->current(binding_);
  }

private:
  permissions::ActivationBinding binding_;
  std::shared_ptr<session::LiveGenerationState> live_;
};

std::unique_ptr<PluginSession> PluginSession::create(
    launcher::Supervisor supervisor, session::ActivationSnapshot snapshot,
    AuthenticatedSessionRuntimeFactory &runtime_factory,
    PluginSessionCreateError &error, PluginSessionEvents *events,
    session::SessionLimits limits, SurfaceIntentSink *intent_sink,
    QObject *parent) {
  error = PluginSessionCreateError::invalid_activation;
  try {
    if (!valid_snapshot(snapshot))
      return {};
  } catch (...) {
    return {};
  }

  const auto nonce = session_nonce();
  if (nonce == 0) {
    error = PluginSessionCreateError::nonce_unavailable;
    return {};
  }

  try {
    auto gesture_clock = std::make_shared<SteadyGestureClock>();
    auto gesture_eligibility =
        std::make_shared<runtime::GestureEligibilityLatch>(gesture_clock);
    auto runtime = runtime_factory.create(
        snapshot.manifest, snapshot.grants, snapshot.revision_directory.get(),
        snapshot.state_directory.get(), nonce, snapshot.live,
        gesture_eligibility);
    if (!runtime) {
      error = PluginSessionCreateError::runtime_unavailable;
      return {};
    }
    const auto binding = snapshot.grants.binding;
    session::SessionToken token{
        .plugin_id = std::string(binding.plugin.view()),
        .revision_sha256 = std::string(binding.revision.view()),
        .generation = binding.generation,
        .session_nonce = nonce,
    };
    auto authority =
        std::make_shared<LiveAuthority>(binding, snapshot.live);
    AuthenticatedSessionLaunch launch{
        .binding = binding,
        .revision_directory =
            session::OwnedFd(snapshot.revision_directory.release()),
        .private_state_directory =
            session::OwnedFd(snapshot.state_directory.release()),
    };
    auto channel = std::make_unique<AuthenticatedSessionChannel>(
        std::move(supervisor), std::move(launch), std::move(authority),
        std::move(runtime), gesture_eligibility);
    auto product = std::unique_ptr<PluginSession>(new PluginSession(
        std::move(token), std::move(snapshot.activation_record),
        std::move(snapshot.manifest),
        std::move(snapshot.grants), std::move(snapshot.live),
        std::move(channel), events, intent_sink,
        std::move(gesture_eligibility), limits, parent));
    error = PluginSessionCreateError::none;
    return product;
  } catch (...) {
    error = PluginSessionCreateError::allocation_failed;
    return {};
  }
}

PluginSession::PluginSession(
    session::SessionToken token, session::OwnedDescriptor activation_record,
    plugins::manifest::ManifestV2 manifest,
    session::policy::GrantSnapshot grants,
    std::shared_ptr<session::LiveGenerationState> live,
    std::unique_ptr<session::SessionChannel> channel,
    PluginSessionEvents *events, SurfaceIntentSink *intent_sink,
    std::shared_ptr<runtime::GestureEligibilityLatch> gesture_eligibility,
    session::SessionLimits limits, QObject *parent)
    : SessionObserver(parent), token_(std::move(token)),
      activation_record_(std::move(activation_record)),
      manifest_(std::move(manifest)),
      grants_(std::move(grants)), live_(std::move(live)),
      router_(token_.generation), events_(events), intent_sink_(intent_sink),
      gesture_eligibility_(std::move(gesture_eligibility)),
      gesture_intents_(std::make_unique<host_session::GestureIntentAuthority>(
          grants_.binding, *gesture_eligibility_)),
      io_(std::make_unique<session::PluginSessionIo>(
          token_, std::move(channel),
          std::make_shared<session::SteadySessionClock>(),
          static_cast<session::SessionObserver *>(this), limits)) {
  surfaces_.reserve(manifest_.surface_names.size());
  for (std::size_t index = 0; index < manifest_.surface_names.size(); ++index) {
    const auto &name = manifest_.surface_names[index];
    surfaces_.push_back({
        .name = name,
        .key = {.id = index + 1, .generation = token_.generation},
        .endpoint = nullptr,
    });
  }
}

PluginSession::~PluginSession() {
  stop();
}

void PluginSession::start() { io_->start(); }

bool PluginSession::send(session::ChannelLane lane, std::uint16_t message_type,
                         std::uint64_t correlation_id,
                         std::vector<std::byte> payload,
                         std::vector<session::OwnedFd> descriptors) {
  if (lane == session::ChannelLane::broker || message_type == 0 ||
      outbound_sequence_ == std::numeric_limits<std::uint64_t>::max())
    return false;
  session::OwnedMessage message{
      .token = token_,
      .lane = lane,
      .message_type = message_type,
      .correlation_id = correlation_id,
      .sequence = outbound_sequence_ + 1,
      .payload = std::move(payload),
      .descriptors = std::move(descriptors),
  };
  if (!io_->enqueue(std::move(message)))
    return false;
  ++outbound_sequence_;
  return true;
}

void PluginSession::revoke() {
  live_->revoke();
  detach_all();
  gesture_intents_->revoke();
  io_->revoke();
}

void PluginSession::stop() {
  live_->revoke();
  detach_all();
  gesture_intents_->revoke();
  io_->stop();
}

SurfaceAttachResult
PluginSession::attach(std::string_view declared_surface,
                      std::span<const std::uint64_t> correlations,
                      session::SurfaceEndpoint &endpoint) {
  if (state() != session::SessionState::running)
    return {.status = SurfaceAttachStatus::session_not_running, .key = {}};
  auto *slot = find_surface(declared_surface);
  if (slot == nullptr)
    return {.status = SurfaceAttachStatus::undeclared_surface, .key = {}};
  if (slot->endpoint != nullptr)
    return {.status = SurfaceAttachStatus::already_attached, .key = slot->key};
  const auto attached = router_.attach(slot->key, correlations, endpoint);
  if (attached != session::AttachResult::attached)
    return {.status = SurfaceAttachStatus::invalid_correlations,
            .key = slot->key};
  const auto declared =
      gesture_intents_->declare_surface(slot->key, slot->name);
  if (declared != host_session::SurfaceDeclarationResult::declared) {
    static_cast<void>(router_.detach(slot->key, endpoint));
    return {.status = SurfaceAttachStatus::invalid_correlations,
            .key = slot->key};
  }
  slot->endpoint = &endpoint;
  return {.status = SurfaceAttachStatus::attached, .key = slot->key};
}

bool PluginSession::detach(std::string_view declared_surface,
                           const session::SurfaceEndpoint &endpoint) {
  auto *slot = find_surface(declared_surface);
  if (slot == nullptr || slot->endpoint != &endpoint ||
      !router_.detach(slot->key, endpoint))
    return false;
  static_cast<void>(gesture_intents_->detach_surface(slot->key));
  slot->endpoint = nullptr;
  return true;
}

bool PluginSession::arm_surface_intent(session::surface::SurfaceKey source,
                                       std::uint64_t input_sequence) {
  return state() == session::SessionState::running &&
         gesture_intents_->arm(source, input_sequence);
}

void PluginSession::clear_surface_intent_eligibility() noexcept {
  gesture_eligibility_->clear();
}

std::size_t PluginSession::surface_count() const noexcept {
  return router_.size();
}

session::SessionState PluginSession::state() const noexcept {
  return io_->state();
}

session::SessionError PluginSession::error() const noexcept {
  return io_->error();
}

const permissions::ActivationBinding &PluginSession::binding() const noexcept {
  return grants_.binding;
}

const plugins::manifest::ManifestV2 &PluginSession::manifest() const noexcept {
  return manifest_;
}

const session::policy::GrantSnapshot &PluginSession::grants() const noexcept {
  return grants_;
}

void PluginSession::state_changed(session::SessionState state,
                                  session::SessionError error) {
  if (state == session::SessionState::revoked ||
      state == session::SessionState::stopped ||
      state == session::SessionState::failed) {
    detach_all();
    gesture_intents_->revoke();
  }
  if (events_)
    events_->state_changed(state, error);
}

void PluginSession::message_received(session::OwnedMessage message) {
  if (message.lane == session::ChannelLane::render) {
    if (message.message_type == static_cast<std::uint16_t>(
                                    session::surface::RenderMessageType::
                                        surface_intent)) {
      session::surface::SurfaceIntentRequest request{};
      if (message.correlation_id != 0 || !message.descriptors.empty() ||
          !session::surface::decode_surface_intent(message.payload, request)) {
        gesture_eligibility_->clear();
        if (events_)
          events_->render_rejected(session::RouteResult::endpoint_rejected);
        return;
      }
      auto admission = gesture_intents_->admit(request);
      if (!admission.intent || intent_sink_ == nullptr ||
          !intent_sink_->accept(std::move(*admission.intent))) {
        if (events_)
          events_->render_rejected(session::RouteResult::endpoint_rejected);
      }
      return;
    }
    const auto destination = render_destination(message);
    if (!destination.valid) {
      if (events_)
        events_->render_rejected(session::RouteResult::endpoint_rejected);
      return;
    }
    const auto result = router_.route(session::OwnedAuthenticatedRenderMessage{
        .launch_generation = token_.generation,
        .message_type = message.message_type,
        .correlation = message.correlation_id,
        .surface = destination.surface,
        .payload = std::move(message.payload),
        .descriptors = std::move(message.descriptors),
    });
    if (result != session::RouteResult::delivered && events_)
      events_->render_rejected(result);
    return;
  }
  if (message.lane == session::ChannelLane::control && events_)
    events_->control_received(message);
}

void PluginSession::detach_all() noexcept {
  for (auto &slot : surfaces_) {
    if (slot.endpoint != nullptr)
      static_cast<void>(gesture_intents_->detach_surface(slot.key));
    slot.endpoint = nullptr;
  }
  router_.detachAll();
}

PluginSession::SurfaceSlot *
PluginSession::find_surface(std::string_view name) noexcept {
  const auto found =
      std::find_if(surfaces_.begin(), surfaces_.end(), [name](const auto &slot) {
        return slot.name == name;
      });
  return found == surfaces_.end() ? nullptr : &*found;
}

#ifdef OMARCHY_PLUGIN_SESSION_TESTING
std::unique_ptr<PluginSession> PluginSessionTestAccess::create_from_activation(
    launcher::Supervisor supervisor, session::ActivationSnapshot snapshot,
    AuthenticatedSessionRuntimeFactory &runtime_factory,
    PluginSessionCreateError &error, PluginSessionEvents *events,
    session::SessionLimits limits, SurfaceIntentSink *intent_sink,
    QObject *parent) {
  return PluginSession::create(std::move(supervisor), std::move(snapshot),
                               runtime_factory, error, events, limits,
                               intent_sink, parent);
}

std::unique_ptr<PluginSession> PluginSessionTestAccess::create(
    session::SessionToken token, plugins::manifest::ManifestV2 manifest,
    session::policy::GrantSnapshot grants,
    std::shared_ptr<session::LiveGenerationState> live,
    std::unique_ptr<session::SessionChannel> channel,
    PluginSessionEvents *events, session::SessionLimits limits,
    SurfaceIntentSink *intent_sink,
    std::shared_ptr<runtime::GestureEligibilityClock> gesture_clock,
    std::shared_ptr<runtime::GestureEligibilityLatch> gesture_eligibility) {
  if (!gesture_clock)
    gesture_clock = std::make_shared<SteadyGestureClock>();
  if (!gesture_eligibility)
    gesture_eligibility =
        std::make_shared<runtime::GestureEligibilityLatch>(gesture_clock);
  return std::unique_ptr<PluginSession>(new PluginSession(
      std::move(token), session::OwnedDescriptor{},
      std::move(manifest), std::move(grants),
      std::move(live), std::move(channel), events, intent_sink,
      std::move(gesture_eligibility), limits, nullptr));
}

int PluginSessionTestAccess::activation_record_fd(
    const PluginSession &session) noexcept {
  return session.activation_record_.get();
}
#endif

} // namespace omarchy::plugin_runtime::channel
