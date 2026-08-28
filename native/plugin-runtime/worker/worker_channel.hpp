#pragma once

#include "omarchy/plugin/wire/state.hpp"

#include <cstddef>
#include <cstdint>
#include <memory>
#include <span>
#include <string>
#include <vector>

namespace omarchy::plugin_runtime::worker {

namespace wire = omarchy::plugin::wire;

enum class ChannelFailure {
  none,
  invalid_descriptor,
  peer_baseline_failed,
  io_error,
  truncated,
  malformed_ancillary,
  credential_mismatch,
  malformed_envelope,
  descriptor_mismatch,
  negotiation_failed,
  send_failed,
};

class ReceivedPacket {
public:
  ReceivedPacket();
  ~ReceivedPacket();
  ReceivedPacket(const ReceivedPacket &) = delete;
  ReceivedPacket &operator=(const ReceivedPacket &) = delete;
  ReceivedPacket(ReceivedPacket &&) noexcept;
  ReceivedPacket &operator=(ReceivedPacket &&) noexcept;

  wire::EnvelopeHeader header{};
  std::vector<std::byte> payload;
  std::vector<int> descriptors;
  ChannelFailure failure = ChannelFailure::none;
  std::string detail;

  [[nodiscard]] explicit operator bool() const {
    return failure == ChannelFailure::none;
  }
  [[nodiscard]] int take_only_descriptor();
  void close_descriptors();
};

class WorkerEndpoint {
public:
  WorkerEndpoint(int descriptor, wire::EndpointRole role,
                 std::uint16_t role_version);
  ~WorkerEndpoint();
  WorkerEndpoint(const WorkerEndpoint &) = delete;
  WorkerEndpoint &operator=(const WorkerEndpoint &) = delete;

  [[nodiscard]] bool valid() const;
  [[nodiscard]] int descriptor() const;
  [[nodiscard]] wire::EndpointRole role() const;
  [[nodiscard]] std::uint64_t generation() const;
  [[nodiscard]] std::uint16_t selected_version() const;
  [[nodiscard]] std::uint32_t maximum_payload() const;
  [[nodiscard]] std::uint32_t maximum_in_flight() const;
  [[nodiscard]] bool selected() const;
  [[nodiscard]] const std::string &last_error() const;

  [[nodiscard]] bool send_hello();
  [[nodiscard]] ReceivedPacket receive();
  [[nodiscard]] bool accept_welcome(const ReceivedPacket &packet);
  [[nodiscard]] bool send(std::uint16_t message_type,
                          std::span<const std::byte> payload,
                          std::uint64_t correlation_id);

private:
  struct Impl;
  std::unique_ptr<Impl> implementation_;
};

} // namespace omarchy::plugin_runtime::worker
