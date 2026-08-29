#include "omarchy/plugin_runtime/providers/hyprland_window_backend.hpp"

#include <QCryptographicHash>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QRandomGenerator>

#include <algorithm>
#include <cstring>

namespace omarchy::plugin_runtime::providers {
namespace {
constexpr std::size_t kMaximumHyprlandJson = 256 * 1024;

bool integer_pair(const QJsonValue &value, int &first, int &second) {
  const auto array = value.toArray();
  if (array.size() != 2 || !array[0].isDouble() || !array[1].isDouble()) return false;
  first = array[0].toInt();
  second = array[1].toInt();
  return true;
}
}

HyprlandWindowBackend::HyprlandWindowBackend(HyprlandCommandBackend command)
    : command_(command) {
  if (command_.read_json == nullptr) command_ = {.read_json = process_command};
  QRandomGenerator::system()->fillRange(
      reinterpret_cast<quint32 *>(identity_key_.data()),
      identity_key_.size() / sizeof(quint32));
}

SystemObserveBackend HyprlandWindowBackend::configuration() noexcept {
  return {.window_rectangles = observe, .context = this};
}

bool HyprlandWindowBackend::process_command(std::string_view argument,
                                            std::span<char> output,
                                            std::size_t &written,
                                            void *) noexcept {
  written = 0;
  if (argument != "monitors" && argument != "clients") return false;
  QProcess process;
  process.setProgram(QStringLiteral("/usr/bin/hyprctl"));
  process.setArguments({QStringLiteral("-j"), QString::fromUtf8(argument)});
  process.start(QIODevice::ReadOnly);
  if (!process.waitForStarted(1000) || !process.waitForFinished(2000) ||
      process.exitStatus() != QProcess::NormalExit || process.exitCode() != 0)
    return false;
  const auto bytes = process.readAllStandardOutput();
  if (bytes.isEmpty() || static_cast<std::size_t>(bytes.size()) > output.size())
    return false;
  std::memcpy(output.data(), bytes.constData(), static_cast<std::size_t>(bytes.size()));
  written = static_cast<std::size_t>(bytes.size());
  return true;
}

bool HyprlandWindowBackend::observe(SanitizedWindowSnapshot &snapshot,
                                    void *opaque) noexcept {
  auto &self = *static_cast<HyprlandWindowBackend *>(opaque);
  std::array<char, kMaximumHyprlandJson> monitor_bytes{};
  std::array<char, kMaximumHyprlandJson> client_bytes{};
  std::size_t monitor_size = 0;
  std::size_t client_size = 0;
  if (!self.command_.read_json("monitors", monitor_bytes, monitor_size,
                               self.command_.context) ||
      !self.command_.read_json("clients", client_bytes, client_size,
                               self.command_.context))
    return false;
  QJsonParseError error;
  const auto monitors = QJsonDocument::fromJson(
      QByteArray(monitor_bytes.data(), static_cast<qsizetype>(monitor_size)), &error);
  if (error.error != QJsonParseError::NoError || !monitors.isArray()) return false;
  const auto clients = QJsonDocument::fromJson(
      QByteArray(client_bytes.data(), static_cast<qsizetype>(client_size)), &error);
  if (error.error != QJsonParseError::NoError || !clients.isArray()) return false;

  QJsonObject monitor;
  for (const auto &entry : monitors.array()) {
    const auto candidate = entry.toObject();
    if (candidate.value("focused").toBool()) { monitor = candidate; break; }
  }
  if (monitor.isEmpty() && !monitors.array().isEmpty()) monitor = monitors.array().first().toObject();
  const int monitor_id = monitor.value("id").toInt(-1);
  const int workspace_id = monitor.value("activeWorkspace").toObject().value("id").toInt(-1);
  const int monitor_x = monitor.value("x").toInt();
  const int monitor_y = monitor.value("y").toInt();
  const int monitor_width = monitor.value("width").toInt();
  const int monitor_height = monitor.value("height").toInt();
  if (monitor_id < 0 || workspace_id < 0 || monitor_width <= 0 || monitor_height <= 0)
    return false;
  snapshot = {.width = static_cast<std::uint32_t>(monitor_width),
              .height = static_cast<std::uint32_t>(monitor_height)};
  const auto reserved = monitor.value("reserved").toArray();
  if (reserved.size() == 4)
    snapshot.reserved_bottom = static_cast<std::uint32_t>(
        std::clamp(reserved[3].toInt(), 0, monitor_height));

  for (const auto &entry : clients.array()) {
    if (snapshot.window_count == snapshot.windows.size()) break;
    const auto client = entry.toObject();
    if (!client.value("mapped").toBool(true) || client.value("hidden").toBool() ||
        client.value("fullscreen").toInt() != 0 ||
        client.value("monitor").toInt(-1) != monitor_id ||
        client.value("workspace").toObject().value("id").toInt(-1) != workspace_id)
      continue;
    int x = 0, y = 0, width = 0, height = 0;
    if (!integer_pair(client.value("at"), x, y) ||
        !integer_pair(client.value("size"), width, height) || width <= 0 || height <= 0)
      continue;
    x -= monitor_x;
    y -= monitor_y;
    const int left = std::clamp(x, 0, monitor_width);
    const int top = std::clamp(y, 0, monitor_height);
    const int right = std::clamp(x + width, 0, monitor_width);
    const int bottom = std::clamp(y + height, 0, monitor_height);
    if (right <= left || bottom <= top) continue;
    const auto address = client.value("address").toString().toUtf8();
    if (address.isEmpty()) continue;
    QByteArray identity(reinterpret_cast<const char *>(self.identity_key_.data()),
                        static_cast<qsizetype>(self.identity_key_.size()));
    identity.append(address);
    const auto hash = QCryptographicHash::hash(identity, QCryptographicHash::Sha256);
    std::uint64_t opaque_id = 0;
    std::memcpy(&opaque_id, hash.constData(), sizeof(opaque_id));
    if (opaque_id == 0) opaque_id = 1;
    snapshot.windows[snapshot.window_count++] = {
        .opaque_id = opaque_id, .x = left, .y = top,
        .width = static_cast<std::uint32_t>(right - left),
        .height = static_cast<std::uint32_t>(bottom - top)};
  }
  return true;
}

} // namespace omarchy::plugin_runtime::providers
