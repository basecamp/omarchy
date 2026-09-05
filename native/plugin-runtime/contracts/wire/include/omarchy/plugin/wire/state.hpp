#pragma once

#include "omarchy/plugin/wire/common.hpp"
#include "omarchy/plugin/wire/role_registry.hpp"

#include <array>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <span>

namespace omarchy::plugin::wire {

struct OutboundSequence {
  std::uint64_t value = 0;
  FatalReason error = FatalReason::none;

  [[nodiscard]] constexpr explicit operator bool() const {
    return error == FatalReason::none;
  }
};

// One instance belongs to one authenticated session. Each lane advances
// independently; the low two wire bits bind a value to its authenticated role.
// Gaps are valid, while zero, wrong-lane, equal, and lower values are fatal.
class SessionSequence final {
public:
  explicit constexpr SessionSequence(std::uint64_t first_outbound = 1)
      : next_outbound_{first_outbound, first_outbound, first_outbound},
        failed_(first_outbound == 0 || first_outbound > kMaximumCounter) {}
  SessionSequence(const SessionSequence &) = delete;
  SessionSequence &operator=(const SessionSequence &) = delete;
  SessionSequence(SessionSequence &&) = delete;
  SessionSequence &operator=(SessionSequence &&) = delete;

  [[nodiscard]] constexpr OutboundSequence
  take_outbound(EndpointRole role) {
    if (failed_)
      return {.error = FatalReason::invalid_message_order};
    const auto index = lane_index(role);
    if (index >= next_outbound_.size()) {
      failed_ = true;
      return {.error = FatalReason::invalid_lane_sequence};
    }
    if (outbound_exhausted_[index]) {
      failed_ = true;
      return {.error = FatalReason::lane_sequence_exhausted};
    }
    const auto counter = next_outbound_[index];
    if (counter == kMaximumCounter)
      outbound_exhausted_[index] = true;
    else
      ++next_outbound_[index];
    return {.value = (counter << 2U) | lane_tag(role)};
  }

  [[nodiscard]] constexpr FatalReason accept_inbound(EndpointRole role,
                                                     std::uint64_t value) {
    if (failed_)
      return FatalReason::invalid_message_order;
    const auto index = lane_index(role);
    const auto counter = value >> 2U;
    if (index >= inbound_high_water_.size() || value == 0 || counter == 0 ||
        (value & 0x3U) != lane_tag(role)) {
      failed_ = true;
      return FatalReason::invalid_lane_sequence;
    }
    if (counter <= inbound_high_water_[index]) {
      failed_ = true;
      return FatalReason::lane_sequence_replayed;
    }
    inbound_high_water_[index] = counter;
    return FatalReason::none;
  }

  [[nodiscard]] constexpr bool failed() const { return failed_; }
  [[nodiscard]] constexpr std::uint64_t
  inbound_high_water(EndpointRole role) const {
    const auto index = lane_index(role);
    return index < inbound_high_water_.size() ? inbound_high_water_[index] : 0;
  }

private:
  static constexpr std::uint64_t kMaximumCounter =
      std::numeric_limits<std::uint64_t>::max() >> 2U;

  [[nodiscard]] static constexpr std::uint64_t lane_tag(EndpointRole role) {
    return static_cast<std::uint16_t>(role) & 0x3U;
  }
  [[nodiscard]] static constexpr std::size_t lane_index(EndpointRole role) {
    const auto tag = static_cast<std::uint16_t>(role);
    return tag >= 1 && tag <= 3 ? tag - 1 : 3;
  }

  std::array<std::uint64_t, 3> next_outbound_{};
  std::array<std::uint64_t, 3> inbound_high_water_{};
  std::array<bool, 3> outbound_exhausted_{};
  bool failed_ = false;
};

enum class NegotiationKind : std::uint8_t { welcome, negotiation_failed };

struct NegotiationResult {
  NegotiationKind kind = NegotiationKind::negotiation_failed;
  EnvelopeHeader header{};
  std::array<std::byte, 8> payload{};
  std::size_t payload_size = 0;
  FatalReason error = FatalReason::none;

  [[nodiscard]] constexpr explicit operator bool() const {
    return error == FatalReason::none;
  }
};

class TrustedNegotiator {
public:
  constexpr TrustedNegotiator(EndpointRole role, VersionRange supported,
                              std::uint64_t authoritative_generation,
                              std::uint32_t maximum_payload,
                              std::uint32_t maximum_in_flight)
      : role_(role), supported_(supported),
        generation_(authoritative_generation),
        maximum_payload_(maximum_payload),
        maximum_in_flight_(maximum_in_flight) {}

  [[nodiscard]] NegotiationResult accept_hello(const PacketView &packet);
  [[nodiscard]] constexpr bool selected() const { return selected_; }
  [[nodiscard]] constexpr bool failed() const { return failed_; }
  [[nodiscard]] constexpr std::uint16_t selected_version() const {
    return selected_version_;
  }

private:
  EndpointRole role_;
  VersionRange supported_;
  std::uint64_t generation_;
  std::uint32_t maximum_payload_;
  std::uint32_t maximum_in_flight_;
  bool hello_seen_ = false;
  bool selected_ = false;
  bool failed_ = false;
  std::uint16_t selected_version_ = 0;
};

class WorkerNegotiator {
public:
  constexpr WorkerNegotiator(EndpointRole role, VersionRange supported)
      : role_(role), supported_(supported) {}

  struct HelloResult {
    EnvelopeHeader header{};
    std::array<std::byte, 4> payload{};
    FatalReason error = FatalReason::none;

    [[nodiscard]] constexpr explicit operator bool() const {
      return error == FatalReason::none;
    }
  };

  [[nodiscard]] HelloResult make_hello();
  [[nodiscard]] FatalReason accept_reply(const PacketView &packet);

  [[nodiscard]] constexpr bool selected() const { return selected_; }
  [[nodiscard]] constexpr bool failed() const { return failed_; }
  [[nodiscard]] constexpr std::uint16_t selected_version() const {
    return selected_version_;
  }
  [[nodiscard]] constexpr std::uint64_t launch_generation() const {
    return generation_;
  }
  [[nodiscard]] constexpr std::uint32_t maximum_payload() const {
    return maximum_payload_;
  }
  [[nodiscard]] constexpr std::uint32_t maximum_in_flight() const {
    return maximum_in_flight_;
  }

private:
  EndpointRole role_;
  VersionRange supported_;
  bool hello_sent_ = false;
  bool selected_ = false;
  bool failed_ = false;
  std::uint16_t selected_version_ = 0;
  std::uint64_t generation_ = 0;
  std::uint32_t maximum_payload_ = 0;
  std::uint32_t maximum_in_flight_ = 0;
};

class RequiredEndpointReadiness {
public:
  [[nodiscard]] FatalReason observe(EndpointRole role,
                                    std::uint64_t generation);
  [[nodiscard]] FatalReason ready(bool &output) const;

private:
  std::array<std::uint64_t, 3> generations_{};
};

enum class SessionAction : std::uint8_t {
  none,
  request_admitted,
  terminal_received,
  recoverable_error_received,
  cancel_requested,
  cancel_unknown,
  cancel_result_received,
  event_received,
  one_way_received,
};

struct SessionResult {
  SessionAction action = SessionAction::none;
  FatalReason error = FatalReason::none;

  [[nodiscard]] constexpr explicit operator bool() const {
    return error == FatalReason::none;
  }
};

template <std::size_t Capacity> class FixedOperationTable {
  static_assert(Capacity > 0);

public:
  struct Entry {
    std::uint64_t correlation = 0;
    bool occupied = false;
    bool cancel_requested = false;
    bool cancel_acknowledged = false;
    bool terminal_received = false;
  };

  [[nodiscard]] Entry *find(std::uint64_t correlation) {
    for (auto &entry : entries_) {
      if (entry.occupied && entry.correlation == correlation) {
        return &entry;
      }
    }
    return nullptr;
  }

  [[nodiscard]] const Entry *find(std::uint64_t correlation) const {
    for (const auto &entry : entries_) {
      if (entry.occupied && entry.correlation == correlation) {
        return &entry;
      }
    }
    return nullptr;
  }

  [[nodiscard]] FatalReason insert(std::uint64_t correlation,
                                   std::size_t negotiated_limit) {
    if (correlation == 0) {
      return FatalReason::invalid_correlation;
    }
    if (find(correlation) != nullptr) {
      return FatalReason::correlation_reused;
    }
    if (size_ >= negotiated_limit || size_ >= Capacity) {
      return FatalReason::maximum_in_flight_exceeded;
    }
    for (auto &entry : entries_) {
      if (!entry.occupied) {
        entry = Entry{.correlation = correlation, .occupied = true};
        ++size_;
        return FatalReason::none;
      }
    }
    return FatalReason::maximum_in_flight_exceeded;
  }

  void erase(Entry &entry) {
    entry = Entry{};
    --size_;
  }

  [[nodiscard]] constexpr std::size_t size() const { return size_; }

private:
  std::array<Entry, Capacity> entries_{};
  std::size_t size_ = 0;
};

template <std::size_t Capacity> class SelectedEndpointState {
public:
  constexpr SelectedEndpointState(EndpointRole role, std::uint16_t role_version,
                                  std::uint64_t generation,
                                  std::size_t maximum_payload,
                                  std::size_t maximum_in_flight,
                                  const RoleSchemaRegistryView &registry)
      : role_(role), role_version_(role_version), generation_(generation),
        maximum_payload_(maximum_payload),
        maximum_in_flight_(maximum_in_flight), registry_(registry) {
    if (role_version == 0 || generation == 0 || maximum_payload == 0 ||
        maximum_payload > payload_cap(role) || maximum_in_flight == 0 ||
        maximum_in_flight > Capacity ||
        registry.validate() != FatalReason::none ||
        registry.find(role, role_version) == nullptr) {
      configuration_error_ = FatalReason::invalid_role_schema;
    }
  }

  [[nodiscard]] SessionResult accept(const PacketView &packet,
                                     Direction direction) {
    if (failed_) {
      return fail(FatalReason::invalid_message_order);
    }
    if (direction != Direction::worker_to_host &&
        direction != Direction::host_to_worker) {
      return fail(FatalReason::invalid_direction);
    }
    if (configuration_error_ != FatalReason::none) {
      return fail(configuration_error_);
    }
    if (packet.header.endpoint_role != role_) {
      return fail(FatalReason::endpoint_role_mismatch);
    }
    if (packet.header.role_protocol_version != role_version_) {
      return fail(FatalReason::unsupported_role_version);
    }
    if (generation_ == 0 || packet.header.launch_generation != generation_) {
      return fail(FatalReason::stale_generation);
    }
    if (packet.payload.size() > maximum_payload_) {
      return fail(FatalReason::payload_cap_exceeded);
    }

    const auto type = packet.header.message_type;
    if (type == static_cast<std::uint16_t>(CommonMessageType::cancel)) {
      if (!packet.payload.empty() || packet.header.correlation_id == 0) {
        return fail(FatalReason::invalid_correlation);
      }
      auto *entry = operations(direction).find(packet.header.correlation_id);
      if (entry == nullptr) {
        return {SessionAction::cancel_unknown, FatalReason::none};
      }
      entry->cancel_requested = true;
      return {SessionAction::cancel_requested, FatalReason::none};
    }
    if (type == static_cast<std::uint16_t>(CommonMessageType::cancel_result)) {
      CancelOutcome outcome{};
      if (packet.header.correlation_id == 0 ||
          !decode_cancel_result_payload(packet.payload, outcome)) {
        return fail(FatalReason::invalid_common_payload);
      }
      auto &initiated = operations(opposite(direction));
      auto *entry = initiated.find(packet.header.correlation_id);
      if (entry == nullptr || !entry->cancel_requested) {
        return fail(FatalReason::unmatched_cancel_result);
      }
      if (entry->cancel_acknowledged) {
        return fail(FatalReason::duplicate_cancel_result);
      }
      entry->cancel_acknowledged = true;
      if (entry->terminal_received) {
        initiated.erase(*entry);
      }
      return {SessionAction::cancel_result_received, FatalReason::none};
    }
    if (type == static_cast<std::uint16_t>(CommonMessageType::typed_error)) {
      const auto *schema = registry_.find(role_, role_version_);
      if (schema == nullptr ||
          packet.payload.size() < schema->typed_error_minimum_payload ||
          packet.payload.size() > schema->typed_error_maximum_payload) {
        return fail(FatalReason::invalid_common_payload);
      }
      return accept_terminal(packet.header.correlation_id, direction,
                             SessionAction::recoverable_error_received);
    }
    if (type < 0x0100) {
      return fail(FatalReason::invalid_message_order);
    }

    const auto *schema = registry_.find(role_, role_version_);
    if (schema == nullptr) {
      return fail(FatalReason::unsupported_role_version);
    }
    const auto *rule = find_message(*schema, type);
    if (rule == nullptr) {
      return fail(FatalReason::unknown_message_type);
    }
    if (!permits_direction(*rule, direction)) {
      return fail(FatalReason::invalid_direction);
    }
    if (packet.payload.size() < rule->minimum_payload ||
        packet.payload.size() > rule->maximum_payload) {
      return fail(FatalReason::invalid_common_payload);
    }
    const bool correlation_valid = rule->correlation == CorrelationRule::zero
                                       ? packet.header.correlation_id == 0
                                       : packet.header.correlation_id != 0;
    if (!correlation_valid) {
      return fail(FatalReason::invalid_correlation);
    }

    switch (rule->semantic) {
    case MessageSemantic::request: {
      const auto error = operations(direction).insert(
          packet.header.correlation_id, maximum_in_flight_);
      if (error != FatalReason::none) {
        return fail(error);
      }
      return {SessionAction::request_admitted, FatalReason::none};
    }
    case MessageSemantic::terminal:
      return accept_terminal(packet.header.correlation_id, direction,
                             SessionAction::terminal_received);
    case MessageSemantic::event:
      return {SessionAction::event_received, FatalReason::none};
    case MessageSemantic::one_way:
      return {SessionAction::one_way_received, FatalReason::none};
    }
    return fail(FatalReason::invalid_role_schema);
  }

  [[nodiscard]] constexpr bool failed() const { return failed_; }

private:
  [[nodiscard]] FixedOperationTable<Capacity> &operations(Direction direction) {
    return direction == Direction::worker_to_host ? worker_operations_
                                                  : host_operations_;
  }

  [[nodiscard]] SessionResult accept_terminal(std::uint64_t correlation,
                                              Direction direction,
                                              SessionAction action) {
    if (correlation == 0) {
      return fail(FatalReason::invalid_correlation);
    }
    auto &initiated = operations(opposite(direction));
    auto *entry = initiated.find(correlation);
    if (entry == nullptr) {
      return fail(FatalReason::unmatched_terminal);
    }
    if (entry->terminal_received) {
      return fail(FatalReason::duplicate_terminal);
    }
    if (entry->cancel_requested && !entry->cancel_acknowledged) {
      entry->terminal_received = true;
    } else {
      initiated.erase(*entry);
    }
    return {action, FatalReason::none};
  }

  [[nodiscard]] SessionResult fail(FatalReason error) {
    failed_ = true;
    return {SessionAction::none, error};
  }

  EndpointRole role_;
  std::uint16_t role_version_;
  std::uint64_t generation_;
  std::size_t maximum_payload_;
  std::size_t maximum_in_flight_;
  const RoleSchemaRegistryView &registry_;
  FixedOperationTable<Capacity> worker_operations_;
  FixedOperationTable<Capacity> host_operations_;
  bool failed_ = false;
  FatalReason configuration_error_ = FatalReason::none;
};

} // namespace omarchy::plugin::wire
