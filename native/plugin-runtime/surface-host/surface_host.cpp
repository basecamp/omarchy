#include "surface_host.hpp"

#include "omarchy/plugin/wire/envelope.hpp"
#include "omarchy/plugin_runtime/surface/render_messages.hpp"

#include <QJsonDocument>
#include <QJsonObject>
#include <QString>

#include <unistd.h>

#include <algorithm>
#include <array>
#include <limits>
#include <stdexcept>
#include <utility>

namespace omarchy::plugin_runtime::surface_host {
namespace wire = omarchy::plugin::wire;
namespace {

[[noreturn]] void fail(std::string_view detail) {
  throw std::runtime_error(std::string(detail));
}

void require(bool condition, std::string_view detail) {
  if (!condition)
    fail(detail);
}

bool bounded_name(std::string_view value) {
  if (value.empty() || value.size() > 64)
    return false;
  for (const unsigned char character : value) {
    if (!((character >= 'a' && character <= 'z') ||
          (character >= 'A' && character <= 'Z') ||
          (character >= '0' && character <= '9') || character == '-' ||
          character == '_'))
      return false;
  }
  return true;
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

bool region_fits(const InputRegion &region,
                 const surface::TrustedAllocation &allocation) {
  if (region.width == 0 || region.height == 0 ||
      region.x >= allocation.logical_width ||
      region.y >= allocation.logical_height)
    return false;
  return region.width <= allocation.logical_width - region.x &&
         region.height <= allocation.logical_height - region.y;
}

bool is_focus_gesture(const surface::InputEvent &event) {
  return (event.kind == surface::InputKind::pointer_button &&
          event.state ==
              static_cast<std::uint32_t>(surface::ButtonState::pressed)) ||
         (event.kind == surface::InputKind::touch && event.state == 1);
}

} // namespace

NamedSurfacePolicy parse_named_surface_policy(
    const omarchy::plugins::manifest::ManifestV2 &manifest,
    std::string_view surface_name) {
  require(bounded_name(surface_name), "invalid surface name");
  QJsonParseError parse_error{};
  const auto document = QJsonDocument::fromJson(
      QByteArray::fromStdString(manifest.canonical_surfaces), &parse_error);
  require(parse_error.error == QJsonParseError::NoError && document.isObject(),
          "canonical surfaces are malformed");
  const QJsonObject surfaces = document.object();
  require(!surfaces.isEmpty() &&
              surfaces.size() <=
                  static_cast<qsizetype>(kMaximumSurfacesPerPlugin),
          "manifest has an invalid surface count");
  const auto selected = surfaces.value(QString::fromUtf8(surface_name));
  require(selected.isObject(), "named surface is absent or not an object");
  const QJsonObject object = selected.toObject();
  static const std::array known{
      QStringLiteral("role"),          QStringLiteral("maximumWidth"),
      QStringLiteral("maximumHeight"), QStringLiteral("maximumFramesPerSecond"),
      QStringLiteral("keyboardFocus"), QStringLiteral("lockScreenVisible"),
      QStringLiteral("inputRegions"),
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
  return {.plugin_id = manifest.id,
          .surface_name = std::string(surface_name),
          .role = role,
          .maximum_width = maximum_width,
          .maximum_height = maximum_height,
          .maximum_frames_per_second = maximum_fps,
          .keyboard_focus = keyboard_focus,
          .dynamic_input_regions = dynamic_input_regions};
}

std::unique_ptr<HostSurface> HostSurface::create(
    NamedSurfacePolicy policy, permissions::ActivationBinding binding,
    std::uint64_t surface_id, std::uint32_t logical_width,
    std::uint32_t logical_height, std::uint32_t dpr_numerator,
    std::uint32_t dpr_denominator, bridge::RemotePluginSurface &bridge_item,
    render_session::PacketSender &render_sender,
    std::shared_ptr<bridge::RenderPacketSink> input_sink,
    InspectionAuthority &inspection_authority, MonotonicClock &clock) {
  const std::string_view bound_plugin = binding.plugin.view();
  const std::string_view bound_revision = binding.revision.view();
  const std::string_view bound_policy = binding.policy_fingerprint.view();
  if (policy.plugin_id.empty() || !bounded_name(policy.surface_name) ||
      policy.plugin_id != bound_plugin ||
      !exact_revision_digest(bound_revision) ||
      !exact_revision_digest(bound_policy) || binding.generation == 0 ||
      surface_id == 0 || logical_width == 0 || logical_height == 0 ||
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
      render_sender, std::move(input_sink), inspection_authority, clock));
  if (!result->render_session_.start(result->allocation_))
    return nullptr;
  if (!result->policy_.dynamic_input_regions) {
    result->input_regions_.push_back(
        {.x = 0, .y = 0, .width = logical_width, .height = logical_height});
  }
  return result;
}

HostSurface::HostSurface(NamedSurfacePolicy policy,
                         permissions::ActivationBinding binding,
                         surface::TrustedAllocation allocation,
                         bridge::RemotePluginSurface &bridge_item,
                         render_session::PacketSender &render_sender,
                         std::shared_ptr<bridge::RenderPacketSink> input_sink,
                         InspectionAuthority &inspection_authority,
                         MonotonicClock &clock)
    : policy_(std::move(policy)), binding_(std::move(binding)),
      allocation_(allocation), bridge_item_(bridge_item),
      input_transport_(std::make_shared<bridge::AuthenticatedInputTransport>(
          binding_.generation, std::move(input_sink))),
      render_session_(binding_.generation, bridge_item, render_sender),
      inspection_authority_(inspection_authority), clock_(clock) {
  bridge_item_.bindTransport(input_transport_);
}

HostSurface::~HostSurface() { close(); }

bool HostSurface::receive_render(std::span<const std::byte> packet) {
  if (terminated_ || locked_)
    return false;
  bool is_frame = false;
  if (render_session_.phase() == render_session::Phase::active) {
    const auto decoded =
        wire::decode_packet(packet, wire::EndpointRole::render);
    surface::FrameReady ready{};
    is_frame = decoded &&
               decoded.packet.header.message_type ==
                   static_cast<std::uint16_t>(
                       surface::RenderMessageType::frame_ready) &&
               decoded.packet.header.role_protocol_version ==
                   surface::kRenderRoleVersion &&
               decoded.packet.header.flags == 0 &&
               decoded.packet.header.launch_generation == binding_.generation &&
               decoded.packet.header.correlation_id == 0 &&
               surface::decode_frame_ready(decoded.packet.payload, ready) &&
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
        if (pace_drops_ != std::numeric_limits<std::uint64_t>::max())
          ++pace_drops_;
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
      render_session_.phase() == render_session::Phase::disconnected)
    terminated_ = true;
  return accepted;
}

bool HostSurface::set_input_regions(std::span<const InputRegion> regions) {
  if (!policy_.dynamic_input_regions || terminated_ ||
      regions.size() > kMaximumInputRegions ||
      !std::ranges::all_of(regions, [this](const InputRegion &region) {
        return region_fits(region, allocation_);
      }))
    return false;
  input_regions_.assign(regions.begin(), regions.end());
  return true;
}

bool HostSurface::point_is_inside(std::uint32_t x_q16,
                                  std::uint32_t y_q16) const {
  const std::uint64_t x = x_q16;
  const std::uint64_t y = y_q16;
  return std::ranges::any_of(input_regions_, [x, y](const InputRegion &region) {
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
  return !terminated_ && !locked_ &&
         render_session_.phase() == render_session::Phase::active &&
         bridge_item_.connected();
}

bool HostSurface::route_input(const surface::InputEvent &event,
                              bool trusted_gesture) {
  if (!active() || event.surface != allocation_.surface)
    return false;
  const auto pressed =
      static_cast<std::uint32_t>(surface::ButtonState::pressed);
  const auto released =
      static_cast<std::uint32_t>(surface::ButtonState::released);
  const bool captured_release =
      event.kind == surface::InputKind::pointer_button &&
      event.state == released && captured_pointer_button_ == event.code;
  const bool touch_continuation = event.kind == surface::InputKind::touch &&
                                  event.state != 1 && touch_active_;
  if (event.kind == surface::InputKind::key) {
    if (policy_.keyboard_focus != KeyboardFocusPolicy::after_gesture ||
        !bridge_item_.surfaceFocused())
      return false;
  } else if (!captured_release && !touch_continuation &&
             !point_is_inside(event.x_q16, event.y_q16)) {
    return false;
  }
  if (policy_.keyboard_focus == KeyboardFocusPolicy::none &&
      event.kind == surface::InputKind::pointer_button) {
    if (event.state == pressed) {
      if (!trusted_gesture || captured_pointer_button_ != 0 ||
          focus_sequence_ == std::numeric_limits<std::uint64_t>::max())
        return false;
      ++focus_sequence_;
      if (!bridge_item_.submitTransientFocus({.surface = allocation_.surface,
                                              .sequence = focus_sequence_,
                                              .focused = true})) {
        close();
        return false;
      }
      transient_focus_active_ = true;
      if (!bridge_item_.submitHostRoutedPointerInput(event)) {
        close();
        return false;
      }
      captured_pointer_button_ = event.code;
      return true;
    }
    if (event.state != released || trusted_gesture ||
        captured_pointer_button_ != event.code)
      return false;
    if (!bridge_item_.submitHostRoutedPointerInput(event)) {
      close();
      return false;
    }
    captured_pointer_button_ = 0;
    if (focus_sequence_ == std::numeric_limits<std::uint64_t>::max()) {
      close();
      return false;
    }
    ++focus_sequence_;
    if (!bridge_item_.submitTransientFocus({.surface = allocation_.surface,
                                            .sequence = focus_sequence_,
                                            .focused = false})) {
      close();
      return false;
    }
    transient_focus_active_ = false;
    return true;
  }
  if (policy_.keyboard_focus == KeyboardFocusPolicy::none &&
      event.kind == surface::InputKind::touch) {
    if (event.state == 1) {
      if (!trusted_gesture || touch_active_ || event.active_touch_points == 0 ||
          focus_sequence_ == std::numeric_limits<std::uint64_t>::max())
        return false;
      ++focus_sequence_;
      if (!bridge_item_.submitTransientFocus({.surface = allocation_.surface,
                                              .sequence = focus_sequence_,
                                              .focused = true})) {
        close();
        return false;
      }
      transient_focus_active_ = true;
      if (!bridge_item_.submitHostRoutedPointerInput(event)) {
        close();
        return false;
      }
      touch_active_ = event.active_touch_points != 0;
      return true;
    }
    if (trusted_gesture || !touch_active_ ||
        (event.state == 2 && event.active_touch_points == 0))
      return false;
    if (!bridge_item_.submitHostRoutedPointerInput(event)) {
      close();
      return false;
    }
    if (event.state == 3 || event.active_touch_points == 0)
      touch_active_ = false;
    if (!touch_active_) {
      if (focus_sequence_ == std::numeric_limits<std::uint64_t>::max()) {
        close();
        return false;
      }
      ++focus_sequence_;
      if (!bridge_item_.submitTransientFocus({.surface = allocation_.surface,
                                              .sequence = focus_sequence_,
                                              .focused = false})) {
        close();
        return false;
      }
      transient_focus_active_ = false;
    }
    return true;
  }
  if (trusted_gesture) {
    if (!is_focus_gesture(event) ||
        focus_sequence_ == std::numeric_limits<std::uint64_t>::max())
      return false;
    if (policy_.keyboard_focus == KeyboardFocusPolicy::after_gesture) {
      ++focus_sequence_;
      if (!bridge_item_.submitFocus({.surface = allocation_.surface,
                                     .sequence = focus_sequence_,
                                     .focused = true}))
        return false;
    }
  }
  const bool submitted = bridge_item_.submitInput(event);
  if (!submitted)
    return false;
  if (event.kind == surface::InputKind::pointer_button) {
    if (event.state == pressed)
      captured_pointer_button_ = event.code;
    else if (event.state == released)
      captured_pointer_button_ = 0;
  } else if (event.kind == surface::InputKind::touch) {
    if (event.state == 1)
      touch_active_ = event.active_touch_points != 0;
    else if (event.state == 3 || event.active_touch_points == 0)
      touch_active_ = false;
  }
  return true;
}

bool HostSurface::clear_focus() {
  if (!active() || !bridge_item_.surfaceFocused())
    return false;
  if (focus_sequence_ == std::numeric_limits<std::uint64_t>::max())
    return false;
  ++focus_sequence_;
  return bridge_item_.submitFocus({.surface = allocation_.surface,
                                   .sequence = focus_sequence_,
                                   .focused = false});
}

bool HostSurface::set_locked(bool locked) {
  if (terminated_ || locked == locked_)
    return false;
  if (locked) {
    locked_ = true;
    captured_pointer_button_ = 0;
    touch_active_ = false;
    if (render_session_.phase() == render_session::Phase::active) {
      bool focus_cleared = true;
      if (transient_focus_active_) {
        if (focus_sequence_ == std::numeric_limits<std::uint64_t>::max()) {
          focus_cleared = false;
        } else {
          ++focus_sequence_;
          focus_cleared =
              bridge_item_.submitTransientFocus({.surface = allocation_.surface,
                                                 .sequence = focus_sequence_,
                                                 .focused = false});
          transient_focus_active_ = false;
        }
      }
      if (bridge_item_.surfaceFocused()) {
        if (focus_sequence_ == std::numeric_limits<std::uint64_t>::max()) {
          focus_cleared = false;
        } else {
          ++focus_sequence_;
          focus_cleared =
              bridge_item_.submitFocus({.surface = allocation_.surface,
                                        .sequence = focus_sequence_,
                                        .focused = false});
        }
      }
      if (!focus_cleared || !bridge_item_.suspend()) {
        close();
        return false;
      }
    }
    return true;
  }
  if (render_session_.phase() == render_session::Phase::active &&
      !bridge_item_.resume()) {
    close();
    return false;
  }
  locked_ = false;
  return true;
}

bool HostSurface::perform_inspection_action(InspectionAction action) {
  if (terminated_)
    return false;
  if (action == InspectionAction::terminate) {
    close();
    return inspection_authority_.perform(action, policy_.plugin_id,
                                         binding_.revision.view(),
                                         policy_.surface_name);
  }
  return inspection_authority_.perform(action, policy_.plugin_id,
                                       binding_.revision.view(),
                                       policy_.surface_name);
}

void HostSurface::peer_lost() {
  if (terminated_)
    return;
  render_session_.peer_lost();
  captured_pointer_button_ = 0;
  touch_active_ = false;
  transient_focus_active_ = false;
  terminated_ = true;
}

void HostSurface::close() {
  if (terminated_)
    return;
  render_session_.close();
  captured_pointer_button_ = 0;
  touch_active_ = false;
  transient_focus_active_ = false;
  terminated_ = true;
}

const NamedSurfacePolicy &HostSurface::policy() const { return policy_; }

const surface::TrustedAllocation &HostSurface::allocation() const {
  return allocation_;
}

InspectionSnapshot HostSurface::inspection() const {
  return {.plugin_id = policy_.plugin_id,
          .revision_digest = std::string(binding_.revision.view()),
          .policy_fingerprint = std::string(binding_.policy_fingerprint.view()),
          .surface_name = policy_.surface_name,
          .role = policy_.role,
          .logical_width = allocation_.logical_width,
          .logical_height = allocation_.logical_height,
          .dpr_numerator = allocation_.dpr_numerator,
          .dpr_denominator = allocation_.dpr_denominator,
          .surface_id = allocation_.surface.id,
          .surface_generation = allocation_.surface.generation,
          .frame_sequence = bridge_item_.frameSequence(),
          .pace_drops = pace_drops_,
          .input_region_count = input_regions_.size(),
          .render_active =
              render_session_.phase() == render_session::Phase::active,
          .visible = active(),
          .focused = bridge_item_.surfaceFocused(),
          .locked = locked_,
          .terminated = terminated_,
          .bridge_state = bridge_item_.inspectionState().toStdString()};
}

} // namespace omarchy::plugin_runtime::surface_host
