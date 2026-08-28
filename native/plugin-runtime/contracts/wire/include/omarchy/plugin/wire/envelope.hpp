#pragma once

#include "omarchy/plugin/wire/error.hpp"

#include <cstddef>
#include <cstdint>
#include <span>

namespace omarchy::plugin::wire {

inline constexpr std::uint32_t kMagic = 0x4f4d504c;
inline constexpr std::uint16_t kEnvelopeVersion = 1;
inline constexpr std::size_t kHeaderSize = 40;

enum class EndpointRole : std::uint16_t {
  control = 1,
  broker = 2,
  render = 3,
};

enum class Direction : std::uint8_t { worker_to_host, host_to_worker };

enum class CommonMessageType : std::uint16_t {
  hello = 0x0001,
  welcome = 0x0002,
  negotiation_failed = 0x0003,
  typed_error = 0x0004,
  cancel = 0x0005,
  cancel_result = 0x0006,
  protocol_error = 0x0007,
};

struct EnvelopeHeader {
  std::uint32_t magic = kMagic;
  std::uint16_t envelope_version = kEnvelopeVersion;
  std::uint16_t header_size = kHeaderSize;
  EndpointRole endpoint_role = EndpointRole::control;
  std::uint16_t message_type =
      static_cast<std::uint16_t>(CommonMessageType::hello);
  std::uint16_t role_protocol_version = 0;
  std::uint16_t flags = 0;
  std::uint32_t payload_length = 0;
  std::uint32_t reserved = 0;
  std::uint64_t launch_generation = 0;
  std::uint64_t correlation_id = 0;
};

struct PacketView {
  EnvelopeHeader header;
  std::span<const std::byte> payload;
};

struct DecodeResult {
  PacketView packet{};
  FatalReason error = FatalReason::none;

  [[nodiscard]] constexpr explicit operator bool() const {
    return error == FatalReason::none;
  }
};

struct EncodeResult {
  std::size_t bytes_written = 0;
  FatalReason error = FatalReason::none;

  [[nodiscard]] constexpr explicit operator bool() const {
    return error == FatalReason::none;
  }
};

[[nodiscard]] constexpr std::uint32_t payload_cap(EndpointRole role) {
  switch (role) {
  case EndpointRole::control:
    return 4096;
  case EndpointRole::broker:
    return 65536;
  case EndpointRole::render:
    return 16384;
  }
  return 0;
}

[[nodiscard]] constexpr Direction opposite(Direction direction) {
  return direction == Direction::worker_to_host ? Direction::host_to_worker
                                                : Direction::worker_to_host;
}

[[nodiscard]] EncodeResult encode_packet(const EnvelopeHeader &header,
                                         std::span<const std::byte> payload,
                                         std::span<std::byte> output);

[[nodiscard]] DecodeResult decode_packet(std::span<const std::byte> packet,
                                         EndpointRole trusted_role);

} // namespace omarchy::plugin::wire
