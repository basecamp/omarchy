#pragma once

#include "omarchy/plugin/wire/envelope.hpp"

#include <cstddef>
#include <cstdint>
#include <span>

namespace omarchy::plugin::wire {

enum class CorrelationRule : std::uint8_t { zero, nonzero };

enum class MessageSemantic : std::uint8_t {
  request,
  terminal,
  event,
  one_way,
};

enum DirectionMask : std::uint8_t {
  worker_to_host = 1U << 0U,
  host_to_worker = 1U << 1U,
  bidirectional = worker_to_host | host_to_worker,
};

struct MessageRule {
  std::uint16_t message_type = 0;
  std::uint8_t directions = 0;
  CorrelationRule correlation = CorrelationRule::zero;
  MessageSemantic semantic = MessageSemantic::event;
  std::uint32_t minimum_payload = 0;
  std::uint32_t maximum_payload = 0;
};

struct RoleSchemaView {
  EndpointRole role = EndpointRole::control;
  std::uint16_t version = 0;
  std::span<const MessageRule> messages;
  std::uint32_t typed_error_minimum_payload = 0;
  std::uint32_t typed_error_maximum_payload = 0;
};

class RoleSchemaRegistryView {
public:
  constexpr explicit RoleSchemaRegistryView(
      std::span<const RoleSchemaView> schemas)
      : schemas_(schemas) {}

  [[nodiscard]] constexpr const RoleSchemaView *
  find(EndpointRole role, std::uint16_t version) const {
    for (const auto &schema : schemas_) {
      if (schema.role == role && schema.version == version) {
        return &schema;
      }
    }
    return nullptr;
  }

  [[nodiscard]] constexpr FatalReason validate() const {
    for (std::size_t index = 0; index < schemas_.size(); ++index) {
      const auto &schema = schemas_[index];
      if (schema.version == 0 ||
          schema.typed_error_minimum_payload >
              schema.typed_error_maximum_payload ||
          schema.typed_error_maximum_payload > payload_cap(schema.role)) {
        return FatalReason::invalid_role_schema;
      }
      for (std::size_t previous = 0; previous < index; ++previous) {
        if (schemas_[previous].role == schema.role &&
            schemas_[previous].version == schema.version) {
          return FatalReason::invalid_role_schema;
        }
      }
      for (std::size_t message = 0; message < schema.messages.size();
           ++message) {
        const auto &rule = schema.messages[message];
        if (rule.message_type < 0x0100 || rule.directions == 0 ||
            (rule.directions & ~DirectionMask::bidirectional) != 0 ||
            rule.minimum_payload > rule.maximum_payload ||
            rule.maximum_payload > payload_cap(schema.role)) {
          return FatalReason::invalid_role_schema;
        }
        for (std::size_t previous = 0; previous < message; ++previous) {
          if (schema.messages[previous].message_type == rule.message_type) {
            return FatalReason::invalid_role_schema;
          }
        }
      }
    }
    return FatalReason::none;
  }

private:
  std::span<const RoleSchemaView> schemas_;
};

[[nodiscard]] constexpr bool permits_direction(const MessageRule &rule,
                                               Direction direction) {
  const auto mask = direction == Direction::worker_to_host
                        ? DirectionMask::worker_to_host
                        : DirectionMask::host_to_worker;
  return (rule.directions & mask) != 0;
}

[[nodiscard]] constexpr const MessageRule *
find_message(const RoleSchemaView &schema, std::uint16_t message_type) {
  for (const auto &rule : schema.messages) {
    if (rule.message_type == message_type) {
      return &rule;
    }
  }
  return nullptr;
}

} // namespace omarchy::plugin::wire
