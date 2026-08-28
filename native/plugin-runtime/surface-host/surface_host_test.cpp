#include "surface_host.hpp"

#include "omarchy/plugin/wire/envelope.hpp"
#include "omarchy/plugin_runtime/surface/render_messages.hpp"

#include <QGuiApplication>

#include <fcntl.h>
#include <sys/mman.h>
#include <unistd.h>

#include <array>
#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <memory>
#include <span>
#include <stdexcept>
#include <string>
#include <string_view>
#include <type_traits>
#include <utility>
#include <vector>

namespace {

namespace bridge = omarchy::plugin_runtime::bridge;
namespace host = omarchy::plugin_runtime::surface_host;
namespace manifest = omarchy::plugins::manifest;
namespace permissions = omarchy::plugins::permissions;
namespace session = omarchy::plugin_runtime::render_session;
namespace surface = omarchy::plugin_runtime::surface;
namespace wire = omarchy::plugin::wire;

const std::filesystem::path kFixtures{D3_PRODUCT_FIXTURE_ROOT};
const std::string kRevision(64, 'a');
const std::string kPolicyFingerprint(64, 'b');

static_assert(!std::is_base_of_v<QObject, host::HostSurface>);
static_assert(
    !std::is_pointer_v<decltype(host::InspectionSnapshot::surface_id)>);

void require(bool condition, std::string_view detail) {
  if (!condition)
    throw std::runtime_error(std::string(detail));
}

std::string read_text(const std::filesystem::path &path) {
  std::ifstream input(path, std::ios::binary);
  require(input.good(), "fixture file could not be opened");
  return {std::istreambuf_iterator<char>(input),
          std::istreambuf_iterator<char>()};
}

manifest::ManifestV2 fixture_manifest(std::string_view name) {
  return manifest::parse_manifest_v2(
      read_text(kFixtures / name / "manifest.json"));
}

std::vector<std::byte> encode(const wire::EnvelopeHeader &header,
                              std::span<const std::byte> payload) {
  std::vector<std::byte> output(wire::kHeaderSize + payload.size());
  const auto result = wire::encode_packet(header, payload, output);
  require(static_cast<bool>(result), "test packet encoding failed");
  output.resize(result.bytes_written);
  return output;
}

wire::EnvelopeHeader worker_header(std::uint16_t type, std::size_t size,
                                   std::uint64_t generation,
                                   std::uint64_t correlation = 0) {
  return {.endpoint_role = wire::EndpointRole::render,
          .message_type = type,
          .role_protocol_version = surface::kRenderRoleVersion,
          .flags = 0,
          .payload_length = static_cast<std::uint32_t>(size),
          .launch_generation = generation,
          .correlation_id = correlation};
}

class RenderSender final : public session::PacketSender {
public:
  ~RenderSender() override {
    if (worker_descriptor >= 0)
      close(worker_descriptor);
  }

  bool send(const wire::EnvelopeHeader &header,
            std::span<const std::byte> payload,
            std::span<const int> descriptors) override {
    if (descriptors.size() > 1)
      return false;
    if (!descriptors.empty() && fcntl(descriptors.front(), F_GETFD) < 0)
      return false;
    if (!descriptors.empty()) {
      if (worker_descriptor >= 0)
        return false;
      worker_descriptor = fcntl(descriptors.front(), F_DUPFD_CLOEXEC, 64);
      if (worker_descriptor < 0)
        return false;
    }
    headers.push_back(header);
    payloads.emplace_back(payload.begin(), payload.end());
    descriptor_counts.push_back(descriptors.size());
    return accept;
  }

  std::vector<wire::EnvelopeHeader> headers;
  std::vector<std::vector<std::byte>> payloads;
  std::vector<std::size_t> descriptor_counts;
  bool accept = true;
  int worker_descriptor = -1;
};

class InputSink final : public bridge::RenderPacketSink {
public:
  bool send(const wire::EnvelopeHeader &header,
            std::span<const std::byte> payload) override {
    headers.push_back(header);
    payloads.emplace_back(payload.begin(), payload.end());
    return accept;
  }

  std::vector<wire::EnvelopeHeader> headers;
  std::vector<std::vector<std::byte>> payloads;
  bool accept = true;
};

class Inspector final : public host::InspectionAuthority {
public:
  bool perform(host::InspectionAction action, std::string_view plugin_id,
               std::string_view revision_digest,
               std::string_view surface_name) override {
    actions.push_back(action);
    plugins.emplace_back(plugin_id);
    revisions.emplace_back(revision_digest);
    surfaces.emplace_back(surface_name);
    return accept;
  }

  std::vector<host::InspectionAction> actions;
  std::vector<std::string> plugins;
  std::vector<std::string> revisions;
  std::vector<std::string> surfaces;
  bool accept = true;
};

class Clock final : public host::MonotonicClock {
public:
  [[nodiscard]] std::uint64_t now_nanoseconds() const override { return now; }
  std::uint64_t now = 1;
};

permissions::ActivationBinding binding(std::string_view plugin,
                                       std::uint64_t generation) {
  return {.plugin = permissions::PluginId(plugin),
          .revision = permissions::Digest(kRevision),
          .policy_fingerprint = permissions::Digest(kPolicyFingerprint),
          .generation = generation};
}

struct Harness {
  Harness(host::NamedSurfacePolicy selected_policy, std::uint64_t generation,
          std::uint32_t width, std::uint32_t height,
          std::uint32_t dpr_numerator = 1, std::uint32_t dpr_denominator = 1)
      : policy(std::move(selected_policy)), generation(generation),
        input_sink(std::make_shared<InputSink>()) {
    hosted = host::HostSurface::create(
        policy, binding(policy.plugin_id, generation), generation + 100, width,
        height, dpr_numerator, dpr_denominator, item, render_sender, input_sink,
        inspector, clock);
    require(hosted != nullptr && render_sender.headers.size() == 1,
            "host surface did not start D2 profile negotiation");
  }

  void negotiate() {
    surface::ProfileOffer offer{};
    require(surface::decode_profile_offer(render_sender.payloads.at(0), offer),
            "profile offer fixture failed");
    const auto selection =
        surface::select_software_profile(std::array{offer.version});
    require(selection.has_value(), "software profile was unavailable");
    const auto selection_payload =
        surface::encode_profile_selection(*selection);
    require(hosted->receive_render(encode(
                worker_header(static_cast<std::uint16_t>(
                                  surface::RenderMessageType::profile_select),
                              selection_payload.size(), generation, 1),
                selection_payload)) &&
                render_sender.headers.size() == 2 &&
                render_sender.descriptor_counts.at(1) == 1,
            "named surface did not receive exact D2 allocation");
    const auto allocated =
        surface::encode_surface_key(hosted->allocation().surface);
    require(
        hosted->receive_render(encode(
            worker_header(static_cast<std::uint16_t>(
                              surface::RenderMessageType::surface_allocated),
                          allocated.size(), generation, 2),
            allocated)) &&
            hosted->inspection().render_active,
        "named surface did not become active");
  }

  bool publish(std::uint64_t slot_sequence, std::uint64_t frame_sequence,
               std::uint32_t slot = 0) {
    const auto &allocation = hosted->allocation();
    void *mapping = mmap(
        nullptr, static_cast<std::size_t>(allocation.mapping_bytes),
        PROT_READ | PROT_WRITE, MAP_SHARED, render_sender.worker_descriptor, 0);
    require(mapping != MAP_FAILED, "worker frame mapping failed");
    std::vector<std::byte> pixels(allocation.frame_bytes, std::byte{0x44});
    const auto published = surface::publish_frame(
        {static_cast<std::byte *>(mapping),
         static_cast<std::size_t>(allocation.mapping_bytes)},
        allocation, slot, slot_sequence, frame_sequence, pixels);
    require(munmap(mapping,
                   static_cast<std::size_t>(allocation.mapping_bytes)) == 0 &&
                published == surface::PublishResult::published,
            "worker frame publication failed");
    const surface::FrameReady ready{.surface = allocation.surface,
                                    .slot = slot,
                                    .slot_sequence = slot_sequence,
                                    .frame_sequence = frame_sequence};
    const auto payload = surface::encode_frame_ready(ready);
    return hosted->receive_render(
        encode(worker_header(static_cast<std::uint16_t>(
                                 surface::RenderMessageType::frame_ready),
                             payload.size(), generation),
               payload));
  }

  host::NamedSurfacePolicy policy;
  std::uint64_t generation;
  RenderSender render_sender;
  std::shared_ptr<InputSink> input_sink;
  Inspector inspector;
  Clock clock;
  bridge::RemotePluginSurface item;
  std::unique_ptr<host::HostSurface> hosted;
};

surface::InputEvent
pointer(surface::SurfaceKey key, std::uint64_t sequence, std::uint32_t x,
        std::uint32_t y,
        surface::ButtonState state = surface::ButtonState::pressed) {
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
                          std::uint32_t state,
                          std::uint32_t active_touch_points) {
  return {.surface = key,
          .sequence = sequence,
          .kind = surface::InputKind::touch,
          .x_q16 = 30U << surface::kQ16FractionBits,
          .y_q16 = 120U << surface::kQ16FractionBits,
          .delta_x_q16 = 0,
          .delta_y_q16 = 0,
          .code = 1,
          .state = state,
          .active_touch_points = active_touch_points};
}

surface::InputEvent key(surface::SurfaceKey surface_key,
                        std::uint64_t sequence) {
  return {.surface = surface_key,
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

void product_policy_mapping() {
  const auto pomodoro =
      host::parse_named_surface_policy(fixture_manifest("pomodoro"), "timer");
  const auto pet =
      host::parse_named_surface_policy(fixture_manifest("pet"), "pet");
  const auto status = host::parse_named_surface_policy(
      fixture_manifest("fake-status"), "statusPanel");
  require(pomodoro.role == host::SurfaceRole::bar_embedded &&
              pomodoro.maximum_width == 280 && pomodoro.maximum_height == 64 &&
              !pomodoro.dynamic_input_regions &&
              pet.role == host::SurfaceRole::desktop_overlay &&
              pet.dynamic_input_regions &&
              pet.keyboard_focus == host::KeyboardFocusPolicy::none &&
              status.role == host::SurfaceRole::panel &&
              status.keyboard_focus == host::KeyboardFocusPolicy::after_gesture,
          "C10 surface manifests did not map to bounded host roles");
}

void pomodoro_full_region_and_host_inspector() {
  Harness harness(
      host::parse_named_surface_policy(fixture_manifest("pomodoro"), "timer"),
      41, 252, 48);
  require(!harness.hosted->route_input(
              pointer(harness.hosted->allocation().surface, 1, 10, 10), true),
          "input reached a surface before D2 allocation acknowledgement");
  harness.negotiate();
  const auto surface_key = harness.hosted->allocation().surface;
  require(harness.hosted->route_input(pointer(surface_key, 1, 10, 10), true) &&
              harness.input_sink->headers.size() == 1 &&
              !harness.hosted->inspection().focused &&
              !harness.hosted->route_input(key(surface_key, 2), false),
          "bar gesture routing or keyboard denial failed");
  const auto snapshot = harness.hosted->inspection();
  require(snapshot.plugin_id == "org.omarchy.fixture.pomodoro" &&
              snapshot.revision_digest == kRevision &&
              snapshot.policy_fingerprint == kPolicyFingerprint &&
              snapshot.surface_name == "timer" &&
              snapshot.role == host::SurfaceRole::bar_embedded &&
              snapshot.logical_width == 252 && snapshot.logical_height == 48 &&
              snapshot.surface_id == 141 && snapshot.surface_generation == 41 &&
              snapshot.input_region_count == 1 && snapshot.visible &&
              snapshot.bridge_state == "ready",
          "inspection metadata was not host-derived and revision-bound");
  require(harness.hosted->perform_inspection_action(
              host::InspectionAction::open_permissions) &&
              harness.inspector.actions.size() == 1 &&
              harness.inspector.plugins.front() == snapshot.plugin_id &&
              harness.inspector.revisions.front() == kRevision,
          "host inspection action lost trusted identity");
  require(harness.hosted->perform_inspection_action(
              host::InspectionAction::terminate) &&
              harness.hosted->inspection().terminated &&
              !harness.hosted->inspection().visible &&
              !harness.item.connected() &&
              harness.inspector.actions.size() == 2,
          "host termination retained plugin pixels or input authority");
}

void pet_dynamic_regions_and_lock_denial() {
  Harness harness(
      host::parse_named_surface_policy(fixture_manifest("pet"), "pet"), 42, 320,
      180);
  harness.negotiate();
  const auto surface_key = harness.hosted->allocation().surface;
  require(!harness.hosted->route_input(pointer(surface_key, 1, 30, 120), true),
          "dynamic surface accepted input before a bounded region update");
  const std::array bad_regions{
      host::InputRegion{.x = 300, .y = 100, .width = 76, .height = 58}};
  const std::array pet_region{
      host::InputRegion{.x = 20, .y = 104, .width = 76, .height = 58}};
  require(
      !harness.hosted->set_input_regions(bad_regions) &&
          harness.hosted->set_input_regions(pet_region) &&
          !harness.hosted->route_input(pointer(surface_key, 1, 2, 2), true) &&
          harness.hosted->route_input(pointer(surface_key, 1, 30, 120), true) &&
          harness.hosted->route_input(
              pointer(surface_key, 2, 200, 50, surface::ButtonState::released),
              false) &&
          harness.hosted->route_input(touch(surface_key, 3, 1, 1), true) &&
          harness.hosted->route_input(touch(surface_key, 4, 2, 1), false) &&
          harness.hosted->route_input(touch(surface_key, 5, 3, 0), false) &&
          !harness.hosted->route_input(key(surface_key, 6), false) &&
          harness.input_sink->headers.size() == 5 &&
          !harness.hosted->inspection().focused,
      "pet input escaped or failed its host-clipped dynamic region");
  std::vector<host::InputRegion> excessive(host::kMaximumInputRegions + 1,
                                           pet_region.front());
  require(!harness.hosted->set_input_regions(excessive) &&
              harness.hosted->inspection().input_region_count == 1,
          "excess input regions replaced the last trusted region set");
  require(harness.hosted->set_input_regions({}) &&
              harness.hosted->inspection().input_region_count == 0 &&
              !harness.hosted->route_input(pointer(surface_key, 6, 30, 120),
                                           true) &&
              harness.hosted->set_input_regions(pet_region),
          "pet could not return to a fully click-through bounded surface");
  require(harness.hosted->set_locked(true) &&
              harness.hosted->inspection().locked &&
              !harness.hosted->inspection().visible &&
              !harness.hosted->inspection().focused &&
              !harness.hosted->route_input(pointer(surface_key, 6, 30, 120),
                                           true) &&
              harness.hosted->set_locked(false) &&
              harness.hosted->inspection().visible,
          "lock screen did not suspend visibility, focus, and input");
}

void panel_gesture_focus_and_failure_distinction() {
  Harness harness(host::parse_named_surface_policy(
                      fixture_manifest("fake-status"), "statusPanel"),
                  43, 420, 520, 3, 2);
  harness.negotiate();
  const auto surface_key = harness.hosted->allocation().surface;
  require(
      harness.hosted->inspection().dpr_numerator == 3 &&
          harness.hosted->inspection().dpr_denominator == 2 &&
          !harness.hosted->route_input(key(surface_key, 1), false) &&
          harness.hosted->route_input(pointer(surface_key, 1, 20, 20), true) &&
          harness.hosted->route_input(key(surface_key, 2), false),
      "after-gesture panel focus gate failed");

  const surface::FrameReady stale{.surface = surface_key,
                                  .slot = 0,
                                  .slot_sequence = 2,
                                  .frame_sequence = 1};
  const auto stale_payload = surface::encode_frame_ready(stale);
  require(!harness.hosted->receive_render(
              encode(worker_header(static_cast<std::uint16_t>(
                                       surface::RenderMessageType::frame_ready),
                                   stale_payload.size(), harness.generation),
                     stale_payload)) &&
              harness.hosted->inspection().render_active &&
              harness.hosted->inspection().visible,
          "nonfatal rejected frame tore down a healthy surface");

  std::vector<std::byte> malformed(wire::kHeaderSize, std::byte{0});
  require(!harness.hosted->receive_render(malformed) &&
              !harness.hosted->inspection().render_active &&
              !harness.hosted->inspection().visible &&
              !harness.hosted->inspection().focused &&
              !harness.item.connected(),
          "fatal render failure retained visibility, input, or focus");
}

void pacing_budget_and_clock_failure() {
  Harness harness(
      host::parse_named_surface_policy(fixture_manifest("pomodoro"), "timer"),
      44, 252, 48);
  harness.negotiate();
  harness.clock.now = 1'000'000'000ULL;
  require(harness.publish(2, 1, 0) && harness.item.frameSequence() == 1,
          "first frame did not enter the host pacing budget");
  require(!harness.publish(2, 2, 1) &&
              harness.hosted->inspection().render_active &&
              harness.hosted->inspection().pace_drops == 1 &&
              harness.item.frameSequence() == 1,
          "above-manifest frame rate consumed trusted copy/upload work");
  harness.clock.now += 33'333'334ULL;
  require(harness.publish(4, 3, 0) && harness.item.frameSequence() == 3,
          "frame at the 30 FPS boundary was not admitted");
  harness.clock.now = 1;
  require(!harness.publish(4, 4, 1) &&
              harness.hosted->inspection().terminated &&
              !harness.hosted->inspection().visible,
          "monotonic clock rollback did not fail closed");
}

void lock_negotiation_races_and_atomic_failure() {
  {
    Harness harness(
        host::parse_named_surface_policy(fixture_manifest("pomodoro"), "timer"),
        45, 252, 48);
    require(harness.hosted->set_locked(true) &&
                harness.hosted->inspection().locked &&
                !harness.hosted->inspection().visible,
            "lock did not latch during profile negotiation");
    surface::ProfileOffer offer{};
    require(surface::decode_profile_offer(harness.render_sender.payloads.at(0),
                                          offer),
            "lock-race profile offer failed");
    const auto selection =
        surface::select_software_profile(std::array{offer.version});
    require(selection.has_value(), "lock-race selection failed");
    const auto payload = surface::encode_profile_selection(*selection);
    require(!harness.hosted->receive_render(encode(
                worker_header(static_cast<std::uint16_t>(
                                  surface::RenderMessageType::profile_select),
                              payload.size(), harness.generation, 1),
                payload)) &&
                harness.render_sender.headers.size() == 1 &&
                harness.hosted->set_locked(false),
            "locked negotiation advanced or could not explicitly unlock");
    harness.negotiate();
  }
  {
    Harness harness(host::parse_named_surface_policy(
                        fixture_manifest("fake-status"), "statusPanel"),
                    46, 420, 520);
    surface::ProfileOffer offer{};
    require(surface::decode_profile_offer(harness.render_sender.payloads.at(0),
                                          offer),
            "allocation lock-race offer failed");
    const auto selection =
        surface::select_software_profile(std::array{offer.version});
    require(selection.has_value(), "allocation lock-race selection failed");
    const auto selected = surface::encode_profile_selection(*selection);
    require(harness.hosted->receive_render(encode(
                worker_header(static_cast<std::uint16_t>(
                                  surface::RenderMessageType::profile_select),
                              selected.size(), harness.generation, 1),
                selected)) &&
                harness.hosted->set_locked(true),
            "lock did not latch while allocation awaited acknowledgement");
    const auto allocated =
        surface::encode_surface_key(harness.hosted->allocation().surface);
    require(
        !harness.hosted->receive_render(encode(
            worker_header(static_cast<std::uint16_t>(
                              surface::RenderMessageType::surface_allocated),
                          allocated.size(), harness.generation, 2),
            allocated)) &&
            !harness.hosted->inspection().render_active &&
            harness.hosted->set_locked(false) &&
            harness.hosted->receive_render(
                encode(worker_header(
                           static_cast<std::uint16_t>(
                               surface::RenderMessageType::surface_allocated),
                           allocated.size(), harness.generation, 2),
                       allocated)),
        "allocation acknowledgement crossed the lock boundary");

    const auto surface_key = harness.hosted->allocation().surface;
    require(harness.hosted->route_input(pointer(surface_key, 1, 20, 20), true),
            "atomic lock fixture could not focus");
    harness.input_sink->accept = false;
    require(!harness.hosted->set_locked(true) &&
                harness.hosted->inspection().locked &&
                harness.hosted->inspection().terminated &&
                !harness.hosted->inspection().visible &&
                !harness.item.connected(),
            "failed focus-clear notification left the surface active");
  }
}

void hostile_policy_and_identity_inputs() {
  auto parsed = fixture_manifest("pet");
  parsed.canonical_surfaces =
      R"({"pet":{"role":"desktop-overlay","maximumWidth":360,"maximumHeight":220,"maximumFramesPerSecond":30,"lockScreenVisible":true}})";
  bool rejected_lock_visibility = false;
  try {
    static_cast<void>(host::parse_named_surface_policy(parsed, "pet"));
  } catch (const std::runtime_error &) {
    rejected_lock_visibility = true;
  }
  parsed.canonical_surfaces =
      R"({"pet":{"role":"compositor","maximumWidth":360,"maximumHeight":220,"maximumFramesPerSecond":30}})";
  bool rejected_compositor = false;
  try {
    static_cast<void>(host::parse_named_surface_policy(parsed, "pet"));
  } catch (const std::runtime_error &) {
    rejected_compositor = true;
  }
  parsed.canonical_surfaces =
      R"({"pet":{"role":"desktop-overlay","maximumWidth":360,"maximumHeight":220,"maximumFramesPerSecond":30,"zOrder":999}})";
  bool rejected_object_authority = false;
  try {
    static_cast<void>(host::parse_named_surface_policy(parsed, "pet"));
  } catch (const std::runtime_error &) {
    rejected_object_authority = true;
  }
  require(rejected_lock_visibility && rejected_compositor &&
              rejected_object_authority,
          "host accepted lock-screen, compositor, or z-order authority");

  const auto valid =
      host::parse_named_surface_policy(fixture_manifest("pomodoro"), "timer");
  RenderSender sender;
  auto input = std::make_shared<InputSink>();
  Inspector inspector;
  Clock clock;
  bridge::RemotePluginSurface item;
  auto invalid_revision = binding(valid.plugin_id, 1);
  invalid_revision.revision = permissions::Digest("not-a-digest");
  require(host::HostSurface::create(valid, invalid_revision, 1, 252, 48, 1, 1,
                                    item, sender, input, inspector,
                                    clock) == nullptr,
          "surface accepted an unbound revision identity");

  auto crossed_plugin = binding("org.omarchy.fixture.pet", 1);
  require(host::HostSurface::create(valid, crossed_plugin, 1, 252, 48, 1, 1,
                                    item, sender, input, inspector,
                                    clock) == nullptr,
          "surface accepted a crossed plugin activation binding");

  Harness generation(
      host::parse_named_surface_policy(fixture_manifest("pomodoro"), "timer"),
      47, 252, 48);
  generation.negotiate();
  require(!generation.hosted->route_input(
              pointer({.id = generation.hosted->allocation().surface.id,
                       .generation = 46},
                      1, 10, 10),
              true),
          "surface accepted a crossed launch generation");
}

} // namespace

int main(int argc, char **argv) {
  try {
    QGuiApplication application(argc, argv);
    product_policy_mapping();
    pomodoro_full_region_and_host_inspector();
    pet_dynamic_regions_and_lock_denial();
    panel_gesture_focus_and_failure_distinction();
    pacing_budget_and_clock_failure();
    lock_negotiation_races_and_atomic_failure();
    hostile_policy_and_identity_inputs();
    return 0;
  } catch (const std::exception &error) {
    qCritical("surface host test failed: %s", error.what());
    return 1;
  }
}
