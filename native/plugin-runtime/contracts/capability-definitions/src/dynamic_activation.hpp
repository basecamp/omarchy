#pragma once

#include "capability_definition.hpp"

#include <array>
#include <cstddef>
#include <optional>
#include <span>
#include <type_traits>
#include <utility>

namespace omarchy::plugins::definitions {

inline constexpr std::size_t kMaximumDynamicPayloadBytes = 32768;
inline constexpr std::size_t kMaximumDynamicEnvelopeBytes = 49152;

struct DynamicRevisionGrant {
  permissions::ActivationBinding binding;
  DynamicRequest request;
  DynamicGrant grant;
};

[[nodiscard]] bool
review_dynamic_grant(const TrustedDefinitionRegistry &registry,
                     const DynamicRevisionGrant &revision,
                     const DynamicScopeValidator &validator);
[[nodiscard]] bool encode_dynamic_grant(const DynamicRevisionGrant &revision,
                                        std::span<std::byte> output,
                                        std::size_t &written);
[[nodiscard]] bool decode_dynamic_grant(std::span<const std::byte> input,
                                        DynamicRevisionGrant &output);

struct DynamicInvocation {
  struct GestureClaim {
    std::uint64_t surface_id = 0;
    std::uint64_t surface_generation = 0;
    std::uint64_t input_sequence = 0;
    bool operator==(const GestureClaim &) const = default;
  };
  CapabilityReference definition;
  Name operation;
  CanonicalScope demand_scope;
  std::optional<GestureClaim> gesture;
  std::span<const std::byte> payload;
};

[[nodiscard]] bool
encode_dynamic_invocation(const DynamicInvocation &invocation,
                          std::span<std::byte> output, std::size_t &written);
[[nodiscard]] bool decode_dynamic_invocation(std::span<const std::byte> input,
                                             DynamicInvocation &output);

struct DynamicAuthorizationContext {
  permissions::ActivationBinding binding;
  CapabilityReference definition;
  std::uint64_t grant_epoch = 0;
};

struct AuthorizedDynamicRequest {
  DynamicAuthorizationContext authorization;
  std::string_view operation;
  std::string_view demand_scope;
  std::span<const std::byte> payload;
};

using DynamicAdapterDispatch = bool (*)(const AuthorizedDynamicRequest &request,
                                        std::span<std::byte> response,
                                        std::size_t &written,
                                        void *context) noexcept;
static_assert(std::is_nothrow_invocable_r_v<
              bool, DynamicAdapterDispatch, const AuthorizedDynamicRequest &,
              std::span<std::byte>, std::size_t &, void *>);

struct DynamicAdapter {
  AdapterBinding binding;
  DynamicAdapterDispatch dispatch = nullptr;
  void *context = nullptr;
};

enum class DynamicPendingDecision : std::uint8_t {
  accepted,
  duplicate,
  table_full,
  unknown,
  stale_activation,
  stale_definition,
  stale_epoch,
  cancelled,
};

template <std::size_t Capacity> class DynamicPendingTable {
public:
  [[nodiscard]] DynamicPendingDecision
  begin(std::uint64_t correlation,
        const permissions::ActivationBinding &binding,
        const CapabilityReference &definition, std::uint64_t grant_epoch) {
    if (correlation == 0 || grant_epoch == 0)
      return DynamicPendingDecision::stale_epoch;
    for (const auto &entry : entries_) {
      if (entry.occupied && entry.correlation == correlation)
        return DynamicPendingDecision::duplicate;
    }
    for (auto &entry : entries_) {
      if (!entry.occupied) {
        entry = {.binding = binding,
                 .definition = definition,
                 .correlation = correlation,
                 .grant_epoch = grant_epoch,
                 .cancelled = false,
                 .occupied = true};
        return DynamicPendingDecision::accepted;
      }
    }
    return DynamicPendingDecision::table_full;
  }

  [[nodiscard]] DynamicPendingDecision
  complete(std::uint64_t correlation,
           const permissions::ActivationBinding &binding,
           const CapabilityReference &definition, std::uint64_t grant_epoch) {
    auto *entry = find(correlation);
    if (entry == nullptr)
      return DynamicPendingDecision::unknown;
    if (entry->binding != binding)
      return DynamicPendingDecision::stale_activation;
    if (entry->definition != definition)
      return DynamicPendingDecision::stale_definition;
    if (entry->grant_epoch != grant_epoch)
      return DynamicPendingDecision::stale_epoch;
    if (entry->cancelled)
      return DynamicPendingDecision::cancelled;
    *entry = {};
    return DynamicPendingDecision::accepted;
  }

  [[nodiscard]] std::size_t
  revoke(const CapabilityReference &definition, std::uint64_t old_epoch,
         std::span<std::uint64_t> cancelled_correlations) {
    std::size_t cancelled = 0;
    for (auto &entry : entries_) {
      if (!entry.occupied || entry.cancelled ||
          entry.definition != definition || entry.grant_epoch != old_epoch)
        continue;
      entry.cancelled = true;
      if (cancelled < cancelled_correlations.size())
        cancelled_correlations[cancelled] = entry.correlation;
      ++cancelled;
    }
    return cancelled;
  }

  [[nodiscard]] std::size_t
  invalidate_activation(const permissions::ActivationBinding &binding,
                        std::span<std::uint64_t> cancelled_correlations) {
    std::size_t cancelled = 0;
    for (auto &entry : entries_) {
      if (!entry.occupied || entry.cancelled || entry.binding == binding)
        continue;
      entry.cancelled = true;
      if (cancelled < cancelled_correlations.size())
        cancelled_correlations[cancelled] = entry.correlation;
      ++cancelled;
    }
    return cancelled;
  }

private:
  struct Entry {
    permissions::ActivationBinding binding;
    CapabilityReference definition;
    std::uint64_t correlation = 0;
    std::uint64_t grant_epoch = 0;
    bool cancelled = false;
    bool occupied = false;
  };

  [[nodiscard]] Entry *find(std::uint64_t correlation) {
    for (auto &entry : entries_) {
      if (entry.occupied && entry.correlation == correlation)
        return &entry;
    }
    return nullptr;
  }

  std::array<Entry, Capacity> entries_{};
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
