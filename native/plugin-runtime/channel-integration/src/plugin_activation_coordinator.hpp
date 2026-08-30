#pragma once

#include "authority_store.hpp"
#include "revision_verifier_adapter.hpp"
#include "plugin_session.hpp"

#include <functional>
#include <memory>
#include <optional>
#include <string_view>

namespace omarchy::plugin_runtime::channel {

class PluginPermissionController;
class ProductionPluginRuntimeRoot;

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

struct PluginActivationPreparationResult final {
  std::unique_ptr<PreparedPluginSession> prepared;
  std::optional<host_session::PreparedLiveBinding> live_binding;
  host_session::ActivationError activation_error =
      host_session::ActivationError::none;
  PluginSessionCreateError session_error = PluginSessionCreateError::none;

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
  [[nodiscard]] PluginActivationPreparationResult
  prepare(std::string_view record_name);
  [[nodiscard]] PluginActivationResult
  commit(std::unique_ptr<PreparedPluginSession> prepared,
         host_session::PreparedLiveBinding live_binding,
         PluginSessionEvents *events, SurfaceIntentSink *intent_sink);
  [[nodiscard]] launcher::Supervisor supervisor() const;
  [[nodiscard]] std::optional<host_session::VerifiedRevision>
  verify_revision(std::string_view record_name) const;

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

  friend class PluginPermissionController;
  friend class ProductionPluginRuntimeRoot;

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
  friend class PluginActivationCoordinatorTestAccess;
#endif
};

#ifdef OMARCHY_PLUGIN_SESSION_TESTING
class PluginActivationCoordinatorTestAccess final {
public:
  static void set_supervisor_factory(
      PluginActivationCoordinator &coordinator,
      PluginActivationCoordinator::SupervisorFactory factory);
  static void set_before_final_fence(
      PluginActivationCoordinator &coordinator,
      PluginActivationCoordinator::BeforeFinalFence callback,
      void *context) noexcept;
  [[nodiscard]] static bool hooks_are(
      const PluginActivationCoordinator &coordinator,
      const PluginSessionEvents *events,
      const SurfaceIntentSink *intent_sink) noexcept;
};
#endif

} // namespace omarchy::plugin_runtime::channel
