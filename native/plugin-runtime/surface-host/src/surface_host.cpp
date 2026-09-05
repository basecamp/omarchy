#include "surface_host.hpp"

#include "omarchy/plugin_runtime/surface/render_messages.hpp"

#include <QDebug>
#include <QJsonDocument>
#include <QJsonObject>
#include <QString>

#include <unistd.h>

#include <algorithm>
#include <array>
#include <limits>
#include <stdexcept>
#include <type_traits>
#include <utility>

namespace omarchy::plugin_runtime::surface_host {
namespace wire = omarchy::plugin::wire;
namespace {

QString diagnostic_text(std::string_view value) {
  return QString::fromUtf8(value.data(), static_cast<qsizetype>(value.size()));
}

const char *input_kind(const bridge::HostInputPayload &payload) noexcept {
  if (const auto *button = std::get_if<surface::PointerButton>(&payload))
    return button->state == surface::ButtonState::pressed ? "pointer-press"
                                                          : "pointer-release";
  if (const auto *key = std::get_if<surface::Key>(&payload)) {
    if (key->auto_repeat)
      return "key-repeat";
    return key->state == surface::ButtonState::pressed ? "key-press"
                                                       : "key-release";
  }
  const auto *touch = std::get_if<bridge::HostTouchFrame>(&payload);
  if (touch == nullptr || touch->phase == surface::TouchFramePhase::update)
    return nullptr;
  if (touch->phase == surface::TouchFramePhase::begin)
    return "touch-begin";
  if (touch->phase == surface::TouchFramePhase::end)
    return "touch-end";
  return "touch-cancel";
}

void log_input_decision(const NamedSurfacePolicy &policy,
                        const surface::TrustedAllocation &allocation,
                        const char *kind, bool trusted_physical,
                        std::uint64_t sequence, const char *decision,
                        const char *reason) {
  if (kind == nullptr)
    return;
  qInfo().noquote().nospace()
      << "omarchy-plugin-security stage=host-input decision=" << decision
      << " reason=" << reason << " plugin="
      << diagnostic_text(policy.plugin_id) << " surface="
      << diagnostic_text(policy.surface_name) << " surface-id="
      << allocation.surface.id << " generation="
      << allocation.surface.generation << " input-sequence=" << sequence
      << " input-kind=" << kind << " trusted-physical="
      << (trusted_physical ? "true" : "false");
}

[[noreturn]] void fail(std::string_view detail) {
  throw std::runtime_error(std::string(detail));
}

void require(bool condition, std::string_view detail) {
  if (!condition)
    fail(detail);
}

bool exact_revision_digest(std::string_view value) {
  return value.size() == 64 &&
         std::ranges::all_of(value, [](unsigned char character) {
           return (character >= '0' && character <= '9') ||
                  (character >= 'a' && character <= 'f');
         });
}

std::uint32_t bounded_integer(const QJsonObject &object, const char *name,
                              std::uint32_t maximum) {
  const auto value = object.value(QLatin1String(name));
  require(value.isDouble(), "surface bound must be an integer");
  const double number = value.toDouble();
  require(number >= 1 && number <= maximum &&
              number == static_cast<double>(static_cast<std::uint32_t>(number)),
          "surface bound is outside the host limit");
  return static_cast<std::uint32_t>(number);
}

SurfaceRole parse_role(const QString &value) {
  if (value == QStringLiteral("bar-embedded"))
    return SurfaceRole::bar_embedded;
  if (value == QStringLiteral("desktop-overlay"))
    return SurfaceRole::desktop_overlay;
  if (value == QStringLiteral("panel"))
    return SurfaceRole::panel;
  fail("unsupported surface role");
}

std::pair<std::uint32_t, std::uint32_t> role_limits(SurfaceRole role) {
  switch (role) {
  case SurfaceRole::bar_embedded:
    return {2048, 256};
  case SurfaceRole::desktop_overlay:
    return {2048, 2048};
  case SurfaceRole::panel:
    return {1024, 2048};
  }
  return {0, 0};
}

bool valid_policy_enums(const NamedSurfacePolicy &policy) {
  const bool valid_role = policy.role == SurfaceRole::bar_embedded ||
                          policy.role == SurfaceRole::desktop_overlay ||
                          policy.role == SurfaceRole::panel;
  const bool valid_focus =
      policy.keyboard_focus == KeyboardFocusPolicy::none ||
      policy.keyboard_focus == KeyboardFocusPolicy::after_gesture;
  return valid_role && valid_focus;
}

bool region_fits(const surface::TransportedInputRegion &region,
                 const surface::TrustedAllocation &allocation) {
  if (region.x < 0 || region.y < 0 || region.width == 0 || region.height == 0)
    return false;
  const auto x = static_cast<std::uint32_t>(region.x);
  const auto y = static_cast<std::uint32_t>(region.y);
  if (x >= allocation.logical_width || y >= allocation.logical_height)
    return false;
  return region.width <= allocation.logical_width - x &&
         region.height <= allocation.logical_height - y;
}

} // namespace

NamedSurfacePolicy parse_named_surface_policy(
    const omarchy::plugins::manifest::ManifestV2 &manifest,
    std::string_view surface_name) {
  require(surface::valid_surface_name(surface_name), "invalid surface name");
  QJsonParseError parse_error{};
  const auto document = QJsonDocument::fromJson(
      QByteArray::fromStdString(manifest.canonical_surfaces), &parse_error);
  require(parse_error.error == QJsonParseError::NoError && document.isObject(),
          "canonical surfaces are malformed");
  const QJsonObject surfaces = document.object();
  require(!surfaces.isEmpty() &&
              surfaces.size() <=
                  static_cast<qsizetype>(wire::kMaximumPluginSurfaces),
          "manifest has an invalid surface count");
  const auto selected = surfaces.value(QString::fromUtf8(surface_name));
  require(selected.isObject(), "named surface is absent or not an object");
  const QJsonObject object = selected.toObject();
  static const std::array known{
      QStringLiteral("role"),          QStringLiteral("maximumWidth"),
      QStringLiteral("maximumHeight"), QStringLiteral("maximumFramesPerSecond"),
      QStringLiteral("keyboardFocus"), QStringLiteral("lockScreenVisible"),
      QStringLiteral("inputRegions"),  QStringLiteral("defaultSection"),
      QStringLiteral("initiallyVisible"),
  };
  for (auto iterator = object.begin(); iterator != object.end(); ++iterator) {
    require(std::ranges::find(known, iterator.key()) != known.end(),
            "unknown surface policy field");
  }
  const auto role_value = object.value(QStringLiteral("role"));
  require(role_value.isString(), "surface role is required");
  const SurfaceRole role = parse_role(role_value.toString());
  const auto [role_maximum_width, role_maximum_height] = role_limits(role);
  const auto maximum_width =
      bounded_integer(object, "maximumWidth", role_maximum_width);
  const auto maximum_height =
      bounded_integer(object, "maximumHeight", role_maximum_height);
  const auto maximum_fps =
      bounded_integer(object, "maximumFramesPerSecond", 60);

  KeyboardFocusPolicy keyboard_focus = KeyboardFocusPolicy::none;
  const auto focus = object.value(QStringLiteral("keyboardFocus"));
  if (!focus.isUndefined()) {
    if (focus.isBool()) {
      require(!focus.toBool(), "unconditional keyboard focus is unsupported");
    } else {
      require(focus.isString() &&
                  focus.toString() == QStringLiteral("after-gesture"),
              "unsupported keyboard focus policy");
      keyboard_focus = KeyboardFocusPolicy::after_gesture;
    }
  }
  const auto lock_screen = object.value(QStringLiteral("lockScreenVisible"));
  require(lock_screen.isUndefined() ||
              (lock_screen.isBool() && !lock_screen.toBool()),
          "plugin surfaces cannot be visible on the lock screen");
  bool dynamic_input_regions = false;
  const auto regions = object.value(QStringLiteral("inputRegions"));
  if (!regions.isUndefined()) {
    require(regions.isString() &&
                regions.toString() == QStringLiteral("dynamic-bounded"),
            "unsupported input-region policy");
    dynamic_input_regions = true;
  }
  bool initially_visible = false;
  const auto initial = object.value(QStringLiteral("initiallyVisible"));
  if (!initial.isUndefined()) {
    require(role == SurfaceRole::desktop_overlay && initial.isBool(),
            "initiallyVisible is only valid for desktop overlays");
    initially_visible = initial.toBool();
  }
  BarSection default_bar_section = BarSection::unspecified;
  const auto section = object.value(QStringLiteral("defaultSection"));
  if (!section.isUndefined()) {
    require(role == SurfaceRole::bar_embedded && section.isString(),
            "defaultSection is only valid for bar surfaces");
    if (section.toString() == QStringLiteral("left"))
      default_bar_section = BarSection::left;
    else if (section.toString() == QStringLiteral("center"))
      default_bar_section = BarSection::center;
    else if (section.toString() == QStringLiteral("right"))
      default_bar_section = BarSection::right;
    else
      fail("unsupported defaultSection");
  }
  return {.plugin_id = manifest.id,
          .surface_name = std::string(surface_name),
          .role = role,
          .maximum_width = maximum_width,
          .maximum_height = maximum_height,
          .maximum_frames_per_second = maximum_fps,
          .keyboard_focus = keyboard_focus,
          .dynamic_input_regions = dynamic_input_regions,
          .initially_visible = initially_visible,
          .default_bar_section = default_bar_section};
}

std::unique_ptr<HostSurface> HostSurface::create(
    NamedSurfacePolicy policy, permissions::ActivationBinding binding,
    std::uint64_t surface_id, std::uint32_t logical_width,
    std::uint32_t logical_height, std::uint32_t dpr_numerator,
    std::uint32_t dpr_denominator, bridge::RemotePluginSurface &bridge_item,
    render_session::PacketSender &render_sender,
    std::shared_ptr<bridge::RenderPacketSink> input_sink,
    bridge::TrustedInputAuthority &input_authority,
    MonotonicClock &clock) {
  const std::string_view bound_plugin = binding.plugin.view();
  const std::string_view bound_revision = binding.revision.view();
  const std::string_view bound_policy = binding.policy_fingerprint.view();
  if (policy.plugin_id.empty() ||
      !surface::valid_surface_name(policy.surface_name) ||
      !valid_policy_enums(policy) || policy.plugin_id != bound_plugin ||
      !exact_revision_digest(bound_revision) ||
      !exact_revision_digest(bound_policy) || binding.generation == 0 ||
      surface_id == 0 ||
      surface_id > (std::numeric_limits<std::uint64_t>::max() - 2) / 4 ||
      logical_width == 0 || logical_height == 0 ||
      logical_width > policy.maximum_width ||
      logical_height > policy.maximum_height || dpr_numerator == 0 ||
      dpr_denominator == 0 || input_sink == nullptr)
    return nullptr;
  const long page_size = sysconf(_SC_PAGESIZE);
  if (page_size <= 0)
    return nullptr;
  const auto pixel_width =
      (static_cast<std::uint64_t>(logical_width) * dpr_numerator +
       dpr_denominator - 1) /
      dpr_denominator;
  const auto pixel_height =
      (static_cast<std::uint64_t>(logical_height) * dpr_numerator +
       dpr_denominator - 1) /
      dpr_denominator;
  if (pixel_width > std::numeric_limits<std::uint32_t>::max() ||
      pixel_height > std::numeric_limits<std::uint32_t>::max())
    return nullptr;
  auto allocation = surface::make_allocation(
      {.id = surface_id, .generation = binding.generation}, logical_width,
      logical_height, static_cast<std::uint32_t>(pixel_width),
      static_cast<std::uint32_t>(pixel_height), dpr_numerator, dpr_denominator,
      static_cast<std::uint64_t>(page_size));
  if (!allocation)
    return nullptr;
  auto result = std::unique_ptr<HostSurface>(new HostSurface(
      std::move(policy), std::move(binding), *allocation, bridge_item,
      render_sender, std::move(input_sink), input_authority, clock));
  if (!bridge_item.bindHostInputRegionRouter(*result)) {
    result->close();
    return nullptr;
  }
  result->input_region_router_bound_ = true;
  if (!result->policy_.dynamic_input_regions) {
    result->input_regions_.push_back(
        {.x = 0, .y = 0, .width = logical_width, .height = logical_height});
  }
  // Publish only after every other fallible pre-start step. close() withdraws
  // this exact transport if render-session start subsequently fails.
  if (!bridge_item.bindTransport(result->input_transport_))
    return nullptr;
  result->input_transport_bound_ = true;
  // Starting emits the profile offer, so it is deliberately the last
  // fallible construction step. A failed create can never leave stale output.
  if (!result->render_session_.start(result->allocation_))
    return nullptr;
  return result;
}

HostSurface::HostSurface(NamedSurfacePolicy policy,
                         permissions::ActivationBinding binding,
                         surface::TrustedAllocation allocation,
                         bridge::RemotePluginSurface &bridge_item,
                         render_session::PacketSender &render_sender,
                         std::shared_ptr<bridge::RenderPacketSink> input_sink,
                         bridge::TrustedInputAuthority &input_authority,
                         MonotonicClock &clock)
    : policy_(std::move(policy)), allocation_(allocation),
      bridge_item_(&bridge_item),
      input_transport_(std::make_shared<bridge::AuthenticatedInputTransport>(
          binding.generation, std::move(input_sink))),
      input_authority_(input_authority),
      render_session_(binding.generation, bridge_item, render_sender,
                      surface::render_correlation_base(allocation.surface)),
      clock_(clock) {}

HostSurface::~HostSurface() { close(); }

bool HostSurface::receive_render(
    const render_session::AuthenticatedRenderPacket &packet) {
  if (terminated_)
    return false;
  bool is_frame = false;
  if (render_session_.phase() == render_session::Phase::active) {
    surface::FrameReady ready{};
    is_frame = packet.message_type ==
                   static_cast<std::uint16_t>(
                       surface::RenderMessageType::frame_ready) &&
               packet.correlation_id == 0 &&
               surface::decode_frame_ready(packet.payload, ready) &&
               ready.surface == allocation_.surface &&
               ready.slot < surface::kSlotCount && ready.slot_sequence != 0 &&
               (ready.slot_sequence & 1U) == 0 && ready.frame_sequence != 0;
    if (is_frame && has_admitted_frame_) {
      const std::uint64_t now = clock_.now_nanoseconds();
      const std::uint64_t period =
          (1'000'000'000ULL + policy_.maximum_frames_per_second - 1) /
          policy_.maximum_frames_per_second;
      if (now < last_admitted_frame_ns_) {
        close();
        return false;
      }
      if (now - last_admitted_frame_ns_ < period) {
        return false;
      }
    }
  }
  const bool accepted = render_session_.receive(packet);
  if (accepted && is_frame) {
    last_admitted_frame_ns_ = clock_.now_nanoseconds();
    has_admitted_frame_ = true;
  }
  if (render_session_.phase() == render_session::Phase::failed ||
      render_session_.phase() == render_session::Phase::disconnected) {
    const auto cancel = input_authority_.cancel(allocation_);
    if (cancel && input_transport_bound_)
      (void)input_transport_->submit_terminal_cancel(*cancel);
    input_authority_.release(allocation_.surface);
    terminated_ = true;
    unbind_input_region_router();
  }
  return accepted;
}

bool HostSurface::apply(const surface::InputRegionUpdate &update) {
  if (!policy_.dynamic_input_regions || !active() ||
      update.surface != allocation_.surface || update.generation == 0 ||
      update.count > surface::kMaximumTransportedInputRegions ||
      !std::ranges::all_of(
          update.regions.begin(), update.regions.begin() + update.count,
          [this](const surface::TransportedInputRegion &region) {
            return region_fits(region, allocation_);
          }))
    return false;
  input_regions_.assign(update.regions.begin(),
                        update.regions.begin() + update.count);
  return true;
}

bool HostSurface::point_is_inside(std::uint32_t x_q16,
                                  std::uint32_t y_q16) const {
  const std::uint64_t x = x_q16;
  const std::uint64_t y = y_q16;
  return std::ranges::any_of(
      input_regions_, [x, y](const surface::TransportedInputRegion &region) {
        const std::uint64_t left = static_cast<std::uint64_t>(region.x)
                                   << surface::kQ16FractionBits;
        const std::uint64_t top = static_cast<std::uint64_t>(region.y)
                                  << surface::kQ16FractionBits;
        const std::uint64_t right =
            static_cast<std::uint64_t>(region.x + region.width)
            << surface::kQ16FractionBits;
        const std::uint64_t bottom =
            static_cast<std::uint64_t>(region.y + region.height)
            << surface::kQ16FractionBits;
        return x >= left && x < right && y >= top && y < bottom;
      });
}

bool HostSurface::active() const {
  return bridge_item_ && !terminated_ &&
         render_session_.phase() == render_session::Phase::active &&
         bridge_item_->connected();
}

bool HostSurface::terminated() const noexcept { return terminated_; }

bool HostSurface::route_input(bridge::HostInputEvent input) {
  const auto *kind = input_kind(input.payload);
  const bool trusted_physical = input.trusted_physical;
  if (!active()) {
    log_input_decision(policy_, allocation_, kind, trusted_physical, 0,
                       "rejected", "surface-inactive");
    return false;
  }
  const bool pointer_capture = input_authority_.pointer_captured(
      allocation_.surface, input.device);
  const bool touch_capture = input_authority_.touch_captured(
      allocation_.surface, input.device);
  const bool wheel_capture = input_authority_.wheel_captured(
      allocation_.surface, input.device);
  const bool allowed = std::visit(
      [&](const auto &event) {
        using Event = std::decay_t<decltype(event)>;
        if constexpr (std::is_same_v<Event, surface::PointerMotion> ||
                      std::is_same_v<Event, surface::PointerButton>) {
          return pointer_capture ||
                 point_is_inside(event.position.x_q16, event.position.y_q16);
        } else if constexpr (std::is_same_v<Event, surface::Wheel>) {
          return wheel_capture ||
                 point_is_inside(event.position.x_q16, event.position.y_q16);
        } else if constexpr (std::is_same_v<Event, bridge::HostTouchFrame>) {
          if (event.count > event.points.size())
            return false;
          if (touch_capture)
            return true;
          return std::ranges::all_of(
              event.points.begin(), event.points.begin() + event.count,
              [&](const bridge::HostTouchPoint &point) {
                return point_is_inside(point.position.x_q16,
                                       point.position.y_q16);
              });
        } else if constexpr (std::is_same_v<Event, surface::Key> ||
                             std::is_same_v<Event, surface::TextCommit>) {
          return policy_.keyboard_focus == KeyboardFocusPolicy::after_gesture &&
                 input_authority_.focused_surface() == allocation_.surface;
        } else {
          return !event.focused ||
                 (policy_.keyboard_focus == KeyboardFocusPolicy::after_gesture &&
                  input_authority_.surface_has_physical_activation(
                      allocation_.surface));
        }
      },
      input.payload);
  if (!allowed) {
    log_input_decision(policy_, allocation_, kind, trusted_physical, 0,
                       "rejected", "policy-filter");
    return false;
  }
  auto admission = input_authority_.admit(allocation_, std::move(input), true);
  if (!admission) {
    log_input_decision(policy_, allocation_, kind, trusted_physical, 0,
                       "rejected", "input-authority");
    return false;
  }
  const auto input_sequence = admission->event.sequence;
  const bool focus_after_gesture =
      admission->trusted_gesture &&
      policy_.keyboard_focus == KeyboardFocusPolicy::after_gesture;
  log_input_decision(policy_, allocation_, kind, trusted_physical,
                     input_sequence, "accepted", "input-authority");
  auto *bridge_item = bridge_item_.data();
  if (bridge_item == nullptr || !bridge_item->submitInput(admission->event)) {
    log_input_decision(policy_, allocation_, kind, trusted_physical,
                       input_sequence, "rejected", "worker-transport");
    close();
    return false;
  }
  if (focus_after_gesture && bridge_item_)
    bridge_item_->forceActiveFocus(Qt::MouseFocusReason);
  return true;
}

bool HostSurface::cancel_input(std::uint64_t device) {
  if (!active() ||
      (!input_authority_.pointer_captured(allocation_.surface, device) &&
       !input_authority_.touch_captured(allocation_.surface, device) &&
       !input_authority_.wheel_captured(allocation_.surface, device)))
    return false;
  const auto cancel = input_authority_.cancel(allocation_);
  if (!cancel)
    return false;
  auto *bridge_item = bridge_item_.data();
  if (bridge_item == nullptr || !bridge_item->submitInput(*cancel)) {
    close();
    return false;
  }
  return true;
}

bool HostSurface::end_input() {
  if (input_ended_)
    return true;
  input_ended_ = true;
  const auto cancel = input_authority_.cancel(allocation_);
  auto *bridge_item = bridge_item_.data();
  return cancel && input_transport_bound_ && bridge_item != nullptr &&
         bridge_item->submitInput(*cancel);
}

void HostSurface::close() {
  unbind_input_region_router();
  if (!terminated_)
    (void)end_input();
  input_authority_.release(allocation_.surface);
  if (input_transport_bound_) {
    if (bridge_item_)
      bridge_item_->unbindTransport(input_transport_);
    else
      input_transport_->disconnect();
    input_transport_bound_ = false;
  }
  if (terminated_)
    return;
  const auto render_phase = render_session_.phase();
  const bool disconnect_bridge =
      render_phase != render_session::Phase::idle &&
      render_phase != render_session::Phase::failed &&
      render_phase != render_session::Phase::disconnected;
  // Release may synchronously destroy the QML item. The generic render
  // session must not retain or call its raw sink after this point.
  render_session_.close(render_session::SinkDisposition::abandon);
  if (disconnect_bridge && bridge_item_)
    bridge_item_->disconnect();
  terminated_ = true;
}

void HostSurface::unbind_input_region_router() {
  if (!input_region_router_bound_)
    return;
  if (bridge_item_)
    bridge_item_->unbindHostInputRegionRouter(*this);
  input_region_router_bound_ = false;
  input_regions_.clear();
}

void HostSurface::abandon_bridge_item() noexcept {
  bridge_item_.clear();
  input_region_router_bound_ = false;
  if (input_transport_bound_) {
    input_transport_->disconnect();
    input_transport_bound_ = false;
  }
}

const surface::TrustedAllocation &HostSurface::allocation() const {
  return allocation_;
}

} // namespace omarchy::plugin_runtime::surface_host
