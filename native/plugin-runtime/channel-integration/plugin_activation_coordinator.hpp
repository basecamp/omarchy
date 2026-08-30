#pragma once

#include "../host-session/authority_store.hpp"
#include "../host-session/revision_verifier_adapter.hpp"
#include "plugin_session.hpp"

#include <functional>
#include <memory>
#include <optional>
#include <string_view>

namespace omarchy::plugin_runtime::channel {

struct PluginActivationResult final {
  PluginSession *session = nullptr;
  host_session::ActivationError activation_error =
      host_session::ActivationError::none;
  PluginSessionCreateError session_error = PluginSessionCreateError::none;

  [[nodiscard]] explicit operator bool() const noexcept {
    return session != nullptr &&
           activation_error == host_session::ActivationError::none &&
           session_error == PluginSessionCreateError::none;
  }
};

// Trusted-host-only product activation path. Plugin input selects only an
// installed record name; descriptor verification and durable active grants
// supply every authority-bearing value used to construct the session.
class PluginActivationCoordinator final {
public:
  PluginActivationCoordinator(
      int activation_root_fd, int revision_root_fd, int state_root_fd,
      host_session::AuthorityStore &authority,
      permissions::PluginId expected_plugin, std::uint32_t trusted_uid,
      AuthenticatedSessionRuntimeFactory &runtime_factory,
      PluginSessionEvents *events = nullptr, session::SessionLimits limits = {},
      SurfaceIntentSink *intent_sink = nullptr, QObject *parent = nullptr);
  ~PluginActivationCoordinator() noexcept;

  [[nodiscard]] PluginActivationResult activate(std::string_view record_name);
  [[nodiscard]] PluginSession *session() const noexcept;
  void stop() noexcept;

private:
  [[nodiscard]] launcher::Supervisor supervisor() const;

  host_session::AuthorityStore &authority_;
  permissions::PluginId expected_plugin_;
  std::optional<host_session::FilesystemIdentity> authority_root_;
  host_session::DescriptorRevisionVerifier revision_verifier_;
  host_session::ActivationSource activation_source_;
  AuthenticatedSessionRuntimeFactory &runtime_factory_;
  PluginSessionEvents *events_;
  session::SessionLimits limits_;
  SurfaceIntentSink *intent_sink_;
  QObject *parent_;
  std::unique_ptr<PluginSession> session_;

#ifdef OMARCHY_PLUGIN_SESSION_TESTING
  using SupervisorFactory = std::function<launcher::Supervisor()>;
  SupervisorFactory supervisor_factory_;
  void set_supervisor_factory(SupervisorFactory factory);
  friend class PluginActivationCoordinatorTestAccess;
#endif
};

#ifdef OMARCHY_PLUGIN_SESSION_TESTING
class PluginActivationCoordinatorTestAccess final {
public:
  static void set_supervisor_factory(
      PluginActivationCoordinator &coordinator,
      PluginActivationCoordinator::SupervisorFactory factory);
};
#endif

} // namespace omarchy::plugin_runtime::channel
