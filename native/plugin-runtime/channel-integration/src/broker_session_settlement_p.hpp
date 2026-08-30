#pragma once
#include "structured_broker.hpp"
#include "authenticated_channel.hpp"

#include <array>
#include <memory>
#include <optional>

namespace omarchy::plugin_runtime::channel {

namespace broker_session = omarchy::plugin_runtime::host_session;
namespace gesture_runtime = omarchy::plugin_runtime::runtime;

enum class BrokerSettlementStatus : std::uint8_t {
  complete,
  would_block,
  fatal,
};

class BrokerReplyTransport {
public:
  virtual ~BrokerReplyTransport() = default;
  [[nodiscard]] virtual bool prepare(std::uint16_t message_type,
                                     std::uint64_t correlation,
                                     std::span<const std::byte> payload) = 0;
  [[nodiscard]] virtual ChannelSendStatus
  try_send(launcher::Deadline deadline) = 0;
  virtual void clear() noexcept = 0;
};

// Owns the one unsettled broker effect and its byte-identical, descriptor-free
// reply. This class is used only on the authenticated session worker thread.
class BrokerSessionSettlement final {
public:
  BrokerSessionSettlement(
      AuthenticatedBrokerChannel &channel,
      broker_session::StructuredBroker &broker,
      broker_session::AuthenticatedBrokerAdmission admission,
      gesture_runtime::GestureEligibilityAuthority *gesture_authority =
          nullptr);
#ifdef OMARCHY_BROKER_SETTLEMENT_TESTING
  BrokerSessionSettlement(
      std::unique_ptr<BrokerReplyTransport> transport,
      broker_session::StructuredBroker &broker,
      broker_session::AuthenticatedBrokerAdmission admission,
      gesture_runtime::GestureEligibilityAuthority *gesture_authority =
          nullptr) noexcept;
#endif
  ~BrokerSessionSettlement();
  BrokerSessionSettlement(const BrokerSessionSettlement &) = delete;
  BrokerSessionSettlement &operator=(const BrokerSessionSettlement &) = delete;

  [[nodiscard]] BrokerSettlementStatus dispatch(AuthenticatedMessage message,
                                                launcher::Deadline deadline);
  [[nodiscard]] BrokerSettlementStatus flush(launcher::Deadline deadline);
  [[nodiscard]] bool abort() noexcept;
  [[nodiscard]] bool pending() const noexcept;
  [[nodiscard]] bool failed() const noexcept;
  [[nodiscard]] launcher::EndpointMask read_lanes() const noexcept;
  [[nodiscard]] launcher::EndpointMask write_lanes() const noexcept;

private:
  [[nodiscard]] bool
  abort_transaction(broker_session::BrokerTransaction &&transaction) noexcept;

  std::unique_ptr<BrokerReplyTransport> transport_;
  broker_session::StructuredBroker &broker_;
  broker_session::AuthenticatedBrokerAdmission admission_;
  gesture_runtime::GestureEligibilityAuthority *gesture_authority_ = nullptr;
  std::optional<broker_session::BrokerTransaction> pending_;
  std::array<std::byte, broker_session::kMaximumOwnedBrokerReplyBytes>
      provider_response_{};
  bool failed_ = false;
  bool terminal_ = false;
};
} // namespace omarchy::plugin_runtime::channel
