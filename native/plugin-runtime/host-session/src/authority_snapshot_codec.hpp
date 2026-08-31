#pragma once

#include "authority_store.hpp"

#include <cstddef>
#include <optional>
#include <span>
#include <string_view>
#include <vector>

namespace omarchy::plugin_runtime::host_session::authority_snapshot_codec {

inline constexpr std::size_t kMaximumEncodedAuthorityBytes = 8 * 1024 * 1024;

[[nodiscard]] bool encode_snapshot(const policy::GrantSnapshot &snapshot,
                                   std::vector<std::byte> &output);
[[nodiscard]] bool decode_snapshot(std::span<const std::byte> bytes,
                                   policy::GrantSnapshot &snapshot);
[[nodiscard]] bool
complete_snapshot(const VerifiedRevision &verified,
                  const policy::GrantSnapshot &snapshot,
                  const definitions::TrustedDefinitionRegistry &registry,
                  definitions::DynamicScopeValidator validator);
[[nodiscard]] AuthorityRevisionRef
reference_for(const policy::GrantSnapshot &snapshot, std::string_view digest);
[[nodiscard]] std::vector<std::byte> encode_slots(const AuthoritySlots &slots);
[[nodiscard]] std::optional<AuthoritySlots>
decode_slots(std::span<const std::byte> bytes);

} // namespace omarchy::plugin_runtime::host_session::authority_snapshot_codec
