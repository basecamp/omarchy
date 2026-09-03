#include "plugin_session.hpp"

#include "omarchy/plugin/wire/control.hpp"
#include "omarchy/plugin/wire/surface_name.hpp"
#include "omarchy/plugin_runtime/surface/render_messages.hpp"
#include "permission_projection.hpp"

#include <QDebug>

#include <sys/random.h>

#include <algorithm>
#include <cerrno>
#include <chrono>
#include <limits>
#include <utility>

namespace omarchy::plugin_runtime::channel {
namespace wire = omarchy::plugin::wire;
namespace {

const char *intent_failure_name(
    host_session::SurfaceIntentAdmissionFailure failure) noexcept {
  using Failure = host_session::SurfaceIntentAdmissionFailure;
  switch (failure) {
  case Failure::none:
    return "none";
  case Failure::malformed:
    return "malformed";
  case Failure::gesture_missing:
    return "gesture-missing";
  case Failure::stale_activation:
    return "stale-activation";
  case Failure::unknown_source:
    return "unknown-source";
  case Failure::unknown_target:
    return "unknown-target";
  case Failure::revoked:
    return "revoked";
  }
  return "unknown";
}

const char *intent_action_name(
    session::surface::SurfaceIntentAction action) noexcept {
  switch (action) {
  case session::surface::SurfaceIntentAction::open:
    return "open";
  case session::surface::SurfaceIntentAction::toggle:
    return "toggle";
  case session::surface::SurfaceIntentAction::dismiss:
    return "dismiss";
  }
  return "invalid";
}

void log_intent_admission(std::string_view plugin,
                          const session::surface::SurfaceIntentRequest &request,
                          const char *decision, const char *reason) {
  qInfo().noquote().nospace()
      << "omarchy-plugin-security stage=host-surface-intent decision="
      << decision << " reason=" << reason << " plugin="
      << QString::fromUtf8(plugin.data(), static_cast<qsizetype>(plugin.size()))
      << " source-id=" << request.source.id << " target-id="
      << request.target.id << " generation=" << request.source.generation
      << " input-sequence=" << request.input_sequence << " action="
      << intent_action_name(request.action);
}

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
         snapshot.live->current(snapshot.grants.binding) &&
         snapshot.manifest.id == snapshot.record.plugin_id &&
         plugins::manifest::requested_capability_fingerprint(
             snapshot.manifest.requests) ==
             snapshot.grants.source_request_fingerprint.view() &&
        snapshot.manifest.surface_names.size() <= wire::kMaximumPluginSurfaces))
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
    if (!session::surface::decode_input_region_update(message.payload, regions))
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

std::optional<plugin::wire::permission_snapshot::PermissionSnapshot>
AuthenticatedSessionRuntimeFactory::project_permissions(
    const plugins::manifest::ManifestV2 &manifest,
    const session::policy::GrantSnapshot &grants) const {
  return session::project_permission_snapshot(manifest, grants);
}

std::unique_ptr<PreparedPluginSession> PluginSession::prepare(
    launcher::Supervisor supervisor, session::ActivationSnapshot snapshot,
    AuthenticatedSessionRuntimeFactory &runtime_factory,
    PluginSessionCreateError &error, session::SessionLimits limits,
    std::optional<std::string> settings) {
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
    const auto projected =
        runtime_factory.project_permissions(snapshot.manifest, snapshot.grants);
    if (!projected)
      return {};
    auto permission_snapshot = wire::permission_snapshot::encode(*projected);
    if (permission_snapshot.empty())
      return {};
    auto settings_entry = snapshot.manifest.settings.defaults;
    if (settings) {
      const auto parsed =
          plugins::manifest::parse_settings_entry(snapshot.manifest, *settings);
      if (parsed)
        settings_entry = *parsed;
    }
    const auto canonical_settings =
        plugins::manifest::canonical_settings_entry(settings_entry);
    const auto settings_bytes = std::as_bytes(std::span(canonical_settings));
    std::vector<std::byte> settings_snapshot(settings_bytes.begin(),
                                             settings_bytes.end());
    auto gesture_clock = std::make_shared<SteadyGestureClock>();
    auto gesture_eligibility =
        std::make_shared<runtime::GestureEligibilityLatch>(gesture_clock);
    auto runtime = runtime_factory.create(snapshot.manifest, snapshot.grants,
                                          snapshot.revision_directory.get(),
                                          snapshot.state_directory.get(), nonce,
                                          snapshot.live, gesture_eligibility);
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
    auto authority = std::make_shared<LiveAuthority>(binding, snapshot.live);
    AuthenticatedSessionLaunch launch{
        .binding = binding,
        .revision_directory =
            session::OwnedFd(snapshot.revision_directory.release()),
        .private_state_directory =
            session::OwnedFd(snapshot.state_directory.release()),
        .permission_snapshot = std::move(permission_snapshot),
        .settings_snapshot = std::move(settings_snapshot),
    };
    auto channel = std::make_unique<AuthenticatedSessionChannel>(
        std::move(supervisor), std::move(launch), std::move(authority),
        std::move(runtime), gesture_eligibility);
    auto product =
        std::unique_ptr<PreparedPluginSession>(new PreparedPluginSession(
        std::move(token), std::move(snapshot.activation_record),
            std::move(snapshot.manifest), std::move(snapshot.grants),
            std::move(snapshot.live), std::move(channel),
            std::move(gesture_eligibility), limits));
    error = PluginSessionCreateError::none;
    return product;
  } catch (...) {
    error = PluginSessionCreateError::allocation_failed;
    return {};
  }
}

std::unique_ptr<PluginSession>
PluginSession::commit(std::unique_ptr<PreparedPluginSession> prepared,
                      PluginSessionCreateError &error,
                      PluginSessionEvents *events,
                      SurfaceIntentSink *intent_sink, QObject *parent) {
  if (!prepared) {
    error = PluginSessionCreateError::invalid_activation;
    return {};
  }
  try {
    auto product = std::unique_ptr<PluginSession>(new PluginSession(
        std::move(prepared->token), std::move(prepared->activation_record),
        std::move(prepared->manifest), std::move(prepared->grants),
        std::move(prepared->live), std::move(prepared->channel), events,
        intent_sink, std::move(prepared->gesture_eligibility), prepared->limits,
        parent));
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
      manifest_(std::move(manifest)), grants_(std::move(grants)),
      live_(std::move(live)), router_(token_.generation), events_(events),
      intent_sink_(intent_sink),
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
    const auto binding =
        wire::manifest_surface_binding(name, index, token_.generation);
    if (!binding)
      throw std::invalid_argument("invalid canonical manifest surface binding");
    const surface::SurfaceKey key{
        .id = binding->id, .generation = binding->generation};
    if (gesture_intents_->declare_surface(key, name) !=
        host_session::SurfaceDeclarationResult::declared)
      throw std::invalid_argument(
          "invalid canonical manifest surface declaration");
    surfaces_.push_back(
        {.name = name, .key = key, .endpoint = nullptr});
  }
}

PluginSession::~PluginSession() { stop(); }

void PluginSession::start() { io_->start(); }

bool PluginSession::send_render(
    std::uint16_t message_type, std::uint64_t correlation_id,
    std::vector<std::byte> payload,
    std::vector<session::OwnedFd> descriptors) {
  if (message_type == 0 ||
      outbound_sequence_ == std::numeric_limits<std::uint64_t>::max())
    return false;
  session::OwnedMessage message{
      .token = token_,
      .lane = session::ChannelLane::render,
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

namespace {
bool send_settings_result(session::PluginSessionIo &io,
                          const session::SessionToken &token,
                          std::uint64_t &sequence, std::uint64_t correlation,
                          bool accepted) {
  if (correlation == 0 ||
      sequence == std::numeric_limits<std::uint64_t>::max())
    return false;
  session::OwnedMessage reply{
      .token = token,
      .lane = session::ChannelLane::control,
      .message_type = wire::kSettingsUpdateResultMessage,
      .correlation_id = correlation,
      .sequence = sequence + 1,
      .payload = {accepted ? std::byte{1} : std::byte{0}},
      .descriptors = {},
  };
  if (!io.enqueue(std::move(reply)))
    return false;
  ++sequence;
  return true;
}
} // namespace

void PluginSession::revoke() {
  (void)live_->revoke_and_drain();
  detach_all();
  gesture_intents_->revoke();
  io_->revoke();
}

void PluginSession::stop() {
  (void)live_->revoke_and_drain();
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
  session::AttachResult attached = session::AttachResult::invalid_registration;
  try {
    // Finish every allocation before the router publishes the endpoint.
    attached = router_.attach(slot->key, correlations, endpoint);
  } catch (...) {
    return {.status = SurfaceAttachStatus::allocation_failed, .key = slot->key};
  }
  if (attached != session::AttachResult::attached)
    return {.status = SurfaceAttachStatus::invalid_correlations,
            .key = slot->key};
#ifdef OMARCHY_PLUGIN_SESSION_TESTING
  if (surface_attach_fault_ == SurfaceAttachFault::after_router) {
    surface_attach_fault_ = SurfaceAttachFault::none;
    static_cast<void>(router_.detach(slot->key, endpoint));
    return {.status = SurfaceAttachStatus::allocation_failed, .key = slot->key};
  }
#endif
  if (!gesture_intents_->attach_surface(slot->key)) {
    static_cast<void>(router_.detach(slot->key, endpoint));
    return {.status = SurfaceAttachStatus::allocation_failed, .key = slot->key};
  }
  slot->endpoint = &endpoint;
  return {.status = SurfaceAttachStatus::attached, .key = slot->key};
}

bool PluginSession::detach(std::string_view declared_surface,
                           const session::SurfaceEndpoint &endpoint) noexcept {
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

void PluginSession::clear_surface_intent_eligibility(
    session::surface::SurfaceKey source) noexcept {
  gesture_intents_->clear_surface_eligibility(source);
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

std::uint64_t PluginSession::session_nonce_value() const noexcept {
  return token_.session_nonce;
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
  if (message.lane == session::ChannelLane::control &&
      message.message_type == wire::kSettingsUpdateMessage) {
    bool accepted = false;
    if (message.correlation_id != 0 && message.descriptors.empty() &&
        message.payload.size() <= 64 * 1024) {
      const std::string bytes(
          reinterpret_cast<const char *>(message.payload.data()),
          message.payload.size());
      const auto entry = plugins::manifest::parse_settings_entry(manifest_,
                                                                  bytes);
      if (entry && events_)
        accepted = events_->update_settings(
            grants_.binding,
            plugins::manifest::canonical_settings_entry(*entry));
    }
    if (!send_settings_result(*io_, token_, outbound_sequence_,
                              message.correlation_id, accepted))
      io_->stop();
    return;
  }
  if (message.lane == session::ChannelLane::render) {
    if (message.message_type ==
        static_cast<std::uint16_t>(
            session::surface::RenderMessageType::surface_intent)) {
      session::surface::SurfaceIntentRequest request{};
      if (message.correlation_id != 0 || !message.descriptors.empty() ||
          !session::surface::decode_surface_intent(message.payload, request)) {
        log_intent_admission(token_.plugin_id, request, "rejected",
                             "wire-invalid");
        gesture_eligibility_->clear();
        if (events_)
          events_->render_rejected(session::RouteResult::endpoint_rejected);
        return;
      }
      auto admission = gesture_intents_->admit(request);
      if (!admission.intent) {
        log_intent_admission(token_.plugin_id, request, "rejected",
                             intent_failure_name(admission.failure));
        if (events_)
          events_->render_rejected(session::RouteResult::endpoint_rejected);
        return;
      }
      if (intent_sink_ == nullptr) {
        log_intent_admission(token_.plugin_id, request, "rejected",
                             "sink-unavailable");
        if (events_)
          events_->render_rejected(session::RouteResult::endpoint_rejected);
        return;
      }
      if (!intent_sink_->accept(std::move(*admission.intent))) {
        log_intent_admission(token_.plugin_id, request, "rejected",
                             "sink-rejected");
        if (events_)
          events_->render_rejected(session::RouteResult::endpoint_rejected);
        return;
      }
      log_intent_admission(token_.plugin_id, request, "admitted",
                           "eligibility-consumed");
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
      std::find_if(surfaces_.begin(), surfaces_.end(),
                   [name](const auto &slot) { return slot.name == name; });
  return found == surfaces_.end() ? nullptr : &*found;
}

#ifdef OMARCHY_PLUGIN_SESSION_TESTING
std::unique_ptr<PreparedPluginSession>
PluginSessionTestAccess::prepare_from_activation(
    launcher::Supervisor supervisor, session::ActivationSnapshot snapshot,
    AuthenticatedSessionRuntimeFactory &runtime_factory,
    PluginSessionCreateError &error, session::SessionLimits limits,
    std::optional<std::string> settings) {
  return PluginSession::prepare(std::move(supervisor), std::move(snapshot),
                                runtime_factory, error, limits,
                                std::move(settings));
}

std::unique_ptr<PreparedPluginSession>
PluginSessionTestAccess::prepare_from_parts(
    session::SessionToken token, plugins::manifest::ManifestV2 manifest,
    session::policy::GrantSnapshot grants,
    std::shared_ptr<session::LiveGenerationState> live,
    std::unique_ptr<session::SessionChannel> channel,
    session::SessionLimits limits,
    std::shared_ptr<runtime::GestureEligibilityClock> gesture_clock,
    std::shared_ptr<runtime::GestureEligibilityLatch> gesture_eligibility) {
  if (!gesture_clock)
    gesture_clock = std::make_shared<SteadyGestureClock>();
  if (!gesture_eligibility)
    gesture_eligibility =
        std::make_shared<runtime::GestureEligibilityLatch>(gesture_clock);
  return std::unique_ptr<PreparedPluginSession>(new PreparedPluginSession(
      std::move(token), session::OwnedDescriptor{}, std::move(manifest),
      std::move(grants), std::move(live), std::move(channel),
      std::move(gesture_eligibility), limits));
}

std::unique_ptr<PluginSession> PluginSessionTestAccess::commit(
    std::unique_ptr<PreparedPluginSession> prepared,
    PluginSessionCreateError &error, PluginSessionEvents *events,
    SurfaceIntentSink *intent_sink, QObject *parent) {
  return PluginSession::commit(std::move(prepared), error, events, intent_sink,
                               parent);
}

int PluginSessionTestAccess::activation_record_fd(
    const PluginSession &session) noexcept {
  return session.activation_record_.get();
}

std::shared_ptr<session::LiveGenerationState>
PluginSessionTestAccess::live_generation(
    const PluginSession &session) noexcept {
  return session.live_;
}

bool PluginSessionTestAccess::ui_affine(const PluginSession &session,
                                        const QThread *thread) noexcept {
  return session.QObject::thread() == thread && session.io_ &&
         session.io_->thread() == thread;
}

void PluginSessionTestAccess::set_surface_attach_fault(
    PluginSession &session, SurfaceAttachFault fault) noexcept {
  session.surface_attach_fault_ = fault;
}
#endif

} // namespace omarchy::plugin_runtime::channel
