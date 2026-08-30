#pragma once

#include "dynamic_activation.hpp"
#include "permission_contract.hpp"

#include <cstdint>
#include <string>
#include <vector>

namespace omarchy::plugin_runtime::policy {

namespace definitions = omarchy::plugins::definitions;
namespace permissions = omarchy::plugins::permissions;

struct GrantSnapshot {
  permissions::ActivationBinding binding;
  permissions::Digest source_request_fingerprint;
  permissions::RequestSet requests;
  permissions::GrantSet grants;
  std::vector<definitions::DynamicRevisionGrant> dynamic_grants;
};

enum class RevisionSlot : std::uint8_t { active, candidate };

struct Revocation {
  std::uint64_t sequence = 0;
  RevisionSlot slot = RevisionSlot::candidate;
  permissions::GrantRecord grant;
  permissions::RevocationMode action = permissions::RevocationMode::deny_new;
  std::string fingerprint;
};

} // namespace omarchy::plugin_runtime::policy
