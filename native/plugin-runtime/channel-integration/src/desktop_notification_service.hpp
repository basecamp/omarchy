#pragma once

#include "session_runtime_factory.hpp"

#include <QDBusMessage>
#include <QString>

#include <memory>
#include <mutex>

namespace omarchy::plugin_runtime::channel {

struct DesktopNotification final {
  QString plugin;
  QString category;
  QString title;
  QString body;
};

class DesktopNotificationTransport {
public:
  virtual ~DesktopNotificationTransport() = default;
  [[nodiscard]] virtual bool
  send(const DesktopNotification &notification) noexcept = 0;
};

// Sole adapter from a permission-checked notification request to the desktop
// notification protocol. It accepts no executable, action, icon or path.
class DesktopNotificationService final {
public:
  explicit DesktopNotificationService(
      std::unique_ptr<DesktopNotificationTransport> transport);

  [[nodiscard]] static bool send(std::string_view plugin,
                                 std::string_view category,
                                 std::string_view title, std::string_view body,
                                 void *context) noexcept;

private:
  std::mutex transport_mutex_;
  std::unique_ptr<DesktopNotificationTransport> transport_;
};

[[nodiscard]] QDBusMessage
desktop_notification_message(const DesktopNotification &notification);
[[nodiscard]] bool
desktop_notification_reply_accepted(const QDBusMessage &reply) noexcept;

// One immutable service table and provider catalog are shared by every runtime
// composed by a bootstrap. Unsupported built-in services remain absent.
[[nodiscard]] std::shared_ptr<const RuntimeServices>
make_runtime_services(
    std::shared_ptr<const provider_host::ProviderCatalog> provider_catalog = {})
    noexcept;

} // namespace omarchy::plugin_runtime::channel
