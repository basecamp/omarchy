#include "SurfaceEndpoint.h"

#include "surface_host.hpp"

#include <QDebug>
#include <QThread>
#include <QPointer>

#include <fcntl.h>

#include <algorithm>
#include <limits>
#include <utility>

namespace omarchy::plugin_runtime::bridge {
namespace {

QString diagnostic_text(std::string_view value) {
  return QString::fromUtf8(value.data(), static_cast<qsizetype>(value.size()));
}

void log_intent_eligibility(
    const channel::SurfaceDescription &description,
    std::uint64_t input_sequence, const char *decision, const char *reason) {
  qInfo().noquote().nospace()
      << "omarchy-plugin-security stage=host-intent-eligibility decision="
      << decision << " reason=" << reason << " plugin="
      << diagnostic_text(description.plugin_id) << " surface="
      << diagnostic_text(description.surface_name) << " surface-id="
      << description.key.id << " generation=" << description.key.generation
      << " input-sequence=" << input_sequence;
}

} // namespace

struct SurfaceEndpoint::Impl final {
  struct OutboundGate final {
    bool render = false;
    bool input = false;
  };
  struct PendingGesture final {
    enum class Kind { pointer, touch, key };
    surface::SurfaceKey surface;
    Kind kind = Kind::pointer;
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
  QPointer<RemotePluginSurface> remote;
  std::optional<channel::SurfaceDescription> description;
  std::optional<PendingGesture> pending_gesture;
  bool input_router_bound = false;
};

SurfaceEndpoint::SurfaceEndpoint(
    channel::SurfaceSessionPort &session,
    TrustedInputAuthority &input_authority,
    std::string declared_surface)
    : session_(session), input_authority_(input_authority),
      declared_surface_(std::move(declared_surface)),
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
    std::uint32_t dpr_denominator, surface_host::MonotonicClock &clock) {
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
  bool observer_bound = false;
  bool session_attached = false;
  const auto rollback = [&]() noexcept {
    value.gate->render = false;
    value.gate->input = false;
    if (value.input_router_bound) {
      surface_item.unbindHostInputRouter(*this);
      value.input_router_bound = false;
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
    value.state = State::inert;
  };

  try {
    if (!surface_item.bindLifetimeObserver(*this)) {
      rollback();
      return false;
    }
    observer_bound = true;
    if (!surface_item.bindHostInputRouter(*this)) {
      rollback();
      return false;
    }
    value.input_router_bound = true;
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
        value.input_sink, input_authority_, clock);
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
  const bool accepted = value.host->receive_render(packet);
  if (value.host->terminated())
    session_.clear_surface_intent_eligibility(*value.description);
  return accepted;
}

bool SurfaceEndpoint::route(HostInputEvent event) {
  auto &value = *implementation_;
  if (std::this_thread::get_id() != owner_thread_ ||
      value.state != State::active || !value.host || !value.description)
    return false;
  const bool pointer =
      std::holds_alternative<surface::PointerButton>(event.payload) &&
      std::get<surface::PointerButton>(event.payload).state ==
          surface::ButtonState::pressed;
  const bool touch = std::holds_alternative<HostTouchFrame>(event.payload) &&
                     std::get<HostTouchFrame>(event.payload).phase ==
                         surface::TouchFramePhase::begin;
  const bool key = std::holds_alternative<surface::Key>(event.payload) &&
                   std::get<surface::Key>(event.payload).state ==
                       surface::ButtonState::pressed &&
                   !std::get<surface::Key>(event.payload).auto_repeat;
  const bool armed = event.trusted_physical && (pointer || touch || key);
  if (armed) {
    if (value.pending_gesture)
      return false;
    value.pending_gesture = Impl::PendingGesture{
        .surface = value.description->key,
        .kind = touch ? Impl::PendingGesture::Kind::touch
                      : key ? Impl::PendingGesture::Kind::key
                            : Impl::PendingGesture::Kind::pointer};
  }
  const bool routed = value.host->route_input(std::move(event));
  if (armed && value.pending_gesture) {
    log_intent_eligibility(*value.description, 0, "rejected",
                           "host-input-rejected");
    session_.clear_surface_intent_eligibility(*value.description);
    value.pending_gesture.reset();
    return false;
  }
  return routed;
}

bool SurfaceEndpoint::cancel(std::uint64_t device) {
  auto &value = *implementation_;
  if (std::this_thread::get_id() != owner_thread_ ||
      value.state != State::active || !value.host || !value.description ||
      !value.host->cancel_input(device))
    return false;
  return true;
}

bool SurfaceEndpoint::forward_input(
    const plugin::wire::EnvelopeHeader &header,
    std::span<const std::byte> payload) {
  auto &value = *implementation_;
  const bool active = value.state == State::active;
  const bool closing = value.state == State::closing;
  if (std::this_thread::get_id() != owner_thread_ ||
      (!active && !closing) || !value.description)
    return false;
  if (header.message_type != static_cast<std::uint16_t>(
                                 surface::RenderMessageType::input))
    return false;

  surface::InputEvent input{};
  if (!surface::decode_input_event(payload, input)) {
    if (value.pending_gesture)
      log_intent_eligibility(*value.description, 0, "rejected",
                             "input-decode");
    session_.clear_surface_intent_eligibility(*value.description);
    value.pending_gesture.reset();
    return false;
  }
  const bool cancel = std::holds_alternative<surface::Cancel>(input.payload);
  if (closing && (!cancel || input.surface != value.description->key ||
                  header.correlation_id != 0))
    return false;
  if (cancel) {
    session_.clear_surface_intent_eligibility(*value.description);
    value.pending_gesture.reset();
  }
  if (closing)
    return session_.send_render_packet(
        *value.description, header,
        std::vector<std::byte>(payload.begin(), payload.end()), {});
  if (!value.pending_gesture)
    return forward_render(header, payload, {});
  const auto pending = *value.pending_gesture;
  value.pending_gesture.reset();
  const bool pointer =
      std::holds_alternative<surface::PointerButton>(input.payload) &&
      std::get<surface::PointerButton>(input.payload).state ==
          surface::ButtonState::pressed;
  const bool touch = std::holds_alternative<surface::TouchFrame>(input.payload) &&
                     std::get<surface::TouchFrame>(input.payload).phase ==
                         surface::TouchFramePhase::begin;
  const bool key = std::holds_alternative<surface::Key>(input.payload) &&
                   std::get<surface::Key>(input.payload).state ==
                       surface::ButtonState::pressed &&
                   !std::get<surface::Key>(input.payload).auto_repeat;
  const auto kind = touch ? Impl::PendingGesture::Kind::touch
                          : key ? Impl::PendingGesture::Kind::key
                                : Impl::PendingGesture::Kind::pointer;
  if (input.surface != pending.surface ||
      static_cast<int>(pointer) + static_cast<int>(touch) +
              static_cast<int>(key) !=
          1 ||
      kind != pending.kind) {
    log_intent_eligibility(*value.description, input.sequence, "rejected",
                           "input-mismatch");
    session_.clear_surface_intent_eligibility(*value.description);
    return false;
  }
  if (!session_.arm_surface_intent(*value.description, input.sequence)) {
    log_intent_eligibility(*value.description, input.sequence, "rejected",
                           "authority-rejected");
    session_.clear_surface_intent_eligibility(*value.description);
    return false;
  }
  if (forward_render(header, payload, {})) {
    log_intent_eligibility(*value.description, input.sequence, "armed",
                           "trusted-input");
    return true;
  }
  log_intent_eligibility(*value.description, input.sequence, "rejected",
                         "worker-transport");
  session_.clear_surface_intent_eligibility(*value.description);
  return false;
}

bool SurfaceEndpoint::forward_render(
    const plugin::wire::EnvelopeHeader &header,
    std::span<const std::byte> payload, std::span<const int> descriptors) {
  auto &value = *implementation_;
  const bool active_route = value.state == State::attached ||
                            value.state == State::active;
  surface::SurfaceKey released{};
  const bool terminal_release =
      value.state == State::closing &&
      header.message_type == static_cast<std::uint16_t>(
                                 surface::RenderMessageType::surface_release) &&
      header.correlation_id == 0 && descriptors.empty() && value.description &&
      surface::decode_surface_key(payload, released) &&
      released == value.description->key;
  if (std::this_thread::get_id() != owner_thread_ ||
      (!active_route && !terminal_release) ||
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
  if (value.state == State::closing || value.state == State::closed)
    return;
  if (value.state == State::inert) {
    value.state = State::closed;
    return;
  }
  // Fence public and reentrant work before either callback-capable terminal
  // send. Only the exact Cancel and release may cross the attached route now.
  value.state = State::closing;
  if (value.host && !value.host->terminated())
    (void)value.host->end_input();
  value.pending_gesture.reset();
  if (value.description)
    session_.clear_surface_intent_eligibility(*value.description);
  if (value.input_router_bound && value.remote) {
    value.remote->unbindHostInputRouter(*this);
    value.input_router_bound = false;
  }
  value.host.reset();
  value.gate->render = false;
  value.gate->input = false;
  if (value.description && !session_.detach(*value.description, *this))
    std::terminate();
  value.input_sink.reset();
  value.sender.reset();
  if (value.remote)
    value.remote->unbindLifetimeObserver(*this);
  value.remote = nullptr;
  value.description.reset();
  value.state = State::closed;
}

void SurfaceEndpoint::remote_surface_destroying() noexcept {
  auto &value = *implementation_;
  value.remote.clear();
  value.input_router_bound = false;
  if (value.host)
    value.host->abandon_bridge_item();
  close_impl();
}

SurfaceEndpoint::State SurfaceEndpoint::state() const
    noexcept {
  return implementation_->state;
}

} // namespace omarchy::plugin_runtime::bridge
