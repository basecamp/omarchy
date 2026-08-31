#pragma once

#include "omarchy/plugin/wire/control.hpp"
#include "omarchy/plugin/wire/state.hpp"
#include "omarchy/plugin_runtime/launcher/launcher.h"
#include "omarchy/plugin_runtime/launcher/termination_state.h"

#include <array>
#include <chrono>
#include <cstdint>
#include <memory>
#include <optional>
#include <span>
#include <string>
#include <vector>

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
  deadline_expired,
};

enum class ChannelSendStatus : std::uint8_t {
  complete,
  would_block,
  peer_closed,
  fatal,
  not_ready,
};

enum class AuthenticatedReceiveStatus : std::uint8_t {
  message,
  would_block,
  peer_closed,
  fatal,
  not_ready,
};

struct AuthenticatedMessage final {
  wire::EndpointRole role = wire::EndpointRole::control;
  std::uint16_t message_type = 0;
  std::uint64_t correlation_id = 0;
  std::vector<std::byte> payload;
  std::vector<launcher::OwnedDescriptor> descriptors;

  AuthenticatedMessage() = default;
  AuthenticatedMessage(AuthenticatedMessage &&) noexcept = default;
  AuthenticatedMessage &operator=(AuthenticatedMessage &&) noexcept = default;
  AuthenticatedMessage(const AuthenticatedMessage &) = delete;
  AuthenticatedMessage &operator=(const AuthenticatedMessage &) = delete;
};

struct AuthenticatedReceiveResult final {
  AuthenticatedReceiveStatus status = AuthenticatedReceiveStatus::fatal;
  std::optional<AuthenticatedMessage> message;

  [[nodiscard]] explicit operator bool() const noexcept {
    return status == AuthenticatedReceiveStatus::message && message.has_value();
  }
};

// Owns the byte-identical v2 datagram produced for one lane. A would-block
// result leaves it intact for retry; every other result consumes it. Descriptor
// arguments remain borrowed by the caller until a retry completes.
class PreparedSend final {
public:
  PreparedSend(PreparedSend &&other) noexcept
      : role_(other.role_), bytes_(std::move(other.bytes_)),
        origin_(other.origin_), descriptor_count_(other.descriptor_count_),
        pending_(other.pending_) {
    other.origin_ = 0;
    other.pending_ = false;
  }
  PreparedSend &operator=(PreparedSend &&) = delete;
  PreparedSend(const PreparedSend &) = delete;
  PreparedSend &operator=(const PreparedSend &) = delete;

  [[nodiscard]] bool pending() const noexcept { return pending_; }
  [[nodiscard]] wire::EndpointRole role() const noexcept { return role_; }

private:
  PreparedSend(wire::EndpointRole role, std::vector<std::byte> bytes,
               std::uint64_t origin, std::uint8_t descriptor_count)
      : role_(role), bytes_(std::move(bytes)), origin_(origin),
        descriptor_count_(descriptor_count) {}

  wire::EndpointRole role_ = wire::EndpointRole::control;
  std::vector<std::byte> bytes_;
  std::uint64_t origin_ = 0;
  std::uint8_t descriptor_count_ = 0;
  bool pending_ = true;
  friend class AuthenticatedBrokerChannel;
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
       std::shared_ptr<const GenerationAuthority> authority,
       launcher::Deadline deadline);

  AuthenticatedBrokerChannel(const AuthenticatedBrokerChannel &) = delete;
  AuthenticatedBrokerChannel &
  operator=(const AuthenticatedBrokerChannel &) = delete;
  ~AuthenticatedBrokerChannel();

  [[nodiscard]] bool negotiate(launcher::Deadline deadline);
  [[nodiscard]] std::optional<PreparedSend>
  prepare_send(wire::EndpointRole role, std::uint16_t message_type,
               std::uint64_t correlation_id,
               std::span<const std::byte> payload);
  [[nodiscard]] ChannelSendStatus
  try_send(PreparedSend &prepared, launcher::Deadline deadline,
           std::span<const int> borrowed_descriptors = {});
  // Borrowed from Worker. Any notifier must be disarmed before fail(),
  // terminate(deadline), or destruction invalidates the descriptor.
  [[nodiscard]] int readiness_fd() const noexcept;
  [[nodiscard]] bool
  arm_readiness(launcher::EndpointMask read_lanes,
                launcher::EndpointMask blocked_write_lanes) noexcept;
  [[nodiscard]] AuthenticatedReceiveResult
  receive_authenticated(launcher::EndpointMask allowed_lanes,
                        launcher::Deadline deadline);
  [[nodiscard]] AuthenticatedReceiveResult
  try_receive_authenticated(launcher::EndpointMask allowed_lanes);
  [[nodiscard]] bool ready() const;
  [[nodiscard]] bool alive() const;
  [[nodiscard]] bool failed() const;
  [[nodiscard]] ChannelFailure failure() const;
  [[nodiscard]] const std::string &detail() const;
  [[nodiscard]] const launcher::LaunchIdentity &identity() const;
  [[nodiscard]] bool terminate(launcher::Deadline deadline) noexcept;

private:
  enum class ReceiveMode { blocking, nonblocking };
  AuthenticatedBrokerChannel(
      std::unique_ptr<launcher::Worker> worker,
      launcher::LaunchIdentity identity,
      std::shared_ptr<const GenerationAuthority> authority,
      launcher::Deadline opening_deadline);

  [[nodiscard]] bool negotiate_one(launcher::ReceivedMessage message,
                                   launcher::Deadline deadline);
  [[nodiscard]] launcher::ReceivedMessage
  receive_one(launcher::EndpointMask lanes, launcher::Deadline deadline);
  [[nodiscard]] bool validate_inbound(const launcher::ReceivedMessage &message,
                                      wire::PacketView &packet);
  [[nodiscard]] AuthenticatedReceiveResult
  receive_authenticated_impl(launcher::EndpointMask allowed_lanes,
                             launcher::Deadline deadline, ReceiveMode mode);
  [[nodiscard]] wire::TrustedNegotiator *negotiator(wire::EndpointRole role);
  bool fail(ChannelFailure failure, std::string detail);

  std::unique_ptr<launcher::Worker> worker_;
  launcher::LaunchIdentity identity_;
  std::shared_ptr<const GenerationAuthority> authority_;
  launcher::Deadline opening_deadline_;
  wire::TrustedNegotiator control_;
  wire::TrustedNegotiator broker_;
  wire::TrustedNegotiator render_;
  wire::RequiredEndpointReadiness readiness_;
  wire::SessionSequence sequence_;
  std::array<bool, 3> negotiated_{};
  launcher::EndpointMask armed_reads_ = launcher::EndpointMask::all;
  ChannelFailure failure_ = ChannelFailure::none;
  std::string detail_;
  bool ready_ = false;
  launcher::TerminationState termination_;
  std::uint64_t origin_ = 0;
};

} // namespace omarchy::plugin_runtime::channel
