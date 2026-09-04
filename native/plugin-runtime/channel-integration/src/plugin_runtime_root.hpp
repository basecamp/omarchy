#pragma once

#include "plugin_permission_authority.hpp"
#include "plugin_session.hpp"
#include "session_runtime_factory.hpp"
#include "surface_session_port.hpp"

#include <cstdint>
#include <functional>
#include <memory>
#include <mutex>
#include <optional>
#include <span>
#include <string>
#include <string_view>
#include <vector>

namespace omarchy::plugin_runtime::bridge {
namespace detail {
class PluginRuntimeController;
}
}

namespace omarchy::plugin_runtime::channel {

class RootSurfaceSessionPort;
class RuntimeBootstrap;

// Trusted, non-owning product integration hook. It must outlive the root and
// be constructed by the host, never from plugin or QML data. Callbacks return
// promptly and queue lifecycle or permission work to the next host-loop turn;
// they must not synchronously reenter this root while a session callback is on
// the stack. Queued work referencing the root must be canceled or drained
// before root destruction.
class PluginRuntimeHooks : public PluginSessionEvents,
                                     public SurfaceIntentSink {
public:
  ~PluginRuntimeHooks() override = default;
};

class PreparedPluginRuntime;

struct PluginRuntimePreparationResult final {
  std::unique_ptr<PreparedPluginRuntime> runtime;
  bool permission_disabled = false;
};

// Sole runtime composition for one secure plugin. Every authority-bearing
// input is fixed by the trusted host before this root exists. Plugin QML,
// sidecars and IPC can neither replace these inputs nor reach the objects that
// own grants, providers, session bindings or lifecycle.
class PluginRuntimeRoot final {
public:
  ~PluginRuntimeRoot() noexcept;
  PluginRuntimeRoot(const PluginRuntimeRoot &) = delete;
  PluginRuntimeRoot &
  operator=(const PluginRuntimeRoot &) = delete;

private:
  [[nodiscard]] std::optional<permissions::ActivationBinding>
  session_binding() const;
  struct DeclaredSurfaceSet final {
    permissions::ActivationBinding binding;
    std::string plugin_id;
    std::vector<std::string> names;
    std::string canonical_surfaces;
  };
  [[nodiscard]] std::optional<DeclaredSurfaceSet>
  declared_surfaces() const noexcept;
  [[nodiscard]] SurfaceSessionPort &surface_session() noexcept;
  [[nodiscard]] PluginSession *session_unlocked() const noexcept;
  [[nodiscard]] PluginSession *running_session_unlocked() const noexcept;
  struct Configuration final {
    std::shared_ptr<PluginPermissionAuthority> permissions;
    std::optional<std::string> settings;
    std::optional<std::string> presentation;
    Limits runtime_limits;
    session::SessionLimits session_limits;
#ifdef OMARCHY_PLUGIN_SESSION_TESTING
    std::function<launcher::Supervisor()> test_supervisor_factory;
    void (*test_before_final_fence)(host_session::AuthorityStore &,
                                    void *) noexcept = nullptr;
    void *test_before_final_fence_context = nullptr;
#endif
  };

  [[nodiscard]] static PluginRuntimePreparationResult
  prepare(Configuration &&configuration);
  [[nodiscard]] static std::unique_ptr<PluginRuntimeRoot>
  commit(std::unique_ptr<PreparedPluginRuntime> prepared,
         PluginRuntimeHooks &hooks, QObject &ui_owner);
  explicit PluginRuntimeRoot(Configuration &configuration);
  [[nodiscard]] launcher::Supervisor supervisor() const;
  void stop() noexcept;

  SessionRuntimeFactory runtime_factory_;
  std::shared_ptr<PluginPermissionAuthority> permissions_;
  session::SessionLimits session_limits_;
  std::unique_ptr<PluginSession> session_;
  std::unique_ptr<SurfaceSessionPort> surface_session_;
  mutable std::mutex mutex_;

  friend class SurfaceSessionPort;
  friend class RootSurfaceSessionPort;
  friend class PreparedPluginRuntime;
  friend class RuntimeBootstrap;
  friend class omarchy::plugin_runtime::bridge::detail::PluginRuntimeController;

#ifdef OMARCHY_PLUGIN_SESSION_TESTING
  std::function<launcher::Supervisor()> supervisor_factory_;
  void (*before_final_fence_)(host_session::AuthorityStore &,
                              void *) noexcept = nullptr;
  void *before_final_fence_context_ = nullptr;
  friend class PluginRuntimeRootTestAccess;
#endif
};

class PreparedPluginRuntime final {
public:
  PreparedPluginRuntime(PreparedPluginRuntime &&) noexcept = default;
  PreparedPluginRuntime &operator=(PreparedPluginRuntime &&) noexcept = default;
  PreparedPluginRuntime(const PreparedPluginRuntime &) = delete;
  PreparedPluginRuntime &operator=(const PreparedPluginRuntime &) = delete;

private:
  PreparedPluginRuntime() = default;
  std::unique_ptr<PluginRuntimeRoot> root;
  std::unique_ptr<PreparedPluginSession> session;
  std::optional<host_session::PreparedLiveBinding> live_binding;

  friend class PluginRuntimeRoot;
};

#ifdef OMARCHY_PLUGIN_SESSION_TESTING
class PluginRuntimeRootTestAccess final {
public:
  [[nodiscard]] static std::optional<permissions::ActivationBinding>
  session_binding(const PluginRuntimeRoot &root) {
    return root.session_binding();
  }
  [[nodiscard]] static SurfaceSessionPort &
  surface_session(PluginRuntimeRoot &root) noexcept {
    return root.surface_session();
  }
  [[nodiscard]] static PluginRuntimePreparationResult
  prepare_from_parts(
      int activation_root_fd, int revision_root_fd, int state_root_fd,
      host_session::OwnedDescriptor authority_root,
      permissions::PluginId plugin, std::uint32_t trusted_uid,
      std::string activation_record,
      std::shared_ptr<const definitions::TrustedDefinitionRegistry> definitions,
      std::shared_ptr<const RuntimeServices> services,
      Limits runtime_limits, session::SessionLimits session_limits,
      std::function<launcher::Supervisor()> supervisor_factory = {},
      void (*before_final_fence)(host_session::AuthorityStore &,
                                 void *) noexcept = nullptr,
      void *before_final_fence_context = nullptr);
  [[nodiscard]] static std::unique_ptr<PluginRuntimeRoot>
  commit(std::unique_ptr<PreparedPluginRuntime> prepared,
         PluginRuntimeHooks &hooks, QObject &ui_owner);
  [[nodiscard]] static bool ui_affine(
      const PluginRuntimeRoot &root,
      const QObject &ui_owner) noexcept;
};
#endif

} // namespace omarchy::plugin_runtime::channel
