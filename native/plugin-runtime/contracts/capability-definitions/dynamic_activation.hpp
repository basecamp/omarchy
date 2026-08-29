#pragma once

#include "capability_definition.hpp"

#include <array>
#include <cstddef>
#include <span>

namespace omarchy::plugins::definitions {

inline constexpr std::size_t kMaximumDynamicPayloadBytes = 32768;
inline constexpr std::size_t kMaximumDynamicEnvelopeBytes = 49152;

struct DynamicRevisionGrant {
  permissions::ActivationBinding binding;
  DynamicRequest request;
  DynamicGrant grant;
};

[[nodiscard]] bool review_dynamic_grant(
    const TrustedDefinitionRegistry &registry,
    const DynamicRevisionGrant &revision,
    const DynamicScopeValidator &validator);
[[nodiscard]] bool encode_dynamic_grant(
    const DynamicRevisionGrant &revision, std::span<std::byte> output,
    std::size_t &written);
[[nodiscard]] bool decode_dynamic_grant(std::span<const std::byte> input,
                                        DynamicRevisionGrant &output);

struct DynamicInvocation {
  CapabilityReference definition;
  Name operation;
  CanonicalScope demand_scope;
  std::span<const std::byte> payload;
};

[[nodiscard]] bool encode_dynamic_invocation(
    const DynamicInvocation &invocation, std::span<std::byte> output,
    std::size_t &written);
[[nodiscard]] bool decode_dynamic_invocation(
    std::span<const std::byte> input, DynamicInvocation &output);

struct DynamicAdapter {
  AdapterBinding binding;
  bool (*dispatch)(std::string_view operation, std::string_view demand_scope,
                   std::span<const std::byte> payload,
                   std::span<std::byte> response, std::size_t &written,
                   void *context) noexcept = nullptr;
  void *context = nullptr;
};

enum class DynamicDispatchResult : std::uint8_t {
  dispatched,
  malformed,
  stale_activation,
  denied,
  adapter_failed,
};

[[nodiscard]] DynamicDispatchResult dispatch_dynamic_invocation(
    const TrustedDefinitionRegistry &registry,
    const DynamicRevisionGrant &revision,
    const permissions::ActivationBinding &channel_binding,
    std::span<const std::byte> envelope, const DynamicAdapter &adapter,
    const DynamicScopeValidator &validator, bool fresh_gesture,
    std::span<std::byte> response, std::size_t &written,
    DynamicDecision &decision);

} // namespace omarchy::plugins::definitions
