#include "SurfaceEndpoint.h"

#include "surface_host.hpp"

#include <QThread>

#include <fcntl.h>

#include <algorithm>
#include <cmath>
#include <limits>
#include <utility>

namespace omarchy::plugin_runtime::bridge {
namespace {

bool is_exact_trusted_activation(const surface::InputEvent &event,
                                 bool trusted_gesture) noexcept {
  return trusted_gesture &&
         ((event.kind == surface::InputKind::pointer_button &&
           event.state == static_cast<std::uint32_t>(
                              surface::ButtonState::pressed)) ||
          (event.kind == surface::InputKind::touch && event.state == 1));
}

std::uint32_t pointer_button(Qt::MouseButton button) noexcept {
  switch (button) {
  case Qt::LeftButton:
    return 1;
  case Qt::RightButton:
    return 2;
  case Qt::MiddleButton:
    return 3;
  case Qt::BackButton:
    return 4;
  case Qt::ForwardButton:
    return 5;
  default:
    return 0;
  }
}

std::optional<std::uint32_t> q16_coordinate(qreal value,
                                            std::uint32_t bound) noexcept {
  if (!std::isfinite(value) || value < 0 || value >= bound)
    return {};
  const double scaled = std::floor(value * (1U << surface::kQ16FractionBits));
  if (scaled < 0 || scaled > std::numeric_limits<std::uint32_t>::max())
    return {};
  return static_cast<std::uint32_t>(scaled);
}

} // namespace

struct SurfaceEndpoint::Impl final {
  struct OutboundGate final {
    bool render = false;
    bool input = false;
  };
  struct PendingGesture final {
    surface::SurfaceKey surface;
    std::uint64_t sequence = 0;
    surface::InputKind kind = surface::InputKind::pointer_button;
    std::uint32_t state = 0;
  };

  class RenderSender final : public render_session::PacketSender {
  public:
    RenderSender(SurfaceEndpoint &owner,
                 std::shared_ptr<OutboundGate> gate)
        : owner_(owner), gate_(std::move(gate)) {}

    bool send(const plugin::wire::EnvelopeHeader &header,
              std::span<const std::byte> payload,
              std::span<const int> descriptors) override {
      return gate_->render && owner_.forward_render(header, payload,
                                                    descriptors);
    }

  private:
    SurfaceEndpoint &owner_;
    std::shared_ptr<OutboundGate> gate_;
  };

  class InputSink final : public RenderPacketSink {
  public:
    InputSink(SurfaceEndpoint &owner,
              std::shared_ptr<OutboundGate> gate)
        : owner_(owner), gate_(std::move(gate)) {}

    bool send(const plugin::wire::EnvelopeHeader &header,
              std::span<const std::byte> payload) override {
      return gate_->input && owner_.forward_input(header, payload);
    }

  private:
    SurfaceEndpoint &owner_;
    std::shared_ptr<OutboundGate> gate_;
  };

  State state = State::inert;
  std::shared_ptr<OutboundGate> gate = std::make_shared<OutboundGate>();
  std::unique_ptr<RenderSender> sender;
  std::shared_ptr<InputSink> input_sink;
  std::unique_ptr<surface_host::HostSurface> host;
  RemotePluginSurface *remote = nullptr;
  std::optional<channel::SurfaceDescription> description;
  std::optional<PendingGesture> pending_gesture;
  std::uint32_t logical_width = 0;
  std::uint32_t logical_height = 0;
  std::uint64_t input_sequence = 0;
  bool pointer_router_bound = false;
};

SurfaceEndpoint::SurfaceEndpoint(
    channel::SurfaceSessionPort &session,
    std::string declared_surface)
    : session_(session), declared_surface_(std::move(declared_surface)),
      owner_thread_(std::this_thread::get_id()),
      implementation_(std::make_unique<Impl>()) {}

SurfaceEndpoint::~SurfaceEndpoint() {
  // Manager ownership is event-loop confined. Continuing teardown on another
  // thread could leave PluginSession routing to a destroyed endpoint.
  if (std::this_thread::get_id() != owner_thread_)
    std::terminate();
  close();
}

bool SurfaceEndpoint::attach(
    RemotePluginSurface &surface_item, std::uint32_t logical_width,
    std::uint32_t logical_height, std::uint32_t dpr_numerator,
    std::uint32_t dpr_denominator,
    surface_host::InspectionAuthority &inspection,
    surface_host::MonotonicClock &clock) {
  auto &value = *implementation_;
  if (std::this_thread::get_id() != owner_thread_ ||
      QThread::currentThread() != surface_item.thread() ||
      value.state != State::inert || declared_surface_.empty())
    return false;

  auto description = session_.describe(declared_surface_);
  if (!description || description->surface_name != declared_surface_ ||
      description->key.id == 0 || description->session_nonce == 0 ||
      description->key.generation != description->binding.generation)
    return false;

  surface_host::NamedSurfacePolicy policy;
  std::unique_ptr<Impl::RenderSender> sender;
  std::shared_ptr<Impl::InputSink> input_sink;
  try {
    plugins::manifest::ManifestV2 policy_source;
    policy_source.id = description->plugin_id;
    policy_source.canonical_surfaces = description->canonical_surfaces;
    policy = surface_host::parse_named_surface_policy(policy_source,
                                                       declared_surface_);
    sender = std::make_unique<Impl::RenderSender>(*this, value.gate);
    input_sink = std::make_shared<Impl::InputSink>(*this, value.gate);
  } catch (...) {
    return false;
  }

  value.remote = &surface_item;
  value.description = std::move(description);
  value.sender = std::move(sender);
  value.input_sink = std::move(input_sink);
  value.logical_width = logical_width;
  value.logical_height = logical_height;
  bool observer_bound = false;
  bool session_attached = false;
  const auto rollback = [&]() noexcept {
    value.gate->render = false;
    value.gate->input = false;
    if (value.pointer_router_bound) {
      surface_item.unbindHostPointerRouter(*this);
      value.pointer_router_bound = false;
    }
    if (session_attached && value.description &&
        !session_.detach(*value.description, *this))
      std::terminate();
    value.host.reset();
    if (observer_bound)
      surface_item.unbindLifetimeObserver(*this);
    value.input_sink.reset();
    value.sender.reset();
    value.description.reset();
    value.remote = nullptr;
    value.logical_width = 0;
    value.logical_height = 0;
    value.state = State::inert;
  };

  try {
    if (!surface_item.bindLifetimeObserver(*this)) {
      rollback();
      return false;
    }
    observer_bound = true;
    if (!surface_item.bindHostPointerRouter(*this)) {
      rollback();
      return false;
    }
    value.pointer_router_bound = true;
    const bool attached = session_.attach(*value.description, *this);
    if (!attached) {
      rollback();
      return false;
    }
    session_attached = true;
    value.state = State::attached;
    value.gate->render = true;
    value.gate->input = true;
    value.host = surface_host::HostSurface::create(
        std::move(policy), value.description->binding,
        value.description->key.id, logical_width, logical_height,
        dpr_numerator, dpr_denominator, surface_item, *value.sender,
        value.input_sink, inspection, clock);
    if (!value.host) {
      rollback();
      return false;
    }
  } catch (...) {
    rollback();
    return false;
  }
  value.state = State::active;
  return true;
}

bool SurfaceEndpoint::receive(
    host_session::OwnedAuthenticatedRenderMessage message) {
  auto &value = *implementation_;
  if (std::this_thread::get_id() != owner_thread_ ||
      value.state != State::active || !value.host || !value.description ||
      !message.descriptors.empty() ||
      message.launch_generation != value.description->binding.generation)
    return false;
  const render_session::AuthenticatedRenderPacket packet{
      .message_type = message.message_type,
      .correlation_id = message.correlation,
      .payload = message.payload,
  };
  return value.host->receive_render(packet);
}

bool SurfaceEndpoint::route_input(const surface::InputEvent &event,
                                            bool trusted_gesture) {
  auto &value = *implementation_;
  if (std::this_thread::get_id() != owner_thread_ ||
      value.state != State::active || !value.host || !value.description ||
      event.surface != value.description->key)
    return false;
  const bool armed = is_exact_trusted_activation(event, trusted_gesture);
  if (armed) {
    if (value.pending_gesture)
      return false;
    value.pending_gesture = Impl::PendingGesture{
        .surface = event.surface,
        .sequence = event.sequence,
        .kind = event.kind,
        .state = event.state,
    };
  }
  const bool routed = value.host->route_input(event, trusted_gesture);
  if (armed && value.pending_gesture) {
    session_.clear_surface_intent_eligibility(*value.description);
    value.pending_gesture.reset();
    return false;
  }
  return routed;
}

bool SurfaceEndpoint::route(const HostPointerEvent &event) {
  auto &value = *implementation_;
  if (std::this_thread::get_id() != owner_thread_ ||
      value.state != State::active || !value.host || !value.description ||
      value.input_sequence == std::numeric_limits<std::uint64_t>::max())
    return false;
  const auto x = q16_coordinate(event.x, value.logical_width);
  const auto y = q16_coordinate(event.y, value.logical_height);
  const auto button = pointer_button(event.button);
  if (!x || !y || button == 0)
    return false;
  ++value.input_sequence;
  const surface::InputEvent input{
      .surface = value.description->key,
      .sequence = value.input_sequence,
      .kind = surface::InputKind::pointer_button,
      .x_q16 = *x,
      .y_q16 = *y,
      .delta_x_q16 = 0,
      .delta_y_q16 = 0,
      .code = button,
      .state = static_cast<std::uint32_t>(
          event.pressed ? surface::ButtonState::pressed
                        : surface::ButtonState::released),
      .active_touch_points = 0,
  };
  return route_input(input, event.pressed && !event.application_synthesized);
}

bool SurfaceEndpoint::forward_input(
    const plugin::wire::EnvelopeHeader &header,
    std::span<const std::byte> payload) {
  auto &value = *implementation_;
  if (std::this_thread::get_id() != owner_thread_ ||
      value.state != State::active || !value.description)
    return false;
  const auto input_type = static_cast<std::uint16_t>(
      surface::RenderMessageType::input);
  if (header.message_type != input_type) {
    // Focus must never inherit eligibility from an earlier input.
    session_.clear_surface_intent_eligibility(*value.description);
    return forward_render(header, payload, {});
  }

  surface::InputEvent input{};
  if (!surface::decode_input_event(payload, input)) {
    session_.clear_surface_intent_eligibility(*value.description);
    value.pending_gesture.reset();
    return false;
  }
  if (!value.pending_gesture)
    return forward_render(header, payload, {});
  const auto pending = *value.pending_gesture;
  value.pending_gesture.reset();
  if (input.surface != pending.surface || input.sequence != pending.sequence ||
      input.kind != pending.kind || input.state != pending.state ||
      !session_.arm_surface_intent(*value.description, input.sequence)) {
    session_.clear_surface_intent_eligibility(*value.description);
    return false;
  }
  if (forward_render(header, payload, {}))
    return true;
  session_.clear_surface_intent_eligibility(*value.description);
  return false;
}

bool SurfaceEndpoint::forward_render(
    const plugin::wire::EnvelopeHeader &header,
    std::span<const std::byte> payload, std::span<const int> descriptors) {
  auto &value = *implementation_;
  if (std::this_thread::get_id() != owner_thread_ ||
      (value.state != State::attached && value.state != State::active) ||
      !value.description || descriptors.size() > 1)
    return false;

  std::vector<host_session::OwnedFd> owned;
  owned.reserve(descriptors.size());
  for (const int descriptor : descriptors) {
    if (descriptor < 0)
      return false;
    const int duplicate = ::fcntl(descriptor, F_DUPFD_CLOEXEC, 0);
    if (duplicate < 0)
      return false;
    owned.emplace_back(duplicate);
  }
  return session_.send_render_packet(
      *value.description, header,
      std::vector<std::byte>(payload.begin(), payload.end()),
      std::move(owned));
}

void SurfaceEndpoint::close() noexcept { close_impl(); }

void SurfaceEndpoint::close_impl() noexcept {
  auto &value = *implementation_;
  if (std::this_thread::get_id() != owner_thread_)
    std::terminate();
  if (value.state == State::closing)
    return;
  if (value.state == State::inert) {
    value.state = State::closing;
    return;
  }
  value.state = State::closing;
  value.gate->render = false;
  value.gate->input = false;
  value.pending_gesture.reset();
  if (value.description)
    session_.clear_surface_intent_eligibility(*value.description);
  if (value.pointer_router_bound && value.remote != nullptr) {
    value.remote->unbindHostPointerRouter(*this);
    value.pointer_router_bound = false;
  }
  if (value.description && !session_.detach(*value.description, *this))
    std::terminate();
  value.host.reset();
  value.input_sink.reset();
  value.sender.reset();
  if (value.remote != nullptr)
    value.remote->unbindLifetimeObserver(*this);
  value.remote = nullptr;
  value.description.reset();
  value.logical_width = 0;
  value.logical_height = 0;
}

void SurfaceEndpoint::remote_surface_destroying() noexcept {
  close_impl();
}

SurfaceEndpoint::State SurfaceEndpoint::state() const
    noexcept {
  return implementation_->state;
}

std::string_view SurfaceEndpoint::declared_surface() const noexcept {
  return declared_surface_;
}

} // namespace omarchy::plugin_runtime::bridge
