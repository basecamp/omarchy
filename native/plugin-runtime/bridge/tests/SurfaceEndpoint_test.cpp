#include "SurfaceEndpoint.h"

#include "omarchy/plugin_runtime/surface/profile.hpp"
#include "omarchy/plugin_runtime/surface/render_messages.hpp"
#include "surface_host.hpp"

#include <QCoreApplication>
#include <QMouseEvent>

#include <fcntl.h>
#include <unistd.h>

#include <cerrno>
#include <stdexcept>
#include <string>
#include <string_view>
#include <type_traits>
#include <utility>

namespace omarchy::plugin_runtime::bridge {

class SurfaceEndpointTestAccess final {
public:
  [[nodiscard]] static std::unique_ptr<SurfaceEndpoint>
  create(channel::SurfaceSessionPort &session,
         TrustedInputAuthority &input_authority,
         std::string declared_surface) {
    return std::unique_ptr<SurfaceEndpoint>(
        new SurfaceEndpoint(session, input_authority,
                            std::move(declared_surface)));
  }

  [[nodiscard]] static bool
  attach(SurfaceEndpoint &endpoint, RemotePluginSurface &surface,
         std::uint32_t logical_width, std::uint32_t logical_height,
         std::uint32_t dpr_numerator, std::uint32_t dpr_denominator,
         surface_host::MonotonicClock &clock) {
    return endpoint.attach(surface, logical_width, logical_height,
                           dpr_numerator, dpr_denominator, clock);
  }

  [[nodiscard]] static bool route_input(SurfaceEndpoint &endpoint,
                                        HostInputEvent event) {
    return endpoint.route(std::move(event));
  }

  [[nodiscard]] static bool cancel_input(SurfaceEndpoint &endpoint,
                                         std::uint64_t device) {
    return endpoint.cancel(device);
  }

  static void close(SurfaceEndpoint &endpoint) noexcept { endpoint.close(); }

  [[nodiscard]] static bool is_inert(const SurfaceEndpoint &endpoint) noexcept {
    return endpoint.state() == SurfaceEndpoint::State::inert;
  }

  [[nodiscard]] static bool
  is_active(const SurfaceEndpoint &endpoint) noexcept {
    return endpoint.state() == SurfaceEndpoint::State::active;
  }

  [[nodiscard]] static bool
  is_closing(const SurfaceEndpoint &endpoint) noexcept {
    return endpoint.state() == SurfaceEndpoint::State::closing;
  }
};

} // namespace omarchy::plugin_runtime::bridge

namespace {

namespace bridge = omarchy::plugin_runtime::bridge;
namespace channel = omarchy::plugin_runtime::channel;
namespace host = omarchy::plugin_runtime::host_session;
namespace permissions = omarchy::plugins::permissions;
namespace render = omarchy::plugin_runtime::render_session;
namespace surface = omarchy::plugin_runtime::surface;
namespace surface_host = omarchy::plugin_runtime::surface_host;
namespace wire = omarchy::plugin::wire;

static_assert(
    !std::is_constructible_v<bridge::SurfaceEndpoint,
                             channel::SurfaceSessionPort &, std::string>,
    "surface endpoint construction escaped its owner");

void require(bool condition, std::string_view message) {
  if (!condition)
    throw std::runtime_error(std::string(message));
}

permissions::ActivationBinding binding(std::uint64_t generation = 7) {
  return {.plugin = permissions::PluginId("org.example.endpoint"),
          .revision = permissions::Digest(std::string(64, 'a')),
          .policy_fingerprint = permissions::Digest(std::string(64, 'b')),
          .generation = generation};
}

struct SharedEligibility {
  std::optional<surface::SurfaceKey> source;
};

class Port final : public channel::SurfaceSessionPort {
public:
  explicit Port(std::string surface_name = "pet", std::uint64_t surface_id = 1,
                SharedEligibility *shared_eligibility = nullptr)
      : shared_eligibility(shared_eligibility) {
    description = {
        .binding = binding(),
        .key = {.id = surface_id, .generation = 7},
        .session_nonce = 41,
        .plugin_id = "org.example.endpoint",
        .surface_name = surface_name,
        .canonical_surfaces = "{\"" + surface_name +
                              "\":{\"keyboardFocus\":false,"
                              "\"maximumFramesPerSecond\":60,"
                              "\"maximumHeight\":32,\"maximumWidth\":64,"
                              "\"role\":\"desktop-overlay\"}}",
    };
  }

  std::optional<channel::SurfaceDescription>
  describe(std::string_view name) const noexcept override {
    if (fail_describe)
      return {};
    if (!running || name != description.surface_name)
      return {};
    return description;
  }

  bool attach(const channel::SurfaceDescription &expected,
              host::SurfaceEndpoint &candidate) noexcept override {
    ++attach_calls;
    if (!running || fail_attach || expected != description ||
        endpoint != nullptr)
      return false;
    endpoint = &candidate;
    attached_description = expected;
    return true;
  }

  bool detach(const channel::SurfaceDescription &expected,
              const host::SurfaceEndpoint &candidate) noexcept override {
    ++detach_calls;
    if (expected != description) {
      ++stale_detach_calls;
      return true;
    }
    if (endpoint != &candidate || !attached_description ||
        expected != *attached_description)
      return false;
    if (remote_at_detach != nullptr)
      remote_was_alive_at_detach = remote_at_detach->connected();
    endpoint = nullptr;
    attached_description.reset();
    return true;
  }

  bool arm_surface_intent(
      const channel::SurfaceDescription &expected,
      std::uint64_t sequence) noexcept override {
    ++arm_calls;
    last_arm_sequence = sequence;
    const bool accepted = running && expected == description && arm_succeeds;
    if (accepted && shared_eligibility != nullptr)
      shared_eligibility->source = expected.key;
    return accepted;
  }

  void clear_surface_intent_eligibility(
      const channel::SurfaceDescription &expected) noexcept override {
    if (expected == description) {
      ++clear_calls;
      if (shared_eligibility != nullptr &&
          shared_eligibility->source == expected.key)
        shared_eligibility->source.reset();
    } else {
      ++stale_clear_calls;
    }
  }

  bool deliver(std::uint16_t type, std::span<const std::byte> payload,
               std::uint64_t correlation, std::uint64_t generation = 7,
               std::vector<host::OwnedFd> descriptors = {}) {
    if (endpoint == nullptr)
      return false;
    return endpoint->receive({.launch_generation = generation,
                              .message_type = type,
                              .correlation = correlation,
                              .surface = std::nullopt,
                              .payload = {payload.begin(), payload.end()},
                              .descriptors = std::move(descriptors)});
  }

  void replace_session() {
    endpoint = nullptr;
    attached_description.reset();
    description.binding.generation = 8;
    description.key.generation = 8;
    description.session_nonce = 42;
  }

  bool send_render_packet_impl(
                               const channel::SurfaceDescription &expected,
                               const wire::EnvelopeHeader &header,
                               std::vector<std::byte> payload,
                               std::vector<host::OwnedFd> descriptors) noexcept override {
    if (expected != description)
      return false;
    ++send_calls;
    last_header = header;
    last_payload = std::move(payload);
    surface::InputEvent input;
    if (header.message_type == static_cast<std::uint16_t>(
                                   surface::RenderMessageType::input) &&
        surface::decode_input_event(last_payload, input))
      inputs.push_back(std::move(input));
    last_descriptor = -1;
    if (!descriptors.empty()) {
      if (descriptors.size() != 1)
        return false;
      last_descriptor = descriptors.front().get();
      descriptor_had_cloexec =
          (::fcntl(last_descriptor, F_GETFD) & FD_CLOEXEC) != 0;
    }
    return !send_fails || header.message_type != fail_message_type;
  }

  channel::SurfaceDescription description;
  std::optional<channel::SurfaceDescription> attached_description;
  host::SurfaceEndpoint *endpoint = nullptr;
  bridge::RemotePluginSurface *remote_at_detach = nullptr;
  wire::EnvelopeHeader last_header{};
  std::vector<std::byte> last_payload;
  std::vector<surface::InputEvent> inputs;
  int last_descriptor = -1;
  std::uint64_t last_arm_sequence = 0;
  std::size_t attach_calls = 0;
  std::size_t detach_calls = 0;
  std::size_t stale_detach_calls = 0;
  std::size_t send_calls = 0;
  std::size_t arm_calls = 0;
  std::size_t clear_calls = 0;
  std::size_t stale_clear_calls = 0;
  bool descriptor_had_cloexec = false;
  bool remote_was_alive_at_detach = false;
  bool running = true;
  bool arm_succeeds = true;
  bool send_fails = false;
  bool fail_attach = false;
  bool fail_describe = false;
  std::uint16_t fail_message_type = 0;
  SharedEligibility *shared_eligibility = nullptr;
};

class Clock final : public surface_host::MonotonicClock {
public:
  std::uint64_t now_nanoseconds() const override { return now; }
  std::uint64_t now = 1'000'000'000;
};

class RegionRouter final : public bridge::HostInputRegionRouter {
public:
  bool apply(const surface::InputRegionUpdate &) override { return true; }
};

class InputSink final : public bridge::RenderPacketSink {
public:
  bool send(const wire::EnvelopeHeader &,
            std::span<const std::byte>) override {
    return true;
  }
};

struct Harness {
  Harness()
      : endpoint(bridge::SurfaceEndpointTestAccess::create(
            port, input_authority, "pet")) {
    port.remote_at_detach = &remote;
  }

  void attach() {
    require(bridge::SurfaceEndpointTestAccess::attach(
                *endpoint, remote, 64, 32, 1, 1, clock),
            "surface endpoint attach failed");
    require(bridge::SurfaceEndpointTestAccess::is_active(*endpoint) &&
                port.send_calls == 1,
            "endpoint did not activate through profile offer");
  }

  void negotiate() {
    const auto selection = surface::encode_profile_selection(
        {.version = surface::kSoftwareProfileVersion,
         .pixel_format = surface::kRgba8888Premultiplied});
    require(port.deliver(static_cast<std::uint16_t>(
                             surface::RenderMessageType::profile_select),
                         selection, surface::render_correlations({.id = 1,
                                                                  .generation = 7})[0]),
            "profile selection failed");
    require(port.descriptor_had_cloexec,
            "frame descriptor lost CLOEXEC ownership");
    errno = 0;
    require(::fcntl(port.last_descriptor, F_GETFD) == -1 && errno == EBADF,
            "duplicated frame descriptor escaped the send attempt");
    const auto allocated = surface::encode_surface_key(port.description.key);
    require(port.deliver(static_cast<std::uint16_t>(
                             surface::RenderMessageType::surface_allocated),
                         allocated, surface::render_correlations(
                                        port.description.key)[1]),
            "surface allocation acknowledgement failed");
  }

  Port port;
  Clock clock;
  bridge::TrustedInputAuthority input_authority;
  bridge::RemotePluginSurface remote;
  std::unique_ptr<bridge::SurfaceEndpoint> endpoint;
};

void lifecycle_and_descriptor_contract() {
  Harness value;
  require(bridge::SurfaceEndpointTestAccess::is_inert(*value.endpoint),
          "endpoint did not begin inert");
  value.attach();
  require(!bridge::SurfaceEndpointTestAccess::attach(
              *value.endpoint, value.remote, 64, 32, 1, 1, value.clock),
          "endpoint allowed a double attach");
  value.negotiate();

  int descriptors[2] = {-1, -1};
  require(::pipe2(descriptors, O_CLOEXEC) == 0, "descriptor fixture failed");
  const int rejected = descriptors[0];
  std::vector<host::OwnedFd> owned;
  owned.emplace_back(rejected);
  require(!value.port.deliver(
              static_cast<std::uint16_t>(surface::RenderMessageType::frame_ready),
              {}, 0, 7, std::move(owned)),
          "descriptor-bearing worker message reached HostSurface");
  errno = 0;
  require(::fcntl(rejected, F_GETFD) == -1 && errno == EBADF,
          "rejected inbound descriptor was not closed");
  ::close(descriptors[1]);

  const auto sends_before_close = value.port.send_calls;
  bridge::SurfaceEndpointTestAccess::close(*value.endpoint);
  bridge::SurfaceEndpointTestAccess::close(*value.endpoint);
  require(bridge::SurfaceEndpointTestAccess::is_closing(*value.endpoint) &&
              value.port.detach_calls == 1 &&
              value.port.remote_was_alive_at_detach &&
              value.port.send_calls == sends_before_close + 1 &&
              !value.port.inputs.empty() &&
              std::holds_alternative<surface::Cancel>(
                  value.port.inputs.back().payload),
          "close did not detach before trusted surface teardown");
  require(value.port.detach_calls == 1,
          "endpoint close was not idempotent");
}

void stale_and_malformed_messages_fail_closed() {
  Harness stale;
  stale.attach();
  const auto selection = surface::encode_profile_selection(
      {.version = surface::kSoftwareProfileVersion,
       .pixel_format = surface::kRgba8888Premultiplied});
  require(!stale.port.deliver(
              static_cast<std::uint16_t>(surface::RenderMessageType::profile_select),
              selection, surface::render_correlations(stale.port.description.key)[0],
              8),
          "replacement generation reached the old endpoint");

  Harness correlation;
  correlation.attach();
  require(!correlation.port.deliver(
              static_cast<std::uint16_t>(surface::RenderMessageType::profile_select),
              selection, 999),
          "wrong render correlation was accepted");

  Harness type;
  type.attach();
  require(!type.port.deliver(0xffff, {}, 0),
          "unknown render type was accepted");
}

void gesture_arming_is_exact_and_send_failure_clears() {
  Harness accepted;
  accepted.attach();
  accepted.negotiate();
  const bridge::HostInputEvent accepted_press{
      .payload = surface::PointerButton{
          .position = {1U << surface::kQ16FractionBits,
                       1U << surface::kQ16FractionBits},
          .button = static_cast<std::uint32_t>(Qt::LeftButton),
          .state = surface::ButtonState::pressed,
          .buttons = static_cast<std::uint32_t>(Qt::LeftButton)},
      .device = 6,
      .trusted_physical = true};
  require(bridge::SurfaceEndpointTestAccess::route_input(
              *accepted.endpoint, accepted_press) &&
              accepted.port.arm_calls == 1 &&
              accepted.port.last_arm_sequence == 1 &&
              accepted.input_authority.surface_has_physical_activation(
                  accepted.port.description.key),
          "physical activation did not arm its exact admitted input");
  bridge::SurfaceEndpointTestAccess::close(*accepted.endpoint);
  require(!accepted.input_authority.surface_has_physical_activation(
              accepted.port.description.key) &&
              !accepted.port.inputs.empty() &&
              std::holds_alternative<surface::Cancel>(
                  accepted.port.inputs.back().payload) &&
              accepted.port.clear_calls >= 1,
          "endpoint teardown did not cancel input and clear its gesture");

  Harness terminal_failure;
  terminal_failure.attach();
  terminal_failure.negotiate();
  require(bridge::SurfaceEndpointTestAccess::route_input(
              *terminal_failure.endpoint, accepted_press) &&
              terminal_failure.port.arm_calls == 1 &&
              !terminal_failure.port.deliver(0xffff, {}, 0) &&
              !terminal_failure.remote.connected() &&
              !terminal_failure.input_authority
                   .surface_has_physical_activation(
                       terminal_failure.port.description.key) &&
              terminal_failure.port.inputs.size() == 2 &&
              std::holds_alternative<surface::Cancel>(
                  terminal_failure.port.inputs.back().payload) &&
              terminal_failure.port.clear_calls >= 1,
          "terminal render failure did not authenticate Cancel before release");

  Harness value;
  value.attach();
  value.negotiate();
  const bridge::HostInputEvent motion{
      .payload = surface::PointerMotion{
          .position = {1U << surface::kQ16FractionBits,
                       1U << surface::kQ16FractionBits}},
      .device = 7,
      .trusted_physical = true};
  require(bridge::SurfaceEndpointTestAccess::route_input(
              *value.endpoint, motion) &&
              value.port.arm_calls == 0,
          "non-press input armed surface intent authority");

  value.port.send_fails = true;
  value.port.fail_message_type =
      static_cast<std::uint16_t>(surface::RenderMessageType::input);
  const bridge::HostInputEvent press{
      .payload = surface::PointerButton{
          .position = {1U << surface::kQ16FractionBits,
                       1U << surface::kQ16FractionBits},
          .button = static_cast<std::uint32_t>(Qt::LeftButton),
          .state = surface::ButtonState::pressed,
          .buttons = static_cast<std::uint32_t>(Qt::LeftButton)},
      .device = 7,
      .trusted_physical = true};
  require(!bridge::SurfaceEndpointTestAccess::route_input(
              *value.endpoint, press) &&
              value.port.arm_calls == 1 && value.port.last_arm_sequence == 2 &&
              value.port.clear_calls == 1,
          "failed trusted press retained gesture eligibility");

  Harness touch;
  touch.attach();
  touch.negotiate();
  const bridge::HostInputEvent start{
      .payload = bridge::HostTouchFrame{
          .phase = surface::TouchFramePhase::begin,
          .points = {{{.id = 91,
                       .state = surface::TouchPointState::pressed,
                       .position = {1U << surface::kQ16FractionBits,
                                    1U << surface::kQ16FractionBits}}}},
          .count = 1},
      .device = 8,
      .trusted_physical = true};
  require(bridge::SurfaceEndpointTestAccess::route_input(
              *touch.endpoint, start) && touch.port.arm_calls == 1,
          "touch-start gesture was not armed at its exact input packet");
  require(bridge::SurfaceEndpointTestAccess::cancel_input(*touch.endpoint, 8) &&
              touch.port.clear_calls == 1,
          "exact Cancel did not revoke the surface intent eligibility");
}

void remote_destruction_detaches_while_cpp_object_is_alive() {
  Port port;
  bridge::TrustedInputAuthority input_authority;
  Clock clock;
  auto endpoint = bridge::SurfaceEndpointTestAccess::create(
      port, input_authority, "pet");
  {
    bridge::RemotePluginSurface remote;
    port.remote_at_detach = &remote;
    require(bridge::SurfaceEndpointTestAccess::attach(
                *endpoint, remote, 64, 32, 1, 1, clock),
            "destruction-order fixture did not attach");
  }
  require(bridge::SurfaceEndpointTestAccess::is_closing(*endpoint) &&
              port.detach_calls == 1 && port.remote_was_alive_at_detach,
          "remote C++ destruction did not fence its endpoint first");
}

void attach_rolls_back_every_published_owner() {
  Port port;
  bridge::TrustedInputAuthority input_authority;
  Clock clock;
  bridge::RemotePluginSurface remote;
  auto endpoint = bridge::SurfaceEndpointTestAccess::create(
      port, input_authority, "pet");
  port.fail_describe = true;
  require(!bridge::SurfaceEndpointTestAccess::attach(
              *endpoint, remote, 64, 32, 1, 1, clock),
          "failed surface description escaped endpoint attach");
  port.fail_describe = false;
  port.fail_attach = true;
  require(!bridge::SurfaceEndpointTestAccess::attach(
              *endpoint, remote, 64, 32, 1, 1, clock) &&
              bridge::SurfaceEndpointTestAccess::is_inert(*endpoint),
          "failed transactional session attach escaped endpoint rollback");
  port.fail_attach = false;
  require(bridge::SurfaceEndpointTestAccess::attach(
              *endpoint, remote, 64, 32, 1, 1, clock),
          "rollback retained a Remote observer or pointer router");
  bridge::SurfaceEndpointTestAccess::close(*endpoint);

  Port bounds_port;
  bridge::TrustedInputAuthority bounds_input_authority;
  bridge::RemotePluginSurface bounds_remote;
  auto bounds = bridge::SurfaceEndpointTestAccess::create(
      bounds_port, bounds_input_authority, "pet");
  require(!bridge::SurfaceEndpointTestAccess::attach(
              *bounds, bounds_remote, 65, 32, 1, 1, clock) &&
              bounds_port.detach_calls == 1 && bounds_port.send_calls == 0 &&
              bridge::SurfaceEndpointTestAccess::attach(
                  *bounds, bounds_remote, 64, 32, 1, 1, clock),
          "HostSurface allocation failure retained published endpoint state");
  bridge::SurfaceEndpointTestAccess::close(*bounds);

  Port router_port;
  bridge::TrustedInputAuthority router_input_authority;
  bridge::RemotePluginSurface router_remote;
  RegionRouter occupied;
  require(router_remote.bindHostInputRegionRouter(occupied),
          "occupied region-router fixture did not bind");
  auto router_endpoint = bridge::SurfaceEndpointTestAccess::create(
      router_port, router_input_authority, "pet");
  require(!bridge::SurfaceEndpointTestAccess::attach(
              *router_endpoint, router_remote, 64, 32, 1, 1, clock) &&
              router_port.detach_calls == 1 && router_port.send_calls == 0,
          "failed HostSurface construction emitted a stale profile offer");
  QMouseEvent rejected_press(
      QEvent::MouseButtonPress, QPointF(1, 1), QPointF(1, 1), QPointF(1, 1),
      Qt::LeftButton, Qt::LeftButton, Qt::NoModifier,
      Qt::MouseEventNotSynthesized);
  QCoreApplication::sendEvent(&router_remote, &rejected_press);
  require(!rejected_press.isAccepted(),
          "failed HostSurface retained an input transport/router");
  router_remote.unbindHostInputRegionRouter(occupied);
  require(bridge::SurfaceEndpointTestAccess::attach(
              *router_endpoint, router_remote, 64, 32, 1, 1, clock),
          "failed HostSurface retained transport state across safe reuse");
  bridge::SurfaceEndpointTestAccess::close(*router_endpoint);

  Port transport_port;
  bridge::TrustedInputAuthority transport_input_authority;
  bridge::RemotePluginSurface transport_remote;
  auto transport_endpoint = bridge::SurfaceEndpointTestAccess::create(
      transport_port, transport_input_authority, "pet");
  auto occupied_sink = std::make_shared<InputSink>();
  auto occupied_transport =
      std::make_shared<bridge::AuthenticatedInputTransport>(99,
                                                            occupied_sink);
  require(transport_remote.bindTransport(occupied_transport) &&
              !bridge::SurfaceEndpointTestAccess::attach(
                  *transport_endpoint, transport_remote, 64, 32, 1, 1,
                  clock) &&
              occupied_transport->connected() &&
              transport_port.detach_calls == 1 &&
              transport_port.send_calls == 0,
          "occupied Remote transport was replaced or emitted a profile");
  transport_remote.unbindTransport(occupied_transport);
  require(bridge::SurfaceEndpointTestAccess::attach(
              *transport_endpoint, transport_remote, 64, 32, 1, 1, clock),
          "occupied transport rejection prevented safe Remote reuse");
  bridge::SurfaceEndpointTestAccess::close(*transport_endpoint);
}

void remote_pointer_events_reach_the_exact_input_path() {
  Harness value;
  value.attach();
  value.negotiate();
  const auto before = value.port.send_calls;
  QMouseEvent press(QEvent::MouseButtonPress, QPointF(1.25, 2.5),
                    QPointF(1.25, 2.5), QPointF(1.25, 2.5), Qt::LeftButton,
                    Qt::LeftButton, Qt::NoModifier,
                    Qt::MouseEventNotSynthesized);
  QCoreApplication::sendEvent(&value.remote, &press);
  QMouseEvent release(QEvent::MouseButtonRelease, QPointF(1.25, 2.5),
                      QPointF(1.25, 2.5), QPointF(1.25, 2.5), Qt::LeftButton,
                      Qt::NoButton, Qt::NoModifier,
                      Qt::MouseEventNotSynthesized);
  QCoreApplication::sendEvent(&value.remote, &release);
  require(press.isAccepted() && release.isAccepted() &&
              value.port.arm_calls == 0 &&
              value.port.send_calls == before + 2,
          "Remote pointer press/release did not traverse the trusted endpoint");

  const auto after_release = value.port.send_calls;
  QMouseEvent outside(QEvent::MouseButtonPress, QPointF(64, 2),
                      QPointF(64, 2), QPointF(64, 2), Qt::LeftButton,
                      Qt::LeftButton, Qt::NoModifier,
                      Qt::MouseEventNotSynthesized);
  QCoreApplication::sendEvent(&value.remote, &outside);
  QMouseEvent synthesized(
      QEvent::MouseButtonPress, QPointF(2, 2), QPointF(2, 2), QPointF(2, 2),
      Qt::LeftButton, Qt::LeftButton, Qt::NoModifier,
      Qt::MouseEventSynthesizedByApplication);
  QCoreApplication::sendEvent(&value.remote, &synthesized);
  require(!outside.isAccepted() && synthesized.isAccepted() &&
              value.port.send_calls == after_release + 1 &&
              value.port.arm_calls == 0 &&
              !value.input_authority.surface_has_physical_activation(
                  value.port.description.key) &&
              !value.remote.surfaceFocused(),
          "synthetic input minted gesture authority or hit testing diverged");
}

void sibling_gesture_survives_unrelated_endpoint_teardown() {
  SharedEligibility eligibility;
  Port first_port("first", 11, &eligibility);
  Port second_port("second", 12, &eligibility);
  bridge::TrustedInputAuthority input_authority;
  Clock clock;
  bridge::RemotePluginSurface first_remote;
  bridge::RemotePluginSurface second_remote;
  auto first = bridge::SurfaceEndpointTestAccess::create(
      first_port, input_authority, "first");
  auto second = bridge::SurfaceEndpointTestAccess::create(
      second_port, input_authority, "second");
  require(bridge::SurfaceEndpointTestAccess::attach(
              *first, first_remote, 64, 32, 1, 1, clock) &&
              bridge::SurfaceEndpointTestAccess::attach(
                  *second, second_remote, 64, 32, 1, 1, clock),
          "sibling endpoint fixture did not attach");
  const auto negotiate = [](Port &port) {
    const auto selection = surface::encode_profile_selection(
        {.version = surface::kSoftwareProfileVersion,
         .pixel_format = surface::kRgba8888Premultiplied});
    const auto correlations =
        surface::render_correlations(port.description.key);
    const auto allocated = surface::encode_surface_key(port.description.key);
    return port.deliver(
               static_cast<std::uint16_t>(
                   surface::RenderMessageType::profile_select),
               selection, correlations[0]) &&
           port.deliver(static_cast<std::uint16_t>(
                            surface::RenderMessageType::surface_allocated),
                        allocated, correlations[1]);
  };
  require(negotiate(first_port) && negotiate(second_port),
          "sibling endpoint fixture did not negotiate");
  const bridge::HostInputEvent second_press{
      .payload = surface::PointerButton{
          .position = {1U << surface::kQ16FractionBits,
                       1U << surface::kQ16FractionBits},
          .button = static_cast<std::uint32_t>(Qt::LeftButton),
          .state = surface::ButtonState::pressed,
          .buttons = static_cast<std::uint32_t>(Qt::LeftButton)},
      .device = 55,
      .trusted_physical = true};
  require(bridge::SurfaceEndpointTestAccess::route_input(*second,
                                                         second_press) &&
              eligibility.source == second_port.description.key,
          "sibling physical activation did not arm its source");
  bridge::SurfaceEndpointTestAccess::close(*first);
  require(eligibility.source == second_port.description.key &&
              first_port.clear_calls >= 1 && second_port.clear_calls == 0,
          "unrelated endpoint teardown erased sibling eligibility");
  bridge::SurfaceEndpointTestAccess::close(*second);
  require(!eligibility.source && second_port.clear_calls >= 1,
          "exact sibling teardown retained its eligibility");
}

void late_g1_remote_teardown_cannot_touch_g2() {
  Port port;
  bridge::TrustedInputAuthority input_authority;
  Clock clock;
  auto endpoint = bridge::SurfaceEndpointTestAccess::create(
      port, input_authority, "pet");
  {
    bridge::RemotePluginSurface remote;
    require(bridge::SurfaceEndpointTestAccess::attach(
                *endpoint, remote, 64, 32, 1, 1, clock),
            "late G1 teardown fixture did not attach");
    port.replace_session();
  }
  require(bridge::SurfaceEndpointTestAccess::is_closing(*endpoint) &&
              port.stale_clear_calls >= 1 && port.clear_calls == 0 &&
              port.stale_detach_calls == 1,
          "late G1 teardown cleared or detached the replacement session");
}

} // namespace

void run_surface_endpoint_tests() {
  lifecycle_and_descriptor_contract();
  stale_and_malformed_messages_fail_closed();
  gesture_arming_is_exact_and_send_failure_clears();
  remote_destruction_detaches_while_cpp_object_is_alive();
  attach_rolls_back_every_published_owner();
  remote_pointer_events_reach_the_exact_input_path();
  sibling_gesture_survives_unrelated_endpoint_teardown();
  late_g1_remote_teardown_cannot_touch_g2();
}
