#pragma once

#include "omarchy/plugin/wire/state.hpp"
#include "omarchy/plugin_runtime/surface/bridge_contract.hpp"
#include "omarchy/plugin_runtime/surface/frame_region.hpp"
#include "omarchy/plugin_runtime/surface/frame_transport.hpp"

#include <chrono>
#include <cstddef>
#include <cstdint>
#include <memory>
#include <optional>
#include <span>
#include <string>

namespace omarchy::plugin_runtime::render_session {

namespace surface = omarchy::plugin_runtime::surface;
namespace wire = omarchy::plugin::wire;

class PacketSender {
public:
  virtual ~PacketSender() = default;
  virtual bool send(const wire::EnvelopeHeader &header,
                    std::span<const std::byte> payload,
                    std::span<const int> descriptors) = 0;
};

enum class Phase {
  idle,
  awaiting_profile,
  awaiting_allocation,
  active,
  failed,
  disconnected,
};

enum class SinkDisposition : std::uint8_t { disconnect, abandon };

struct Statistics {
  std::uint64_t accepted_frames = 0;
  std::uint64_t rejected_frames = 0;
  std::uint64_t copied_bytes = 0;
  std::chrono::nanoseconds total_copy_time{};
  std::chrono::nanoseconds maximum_copy_time{};
};

// A render message admitted by the authenticated channel boundary. The payload
// is borrowed and consumed synchronously. Worker render messages never carry
// descriptors; the channel adapter must reject descriptor-bearing messages
// before constructing this view.
struct AuthenticatedRenderPacket {
  std::uint16_t message_type = 0;
  std::uint64_t correlation_id = 0;
  std::span<const std::byte> payload;
};

class HostRenderSession final {
public:
  HostRenderSession(std::uint64_t launch_generation,
                    surface::TrustedFrameSink &sink, PacketSender &sender,
                    std::uint64_t correlation_base = 0);
  ~HostRenderSession();
  HostRenderSession(const HostRenderSession &) = delete;
  HostRenderSession &operator=(const HostRenderSession &) = delete;

  [[nodiscard]] bool start(const surface::TrustedAllocation &allocation);
  [[nodiscard]] bool receive(const AuthenticatedRenderPacket &packet);
  void close(SinkDisposition sink = SinkDisposition::disconnect);

  [[nodiscard]] Phase phase() const;
  [[nodiscard]] const Statistics &statistics() const;
  [[nodiscard]] const std::string &failure_detail() const;
  [[nodiscard]] const surface::TrustedAllocation *allocation() const;

private:
  bool send(std::uint16_t message_type, std::span<const std::byte> payload,
            std::uint64_t correlation, std::span<const int> descriptors = {});
  bool fail(std::string detail);
  bool accept(const wire::PacketView &packet);
  bool handle(const wire::PacketView &packet);

  std::uint64_t generation_ = 0;
  std::uint64_t correlation_base_ = 0;
  surface::TrustedFrameSink &sink_;
  PacketSender &sender_;
  std::unique_ptr<wire::SelectedEndpointState<8>> endpoint_;
  std::optional<surface::TrustedAllocation> allocation_;
  std::optional<surface::HostFrameRegion> region_;
  std::optional<surface::FrameConsumer> consumer_;
  Phase phase_ = Phase::idle;
  Statistics statistics_;
  std::string failure_detail_;
};

} // namespace omarchy::plugin_runtime::render_session
