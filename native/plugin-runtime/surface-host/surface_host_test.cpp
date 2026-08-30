#include "surface_host.hpp"

#include "omarchy/plugin_runtime/surface/profile.hpp"
#include "omarchy/plugin_runtime/surface/render_messages.hpp"

#include <QGuiApplication>

#include <cstdlib>
#include <memory>
#include <stdexcept>
#include <string>
#include <string_view>

namespace {

namespace bridge = omarchy::plugin_runtime::bridge;
namespace host = omarchy::plugin_runtime::surface_host;
namespace permissions = omarchy::plugins::permissions;
namespace render_session = omarchy::plugin_runtime::render_session;
namespace surface = omarchy::plugin_runtime::surface;
namespace wire = omarchy::plugin::wire;

void require(bool condition, std::string_view message) {
  if (!condition)
    throw std::runtime_error(std::string(message));
}

class PacketSender final : public render_session::PacketSender {
public:
  bool send(const wire::EnvelopeHeader &, std::span<const std::byte>,
            std::span<const int>) override {
    return true;
  }
};

class InputSink final : public bridge::RenderPacketSink {
public:
  bool send(const wire::EnvelopeHeader &, std::span<const std::byte>) override {
    ++calls;
    return true;
  }
  std::size_t calls = 0;
};

class InspectionAuthority final : public host::InspectionAuthority {
public:
  bool perform(host::InspectionAction, std::string_view, std::string_view,
               std::string_view) override {
    return true;
  }
};

class Clock final : public host::MonotonicClock {
public:
  std::uint64_t now_nanoseconds() const override { return 1'000'000'000; }
};

render_session::AuthenticatedRenderPacket
packet(std::uint16_t type, std::span<const std::byte> payload,
       std::uint64_t correlation) {
  return {.message_type = type,
          .correlation_id = correlation,
          .payload = payload};
}

struct Harness {
  explicit Harness(bool dynamic = true,
                   host::SurfaceRole role = host::SurfaceRole::desktop_overlay)
      : sink(std::make_shared<InputSink>()) {
    const permissions::ActivationBinding binding{
        .plugin = permissions::PluginId("org.example.regions"),
        .revision = permissions::Digest(std::string(64, 'a')),
        .policy_fingerprint = permissions::Digest(std::string(64, 'b')),
        .generation = generation,
    };
    surface_host = host::HostSurface::create(
        {.plugin_id = "org.example.regions",
         .surface_name = "pet",
         .role = role,
         .maximum_width = 64,
         .maximum_height = 32,
         .maximum_frames_per_second = 60,
         .keyboard_focus = host::KeyboardFocusPolicy::none,
         .dynamic_input_regions = dynamic},
        binding, surface_id, 64, 32, 1, 1, item, sender, sink, authority,
        clock);
    require(surface_host != nullptr, "host surface creation failed");

    const auto selection = surface::encode_profile_selection(
        {.version = surface::kSoftwareProfileVersion,
         .pixel_format = surface::kRgba8888Premultiplied});
    require(surface_host->receive_render(
                packet(static_cast<std::uint16_t>(
                           surface::RenderMessageType::profile_select),
                       selection, surface_id * 4 + 1)),
            "profile negotiation failed");
    const auto allocated =
        surface::encode_surface_key(surface_host->allocation().surface);
    require(surface_host->receive_render(
                packet(static_cast<std::uint16_t>(
                           surface::RenderMessageType::surface_allocated),
                       allocated, surface_id * 4 + 2)),
            "surface activation failed");
  }

  surface::InputRegionUpdate update(std::uint64_t region_generation = 1) {
    return {.surface = surface_host->allocation().surface,
            .generation = region_generation,
            .regions = {{{.x = 2, .y = 3, .width = 4, .height = 5}}},
            .count = 1};
  }

  bool receive(const surface::InputRegionUpdate &value) {
    const auto payload = surface::encode_input_region_update(value);
    return surface_host->receive_render(
        packet(static_cast<std::uint16_t>(
                   surface::RenderMessageType::input_regions),
               payload, 0));
  }

  static constexpr std::uint64_t generation = 7;
  static constexpr std::uint64_t surface_id = 71;
  bridge::RemotePluginSurface item;
  PacketSender sender;
  std::shared_ptr<InputSink> sink;
  InspectionAuthority authority;
  Clock clock;
  std::unique_ptr<host::HostSurface> surface_host;
};

void authenticated_input_regions_reach_the_single_policy_decision() {
  Harness accepted;
  require(accepted.receive(accepted.update()) &&
              accepted.item.inputRegions() ==
                  QList<QRect>{QRect(2, 3, 4, 5)} &&
              accepted.surface_host->inspection().input_region_count == 1,
          "authenticated input regions did not reach native policy");

  Harness rejected;
  auto invalid = rejected.update();
  invalid.regions[0].x = -1;
  require(!rejected.receive(invalid) &&
              rejected.surface_host->inspection().terminated &&
              !rejected.item.connected() &&
              rejected.item.inputRegions().isEmpty(),
          "invalid authenticated input regions did not fail closed");
}

void accepted_regions_are_one_enforcement_and_projection_decision() {
  Harness harness;
  const auto accepted = harness.update();
  require(harness.item.updateInputRegions(accepted) &&
              harness.item.inputRegions() == QList<QRect>{QRect(2, 3, 4, 5)} &&
              harness.surface_host->inspection().input_region_count == 1,
          "accepted regions diverged between enforcement and projection");

  auto outside = surface::InputEvent{
      .surface = harness.surface_host->allocation().surface,
      .sequence = 1,
      .kind = surface::InputKind::pointer_button,
      .x_q16 = 1U << surface::kQ16FractionBits,
      .y_q16 = 1U << surface::kQ16FractionBits,
      .delta_x_q16 = 0,
      .delta_y_q16 = 0,
      .code = 1,
      .state = static_cast<std::uint32_t>(surface::ButtonState::pressed),
      .active_touch_points = 0};
  require(!harness.surface_host->route_input(outside, true),
          "point outside the projected region passed native hit testing");
  outside.x_q16 = 3U << surface::kQ16FractionBits;
  outside.y_q16 = 4U << surface::kQ16FractionBits;
  require(harness.surface_host->route_input(outside, true) &&
              harness.sink->calls == 2,
          "point inside the projected region failed native hit testing");

  auto cleared = harness.update(2);
  cleared.count = 0;
  require(harness.item.updateInputRegions(cleared) &&
              harness.item.inputRegions().isEmpty() &&
              harness.surface_host->inspection().input_region_count == 0,
          "accepted empty regions did not clear both trusted states");
}

void invalid_regions_preserve_last_accepted_state() {
  Harness harness;
  require(harness.item.updateInputRegions(harness.update()),
          "valid baseline regions were rejected");
  const auto expected = harness.item.inputRegions();

  auto negative = harness.update(2);
  negative.regions[0].x = -1;
  auto zero = harness.update(2);
  zero.regions[0].width = 0;
  auto outside = harness.update(2);
  outside.regions[0] = {.x = 63, .y = 31, .width = 2, .height = 2};
  auto too_many = harness.update(2);
  too_many.count = surface::kMaximumTransportedInputRegions + 1;
  auto wrong_surface = harness.update(2);
  wrong_surface.surface.id++;
  for (const auto &candidate :
       {negative, zero, outside, too_many, wrong_surface}) {
    require(!harness.item.updateInputRegions(candidate) &&
                harness.item.inputRegions() == expected &&
                harness.surface_host->inspection().input_region_count == 1,
            "invalid regions changed projected or enforced state");
  }
  require(!harness.item.updateInputRegions(harness.update()) &&
              harness.item.inputRegions() == expected,
          "stale regions changed the last accepted state");
}

void policy_and_lifetime_are_fail_closed() {
  Harness fixed(false);
  require(!fixed.item.updateInputRegions(fixed.update()) &&
              fixed.item.inputRegions().isEmpty() &&
              fixed.surface_host->inspection().input_region_count == 1,
          "fixed-region policy accepted a dynamic update");

  Harness bar(true, host::SurfaceRole::bar_embedded);
  require(bar.item.updateInputRegions(bar.update()) &&
              bar.item.inputRegions() == QList<QRect>{QRect(2, 3, 4, 5)},
          "bar surface did not use the same bounded native region policy");
  bar.surface_host.reset();
  require(bar.item.inputRegions().isEmpty() &&
              !bar.item.updateInputRegions(
                  {.surface = {.id = Harness::surface_id,
                               .generation = Harness::generation},
                   .generation = 2,
                   .count = 0}),
          "host destruction retained a route or projected regions");
}

} // namespace

int main(int argc, char **argv) {
  QGuiApplication application(argc, argv);
  (void)application;
  try {
    authenticated_input_regions_reach_the_single_policy_decision();
    accepted_regions_are_one_enforcement_and_projection_decision();
    invalid_regions_preserve_last_accepted_state();
    policy_and_lifetime_are_fail_closed();
    return EXIT_SUCCESS;
  } catch (const std::exception &failure) {
    qCritical("surface host test failed: %s", failure.what());
    return EXIT_FAILURE;
  }
}
