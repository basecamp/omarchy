#include "omarchy/plugin/wire/envelope.hpp"

#include <cstring>
#include <limits>

namespace omarchy::plugin::wire {
namespace {

void put16(std::span<std::byte> output, std::size_t offset,
           std::uint16_t value) {
  output[offset] = static_cast<std::byte>(value >> 8U);
  output[offset + 1] = static_cast<std::byte>(value);
}

void put32(std::span<std::byte> output, std::size_t offset,
           std::uint32_t value) {
  put16(output, offset, static_cast<std::uint16_t>(value >> 16U));
  put16(output, offset + 2, static_cast<std::uint16_t>(value));
}

void put64(std::span<std::byte> output, std::size_t offset,
           std::uint64_t value) {
  put32(output, offset, static_cast<std::uint32_t>(value >> 32U));
  put32(output, offset + 4, static_cast<std::uint32_t>(value));
}

std::uint16_t get16(std::span<const std::byte> input, std::size_t offset) {
  return (std::to_integer<std::uint16_t>(input[offset]) << 8U) |
         std::to_integer<std::uint16_t>(input[offset + 1]);
}

std::uint32_t get32(std::span<const std::byte> input, std::size_t offset) {
  return (static_cast<std::uint32_t>(get16(input, offset)) << 16U) |
         get16(input, offset + 2);
}

std::uint64_t get64(std::span<const std::byte> input, std::size_t offset) {
  return (static_cast<std::uint64_t>(get32(input, offset)) << 32U) |
         get32(input, offset + 4);
}

} // namespace

EncodeResult encode_packet(const EnvelopeHeader &header,
                           std::span<const std::byte> payload,
                           std::span<std::byte> output) {
  if (header.magic != kMagic) {
    return {0, FatalReason::invalid_magic};
  }
  if (header.envelope_version != kEnvelopeVersion) {
    return {0, FatalReason::unsupported_envelope_version};
  }
  if (header.header_size != kHeaderSize) {
    return {0, FatalReason::invalid_header_size};
  }
  if (header.flags != 0) {
    return {0, FatalReason::nonzero_flags};
  }
  if (header.reserved != 0) {
    return {0, FatalReason::nonzero_reserved};
  }
  const auto cap = payload_cap(header.endpoint_role);
  if (cap == 0 || payload.size() > cap ||
      payload.size() > std::numeric_limits<std::uint32_t>::max()) {
    return {0, FatalReason::payload_cap_exceeded};
  }
  const auto packet_size = kHeaderSize + payload.size();
  if (output.size() < packet_size) {
    return {0, FatalReason::output_too_small};
  }

  put32(output, 0, header.magic);
  put16(output, 4, header.envelope_version);
  put16(output, 6, header.header_size);
  put16(output, 8, static_cast<std::uint16_t>(header.endpoint_role));
  put16(output, 10, header.message_type);
  put16(output, 12, header.role_protocol_version);
  put16(output, 14, header.flags);
  put32(output, 16, static_cast<std::uint32_t>(payload.size()));
  put32(output, 20, header.reserved);
  put64(output, 24, header.launch_generation);
  put64(output, 32, header.correlation_id);
  if (!payload.empty()) {
    std::memcpy(output.data() + kHeaderSize, payload.data(), payload.size());
  }
  return {packet_size, FatalReason::none};
}

DecodeResult decode_packet(std::span<const std::byte> packet,
                           EndpointRole trusted_role) {
  if (packet.size() < kHeaderSize) {
    return {{}, FatalReason::packet_too_short};
  }

  EnvelopeHeader header{
      .magic = get32(packet, 0),
      .envelope_version = get16(packet, 4),
      .header_size = get16(packet, 6),
      .endpoint_role = static_cast<EndpointRole>(get16(packet, 8)),
      .message_type = get16(packet, 10),
      .role_protocol_version = get16(packet, 12),
      .flags = get16(packet, 14),
      .payload_length = get32(packet, 16),
      .reserved = get32(packet, 20),
      .launch_generation = get64(packet, 24),
      .correlation_id = get64(packet, 32),
  };

  if (header.magic != kMagic) {
    return {{}, FatalReason::invalid_magic};
  }
  if (header.envelope_version != kEnvelopeVersion) {
    return {{}, FatalReason::unsupported_envelope_version};
  }
  if (header.header_size != kHeaderSize) {
    return {{}, FatalReason::invalid_header_size};
  }
  if (header.flags != 0) {
    return {{}, FatalReason::nonzero_flags};
  }
  if (header.reserved != 0) {
    return {{}, FatalReason::nonzero_reserved};
  }
  if (header.endpoint_role != trusted_role) {
    return {{}, FatalReason::endpoint_role_mismatch};
  }
  const auto cap = payload_cap(trusted_role);
  if (cap == 0 || header.payload_length > cap) {
    return {{}, FatalReason::payload_cap_exceeded};
  }
  if (packet.size() - kHeaderSize != header.payload_length) {
    return {{}, FatalReason::packet_length_mismatch};
  }

  return {PacketView{header, packet.subspan(kHeaderSize)}, FatalReason::none};
}

} // namespace omarchy::plugin::wire
