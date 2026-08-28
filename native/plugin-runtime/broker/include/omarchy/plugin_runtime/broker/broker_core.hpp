#pragma once

#include "omarchy/plugin/wire/state.hpp"
#include "omarchy/plugin_runtime/broker/broker_codec.hpp"
#include "omarchy/plugin_runtime/broker/broker_schema.hpp"

#include <array>
#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <span>
#include <utility>

namespace omarchy::plugin_runtime::broker {

namespace wire = omarchy::plugin::wire;

enum class ProviderStatus : std::uint8_t { completed, pending, failed };

struct ProviderResult {
  ProviderStatus status = ProviderStatus::failed;
  std::size_t bytes_written = 0;
};

struct AuthorizedRequest {
  const permissions::ActivationBinding &binding;
  std::uint64_t correlation = 0;
  permissions::OperationId operation{};
  const permissions::Scope &demand;
  std::span<const std::byte> payload;
  std::uint64_t grant_epoch = 0;
};

using ProviderDispatch = ProviderResult (*)(const AuthorizedRequest &request,
                                            std::span<std::byte> response,
                                            void *context) noexcept;
using ProviderCancel = bool (*)(std::uint64_t correlation,
                                void *context) noexcept;

struct ProviderEntry {
  permissions::OperationId operation{};
  ProviderDispatch dispatch = nullptr;
  ProviderCancel cancel = nullptr;
  void *context = nullptr;
};

template <std::size_t Capacity> class ProviderRegistry {
public:
  [[nodiscard]] bool add(ProviderEntry entry) {
    const auto *definition = permissions::find_operation(entry.operation);
    if (entry.dispatch == nullptr || definition == nullptr ||
        (definition->revocation == permissions::RevocationMode::cancel_inflight &&
         entry.cancel == nullptr) ||
        find(entry.operation) != nullptr || size_ == Capacity) {
      return false;
    }
    entries_[size_++] = entry;
    return true;
  }

  [[nodiscard]] const ProviderEntry *
  find(permissions::OperationId operation) const {
    for (std::size_t index = 0; index < size_; ++index) {
      if (entries_[index].operation == operation) {
        return &entries_[index];
      }
    }
    return nullptr;
  }

private:
  std::array<ProviderEntry, Capacity> entries_{};
  std::size_t size_ = 0;
};

enum class DispatchOutcome : std::uint8_t {
  dispatched,
  pending,
  denied,
  malformed,
  provider_unavailable,
  provider_failed,
  protocol_fatal,
  core_failed,
  core_busy,
};

struct DispatchResult {
  DispatchOutcome outcome = DispatchOutcome::core_failed;
  omarchy::plugin::wire::FatalReason wire_error =
      omarchy::plugin::wire::FatalReason::none;
  permissions::GrantDecision decision{};
  std::size_t response_bytes = 0;
};

template <std::size_t Capacity> struct RevocationPlan {
  std::uint64_t new_epoch = 0;
  std::array<std::uint64_t, Capacity> cancel_correlations{};
  std::size_t cancel_count = 0;
  bool restart_worker = false;
  bool core_busy = false;
  bool core_failed = false;
  bool accepted = false;
};

enum class TerminalResult : std::uint8_t {
  accepted,
  core_failed,
  unknown_correlation,
  mismatched_operation,
  malformed_error,
  protocol_fatal,
  core_busy,
};

enum class CancelResult : std::uint8_t {
  accepted,
  provider_notified,
  unsupported,
  unknown,
  protocol_fatal,
  core_failed,
  core_busy,
};

template <std::size_t Capacity, std::size_t ProviderCapacity> class BrokerCore {
  static_assert(Capacity > 0);

public:
  BrokerCore(permissions::ActivationBinding binding,
             permissions::PermissionAuthority &authority,
             const ProviderRegistry<ProviderCapacity> &providers,
             std::size_t maximum_in_flight)
      : binding_(std::move(binding)), authority_(authority),
        providers_(providers),
        endpoint_(wire::EndpointRole::broker, kBrokerRoleVersion,
                  binding_.generation,
                  wire::payload_cap(wire::EndpointRole::broker),
                  maximum_in_flight, broker_schema_registry()) {}

  [[nodiscard]] DispatchResult
  dispatch(const wire::PacketView &packet, std::uint64_t now_monotonic_ns,
           std::span<std::byte> response = {},
           permissions::GestureProof *gesture = nullptr) {
    if (failed_) {
      return {.outcome = DispatchOutcome::core_failed};
    }
    if (dispatching_) {
      return {.outcome = DispatchOutcome::core_busy};
    }
    struct DispatchScope {
      bool &active;
      ~DispatchScope() { active = false; }
    } scope{dispatching_};
    dispatching_ = true;
    const auto session =
        endpoint_.accept(packet, wire::Direction::worker_to_host);
    if (!session || session.action != wire::SessionAction::request_admitted) {
      failed_ = true;
      return {.outcome = DispatchOutcome::protocol_fatal,
              .wire_error = session.error};
    }

    DecodedBrokerRequest request{};
    if (decode_broker_request(packet.header.message_type, packet.payload,
                              request) != BrokerDecodeResult::accepted) {
      failed_ = true;
      return {.outcome = DispatchOutcome::malformed};
    }
    auto *slot = reserve(packet.header.correlation_id, request.operation);
    if (slot == nullptr) {
      failed_ = true;
      return {.outcome = DispatchOutcome::core_failed};
    }

    auto decision = authority_.authorize(request.operation, request.demand,
                                         binding_, now_monotonic_ns, gesture);
    slot->capability = decision.capability;
    slot->grant_epoch = decision.grant_epoch;
    slot->decision = decision.code;
    if (!decision.allowed()) {
      return {.outcome = DispatchOutcome::denied, .decision = decision};
    }
    slot->authorized = true;
    const auto *provider = providers_.find(request.operation);
    if (provider == nullptr) {
      return {.outcome = DispatchOutcome::provider_unavailable,
              .decision = decision};
    }
    const AuthorizedRequest authorized{
        .binding = binding_,
        .correlation = packet.header.correlation_id,
        .operation = request.operation,
        .demand = request.demand,
        .payload = request.provider_payload,
        .grant_epoch = decision.grant_epoch,
    };
    const auto bounded_response = response.first(std::min<std::size_t>(
        response.size(), wire::payload_cap(wire::EndpointRole::broker)));
    const auto provider_result =
        provider->dispatch(authorized, bounded_response, provider->context);
    const bool known_status =
        provider_result.status == ProviderStatus::completed ||
        provider_result.status == ProviderStatus::pending ||
        provider_result.status == ProviderStatus::failed;
    if (!known_status || provider_result.status == ProviderStatus::failed ||
        provider_result.bytes_written > bounded_response.size() ||
        provider_result.bytes_written >
            wire::payload_cap(wire::EndpointRole::broker) ||
        (provider_result.status == ProviderStatus::pending &&
         provider_result.bytes_written != 0)) {
      return {.outcome = DispatchOutcome::provider_failed,
              .decision = decision};
    }
    slot->provider_active = provider_result.status == ProviderStatus::pending;
    return {.outcome = slot->provider_active ? DispatchOutcome::pending
                                             : DispatchOutcome::dispatched,
            .decision = decision,
            .response_bytes = provider_result.bytes_written};
  }

  [[nodiscard]] RevocationPlan<Capacity>
  revoke(const permissions::CapabilityKey &capability) {
    RevocationPlan<Capacity> plan;
    if (failed_) {
      plan.core_failed = true;
      return plan;
    }
    if (dispatching_) {
      plan.core_busy = true;
      return plan;
    }
    const auto *definition = permissions::find_capability(capability);
    if (definition == nullptr) {
      return plan;
    }
    bool revocable = false;
    for (const auto &grant : authority_.grants().values()) {
      if (grant.capability == capability &&
          grant.epoch < std::numeric_limits<std::uint64_t>::max()) {
        revocable = true;
        break;
      }
    }
    if (!revocable) {
      return plan;
    }
    plan.new_epoch = authority_.revoke(capability);
    plan.accepted = true;
    for (const auto &slot : pending_) {
      if (!slot.occupied || !slot.provider_active ||
          slot.capability != capability) {
        continue;
      }
      if (definition->revocation ==
          permissions::RevocationMode::restart_worker) {
        plan.restart_worker = true;
      } else if (definition->revocation ==
                 permissions::RevocationMode::cancel_inflight) {
        plan.cancel_correlations[plan.cancel_count++] = slot.correlation;
      }
    }
    return plan;
  }

  [[nodiscard]] CancelResult accept_cancel(const wire::PacketView &packet) {
    if (failed_) {
      return CancelResult::core_failed;
    }
    if (dispatching_) {
      return CancelResult::core_busy;
    }
    const auto session =
        endpoint_.accept(packet, wire::Direction::worker_to_host);
    if (!session) {
      failed_ = true;
      return CancelResult::protocol_fatal;
    }
    if (session.action == wire::SessionAction::cancel_unknown) {
      return CancelResult::unknown;
    }
    if (session.action != wire::SessionAction::cancel_requested) {
      failed_ = true;
      return CancelResult::protocol_fatal;
    }
    auto *slot = find(packet.header.correlation_id);
    if (slot == nullptr) {
      failed_ = true;
      return CancelResult::protocol_fatal;
    }
    slot->cancel_requested = true;
    if (slot->provider_cancel_notified) {
      return slot->provider_cancel_accepted ? CancelResult::provider_notified
                                            : CancelResult::unsupported;
    }
    const auto *provider = providers_.find(slot->operation);
    if (!slot->provider_active || provider == nullptr ||
        provider->cancel == nullptr) {
      return CancelResult::unsupported;
    }
    slot->provider_cancel_notified = true;
    struct CancelScope {
      bool &active;
      ~CancelScope() { active = false; }
    } scope{dispatching_};
    dispatching_ = true;
    slot->provider_cancel_accepted =
        provider->cancel(slot->correlation, provider->context);
    return slot->provider_cancel_accepted ? CancelResult::provider_notified
                                          : CancelResult::unsupported;
  }

  [[nodiscard]] CancelResult
  accept_cancel_result(const wire::PacketView &packet) {
    if (failed_) {
      return CancelResult::core_failed;
    }
    if (dispatching_) {
      return CancelResult::core_busy;
    }
    auto *slot = find(packet.header.correlation_id);
    const auto session =
        endpoint_.accept(packet, wire::Direction::host_to_worker);
    if (!session ||
        session.action != wire::SessionAction::cancel_result_received) {
      failed_ = true;
      return CancelResult::protocol_fatal;
    }
    if (slot == nullptr || !slot->cancel_requested) {
      failed_ = true;
      return CancelResult::protocol_fatal;
    }
    slot->cancel_acknowledged = true;
    if (slot->terminal_received) {
      erase(*slot);
    }
    return CancelResult::accepted;
  }

  [[nodiscard]] TerminalResult accept_terminal(const wire::PacketView &packet) {
    if (failed_) {
      return TerminalResult::core_failed;
    }
    if (dispatching_) {
      return TerminalResult::core_busy;
    }
    auto *slot = find(packet.header.correlation_id);
    bool semantic_valid = slot != nullptr;
    if (packet.header.message_type ==
        static_cast<std::uint16_t>(wire::CommonMessageType::typed_error)) {
      BrokerTypedError error{};
      if (!decode_broker_error(packet.payload, error)) {
        semantic_valid = false;
      }
      if (slot != nullptr && error.failed_operation != slot->operation) {
        semantic_valid = false;
      }
      const bool exact_denial = slot != nullptr && !slot->authorized &&
                                error.reason == BrokerErrorReason::denied &&
                                error.decision == slot->decision;
      const bool exact_operational_error =
          slot != nullptr && slot->authorized &&
          error.reason != BrokerErrorReason::denied &&
          error.decision == permissions::GrantDecisionCode::allowed;
      if (!exact_denial && !exact_operational_error) {
        semantic_valid = false;
      }
    } else if (packet.header.message_type != kBrokerResultMessage ||
               slot == nullptr || !slot->authorized) {
      semantic_valid = false;
    }
    const auto session =
        endpoint_.accept(packet, wire::Direction::host_to_worker);
    if (!session ||
        (session.action != wire::SessionAction::terminal_received &&
         session.action != wire::SessionAction::recoverable_error_received)) {
      failed_ = true;
      return TerminalResult::protocol_fatal;
    }
    if (!semantic_valid || slot == nullptr) {
      failed_ = true;
      return TerminalResult::mismatched_operation;
    }
    slot->provider_active = false;
    if (slot->cancel_requested && !slot->cancel_acknowledged) {
      slot->terminal_received = true;
    } else {
      erase(*slot);
    }
    return TerminalResult::accepted;
  }

  [[nodiscard]] bool failed() const { return failed_ || endpoint_.failed(); }
  [[nodiscard]] std::size_t in_flight() const { return in_flight_; }

private:
  struct Pending {
    std::uint64_t correlation = 0;
    permissions::OperationId operation{};
    permissions::CapabilityKey capability;
    std::uint64_t grant_epoch = 0;
    permissions::GrantDecisionCode decision =
        permissions::GrantDecisionCode::ungranted;
    bool authorized = false;
    bool provider_active = false;
    bool provider_cancel_notified = false;
    bool provider_cancel_accepted = false;
    bool cancel_requested = false;
    bool cancel_acknowledged = false;
    bool terminal_received = false;
    bool occupied = false;
  };

  [[nodiscard]] Pending *reserve(std::uint64_t correlation,
                                 permissions::OperationId operation) {
    if (correlation == 0 || find(correlation) != nullptr ||
        in_flight_ == Capacity) {
      return nullptr;
    }
    for (auto &slot : pending_) {
      if (!slot.occupied) {
        slot = {.correlation = correlation,
                .operation = operation,
                .capability = {},
                .grant_epoch = 0,
                .decision = permissions::GrantDecisionCode::ungranted,
                .authorized = false,
                .provider_active = false,
                .provider_cancel_notified = false,
                .provider_cancel_accepted = false,
                .cancel_requested = false,
                .cancel_acknowledged = false,
                .terminal_received = false,
                .occupied = true};
        ++in_flight_;
        return &slot;
      }
    }
    return nullptr;
  }

  [[nodiscard]] Pending *find(std::uint64_t correlation) {
    for (auto &slot : pending_) {
      if (slot.occupied && slot.correlation == correlation) {
        return &slot;
      }
    }
    return nullptr;
  }

  void erase(Pending &slot) {
    slot = {};
    --in_flight_;
  }

  permissions::ActivationBinding binding_;
  permissions::PermissionAuthority &authority_;
  ProviderRegistry<ProviderCapacity> providers_;
  wire::SelectedEndpointState<Capacity> endpoint_;
  std::array<Pending, Capacity> pending_{};
  std::size_t in_flight_ = 0;
  bool failed_ = false;
  bool dispatching_ = false;
};

} // namespace omarchy::plugin_runtime::broker
