#include "remote_surface.hpp"
#include "pointer_provenance.hpp"
#include "render_input_transport.hpp"

#include "omarchy/plugin_runtime/surface/render_messages.hpp"
#include "omarchy/plugin_runtime/surface/shared_layout.hpp"

#include <QGuiApplication>
#include <QImage>
#include <QMouseEvent>
#include <QPainter>
#include <QPointingDevice>
#include <QQuickWindow>
#include <QSizeF>
#include <QTest>
#include <QWheelEvent>

#include <algorithm>
#include <array>
#include <cstdio>
#include <cstdlib>
#include <memory>
#include <optional>
#include <stdexcept>
#include <string_view>
#include <vector>

namespace {

namespace bridge = omarchy::plugin_runtime::bridge;
namespace surface = omarchy::plugin_runtime::surface;
namespace wire = omarchy::plugin::wire;

void require(bool condition, std::string_view message) {
  if (!condition)
    throw std::runtime_error(std::string(message));
}

class RecordingSink final : public bridge::RenderPacketSink {
public:
  bool send(const wire::EnvelopeHeader &value,
            std::span<const std::byte> bytes) override {
    ++calls;
    header = value;
    payload.assign(bytes.begin(), bytes.end());
    return accept;
  }

  wire::EnvelopeHeader header{};
  std::vector<std::byte> payload;
  std::size_t calls = 0;
  bool accept = true;
};

class FakeFrameProducer final {
public:
  explicit FakeFrameProducer(surface::TrustedFrameSink &sink) : sink_(sink) {}

  bool configure(const surface::TrustedAllocation &allocation) {
    allocation_ = allocation;
    return sink_.configure(allocation);
  }

  bool publish(std::uint64_t sequence, std::span<const std::byte> pixels) {
    return allocation_.has_value() &&
           sink_.present(allocation_->surface, sequence, pixels);
  }

private:
  surface::TrustedFrameSink &sink_;
  std::optional<surface::TrustedAllocation> allocation_;
};

class RecordingInputRouter final : public bridge::HostInputRouter {
public:
  bool route(bridge::HostInputEvent event) override {
    events.push_back(std::move(event));
    return accept;
  }
  bool cancel(std::uint64_t device) override {
    cancelled_device = device;
    return accept;
  }
  std::vector<bridge::HostInputEvent> events;
  std::uint64_t cancelled_device = 0;
  bool accept = true;
};

class RecordingRegionRouter final : public bridge::HostInputRegionRouter {
public:
  bool apply(const surface::InputRegionUpdate &update) override {
    ++calls;
    last_generation = update.generation;
    return accept;
  }
  std::size_t calls = 0;
  std::uint64_t last_generation = 0;
  bool accept = true;
};

class WindowInputProbe final : public QObject {
public:
  bool eventFilter(QObject *watched, QEvent *event) override {
    (void)watched;
    if (event->type() == QEvent::MouseButtonPress) {
      const auto &mouse = *static_cast<QMouseEvent *>(event);
      saw_press = true;
      press_was_spontaneous = mouse.spontaneous();
      press_source = mouse.source();
      press_device_type = mouse.deviceType();
    }
    return false;
  }

  bool saw_press = false;
  bool press_was_spontaneous = false;
  Qt::MouseEventSource press_source = Qt::MouseEventSynthesizedByApplication;
  QInputDevice::DeviceType press_device_type =
      QInputDevice::DeviceType::Unknown;
};

class AbsorbingItem final : public QQuickItem {
public:
  explicit AbsorbingItem(QQuickItem *parent) : QQuickItem(parent) {
    setAcceptedMouseButtons(Qt::LeftButton);
  }

private:
  void mousePressEvent(QMouseEvent *event) override { event->accept(); }
  void mouseReleaseEvent(QMouseEvent *event) override { event->accept(); }
};

void test_qpa_pointer_provenance_is_captured_before_quick_redispatch() {
  QQuickWindow window;
  window.resize(96, 96);
  WindowInputProbe probe;
  window.installEventFilter(&probe);

  bridge::RemotePluginSurface item(window.contentItem());
  item.setPosition({0, 0});
  item.setSize({64, 64});
  RecordingInputRouter router;
  auto sink = std::make_shared<RecordingSink>();
  auto transport =
      std::make_shared<bridge::AuthenticatedInputTransport>(18, sink);
  const auto allocation = surface::make_allocation(
      {.id = 12, .generation = 6}, 64, 64, 64, 64, 1, 1, 4096);
  require(allocation && item.bindTransport(transport) &&
              item.configure(*allocation) && item.bindHostInputRouter(router),
          "QPA provenance fixture did not configure");

  window.show();
  QCoreApplication::processEvents();
  router.events.clear();
  QTest::mousePress(&window, Qt::LeftButton, Qt::NoModifier, {12, 18});
  QTest::mouseRelease(&window, Qt::LeftButton, Qt::NoModifier, {12, 18});
  require(probe.saw_press, "QPA window did not observe a mouse press");
  require(probe.press_was_spontaneous,
          "QPA window mouse press was not spontaneous");
  require(probe.press_source == Qt::MouseEventNotSynthesized,
          "QPA window mouse press was synthesized");
  require(probe.press_device_type == QInputDevice::DeviceType::Mouse,
          "QPA window press did not originate from a mouse device");
  const auto pointer_events = [&] {
    return std::ranges::count_if(router.events, [](const auto &input) {
      return std::holds_alternative<surface::PointerButton>(input.payload);
    });
  };
  require(pointer_events() == 2,
          "QPA press/release did not route exactly once each");
  const auto press = std::ranges::find_if(router.events, [](const auto &input) {
    const auto *button = std::get_if<surface::PointerButton>(&input.payload);
    return button != nullptr &&
           button->state == surface::ButtonState::pressed;
  });
  const auto release =
      std::ranges::find_if(router.events, [](const auto &input) {
        const auto *button =
            std::get_if<surface::PointerButton>(&input.payload);
        return button != nullptr &&
               button->state == surface::ButtonState::released;
      });
  require(press != router.events.end() && release != router.events.end() &&
              press->trusted_physical && release->trusted_physical,
          "QPA mouse press lost physical provenance before item routing");

  const auto after_physical = pointer_events();
  QMouseEvent direct_replay(
      QEvent::MouseButtonPress, QPointF(12, 18), QPointF(12, 18),
      QPointF(12, 18), Qt::LeftButton, Qt::LeftButton, Qt::NoModifier,
      Qt::MouseEventNotSynthesized);
  require(QCoreApplication::sendEvent(&item, &direct_replay) &&
              pointer_events() == after_physical + 1 &&
              !router.events.back().trusted_physical,
          "direct item replay borrowed retained QPA provenance");

  const auto after_replay = pointer_events();
  QMouseEvent synthetic_window(
      QEvent::MouseButtonPress, QPointF(12, 18), QPointF(12, 18),
      QPointF(12, 18), Qt::LeftButton, Qt::LeftButton, Qt::NoModifier,
      Qt::MouseEventNotSynthesized);
  QCoreApplication::sendEvent(&window, &synthetic_window);
  QMouseEvent application_synthesized(
      QEvent::MouseButtonPress, QPointF(12, 18), QPointF(12, 18),
      QPointF(12, 18), Qt::LeftButton, Qt::LeftButton, Qt::NoModifier,
      Qt::MouseEventSynthesizedByApplication);
  QCoreApplication::sendEvent(&window, &application_synthesized);
  require(pointer_events() == after_replay,
          "non-spontaneous window input escaped the private proxy gate");
  item.setWidth(63);
  QTest::mousePress(&window, Qt::LeftButton, Qt::NoModifier, {12, 18});
  QTest::mouseRelease(&window, Qt::LeftButton, Qt::NoModifier, {12, 18});
  require(pointer_events() == after_replay,
          "physical input escaped a mismatched allocation geometry");
  item.setWidth(64);

  AbsorbingItem unrelated(&item);
  unrelated.setSize(item.size());
  unrelated.setZ(10);
  QTest::mousePress(&window, Qt::LeftButton, Qt::NoModifier, {12, 18});
  QTest::mouseRelease(&window, Qt::LeftButton, Qt::NoModifier, {12, 18});
  require(pointer_events() == after_replay,
          "an unrelated child borrowed the private proxy provenance path");

  unrelated.setVisible(false);
  auto *touch_device = QTest::createTouchDevice();
  require(touch_device != nullptr, "QPA touch device could not be created");
  QTest::touchEvent(&window, touch_device)
      .press(0, {20, 20}, &window)
      .commit();
  QTest::touchEvent(&window, touch_device)
      .release(0, {20, 20}, &window)
      .commit();
  const auto touch_frames =
      std::ranges::count_if(router.events, [](const auto &input) {
        return std::holds_alternative<bridge::HostTouchFrame>(input.payload);
      });
  const bool touch_was_untrusted =
      std::ranges::all_of(router.events, [](const auto &input) {
        return !std::holds_alternative<bridge::HostTouchFrame>(input.payload) ||
               !input.trusted_physical;
      });
  require(touch_frames == 2 && touch_was_untrusted &&
              pointer_events() == after_replay,
          "localized QPA touch did not traverse the fail-closed parent path");
}

void test_physical_pointer_device_classification() {
  using bridge::detail::classify_pointer_provenance;

  const QPointingDevice mouse(
      QStringLiteral("mouse"), 1, QInputDevice::DeviceType::Mouse,
      QPointingDevice::PointerType::Generic, QInputDevice::Capability::Position,
      1, 5);
  const QPointingDevice touchpad(
      QStringLiteral("touchpad"), 2, QInputDevice::DeviceType::TouchPad,
      QPointingDevice::PointerType::Finger,
      QInputDevice::Capability::Position, 5, 3);
  const QPointingDevice touchscreen(
      QStringLiteral("touchscreen"), 3, QInputDevice::DeviceType::TouchScreen,
      QPointingDevice::PointerType::Finger,
      QInputDevice::Capability::Position, 10, 0);
  const QPointingDevice unknown(
      QStringLiteral("unknown"), 4, QInputDevice::DeviceType::Unknown,
      QPointingDevice::PointerType::Unknown, QInputDevice::Capability::None, 1,
      0);

  require(classify_pointer_provenance(
              true, Qt::MouseEventNotSynthesized, &mouse)
              .trusted(),
          "physical mouse device was rejected");
  require(classify_pointer_provenance(
              true, Qt::MouseEventNotSynthesized, &touchpad)
              .trusted(),
          "physical touchpad device was rejected");
  require(!classify_pointer_provenance(
               true, Qt::MouseEventSynthesizedBySystem, &touchpad)
               .trusted() &&
              !classify_pointer_provenance(
                   true, Qt::MouseEventSynthesizedByApplication, &mouse)
                   .trusted(),
          "synthesized pointer input gained physical provenance");
  require(!classify_pointer_provenance(
               true, Qt::MouseEventNotSynthesized, &unknown)
               .trusted(),
          "unknown pointer device gained physical provenance");
  require(!classify_pointer_provenance(
               true, Qt::MouseEventNotSynthesized, &touchscreen)
               .trusted(),
          "touchscreen mouse emulation gained physical provenance");
  require(!classify_pointer_provenance(
               true, Qt::MouseEventNotSynthesized, nullptr)
               .trusted() &&
              !classify_pointer_provenance(
                   false, Qt::MouseEventNotSynthesized, &touchpad)
                   .trusted(),
          "missing-device or non-spontaneous input gained provenance");
}

void test_quick_item_pointer_delivery() {
  bridge::RemotePluginSurface item;
  RecordingInputRouter router;
  auto sink = std::make_shared<RecordingSink>();
  auto transport =
      std::make_shared<bridge::AuthenticatedInputTransport>(1, sink);
  const auto allocation = surface::make_allocation(
      {.id = 1, .generation = 1}, 64, 64, 64, 64, 1, 1, 4096);
  require(allocation && item.bindTransport(transport) &&
              item.configure(*allocation) && item.bindHostInputRouter(router),
          "configured input router fixture did not bind");
  QMouseEvent press(QEvent::MouseButtonPress, QPointF(12, 34),
                    QPointF(12, 34), QPointF(12, 34), Qt::LeftButton, Qt::LeftButton,
                    Qt::NoModifier, Qt::MouseEventNotSynthesized);
  QMouseEvent release(QEvent::MouseButtonRelease, QPointF(12, 34),
                      QPointF(12, 34), QPointF(12, 34), Qt::LeftButton, Qt::NoButton,
                      Qt::NoModifier, Qt::MouseEventNotSynthesized);
  require(QCoreApplication::sendEvent(&item, &press) &&
              QCoreApplication::sendEvent(&item, &release) &&
              router.events.size() == 2 &&
              std::get<surface::PointerButton>(router.events[0].payload).state ==
                  surface::ButtonState::pressed &&
              std::get<surface::PointerButton>(router.events[1].payload).state ==
                  surface::ButtonState::released &&
              !router.events[0].trusted_physical,
          "QQuick item did not route host pointer press and release");

  QMouseEvent outside_release(
      QEvent::MouseButtonRelease, QPointF(65, 1), QPointF(65, 1),
      QPointF(65, 1), Qt::LeftButton, Qt::NoButton, Qt::NoModifier,
      Qt::MouseEventNotSynthesized);
  require(QCoreApplication::sendEvent(&item, &outside_release) &&
              router.cancelled_device != 0,
          "unrepresentable pointer release did not request exact cancel");

  router.cancelled_device = 0;
  QWheelEvent wheel_begin(QPointF(2, 2), QPointF(2, 2), QPoint(),
                          QPoint(0, 120), Qt::NoButton, Qt::NoModifier,
                          Qt::ScrollBegin, false);
  QWheelEvent wheel_update(QPointF(2, 2), QPointF(2, 2), QPoint(-3, -4),
                           QPoint(-120, -120), Qt::NoButton, Qt::NoModifier,
                           Qt::ScrollUpdate, false);
  QWheelEvent wheel_end(QPointF(65, 2), QPointF(65, 2), QPoint(), QPoint(),
                        Qt::NoButton, Qt::NoModifier, Qt::ScrollEnd, false);
  require(QCoreApplication::sendEvent(&item, &wheel_begin) &&
              QCoreApplication::sendEvent(&item, &wheel_update) &&
              std::get<surface::Wheel>(router.events.back().payload)
                      .pixel_delta_x_q16 == -(3 << 16) &&
              std::get<surface::Wheel>(router.events.back().payload)
                      .pixel_delta_y_q16 == -(4 << 16) &&
              QCoreApplication::sendEvent(&item, &wheel_end) &&
              router.cancelled_device != 0,
          "negative wheel delta or unrepresentable end was not exact");

  QMouseEvent synthesized(QEvent::MouseButtonPress, QPointF(1, 2),
                          QPointF(1, 2), QPointF(1, 2), Qt::LeftButton, Qt::LeftButton,
                          Qt::NoModifier,
                          Qt::MouseEventSynthesizedByApplication);
  require(QCoreApplication::sendEvent(&item, &synthesized) &&
              router.events.size() == 5 &&
              !router.events.back().trusted_physical,
          "QQuick item lost the synthetic-input classification");

  QMouseEvent system_synthesized(
      QEvent::MouseButtonPress, QPointF(3, 4), QPointF(3, 4), QPointF(3, 4),
      Qt::LeftButton, Qt::LeftButton, Qt::NoModifier,
      Qt::MouseEventSynthesizedBySystem);
  require(QCoreApplication::sendEvent(&item, &system_synthesized) &&
              router.events.size() == 6 &&
              !router.events.back().trusted_physical,
          "synthetic system input minted physical provenance");
}

void test_router_unbind_is_idempotent_and_identity_checked() {
  bridge::RemotePluginSurface item;
  RecordingInputRouter first;
  RecordingInputRouter unrelated;
  auto sink = std::make_shared<RecordingSink>();
  auto transport =
      std::make_shared<bridge::AuthenticatedInputTransport>(2, sink);
  const auto allocation = surface::make_allocation(
      {.id = 2, .generation = 2}, 16, 16, 16, 16, 1, 1, 4096);
  require(allocation && item.bindTransport(transport) &&
              item.configure(*allocation) && item.bindHostInputRouter(first),
          "configured input router did not bind");

  item.unbindHostInputRouter(unrelated);
  QMouseEvent routed(QEvent::MouseButtonPress, QPointF(5, 6), QPointF(5, 6),
                     QPointF(5, 6), Qt::LeftButton, Qt::LeftButton,
                     Qt::NoModifier, Qt::MouseEventNotSynthesized);
  require(QCoreApplication::sendEvent(&item, &routed) &&
              first.events.size() == 1,
          "an unrelated router detached the active pointer route");

  item.unbindHostInputRouter(first);
  item.unbindHostInputRouter(first);
  QMouseEvent detached(QEvent::MouseButtonPress, QPointF(7, 8),
                       QPointF(7, 8), QPointF(7, 8), Qt::LeftButton,
                       Qt::LeftButton, Qt::NoModifier,
                       Qt::MouseEventNotSynthesized);
  QCoreApplication::sendEvent(&item, &detached);
  require(first.events.size() == 1,
          "a detached pointer router remained callable");
}

void test_router_destruction_orders() {
  bridge::RemotePluginSurface item;
  {
    RecordingInputRouter router;
    require(item.bindHostInputRouter(router), "input router did not bind");
    item.unbindHostInputRouter(router);
  }
  QMouseEvent after_router(QEvent::MouseButtonPress, QPointF(1, 1),
                           QPointF(1, 1), QPointF(1, 1), Qt::LeftButton,
                           Qt::LeftButton, Qt::NoModifier,
                           Qt::MouseEventNotSynthesized);
  QCoreApplication::sendEvent(&item, &after_router);

  auto sink = std::make_shared<RecordingSink>();
  auto transport =
      std::make_shared<bridge::AuthenticatedInputTransport>(16, sink);
  require(item.bindTransport(transport), "input transport did not bind");
  const auto allocation = surface::make_allocation({.id = 10, .generation = 4},
                                                   2, 2, 2, 2, 1, 1, 4096);
  require(allocation && item.configure(*allocation),
          "input-region teardown fixture configure");
  const surface::InputRegionUpdate update{
      .surface = allocation->surface,
      .generation = 1,
      .count = 0,
  };
  {
    RecordingRegionRouter router;
    RecordingRegionRouter unrelated;
    require(item.bindHostInputRegionRouter(router),
            "input-region router did not bind");
    require(!item.bindHostInputRegionRouter(unrelated),
            "a second input-region router replaced the trusted route");
    item.unbindHostInputRegionRouter(unrelated);
    require(item.updateInputRegions(update) && router.calls == 1 &&
                router.last_generation == 1,
            "an unrelated router detached the active input-region route");
    item.unbindHostInputRegionRouter(router);
    item.unbindHostInputRegionRouter(router);
  }
  auto newer_update = update;
  newer_update.generation = 2;
  require(!item.updateInputRegions(newer_update),
          "input-region routing survived router teardown");

  RecordingInputRouter surviving_router;
  {
    auto short_lived_item = std::make_unique<bridge::RemotePluginSurface>();
    require(short_lived_item->bindHostInputRouter(surviving_router),
            "surviving pointer router did not bind");
  }
  require(surviving_router.events.empty(),
          "surface teardown unexpectedly called its surviving router");
}

void test_input_region_projection_is_post_router_and_stable_on_reject() {
  auto sink = std::make_shared<RecordingSink>();
  auto transport =
      std::make_shared<bridge::AuthenticatedInputTransport>(17, sink);
  bridge::RemotePluginSurface item;
  require(item.bindTransport(transport), "input transport did not bind");
  const auto allocation = surface::make_allocation({.id = 11, .generation = 5},
                                                   20, 10, 20, 10, 1, 1, 4096);
  require(allocation && item.configure(*allocation),
          "input-region projection fixture configure");
  RecordingRegionRouter router;
  require(item.bindHostInputRegionRouter(router),
          "input-region projection router did not bind");

  surface::InputRegionUpdate accepted{
      .surface = allocation->surface,
      .generation = 1,
      .regions = {{{.x = 2, .y = 3, .width = 4, .height = 5}}},
      .count = 1,
  };
  require(item.updateInputRegions(accepted) && router.calls == 1 &&
              item.inputRegions() == QList<QRect>{QRect(2, 3, 4, 5)},
          "router-accepted regions were not projected exactly");

  auto stale = accepted;
  stale.generation = 1;
  stale.regions[0].x = 9;
  require(!item.updateInputRegions(stale) && router.calls == 1 &&
              item.inputRegions() == QList<QRect>{QRect(2, 3, 4, 5)},
          "stale regions reached the router or replaced accepted state");

  auto wrong_surface = accepted;
  wrong_surface.surface.generation--;
  wrong_surface.generation = 2;
  require(!item.updateInputRegions(wrong_surface) && router.calls == 1 &&
              item.inputRegions() == QList<QRect>{QRect(2, 3, 4, 5)},
          "wrong-surface regions replaced accepted state");

  router.accept = false;
  auto rejected = accepted;
  rejected.generation = 2;
  rejected.regions[0].x = 8;
  require(!item.updateInputRegions(rejected) && router.calls == 2 &&
              item.inputRegions() == QList<QRect>{QRect(2, 3, 4, 5)},
          "router-rejected regions replaced accepted state");

  router.accept = true;
  auto cleared = accepted;
  cleared.generation = 3;
  cleared.count = 0;
  require(item.updateInputRegions(cleared) && item.inputRegions().isEmpty(),
          "accepted empty regions did not clear projected state");

  auto restored = accepted;
  restored.generation = 4;
  require(item.updateInputRegions(restored) && !item.inputRegions().isEmpty(),
          "accepted regions were not restored");
  const auto calls_before_destroy = router.calls;
  item.disconnect();
  require(item.inputRegions().isEmpty(),
          "surface teardown retained projected input regions");
  auto after_destroy = accepted;
  after_destroy.generation = 5;
  require(!item.updateInputRegions(after_destroy) &&
              router.calls == calls_before_destroy &&
              item.inputRegions().isEmpty(),
          "destroying surface repopulated regions or reached the router");
  item.unbindHostInputRegionRouter(router);
}

surface::InputEvent pointer(surface::SurfaceKey key, std::uint64_t sequence) {
  return {.surface = key,
          .sequence = sequence,
          .payload = surface::PointerButton{
              .position = {1U << surface::kQ16FractionBits,
                           1U << surface::kQ16FractionBits},
              .button = static_cast<std::uint32_t>(Qt::LeftButton),
              .state = surface::ButtonState::pressed,
              .buttons = static_cast<std::uint32_t>(Qt::LeftButton)}};
}

void test_owned_pixels_and_lifecycle() {
  auto sink = std::make_shared<RecordingSink>();
  auto transport =
      std::make_shared<bridge::AuthenticatedInputTransport>(9, sink);
  bridge::RemotePluginSurface item;
  FakeFrameProducer producer(item);
  require(item.bindTransport(transport), "input transport did not bind");
  const auto allocation = surface::make_allocation({.id = 7, .generation = 2},
                                                   2, 2, 2, 2, 1, 1, 4096);
  require(allocation && producer.configure(*allocation) && item.connected() &&
              !item.ready() && item.surfaceId() == 7 &&
              item.surfaceGeneration() == 2,
          "trusted surface configuration failed");
  std::vector<std::byte> pixels(allocation->frame_bytes, std::byte{0x20});
  pixels[0] = std::byte{0xff};
  require(producer.publish(1, pixels) && item.ready() &&
              item.frameSequence() == 1,
          "trusted frame presentation failed");
  const auto copied_byte = std::to_integer<unsigned char>(pixels[0]);
  pixels[0] = std::byte{0};

  QImage target(4, 4, QImage::Format_RGBA8888_Premultiplied);
  target.fill(Qt::transparent);
  QPainter painter(&target);
  item.setSize(QSizeF(4, 4));
  item.paint(&painter);
  painter.end();
  require(!target.isNull() && target.constBits()[0] == copied_byte,
          "trusted surface retained producer memory or failed to paint it");

  std::vector<std::byte> short_pixels(allocation->frame_bytes - 1);
  require(!producer.publish(2, short_pixels) && item.ready() &&
              item.frameSequence() == 1 &&
              item.inspectionState() == QStringLiteral("invalid-pixels"),
          "malformed frame replaced the last valid image");
  require(!producer.publish(1, pixels) && item.ready() &&
              item.frameSequence() == 1,
          "replayed frame replaced the last valid image");
  require(!item.present({.id = 7, .generation = 1}, 2, pixels) && item.ready(),
          "stale surface generation replaced trusted pixels");
  item.disconnect();
  require(!item.connected() && !item.ready() && !item.surfaceFocused() &&
              item.inspectionState() == QStringLiteral("disconnected"),
          "disconnect retained visible or focused plugin state");
}

void test_authenticated_focus_and_input() {
  auto sink = std::make_shared<RecordingSink>();
  auto transport =
      std::make_shared<bridge::AuthenticatedInputTransport>(11, sink);
  bridge::RemotePluginSurface item;
  require(item.bindTransport(transport), "input transport did not bind");
  const auto allocation = surface::make_allocation({.id = 8, .generation = 3},
                                                   4, 4, 4, 4, 1, 1, 4096);
  require(allocation && item.configure(*allocation), "input fixture configure");
  const surface::InputEvent focus{
      .surface = allocation->surface,
      .sequence = 1,
      .payload = surface::FocusChanged{.focused = true}};
  require(
      item.submitInput(focus) && item.surfaceFocused() && sink->calls == 1 &&
          sink->header.endpoint_role == wire::EndpointRole::render &&
          sink->header.launch_generation == 11 &&
          sink->header.role_protocol_version == surface::kRenderRoleVersion &&
          sink->header.flags == 0 &&
          sink->header.payload_length == sink->payload.size() &&
          sink->header.message_type ==
              static_cast<std::uint16_t>(surface::RenderMessageType::input) &&
          sink->header.correlation_id == 0,
      "focus did not use authenticated render envelope");
  surface::InputEvent decoded_focus{};
  require(surface::decode_input_event(sink->payload, decoded_focus) &&
              decoded_focus == focus,
          "focus payload changed across bridge");

  const auto event = pointer(allocation->surface, 2);
  require(item.submitInput(event) && sink->calls == 2 &&
              sink->header.message_type ==
                  static_cast<std::uint16_t>(surface::RenderMessageType::input),
          "focused input did not use render transport");
  surface::InputEvent decoded_input{};
  require(surface::decode_input_event(sink->payload, decoded_input) &&
              decoded_input.surface == event.surface &&
              decoded_input.sequence == event.sequence,
          "input payload changed across bridge");
  require(!item.submitInput({.surface = {.id = 8, .generation = 2},
                             .sequence = 3,
                             .payload = surface::FocusChanged{.focused = false}}) &&
              sink->calls == 2 && item.surfaceFocused(),
          "stale focus event reached transport or changed local focus");

  sink->accept = false;
  require(
      !item.submitInput(
          {.surface = allocation->surface,
           .sequence = 3,
           .payload = surface::FocusChanged{.focused = false}}) &&
          !item.connected() && !item.ready() && transport->failed(),
      "transport failure did not clear and disconnect surface");
}

void test_invalid_transport_and_allocation() {
  auto sink = std::make_shared<RecordingSink>();
  auto invalid_transport =
      std::make_shared<bridge::AuthenticatedInputTransport>(0, sink);
  require(!invalid_transport->connected() && invalid_transport->failed(),
          "zero-generation transport was usable");
  bridge::RemotePluginSurface item;
  require(!item.bindTransport(invalid_transport),
          "invalid input transport bound");
  surface::TrustedAllocation invalid{};
  require(!item.configure(invalid) && !item.connected() &&
              !invalid_transport->connected() &&
              item.inspectionState() == QStringLiteral("invalid-allocation"),
          "invalid allocation became a QML-visible surface");

  auto valid_transport =
      std::make_shared<bridge::AuthenticatedInputTransport>(12, sink);
  bridge::RemotePluginSurface duplicate;
  require(duplicate.bindTransport(valid_transport),
          "valid input transport did not bind");
  const auto allocation = surface::make_allocation({.id = 9, .generation = 1},
                                                   2, 2, 2, 2, 1, 1, 4096);
  require(allocation && duplicate.configure(*allocation) &&
              !duplicate.configure(*allocation) && !duplicate.connected() &&
              !valid_transport->connected(),
          "duplicate configure did not terminate the bound session");
  std::vector<std::byte> pixels(allocation->frame_bytes, std::byte{0xff});
  require(!duplicate.present(allocation->surface, 1, pixels) &&
              !duplicate.ready(),
          "terminal lifecycle failure allowed frame resurrection");

  auto first_transport =
      std::make_shared<bridge::AuthenticatedInputTransport>(14, sink);
  auto replacement_transport =
      std::make_shared<bridge::AuthenticatedInputTransport>(15, sink);
  bridge::RemotePluginSurface rebound;
  require(rebound.bindTransport(first_transport) &&
              !rebound.bindTransport(replacement_transport) &&
              first_transport->connected() &&
              !replacement_transport->connected(),
          "transport replacement changed the authenticated launch binding");

  std::shared_ptr<bridge::RenderPacketSink> missing_sink;
  bridge::AuthenticatedInputTransport missing_transport(13, missing_sink);
  require(!missing_transport.connected() && missing_transport.failed(),
          "transport accepted a missing authenticated session sink");
}

void test_input_authority_sequence_focus_capture_and_touch_identity() {
  bridge::TrustedInputAuthority authority;
  const auto first = surface::make_allocation({.id = 21, .generation = 3},
                                              8, 8, 8, 8, 1, 1, 4096);
  const auto second = surface::make_allocation({.id = 22, .generation = 3},
                                               8, 8, 8, 8, 1, 1, 4096);
  require(first && second, "authority allocation fixture failed");

  const surface::InputPoint point{.x_q16 = 1U << surface::kQ16FractionBits,
                                  .y_q16 = 1U << surface::kQ16FractionBits};
  auto press = authority.admit(
      *first,
      {.payload = surface::PointerButton{
           .position = point,
           .button = static_cast<std::uint32_t>(Qt::LeftButton),
           .state = surface::ButtonState::pressed,
           .buttons = static_cast<std::uint32_t>(Qt::LeftButton)},
       .device = 41,
       .trusted_physical = true},
      true);
  require(press && press->event.sequence == 1 && press->trusted_gesture &&
              authority.pointer_captured(first->surface, 41) &&
              !authority.pointer_captured(first->surface, 42) &&
              !authority.pointer_captured(second->surface, 41),
          "pointer activation did not mint one exact capture lease");

  require(!authority.admit(
      *second,
      {.payload = surface::PointerMotion{.position = point, .buttons = 0},
       .device = 42,
       .trusted_physical = true},
      true) &&
              !authority.admit(
                  *first,
                  {.payload = surface::PointerMotion{
                       .position = point,
                       .buttons = static_cast<std::uint32_t>(Qt::LeftButton)},
                   .device = 42,
                   .trusted_physical = true},
                  true),
          "wrong-device motion borrowed another surface's pointer capture");
  auto release = authority.admit(
      *first,
      {.payload = surface::PointerButton{
           .position = point,
           .button = static_cast<std::uint32_t>(Qt::LeftButton),
           .state = surface::ButtonState::released,
           .buttons = 0},
       .device = 41,
       .trusted_physical = true},
      true);
  require(release && release->event.sequence == 2 &&
              !authority.pointer_captured(first->surface, 41),
          "exact pointer release did not clear capture");

  auto interleaved = authority.admit(
      *second,
      {.payload = surface::PointerMotion{.position = point, .buttons = 0},
       .device = 42,
       .trusted_physical = true},
      true);
  require(interleaved && interleaved->event.sequence == 3,
          "cross-surface input did not share one global sequence");

  auto focus_first = authority.admit(
      *first, {.payload = surface::FocusChanged{.focused = true}}, true);
  auto invalid_switch = authority.admit(
      *second, {.payload = surface::FocusChanged{.focused = true}}, true);
  auto blur_first = authority.admit(
      *first, {.payload = surface::FocusChanged{.focused = false}}, true);
  auto focus_second = authority.admit(
      *second, {.payload = surface::FocusChanged{.focused = true}}, true);
  require(focus_first && focus_first->event.sequence == 4 &&
              !invalid_switch && blur_first && blur_first->event.sequence == 5 &&
              focus_second && focus_second->event.sequence == 6 &&
              authority.focused_surface() == second->surface,
          "focus switch was not ordered old-false before new-true");

  bridge::HostTouchFrame begin;
  begin.phase = surface::TouchFramePhase::begin;
  begin.count = 1;
  begin.points[0] = {.id = 400,
                     .state = surface::TouchPointState::pressed,
                     .position = point};
  auto touch_begin = authority.admit(
      *first,
      {.payload = begin, .device = 51, .trusted_physical = true}, true);
  require(touch_begin && touch_begin->event.sequence == 7 &&
              std::get<surface::TouchFrame>(touch_begin->event.payload)
                      .points[0]
                      .id == 0 &&
              authority.touch_captured(first->surface, 51),
          "raw touch identity was not normalized into an exact capture");

  bridge::HostTouchFrame update = begin;
  update.phase = surface::TouchFramePhase::update;
  update.points[0].state = surface::TouchPointState::updated;
  require(!authority.admit(
              *first,
              {.payload = update, .device = 52, .trusted_physical = true},
              true) &&
              !authority.admit(
                  *second,
                  {.payload = update,
                   .device = 51,
                   .trusted_physical = true},
                  true),
          "wrong-device or wrong-surface touch borrowed contact identity");

  auto omitted = update;
  omitted.points[0] = {.id = 401,
                       .state = surface::TouchPointState::pressed,
                       .position = point};
  require(!authority.admit(
              *first,
              {.payload = omitted, .device = 51, .trusted_physical = true},
              true),
          "partial touch frame omitted an already-active contact");

  auto add_contact = update;
  add_contact.count = 2;
  add_contact.points[0].state = surface::TouchPointState::stationary;
  add_contact.points[1] = {.id = 401,
                           .state = surface::TouchPointState::pressed,
                           .position = point};
  auto added = authority.admit(
      *first,
      {.payload = add_contact, .device = 51, .trusted_physical = true}, true);
  require(added && added->event.sequence == 8,
          "complete touch frame could not add a second contact");

  auto end = add_contact;
  end.phase = surface::TouchFramePhase::end;
  end.points[0].state = surface::TouchPointState::released;
  end.points[1].state = surface::TouchPointState::released;
  auto touch_end = authority.admit(
      *first, {.payload = end, .device = 51, .trusted_physical = true}, true);
  begin.points[0].id = 900;
  auto reused = authority.admit(
      *first,
      {.payload = begin, .device = 51, .trusted_physical = true}, true);
  require(touch_end && touch_end->event.sequence == 9 && reused &&
              reused->event.sequence == 10 &&
              std::get<surface::TouchFrame>(reused->event.payload)
                      .points[0]
                      .id == 0,
          "released touch slots were not deterministically reusable");
  const auto cancelled = authority.cancel(*first);
  authority.release(second->surface);
  require(cancelled && cancelled->sequence == 11 &&
              !authority.touch_captured(first->surface, 51) &&
              !authority.focused_surface(),
          "cancel/release did not clear authority state");
  begin.points[0].id = 1200;
  auto after_cancel = authority.admit(
      *first,
      {.payload = begin, .device = 52, .trusted_physical = true}, true);
  require(after_cancel && after_cancel->event.sequence == 12 &&
              std::get<surface::TouchFrame>(after_cancel->event.payload)
                      .points[0]
                      .id == 0 &&
              authority.touch_captured(first->surface, 52),
          "terminal cancel retained touch owner or raw-contact identity");
  authority.release(first->surface);
}

void test_synthesized_activation_routes_without_privileged_provenance() {
  bridge::TrustedInputAuthority authority;
  const auto allocation = surface::make_allocation(
      {.id = 31, .generation = 4}, 8, 8, 8, 8, 1, 1, 4096);
  require(allocation.has_value(),
          "synthetic authority allocation fixture failed");
  const surface::InputPoint point{.x_q16 = 1U << surface::kQ16FractionBits,
                                  .y_q16 = 1U << surface::kQ16FractionBits};
  auto press = authority.admit(
      *allocation,
      {.payload = surface::PointerButton{
           .position = point,
           .button = static_cast<std::uint32_t>(Qt::LeftButton),
           .state = surface::ButtonState::pressed,
           .buttons = static_cast<std::uint32_t>(Qt::LeftButton)},
       .device = 61,
       .trusted_physical = false},
      true);
  require(press && !press->trusted_gesture &&
              authority.pointer_captured(allocation->surface, 61) &&
              !authority.surface_has_physical_activation(allocation->surface),
          "synthetic pointer routing lease gained privileged provenance");
  const auto cancelled = authority.cancel(*allocation);
  require(cancelled &&
              !authority.pointer_captured(allocation->surface, 61),
          "synthetic pointer routing lease did not cancel cleanly");
}

} // namespace

int main(int argc, char **argv) {
  QGuiApplication application(argc, argv);
  (void)application;
  try {
    test_qpa_pointer_provenance_is_captured_before_quick_redispatch();
    test_physical_pointer_device_classification();
    test_quick_item_pointer_delivery();
    test_router_unbind_is_idempotent_and_identity_checked();
    test_router_destruction_orders();
    test_input_region_projection_is_post_router_and_stable_on_reject();
    test_owned_pixels_and_lifecycle();
    test_authenticated_focus_and_input();
    test_invalid_transport_and_allocation();
    test_input_authority_sequence_focus_capture_and_touch_identity();
    test_synthesized_activation_routes_without_privileged_provenance();
    return EXIT_SUCCESS;
  } catch (const std::exception &failure) {
    std::fprintf(stderr, "trusted bridge test failed: %s\n", failure.what());
    return EXIT_FAILURE;
  }
}
