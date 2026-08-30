#include "test.hpp"

#include "omarchy/plugin_runtime/surface/bridge_contract.hpp"

#include <cstddef>
#include <cstdint>
#include <span>
#include <vector>

using namespace omarchy::plugin_runtime::surface;

class RecordingBridge final : public TrustedFrameSink, public HostInputSource {
public:
  bool configure(const TrustedAllocation &allocation) override {
    configured = allocation.surface;
    return true;
  }
  bool present(SurfaceKey surface, std::uint64_t frame_sequence,
               std::span<const std::byte> trusted_pixels) override {
    presented = surface;
    sequence = frame_sequence;
    bytes.assign(trusted_pixels.begin(), trusted_pixels.end());
    return true;
  }
  bool updateInputRegions(const InputRegionUpdate &) override { return false; }
  void clear(SurfaceKey surface) override { cleared = surface; }
  void disconnect() override { disconnected = true; }
  bool submit(const InputEvent &event) override {
    input = event;
    return true;
  }

  SurfaceKey configured{};
  SurfaceKey presented{};
  SurfaceKey cleared{};
  std::uint64_t sequence = 0;
  std::vector<std::byte> bytes;
  InputEvent input{};
  bool disconnected = false;
};

int main() {
  const auto allocation =
      make_allocation({.id = 10, .generation = 4}, 4, 4, 4, 4, 1, 1, 4096);
  require(allocation.has_value(), "fixture allocation failed");
  RecordingBridge bridge;
  std::vector<std::byte> pixels(allocation->frame_bytes, std::byte{0x33});
  require(bridge.configure(*allocation), "bridge configure failed");
  require(bridge.present(allocation->surface, 5, pixels),
          "bridge present failed");
  bridge.clear(allocation->surface);
  bridge.disconnect();
  require(bridge.configured == allocation->surface &&
              bridge.presented == allocation->surface &&
              bridge.cleared == allocation->surface && bridge.sequence == 5 &&
              bridge.bytes == pixels && bridge.disconnected,
          "trusted bridge call order/data changed");

  const InputEvent input{.surface = allocation->surface,
                         .sequence = 1,
                         .payload = PointerMotion{}};
  require(bridge.submit(input) && bridge.input.sequence == 1,
          "host input mock failed");
}
