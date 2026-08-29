#include "omarchy/plugin_runtime/providers/bluez_audio_backend.hpp"

#include <QDBusConnection>
#include <QDBusInterface>
#include <QDBusMessage>
#include <QDBusReply>
#include <QVariantMap>

#include <algorithm>
#include <cctype>
#include <utility>

namespace omarchy::plugin_runtime::providers {
namespace {
bool valid_address(std::string_view value) noexcept {
  if (value.size() != 17) return false;
  for (std::size_t index = 0; index < value.size(); ++index) {
    if (index % 3 == 2) {
      if (value[index] != ':') return false;
    } else if (!std::isxdigit(static_cast<unsigned char>(value[index]))) {
      return false;
    }
  }
  return true;
}

QString object_path(std::string_view address) {
  QString suffix = QString::fromLatin1(address.data(),
                                       static_cast<qsizetype>(address.size()));
  suffix.replace(':', '_');
  return QStringLiteral("/org/bluez/hci0/dev_") + suffix.toUpper();
}
} // namespace

BluezAudioBackend::BluezAudioBackend(std::string selected_address)
    : selected_address_(std::move(selected_address)) {}

AudioDeviceBackend BluezAudioBackend::configuration() noexcept {
  return {.observe = observe, .control = nullptr, .context = this};
}

bool BluezAudioBackend::valid_selection() const noexcept {
  return valid_address(selected_address_);
}

bool BluezAudioBackend::observe(AudioDeviceStatus &status, void *opaque) noexcept {
  auto &self = *static_cast<BluezAudioBackend *>(opaque);
  if (!self.valid_selection()) return false;
  QDBusInterface properties(
      QStringLiteral("org.bluez"), object_path(self.selected_address_),
      QStringLiteral("org.freedesktop.DBus.Properties"),
      QDBusConnection::systemBus());
  if (!properties.isValid()) return false;
  const QDBusReply<QVariantMap> reply =
      properties.call(QStringLiteral("GetAll"), QStringLiteral("org.bluez.Device1"));
  if (!reply.isValid()) return false;
  const auto values = reply.value();
  const QString name = values.value(QStringLiteral("Alias")).toString();
  if (name.isEmpty() || name.toUtf8().size() > 128) return false;
  self.display_name_ = name.toStdString();
  status = {.display_name = self.display_name_,
            .connected = values.value(QStringLiteral("Connected")).toBool(),
            .left = -1,
            .right = -1,
            .case_level = -1,
            .listening_mode = "unavailable",
            .adaptive_level = 0,
            .conversation_awareness = false,
            .one_bud_anc = false,
            .ear_detection = "unavailable",
            .supported_controls = 0};
  return true;
}

} // namespace omarchy::plugin_runtime::providers
