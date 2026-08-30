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
  stop();
  if (!authority_root_)
    return {.activation_error = host_session::ActivationError::root_untrusted};

  auto loaded = activation_source_.load(record_name);
  if (!loaded.snapshot)
    return {.activation_error = loaded.error};
  auto &snapshot = *loaded.snapshot;
  const auto binding = snapshot.grants.binding;
  const auto live = snapshot.live;
  if (snapshot.record.plugin_id != expected_plugin_.view() ||
      !authority_.bind_live_activation(binding, live))
    return {.activation_error = host_session::ActivationError::grant_mismatch};

  // Bind before construction so an already-stale active revision cannot enter
  // even the side-effect-free runtime assembly phase.
  PluginSessionCreateError create_error = PluginSessionCreateError::none;
  auto created = PluginSession::create(
      supervisor(), std::move(snapshot), runtime_factory_, create_error, events_,
      limits_, intent_sink_, parent_);
  if (!created)
    return {.session_error = create_error};
  // Construction may race promotion. Rebind the same live state before start;
  // promotion either revoked it or makes this exact active check fail.
  if (!authority_.bind_live_activation(binding, live))
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
PluginActivationCoordinator::verify_revision(std::string_view record_name) const {
  return activation_source_.verified_revision(record_name);
}

#ifdef OMARCHY_PLUGIN_SESSION_TESTING
void PluginActivationCoordinator::set_supervisor_factory(
    SupervisorFactory factory) {
  supervisor_factory_ = std::move(factory);
}

void PluginActivationCoordinatorTestAccess::set_supervisor_factory(
    PluginActivationCoordinator &coordinator,
    PluginActivationCoordinator::SupervisorFactory factory) {
  coordinator.set_supervisor_factory(std::move(factory));
}
#endif

} // namespace omarchy::plugin_runtime::channel
