#pragma once

#include "omarchy/plugin/wire/state.hpp"
#include "omarchy/plugin_runtime/launcher/launcher.h"
#include "omarchy/plugin_runtime/launcher/termination_state.h"

#include <chrono>
#include <cstdint>
#include <memory>
#include <string>

namespace omarchy::plugin_runtime::channel {

namespace launcher = omarchy::plugin_runtime::launcher;
namespace wire = omarchy::plugin::wire;

enum class ChannelFailure : std::uint8_t {
  none,
  launch_failed,
  identity_mismatch,
  peer_failure,
  malformed_envelope,
  negotiation_failed,
  readiness_failed,
  not_ready,
  role_version_mismatch,
  stale_generation,
  dispatch_failed,
};

enum class DispatchStatus : std::uint8_t {
  dispatched,
  timeout,
  fatal,
  not_ready,
};

class BrokerDispatcher {
public:
  virtual ~BrokerDispatcher() = default;
  [[nodiscard]] virtual bool dispatch(const wire::PacketView &packet) = 0;
};

class GenerationAuthority {
public:
  virtual ~GenerationAuthority() = default;
  [[nodiscard]] virtual bool
  is_current(const launcher::LaunchIdentity &identity) const noexcept = 0;
};

class AuthenticatedBrokerChannel;

struct OpenResult {
  std::unique_ptr<AuthenticatedBrokerChannel> channel;
  ChannelFailure failure = ChannelFailure::none;
  launcher::LaunchFailure launch_failure = launcher::LaunchFailure::none;
  std::string detail;

  [[nodiscard]] explicit operator bool() const { return channel != nullptr; }
};

class AuthenticatedBrokerChannel {
public:
  [[nodiscard]] static OpenResult
  open(launcher::Supervisor &supervisor,
       const launcher::TrustedLaunchRequest &request,
       std::shared_ptr<BrokerDispatcher> dispatcher,
       std::shared_ptr<const GenerationAuthority> authority);

  AuthenticatedBrokerChannel(const AuthenticatedBrokerChannel &) = delete;
  AuthenticatedBrokerChannel &
  operator=(const AuthenticatedBrokerChannel &) = delete;
  ~AuthenticatedBrokerChannel();

  [[nodiscard]] bool negotiate(std::chrono::milliseconds timeout);
  [[nodiscard]] DispatchStatus dispatch_one(std::chrono::milliseconds timeout);
  [[nodiscard]] bool ready() const;
  [[nodiscard]] bool alive() const;
  [[nodiscard]] bool failed() const;
  [[nodiscard]] ChannelFailure failure() const;
  [[nodiscard]] const std::string &detail() const;
  [[nodiscard]] const launcher::LaunchIdentity &identity() const;
  [[nodiscard]] bool terminate();

private:
  AuthenticatedBrokerChannel(
      std::unique_ptr<launcher::Worker> worker,
      launcher::LaunchIdentity identity,
      std::shared_ptr<BrokerDispatcher> dispatcher,
      std::shared_ptr<const GenerationAuthority> authority);

  [[nodiscard]] bool negotiate_role(wire::EndpointRole role,
                                    std::chrono::milliseconds timeout);
  bool fail(ChannelFailure failure, std::string detail);

  std::unique_ptr<launcher::Worker> worker_;
  launcher::LaunchIdentity identity_;
  std::shared_ptr<BrokerDispatcher> dispatcher_;
  std::shared_ptr<const GenerationAuthority> authority_;
  wire::TrustedNegotiator control_;
  wire::TrustedNegotiator broker_;
  wire::TrustedNegotiator render_;
  wire::RequiredEndpointReadiness readiness_;
  ChannelFailure failure_ = ChannelFailure::none;
  std::string detail_;
  bool ready_ = false;
  launcher::TerminationState termination_;
};

} // namespace omarchy::plugin_runtime::channel
