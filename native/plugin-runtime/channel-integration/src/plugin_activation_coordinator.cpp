#include "plugin_activation_coordinator.hpp"
#include "plugin_permission_controller.hpp"

#include <utility>

namespace omarchy::plugin_runtime::channel {

PluginActivationCoordinator::PluginActivationCoordinator(
    PluginPermissionAuthority &permissions,
    AuthenticatedSessionRuntimeFactory &runtime_factory,
    session::SessionLimits limits)
    : permissions_(permissions), runtime_factory_(runtime_factory),
      limits_(limits) {}

PluginActivationCoordinator::~PluginActivationCoordinator() noexcept { stop(); }

PluginActivationPreparationResult
PluginActivationCoordinator::prepare() {
  stop();
  auto loaded = permissions_.load_activation();
  if (!loaded.snapshot)
    return {.prepared = {},
            .live_binding = {},
            .activation_error = loaded.error,
            .session_error = PluginSessionCreateError::none,
            .permission_disabled = false};
  auto &snapshot = *loaded.snapshot;
  const auto binding = snapshot.grants.binding;
  const auto live = snapshot.live;
  if (snapshot.record.plugin_id != permissions_.expected_plugin_.view())
    return {.prepared = {},
            .live_binding = {},
            .activation_error = host_session::ActivationError::grant_mismatch,
            .session_error = PluginSessionCreateError::none,
            .permission_disabled = false};
  auto live_binding = permissions_.prepare_live_activation(binding, live);
  if (!live_binding)
    return {.prepared = {},
            .live_binding = {},
            .activation_error = host_session::ActivationError::grant_mismatch,
            .session_error = PluginSessionCreateError::none,
            .permission_disabled =
                permissions_.active_revision_status(binding) ==
                host_session::ActiveRevisionStatus::permission_disabled};

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
            .session_error = create_error,
            .permission_disabled = false};
  return {.prepared = std::move(prepared),
          .live_binding = std::move(live_binding),
          .activation_error = host_session::ActivationError::none,
          .session_error = PluginSessionCreateError::none,
          .permission_disabled = false};
}

bool PluginActivationCoordinator::commit(
    std::unique_ptr<PreparedPluginSession> prepared,
    host_session::PreparedLiveBinding live_binding, PluginSessionEvents *events,
    SurfaceIntentSink *intent_sink) {
  if (!prepared)
    return false;
  const auto expected_binding = prepared->grants.binding;
  const auto expected_live = prepared->live;
  PluginSessionCreateError create_error = PluginSessionCreateError::none;
  auto created = PluginSession::commit(std::move(prepared), create_error,
                                       events, intent_sink, nullptr);
  if (!created)
    return false;
#ifdef OMARCHY_PLUGIN_SESSION_TESTING
  if (before_final_fence_)
    before_final_fence_(permissions_.authority_for_test(),
                        before_final_fence_context_);
#endif
  if (!permissions_.commit_live_activation(std::move(live_binding),
                                           expected_binding, expected_live))
    return false;
  created->start();
  session_ = std::move(created);
  return true;
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
  return launcher::Supervisor::packaged();
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

#endif

} // namespace omarchy::plugin_runtime::channel
