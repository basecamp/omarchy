#include "omarchy/plugin_runtime/surface/render_messages.hpp"

#include <cstddef>
#include <cstdint>
#include <span>

extern "C" int LLVMFuzzerTestOneInput(const std::uint8_t *data,
                                      std::size_t size) {
  namespace surface = omarchy::plugin_runtime::surface;
  const auto bytes = std::as_bytes(std::span(data, size));
  surface::ProfileOffer offer{};
  surface::ProfileSelection selection{};
  surface::TrustedAllocation allocation{};
  surface::SurfaceKey key{};
  surface::FrameReady frame{};
  surface::InputEvent input{};
  surface::FocusEvent focus{};
  surface::RenderTypedError error{};
  static_cast<void>(surface::decode_profile_offer(bytes, offer));
  static_cast<void>(surface::decode_profile_selection(bytes, selection));
  static_cast<void>(
      surface::decode_surface_allocation(bytes, 4096, allocation));
  static_cast<void>(surface::decode_surface_key(bytes, key));
  static_cast<void>(surface::decode_frame_ready(bytes, frame));
  static_cast<void>(surface::decode_input_event(bytes, input));
  static_cast<void>(surface::decode_focus_event(bytes, focus));
  static_cast<void>(surface::decode_render_error(bytes, error));
  return 0;
}
