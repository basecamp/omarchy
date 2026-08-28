#include "remote_surface.hpp"
#include "render_input_transport.hpp"

#include "omarchy/plugin_runtime/surface/render_messages.hpp"
#include "omarchy/plugin_runtime/surface/shared_layout.hpp"

#include <QGuiApplication>
#include <QImage>
#include <QPainter>
#include <QSizeF>

#include <array>
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

surface::InputEvent pointer(surface::SurfaceKey key, std::uint64_t sequence) {
  return {.surface = key,
          .sequence = sequence,
          .kind = surface::InputKind::pointer_button,
          .x_q16 = 1U << surface::kQ16FractionBits,
          .y_q16 = 1U << surface::kQ16FractionBits,
          .delta_x_q16 = 0,
          .delta_y_q16 = 0,
          .code = 1,
          .state = static_cast<std::uint32_t>(surface::ButtonState::pressed),
          .active_touch_points = 0};
}

void test_owned_pixels_and_lifecycle() {
  auto sink = std::make_shared<RecordingSink>();
  auto transport =
      std::make_shared<bridge::AuthenticatedInputTransport>(9, sink);
  bridge::RemotePluginSurface item;
  FakeFrameProducer producer(item);
  item.bindTransport(transport);
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
  const auto copied_byte = item.ownedImage().constBits()[0];
  pixels[0] = std::byte{0};
  require(item.ownedImage().constBits()[0] == copied_byte,
          "bridge retained producer pixel memory");

  QImage target(4, 4, QImage::Format_RGBA8888_Premultiplied);
  target.fill(Qt::transparent);
  QPainter painter(&target);
  item.setSize(QSizeF(4, 4));
  item.paint(&painter);
  painter.end();
  require(!target.isNull(), "trusted surface could not paint owned pixels");

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
  require(item.suspend() &&
              !item.submitInput(pointer(allocation->surface, 1)) &&
              item.resume(),
          "suspended surface accepted input or failed to resume");
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
  item.bindTransport(transport);
  const auto allocation = surface::make_allocation({.id = 8, .generation = 3},
                                                   4, 4, 4, 4, 1, 1, 4096);
  require(allocation && item.configure(*allocation), "input fixture configure");
  const surface::FocusEvent focus{
      .surface = allocation->surface, .sequence = 1, .focused = true};
  require(
      item.submitFocus(focus) && item.surfaceFocused() && sink->calls == 1 &&
          sink->header.endpoint_role == wire::EndpointRole::render &&
          sink->header.launch_generation == 11 &&
          sink->header.role_protocol_version == surface::kRenderRoleVersion &&
          sink->header.flags == 0 &&
          sink->header.payload_length == sink->payload.size() &&
          sink->header.message_type ==
              static_cast<std::uint16_t>(surface::RenderMessageType::focus) &&
          sink->header.correlation_id == 0,
      "focus did not use authenticated render envelope");
  surface::FocusEvent decoded_focus{};
  require(surface::decode_focus_event(sink->payload, decoded_focus) &&
              decoded_focus.surface == focus.surface &&
              decoded_focus.sequence == focus.sequence &&
              decoded_focus.focused == focus.focused,
          "focus payload changed across bridge");

  const auto event = pointer(allocation->surface, 1);
  require(item.submitInput(event) && sink->calls == 2 &&
              sink->header.message_type ==
                  static_cast<std::uint16_t>(surface::RenderMessageType::input),
          "focused input did not use render transport");
  surface::InputEvent decoded_input{};
  require(surface::decode_input_event(sink->payload, decoded_input) &&
              decoded_input.surface == event.surface &&
              decoded_input.sequence == event.sequence,
          "input payload changed across bridge");
  require(!item.submitInput(event) && sink->calls == 2,
          "replayed input reached transport");
  require(!item.submitFocus({.surface = {.id = 8, .generation = 2},
                             .sequence = 2,
                             .focused = false}) &&
              sink->calls == 2 && item.surfaceFocused(),
          "stale focus event reached transport or changed local focus");

  sink->accept = false;
  require(
      !item.submitFocus(
          {.surface = allocation->surface, .sequence = 2, .focused = false}) &&
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
  item.bindTransport(invalid_transport);
  surface::TrustedAllocation invalid{};
  require(!item.configure(invalid) && !item.connected() &&
              !invalid_transport->connected() &&
              item.inspectionState() == QStringLiteral("invalid-allocation"),
          "invalid allocation became a QML-visible surface");

  auto valid_transport =
      std::make_shared<bridge::AuthenticatedInputTransport>(12, sink);
  bridge::RemotePluginSurface duplicate;
  duplicate.bindTransport(valid_transport);
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
  rebound.bindTransport(first_transport);
  rebound.bindTransport(replacement_transport);
  require(!rebound.connected() && !first_transport->connected() &&
              !replacement_transport->connected() &&
              rebound.inspectionState() == QStringLiteral("invalid-lifecycle"),
          "transport replacement changed the authenticated launch binding");

  std::shared_ptr<bridge::RenderPacketSink> missing_sink;
  bridge::AuthenticatedInputTransport missing_transport(13, missing_sink);
  require(!missing_transport.connected() && missing_transport.failed(),
          "transport accepted a missing authenticated session sink");
}

} // namespace

int main(int argc, char **argv) {
  QGuiApplication application(argc, argv);
  (void)application;
  try {
    test_owned_pixels_and_lifecycle();
    test_authenticated_focus_and_input();
    test_invalid_transport_and_allocation();
    return EXIT_SUCCESS;
  } catch (const std::exception &failure) {
    qCritical("trusted bridge test failed: %s", failure.what());
    return EXIT_FAILURE;
  }
}
