#pragma once

#include "authenticated_session_channel.hpp"

#include <span>

namespace omarchy::plugin_runtime::channel {

// Private transport seam shared by the runtime implementation and the
// standalone macro-gated adapter test. It is not part of the installed API.
class AuthenticatedSessionBackend {
public:
  virtual ~AuthenticatedSessionBackend() = default;
  [[nodiscard]] virtual session::ChannelError
  launch(const session::SessionToken &token, launcher::Deadline deadline) = 0;
  [[nodiscard]] virtual session::ChannelError
  handshake(launcher::Deadline deadline) = 0;
  [[nodiscard]] virtual bool
  prepare(wire::EndpointRole role, std::uint16_t message_type,
          std::uint64_t correlation_id, std::span<const std::byte> payload,
          std::size_t descriptor_count) = 0;
  [[nodiscard]] virtual session::SendStatus
  try_send(std::span<const int> borrowed_descriptors,
           launcher::Deadline deadline) = 0;
  [[nodiscard]] virtual AuthenticatedReceiveResult
  receive(launcher::EndpointMask allowed_lanes,
          launcher::Deadline deadline) = 0;
  [[nodiscard]] virtual int readiness_fd() const noexcept = 0;
  [[nodiscard]] virtual bool
  arm(launcher::EndpointMask read_lanes,
      launcher::EndpointMask write_lanes) noexcept = 0;
  virtual void terminate(launcher::Deadline deadline) noexcept = 0;
};

} // namespace omarchy::plugin_runtime::channel
