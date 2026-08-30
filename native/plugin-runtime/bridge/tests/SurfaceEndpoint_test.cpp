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
#include <utility>

namespace {

namespace bridge = omarchy::plugin_runtime::bridge;
namespace channel = omarchy::plugin_runtime::channel;
namespace host = omarchy::plugin_runtime::host_session;
namespace permissions = omarchy::plugins::permissions;
namespace render = omarchy::plugin_runtime::render_session;
namespace surface = omarchy::plugin_runtime::surface;
namespace surface_host = omarchy::plugin_runtime::surface_host;
namespace wire = omarchy::plugin::wire;

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

class Port final : public channel::SurfaceSessionPort {
public:
  Port() {
    description = {
        .binding = binding(),
        .key = {.id = 1, .generation = 7},
        .session_nonce = 41,
        .plugin_id = "org.example.endpoint",
        .surface_name = "pet",
        .canonical_surfaces =
            R"({"pet":{"keyboardFocus":false,"maximumFramesPerSecond":60,"maximumHeight":32,"maximumWidth":64,"role":"desktop-overlay"}})",
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
    return running && expected == description && arm_succeeds;
  }

  void clear_surface_intent_eligibility(
      const channel::SurfaceDescription &expected) noexcept override {
    if (expected == description)
      ++clear_calls;
    else
      ++stale_clear_calls;
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
    if (header.message_type ==
            static_cast<std::uint16_t>(surface::RenderMessageType::focus) &&
        !saw_focus) {
      saw_focus = true;
      intent_after_focus_admitted = arm_calls != 0;
    }
    last_header = header;
    last_payload = std::move(payload);
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
  bool saw_focus = false;
  bool intent_after_focus_admitted = false;
  bool remote_was_alive_at_detach = false;
  bool running = true;
  bool arm_succeeds = true;
  bool send_fails = false;
  bool fail_attach = false;
  bool fail_describe = false;
  std::uint16_t fail_message_type = 0;
};

class Inspection final : public surface_host::InspectionAuthority {
public:
  bool perform(surface_host::InspectionAction, std::string_view,
               std::string_view, std::string_view) override {
    return true;
  }
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
  Harness() : endpoint(port, "pet") {
    port.remote_at_detach = &remote;
  }

  void attach() {
    require(endpoint.attach(remote, 64, 32, 1, 1, inspection, clock),
            "surface endpoint attach failed");
    require(endpoint.state() == bridge::SurfaceEndpoint::State::active &&
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
  Inspection inspection;
  Clock clock;
  bridge::RemotePluginSurface remote;
  bridge::SurfaceEndpoint endpoint;
};

void lifecycle_and_descriptor_contract() {
  Harness value;
  require(value.endpoint.state() ==
              bridge::SurfaceEndpoint::State::inert,
          "endpoint did not begin inert");
  value.attach();
  require(!value.endpoint.attach(value.remote, 64, 32, 1, 1,
                                 value.inspection, value.clock),
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
  value.endpoint.close();
  value.endpoint.close();
  require(value.endpoint.state() ==
              bridge::SurfaceEndpoint::State::closing &&
              value.port.detach_calls == 1 &&
              value.port.remote_was_alive_at_detach &&
              value.port.send_calls == sends_before_close,
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
  Harness value;
  value.attach();
  value.negotiate();
  const surface::InputEvent motion{.surface = value.port.description.key,
                                   .sequence = 1,
                                   .kind = surface::InputKind::pointer_motion,
                                   .x_q16 = 1U << surface::kQ16FractionBits,
                                   .y_q16 = 1U << surface::kQ16FractionBits,
                                   .delta_x_q16 = 0,
                                   .delta_y_q16 = 0,
                                   .code = 0,
                                   .state = 0,
                                   .active_touch_points = 0};
  require(value.endpoint.route_input(motion, false) &&
              value.port.arm_calls == 0,
          "non-press input armed surface intent authority");

  value.port.send_fails = true;
  value.port.fail_message_type =
      static_cast<std::uint16_t>(surface::RenderMessageType::input);
  const surface::InputEvent press{
      .surface = value.port.description.key,
      .sequence = 2,
      .kind = surface::InputKind::pointer_button,
      .x_q16 = 1U << surface::kQ16FractionBits,
      .y_q16 = 1U << surface::kQ16FractionBits,
      .delta_x_q16 = 0,
      .delta_y_q16 = 0,
      .code = 1,
      .state = static_cast<std::uint32_t>(surface::ButtonState::pressed),
      .active_touch_points = 0};
  require(!value.endpoint.route_input(press, true) &&
              value.port.arm_calls == 1 && value.port.last_arm_sequence == 2 &&
              value.port.clear_calls >= 2 &&
              !value.port.intent_after_focus_admitted,
          "failed trusted press retained gesture eligibility");

  Harness touch;
  touch.attach();
  touch.negotiate();
  const surface::InputEvent start{
      .surface = touch.port.description.key,
      .sequence = 3,
      .kind = surface::InputKind::touch,
      .x_q16 = 1U << surface::kQ16FractionBits,
      .y_q16 = 1U << surface::kQ16FractionBits,
      .delta_x_q16 = 0,
      .delta_y_q16 = 0,
      .code = 1,
      .state = 1,
      .active_touch_points = 1};
  require(touch.endpoint.route_input(start, true) &&
              touch.port.arm_calls == 1 &&
              !touch.port.intent_after_focus_admitted,
          "touch-start gesture was not armed at its exact input packet");
}

void remote_destruction_detaches_while_cpp_object_is_alive() {
  Port port;
  Inspection inspection;
  Clock clock;
  bridge::SurfaceEndpoint endpoint(port, "pet");
  {
    bridge::RemotePluginSurface remote;
    port.remote_at_detach = &remote;
    require(endpoint.attach(remote, 64, 32, 1, 1, inspection, clock),
            "destruction-order fixture did not attach");
  }
  require(endpoint.state() == bridge::SurfaceEndpoint::State::closing &&
              port.detach_calls == 1 && port.remote_was_alive_at_detach,
          "remote C++ destruction did not fence its endpoint first");
}

void attach_rolls_back_every_published_owner() {
  Port port;
  Inspection inspection;
  Clock clock;
  bridge::RemotePluginSurface remote;
  bridge::SurfaceEndpoint endpoint(port, "pet");
  port.fail_describe = true;
  require(!endpoint.attach(remote, 64, 32, 1, 1, inspection, clock),
          "failed surface description escaped endpoint attach");
  port.fail_describe = false;
  port.fail_attach = true;
  require(!endpoint.attach(remote, 64, 32, 1, 1, inspection, clock) &&
              endpoint.state() == bridge::SurfaceEndpoint::State::inert,
          "failed transactional session attach escaped endpoint rollback");
  port.fail_attach = false;
  require(endpoint.attach(remote, 64, 32, 1, 1, inspection, clock),
          "rollback retained a Remote observer or pointer router");
  endpoint.close();

  Port bounds_port;
  bridge::RemotePluginSurface bounds_remote;
  bridge::SurfaceEndpoint bounds(bounds_port, "pet");
  require(!bounds.attach(bounds_remote, 65, 32, 1, 1, inspection, clock) &&
              bounds_port.detach_calls == 1 && bounds_port.send_calls == 0 &&
              bounds.attach(bounds_remote, 64, 32, 1, 1, inspection, clock),
          "HostSurface allocation failure retained published endpoint state");
  bounds.close();

  Port router_port;
  bridge::RemotePluginSurface router_remote;
  RegionRouter occupied;
  require(router_remote.bindHostInputRegionRouter(occupied),
          "occupied region-router fixture did not bind");
  bridge::SurfaceEndpoint router_endpoint(router_port, "pet");
  require(!router_endpoint.attach(router_remote, 64, 32, 1, 1, inspection,
                                  clock) &&
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
  require(router_endpoint.attach(router_remote, 64, 32, 1, 1, inspection,
                                 clock),
          "failed HostSurface retained transport state across safe reuse");
  router_endpoint.close();

  Port transport_port;
  bridge::RemotePluginSurface transport_remote;
  bridge::SurfaceEndpoint transport_endpoint(transport_port,
                                                        "pet");
  auto occupied_sink = std::make_shared<InputSink>();
  auto occupied_transport =
      std::make_shared<bridge::AuthenticatedInputTransport>(99,
                                                            occupied_sink);
  require(transport_remote.bindTransport(occupied_transport) &&
              !transport_endpoint.attach(transport_remote, 64, 32, 1, 1,
                                         inspection, clock) &&
              occupied_transport->connected() &&
              transport_port.detach_calls == 1 &&
              transport_port.send_calls == 0,
          "occupied Remote transport was replaced or emitted a profile");
  transport_remote.unbindTransport(occupied_transport);
  require(transport_endpoint.attach(transport_remote, 64, 32, 1, 1,
                                    inspection, clock),
          "occupied transport rejection prevented safe Remote reuse");
  transport_endpoint.close();
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
              value.port.arm_calls == 1 && value.port.last_arm_sequence == 1 &&
              value.port.send_calls == before + 4 &&
              !value.port.intent_after_focus_admitted,
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
  require(!outside.isAccepted() && !synthesized.isAccepted() &&
              value.port.send_calls == after_release &&
              value.port.arm_calls == 1,
          "untrusted or out-of-bounds Remote input escaped the pointer router");
}

void late_g1_remote_teardown_cannot_touch_g2() {
  Port port;
  Inspection inspection;
  Clock clock;
  bridge::SurfaceEndpoint endpoint(port, "pet");
  {
    bridge::RemotePluginSurface remote;
    require(endpoint.attach(remote, 64, 32, 1, 1, inspection, clock),
            "late G1 teardown fixture did not attach");
    port.replace_session();
  }
  require(endpoint.state() == bridge::SurfaceEndpoint::State::closing &&
              port.stale_clear_calls == 1 && port.clear_calls == 0 &&
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
  late_g1_remote_teardown_cannot_touch_g2();
}
