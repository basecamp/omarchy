#include "desktop_notification_service.hpp"

#include <QCoreApplication>
#include <QDBusError>
#include <QMetaType>
#include <QStringList>
#include <QVariantMap>

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <iostream>
#include <memory>
#include <mutex>
#include <stdexcept>
#include <string>
#include <thread>
#include <utility>

namespace channel = omarchy::plugin_runtime::channel;

namespace {

void require(bool condition, const char *message) {
  if (!condition)
    throw std::runtime_error(message);
}

struct Probe final : channel::DesktopNotificationTransport {
  bool result = true;
  unsigned calls = 0;
  channel::DesktopNotification last;

  bool
  send(const channel::DesktopNotification &notification) noexcept override {
    ++calls;
    last = notification;
    return result;
  }
};

struct HoldingProbe final : channel::DesktopNotificationTransport {
  bool send(const channel::DesktopNotification &) noexcept override {
    std::unique_lock lock(mutex);
    ++calls;
    entered = true;
    changed.notify_all();
    changed.wait(lock, [&] { return released; });
    return true;
  }

  bool await_entered() {
    std::unique_lock lock(mutex);
    return changed.wait_for(lock, std::chrono::seconds(1),
                            [&] { return entered; });
  }

  void release() {
    std::scoped_lock lock(mutex);
    released = true;
    changed.notify_all();
  }

  std::mutex mutex;
  std::condition_variable changed;
  unsigned calls = 0;
  bool entered = false;
  bool released = false;
};

void callback_forwards_only_bounded_fields() {
  auto transport = std::make_unique<Probe>();
  auto *probe = transport.get();
  channel::DesktopNotificationService service(std::move(transport));
  require(channel::DesktopNotificationService::send("org.example.clock",
                                                    "timer", "Tea is ready",
                                                    "Five minutes", &service),
          "successful transport result was lost");
  require(probe->calls == 1 && probe->last.plugin == "org.example.clock" &&
              probe->last.category == "timer" &&
              probe->last.title == "Tea is ready" &&
              probe->last.body == "Five minutes",
          "notification fields changed at the trusted adapter boundary");

  probe->result = false;
  require(!channel::DesktopNotificationService::send(
              "org.example.clock", "timer", "Tea is ready", "Five minutes",
              &service) &&
              probe->calls == 2,
          "transport failure did not fail closed");
  require(!channel::DesktopNotificationService::send("org.example.clock",
                                                     "timer", "Tea is ready",
                                                     "Five minutes", nullptr),
          "missing transport context did not fail closed");
}

void dbus_message_has_no_plugin_control_surface() {
  const auto message = channel::desktop_notification_message(
      {.plugin = QStringLiteral("org.example.clock"),
       .category = QStringLiteral("timer"),
       .title = QStringLiteral("Tea is ready"),
       .body = QStringLiteral("Five minutes")});
  require(message.service() == "org.freedesktop.Notifications" &&
              message.path() == "/org/freedesktop/Notifications" &&
              message.interface() == "org.freedesktop.Notifications" &&
              message.member() == "Notify",
          "notification message addressed a non-fixed endpoint");
  const auto arguments = message.arguments();
  require(arguments.size() == 8,
          "notification message has the wrong method signature");
  require(arguments[0].toString() ==
                  QStringLiteral("Omarchy Plugin · org.example.clock") &&
              arguments[1].metaType() == QMetaType::fromType<uint>() &&
              arguments[1].toUInt() == 0 && arguments[2].toString().isEmpty() &&
              arguments[3].toString() == "Tea is ready" &&
              arguments[4].toString() == "Five minutes" &&
              arguments[5].toStringList().isEmpty() &&
              arguments[7].toInt() == 5000,
          "notification message exposed an action, icon or mutable identity");
  const auto hints = arguments[6].toMap();
  require(hints.size() == 2 && hints.value("category").toString() == "timer" &&
              hints.value("urgency").metaType() ==
                  QMetaType::fromType<uchar>() &&
              hints.value("urgency").value<uchar>() == 0,
          "notification message exposed an unregistered hint");
}

void dbus_reply_requires_only_the_specified_type() {
  const auto call = QDBusMessage::createMethodCall(
      QStringLiteral("org.freedesktop.Notifications"),
      QStringLiteral("/org/freedesktop/Notifications"),
      QStringLiteral("org.freedesktop.Notifications"),
      QStringLiteral("Notify"));
  require(channel::desktop_notification_reply_accepted(
              call.createReply(QVariant::fromValue(uint{0}))) &&
              channel::desktop_notification_reply_accepted(
                  call.createReply(QVariant::fromValue(uint{42}))),
          "a correctly typed notification id was rejected by value");
  require(!channel::desktop_notification_reply_accepted(
              call.createReply(QVariant::fromValue(int{42}))) &&
              !channel::desktop_notification_reply_accepted(
                  call.createReply(QVariantList{})) &&
              !channel::desktop_notification_reply_accepted(
                  call.createErrorReply(QDBusError::Failed,
                                        QStringLiteral("failed"))),
          "malformed or error notification reply was accepted");
}

void busy_shared_transport_fails_closed_promptly() {
  auto transport = std::make_unique<HoldingProbe>();
  auto *probe = transport.get();
  channel::DesktopNotificationService service(std::move(transport));
  std::atomic<bool> first_succeeded = false;
  std::thread first([&] {
    first_succeeded = channel::DesktopNotificationService::send(
        "org.example.clock", "timer", "Tea is ready", "Five minutes",
        &service);
  });
  const bool entered = probe->await_entered();
  if (!entered) {
    probe->release();
    first.join();
    require(false, "first notification did not enter transport");
  }
  const auto started = std::chrono::steady_clock::now();
  const bool second = channel::DesktopNotificationService::send(
      "org.example.clock", "timer", "Second", "Must not wait", &service);
  const auto elapsed = std::chrono::steady_clock::now() - started;
  probe->release();
  first.join();
  require(!second && elapsed < std::chrono::milliseconds(100) &&
              first_succeeded && probe->calls == 1,
          "busy shared notification transport did not fail closed promptly");
}

void runtime_services_enable_only_implemented_adapters() {
  const auto services = channel::make_runtime_services();
  require(services && services->context && services->notification_send &&
              services->audio_play == nullptr &&
              services->compare_scope == nullptr &&
              !services->provider_catalog,
          "runtime service table enabled an unsupported adapter");
  const auto capability = [](std::string_view id) {
    return omarchy::plugins::permissions::CapabilityKey{
        .id = omarchy::plugins::permissions::CapabilityId(id), .version = 1};
  };
  require(channel::runtime_service_available(*services,
                                             capability("storage.private")) &&
              channel::runtime_service_available(
                  *services, capability("notifications.send")) &&
              !channel::runtime_service_available(
                  *services, capability("audio.play-cue")) &&
              !channel::runtime_service_available(*services,
                                                  capability("unknown.effect")),
          "built-in availability diverged from the frozen service table");
  omarchy::plugins::definitions::TrustedDefinitionRegistry definitions;
  require(!channel::runtime_service_available(
              definitions, *services,
              {.canonical_name =
                   omarchy::plugins::definitions::Name("harness.example"),
               .definition_generation = 1,
               .definition_digest = omarchy::plugins::definitions::Digest(
                   std::string(64, 'a'))}),
          "unregistered dynamic adapter was reported available");
}

} // namespace

int main(int argc, char **argv) {
  QCoreApplication application(argc, argv);
  try {
    callback_forwards_only_bounded_fields();
    dbus_message_has_no_plugin_control_surface();
    dbus_reply_requires_only_the_specified_type();
    busy_shared_transport_fails_closed_promptly();
    runtime_services_enable_only_implemented_adapters();
    return 0;
  } catch (const std::exception &error) {
    std::cerr << "desktop notification service test failed: " << error.what()
              << '\n';
    return 1;
  }
}
