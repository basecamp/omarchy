#pragma once

#include "plugin_session_io.hpp"
#include "authenticated_channel.hpp"
#include "permission_contract.hpp"

#include <cstddef>
#include <memory>
#include <string>
#include <vector>

namespace omarchy::plugin_runtime::host_session {
class StructuredBroker;
}
namespace omarchy::plugin_runtime::runtime {
class GestureEligibilityAuthority;
class GestureEligibilityLatch;
} // namespace omarchy::plugin_runtime::runtime

namespace omarchy::plugin_runtime::channel {

namespace session = omarchy::plugin_runtime::host_session;
namespace permissions = omarchy::plugins::permissions;

struct AuthenticatedSessionLaunch final {
  permissions::ActivationBinding binding;
  session::OwnedFd revision_directory;
  session::OwnedFd private_state_directory;
  // Canonical manifest-indexed permission authority for this generation.
  // The channel sends it exactly once during authenticated startup and does
  // not become ready until the worker acknowledges loading its QML with it.
  std::vector<std::byte> permission_snapshot;
  std::vector<std::byte> settings_snapshot;
  std::vector<std::byte> presentation_snapshot;
};

// Owns the broker and every object referenced by it (audit sink, trusted
// definitions, providers and dispatch authority) for the complete async
// channel lifetime. Implementations are created by the trusted product host.
class AuthenticatedSessionRuntime {
public:
  virtual ~AuthenticatedSessionRuntime() = default;
  [[nodiscard]] virtual session::StructuredBroker &broker() noexcept = 0;
};

#ifdef OMARCHY_AUTHENTICATED_SESSION_CHANNEL_TESTING
class AuthenticatedSessionBackend;
#endif

// Adapts the authenticated v2 transport to PluginSessionIo's semantic message
// contract. Before transfer into PluginSessionIo an unlaunched instance owns
// no QObject, notifier, thread affinity, or installed wake callback and may be
// destroyed on any thread. After transfer, all methods and destruction run on
// the one PluginSessionIo worker thread.
class AuthenticatedSessionChannel final : public session::SessionChannel {
public:
  AuthenticatedSessionChannel(
      launcher::Supervisor supervisor, AuthenticatedSessionLaunch launch,
      std::shared_ptr<const GenerationAuthority> authority,
      std::unique_ptr<AuthenticatedSessionRuntime> runtime,
      std::shared_ptr<runtime::GestureEligibilityLatch> gesture_eligibility);
#ifdef OMARCHY_AUTHENTICATED_SESSION_CHANNEL_TESTING
  explicit AuthenticatedSessionChannel(
      std::unique_ptr<AuthenticatedSessionBackend> backend,
      std::vector<std::byte> permission_snapshot);
#endif
  ~AuthenticatedSessionChannel() override;
  AuthenticatedSessionChannel(const AuthenticatedSessionChannel &) = delete;
  AuthenticatedSessionChannel &
  operator=(const AuthenticatedSessionChannel &) = delete;

  [[nodiscard]] session::ChannelError launch(const session::SessionToken &token,
                                             TimePoint deadline) override;
  [[nodiscard]] session::ChannelError handshake(TimePoint deadline) override;
  [[nodiscard]] session::SendStatus send(const session::OwnedMessage &message,
                                         TimePoint deadline) override;
  [[nodiscard]] session::ReceiveResult receive(TimePoint deadline) override;
  [[nodiscard]] bool
  install_wake_handler(session::SessionWakeHandler handler) noexcept override;
  void clear_wake_handler() noexcept override;
  [[nodiscard]] bool revoke(const session::SessionToken &token,
                            TimePoint deadline) noexcept override;
  void terminate(TimePoint deadline) noexcept override;

private:
  struct Impl;
  std::unique_ptr<Impl> implementation_;
};

} // namespace omarchy::plugin_runtime::channel
