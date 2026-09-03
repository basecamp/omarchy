#pragma once

#include "MultiSurfaceRouter.h"
#include "activation_snapshot.hpp"
#include "gesture_intent.hpp"
#include "authenticated_session_channel.hpp"
#include "omarchy/plugin/wire/permission_snapshot.hpp"

#include <memory>
#include <span>
#include <string_view>
#include <utility>
#include <vector>

namespace omarchy::plugin_runtime::channel {

#ifdef OMARCHY_PLUGIN_SESSION_TESTING
class PluginSessionTestAccess;
#endif
class PreparedPluginSession;
class PluginRuntimeRoot;

class AuthenticatedSessionRuntimeFactory {
public:
  virtual ~AuthenticatedSessionRuntimeFactory() = default;
  // Projects the authority snapshot into the permissions visible to this
  // exact runtime composition. Implementations may remove operation bits for
  // optional grants whose trusted provider is currently absent, but must not
  // widen durable authority.
  [[nodiscard]] virtual std::optional<
      plugin::wire::permission_snapshot::PermissionSnapshot>
  project_permissions(const plugins::manifest::ManifestV2 &manifest,
                      const session::policy::GrantSnapshot &grants) const;
  // Construction may allocate owned provider/runtime state, but it must not
  // launch code or perform plugin-visible/system effects. Start and the
  // authenticated generation fences are the first effect boundary.
  // Both descriptors name the exact activation objects and are borrowed only
  // for this call. A returned owner must hold any descriptor it retains. It
  // must also retain the exact supplied LiveGenerationState as long as an
  // asynchronous effect can settle, and every DispatchAuthorityLease must
  // consult that state at effect time rather than a reconstructed generation.
  [[nodiscard]] virtual std::unique_ptr<AuthenticatedSessionRuntime>
  create(const plugins::manifest::ManifestV2 &manifest,
         const session::policy::GrantSnapshot &grants,
         int revision_directory_fd, int private_state_directory_fd,
         std::uint64_t session_nonce,
         std::shared_ptr<session::LiveGenerationState> live_generation,
         std::shared_ptr<runtime::GestureEligibilityLatch>
             gesture_eligibility) = 0;
};

class PluginSessionEvents {
public:
  virtual ~PluginSessionEvents() = default;
  virtual void state_changed(session::SessionState state,
                             session::SessionError error) = 0;
  virtual void render_rejected(session::RouteResult result) = 0;
  [[nodiscard]] virtual bool update_settings(
      const permissions::ActivationBinding &,
      std::string_view) { return false; }
};

// The shell-side consumer performs the final freshness check immediately
// before publishing the effect. Keeping this interface move-only prevents an
// admitted intent from being copied or replayed between host components.
class SurfaceIntentSink {
public:
  virtual ~SurfaceIntentSink() = default;
  [[nodiscard]] virtual bool
  accept(host_session::AdmittedSurfaceIntent intent) = 0;
};

enum class PluginSessionCreateError : std::uint8_t {
  none,
  invalid_activation,
  nonce_unavailable,
  runtime_unavailable,
  allocation_failed,
};

enum class SurfaceAttachStatus : std::uint8_t {
  attached,
  session_not_running,
  undeclared_surface,
  already_attached,
  invalid_correlations,
  allocation_failed,
};

#ifdef OMARCHY_PLUGIN_SESSION_TESTING
enum class SurfaceAttachFault : std::uint8_t { none, after_router };
#endif

struct SurfaceAttachResult final {
  SurfaceAttachStatus status = SurfaceAttachStatus::undeclared_surface;
  session::surface::SurfaceKey key{};
  [[nodiscard]] explicit operator bool() const noexcept {
    return status == SurfaceAttachStatus::attached;
  }
};

// Product composition root for one verified plugin activation. One instance
// owns one worker/channel/sandbox/sidecar lifecycle and routes every attached
// surface over that single authenticated render lane.
class PluginSession final : private session::SessionObserver {
public:
  ~PluginSession() override;
  PluginSession(const PluginSession &) = delete;
  PluginSession &operator=(const PluginSession &) = delete;

  void start();
  [[nodiscard]] bool
  send_render(std::uint16_t message_type, std::uint64_t correlation_id,
              std::vector<std::byte> payload,
              std::vector<session::OwnedFd> descriptors = {});
  void revoke();
  void stop();

  [[nodiscard]] SurfaceAttachResult
  attach(std::string_view declared_surface,
         std::span<const std::uint64_t> correlations,
         session::SurfaceEndpoint &endpoint);
  [[nodiscard]] bool detach(std::string_view declared_surface,
                            const session::SurfaceEndpoint &endpoint) noexcept;
  // Called only after trusted host-input admission accepts physical input. If
  // the input packet cannot be sent, the caller must clear the exact source.
  [[nodiscard]] bool arm_surface_intent(session::surface::SurfaceKey source,
                                        std::uint64_t input_sequence);
  void clear_surface_intent_eligibility(
      session::surface::SurfaceKey source) noexcept;
  [[nodiscard]] std::size_t surface_count() const noexcept;
  [[nodiscard]] session::SessionState state() const noexcept;
  [[nodiscard]] session::SessionError error() const noexcept;
  [[nodiscard]] const permissions::ActivationBinding &binding() const noexcept;
  [[nodiscard]] std::uint64_t session_nonce_value() const noexcept;
  [[nodiscard]] const plugins::manifest::ManifestV2 &manifest() const noexcept;
  [[nodiscard]] const session::policy::GrantSnapshot &grants() const noexcept;

private:
  [[nodiscard]] static std::unique_ptr<PreparedPluginSession>
  prepare(launcher::Supervisor supervisor, session::ActivationSnapshot snapshot,
          AuthenticatedSessionRuntimeFactory &runtime_factory,
          PluginSessionCreateError &error, session::SessionLimits limits,
          std::optional<std::string> settings = std::nullopt);
  [[nodiscard]] static std::unique_ptr<PluginSession>
  commit(std::unique_ptr<PreparedPluginSession> prepared,
         PluginSessionCreateError &error, PluginSessionEvents *events,
         SurfaceIntentSink *intent_sink, QObject *parent);

  class LiveAuthority;
  PluginSession(
      session::SessionToken token, session::OwnedDescriptor activation_record,
      plugins::manifest::ManifestV2 manifest,
      session::policy::GrantSnapshot grants,
      std::shared_ptr<session::LiveGenerationState> live,
      std::unique_ptr<session::SessionChannel> channel,
      PluginSessionEvents *events, SurfaceIntentSink *intent_sink,
      std::shared_ptr<runtime::GestureEligibilityLatch> gesture_eligibility,
      session::SessionLimits limits, QObject *parent);

  void state_changed(session::SessionState state,
                     session::SessionError error) override;
  void message_received(session::OwnedMessage message) override;
  void detach_all() noexcept;

  struct SurfaceSlot final {
    std::string name;
    session::surface::SurfaceKey key;
    session::SurfaceEndpoint *endpoint = nullptr;
  };
  [[nodiscard]] SurfaceSlot *find_surface(std::string_view name) noexcept;

  session::SessionToken token_;
  session::OwnedDescriptor activation_record_;
  plugins::manifest::ManifestV2 manifest_;
  session::policy::GrantSnapshot grants_;
  std::shared_ptr<session::LiveGenerationState> live_;
  session::MultiSurfaceRouter router_;
  std::vector<SurfaceSlot> surfaces_;
  PluginSessionEvents *events_ = nullptr;
  SurfaceIntentSink *intent_sink_ = nullptr;
  std::shared_ptr<runtime::GestureEligibilityLatch> gesture_eligibility_;
  std::unique_ptr<host_session::GestureIntentAuthority> gesture_intents_;
  std::unique_ptr<session::PluginSessionIo> io_;
  std::uint64_t outbound_sequence_ = 0;

#ifdef OMARCHY_PLUGIN_SESSION_TESTING
  SurfaceAttachFault surface_attach_fault_ = SurfaceAttachFault::none;
  friend class PluginSessionTestAccess;
#endif
  friend class PluginRuntimeRoot;
};

// Fully validated and assembled activation state with no QObject ownership or
// effects. It may cross from a lifecycle worker to the UI thread; only
// PluginSession::commit constructs the observer and PluginSessionIo there.
class PreparedPluginSession final {
public:
  PreparedPluginSession(PreparedPluginSession &&) noexcept = default;
  PreparedPluginSession &operator=(PreparedPluginSession &&) noexcept = default;
  PreparedPluginSession(const PreparedPluginSession &) = delete;
  PreparedPluginSession &operator=(const PreparedPluginSession &) = delete;

private:
  PreparedPluginSession(
      session::SessionToken token, session::OwnedDescriptor activation_record,
      plugins::manifest::ManifestV2 manifest,
      session::policy::GrantSnapshot grants,
      std::shared_ptr<session::LiveGenerationState> live,
      std::unique_ptr<session::SessionChannel> channel,
      std::shared_ptr<runtime::GestureEligibilityLatch> gesture_eligibility,
      session::SessionLimits limits) noexcept
      : token(std::move(token)),
        activation_record(std::move(activation_record)),
        manifest(std::move(manifest)), grants(std::move(grants)),
        live(std::move(live)), channel(std::move(channel)),
        gesture_eligibility(std::move(gesture_eligibility)), limits(limits) {}

  session::SessionToken token;
  session::OwnedDescriptor activation_record;
  plugins::manifest::ManifestV2 manifest;
  session::policy::GrantSnapshot grants;
  std::shared_ptr<session::LiveGenerationState> live;
  std::unique_ptr<session::SessionChannel> channel;
  std::shared_ptr<runtime::GestureEligibilityLatch> gesture_eligibility;
  session::SessionLimits limits;

  friend class PluginSession;
  friend class PluginRuntimeRoot;
#ifdef OMARCHY_PLUGIN_SESSION_TESTING
  friend class PluginSessionTestAccess;
#endif
};

#ifdef OMARCHY_PLUGIN_SESSION_TESTING
class PluginSessionTestAccess final {
public:
  [[nodiscard]] static std::unique_ptr<PreparedPluginSession>
  prepare_from_activation(launcher::Supervisor supervisor,
                          session::ActivationSnapshot snapshot,
                          AuthenticatedSessionRuntimeFactory &runtime_factory,
                          PluginSessionCreateError &error,
                          session::SessionLimits limits = {},
                          std::optional<std::string> settings = std::nullopt);
  [[nodiscard]] static std::unique_ptr<PreparedPluginSession>
  prepare_from_parts(
      session::SessionToken token, plugins::manifest::ManifestV2 manifest,
      session::policy::GrantSnapshot grants,
      std::shared_ptr<session::LiveGenerationState> live,
      std::unique_ptr<session::SessionChannel> channel,
      session::SessionLimits limits = {},
      std::shared_ptr<runtime::GestureEligibilityClock> gesture_clock = {},
      std::shared_ptr<runtime::GestureEligibilityLatch> gesture_eligibility =
          {});
  [[nodiscard]] static std::unique_ptr<PluginSession>
  commit(std::unique_ptr<PreparedPluginSession> prepared,
         PluginSessionCreateError &error, PluginSessionEvents *events = nullptr,
         SurfaceIntentSink *intent_sink = nullptr, QObject *parent = nullptr);
  [[nodiscard]] static int
  activation_record_fd(const PluginSession &session) noexcept;
  [[nodiscard]] static std::shared_ptr<session::LiveGenerationState>
  live_generation(const PluginSession &session) noexcept;
  [[nodiscard]] static bool ui_affine(const PluginSession &session,
                                      const QThread *thread) noexcept;
  static void set_surface_attach_fault(PluginSession &session,
                                       SurfaceAttachFault fault) noexcept;
};
#endif

} // namespace omarchy::plugin_runtime::channel
