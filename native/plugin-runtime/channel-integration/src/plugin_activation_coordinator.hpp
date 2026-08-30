#pragma once

#include "authority_store.hpp"
#include "revision_verifier_adapter.hpp"
#include "plugin_session.hpp"

#include <functional>
#include <memory>
#include <optional>
#include <string_view>

namespace omarchy::plugin_runtime::channel {

class PluginPermissionAuthority;
class PluginRuntimeRoot;

struct PluginActivationPreparationResult final {
  std::unique_ptr<PreparedPluginSession> prepared;
  std::optional<host_session::PreparedLiveBinding> live_binding;
  host_session::ActivationError activation_error =
      host_session::ActivationError::none;
  PluginSessionCreateError session_error = PluginSessionCreateError::none;
  bool permission_disabled = false;

  [[nodiscard]] explicit operator bool() const noexcept {
    return prepared != nullptr && live_binding.has_value() &&
           activation_error == host_session::ActivationError::none &&
           session_error == PluginSessionCreateError::none;
  }
};

// Trusted-host-only product activation path. Plugin input selects only an
// installed record name; descriptor verification and durable active grants
// supply every authority-bearing value used to construct the session.
class PluginActivationCoordinator final {
public:
  ~PluginActivationCoordinator() noexcept;

private:
  PluginActivationCoordinator(
      PluginPermissionAuthority &permissions,
      AuthenticatedSessionRuntimeFactory &runtime_factory,
      session::SessionLimits limits = {});

  [[nodiscard]] PluginSession *session() const noexcept;
  void stop() noexcept;

  [[nodiscard]] PluginActivationPreparationResult prepare();
  [[nodiscard]] bool
  commit(std::unique_ptr<PreparedPluginSession> prepared,
         host_session::PreparedLiveBinding live_binding,
         PluginSessionEvents *events, SurfaceIntentSink *intent_sink);
  [[nodiscard]] launcher::Supervisor supervisor() const;

  PluginPermissionAuthority &permissions_;
  AuthenticatedSessionRuntimeFactory &runtime_factory_;
  session::SessionLimits limits_;
  std::unique_ptr<PluginSession> session_;

  friend class PluginPermissionAuthority;
  friend class PluginRuntimeRoot;

#ifdef OMARCHY_PLUGIN_SESSION_TESTING
  using SupervisorFactory = std::function<launcher::Supervisor()>;
  using BeforeFinalFence =
      void (*)(host_session::AuthorityStore &, void *) noexcept;
  SupervisorFactory supervisor_factory_;
  BeforeFinalFence before_final_fence_ = nullptr;
  void *before_final_fence_context_ = nullptr;
  void set_supervisor_factory(SupervisorFactory factory);
  void set_before_final_fence(BeforeFinalFence callback,
                              void *context) noexcept;
#endif
};

} // namespace omarchy::plugin_runtime::channel
