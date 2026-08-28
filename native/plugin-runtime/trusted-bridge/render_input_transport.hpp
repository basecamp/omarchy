#pragma once

#include "omarchy/plugin/wire/state.hpp"
#include "omarchy/plugin_runtime/surface/bridge_contract.hpp"
#include "omarchy/plugin_runtime/surface/render_messages.hpp"

#include <cstddef>
#include <cstdint>
#include <memory>
#include <span>

namespace omarchy::plugin_runtime::bridge {

namespace surface = omarchy::plugin_runtime::surface;
namespace wire = omarchy::plugin::wire;

class RenderPacketSink {
public:
  virtual ~RenderPacketSink() = default;
  virtual bool send(const wire::EnvelopeHeader &header,
                    std::span<const std::byte> payload) = 0;
};

class AuthenticatedInputTransport final : public surface::HostInputSource {
public:
  AuthenticatedInputTransport(std::uint64_t launch_generation,
                              std::shared_ptr<RenderPacketSink> sink);

  bool submit(const surface::InputEvent &event) override;
  bool submit_focus(const surface::FocusEvent &event);
  void disconnect();

  [[nodiscard]] bool connected() const;
  [[nodiscard]] bool failed() const;

private:
  bool send(std::uint16_t message_type, std::span<const std::byte> payload);

  std::uint64_t generation_ = 0;
  std::shared_ptr<RenderPacketSink> sink_;
  wire::SelectedEndpointState<1> endpoint_;
  bool connected_ = true;
  bool failed_ = false;
};

} // namespace omarchy::plugin_runtime::bridge
