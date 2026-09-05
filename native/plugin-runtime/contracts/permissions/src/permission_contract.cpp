#include "permission_contract.hpp"

#include "canonical_identity_encoding.hpp"

#include <limits>

namespace omarchy::plugins::permissions {
namespace {

using detail::require;

template <std::size_t Size>
bool nonzero(const std::array<std::byte, Size> &bytes) {
  return std::any_of(bytes.begin(), bytes.end(),
                     [](std::byte value) { return value != std::byte{0}; });
}

bool demand_matches_operation(const Scope &scope, OperationId operation) {
  const auto *resources = std::get_if<ResourceScope>(&scope);
  return resources == nullptr || (resources->operations.size() == 1 &&
                                  resources->operations.contains(operation));
}

const CapabilityRequest *request_for(const RequestSet &requests,
                                     const CapabilityKey &key) {
  const auto found = std::find_if(
      requests.values().begin(), requests.values().end(),
      [&key](const auto &request) { return request.capability == key; });
  return found == requests.values().end() ? nullptr : &*found;
}

const GrantRecord *grant_for(const GrantSet &grants, const CapabilityKey &key) {
  const auto found = std::find_if(
      grants.values().begin(), grants.values().end(),
      [&key](const auto &grant) { return grant.capability == key; });
  return found == grants.values().end() ? nullptr : &*found;
}

void validate_grants(const GrantSet &grants, const RequestSet *requests) {
  FixedSet<CapabilityKey, 64> seen;
  for (const auto &grant : grants.values()) {
    require(seen.insert(grant.capability), "duplicate grant");
    require(static_cast<std::uint8_t>(grant.state) <=
                static_cast<std::uint8_t>(GrantState::revoked),
            "invalid grant state");
    const auto *definition = find_capability(grant.capability);
    require(definition != nullptr && valid_scope(*definition, grant.scope) &&
                grant.epoch > 0,
            "invalid grant");
    if (requests == nullptr)
      continue;
    const auto *request = request_for(*requests, grant.capability);
    require(request != nullptr, "grant is not declared by policy");
    const auto relation = compare_scope(grant.scope, request->scope);
    require(relation == ScopeRelation::equal ||
                relation == ScopeRelation::narrower,
            "grant expands policy request");
  }
}

GrantRecord *grant_for(GrantSet &grants, const CapabilityKey &key) {
  const auto found = std::find_if(
      grants.values().begin(), grants.values().end(),
      [&key](const auto &grant) { return grant.capability == key; });
  return found == grants.values().end() ? nullptr : &*found;
}

} // namespace

using detail::append_text;
using detail::append_u16;
using detail::append_u64;
using detail::append_u8;
using detail::canonical_digest;
using detail::canonical_id;
using detail::domain;
using detail::fingerprint;
using detail::require;

void validate_grants(const GrantSet &grants, const RequestSet &requests) {
  validate_grants(grants, &requests);
}

std::string policy_request_fingerprint(const RequestSet &input) {
  validate_requests(input);
  std::array<const CapabilityRequest *, 64> sorted{};
  for (std::size_t index = 0; index < input.size(); ++index)
    sorted[index] = &input[index];
  std::sort(sorted.begin(), sorted.begin() + input.size(),
            [](auto left, auto right) {
              return left->capability < right->capability;
            });
  std::string bytes = domain("OMARCHY-PLUGIN-POLICY-REQUESTS-V1\0");
  append_u16(bytes, static_cast<std::uint16_t>(input.size()));
  for (std::size_t index = 0; index < input.size(); ++index) {
    const auto &request = *sorted[index];
    append_text(bytes, request.capability.id.view());
    append_u16(bytes, request.capability.version);
    append_u8(bytes, request.required ? 1 : 0);
    append_text(bytes, canonical_scope(request.scope));
  }
  return fingerprint(std::move(bytes));
}

void validate_decision(const UserDecisionRecord &decision) {
  require(decision.sequence > 0 && canonical_id(decision.plugin.view()) &&
              canonical_digest(decision.revision) &&
              canonical_digest(decision.source_request_fingerprint) &&
              canonical_digest(decision.policy_request_fingerprint),
          "invalid user decision identity");
  require(static_cast<std::uint8_t>(decision.decision) <=
                  static_cast<std::uint8_t>(UserDecision::deny) &&
              static_cast<std::uint8_t>(decision.actor) <=
                  static_cast<std::uint8_t>(DecisionActor::reviewed_policy) &&
              decision.decided_wall_seconds > 0,
          "invalid user decision enumeration");
  const auto *definition = find_capability(decision.capability);
  require(definition != nullptr &&
              valid_scope(*definition, decision.requested_scope),
          "invalid requested decision scope");
  require(valid_scope(*definition, decision.decided_scope),
          "invalid decided scope");
  if (decision.decision == UserDecision::grant) {
    const auto relation =
        compare_scope(decision.decided_scope, decision.requested_scope);
    require(relation == ScopeRelation::equal ||
                relation == ScopeRelation::narrower,
            "user decision expands requested scope");
  } else {
    require(compare_scope(decision.decided_scope, decision.requested_scope) ==
                ScopeRelation::equal,
            "denial must preserve the requested scope");
  }
}

std::string grant_fingerprint(const PluginId &plugin, const Digest &revision,
                              const Digest &policy_fingerprint,
                              const GrantSet &grants) {
  require(canonical_id(plugin.view()) && canonical_digest(revision) &&
              canonical_digest(policy_fingerprint),
          "invalid grant fingerprint identity");
  std::array<const GrantRecord *, 64> sorted{};
  validate_grants(grants, nullptr);
  for (std::size_t index = 0; index < grants.size(); ++index) {
    sorted[index] = &grants[index];
  }
  std::sort(sorted.begin(), sorted.begin() + grants.size(),
            [](auto left, auto right) {
              return left->capability < right->capability;
            });
  std::string bytes = domain("OMARCHY-PLUGIN-GRANTS-V1\0");
  append_text(bytes, plugin.view());
  append_text(bytes, revision.view());
  append_text(bytes, policy_fingerprint.view());
  append_u16(bytes, static_cast<std::uint16_t>(grants.size()));
  for (std::size_t index = 0; index < grants.size(); ++index) {
    const auto &grant = *sorted[index];
    append_text(bytes, grant.capability.id.view());
    append_u16(bytes, grant.capability.version);
    append_u8(bytes, static_cast<std::uint8_t>(grant.state));
    append_u64(bytes, grant.epoch);
    append_text(bytes, canonical_scope(grant.scope));
  }
  return fingerprint(std::move(bytes));
}

DeltaSet compute_update_delta(const RequestSet &old_requests,
                              const GrantSet &old_grants,
                              const RequestSet &new_requests) {
  validate_requests(old_requests);
  validate_requests(new_requests);
  validate_grants(old_grants, &old_requests);
  DeltaSet result;
  for (const auto &next : new_requests.values()) {
    PermissionDelta delta{.capability = next.capability,
                          .kind = DeltaKind::unchanged,
                          .inherited_grant = std::nullopt};
    const auto *previous = request_for(old_requests, next.capability);
    const auto *grant = grant_for(old_grants, next.capability);
    if (previous == nullptr) {
      delta.kind = DeltaKind::added;
    } else if (previous->required != next.required) {
      delta.kind = DeltaKind::requirement_changed;
    } else {
      const auto relation = compare_scope(next.scope, previous->scope);
      delta.kind = relation == ScopeRelation::equal      ? DeltaKind::unchanged
                   : relation == ScopeRelation::narrower ? DeltaKind::narrowed
                   : relation == ScopeRelation::expanded
                       ? DeltaKind::expanded
                       : DeltaKind::incomparable;
      if (grant != nullptr && delta.kind == DeltaKind::unchanged) {
        delta.inherited_grant = *grant;
      } else if (grant != nullptr && delta.kind == DeltaKind::narrowed) {
        if (grant->state != GrantState::granted) {
          delta.inherited_grant = *grant;
          // The suggestion keeps the prior state/epoch but belongs to the
          // candidate request, whose exact narrower scope must be displayed.
          delta.inherited_grant->scope = next.scope;
        } else {
          const auto within_grant = compare_scope(next.scope, grant->scope);
          if (within_grant == ScopeRelation::equal ||
              within_grant == ScopeRelation::narrower) {
            delta.inherited_grant = *grant;
            delta.inherited_grant->scope = next.scope;
          }
        }
      }
    }
    result.push_back(std::move(delta));
  }
  for (const auto &previous : old_requests.values()) {
    if (request_for(new_requests, previous.capability) == nullptr) {
      result.push_back({.capability = previous.capability,
                        .kind = DeltaKind::removed,
                        .inherited_grant = std::nullopt});
    }
  }
  return result;
}

PermissionAuthority::PermissionAuthority(ActivationBinding binding,
                                         RequestSet requests, GrantSet grants)
    : binding_(std::move(binding)), requests_(std::move(requests)),
      grants_(std::move(grants)) {
  require(canonical_id(binding_.plugin.view()) &&
              canonical_digest(binding_.revision) &&
              canonical_digest(binding_.policy_fingerprint) &&
              binding_.generation > 0,
          "invalid activation binding");
  validate_requests(requests_);
  validate_grants(grants_, &requests_);
  require(binding_.policy_fingerprint ==
              Digest(policy_request_fingerprint(requests_)),
          "activation policy fingerprint mismatch");
}

PermissionAuthority::PermissionAuthority(ActivationBinding binding,
                                         RequestSet requests, GrantSet grants,
                                         ValidatedCombinedPolicy)
    : binding_(std::move(binding)), requests_(std::move(requests)),
      grants_(std::move(grants)) {
  require(canonical_id(binding_.plugin.view()) &&
              canonical_digest(binding_.revision) &&
              canonical_digest(binding_.policy_fingerprint) &&
              binding_.generation > 0,
          "invalid activation binding");
  validate_requests(requests_);
  validate_grants(grants_, &requests_);
}

GrantDecision PermissionAuthority::authorize(OperationId operation,
                                             const Scope &demand,
                                             const ActivationBinding &channel,
                                             std::uint64_t now_monotonic_ns,
                                             GestureProof *gesture) const {
  const auto *definition = find_operation(operation);
  if (definition == nullptr)
    return {.code = GrantDecisionCode::unknown_operation,
            .capability = {},
            .grant_epoch = 0};
  GrantDecision result{.code = GrantDecisionCode::ungranted,
                       .capability = definition->key};
  if (channel != binding_) {
    result.code = GrantDecisionCode::activation_mismatch;
    return result;
  }
  const auto *request = request_for(requests_, definition->key);
  if (request == nullptr) {
    result.code = GrantDecisionCode::capability_undeclared;
    return result;
  }
  const auto *grant = grant_for(grants_, definition->key);
  if (grant == nullptr)
    return result;
  result.grant_epoch = grant->epoch;
  if (grant->state == GrantState::denied) {
    result.code = GrantDecisionCode::explicitly_denied;
    return result;
  }
  if (grant->state == GrantState::revoked) {
    result.code = GrantDecisionCode::revoked;
    return result;
  }
  if (!valid_scope(*definition, demand) ||
      !demand_matches_operation(demand, operation)) {
    result.code = GrantDecisionCode::outside_scope;
    return result;
  }
  const auto relation = compare_scope(demand, grant->scope);
  if (relation != ScopeRelation::equal && relation != ScopeRelation::narrower) {
    result.code = GrantDecisionCode::outside_scope;
    return result;
  }
  if (definition->gesture == GestureRule::fresh_single_use) {
    if (gesture == nullptr) {
      result.code = GrantDecisionCode::gesture_missing;
      return result;
    }
    if (gesture->consumed) {
      result.code = GrantDecisionCode::gesture_used;
      return result;
    }
    if (now_monotonic_ns >= gesture->expires_monotonic_ns) {
      result.code = GrantDecisionCode::gesture_expired;
      return result;
    }
    if (!nonzero(gesture->id.bytes) || gesture->plugin != binding_.plugin ||
        gesture->generation != binding_.generation ||
        gesture->operation != operation || gesture->surface == 0) {
      result.code = GrantDecisionCode::gesture_wrong_binding;
      return result;
    }
    gesture->consumed = true;
  }
  result.code = GrantDecisionCode::allowed;
  return result;
}

std::uint64_t PermissionAuthority::revoke(const CapabilityKey &capability) {
  auto *grant = grant_for(grants_, capability);
  require(grant != nullptr, "cannot revoke missing grant");
  require(grant->epoch < std::numeric_limits<std::uint64_t>::max(),
          "grant epoch exhausted");
  ++grant->epoch;
  grant->state = GrantState::revoked;
  return grant->epoch;
}

bool valid_handle_record(const HandleRecord &record) {
  const auto *definition = find_operation(record.operation);
  return nonzero(record.id.bytes) && canonical_id(record.plugin.view()) &&
         canonical_digest(record.revision) &&
         canonical_digest(record.policy_fingerprint) && record.generation > 0 &&
         definition != nullptr && valid_scope(*definition, record.scope) &&
         demand_matches_operation(record.scope, record.operation) &&
         record.grant_epoch > 0 && record.expires_monotonic_ns > 0;
}

} // namespace omarchy::plugins::permissions
