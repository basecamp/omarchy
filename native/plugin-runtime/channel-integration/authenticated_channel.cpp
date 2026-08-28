#include "authenticated_channel.hpp"

#include "omarchy/plugin_runtime/broker/broker_schema.hpp"
#include "omarchy/plugin_runtime/surface/render_messages.hpp"

#include <unistd.h>

#include <algorithm>
#include <array>
#include <chrono>
#include <span>
#include <utility>
#include <vector>

namespace omarchy::plugin_runtime::channel {
namespace {

constexpr std::uint16_t kControlRoleVersion = 1;
constexpr std::uint32_t kMaximumInFlight = 32;
constexpr auto kMaximumNegotiationWait = std::chrono::seconds(30);

launcher::EndpointRole launcher_role(wire::EndpointRole role) {
  switch (role) {
  case wire::EndpointRole::control:
    return launcher::EndpointRole::control;
  case wire::EndpointRole::broker:
    return launcher::EndpointRole::broker;
  case wire::EndpointRole::render:
    return launcher::EndpointRole::render;
  }
  return launcher::EndpointRole::control;
}

std::uint16_t role_version(wire::EndpointRole role) {
  switch (role) {
  case wire::EndpointRole::control:
    return kControlRoleVersion;
  case wire::EndpointRole::broker:
    return broker::kBrokerRoleVersion;
  case wire::EndpointRole::render:
    return surface::kRenderRoleVersion;
  }
  return 0;
}

std::chrono::milliseconds
remaining(std::chrono::steady_clock::time_point deadline) {
  const auto now = std::chrono::steady_clock::now();
  if (now >= deadline)
    return std::chrono::milliseconds(0);
  return std::max(
      std::chrono::milliseconds(1),
      std::chrono::duration_cast<std::chrono::milliseconds>(deadline - now));
}

} // namespace

AuthenticatedBrokerChannel::AuthenticatedBrokerChannel(
    std::unique_ptr<launcher::Worker> worker, launcher::LaunchIdentity identity,
    std::shared_ptr<BrokerDispatcher> dispatcher,
    std::shared_ptr<const GenerationAuthority> authority)
    : worker_(std::move(worker)), identity_(std::move(identity)),
      dispatcher_(std::move(dispatcher)), authority_(std::move(authority)),
      control_(wire::EndpointRole::control,
               {kControlRoleVersion, kControlRoleVersion}, identity_.generation,
               wire::payload_cap(wire::EndpointRole::control),
               kMaximumInFlight),
      broker_(wire::EndpointRole::broker,
              {broker::kBrokerRoleVersion, broker::kBrokerRoleVersion},
              identity_.generation,
              wire::payload_cap(wire::EndpointRole::broker), kMaximumInFlight),
      render_(wire::EndpointRole::render,
              {surface::kRenderRoleVersion, surface::kRenderRoleVersion},
              identity_.generation,
              wire::payload_cap(wire::EndpointRole::render), kMaximumInFlight) {
}

AuthenticatedBrokerChannel::~AuthenticatedBrokerChannel() {
  if (worker_ != nullptr && !termination_.attempted())
    (void)worker_->terminate();
}

OpenResult AuthenticatedBrokerChannel::open(
    launcher::Supervisor &supervisor,
    const launcher::TrustedLaunchRequest &request,
    std::shared_ptr<BrokerDispatcher> dispatcher,
    std::shared_ptr<const GenerationAuthority> authority) {
  if (dispatcher == nullptr || authority == nullptr)
    return {.channel = nullptr,
            .failure = ChannelFailure::identity_mismatch,
            .launch_failure = launcher::LaunchFailure::none,
            .detail = "broker dispatcher or generation authority is absent"};
  auto launched = supervisor.launch(request);
  if (!launched)
    return {.channel = nullptr,
            .failure = ChannelFailure::launch_failed,
            .launch_failure = launched.failure,
            .detail = std::move(launched.detail)};
  const auto &identity = launched.worker->identity();
  if (identity.plugin_id != request.plugin_id ||
      identity.revision_sha256 != request.revision_sha256 ||
      identity.generation != request.generation ||
      identity.outer_worker_pid <= 0 || identity.outer_uid != getuid() ||
      identity.outer_gid != getgid() || !launched.worker->alive()) {
    (void)launched.worker->terminate();
    return {.channel = nullptr,
            .failure = ChannelFailure::identity_mismatch,
            .launch_failure = launcher::LaunchFailure::none,
            .detail = "launched process identity differs from trusted request"};
  }
  if (!dispatcher->accepts(identity)) {
    (void)launched.worker->terminate();
    return {.channel = nullptr,
            .failure = ChannelFailure::identity_mismatch,
            .launch_failure = launcher::LaunchFailure::none,
            .detail = "broker dispatcher rejects the launched identity"};
  }
  if (!authority->is_current(identity)) {
    (void)launched.worker->terminate();
    return {.channel = nullptr,
            .failure = ChannelFailure::stale_generation,
            .launch_failure = launcher::LaunchFailure::none,
            .detail = "launched generation is no longer authoritative"};
  }
  auto channel = std::unique_ptr<AuthenticatedBrokerChannel>(
      new AuthenticatedBrokerChannel(std::move(launched.worker), identity,
                                     std::move(dispatcher),
                                     std::move(authority)));
  return {.channel = std::move(channel),
          .failure = ChannelFailure::none,
          .launch_failure = launcher::LaunchFailure::none,
          .detail = {}};
}

bool AuthenticatedBrokerChannel::negotiate(std::chrono::milliseconds timeout) {
  if (failed() || ready_ || timeout.count() <= 0 ||
      timeout > kMaximumNegotiationWait)
    return fail(ChannelFailure::negotiation_failed,
                "invalid or repeated channel negotiation");
  const auto deadline = std::chrono::steady_clock::now() + timeout;
  for (const auto role :
       {wire::EndpointRole::control, wire::EndpointRole::broker,
        wire::EndpointRole::render}) {
    if (!negotiate_role(role, remaining(deadline)))
      return false;
  }
  bool aggregate_ready = false;
  if (!authority_->is_current(identity_))
    return fail(ChannelFailure::stale_generation,
                "launch generation changed during endpoint negotiation");
  if (readiness_.ready(aggregate_ready) != wire::FatalReason::none ||
      !aggregate_ready || !worker_->alive())
    return fail(ChannelFailure::readiness_failed,
                "required endpoint generations are not jointly ready");
  ready_ = true;
  return true;
}

bool AuthenticatedBrokerChannel::negotiate_role(
    wire::EndpointRole role, std::chrono::milliseconds timeout) {
  auto message =
      worker_->receive(launcher_role(role), wire::kHeaderSize + 4, timeout);
  if (!message)
    return fail(ChannelFailure::peer_failure,
                "authenticated endpoint HELLO receive failed");
  const auto decoded = wire::decode_packet(message.payload, role);
  if (!decoded)
    return fail(ChannelFailure::malformed_envelope,
                "endpoint HELLO envelope is malformed");
  wire::TrustedNegotiator *negotiator = nullptr;
  switch (role) {
  case wire::EndpointRole::control:
    negotiator = &control_;
    break;
  case wire::EndpointRole::broker:
    negotiator = &broker_;
    break;
  case wire::EndpointRole::render:
    negotiator = &render_;
    break;
  }
  const auto negotiated = negotiator->accept_hello(decoded.packet);
  if (!negotiated)
    return fail(ChannelFailure::negotiation_failed,
                "endpoint HELLO negotiation failed");
  std::array<std::byte, wire::kHeaderSize + 8> encoded{};
  const auto payload =
      std::span(negotiated.payload).first(negotiated.payload_size);
  auto header = negotiated.header;
  header.payload_length = static_cast<std::uint32_t>(payload.size());
  const auto result = wire::encode_packet(header, payload, encoded);
  if (!result || !worker_->send(launcher_role(role),
                                std::span(encoded).first(result.bytes_written)))
    return fail(ChannelFailure::peer_failure,
                "endpoint negotiation reply send failed");
  if (negotiated.kind != wire::NegotiationKind::welcome)
    return fail(ChannelFailure::negotiation_failed,
                "endpoint has no supported role version");
  if (negotiator->selected_version() != role_version(role) ||
      readiness_.observe(role, identity_.generation) != wire::FatalReason::none)
    return fail(ChannelFailure::readiness_failed,
                "endpoint selected unexpected version or generation");
  return true;
}

DispatchStatus
AuthenticatedBrokerChannel::dispatch_one(std::chrono::milliseconds timeout) {
  if (!ready_ || failed() || termination_.attempted()) {
    if (!failed() && !termination_.attempted())
      fail(ChannelFailure::not_ready,
           "broker dispatch attempted before aggregate readiness");
    return DispatchStatus::not_ready;
  }
  if (!worker_->alive()) {
    fail(ChannelFailure::peer_failure,
         "pidfd reports worker exit before broker dispatch");
    return DispatchStatus::fatal;
  }
  if (!authority_->is_current(identity_)) {
    fail(ChannelFailure::stale_generation,
         "launch generation changed before broker receive");
    return DispatchStatus::fatal;
  }
  auto message = worker_->receive(
      launcher::EndpointRole::broker,
      wire::kHeaderSize + wire::payload_cap(wire::EndpointRole::broker),
      timeout);
  if (!message) {
    if (message.failure == launcher::ReceiveFailure::timeout)
      return DispatchStatus::timeout;
    fail(ChannelFailure::peer_failure,
         "authenticated broker endpoint receive failed");
    return DispatchStatus::fatal;
  }
  const auto decoded =
      wire::decode_packet(message.payload, wire::EndpointRole::broker);
  if (!decoded) {
    fail(ChannelFailure::malformed_envelope,
         "broker envelope failed outer validation");
    return DispatchStatus::fatal;
  }
  if (decoded.packet.header.role_protocol_version !=
      broker::kBrokerRoleVersion) {
    fail(ChannelFailure::role_version_mismatch,
         "broker role protocol version differs from negotiation");
    return DispatchStatus::fatal;
  }
  if (decoded.packet.header.launch_generation != identity_.generation) {
    fail(ChannelFailure::stale_generation,
         "broker packet generation differs from launch identity");
    return DispatchStatus::fatal;
  }
  if (!worker_->alive()) {
    fail(ChannelFailure::peer_failure,
         "pidfd reports worker exit before trusted dispatch");
    return DispatchStatus::fatal;
  }
  if (!authority_->is_current(identity_)) {
    fail(ChannelFailure::stale_generation,
         "launch generation changed before trusted dispatch");
    return DispatchStatus::fatal;
  }
  bool dispatched = false;
  try {
    dispatched = dispatcher_->dispatch(decoded.packet);
  } catch (...) {
    fail(ChannelFailure::dispatch_failed,
         "C4 broker dispatcher raised across the channel boundary");
    return DispatchStatus::fatal;
  }
  if (!dispatched) {
    fail(ChannelFailure::dispatch_failed,
         "C4 broker dispatcher rejected the authenticated packet");
    return DispatchStatus::fatal;
  }
  return DispatchStatus::dispatched;
}

bool AuthenticatedBrokerChannel::ready() const { return ready_ && !failed(); }
bool AuthenticatedBrokerChannel::alive() const {
  return worker_ != nullptr && !failed() && !termination_.attempted() &&
         worker_->alive();
}
bool AuthenticatedBrokerChannel::failed() const {
  return failure_ != ChannelFailure::none;
}
ChannelFailure AuthenticatedBrokerChannel::failure() const { return failure_; }
const std::string &AuthenticatedBrokerChannel::detail() const {
  return detail_;
}
const launcher::LaunchIdentity &AuthenticatedBrokerChannel::identity() const {
  return identity_;
}

bool AuthenticatedBrokerChannel::terminate() {
  if (!termination_.begin())
    return termination_.succeeded();
  ready_ = false;
  termination_.complete(worker_ == nullptr || worker_->terminate());
  return termination_.succeeded();
}

bool AuthenticatedBrokerChannel::fail(ChannelFailure failure,
                                      std::string detail) {
  if (!failed()) {
    failure_ = failure;
    detail_ = std::move(detail);
  }
  ready_ = false;
  (void)terminate();
  return false;
}

} // namespace omarchy::plugin_runtime::channel
