#include "omarchy/plugin/wire/permission_snapshot.hpp"

#include <algorithm>
#include <utility>

namespace omarchy::plugin::wire::permission_snapshot {
namespace {

void put16(std::span<std::byte> output, std::size_t offset,
           std::uint16_t value) {
  output[offset] = static_cast<std::byte>(value >> 8U);
  output[offset + 1] = static_cast<std::byte>(value);
}

std::uint16_t get16(std::span<const std::byte> input, std::size_t offset) {
  return (std::to_integer<std::uint16_t>(input[offset]) << 8U) |
         std::to_integer<std::uint16_t>(input[offset + 1]);
}

bool valid_state(GrantState state) {
  return state >= GrantState::granted && state <= GrantState::revoked;
}

} // namespace

bool valid_manifest_request_fingerprint(std::string_view fingerprint) noexcept {
  return fingerprint.size() == kManifestRequestFingerprintBytes &&
         std::ranges::all_of(fingerprint, [](unsigned char character) {
           return (character >= '0' && character <= '9') ||
                  (character >= 'a' && character <= 'f');
         });
}

std::vector<std::byte> encode(const PermissionSnapshot &snapshot) {
  if (!valid_manifest_request_fingerprint(
          snapshot.manifest_request_fingerprint) ||
      snapshot.states.size() > kMaximumManifestRequests ||
      !std::ranges::all_of(snapshot.states, valid_state))
    return {};

  std::vector<std::byte> output(kFixedPayloadBytes + snapshot.states.size());
  put16(output, 0, kCodecVersion);
  std::transform(snapshot.manifest_request_fingerprint.begin(),
                 snapshot.manifest_request_fingerprint.end(),
                 output.begin() + sizeof(std::uint16_t),
                 [](char character) { return std::byte(character); });
  put16(output, sizeof(std::uint16_t) + kManifestRequestFingerprintBytes,
        static_cast<std::uint16_t>(snapshot.states.size()));
  std::transform(snapshot.states.begin(), snapshot.states.end(),
                 output.begin() + kFixedPayloadBytes, [](GrantState state) {
                   return static_cast<std::byte>(state);
                 });
  return output;
}

bool decode(std::span<const std::byte> payload, PermissionSnapshot &snapshot) {
  if (payload.size() < kFixedPayloadBytes ||
      payload.size() > kMaximumPayloadBytes ||
      get16(payload, 0) != kCodecVersion)
    return false;

  PermissionSnapshot decoded;
  decoded.manifest_request_fingerprint.reserve(
      kManifestRequestFingerprintBytes);
  for (std::size_t index = 0; index < kManifestRequestFingerprintBytes;
       ++index) {
    decoded.manifest_request_fingerprint.push_back(
        static_cast<char>(std::to_integer<unsigned char>(
            payload[sizeof(std::uint16_t) + index])));
  }
  if (!valid_manifest_request_fingerprint(decoded.manifest_request_fingerprint))
    return false;

  const auto count =
      get16(payload, sizeof(std::uint16_t) + kManifestRequestFingerprintBytes);
  if (count > kMaximumManifestRequests ||
      payload.size() != kFixedPayloadBytes + count)
    return false;

  decoded.states.reserve(count);
  for (const auto byte : payload.subspan(kFixedPayloadBytes)) {
    const auto state =
        static_cast<GrantState>(std::to_integer<std::uint8_t>(byte));
    if (!valid_state(state))
      return false;
    decoded.states.push_back(state);
  }
  snapshot = std::move(decoded);
  return true;
}

} // namespace omarchy::plugin::wire::permission_snapshot
