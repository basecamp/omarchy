#include "broker_session_settlement_p.hpp"

#include <chrono>

namespace omarchy::plugin_runtime::channel {

namespace {
class ChannelBrokerReplyTransport final : public BrokerReplyTransport {
public:
  explicit ChannelBrokerReplyTransport(AuthenticatedBrokerChannel &channel)
      : channel_(channel) {}

  bool prepare(std::uint16_t message_type, std::uint64_t correlation,
               std::span<const std::byte> payload) override {
    if (prepared_)
      return false;
    auto prepared = channel_.prepare_send(wire::EndpointRole::broker,
                                          message_type, correlation, payload);
    if (!prepared)
      return false;
    prepared_.emplace(std::move(*prepared));
    return true;
  }

  ChannelSendStatus try_send(launcher::Deadline deadline) override {
    if (!prepared_)
      return ChannelSendStatus::fatal;
    const auto status = channel_.try_send(*prepared_, deadline);
    if (status != ChannelSendStatus::would_block)
      prepared_.reset();
    return status;
  }
  void clear() noexcept override { prepared_.reset(); }

private:
  AuthenticatedBrokerChannel &channel_;
  std::optional<PreparedSend> prepared_;
};
} // namespace

BrokerSessionSettlement::BrokerSessionSettlement(
    AuthenticatedBrokerChannel &channel,
    broker_session::StructuredBroker &broker,
    broker_session::AuthenticatedBrokerAdmission admission,
    gesture_runtime::GestureEligibilityAuthority *gesture_authority)
    : transport_(std::make_unique<ChannelBrokerReplyTransport>(channel)),
      broker_(broker), admission_(std::move(admission)),
      gesture_authority_(gesture_authority) {}

#ifdef OMARCHY_BROKER_SETTLEMENT_TESTING
BrokerSessionSettlement::BrokerSessionSettlement(
    std::unique_ptr<BrokerReplyTransport> transport,
    broker_session::StructuredBroker &broker,
    broker_session::AuthenticatedBrokerAdmission admission,
    gesture_runtime::GestureEligibilityAuthority *gesture_authority) noexcept
    : transport_(std::move(transport)), broker_(broker),
      admission_(std::move(admission)), gesture_authority_(gesture_authority) {
  if (!transport_) {
    failed_ = true;
    terminal_ = true;
  }
}
#endif

BrokerSessionSettlement::~BrokerSessionSettlement() { (void)abort(); }

BrokerSettlementStatus
BrokerSessionSettlement::dispatch(AuthenticatedMessage message,
                                  launcher::Deadline deadline) {
  if (pending_) {
    failed_ = true;
    (void)abort();
    return BrokerSettlementStatus::fatal;
  }
  if (terminal_ || failed_ || message.role != wire::EndpointRole::broker ||
      !message.descriptors.empty() ||
      std::chrono::steady_clock::now() >= deadline) {
    failed_ = true;
    terminal_ = true;
    return BrokerSettlementStatus::fatal;
  }
  auto admitted = admission_.admit({.message_type = message.message_type,
                                    .correlation_id = message.correlation_id,
                                    .payload = message.payload});
  if (!admitted) {
    failed_ = true;
    terminal_ = true;
    return BrokerSettlementStatus::fatal;
  }
  if (std::chrono::steady_clock::now() >= deadline) {
    failed_ = true;
    terminal_ = true;
    return BrokerSettlementStatus::fatal;
  }
  const auto now = std::chrono::duration_cast<std::chrono::nanoseconds>(
                       std::chrono::steady_clock::now().time_since_epoch())
                       .count();
  try {
    auto transaction =
        broker_.dispatch(std::move(*admitted.request),
                         static_cast<std::uint64_t>(now), provider_response_,
                         nullptr, gesture_authority_);
    if (transaction.state() != broker_session::TransactionState::reply) {
      failed_ = true;
      terminal_ = true;
      return BrokerSettlementStatus::fatal;
    }
    if (std::chrono::steady_clock::now() >= deadline) {
      (void)abort_transaction(std::move(transaction));
      failed_ = true;
      terminal_ = true;
      return BrokerSettlementStatus::fatal;
    }
    try {
      if (!transport_->prepare(transaction.message_type(),
                               transaction.correlation(),
                               transaction.wire_payload())) {
        (void)abort_transaction(std::move(transaction));
        failed_ = true;
        terminal_ = true;
        return BrokerSettlementStatus::fatal;
      }
      if (std::chrono::steady_clock::now() >= deadline) {
        transport_->clear();
        (void)abort_transaction(std::move(transaction));
        failed_ = true;
        terminal_ = true;
        return BrokerSettlementStatus::fatal;
      }
      pending_.emplace(std::move(transaction));
    } catch (...) {
      transport_->clear();
      (void)abort_transaction(std::move(transaction));
      failed_ = true;
      terminal_ = true;
      return BrokerSettlementStatus::fatal;
    }
    return flush(deadline);
  } catch (...) {
    failed_ = true;
    terminal_ = true;
    return BrokerSettlementStatus::fatal;
  }
}

BrokerSettlementStatus
BrokerSessionSettlement::flush(launcher::Deadline deadline) {
  if (terminal_ || failed_)
    return BrokerSettlementStatus::fatal;
  if (!pending_)
    return BrokerSettlementStatus::complete;
  if (std::chrono::steady_clock::now() >= deadline) {
    failed_ = true;
    (void)abort();
    return BrokerSettlementStatus::fatal;
  }
  ChannelSendStatus status = ChannelSendStatus::fatal;
  try {
    status = transport_->try_send(deadline);
  } catch (...) {
    failed_ = true;
    (void)abort();
    return BrokerSettlementStatus::fatal;
  }
  if (status == ChannelSendStatus::would_block) {
    if (std::chrono::steady_clock::now() >= deadline) {
      failed_ = true;
      (void)abort();
      return BrokerSettlementStatus::fatal;
    }
    return BrokerSettlementStatus::would_block;
  }
  if (status != ChannelSendStatus::complete) {
    failed_ = true;
    (void)abort();
    return BrokerSettlementStatus::fatal;
  }

  auto transaction = std::move(*pending_);
  pending_.reset();
  bool committed = false;
  try {
    committed = broker_.commit_sent(std::move(transaction));
  } catch (...) {
    committed = false;
  }
  const bool expired = std::chrono::steady_clock::now() >= deadline;
  if (!committed || expired) {
    failed_ = true;
    terminal_ = true;
    return BrokerSettlementStatus::fatal;
  }
  return BrokerSettlementStatus::complete;
}

bool BrokerSessionSettlement::abort_transaction(
    broker_session::BrokerTransaction &&transaction) noexcept {
  try {
    return broker_.abort_send(std::move(transaction));
  } catch (...) {
    return false;
  }
}

bool BrokerSessionSettlement::abort() noexcept {
  if (terminal_ && !pending_) {
    transport_->clear();
    return !failed_;
  }
  terminal_ = true;
  if (!pending_) {
    transport_->clear();
    return true;
  }
  auto transaction = std::move(*pending_);
  pending_.reset();
  transport_->clear();
  const bool aborted = abort_transaction(std::move(transaction));
  if (!aborted)
    failed_ = true;
  return aborted;
}

bool BrokerSessionSettlement::pending() const noexcept {
  return pending_.has_value();
}

bool BrokerSessionSettlement::failed() const noexcept { return failed_; }

launcher::EndpointMask BrokerSessionSettlement::read_lanes() const noexcept {
  if (terminal_ || failed_)
    return launcher::EndpointMask::none;
  return pending_
             ? launcher::EndpointMask::control | launcher::EndpointMask::render
             : launcher::EndpointMask::all;
}

launcher::EndpointMask BrokerSessionSettlement::write_lanes() const noexcept {
  if (terminal_ || failed_)
    return launcher::EndpointMask::none;
  return pending_ ? launcher::EndpointMask::broker
                  : launcher::EndpointMask::none;
}

} // namespace omarchy::plugin_runtime::channel
