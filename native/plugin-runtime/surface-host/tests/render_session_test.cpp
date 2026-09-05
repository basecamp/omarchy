#include "render_session.hpp"

#include "remote_surface.hpp"
#include "render_input_transport.hpp"
#include "worker_runtime.hpp"

#include "omarchy/plugin_runtime/surface/render_messages.hpp"

#include <QEventLoop>
#include <QGuiApplication>
#include <QPainter>
#include <QTimer>

#include <fcntl.h>
#include <unistd.h>

#include <algorithm>
#include <array>
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <iostream>
#include <span>
#include <stdexcept>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace {

namespace bridge = omarchy::plugin_runtime::bridge;
namespace session = omarchy::plugin_runtime::render_session;
namespace surface = omarchy::plugin_runtime::surface;
namespace wire = omarchy::plugin::wire;
namespace worker = omarchy::plugin_runtime::worker;

void require(bool condition, std::string_view message) {
  if (!condition)
    throw std::runtime_error(std::string(message));
}

void wait_for_render_request(worker::WorkerRuntime &runtime,
                             int timeout_milliseconds = 100) {
  const auto deadline = std::chrono::steady_clock::now() +
                        std::chrono::milliseconds(timeout_milliseconds);
  while (!runtime.render_requested() &&
         std::chrono::steady_clock::now() < deadline) {
    QEventLoop loop;
    QTimer::singleShot(2, &loop, &QEventLoop::quit);
    loop.exec();
  }
  require(runtime.render_requested(), "timed out waiting for a dirty scene");
}

class NullInputSink final : public bridge::RenderPacketSink {
public:
  bool send(const wire::EnvelopeHeader &, std::span<const std::byte>) override {
    return true;
  }
};

class CapturingSender final : public session::PacketSender {
public:
  ~CapturingSender() override {
    if (worker_descriptor >= 0)
      close(worker_descriptor);
    if (mutation_descriptor >= 0)
      close(mutation_descriptor);
  }

  bool send(const wire::EnvelopeHeader &header,
            std::span<const std::byte> payload,
            std::span<const int> descriptors) override {
    if (fail_send || descriptors.size() > 1)
      return false;
    headers.push_back(header);
    payloads.emplace_back(payload.begin(), payload.end());
    if (!descriptors.empty()) {
      if (worker_descriptor >= 0)
        return false;
      worker_descriptor = fcntl(descriptors.front(), F_DUPFD_CLOEXEC, 64);
      mutation_descriptor = fcntl(descriptors.front(), F_DUPFD_CLOEXEC, 64);
      if (worker_descriptor < 0 || mutation_descriptor < 0)
        return false;
    }
    return true;
  }

  int take_worker_descriptor() { return std::exchange(worker_descriptor, -1); }

  std::vector<wire::EnvelopeHeader> headers;
  std::vector<std::vector<std::byte>> payloads;
  int worker_descriptor = -1;
  int mutation_descriptor = -1;
  bool fail_send = false;
};

struct Harness {
  explicit Harness(std::uint64_t generation, std::uint32_t logical_width = 64,
                   std::uint32_t logical_height = 32, std::uint32_t dpr = 1,
                   std::string_view fixture_name = "expressive")
      : runtime(std::filesystem::path(SURFACE_HOST_WORKER_FIXTURE_ROOT) /
                fixture_name),
        input_sink(std::make_shared<NullInputSink>()),
        transport(std::make_shared<bridge::AuthenticatedInputTransport>(
            generation, input_sink)),
        host(generation, item, sender) {
    require(item.bindTransport(transport), "render transport did not bind");
    const auto page_size = sysconf(_SC_PAGESIZE);
    require(page_size > 0, "system page size unavailable");
    allocation = surface::make_allocation(
        {.id = generation + 100, .generation = generation}, logical_width,
        logical_height, logical_width * dpr, logical_height * dpr, dpr, 1,
        static_cast<std::uint64_t>(page_size));
    require(allocation.has_value(), "surface allocation fixture failed");
  }

  bool receive(std::uint16_t type, std::span<const std::byte> payload,
               std::uint64_t correlation = 0) {
    return host.receive({.message_type = type,
                         .correlation_id = correlation,
                         .payload = payload});
  }

  void select_profile() {
    require(static_cast<bool>(runtime.load_manifest_entry()) &&
                host.start(*allocation) && sender.headers.size() == 1,
            "worker/host profile negotiation did not start");
    surface::ProfileOffer offer{};
    require(surface::decode_profile_offer(sender.payloads.at(0), offer) &&
                static_cast<bool>(runtime.select_software_profile(offer)),
            "worker rejected the host software-profile offer");
    const auto selected =
        surface::select_software_profile(std::array{offer.version});
    require(selected.has_value(), "profile selection fixture failed");
    const auto selected_payload = surface::encode_profile_selection(*selected);
    require(receive(static_cast<std::uint16_t>(
                        surface::RenderMessageType::profile_select),
                    selected_payload, 1) &&
                sender.headers.size() == 2 && sender.worker_descriptor >= 0,
            "host did not send the surface allocation and descriptor");
    surface::TrustedAllocation decoded{};
    const auto page_size = sysconf(_SC_PAGESIZE);
    require(surface::decode_surface_allocation(
                sender.payloads.at(1), static_cast<std::uint64_t>(page_size),
                decoded) &&
                decoded == *allocation &&
                static_cast<bool>(
                    runtime.allocate(decoded, sender.take_worker_descriptor())),
            "worker rejected the host frame region");
  }

  void negotiate() {
    select_profile();
    const auto allocated = surface::encode_surface_key(allocation->surface);
    require(
        receive(static_cast<std::uint16_t>(
                    surface::RenderMessageType::surface_allocated),
                allocated, 2) &&
            host.phase() == session::Phase::active && item.connected(),
        "surface allocation did not become active");
  }

  surface::FrameReady publish() {
    const auto frame = runtime.render();
    require(frame.has_value(), "worker did not render a frame");
    const auto payload = surface::encode_frame_ready(frame->ready);
    require(receive(static_cast<std::uint16_t>(
                        surface::RenderMessageType::frame_ready),
                    payload),
            "host rejected a valid worker frame");
    return frame->ready;
  }

  worker::WorkerRuntime runtime;
  std::shared_ptr<NullInputSink> input_sink;
  std::shared_ptr<bridge::AuthenticatedInputTransport> transport;
  bridge::RemotePluginSurface item;
  CapturingSender sender;
  session::HostRenderSession host;
  std::optional<surface::TrustedAllocation> allocation;
};

QImage painted_surface(bridge::RemotePluginSurface &item,
                       const surface::TrustedAllocation &allocation) {
  QImage image(static_cast<int>(allocation.pixel_width),
               static_cast<int>(allocation.pixel_height),
               QImage::Format_RGBA8888_Premultiplied);
  image.setDevicePixelRatio(
      static_cast<qreal>(allocation.dpr_numerator) /
      static_cast<qreal>(allocation.dpr_denominator));
  image.fill(Qt::transparent);
  item.setSize(QSizeF(allocation.logical_width, allocation.logical_height));
  QPainter painter(&image);
  item.paint(&painter);
  return image;
}

void asynchronous_change_reaches_host_surface() {
  Harness harness(38, 64, 32, 1, "async-change");
  harness.negotiate();
  static_cast<void>(harness.publish());
  const QImage first_image = painted_surface(harness.item, *harness.allocation);
  require(!harness.runtime.render().has_value(),
          "clean worker scene produced a duplicate frame");

  QEventLoop loop;
  QTimer::singleShot(60, &loop, &QEventLoop::quit);
  loop.exec();
  require(harness.runtime.render_requested(),
          "asynchronous QML change did not request a later frame");
  const auto second = harness.publish();
  require(second.frame_sequence == 2 && harness.item.frameSequence() == 2 &&
              painted_surface(harness.item, *harness.allocation) !=
                  first_image &&
              harness.host.statistics().accepted_frames == 2,
          "host did not present the asynchronous QML frame");
}

void animated_alpha_and_throughput() {
  Harness harness(31);
  harness.negotiate();
  const auto first = harness.publish();
  require(harness.item.ready() && harness.item.frameSequence() == 1,
          "trusted bridge did not expose the first copied frame");
  const QImage first_image = painted_surface(harness.item, *harness.allocation);
  const auto pixel = first_image.pixelColor(0, 0);
  require(pixel.alpha() > 0 && pixel.alpha() < 255,
          "premultiplied alpha was lost across the render loop");
  bool changed = false;
  const auto started = std::chrono::steady_clock::now();
  for (int frame = 0; frame < 120; ++frame) {
    wait_for_render_request(harness.runtime);
    static_cast<void>(harness.publish());
    changed = changed ||
              painted_surface(harness.item, *harness.allocation) != first_image;
  }
  const auto elapsed = std::chrono::steady_clock::now() - started;
  const auto &statistics = harness.host.statistics();
  require(changed && statistics.accepted_frames == 121 &&
              statistics.copied_bytes ==
                  121 * harness.allocation->frame_bytes &&
              elapsed < std::chrono::seconds(5) &&
              statistics.maximum_copy_time < std::chrono::milliseconds(50),
          "animated frame throughput or bounded copy latency regressed");
  std::cout
      << "render_session frames=" << statistics.accepted_frames
      << " copied_bytes=" << statistics.copied_bytes << " wall_us="
      << std::chrono::duration_cast<std::chrono::microseconds>(elapsed).count()
      << " max_copy_us="
      << std::chrono::duration_cast<std::chrono::microseconds>(
             statistics.maximum_copy_time)
             .count()
      << '\n';

  const auto repeated = surface::encode_frame_ready(first);
  require(!harness.receive(static_cast<std::uint16_t>(
                               surface::RenderMessageType::frame_ready),
                           repeated) &&
              harness.host.phase() == session::Phase::active &&
              harness.item.ready() &&
              harness.host.statistics().rejected_frames == 1,
          "stale frame did not preserve the last trusted image");
}

void resize_and_dpr() {
  Harness harness(32, 48, 24, 2);
  harness.negotiate();
  static_cast<void>(harness.publish());
  const auto painted = painted_surface(harness.item, *harness.allocation);
  require(painted.width() == 96 && painted.height() == 48 &&
              painted.devicePixelRatio() == 2.0 &&
              painted.pixelColor(95, 47).alpha() != 0 &&
              harness.item.implicitWidth() == 48 &&
              harness.item.implicitHeight() == 24,
          "host-owned resize or DPR was not preserved");
}

void graceful_close_releases_worker_mapping() {
  Harness harness(37);
  harness.negotiate();
  static_cast<void>(harness.publish());
  harness.host.close();
  surface::SurfaceKey released{};
  require(harness.sender.headers.size() == 3 &&
              harness.sender.headers.back().message_type ==
                  static_cast<std::uint16_t>(
                      surface::RenderMessageType::surface_release) &&
              surface::decode_surface_key(harness.sender.payloads.back(),
                                          released) &&
              released == harness.allocation->surface &&
              static_cast<bool>(harness.runtime.release(released)) &&
              !harness.runtime.allocated() && !harness.runtime.active() &&
              !harness.item.connected() && !harness.item.ready(),
          "graceful close retained the worker mapping or trusted pixels");

  Harness failed(38);
  failed.negotiate();
  failed.sender.fail_send = true;
  failed.host.close();
  require(failed.host.phase() == session::Phase::failed &&
              !failed.item.connected() && !failed.item.ready(),
          "failed release transport did not close the surface fail-closed");
}

void malformed_and_oversized_fail_closed() {
  {
    Harness harness(34);
    harness.negotiate();
    const auto frame = harness.runtime.render();
    require(frame.has_value(), "malformed-region frame fixture failed");
    const std::byte nonzero{0x7f};
    const auto offset = static_cast<off_t>(
        frame->ready.slot * harness.allocation->slot_extent + 88);
    require(pwrite(harness.sender.mutation_descriptor, &nonzero, 1, offset) ==
                1,
            "could not corrupt the untrusted frame header fixture");
    const auto payload = surface::encode_frame_ready(frame->ready);
    require(!harness.receive(static_cast<std::uint16_t>(
                                 surface::RenderMessageType::frame_ready),
                             payload) &&
                harness.host.phase() == session::Phase::failed &&
                !harness.item.ready(),
            "malformed shared frame header did not fail closed");
  }
  {
    Harness harness(39);
    require(static_cast<bool>(harness.runtime.load_manifest_entry()) &&
                harness.host.start(*harness.allocation),
            "typed above-cap fixture did not start");
    std::vector<std::byte> oversized(
        wire::payload_cap(wire::EndpointRole::render) + 1, std::byte{0x7f});
    require(!harness.host.receive(
                {.message_type = static_cast<std::uint16_t>(
                     surface::RenderMessageType::profile_select),
                 .correlation_id = 1,
                 .payload = oversized}) &&
                harness.host.phase() == session::Phase::failed &&
                !harness.item.connected() && !harness.item.ready(),
            "above-cap authenticated packet did not fail before phase progress");
  }
  {
    Harness harness(36);
    require(static_cast<bool>(harness.runtime.load_manifest_entry()) &&
                harness.host.start(*harness.allocation),
            "send-failure negotiation fixture did not start");
    surface::ProfileOffer offer{};
    require(
        surface::decode_profile_offer(harness.sender.payloads.at(0), offer) &&
            static_cast<bool>(harness.runtime.select_software_profile(offer)),
        "send-failure profile fixture was invalid");
    const auto selected =
        surface::select_software_profile(std::array{offer.version});
    require(selected.has_value(), "send-failure selection fixture failed");
    const auto selected_payload = surface::encode_profile_selection(*selected);
    harness.sender.fail_send = true;
    require(!harness.receive(static_cast<std::uint16_t>(
                                 surface::RenderMessageType::profile_select),
                             selected_payload, 1) &&
                harness.host.phase() == session::Phase::failed &&
                !harness.item.ready() && !harness.item.connected(),
            "descriptor transport failure retained the trusted surface");
  }
}

enum class RenderFailure {
  invalid_correlation,
  invalid_schema,
  unknown_type,
  typed_error,
  stale_surface,
};

void exercise_render_failure(RenderFailure failure) {
  Harness harness(51);
  if (failure == RenderFailure::stale_surface) {
    harness.select_profile();
    auto stale = harness.allocation->surface;
    ++stale.generation;
    const auto payload = surface::encode_surface_key(stale);
    require(!harness.receive(static_cast<std::uint16_t>(
                                 surface::RenderMessageType::surface_allocated),
                             payload, 2),
            "stale surface allocation was admitted");
  } else {
    require(static_cast<bool>(harness.runtime.load_manifest_entry()) &&
                harness.host.start(*harness.allocation),
            "authenticated failure fixture did not start");
    const auto selection = surface::encode_profile_selection(
        {.version = surface::kSoftwareProfileVersion,
         .pixel_format = surface::kRgba8888Premultiplied});
    if (failure == RenderFailure::invalid_correlation) {
      require(!harness.receive(static_cast<std::uint16_t>(
                                   surface::RenderMessageType::profile_select),
                               selection, 0),
              "zero-correlation profile selection was admitted");
    } else if (failure == RenderFailure::invalid_schema) {
      require(!harness.receive(static_cast<std::uint16_t>(
                                   surface::RenderMessageType::profile_select),
                               std::span(selection).first(7), 1),
              "wrong-sized profile selection was admitted");
    } else if (failure == RenderFailure::unknown_type) {
      require(!harness.receive(0x20ff, selection, 1),
              "unknown render message was admitted");
    } else {
      const auto error = surface::encode_render_error(
          {.reason = surface::RenderErrorReason::unsupported_profile,
           .failed_message_type = static_cast<std::uint16_t>(
               surface::RenderMessageType::profile_offer),
           .surface = {}});
      require(!harness.receive(
                  static_cast<std::uint16_t>(wire::CommonMessageType::typed_error),
                  error, 1),
              "render typed error incorrectly advanced the lifecycle");
    }
  }
  require(harness.host.phase() == session::Phase::failed &&
              !harness.item.connected() && !harness.item.ready() &&
              !harness.host.failure_detail().empty(),
          "adversarial authenticated render packet did not fail closed");
}

void authenticated_ingress_failures_fail_closed() {
  for (const auto failure : {RenderFailure::invalid_correlation,
                             RenderFailure::invalid_schema,
                             RenderFailure::unknown_type,
                             RenderFailure::typed_error,
                             RenderFailure::stale_surface})
    exercise_render_failure(failure);
}

} // namespace

int main(int argc, char **argv) {
  try {
    QGuiApplication application(argc, argv);
    animated_alpha_and_throughput();
    asynchronous_change_reaches_host_surface();
    resize_and_dpr();
    graceful_close_releases_worker_mapping();
    authenticated_ingress_failures_fail_closed();
    malformed_and_oversized_fail_closed();
    std::cout << "plugin render session: ok\n";
    return 0;
  } catch (const std::exception &error) {
    std::cerr << "plugin render session: " << error.what() << '\n';
    return 1;
  }
}
