#pragma once

#include "../host-session/plugin_session_io.hpp"
#include "authenticated_channel.hpp"
#include "permission_contract.hpp"

#include <memory>
#include <string>

namespace omarchy::plugin_runtime::host_session {
class StructuredBroker;
}

namespace omarchy::plugin_runtime::channel {

namespace session = omarchy::plugin_runtime::host_session;
namespace permissions = omarchy::plugins::permissions;

struct AuthenticatedSessionLaunch final {
  permissions::ActivationBinding binding;
  session::OwnedFd revision_directory;
  session::OwnedFd private_state_directory;
};

#ifdef OMARCHY_AUTHENTICATED_SESSION_CHANNEL_TESTING
class AuthenticatedSessionBackend;
#endif

// Adapts the authenticated v2 transport to PluginSessionIo's semantic message
// contract. All methods, including wake installation and destruction, run on
// one PluginSessionIo worker thread.
class AuthenticatedSessionChannel final : public session::SessionChannel {
public:
  AuthenticatedSessionChannel(
      launcher::Supervisor supervisor, AuthenticatedSessionLaunch launch,
      std::shared_ptr<BrokerDispatcher> dispatcher,
      std::shared_ptr<const GenerationAuthority> authority,
      std::unique_ptr<session::StructuredBroker> broker);
#ifdef OMARCHY_AUTHENTICATED_SESSION_CHANNEL_TESTING
  explicit AuthenticatedSessionChannel(
      std::unique_ptr<AuthenticatedSessionBackend> backend);
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
