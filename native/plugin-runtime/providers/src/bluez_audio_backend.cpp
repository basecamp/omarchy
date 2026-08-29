#include "omarchy/plugin_runtime/providers/bluez_audio_backend.hpp"

#include <QDBusConnection>
#include <QDBusInterface>
#include <QDBusMessage>
#include <QDBusReply>
#include <QProcess>
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

bool selected_default_sink(std::string_view address, int *volume = nullptr) {
  QProcess inspect;
  inspect.start(QStringLiteral("/usr/bin/wpctl"),
                {QStringLiteral("inspect"), QStringLiteral("@DEFAULT_AUDIO_SINK@")});
  if (!inspect.waitForFinished(2000) || inspect.exitCode() != 0) return false;
  QByteArray marker(address.data(), static_cast<qsizetype>(address.size()));
  marker.replace(':', '_');
  if (!inspect.readAllStandardOutput().toUpper().contains(marker.toUpper()))
    return false;
  if (volume == nullptr) return true;
  QProcess get;
  get.start(QStringLiteral("/usr/bin/wpctl"),
            {QStringLiteral("get-volume"), QStringLiteral("@DEFAULT_AUDIO_SINK@")});
  if (!get.waitForFinished(2000) || get.exitCode() != 0) return false;
  const auto fields = QString::fromUtf8(get.readAllStandardOutput()).split(' ');
  if (fields.size() < 2) return false;
  bool ok = false;
  const double value = fields.at(1).trimmed().toDouble(&ok);
  if (!ok || value < 0 || value > 1) return false;
  *volume = qRound(value * 100);
  return true;
}
} // namespace

BluezAudioBackend::BluezAudioBackend(std::string selected_address)
    : selected_address_(std::move(selected_address)) {}

AudioDeviceBackend BluezAudioBackend::configuration() noexcept {
  return {.observe = observe, .control = control, .context = this};
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
  int volume = -1;
  if (!selected_default_sink(self.selected_address_, &volume)) return false;
  status = {.display_name = self.display_name_,
            .connected = values.value(QStringLiteral("Connected")).toBool(),
            .left = -1,
            .right = -1,
            .case_level = -1,
            .volume_percent = volume,
            .listening_mode = "unavailable",
            .adaptive_level = 0,
            .conversation_awareness = false,
            .one_bud_anc = false,
            .ear_detection = "unavailable",
            .supported_controls = kVolumeControl};
  return true;
}

bool BluezAudioBackend::control(std::string_view operation,
                                std::string_view value, void *opaque) noexcept {
  auto &self = *static_cast<BluezAudioBackend *>(opaque);
  if (operation != "set-volume" || !self.valid_selection() ||
      !selected_default_sink(self.selected_address_))
    return false;
  bool ok = false;
  const int percent = QString::fromLatin1(value.data(),
      static_cast<qsizetype>(value.size())).toInt(&ok);
  if (!ok || percent < 0 || percent > 100) return false;
  QProcess set;
  set.start(QStringLiteral("/usr/bin/wpctl"),
            {QStringLiteral("set-volume"), QStringLiteral("@DEFAULT_AUDIO_SINK@"),
             QString::number(percent) + QStringLiteral("%")});
  if (!set.waitForFinished(2000) || set.exitCode() != 0) return false;
  int observed = -1;
  return selected_default_sink(self.selected_address_, &observed) &&
         observed == percent;
}

} // namespace omarchy::plugin_runtime::providers
