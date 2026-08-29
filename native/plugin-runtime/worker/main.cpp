#include "worker_channel.hpp"
#include "qml_broker_api.hpp"
#include "sidecar_supervisor.hpp"
#include "worker_runtime.hpp"
#include "omarchy/plugin/wire/control.hpp"

#include "manifest_contract.hpp"

#include "omarchy/plugin_runtime/Version.h"
#include "omarchy/plugin_runtime/surface/render_messages.hpp"

#include <QGuiApplication>
#include <QSocketNotifier>
#include <QStringList>
#include <QTextStream>
#include <QTimer>

#include <fcntl.h>
#include <sys/socket.h>
#include <unistd.h>

#include <array>
#include <cstdlib>
#include <fstream>
#include <memory>
#include <span>
#include <string>

namespace {

namespace surface = omarchy::plugin_runtime::surface;
namespace worker = omarchy::plugin_runtime::worker;
namespace wire = omarchy::plugin::wire;

constexpr int kControlDescriptor = 3;
constexpr int kBrokerDescriptor = 4;
constexpr int kRenderDescriptor = 5;
constexpr std::uint16_t kControlRoleVersion = 1;
constexpr std::uint16_t kBrokerRoleVersion = 1;

bool exact_environment(std::string_view name, std::string_view expected) {
  const std::string owned(name);
  const auto *value = std::getenv(owned.c_str());
  return value != nullptr && std::string_view(value) == expected;
}

bool socket_descriptor(int descriptor) {
  int type = 0;
  socklen_t size = sizeof(type);
  return fcntl(descriptor, F_GETFD) >= 0 &&
         getsockopt(descriptor, SOL_SOCKET, SO_TYPE, &type, &size) == 0 &&
         size == sizeof(type) && type == SOCK_SEQPACKET;
}

bool trusted_launch_environment() {
  return getpid() == 1 && getuid() == 0 && getgid() == 0 &&
         socket_descriptor(kControlDescriptor) &&
         socket_descriptor(kBrokerDescriptor) &&
         socket_descriptor(kRenderDescriptor) &&
         exact_environment("HOME", "/home/plugin") &&
         exact_environment("PWD", "/plugin") &&
         exact_environment("QT_QPA_PLATFORM", "offscreen") &&
         exact_environment("QSG_RHI_BACKEND", "software") &&
         exact_environment("XDG_RUNTIME_DIR", "/run/plugin");
}

std::string read_manifest() {
  std::ifstream input("/plugin/manifest.json", std::ios::binary);
  if (!input.good())
    return {};
  return {std::istreambuf_iterator<char>(input),
          std::istreambuf_iterator<char>()};
}

class WorkerApplication {
public:
  explicit WorkerApplication(
      const omarchy::plugins::manifest::ManifestV2 &manifest)
      : runtime_("/plugin"),
        control_(kControlDescriptor, wire::EndpointRole::control,
                 kControlRoleVersion),
        broker_(kBrokerDescriptor, wire::EndpointRole::broker,
                kBrokerRoleVersion),
        render_(kRenderDescriptor, wire::EndpointRole::render,
                surface::kRenderRoleVersion),
        schemas_{surface::render_role_schema()}, registry_(schemas_),
        control_notifier_(kControlDescriptor, QSocketNotifier::Read),
        broker_notifier_(kBrokerDescriptor, QSocketNotifier::Read),
        render_notifier_(kRenderDescriptor, QSocketNotifier::Read),
        manifest_(manifest) {
    QObject::connect(&control_notifier_, &QSocketNotifier::activated,
                     [&] { receive(control_); });
    QObject::connect(&broker_notifier_, &QSocketNotifier::activated,
                     [&] { receive(broker_); });
    QObject::connect(&render_notifier_, &QSocketNotifier::activated,
                     [&] { receive(render_); });
    frame_timer_.setInterval(16);
    QObject::connect(&frame_timer_, &QTimer::timeout, [&] { publish_frame(); });
  }

  bool start() {
    if (!control_.valid() || !broker_.valid() || !render_.valid())
      return fatal("inherited endpoint baseline failed");
    if (!control_.send_hello() || !broker_.send_hello() ||
        !render_.send_hello())
      return fatal("cannot send required endpoint HELLO");
    return true;
  }

private:
  bool fatal(std::string_view detail) {
    const std::string diagnostic = "omarchy-plugin-qml-worker: " +
                                   std::string(detail) + "\n";
    static_cast<void>(write(STDERR_FILENO, diagnostic.data(),
                            diagnostic.size()));
    control_notifier_.setEnabled(false);
    broker_notifier_.setEnabled(false);
    render_notifier_.setEnabled(false);
    frame_timer_.stop();
    QCoreApplication::exit(70);
    return false;
  }

  void receive(worker::WorkerEndpoint &endpoint) {
    auto packet = endpoint.receive();
    if (!packet) {
      fatal(packet.detail);
      return;
    }
    if (!endpoint.selected()) {
      if (!endpoint.accept_welcome(packet)) {
        fatal(endpoint.last_error());
        return;
      }
      if (readiness_.observe(endpoint.role(), endpoint.generation()) !=
          wire::FatalReason::none) {
        fatal("endpoint generations disagree");
        return;
      }
      bool ready = false;
      if (readiness_.ready(ready) != wire::FatalReason::none) {
        fatal("endpoint readiness failed");
        return;
      }
      if (ready)
        ready_runtime();
      return;
    }
    if (endpoint.role() == wire::EndpointRole::broker && broker_api_) {
      if (!broker_api_->receive(std::move(packet)))
        fatal("broker response failed runtime validation");
      return;
    }
    if (endpoint.role() == wire::EndpointRole::control && broker_api_) {
      if (packet.header.message_type != wire::kPermissionSnapshotMessage ||
          packet.header.correlation_id != 0 || !packet.descriptors.empty() ||
          !broker_api_->applyHostPermissionSnapshotPayload(
              packet.header.launch_generation, packet.payload)) {
        fatal("permission snapshot failed runtime validation");
        return;
      }
      if (!runtime_loaded_ && !runtime_load_pending_) {
        runtime_load_pending_ = true;
        QTimer::singleShot(0, [&] {
          const auto loaded = runtime_.load_manifest_entry();
          if (!loaded) {
            fatal(loaded.detail);
            return;
          }
          runtime_loaded_ = true;
          runtime_load_pending_ = false;
          if (!control_.send(wire::kPermissionSnapshotAcceptedMessage, {}, 0))
            fatal("permission snapshot acknowledgement failed");
        });
      } else if (runtime_loaded_ &&
                 !control_.send(wire::kPermissionSnapshotAcceptedMessage, {},
                                0)) {
        fatal("permission snapshot acknowledgement failed");
      }
      return;
    }
    if (endpoint.role() != wire::EndpointRole::render || !render_state_) {
      fatal("unexpected post-negotiation control traffic");
      return;
    }
    const wire::PacketView view{.header = packet.header,
                                .payload = packet.payload};
    if (!render_state_->accept(view, wire::Direction::host_to_worker)) {
      fatal("render endpoint state rejected host packet");
      return;
    }
    handle_render(packet);
  }

  void ready_runtime() {
    // Trusted Qt type preparation may run a nested Qt event loop. Keep all
    // authenticated endpoints quiescent until the broker API and steady-state
    // filter are fully installed; queued packets remain on their sockets.
    control_notifier_.setEnabled(false);
    broker_notifier_.setEnabled(false);
    render_notifier_.setEnabled(false);
    render_state_ = std::make_unique<wire::SelectedEndpointState<32>>(
        wire::EndpointRole::render, render_.selected_version(),
        render_.generation(), render_.maximum_payload(),
        render_.maximum_in_flight(), registry_);
    const auto trusted_types = runtime_.prepare_trusted_qt_types();
    if (!trusted_types) {
      fatal(trusted_types.detail);
      return;
    }
    std::string seccomp_error;
    if (!worker::install_steady_state_seccomp(seccomp_error)) {
      fatal(seccomp_error);
      return;
    }
    broker_api_ = std::make_unique<worker::QmlBrokerApi>(
        broker_, std::make_unique<worker::ManifestInvokeEncoder>(manifest_),
        manifest_, broker_.generation());
    const auto bound = runtime_.bind_runtime_api(*broker_api_);
    if (!bound) {
      fatal(bound.detail);
      return;
    }
    control_notifier_.setEnabled(true);
    broker_notifier_.setEnabled(true);
    render_notifier_.setEnabled(true);
    // QML is loaded only after the authenticated host supplies the initial
    // permission snapshot, so feature decisions never observe guessed grants.
  }

  bool validate_outgoing(std::uint16_t type, std::span<const std::byte> payload,
                         std::uint64_t correlation) {
    const wire::PacketView view{
        .header = {.endpoint_role = wire::EndpointRole::render,
                   .message_type = type,
                   .role_protocol_version = render_.selected_version(),
                   .payload_length = static_cast<std::uint32_t>(payload.size()),
                   .launch_generation = render_.generation(),
                   .correlation_id = correlation},
        .payload = payload};
    return render_state_ && static_cast<bool>(render_state_->accept(
                                view, wire::Direction::worker_to_host));
  }

  bool send_render(std::uint16_t type, std::span<const std::byte> payload,
                   std::uint64_t correlation) {
    if (!validate_outgoing(type, payload, correlation) ||
        !render_.send(type, payload, correlation))
      return fatal("render response failed protocol validation or send");
    return true;
  }

  void typed_error(const worker::RuntimeResult &result,
                   std::uint16_t failed_type, surface::SurfaceKey surface_key,
                   std::uint64_t correlation) {
    surface::RenderErrorReason reason =
        surface::RenderErrorReason::invalid_allocation;
    if (result.failure == worker::RuntimeFailure::profile_not_selected)
      reason = surface::RenderErrorReason::unsupported_profile;
    else if (result.failure == worker::RuntimeFailure::object_limit)
      reason = surface::RenderErrorReason::resource_limit;
    else if (result.failure == worker::RuntimeFailure::stale_surface)
      reason = surface::RenderErrorReason::stale_surface;
    const auto payload =
        surface::encode_render_error({.reason = reason,
                                      .failed_message_type = failed_type,
                                      .surface = surface_key});
    if (!send_render(
            static_cast<std::uint16_t>(wire::CommonMessageType::typed_error),
            payload, correlation))
      return;
  }

  void handle_render(worker::ReceivedPacket &packet) {
    const auto type =
        static_cast<surface::RenderMessageType>(packet.header.message_type);
    if (type == surface::RenderMessageType::profile_offer) {
      surface::ProfileOffer offer{};
      if (!surface::decode_profile_offer(packet.payload, offer)) {
        fatal("malformed profile offer");
        return;
      }
      const auto result = runtime_.select_software_profile(offer);
      if (!result) {
        typed_error(result, packet.header.message_type, {},
                    packet.header.correlation_id);
        return;
      }
      const auto selection =
          surface::select_software_profile(std::array{offer.version});
      const auto payload = surface::encode_profile_selection(*selection);
      send_render(static_cast<std::uint16_t>(
                      surface::RenderMessageType::profile_select),
                  payload, packet.header.correlation_id);
      return;
    }
    if (type == surface::RenderMessageType::surface_allocate) {
      surface::TrustedAllocation allocation{};
      const auto page_size = sysconf(_SC_PAGESIZE);
      if (page_size <= 0 ||
          !surface::decode_surface_allocation(
              packet.payload, static_cast<std::uint64_t>(page_size),
              allocation)) {
        fatal("malformed trusted surface allocation");
        return;
      }
      const auto result =
          runtime_.allocate(allocation, packet.take_only_descriptor());
      if (!result) {
        typed_error(result, packet.header.message_type, allocation.surface,
                    packet.header.correlation_id);
        return;
      }
      const auto payload = surface::encode_surface_key(allocation.surface);
      if (send_render(static_cast<std::uint16_t>(
                          surface::RenderMessageType::surface_allocated),
                      payload, packet.header.correlation_id)) {
        frame_timer_.start();
        publish_frame();
      }
      return;
    }
    surface::SurfaceKey key{};
    if (type == surface::RenderMessageType::surface_release ||
        type == surface::RenderMessageType::surface_suspend ||
        type == surface::RenderMessageType::surface_resume) {
      if (!surface::decode_surface_key(packet.payload, key)) {
        fatal("malformed surface lifecycle key");
        return;
      }
      worker::RuntimeResult result;
      if (type == surface::RenderMessageType::surface_release)
        result = runtime_.release(key);
      else if (type == surface::RenderMessageType::surface_suspend)
        result = runtime_.suspend(key);
      else
        result = runtime_.resume(key);
      if (!result) {
        fatal(result.detail);
        return;
      }
      if (type == surface::RenderMessageType::surface_release)
        frame_timer_.stop();
      return;
    }
    if (type == surface::RenderMessageType::focus) {
      surface::FocusEvent event{};
      if (!surface::decode_focus_event(packet.payload, event) ||
          !runtime_.focus(event))
        fatal("focus event failed validation");
      return;
    }
    if (type == surface::RenderMessageType::input) {
      surface::InputEvent event{};
      if (!surface::decode_input_event(packet.payload, event) ||
          !runtime_.input(event))
        fatal("input event failed validation");
      return;
    }
    fatal("unexpected render message type");
  }

  void publish_frame() {
    if (!runtime_.active())
      return;
    const auto frame = runtime_.render();
    if (!frame) {
      if (!runtime_.last_error().empty())
        fatal(runtime_.last_error());
      return;
    }
    const auto payload = surface::encode_frame_ready(frame->ready);
    send_render(
        static_cast<std::uint16_t>(surface::RenderMessageType::frame_ready),
        payload, 0);
  }

  worker::WorkerRuntime runtime_;
  worker::WorkerEndpoint control_;
  worker::WorkerEndpoint broker_;
  worker::WorkerEndpoint render_;
  wire::RequiredEndpointReadiness readiness_;
  std::array<wire::RoleSchemaView, 1> schemas_;
  wire::RoleSchemaRegistryView registry_;
  std::unique_ptr<wire::SelectedEndpointState<32>> render_state_;
  std::unique_ptr<worker::QmlBrokerApi> broker_api_;
  bool runtime_loaded_ = false;
  bool runtime_load_pending_ = false;
  QSocketNotifier control_notifier_;
  QSocketNotifier broker_notifier_;
  QSocketNotifier render_notifier_;
  QTimer frame_timer_;
  omarchy::plugins::manifest::ManifestV2 manifest_;
};

} // namespace

int main(int argc, char *argv[]) {
  if (argc == 2 && std::string_view(argv[1]) == "--version") {
    const auto version = omarchy::plugin_runtime::build_version();
    QTextStream(stdout) << "omarchy-plugin-qml-worker "
                        << QString::fromLatin1(version.data(), version.size())
                        << " envelope="
                        << omarchy::plugin_runtime::envelope_version() << '\n';
    return 0;
  }
  if (argc != 1 || !trusted_launch_environment()) {
    QTextStream(stderr)
        << "omarchy-plugin-qml-worker: direct execution denied; trusted "
           "Bubblewrap FD 3/4/5 launch is required\n";
    return 78;
  }
  qputenv("QT_QPA_PLATFORMTHEME", "none");
  qputenv("QSG_SOFTWARE_RENDERER_FORCE_PARTIAL_UPDATES", "0");
  worker::SidecarSupervisor sidecars;
  omarchy::plugins::manifest::ManifestV2 manifest;
  try {
    manifest = omarchy::plugins::manifest::parse_manifest_v2(
        read_manifest());
    std::string sidecar_error;
    if (!sidecars.start(manifest.runtime.sidecars, sidecar_error)) {
      QTextStream(stderr) << "omarchy-plugin-qml-worker: "
                          << QString::fromStdString(sidecar_error) << '\n';
      return 70;
    }
  } catch (const std::exception &error) {
    QTextStream(stderr) << "omarchy-plugin-qml-worker: manifest rejected: "
                        << error.what() << '\n';
    return 70;
  }
  QGuiApplication application(argc, argv);
  application.setApplicationName(QStringLiteral("omarchy-plugin-qml-worker"));
  // The worker owns only offscreen render-control windows. Loading QML after
  // the authenticated startup snapshot happens inside the event loop, where
  // Qt's GUI default would otherwise quit when it observes no visible window.
  application.setQuitOnLastWindowClosed(false);
  WorkerApplication worker(manifest);
  if (!worker.start())
    return 70;
  QTimer sidecar_health;
  sidecar_health.setInterval(100);
  QObject::connect(&sidecar_health, &QTimer::timeout, [&] {
    std::string error;
    if (!sidecars.healthy(error)) {
      qCritical().noquote() << "omarchy-plugin-qml-worker:"
                            << QString::fromStdString(error);
      application.exit(70);
    }
  });
  sidecar_health.start();
  return application.exec();
}
