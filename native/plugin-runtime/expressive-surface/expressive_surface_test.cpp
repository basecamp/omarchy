#include "expressive_surface.hpp"

#include "omarchy/plugin/wire/envelope.hpp"
#include "omarchy/plugin_runtime/surface/render_messages.hpp"
#include "worker_runtime.hpp"

#include <QEventLoop>
#include <QGuiApplication>
#include <QImage>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QTimer>

#include <fcntl.h>
#include <unistd.h>

#include <array>
#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <memory>
#include <span>
#include <stdexcept>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace {

namespace bridge = omarchy::plugin_runtime::bridge;
namespace expressive = omarchy::plugin_runtime::expressive_surface;
namespace host = omarchy::plugin_runtime::surface_host;
namespace manifest = omarchy::plugins::manifest;
namespace permissions = omarchy::plugins::permissions;
namespace session = omarchy::plugin_runtime::render_session;
namespace surface = omarchy::plugin_runtime::surface;
namespace wire = omarchy::plugin::wire;
namespace worker = omarchy::plugin_runtime::worker;

constexpr std::uint64_t kGeneration = 71;
const std::string kRevision(64, 'a');
const std::string kPolicy(64, 'b');
const std::filesystem::path kPetRoot{E2_PET_FIXTURE_ROOT};

void require(bool condition, std::string_view message) {
  if (!condition)
    throw std::runtime_error(std::string(message));
}

std::string read_text(const std::filesystem::path &path) {
  std::ifstream input(path, std::ios::binary);
  require(input.good(), "fixture could not be opened");
  return {std::istreambuf_iterator<char>(input),
          std::istreambuf_iterator<char>()};
}

std::vector<std::byte> encode(const wire::EnvelopeHeader &header,
                              std::span<const std::byte> payload) {
  std::vector<std::byte> output(wire::kHeaderSize + payload.size());
  const auto encoded = wire::encode_packet(header, payload, output);
  require(static_cast<bool>(encoded), "envelope encoding failed");
  output.resize(encoded.bytes_written);
  return output;
}

wire::EnvelopeHeader worker_header(std::uint16_t type, std::size_t size,
                                   std::uint64_t correlation = 0) {
  return {.endpoint_role = wire::EndpointRole::render,
          .message_type = type,
          .role_protocol_version = surface::kRenderRoleVersion,
          .flags = 0,
          .payload_length = static_cast<std::uint32_t>(size),
          .launch_generation = kGeneration,
          .correlation_id = correlation};
}

class Sender final : public session::PacketSender {
public:
  ~Sender() override {
    if (descriptor_ >= 0)
      close(descriptor_);
  }
  bool send(const wire::EnvelopeHeader &header,
            std::span<const std::byte> payload,
            std::span<const int> descriptors) override {
    if (descriptors.size() > 1)
      return false;
    if (!descriptors.empty()) {
      if (descriptor_ >= 0)
        return false;
      descriptor_ = fcntl(descriptors.front(), F_DUPFD_CLOEXEC, 64);
      if (descriptor_ < 0)
        return false;
    }
    headers.push_back(header);
    payloads.emplace_back(payload.begin(), payload.end());
    return true;
  }
  int take_descriptor() { return std::exchange(descriptor_, -1); }
  std::vector<wire::EnvelopeHeader> headers;
  std::vector<std::vector<std::byte>> payloads;

private:
  int descriptor_ = -1;
};

class WorkerSink final : public bridge::RenderPacketSink {
public:
  explicit WorkerSink(worker::WorkerRuntime &runtime) : runtime_(runtime) {}
  bool send(const wire::EnvelopeHeader &header,
            std::span<const std::byte> payload) override {
    if (header.message_type ==
        static_cast<std::uint16_t>(surface::RenderMessageType::focus)) {
      surface::FocusEvent event{};
      if (!surface::decode_focus_event(payload, event))
        return false;
      focus.push_back(event);
      return static_cast<bool>(runtime_.focus(event));
    }
    if (header.message_type ==
        static_cast<std::uint16_t>(surface::RenderMessageType::input)) {
      surface::InputEvent event{};
      if (!surface::decode_input_event(payload, event))
        return false;
      input.push_back(event);
      return static_cast<bool>(runtime_.input(event));
    }
    return false;
  }
  std::vector<surface::FocusEvent> focus;
  std::vector<surface::InputEvent> input;

private:
  worker::WorkerRuntime &runtime_;
};

class Inspector final : public host::InspectionAuthority {
public:
  bool perform(host::InspectionAction, std::string_view, std::string_view,
               std::string_view) override {
    return true;
  }
};

class Clock final : public host::MonotonicClock {
public:
  std::uint64_t now_nanoseconds() const override { return now; }
  std::uint64_t now = 1'000'000'000ULL;
};

permissions::ActivationBinding binding() {
  return {.plugin = permissions::PluginId("org.omarchy.fixture.pet"),
          .revision = permissions::Digest(kRevision),
          .policy_fingerprint = permissions::Digest(kPolicy),
          .generation = kGeneration};
}

struct Harness {
  Harness()
      : runtime(kPetRoot), input_sink(std::make_shared<WorkerSink>(runtime)) {
    const auto parsed =
        manifest::parse_manifest_v2(read_text(kPetRoot / "manifest.json"));
    policy = host::parse_named_surface_policy(parsed, "pet");
    require(static_cast<bool>(runtime.load_manifest_entry()),
            "C10 pet did not load in the arbitrary-QML worker");
    hosted =
        host::HostSurface::create(policy, binding(), 171, 320, 180, 1, 1, item,
                                  sender, input_sink, inspector, clock);
    require(hosted != nullptr && sender.headers.size() == 1,
            "D3 pet surface did not start D2 negotiation");
  }

  void negotiate() {
    surface::ProfileOffer offer{};
    require(surface::decode_profile_offer(sender.payloads.at(0), offer) &&
                static_cast<bool>(runtime.select_software_profile(offer)),
            "worker rejected the host software profile");
    const auto selected =
        surface::select_software_profile(std::array{offer.version});
    require(selected.has_value(), "host software profile disappeared");
    const auto selection = surface::encode_profile_selection(*selected);
    require(hosted->receive_render(encode(
                worker_header(static_cast<std::uint16_t>(
                                  surface::RenderMessageType::profile_select),
                              selection.size(), 1),
                selection)) &&
                sender.payloads.size() == 2,
            "D2 allocation was not issued");
    surface::TrustedAllocation allocation{};
    const auto page_size = sysconf(_SC_PAGESIZE);
    require(page_size > 0 &&
                surface::decode_surface_allocation(
                    sender.payloads.at(1),
                    static_cast<std::uint64_t>(page_size), allocation) &&
                allocation == hosted->allocation() &&
                static_cast<bool>(
                    runtime.allocate(allocation, sender.take_descriptor())),
            "worker rejected the host-owned allocation");
    const auto acknowledged = surface::encode_surface_key(allocation.surface);
    require(
        hosted->receive_render(encode(
            worker_header(static_cast<std::uint16_t>(
                              surface::RenderMessageType::surface_allocated),
                          acknowledged.size(), 2),
            acknowledged)),
        "surface allocation acknowledgement failed");
  }

  bool render() {
    const auto frame = runtime.render();
    require(frame.has_value(), "arbitrary QML did not render");
    const auto payload = surface::encode_frame_ready(frame->ready);
    return hosted->receive_render(
        encode(worker_header(static_cast<std::uint16_t>(
                                 surface::RenderMessageType::frame_ready),
                             payload.size()),
               payload));
  }

  host::NamedSurfacePolicy policy;
  worker::WorkerRuntime runtime;
  std::shared_ptr<WorkerSink> input_sink;
  Sender sender;
  Inspector inspector;
  Clock clock;
  bridge::RemotePluginSurface item;
  std::unique_ptr<host::HostSurface> hosted;
};

surface::InputEvent pointer(surface::SurfaceKey key, std::uint64_t sequence,
                            std::uint32_t x, std::uint32_t y,
                            surface::ButtonState state) {
  return {.surface = key,
          .sequence = sequence,
          .kind = surface::InputKind::pointer_button,
          .x_q16 = x << surface::kQ16FractionBits,
          .y_q16 = y << surface::kQ16FractionBits,
          .delta_x_q16 = 0,
          .delta_y_q16 = 0,
          .code = 1,
          .state = static_cast<std::uint32_t>(state),
          .active_touch_points = 0};
}

surface::InputEvent touch(surface::SurfaceKey key, std::uint64_t sequence,
                          std::uint32_t x, std::uint32_t y, std::uint32_t state,
                          std::uint32_t active_points) {
  return {.surface = key,
          .sequence = sequence,
          .kind = surface::InputKind::touch,
          .x_q16 = x << surface::kQ16FractionBits,
          .y_q16 = y << surface::kQ16FractionBits,
          .delta_x_q16 = 0,
          .delta_y_q16 = 0,
          .code = 1,
          .state = state,
          .active_touch_points = active_points};
}

surface::InputEvent key(surface::SurfaceKey key, std::uint64_t sequence) {
  return {.surface = key,
          .sequence = sequence,
          .kind = surface::InputKind::key,
          .x_q16 = 0,
          .y_q16 = 0,
          .delta_x_q16 = 0,
          .delta_y_q16 = 0,
          .code = 30,
          .state = static_cast<std::uint32_t>(surface::ButtonState::pressed),
          .active_touch_points = 0};
}

void expressive_pet_composition() {
  QQmlEngine engine;
  QQmlComponent component(&engine, QUrl::fromLocalFile(QString::fromStdString(
                                       (kPetRoot / "ui/Pet.qml").string())));
  require(component.isReady(), "C10 pet QML did not compile");
  std::unique_ptr<QObject> scene(component.create());
  require(scene != nullptr, "C10 pet QML did not instantiate");
  const auto initial_x = scene->property("petX").toReal();
  require(scene->setProperty("walking", true),
          "pet animation property was unavailable");
  QEventLoop animation_loop;
  QTimer::singleShot(100, &animation_loop, &QEventLoop::quit);
  animation_loop.exec();
  require(scene->property("petX").toReal() != initial_x,
          "arbitrary C10 NumberAnimation did not advance");

  Harness harness;
  harness.negotiate();
  require(harness.render(), "first pet frame was rejected");
  const QImage first = harness.item.ownedImage();
  bool transparent = false;
  bool visible = false;
  for (int y = 0; y < first.height(); ++y) {
    for (int x = 0; x < first.width(); ++x) {
      const auto alpha = first.pixelColor(x, y).alpha();
      transparent = transparent || alpha == 0;
      visible = visible || alpha > 0;
    }
  }
  require(transparent && visible,
          "composited arbitrary QML lost transparent or visible pixels");

  const auto surface_key = harness.hosted->allocation().surface;
  require(
      harness.hosted->set_input_regions({}) &&
          !harness.hosted->route_input(
              pointer(surface_key, 1, 30, 120, surface::ButtonState::pressed),
              true),
      "empty region was not fully click-through");
  const std::array regions{
      host::InputRegion{.x = 20, .y = 104, .width = 76, .height = 58},
      host::InputRegion{.x = 260, .y = 8, .width = 12, .height = 12}};
  require(
      harness.hosted->set_input_regions(regions) &&
          !harness.hosted->route_input(
              pointer(surface_key, 1, 200, 80, surface::ButtonState::pressed),
              true) &&
          harness.hosted->route_input(
              pointer(surface_key, 1, 30, 120, surface::ButtonState::pressed),
              true) &&
          harness.hosted->route_input(
              pointer(surface_key, 2, 200, 80, surface::ButtonState::released),
              false),
      "irregular pointer clipping or exact capture lifecycle failed");

  require(
      harness.hosted->route_input(touch(surface_key, 3, 30, 120, 1, 1), true) &&
          harness.hosted->route_input(touch(surface_key, 4, 200, 80, 2, 1),
                                      false) &&
          harness.hosted->route_input(touch(surface_key, 5, 200, 80, 3, 0),
                                      false) &&
          !harness.hosted->route_input(key(surface_key, 6), false) &&
          harness.input_sink->input.size() == 5 &&
          harness.input_sink->focus.size() == 4 &&
          harness.input_sink->focus.front().focused &&
          !harness.input_sink->focus.back().focused &&
          !harness.hosted->inspection().focused &&
          !harness.item.surfaceFocused() && !harness.runtime.focused(),
      "pointer/touch capture accidentally retained keyboard focus");

  require(!harness.render() && harness.hosted->inspection().pace_drops == 1 &&
              harness.item.ownedImage() == first,
          "above-30-FPS frame consumed trusted compositing work");
  harness.clock.now += 33'333'334ULL;
  require(harness.render() && harness.hosted->inspection().frame_sequence == 3,
          "frame at the host-owned FPS boundary was not admitted");
}

class FixedPlacement final : public expressive::PlacementAuthority {
public:
  std::optional<expressive::Placement> place(const host::NamedSurfacePolicy &,
                                             std::uint32_t,
                                             std::uint32_t) noexcept override {
    ++calls;
    return placement;
  }
  expressive::Placement placement{.monitor_id = 7, .x = 100, .y = 40};
  std::size_t calls = 0;
};

void host_owned_bounds() {
  const auto parsed =
      manifest::parse_manifest_v2(read_text(kPetRoot / "manifest.json"));
  const auto pet = host::parse_named_surface_policy(parsed, "pet");
  const std::array monitors{
      expressive::Monitor{.id = 7, .width = 1920, .height = 1080},
      expressive::Monitor{.id = 9, .width = 1280, .height = 720}};
  const std::array duplicate_monitors{
      expressive::Monitor{.id = 7, .width = 1920, .height = 1080},
      expressive::Monitor{.id = 7, .width = 1280, .height = 720}};
  require(!expressive::Registry::create(pet.plugin_id, duplicate_monitors),
          "ambiguous host monitor identity was accepted");
  auto registry = expressive::Registry::create(pet.plugin_id, monitors);
  require(registry.has_value(), "trusted monitor registry was rejected");
  FixedPlacement authority;
  const auto admitted = registry->admit(pet, 1, 320, 180, authority);
  require(admitted && admitted->monitor_id == 7 && admitted->x == 100 &&
              admitted->y == 40 &&
              admitted->layer == expressive::HostLayer::desktop_overlay &&
              admitted->keyboard_focus == host::KeyboardFocusPolicy::none &&
              admitted->maximum_frames_per_second == 30,
          "pet selected host monitor, placement, layer, focus, or FPS");
  require(!registry->admit(pet, 2, 361, 180, authority) &&
              !registry->admit(pet, 1, 320, 180, authority) &&
              authority.calls == 1,
          "invalid geometry or duplicate reached placement authority");
  auto crossed_plugin = pet;
  crossed_plugin.plugin_id = "org.omarchy.fixture.crossed";
  require(!registry->admit(crossed_plugin, 2, 320, 180, authority) &&
              authority.calls == 1,
          "cross-plugin surface reached placement authority");

  for (std::size_t index = 1; index < host::kMaximumSurfacesPerPlugin;
       ++index) {
    auto next = pet;
    next.surface_name = "pet" + std::to_string(index);
    require(registry->admit(next, index + 1, 320, 180, authority).has_value(),
            "host denied an in-budget expressive surface");
  }
  auto ninth = pet;
  ninth.surface_name = "ninth";
  require(registry->size() == host::kMaximumSurfacesPerPlugin &&
              !registry->admit(ninth, 99, 320, 180, authority) &&
              registry->close(1) && registry->size() == 7,
          "per-plugin surface count was not host bounded");
  authority.placement = {.monitor_id = 9, .x = 1200, .y = 700};
  require(!registry->admit(ninth, 99, 320, 180, authority),
          "surface escaped the selected monitor bounds");
  authority.placement = {.monitor_id = 99, .x = 0, .y = 0};
  require(!registry->admit(ninth, 99, 320, 180, authority),
          "unknown monitor placement was accepted");
}

} // namespace

int main(int argc, char **argv) {
  QGuiApplication application(argc, argv);
  try {
    expressive_pet_composition();
    host_owned_bounds();
  } catch (const std::exception &error) {
    std::cerr << "FAIL: " << error.what() << '\n';
    return 1;
  }
  return 0;
}
