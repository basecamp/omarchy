#include "plugin_activation_coordinator.hpp"

#include <utility>

namespace omarchy::plugin_runtime::channel {

PluginActivationCoordinator::PluginActivationCoordinator(
    int activation_root_fd, int revision_root_fd, int state_root_fd,
    host_session::AuthorityStore &authority,
    permissions::PluginId expected_plugin, std::uint32_t trusted_uid,
    AuthenticatedSessionRuntimeFactory &runtime_factory,
    PluginSessionEvents *events, session::SessionLimits limits,
    SurfaceIntentSink *intent_sink, QObject *parent)
    : authority_(authority), expected_plugin_(std::move(expected_plugin)),
      authority_root_(authority.root_identity()), revision_verifier_(),
      activation_source_(
          activation_root_fd, revision_root_fd, state_root_fd,
          revision_verifier_, authority,
          authority_root_.value_or(host_session::FilesystemIdentity{}),
          std::string(expected_plugin_.view()), trusted_uid),
      runtime_factory_(runtime_factory), events_(events), limits_(limits),
      intent_sink_(intent_sink), parent_(parent) {}

PluginActivationCoordinator::~PluginActivationCoordinator() noexcept { stop(); }

PluginActivationResult
PluginActivationCoordinator::activate(std::string_view record_name) {
  auto prepared = prepare(record_name);
  if (!prepared)
    return {.activation_error = prepared.activation_error,
            .session_error = prepared.session_error};
  return commit(std::move(prepared.prepared), std::move(*prepared.live_binding),
                events_, intent_sink_);
}

PluginActivationPreparationResult
PluginActivationCoordinator::prepare(std::string_view record_name) {
  stop();
  if (!authority_root_)
    return {.prepared = {},
            .live_binding = {},
            .activation_error = host_session::ActivationError::root_untrusted,
            .session_error = PluginSessionCreateError::none};

  auto loaded = activation_source_.load(record_name);
  if (!loaded.snapshot)
    return {.prepared = {},
            .live_binding = {},
            .activation_error = loaded.error,
            .session_error = PluginSessionCreateError::none};
  auto &snapshot = *loaded.snapshot;
  const auto binding = snapshot.grants.binding;
  const auto live = snapshot.live;
  if (snapshot.record.plugin_id != expected_plugin_.view())
    return {.prepared = {},
            .live_binding = {},
            .activation_error = host_session::ActivationError::grant_mismatch,
            .session_error = PluginSessionCreateError::none};
  auto live_binding = authority_.prepare_live_activation(binding, live);
  if (!live_binding)
    return {.prepared = {},
            .live_binding = {},
            .activation_error = host_session::ActivationError::grant_mismatch,
            .session_error = PluginSessionCreateError::none};

  // Bind before construction so an already-stale active revision cannot enter
  // even the side-effect-free runtime assembly phase.
  PluginSessionCreateError create_error = PluginSessionCreateError::none;
  auto prepared =
      PluginSession::prepare(supervisor(), std::move(snapshot),
                             runtime_factory_, create_error, limits_);
  if (!prepared)
    return {.prepared = {},
            .live_binding = {},
            .activation_error = host_session::ActivationError::none,
            .session_error = create_error};
  return {.prepared = std::move(prepared),
          .live_binding = std::move(live_binding),
          .activation_error = host_session::ActivationError::none,
          .session_error = PluginSessionCreateError::none};
}

PluginActivationResult PluginActivationCoordinator::commit(
    std::unique_ptr<PreparedPluginSession> prepared,
    host_session::PreparedLiveBinding live_binding, PluginSessionEvents *events,
    SurfaceIntentSink *intent_sink) {
  if (!prepared)
    return {.session_error = PluginSessionCreateError::invalid_activation};
  if ((events_ != nullptr && events_ != events) ||
      (intent_sink_ != nullptr && intent_sink_ != intent_sink))
    return {.session_error = PluginSessionCreateError::invalid_activation};
  events_ = events;
  intent_sink_ = intent_sink;
  const auto expected_binding = prepared->grants.binding;
  const auto expected_live = prepared->live;
  PluginSessionCreateError create_error = PluginSessionCreateError::none;
  auto created = PluginSession::commit(std::move(prepared), create_error,
                                       events, intent_sink, parent_);
  if (!created)
    return {.session_error = create_error};
#ifdef OMARCHY_PLUGIN_SESSION_TESTING
  if (before_final_fence_)
    before_final_fence_(authority_, before_final_fence_context_);
#endif
  if (!authority_.commit_live_activation(std::move(live_binding),
                                         expected_binding, expected_live))
    return {.activation_error = host_session::ActivationError::grant_mismatch};
  created->start();
  session_ = std::move(created);
  return {.session = session_.get()};
}

PluginSession *PluginActivationCoordinator::session() const noexcept {
  return session_.get();
}

void PluginActivationCoordinator::stop() noexcept {
  if (!session_)
    return;
  session_->revoke();
  session_->stop();
  session_.reset();
}

launcher::Supervisor PluginActivationCoordinator::supervisor() const {
#ifdef OMARCHY_PLUGIN_SESSION_TESTING
  if (supervisor_factory_)
    return supervisor_factory_();
#endif
  return launcher::Supervisor::production();
}

std::optional<host_session::VerifiedRevision>
PluginActivationCoordinator::verify_revision(
    std::string_view record_name) const {
  return activation_source_.verified_revision(record_name);
}

#ifdef OMARCHY_PLUGIN_SESSION_TESTING
void PluginActivationCoordinator::set_supervisor_factory(
    SupervisorFactory factory) {
  supervisor_factory_ = std::move(factory);
}

void PluginActivationCoordinator::set_before_final_fence(
    BeforeFinalFence callback, void *context) noexcept {
  before_final_fence_ = callback;
  before_final_fence_context_ = context;
}

void PluginActivationCoordinatorTestAccess::set_supervisor_factory(
    PluginActivationCoordinator &coordinator,
    PluginActivationCoordinator::SupervisorFactory factory) {
  coordinator.set_supervisor_factory(std::move(factory));
}

void PluginActivationCoordinatorTestAccess::set_before_final_fence(
    PluginActivationCoordinator &coordinator,
    PluginActivationCoordinator::BeforeFinalFence callback,
    void *context) noexcept {
  coordinator.set_before_final_fence(callback, context);
}

bool PluginActivationCoordinatorTestAccess::hooks_are(
    const PluginActivationCoordinator &coordinator,
    const PluginSessionEvents *events,
    const SurfaceIntentSink *intent_sink) noexcept {
  return coordinator.events_ == events &&
         coordinator.intent_sink_ == intent_sink;
}
#endif

} // namespace omarchy::plugin_runtime::channel
