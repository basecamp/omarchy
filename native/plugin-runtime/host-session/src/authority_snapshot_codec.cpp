#include "authority_snapshot_codec.hpp"

#include "manifest_contract.hpp"

#include <algorithm>
#include <array>
#include <cstdint>
#include <utility>

namespace omarchy::plugin_runtime::host_session::authority_snapshot_codec {
namespace {

constexpr std::size_t kMaximumDynamicGrants = 128;
constexpr std::array<std::byte, 8> kSnapshotMagic{
    std::byte{'O'}, std::byte{'M'}, std::byte{'G'}, std::byte{'R'},
    std::byte{'A'}, std::byte{'N'}, std::byte{'T'}, std::byte{1}};
constexpr std::array<std::byte, 8> kSlotsMagic{
    std::byte{'O'}, std::byte{'M'}, std::byte{'S'}, std::byte{'L'},
    std::byte{'O'}, std::byte{'T'}, std::byte{'S'}, std::byte{1}};

struct Writer {
  std::vector<std::byte> bytes;

  bool raw(std::span<const std::byte> value) {
    if (value.size() > kMaximumEncodedAuthorityBytes - bytes.size())
      return false;
    bytes.insert(bytes.end(), value.begin(), value.end());
    return true;
  }
  bool u8(std::uint8_t value) { return raw(std::array{std::byte{value}}); }
  bool u16(std::uint16_t value) {
    return raw(std::array{std::byte{static_cast<unsigned char>(value >> 8)},
                          std::byte{static_cast<unsigned char>(value)}});
  }
  bool u32(std::uint32_t value) {
    std::array<std::byte, 4> bytes{};
    for (int index = 0; index < 4; ++index)
      bytes[index] =
          std::byte{static_cast<unsigned char>(value >> (24 - 8 * index))};
    return raw(bytes);
  }
  bool u64(std::uint64_t value) {
    std::array<std::byte, 8> bytes{};
    for (int index = 0; index < 8; ++index)
      bytes[index] =
          std::byte{static_cast<unsigned char>(value >> (56 - 8 * index))};
    return raw(bytes);
  }
  bool text(std::string_view value) {
    return !value.empty() && value.size() <= UINT16_MAX &&
           u16(static_cast<std::uint16_t>(value.size())) &&
           raw(std::as_bytes(std::span(value.data(), value.size())));
  }
  bool blob(std::string_view value) {
    return value.size() <= UINT16_MAX &&
           u16(static_cast<std::uint16_t>(value.size())) &&
           raw(std::as_bytes(std::span(value.data(), value.size())));
  }
};

struct Reader {
  std::span<const std::byte> bytes;
  std::size_t offset = 0;

  bool raw(std::size_t size, std::span<const std::byte> &value) {
    if (size > bytes.size() - std::min(offset, bytes.size()))
      return false;
    value = bytes.subspan(offset, size);
    offset += size;
    return true;
  }
  bool u8(std::uint8_t &value) {
    std::span<const std::byte> bytes;
    if (!raw(1, bytes))
      return false;
    value = std::to_integer<std::uint8_t>(bytes[0]);
    return true;
  }
  bool u16(std::uint16_t &value) {
    std::span<const std::byte> bytes;
    if (!raw(2, bytes))
      return false;
    value =
        static_cast<std::uint16_t>(std::to_integer<unsigned>(bytes[0]) << 8 |
                                   std::to_integer<unsigned>(bytes[1]));
    return true;
  }
  bool u32(std::uint32_t &value) {
    std::span<const std::byte> bytes;
    if (!raw(4, bytes))
      return false;
    value = 0;
    for (const auto byte : bytes)
      value = value << 8 | std::to_integer<unsigned>(byte);
    return true;
  }
  bool u64(std::uint64_t &value) {
    std::span<const std::byte> bytes;
    if (!raw(8, bytes))
      return false;
    value = 0;
    for (const auto byte : bytes)
      value = value << 8 | std::to_integer<unsigned>(byte);
    return true;
  }
  bool text(std::string_view &value) {
    std::uint16_t size = 0;
    std::span<const std::byte> bytes;
    if (!u16(size) || size == 0 || !raw(size, bytes))
      return false;
    value = {reinterpret_cast<const char *>(bytes.data()), bytes.size()};
    return value.find('\0') == std::string_view::npos;
  }
  bool blob(std::string_view &value) {
    std::uint16_t size = 0;
    std::span<const std::byte> bytes;
    if (!u16(size) || !raw(size, bytes))
      return false;
    value = {reinterpret_cast<const char *>(bytes.data()), bytes.size()};
    return true;
  }
};

bool same_requests(const permissions::RequestSet &left,
                   const permissions::RequestSet &right) {
  return std::ranges::equal(left.values(), right.values());
}

bool write_reference(Writer &writer,
                     const std::optional<AuthorityRevisionRef> &reference) {
  if (!writer.u8(reference.has_value()))
    return false;
  return !reference || (writer.text(reference->snapshot_digest.view()) &&
                        writer.u64(reference->generation));
}

bool read_reference(Reader &reader,
                    std::optional<AuthorityRevisionRef> &reference) {
  std::uint8_t present = 0;
  std::string_view text;
  if (!reader.u8(present) || present > 1)
    return false;
  if (!present) {
    reference.reset();
    return true;
  }
  try {
    AuthorityRevisionRef value;
    if (!reader.text(text))
      return false;
    value.snapshot_digest = permissions::Digest(text);
    if (!reader.u64(value.generation) || value.generation == 0)
      return false;
    reference = std::move(value);
    return true;
  } catch (...) {
    return false;
  }
}

} // namespace

bool encode_snapshot(const policy::GrantSnapshot &snapshot,
                     std::vector<std::byte> &output) {
  Writer writer;
  if (!writer.raw(kSnapshotMagic) ||
      !writer.text(snapshot.binding.plugin.view()) ||
      !writer.text(snapshot.binding.revision.view()) ||
      !writer.text(snapshot.binding.policy_fingerprint.view()) ||
      !writer.u64(snapshot.binding.generation) ||
      !writer.text(snapshot.source_request_fingerprint.view()) ||
      !writer.u8(static_cast<std::uint8_t>(snapshot.requests.size())))
    return false;
  for (const auto &request : snapshot.requests.values()) {
    if (!writer.text(request.capability.id.view()) ||
        !writer.u16(request.capability.version) ||
        !writer.blob(permissions::canonical_scope(request.scope)) ||
        !writer.u8(request.required))
      return false;
  }
  if (!writer.u8(static_cast<std::uint8_t>(snapshot.grants.size())))
    return false;
  for (const auto &grant : snapshot.grants.values()) {
    if (!writer.text(grant.capability.id.view()) ||
        !writer.u16(grant.capability.version) ||
        !writer.blob(permissions::canonical_scope(grant.scope)) ||
        !writer.u8(static_cast<std::uint8_t>(grant.state)) ||
        !writer.u64(grant.epoch))
      return false;
  }
  if (snapshot.dynamic_grants.size() > kMaximumDynamicGrants ||
      !writer.u8(static_cast<std::uint8_t>(snapshot.dynamic_grants.size())))
    return false;
  std::array<std::byte, definitions::kMaximumDynamicEnvelopeBytes> encoded{};
  for (const auto &grant : snapshot.dynamic_grants) {
    std::size_t size = 0;
    if (!definitions::encode_dynamic_grant(grant, encoded, size) ||
        size > definitions::kMaximumDynamicEnvelopeBytes ||
        !writer.u32(static_cast<std::uint32_t>(size)) ||
        !writer.raw(std::span(encoded).first(size)))
      return false;
  }
  output = std::move(writer.bytes);
  return true;
}

bool decode_snapshot(std::span<const std::byte> bytes,
                     policy::GrantSnapshot &snapshot) {
  Reader reader{bytes};
  std::span<const std::byte> magic;
  std::string_view text;
  std::uint8_t count = 0;
  snapshot = {};
  try {
    if (!reader.raw(kSnapshotMagic.size(), magic) ||
        !std::ranges::equal(magic, kSnapshotMagic) || !reader.text(text))
      return false;
    snapshot.binding.plugin = permissions::PluginId(text);
    if (!reader.text(text))
      return false;
    snapshot.binding.revision = permissions::Digest(text);
    if (!reader.text(text))
      return false;
    snapshot.binding.policy_fingerprint = permissions::Digest(text);
    if (!reader.u64(snapshot.binding.generation) || !reader.text(text))
      return false;
    snapshot.source_request_fingerprint = permissions::Digest(text);
    if (!reader.u8(count) || count > 64)
      return false;
    for (std::uint8_t index = 0; index < count; ++index) {
      permissions::CapabilityRequest request;
      std::uint8_t required = 0;
      if (!reader.text(text))
        return false;
      request.capability.id = permissions::CapabilityId(text);
      if (!reader.u16(request.capability.version) || !reader.blob(text))
        return false;
      request.scope =
          permissions::scope_from_canonical(request.capability, text);
      if (!reader.u8(required) || required > 1)
        return false;
      request.required = required;
      snapshot.requests.push_back(std::move(request));
    }
    if (!reader.u8(count) || count > 64)
      return false;
    for (std::uint8_t index = 0; index < count; ++index) {
      permissions::GrantRecord grant;
      std::uint8_t state = 0;
      if (!reader.text(text))
        return false;
      grant.capability.id = permissions::CapabilityId(text);
      if (!reader.u16(grant.capability.version) || !reader.blob(text))
        return false;
      grant.scope = permissions::scope_from_canonical(grant.capability, text);
      if (!reader.u8(state) ||
          state > static_cast<std::uint8_t>(permissions::GrantState::revoked) ||
          !reader.u64(grant.epoch))
        return false;
      grant.state = static_cast<permissions::GrantState>(state);
      snapshot.grants.push_back(std::move(grant));
    }
    if (!reader.u8(count) || count > kMaximumDynamicGrants)
      return false;
    for (std::uint8_t index = 0; index < count; ++index) {
      std::uint32_t size = 0;
      std::span<const std::byte> encoded;
      definitions::DynamicRevisionGrant grant;
      if (!reader.u32(size) ||
          size > definitions::kMaximumDynamicEnvelopeBytes ||
          !reader.raw(size, encoded) ||
          !definitions::decode_dynamic_grant(encoded, grant))
        return false;
      snapshot.dynamic_grants.push_back(std::move(grant));
    }
  } catch (...) {
    return false;
  }
  return reader.offset == bytes.size();
}

bool complete_snapshot(const VerifiedRevision &verified,
                       const policy::GrantSnapshot &snapshot,
                       const definitions::TrustedDefinitionRegistry &registry,
                       definitions::DynamicScopeValidator validator) {
  try {
    if (snapshot.binding.plugin.view() != verified.manifest.id ||
        snapshot.binding.revision.view() != verified.tree_sha256 ||
        snapshot.source_request_fingerprint.view() != verified.request_sha256 ||
        verified.request_sha256 !=
            plugins::manifest::requested_capability_fingerprint(
                verified.manifest.requests) ||
        snapshot.binding.generation == 0 ||
        snapshot.binding.policy_fingerprint.view() !=
            permissions::policy_request_fingerprint(snapshot.requests) ||
        !same_requests(snapshot.requests,
                       permissions::requests_from_manifest(verified.manifest)))
      return false;
    if (snapshot.grants.size() != snapshot.requests.size())
      return false;
    permissions::PermissionAuthority builtin(
        snapshot.binding, snapshot.requests, snapshot.grants);
    (void)builtin;
    std::vector<definitions::DynamicRequest> requested;
    for (const auto &manifest_request : verified.manifest.requests) {
      if (manifest_request.definition_generation == 0)
        continue;
      auto dynamic = definitions::dynamic_request_from_manifest(
          manifest_request, registry);
      if (!dynamic)
        return false;
      requested.push_back(std::move(*dynamic));
    }
    if (requested.size() != snapshot.dynamic_grants.size() ||
        requested.size() > kMaximumDynamicGrants)
      return false;
    std::ranges::sort(requested, {}, [](const auto &request) {
      return request.definition.canonical_name;
    });
    for (std::size_t index = 0; index < requested.size(); ++index) {
      const auto &grant = snapshot.dynamic_grants[index];
      if (grant.binding != snapshot.binding ||
          grant.request != requested[index] ||
          static_cast<std::uint8_t>(grant.grant.state) >
              static_cast<std::uint8_t>(permissions::GrantState::revoked) ||
          !definitions::review_dynamic_grant(registry, grant, validator))
        return false;
      if (index > 0 && !(snapshot.dynamic_grants[index - 1]
                             .request.definition.canonical_name <
                         grant.request.definition.canonical_name))
        return false;
    }
    return true;
  } catch (...) {
    return false;
  }
}

AuthorityRevisionRef reference_for(const policy::GrantSnapshot &snapshot,
                                   std::string_view digest) {
  return {.snapshot_digest = permissions::Digest(digest),
          .generation = snapshot.binding.generation};
}

std::vector<std::byte> encode_slots(const AuthoritySlots &slots) {
  Writer writer;
  if (!writer.raw(kSlotsMagic) || !writer.u64(slots.sequence) ||
      !writer.u64(slots.generation_high_watermark) ||
      !write_reference(writer, slots.active) ||
      !write_reference(writer, slots.candidate))
    return {};
  return std::move(writer.bytes);
}

std::optional<AuthoritySlots> decode_slots(std::span<const std::byte> bytes) {
  Reader reader{bytes};
  std::span<const std::byte> magic;
  AuthoritySlots slots;
  if (!reader.raw(kSlotsMagic.size(), magic) ||
      !std::ranges::equal(magic, kSlotsMagic) || !reader.u64(slots.sequence) ||
      !reader.u64(slots.generation_high_watermark) ||
      !read_reference(reader, slots.active) ||
      !read_reference(reader, slots.candidate) || reader.offset != bytes.size())
    return std::nullopt;
  return slots;
}

} // namespace omarchy::plugin_runtime::host_session::authority_snapshot_codec
