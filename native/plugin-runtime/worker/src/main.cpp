#include "worker_channel.hpp"
#include "qml_broker_api.hpp"
#include "sidecar_supervisor.hpp"
#include "startup_state.hpp"
#include "worker_runtime.hpp"
#include "omarchy/plugin/wire/control.hpp"

#include "manifest_contract.hpp"

#include "omarchy/plugin_runtime/Version.h"
#include "omarchy/plugin_runtime/runtime_paths.hpp"
#include "omarchy/plugin_runtime/sandbox/policy.h"
#include "omarchy/plugin_runtime/surface/render_messages.hpp"

#include <QGuiApplication>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSocketNotifier>
#include <QStringList>
#include <QTextStream>
#include <QTimer>

#include <fcntl.h>
#include <sys/socket.h>
#include <unistd.h>

#include <array>
#include <algorithm>
#include <cstdlib>
#include <fstream>
#include <memory>
#include <optional>
#include <span>
#include <string>

namespace {

namespace surface = omarchy::plugin_runtime::surface;
namespace worker = omarchy::plugin_runtime::worker;
namespace wire = omarchy::plugin::wire;

int frame_interval(const omarchy::plugins::manifest::ManifestV2 &manifest) {
  const auto document = QJsonDocument::fromJson(
      QByteArray::fromStdString(manifest.canonical_surfaces));
  int maximum_frames_per_second = 60;
  for (const auto surface : document.object()) {
    maximum_frames_per_second = std::min(
        maximum_frames_per_second,
        surface.toObject()
            .value(QStringLiteral("maximumFramesPerSecond"))
            .toInt(60));
  }
  return (1000 + maximum_frames_per_second - 1) /
             maximum_frames_per_second +
         1;
}

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

class WorkerApplication final : public worker::SurfaceIntentSink {
public:
  explicit WorkerApplication(
      const omarchy::plugins::manifest::ManifestV2 &manifest)
      : runtime_("/plugin", std::string(
                                omarchy::plugin_runtime::sandbox::
                                    trusted_qml_import_root())),
        control_(kControlDescriptor, wire::EndpointRole::control,
                 kControlRoleVersion, sequence_),
        broker_(kBrokerDescriptor, wire::EndpointRole::broker,
                kBrokerRoleVersion, sequence_),
        render_(kRenderDescriptor, wire::EndpointRole::render,
                surface::kRenderRoleVersion, sequence_),
        schemas_{surface::render_role_schema()}, registry_(schemas_),
        control_notifier_(kControlDescriptor, QSocketNotifier::Read),
        broker_notifier_(kBrokerDescriptor, QSocketNotifier::Read),
        render_notifier_(kRenderDescriptor, QSocketNotifier::Read),
        frame_interval_ms_(frame_interval(manifest)),
        manifest_(manifest) {
    QObject::connect(&control_notifier_, &QSocketNotifier::activated,
                     [&] { receive(control_); });
    QObject::connect(&broker_notifier_, &QSocketNotifier::activated,
                     [&] { receive_broker_if_ready(); });
    QObject::connect(&render_notifier_, &QSocketNotifier::activated,
                     [&] { receive(render_); });
    broker_poll_timer_.setInterval(5);
    QObject::connect(&broker_poll_timer_, &QTimer::timeout,
                     [&] { receive_broker_if_ready(); });
    frame_timer_.setInterval(frame_interval_ms_);
    frame_timer_.setTimerType(Qt::PreciseTimer);
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
  bool request_surface_intent(
      std::optional<
          omarchy::plugins::definitions::DynamicInvocation::GestureClaim>
          source,
      std::string_view target_surface,
      surface::SurfaceIntentAction action, const QVariantMap &data) override {
    if (!startup_.loaded())
      return false;
    const auto target = runtime_.surface_key(target_surface);
    if (!target ||
        (source &&
         (source->surface_id == 0 || source->surface_generation == 0 ||
          source->input_sequence == 0 ||
          target->generation != source->surface_generation)) ||
        (!source && action != surface::SurfaceIntentAction::dismiss) ||
        (!data.empty() &&
         !runtime_.can_deliver_surface_intent(target_surface)))
      return false;
    const auto source_key = source
                                ? surface::SurfaceKey{
                                      .id = source->surface_id,
                                      .generation = source->surface_generation}
                                : *target;
    const auto payload = surface::encode_surface_intent(
        {.source = source_key,
         .target = *target,
         .input_sequence = source ? source->input_sequence : 0,
         .action = action});
    if (!send_render(
        static_cast<std::uint16_t>(surface::RenderMessageType::surface_intent),
        payload, 0))
      return false;
    return data.empty() ||
           runtime_.deliver_surface_intent(target_surface, data);
  }

  void receive_broker_if_ready() {
    // A socket-notifier activation and the level-triggered readiness recheck
    // may both be queued for one datagram. Recheck readiness in the callback
    // so the second delivery cannot enter a blocking recvmsg after the first
    // one consumed it.
    if (!startup_.terminal() && broker_.has_pending_input())
      receive(broker_);
  }

  bool fatal(std::string_view detail) {
    if (!startup_.terminate())
      return false;
    const std::string diagnostic = "omarchy-plugin-qml-worker: " +
                                   std::string(detail) + "\n";
    const auto ignored =
        write(STDERR_FILENO, diagnostic.data(), diagnostic.size());
    static_cast<void>(ignored);
    control_notifier_.setEnabled(false);
    broker_notifier_.setEnabled(false);
    render_notifier_.setEnabled(false);
    frame_timer_.stop();
    broker_poll_timer_.stop();
    QCoreApplication::exit(70);
    return false;
  }

  void receive(worker::WorkerEndpoint &endpoint) {
    if (startup_.terminal())
      return;
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
    if (endpoint.role() == wire::EndpointRole::control && !broker_api_) {
      if (pending_permission_snapshot_ ||
          packet.header.message_type != wire::kPermissionSnapshotMessage ||
          packet.header.correlation_id != 0 || !packet.descriptors.empty()) {
        fatal("unexpected pre-readiness control traffic");
        return;
      }
      pending_permission_snapshot_ = std::move(packet);
      return;
    }
    if (endpoint.role() == wire::EndpointRole::control && broker_api_) {
      if (packet.header.message_type == wire::kSettingsSnapshotMessage) {
        if (settings_snapshot_received_ || packet.header.correlation_id != 0 ||
            !packet.descriptors.empty() ||
            !broker_api_->applySettingsSnapshot(
                packet.header.launch_generation, packet.payload) ||
            !control_.send(wire::kSettingsSnapshotAcceptedMessage, {}, 0)) {
          fatal("settings snapshot failed runtime validation");
          return;
        }
        settings_snapshot_received_ = true;
      } else if (packet.header.message_type ==
                 wire::kSettingsUpdateResultMessage) {
        if (!broker_api_->receiveSettingsResult(std::move(packet)))
          fatal("settings update result failed runtime validation");
      } else {
        if (!settings_snapshot_received_) {
          fatal("permission snapshot preceded settings authority");
          return;
        }
        apply_permission_snapshot(std::move(packet));
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

  void apply_permission_snapshot(worker::ReceivedPacket packet) {
    if (!broker_api_ || !startup_.begin_loading()) {
      fatal("permission snapshot is invalid in the current runtime state");
      return;
    }
    if (packet.header.message_type != wire::kPermissionSnapshotMessage ||
        packet.header.correlation_id != 0 || !packet.descriptors.empty() ||
        !broker_api_->applyPermissionSnapshot(packet.header.launch_generation,
                                              packet.payload)) {
      fatal("permission snapshot failed runtime validation");
      return;
    }
    const auto generation = packet.header.launch_generation;
    QTimer::singleShot(0, &control_notifier_, [this, generation] {
      if (startup_.terminal())
        return;
      if (!manifest_.runtime.surface_qml.empty()) {
        for (const auto &entry : manifest_.runtime.surface_qml) {
          const auto loaded =
              runtime_.load_surface_entry(entry.surface, entry.qml);
          if (!loaded) {
            fatal(loaded.detail);
            return;
          }
        }
      } else {
        const auto surfaces = QJsonDocument::fromJson(
            QByteArray::fromStdString(manifest_.canonical_surfaces));
        if (!surfaces.isObject() || surfaces.object().size() > 1) {
          fatal("single-entry runtime permits at most one surface");
          return;
        }
        const auto loaded = surfaces.object().isEmpty()
                                ? runtime_.load_entry(manifest_.runtime.qml)
                                : runtime_.load_surface_entry(
                                      surfaces.object()
                                          .begin()
                                          .key()
                                          .toStdString(),
                                      manifest_.runtime.qml);
        if (!loaded) {
          fatal(loaded.detail);
          return;
        }
      }
      for (std::size_t index = 0; index < manifest_.surface_names.size();
           ++index) {
        const auto &surface_name = manifest_.surface_names[index];
        const auto binding = wire::manifest_surface_binding(
            surface_name, index, generation);
        if (!binding ||
            !runtime_.bind_surface(
                surface_name,
                {.id = binding->id, .generation = binding->generation})) {
          fatal("manifest surface binding failed runtime validation");
          return;
        }
      }
      if (!startup_.finish_loading()) {
        fatal("QML load completed outside the startup authority phase");
        return;
      }
      if (!control_.send(wire::kPermissionSnapshotAcceptedMessage, {}, 0)) {
        fatal("permission snapshot acknowledgement failed");
        return;
      }
      if (!broker_api_->markBrokerReady())
        fatal("broker became ready outside the startup authority phase");
    });
  }

  void ready_runtime() {
    if (startup_.terminal())
      return;
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
        manifest_, broker_.generation(), nullptr, &control_);
    if (!broker_api_->bindSurfaceIntentSink(*this)) {
      fatal("surface intent sink binding failed");
      return;
    }
    broker_api_->setPackagedAssetRoot("/plugin");
    QObject::connect(broker_api_.get(), &worker::QmlBrokerApi::callFinished,
                     broker_api_.get(),
                     [&] {
                       QTimer::singleShot(1, broker_api_.get(),
                                          [&] { runtime_.request_render(); });
                       QTimer::singleShot(frame_interval_ms_ + 1,
                                          broker_api_.get(),
                                          [&] { runtime_.request_render(); });
                     });
    const auto bound = runtime_.bind_runtime_api(*broker_api_);
    if (!bound) {
      fatal(bound.detail);
      return;
    }
    control_notifier_.setEnabled(true);
    broker_notifier_.setEnabled(true);
    render_notifier_.setEnabled(true);
    broker_poll_timer_.start();
    if (pending_permission_snapshot_) {
      auto pending = std::move(*pending_permission_snapshot_);
      pending_permission_snapshot_.reset();
      apply_permission_snapshot(std::move(pending));
    }
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
      if (type == surface::RenderMessageType::surface_release &&
          !runtime_.active())
        frame_timer_.stop();
      return;
    }
    if (type == surface::RenderMessageType::input) {
      surface::InputEvent event{};
      if (!surface::decode_input_event(packet.payload, event)) {
        fatal("input event failed validation");
        return;
      }
      const bool trusted_activation =
          broker_api_->beginTrustedGestureForInput(event);
      if (!runtime_.input(event)) {
        broker_api_->endTrustedGesture();
        fatal("input event failed validation");
        return;
      }
      if (trusted_activation)
        broker_api_->endTrustedGesture();
      return;
    }
    fatal("unexpected render message type");
  }

  void publish_frame() {
    if (startup_.terminal() || !runtime_.active())
      return;
    const auto frame = runtime_.render();
    if (!frame) {
      if (!runtime_.last_error().empty())
        fatal(runtime_.last_error());
      return;
    }
    const auto regions = runtime_.input_region_update(
        frame->ready.surface, frame->ready.frame_sequence);
    if (regions) {
      const auto region_payload = surface::encode_input_region_update(*regions);
      send_render(static_cast<std::uint16_t>(
                      surface::RenderMessageType::input_regions),
                  region_payload, 0);
    }
    const auto payload = surface::encode_frame_ready(frame->ready);
    send_render(
        static_cast<std::uint16_t>(surface::RenderMessageType::frame_ready),
        payload, 0);
  }

  worker::WorkerRuntime runtime_;
  // Constructed before and destroyed after every endpoint that borrows it.
  wire::SessionSequence sequence_;
  worker::WorkerEndpoint control_;
  worker::WorkerEndpoint broker_;
  worker::WorkerEndpoint render_;
  wire::RequiredEndpointReadiness readiness_;
  std::array<wire::RoleSchemaView, 1> schemas_;
  wire::RoleSchemaRegistryView registry_;
  std::unique_ptr<wire::SelectedEndpointState<32>> render_state_;
  std::unique_ptr<worker::QmlBrokerApi> broker_api_;
  bool settings_snapshot_received_ = false;
  worker::StartupState startup_;
  std::optional<worker::ReceivedPacket> pending_permission_snapshot_;
  QSocketNotifier control_notifier_;
  QSocketNotifier broker_notifier_;
  QSocketNotifier render_notifier_;
  QTimer frame_timer_;
  QTimer broker_poll_timer_;
  int frame_interval_ms_ = 17;
  omarchy::plugins::manifest::ManifestV2 manifest_;
};

} // namespace

int main(int argc, char *argv[]) {
  if (argc == 2 && std::string_view(argv[1]) == "--runtime-worker-path") {
    QTextStream(stdout)
        << QString::fromLatin1(
               omarchy::plugin_runtime::kPackagedWorkerPath.data(),
               static_cast<qsizetype>(
                   omarchy::plugin_runtime::kPackagedWorkerPath.size()))
        << '\n';
    return 0;
  }
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
