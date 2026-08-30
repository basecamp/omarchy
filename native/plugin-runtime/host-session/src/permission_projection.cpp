#include "permission_projection.hpp"

#include "permission_contract.hpp"

#include <algorithm>
#include <cstdint>
#include <limits>
#include <ranges>

namespace omarchy::plugin_runtime::host_session {
namespace {

namespace definitions = plugins::definitions;
namespace manifest_contract = plugins::manifest;
namespace permissions = plugins::permissions;
namespace snapshot_wire = plugin::wire::permission_snapshot;

std::optional<snapshot_wire::GrantState>
wire_state(permissions::GrantState state) {
  switch (state) {
  case permissions::GrantState::granted:
    return snapshot_wire::GrantState::granted;
  case permissions::GrantState::denied:
    return snapshot_wire::GrantState::denied;
  case permissions::GrantState::revoked:
    return snapshot_wire::GrantState::revoked;
  }
  return std::nullopt;
}

const permissions::CapabilityRequest *
builtin_request(const permissions::RequestSet &requests,
                std::string_view capability) {
  const auto found = std::ranges::find_if(
      requests.values(), [&](const auto &request) {
        return request.capability.version == 1 &&
               request.capability.id.view() == capability;
      });
  return found == requests.values().end() ? nullptr : &*found;
}

const permissions::GrantRecord *
builtin_grant(const permissions::GrantSet &grants,
              const permissions::CapabilityKey &capability) {
  const auto found = std::ranges::find(grants.values(), capability,
                                       &permissions::GrantRecord::capability);
  return found == grants.values().end() ? nullptr : &*found;
}

bool same_dynamic_request(const manifest_contract::CapabilityRequest &manifest,
                          const definitions::DynamicRequest &request) {
  if (request.definition.canonical_name.view() != manifest.capability ||
      request.definition.definition_generation !=
          manifest.definition_generation ||
      request.definition.definition_digest.view() !=
          manifest.definition_digest ||
      request.scope.view() != manifest.canonical_scope ||
      request.required != manifest.required ||
      request.operations.size() != manifest.operations.size())
    return false;
  return std::ranges::equal(
      request.operations.values(), manifest.operations,
      [](const auto &left, const auto &right) { return left.view() == right; });
}

const definitions::DynamicRevisionGrant *
dynamic_grant(const std::vector<definitions::DynamicRevisionGrant> &grants,
              const manifest_contract::CapabilityRequest &request) {
  const auto found = std::ranges::find_if(grants, [&](const auto &grant) {
    return grant.request.definition.canonical_name.view() == request.capability;
  });
  return found == grants.end() ? nullptr : &*found;
}

bool valid_dynamic_grant_shape(
    const definitions::DynamicRevisionGrant &revision) {
  if (revision.grant.definition != revision.request.definition ||
      revision.grant.epoch == 0 || revision.grant.scope.view().empty() ||
      static_cast<std::uint8_t>(revision.grant.state) >
          static_cast<std::uint8_t>(permissions::GrantState::revoked))
    return false;
  if (revision.grant.state == permissions::GrantState::denied)
    return revision.grant.operations == revision.request.operations &&
           revision.grant.scope == revision.request.scope;
  return revision.grant.operations.size() != 0 &&
         std::ranges::all_of(revision.grant.operations.values(),
                             [&](const auto &operation) {
                               return revision.request.operations.contains(
                                   operation);
                             });
}

std::uint16_t complete_operation_mask(std::size_t count) {
  if (count == 0 || count > 16)
    throw std::runtime_error("permission request operation count is invalid");
  return count == 16 ? std::numeric_limits<std::uint16_t>::max()
                     : static_cast<std::uint16_t>((1U << count) - 1U);
}

std::uint16_t dynamic_operation_mask(
    const manifest_contract::CapabilityRequest &manifest,
    const definitions::DynamicGrant &grant) {
  std::uint16_t result = 0;
  for (std::size_t index = 0; index < manifest.operations.size(); ++index) {
    if (grant.operations.contains(definitions::Name(manifest.operations[index])))
      result |= static_cast<std::uint16_t>(1U << index);
  }
  return result;
}

} // namespace

std::optional<snapshot_wire::PermissionSnapshot>
project_permission_snapshot(const manifest_contract::ManifestV2 &manifest,
                            const policy::GrantSnapshot &snapshot) noexcept {
  try {
    if (snapshot.binding.plugin.view() != manifest.id ||
        snapshot.binding.generation == 0 ||
        snapshot.source_request_fingerprint.view() !=
            manifest_contract::requested_capability_fingerprint(
                manifest.requests) ||
        snapshot.binding.policy_fingerprint.view() !=
            permissions::policy_request_fingerprint(snapshot.requests))
      return std::nullopt;

    const auto expected_builtin =
        permissions::requests_from_manifest(manifest);
    if (expected_builtin.size() != snapshot.requests.size() ||
        snapshot.grants.size() != snapshot.requests.size())
      return std::nullopt;
    permissions::PermissionAuthority authority(
        snapshot.binding, snapshot.requests, snapshot.grants);
    (void)authority;
    for (const auto &expected : expected_builtin.values()) {
      const auto *actual = builtin_request(
          snapshot.requests, expected.capability.id.view());
      if (actual == nullptr || *actual != expected)
        return std::nullopt;
    }

    const auto dynamic_count = std::ranges::count_if(
        manifest.requests,
        [](const auto &request) { return request.definition_generation != 0; });
    if (static_cast<std::size_t>(dynamic_count) !=
        snapshot.dynamic_grants.size())
      return std::nullopt;

    snapshot_wire::PermissionSnapshot result{
        .manifest_request_fingerprint =
            manifest_contract::requested_capability_fingerprint(
                manifest.requests),
        .permissions = {}};
    const auto ordered =
        manifest_contract::canonical_capability_requests(manifest.requests);
    result.permissions.reserve(ordered.size());
    for (const auto &request : ordered) {
      std::optional<snapshot_wire::GrantState> state;
      std::uint16_t operation_mask = 0;
      if (request.definition_generation == 0) {
        const auto *declared = builtin_request(snapshot.requests,
                                               request.capability);
        if (declared == nullptr)
          return std::nullopt;
        const auto *grant = builtin_grant(snapshot.grants,
                                          declared->capability);
        if (grant == nullptr)
          return std::nullopt;
        state = wire_state(grant->state);
        if (grant->state != permissions::GrantState::denied) {
          const auto *definition =
              permissions::find_capability(declared->capability);
          if (definition == nullptr)
            return std::nullopt;
          operation_mask =
              complete_operation_mask(definition->operation_count);
        }
      } else {
        const auto *revision = dynamic_grant(snapshot.dynamic_grants, request);
        if (revision == nullptr || revision->binding != snapshot.binding ||
            !same_dynamic_request(request, revision->request) ||
            !valid_dynamic_grant_shape(*revision))
          return std::nullopt;
        state = wire_state(revision->grant.state);
        if (revision->grant.state != permissions::GrantState::denied)
          operation_mask = dynamic_operation_mask(request, revision->grant);
      }
      if (!state ||
          (request.required && *state != snapshot_wire::GrantState::granted))
        return std::nullopt;
      result.permissions.push_back(
          {.state = *state, .operation_mask = operation_mask});
    }
    return result;
  } catch (...) {
    return std::nullopt;
  }
}

} // namespace omarchy::plugin_runtime::host_session
