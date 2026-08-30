#pragma once

#include <cstddef>
#include <cstdint>
#include <span>
#include <string>
#include <string_view>
#include <vector>

namespace omarchy::plugin::wire::permission_snapshot {

inline constexpr std::uint16_t kCodecVersion = 1;
inline constexpr std::size_t kManifestRequestFingerprintBytes = 64;
inline constexpr std::size_t kMaximumManifestRequests = 256;
inline constexpr std::size_t kFixedPayloadBytes =
    sizeof(std::uint16_t) + kManifestRequestFingerprintBytes +
    sizeof(std::uint16_t);
inline constexpr std::size_t kMaximumPayloadBytes =
    kFixedPayloadBytes + kMaximumManifestRequests;

// These values are the complete wire state space. They intentionally do not
// depend on the host policy implementation's enum representation.
enum class GrantState : std::uint8_t {
  granted = 1,
  denied = 2,
  revoked = 3,
};

struct PermissionSnapshot {
  std::string manifest_request_fingerprint;

  // One entry per manifest request, ordered by the same canonical request
  // tuple used by requested_capability_fingerprint(): capability, required,
  // canonical scope, definition generation, definition digest, and sorted
  // operations. Manifest array order therefore cannot change this mapping.
  std::vector<GrantState> states;

  bool operator==(const PermissionSnapshot &) const = default;
};

[[nodiscard]] bool
valid_manifest_request_fingerprint(std::string_view fingerprint) noexcept;
[[nodiscard]] std::vector<std::byte> encode(const PermissionSnapshot &snapshot);
[[nodiscard]] bool decode(std::span<const std::byte> payload,
                          PermissionSnapshot &snapshot);

} // namespace omarchy::plugin::wire::permission_snapshot
