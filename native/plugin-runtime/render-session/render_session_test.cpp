#include "render_session.hpp"

#include "remote_surface.hpp"
#include "render_input_transport.hpp"
#include "worker_runtime.hpp"

#include "omarchy/plugin_runtime/surface/render_messages.hpp"

#include <QEventLoop>
#include <QGuiApplication>
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

std::vector<std::byte> encode(const wire::EnvelopeHeader &header,
                              std::span<const std::byte> payload) {
  std::vector<std::byte> output(wire::kHeaderSize + payload.size());
  const auto encoded = wire::encode_packet(header, payload, output);
  require(static_cast<bool>(encoded), "test envelope encoding failed");
  output.resize(encoded.bytes_written);
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
                   std::uint32_t logical_height = 32, std::uint32_t dpr = 1)
      : generation(generation),
        runtime(std::filesystem::path(D2_WORKER_FIXTURE_ROOT) / "expressive"),
        input_sink(std::make_shared<NullInputSink>()),
        transport(std::make_shared<bridge::AuthenticatedInputTransport>(
            generation, input_sink)),
        host(generation, item, sender) {
    item.bindTransport(transport);
    const auto page_size = sysconf(_SC_PAGESIZE);
    require(page_size > 0, "system page size unavailable");
    allocation = surface::make_allocation(
        {.id = generation + 100, .generation = generation}, logical_width,
        logical_height, logical_width * dpr, logical_height * dpr, dpr, 1,
        static_cast<std::uint64_t>(page_size));
    require(allocation.has_value(), "D2 allocation fixture failed");
  }

  void negotiate() {
    require(static_cast<bool>(runtime.load_manifest_entry()) &&
                host.start(*allocation) && sender.headers.size() == 1,
            "worker/host profile negotiation did not start");
    surface::ProfileOffer offer{};
    require(surface::decode_profile_offer(sender.payloads.at(0), offer) &&
                static_cast<bool>(runtime.select_software_profile(offer)),
            "C5 worker rejected D2 software offer");
    const auto selected =
        surface::select_software_profile(std::array{offer.version});
    require(selected.has_value(), "profile selection fixture failed");
    const auto selected_payload = surface::encode_profile_selection(*selected);
    require(host.receive(encode(
                worker_header(static_cast<std::uint16_t>(
                                  surface::RenderMessageType::profile_select),
                              selected_payload.size(), generation, 1),
                selected_payload)) &&
                sender.headers.size() == 2 && sender.worker_descriptor >= 0,
            "host did not send the B4 allocation and descriptor");
    surface::TrustedAllocation decoded{};
    const auto page_size = sysconf(_SC_PAGESIZE);
    require(surface::decode_surface_allocation(
                sender.payloads.at(1), static_cast<std::uint64_t>(page_size),
                decoded) &&
                decoded == *allocation &&
                static_cast<bool>(
                    runtime.allocate(decoded, sender.take_worker_descriptor())),
            "C5 worker rejected D2 frame region");
    const auto allocated = surface::encode_surface_key(allocation->surface);
    require(
        host.receive(encode(
            worker_header(static_cast<std::uint16_t>(
                              surface::RenderMessageType::surface_allocated),
                          allocated.size(), generation, 2),
            allocated)) &&
            host.phase() == session::Phase::active && item.connected(),
        "surface allocation did not become active");
  }

  surface::FrameReady publish() {
    const auto frame = runtime.render();
    require(frame.has_value(), "C5 worker did not render a frame");
    const auto payload = surface::encode_frame_ready(frame->ready);
    require(host.receive(encode(
                worker_header(static_cast<std::uint16_t>(
                                  surface::RenderMessageType::frame_ready),
                              payload.size(), generation),
                payload)),
            "D2 host rejected a valid C5 frame");
    return frame->ready;
  }

  std::uint64_t generation;
  worker::WorkerRuntime runtime;
  std::shared_ptr<NullInputSink> input_sink;
  std::shared_ptr<bridge::AuthenticatedInputTransport> transport;
  bridge::RemotePluginSurface item;
  CapturingSender sender;
  session::HostRenderSession host;
  std::optional<surface::TrustedAllocation> allocation;
};

void animated_alpha_and_throughput() {
  Harness harness(31);
  harness.negotiate();
  const auto first = harness.publish();
  require(harness.item.ready() && harness.item.frameSequence() == 1 &&
              harness.item.ownedImage().devicePixelRatio() == 1.0,
          "trusted bridge did not expose the first copied frame");
  const auto pixel = harness.item.ownedImage().pixelColor(0, 0);
  require(pixel.alpha() > 0 && pixel.alpha() < 255,
          "premultiplied alpha was lost across the D2 loop");
  const QImage first_image = harness.item.ownedImage();
  bool changed = false;
  const auto started = std::chrono::steady_clock::now();
  for (int frame = 0; frame < 120; ++frame) {
    QEventLoop loop;
    QTimer::singleShot(2, &loop, &QEventLoop::quit);
    loop.exec();
    static_cast<void>(harness.publish());
    changed = changed || harness.item.ownedImage() != first_image;
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
      << "D2 frames=" << statistics.accepted_frames
      << " copied_bytes=" << statistics.copied_bytes << " wall_us="
      << std::chrono::duration_cast<std::chrono::microseconds>(elapsed).count()
      << " max_copy_us="
      << std::chrono::duration_cast<std::chrono::microseconds>(
             statistics.maximum_copy_time)
             .count()
      << '\n';

  const auto repeated = surface::encode_frame_ready(first);
  require(!harness.host.receive(
              encode(worker_header(static_cast<std::uint16_t>(
                                       surface::RenderMessageType::frame_ready),
                                   repeated.size(), harness.generation),
                     repeated)) &&
              harness.host.phase() == session::Phase::active &&
              harness.item.ready() &&
              harness.host.statistics().rejected_frames == 1,
          "stale frame did not preserve the last trusted image");
}

void resize_dpr_and_peer_loss() {
  Harness harness(32, 48, 24, 2);
  harness.negotiate();
  static_cast<void>(harness.publish());
  require(harness.item.ownedImage().width() == 96 &&
              harness.item.ownedImage().height() == 48 &&
              harness.item.ownedImage().devicePixelRatio() == 2.0 &&
              harness.item.implicitWidth() == 48 &&
              harness.item.implicitHeight() == 24,
          "host-owned resize or DPR was not preserved");
  harness.host.peer_lost();
  require(harness.host.phase() == session::Phase::disconnected &&
              !harness.item.connected() && !harness.item.ready(),
          "peer loss retained pixels or an active bridge");
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
    Harness harness(33);
    harness.negotiate();
    static_cast<void>(harness.publish());
    std::vector<std::byte> malformed(wire::kHeaderSize, std::byte{0});
    require(!harness.host.receive(malformed) &&
                harness.host.phase() == session::Phase::failed &&
                !harness.item.ready(),
            "malformed envelope did not clear and fail the surface");
  }
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
    require(!harness.host.receive(encode(
                worker_header(static_cast<std::uint16_t>(
                                  surface::RenderMessageType::frame_ready),
                              payload.size(), harness.generation),
                payload)) &&
                harness.host.phase() == session::Phase::failed &&
                !harness.item.ready(),
            "malformed shared frame header did not fail closed");
  }
  {
    Harness harness(35);
    harness.negotiate();
    std::vector<std::byte> oversized(
        wire::kHeaderSize + wire::payload_cap(wire::EndpointRole::render) + 1,
        std::byte{0x7f});
    require(!harness.host.receive(oversized) &&
                harness.host.phase() == session::Phase::failed &&
                !harness.item.connected(),
            "above-cap render packet did not fail closed");
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
    require(!harness.host.receive(encode(
                worker_header(static_cast<std::uint16_t>(
                                  surface::RenderMessageType::profile_select),
                              selected_payload.size(), harness.generation, 1),
                selected_payload)) &&
                harness.host.phase() == session::Phase::failed &&
                !harness.item.ready() && !harness.item.connected(),
            "descriptor transport failure retained the trusted surface");
  }
}

} // namespace

int main(int argc, char **argv) {
  try {
    QGuiApplication application(argc, argv);
    animated_alpha_and_throughput();
    resize_dpr_and_peer_loss();
    graceful_close_releases_worker_mapping();
    malformed_and_oversized_fail_closed();
    std::cout << "plugin render session: ok\n";
    return 0;
  } catch (const std::exception &error) {
    std::cerr << "plugin render session: " << error.what() << '\n';
    return 1;
  }
}
