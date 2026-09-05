#include "desktop_notification_service.hpp"

#include <QDBusConnection>
#include <QMetaType>
#include <QStringList>
#include <QVariantMap>

#include <memory>
#include <utility>

namespace omarchy::plugin_runtime::channel {
namespace {

constexpr int kNotificationCallTimeoutMilliseconds = 1500;
constexpr int kNotificationDisplayTimeoutMilliseconds = 5000;

class FreedesktopNotificationTransport final
    : public DesktopNotificationTransport {
public:
  explicit FreedesktopNotificationTransport(QDBusConnection connection)
      : connection_(std::move(connection)) {}

  [[nodiscard]] bool
  send(const DesktopNotification &notification) noexcept override {
    try {
      if (!connection_.isConnected())
        return false;
      const auto reply =
          connection_.call(desktop_notification_message(notification),
                           QDBus::Block, kNotificationCallTimeoutMilliseconds);
      return desktop_notification_reply_accepted(reply);
    } catch (...) {
      return false;
    }
  }

private:
  QDBusConnection connection_;
};

QString trusted_plugin_label(const QString &plugin) {
  return QStringLiteral("Omarchy Plugin · ") + plugin;
}

} // namespace

DesktopNotificationService::DesktopNotificationService(
    std::unique_ptr<DesktopNotificationTransport> transport)
    : transport_(std::move(transport)) {}

bool DesktopNotificationService::send(std::string_view plugin,
                                      std::string_view category,
                                      std::string_view title,
                                      std::string_view body,
                                      void *context) noexcept {
  try {
    auto *service = static_cast<DesktopNotificationService *>(context);
    if (service == nullptr || !service->transport_)
      return false;
    std::unique_lock lock(service->transport_mutex_, std::try_to_lock);
    if (!lock.owns_lock())
      return false;
    const auto utf8 = [](std::string_view value) {
      return QString::fromUtf8(value.data(),
                               static_cast<qsizetype>(value.size()));
    };
    return service->transport_->send({.plugin = utf8(plugin),
                                      .category = utf8(category),
                                      .title = utf8(title),
                                      .body = utf8(body)});
  } catch (...) {
    return false;
  }
}

QDBusMessage
desktop_notification_message(const DesktopNotification &notification) {
  auto message = QDBusMessage::createMethodCall(
      QStringLiteral("org.freedesktop.Notifications"),
      QStringLiteral("/org/freedesktop/Notifications"),
      QStringLiteral("org.freedesktop.Notifications"),
      QStringLiteral("Notify"));
  QVariantMap hints;
  hints.insert(QStringLiteral("category"), notification.category);
  hints.insert(QStringLiteral("urgency"),
               QVariant::fromValue(static_cast<uchar>(0)));
  message.setArguments({trusted_plugin_label(notification.plugin),
                        QVariant::fromValue(uint{0}), QString{},
                        notification.title, notification.body, QStringList{},
                        hints, kNotificationDisplayTimeoutMilliseconds});
  return message;
}

bool desktop_notification_reply_accepted(const QDBusMessage &reply) noexcept {
  try {
    const auto arguments = reply.arguments();
    return reply.type() == QDBusMessage::ReplyMessage &&
           arguments.size() == 1 &&
           arguments.front().metaType() == QMetaType::fromType<uint>();
  } catch (...) {
    return false;
  }
}

std::shared_ptr<const RuntimeServices> make_runtime_services(
    std::shared_ptr<const provider_host::ProviderCatalog> provider_catalog)
    noexcept {
  try {
    auto service = std::make_shared<DesktopNotificationService>(
        std::make_unique<FreedesktopNotificationTransport>(
            QDBusConnection::sessionBus()));
    RuntimeServices services;
    services.context = std::move(service);
    services.notification_send = DesktopNotificationService::send;
    services.provider_catalog = std::move(provider_catalog);
    return std::make_shared<const RuntimeServices>(std::move(services));
  } catch (...) {
    return {};
  }
}

} // namespace omarchy::plugin_runtime::channel
