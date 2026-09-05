#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QElapsedTimer>
#include <QHash>
#include <QProcess>
#include <QProcessEnvironment>
#include <QStringList>

#include <sys/socket.h>
#include <sys/stat.h>
#include <unistd.h>

#include <algorithm>
#include <array>
#include <cstddef>
#include <cstdint>
#include <optional>
#include <span>
#include <string>
#include <string_view>
#include <vector>

namespace {

constexpr std::uint32_t kMagic = 0x4f505256;
constexpr std::size_t kHeaderBytes = 20;
constexpr std::size_t kMaximumFrameBytes = 64 * 1024 + kHeaderBytes;
constexpr qsizetype kMaximumOutputBytes = 1024 * 1024;
constexpr int kCommandTimeoutMs = 25000;

#ifndef OMARCHY_SYSTEM_OBSERVE_CHECKUPDATES
#define OMARCHY_SYSTEM_OBSERVE_CHECKUPDATES "/usr/bin/checkupdates"
#endif
#ifndef OMARCHY_SYSTEM_OBSERVE_PACMAN
#define OMARCHY_SYSTEM_OBSERVE_PACMAN "/usr/bin/pacman"
#endif
#ifndef OMARCHY_SYSTEM_OBSERVE_HYPRCTL
#define OMARCHY_SYSTEM_OBSERVE_HYPRCTL "/usr/bin/hyprctl"
#endif

std::uint16_t u16(std::span<const std::byte> bytes, std::size_t offset,
                  bool &ok) {
  if (offset + 2 > bytes.size()) {
    ok = false;
    return 0;
  }
  return static_cast<std::uint16_t>(
      (std::to_integer<unsigned char>(bytes[offset]) << 8U) |
      std::to_integer<unsigned char>(bytes[offset + 1]));
}

std::uint32_t u32(std::span<const std::byte> bytes, std::size_t offset,
                  bool &ok) {
  if (offset + 4 > bytes.size()) {
    ok = false;
    return 0;
  }
  std::uint32_t value = 0;
  for (std::size_t index = 0; index < 4; ++index)
    value = (value << 8U) |
            std::to_integer<unsigned char>(bytes[offset + index]);
  return value;
}

std::uint64_t u64(std::span<const std::byte> bytes, std::size_t offset,
                  bool &ok) {
  if (offset + 8 > bytes.size()) {
    ok = false;
    return 0;
  }
  std::uint64_t value = 0;
  for (std::size_t index = 0; index < 8; ++index)
    value = (value << 8U) |
            std::to_integer<unsigned char>(bytes[offset + index]);
  return value;
}

void put_u32(std::vector<std::byte> &bytes, std::uint32_t value) {
  for (int shift = 24; shift >= 0; shift -= 8)
    bytes.push_back(static_cast<std::byte>(value >> shift));
}

void put_u64(std::vector<std::byte> &bytes, std::uint64_t value) {
  for (int shift = 56; shift >= 0; shift -= 8)
    bytes.push_back(static_cast<std::byte>(value >> shift));
}

bool read_text(std::span<const std::byte> bytes, std::size_t &offset,
               std::string_view &value) {
  bool ok = true;
  const auto size = u16(bytes, offset, ok);
  offset += 2;
  if (!ok || offset + size > bytes.size())
    return false;
  value = std::string_view(
      reinterpret_cast<const char *>(bytes.data() + offset), size);
  offset += size;
  return value.find('\0') == std::string_view::npos;
}

struct Request final {
  std::uint64_t correlation = 0;
  QString scope;
  QString dataset;
  QString output;
};

std::optional<Request> decode(std::span<const std::byte> frame) {
  bool ok = true;
  const auto magic = u32(frame, 0, ok);
  const auto correlation = u64(frame, 8, ok);
  const auto body_size = u32(frame, 16, ok);
  if (!ok || frame.size() < kHeaderBytes || magic != kMagic ||
      frame[4] != std::byte{1} || frame[5] != std::byte{1} ||
      frame[6] != std::byte{0} || frame[7] != std::byte{0} ||
      correlation == 0 || body_size + kHeaderBytes != frame.size())
    return std::nullopt;
  std::size_t offset = kHeaderBytes;
  std::string_view adapter, contract, operation, scope;
  if (!read_text(frame, offset, adapter) || !read_text(frame, offset, contract))
    return std::nullopt;
  const auto abi = u32(frame, offset, ok);
  offset += 4;
  if (!ok || !read_text(frame, offset, operation) ||
      !read_text(frame, offset, scope))
    return std::nullopt;
  const auto payload_size = u32(frame, offset, ok);
  offset += 4;
  if (!ok || offset + payload_size != frame.size() ||
      adapter != "sanitized-system-observe" || operation != "observe" ||
      abi != 1 || contract != OMARCHY_SYSTEM_OBSERVE_CONTRACT_DIGEST)
    return std::nullopt;
  QJsonParseError error{};
  const auto document = QJsonDocument::fromJson(
      QByteArray(reinterpret_cast<const char *>(frame.data() + offset),
                 static_cast<qsizetype>(payload_size)),
      &error);
  if (error.error != QJsonParseError::NoError || !document.isObject())
    return std::nullopt;
  const auto object = document.object();
  if ((object.size() != 1 && object.size() != 2) ||
      !object.value("dataset").isString() ||
      (object.size() == 2 && !object.value("output").isString()))
    return std::nullopt;
  for (const auto &key : object.keys())
    if (key != QStringLiteral("dataset") && key != QStringLiteral("output"))
      return std::nullopt;
  return Request{.correlation = correlation,
                 .scope = QString::fromUtf8(scope),
                 .dataset = object.value("dataset").toString(),
                 .output = object.value("output").toString()};
}

bool authorized(const Request &request) {
  if (request.dataset != QStringLiteral("packages.summary") &&
      request.dataset != QStringLiteral("compositor.window-rectangles"))
    return false;
  QJsonParseError error{};
  const auto document = QJsonDocument::fromJson(request.scope.toUtf8(), &error);
  if (error.error != QJsonParseError::NoError || !document.isObject())
    return false;
  const auto object = document.object();
  if (object.size() != 1 || !object.value("datasets").isArray())
    return false;
  const auto datasets = object.value("datasets").toArray();
  if (datasets.isEmpty() || datasets.size() > 2 ||
      (request.dataset == QStringLiteral("packages.summary") &&
       !request.output.isEmpty()) || request.output.toUtf8().size() > 128)
    return false;
  QStringList seen;
  for (const auto &value : datasets) {
    if (!value.isString())
      return false;
    const auto dataset = value.toString();
    if ((dataset != QStringLiteral("packages.summary") &&
         dataset != QStringLiteral("compositor.window-rectangles")) ||
        seen.contains(dataset))
      return false;
    seen.push_back(dataset);
  }
  const auto output = request.output.toUtf8();
  return seen.contains(request.dataset) &&
         std::ranges::none_of(output, [](const char value) {
           const auto byte = static_cast<unsigned char>(value);
           return byte < 0x21 || byte > 0x7e;
         });
}

bool trusted_owner(const struct stat &metadata) {
#ifdef OMARCHY_SYSTEM_OBSERVE_TESTING
  (void)metadata;
  return true;
#else
  return metadata.st_uid == 0;
#endif
}

bool secure_directory(const char *path) {
  struct stat metadata {};
  return ::lstat(path, &metadata) == 0 && S_ISDIR(metadata.st_mode) &&
         trusted_owner(metadata) && (metadata.st_mode & 0022) == 0;
}

bool secure_executable(const char *path) {
  struct stat metadata {};
  return secure_directory("/") && secure_directory("/usr") &&
         secure_directory("/usr/bin") && ::lstat(path, &metadata) == 0 &&
         S_ISREG(metadata.st_mode) && trusted_owner(metadata) &&
         (metadata.st_mode & 0022) == 0 && (metadata.st_mode & 06000) == 0 &&
         (metadata.st_mode & 0100) != 0;
}

struct CountResult final {
  bool ok = false;
  int count = 0;
};

CountResult count_lines(const QString &program, const QStringList &arguments,
                        int empty_exit_code) {
  QProcess process;
  QProcessEnvironment environment;
  environment.insert(QStringLiteral("PATH"), QStringLiteral("/usr/bin"));
  environment.insert(QStringLiteral("LANG"), QStringLiteral("C"));
  environment.insert(QStringLiteral("LC_ALL"), QStringLiteral("C"));
  environment.insert(QStringLiteral("HOME"), QStringLiteral("/nonexistent"));
  process.setProcessEnvironment(environment);
  process.setProgram(program);
  process.setArguments(arguments);
  process.setProcessChannelMode(QProcess::SeparateChannels);
  process.start(QIODevice::ReadOnly);
  if (!process.waitForStarted(1000))
    return {};
  qsizetype output_bytes = 0;
  qsizetype error_bytes = 0;
  int lines = 0;
  char last_output = '\0';
  bool stderr_content = false;
  bool overflow = false;
  const auto drain = [&] {
    const auto output = process.readAllStandardOutput();
    const auto error = process.readAllStandardError();
    output_bytes += output.size();
    error_bytes += error.size();
    overflow = overflow || output_bytes > kMaximumOutputBytes ||
               error_bytes > kMaximumOutputBytes;
    for (const auto byte : output) {
      last_output = byte;
      if (byte == '\n' && lines <= 100000)
        ++lines;
    }
    stderr_content = stderr_content || !error.trimmed().isEmpty();
  };
  QElapsedTimer timer;
  timer.start();
  while (process.state() != QProcess::NotRunning &&
         timer.elapsed() < kCommandTimeoutMs && !overflow) {
    process.waitForReadyRead(100);
    drain();
  }
  if (process.state() != QProcess::NotRunning || overflow) {
    process.kill();
    process.waitForFinished(500);
    return {};
  }
  drain();
  if (overflow || process.exitStatus() != QProcess::NormalExit)
    return {};
  const int code = process.exitCode();
  if (code == empty_exit_code)
    return {.ok = true, .count = 0};
  if (code != 0 || stderr_content)
    return {};
  if (output_bytes > 0 && last_output != '\n' && lines <= 100000)
    ++lines;
  return {.ok = lines <= 100000, .count = lines};
}

QByteArray observe() {
  if (!secure_executable(OMARCHY_SYSTEM_OBSERVE_CHECKUPDATES) ||
      !secure_executable(OMARCHY_SYSTEM_OBSERVE_PACMAN))
    return QJsonDocument(QJsonObject{{"ok", false}, {"error", "unavailable"}})
        .toJson(QJsonDocument::Compact);
  const auto updates = count_lines(
      QStringLiteral(OMARCHY_SYSTEM_OBSERVE_CHECKUPDATES), {}, 2);
  const auto orphans = count_lines(QStringLiteral(OMARCHY_SYSTEM_OBSERVE_PACMAN),
                                   {QStringLiteral("-Qdtq")}, 1);
  if (!updates.ok || !orphans.ok)
    return QJsonDocument(QJsonObject{{"ok", false}, {"error", "probe-failed"}})
        .toJson(QJsonDocument::Compact);
  return QJsonDocument(QJsonObject{{"ok", true},
                                   {"pendingUpdates", updates.count},
                                   {"orphanCount", orphans.count}})
      .toJson(QJsonDocument::Compact);
}

std::optional<QJsonArray> hyprland(const QString &query) {
  if (!secure_executable(OMARCHY_SYSTEM_OBSERVE_HYPRCTL))
    return std::nullopt;
  QProcess process;
  QProcessEnvironment environment = QProcessEnvironment::systemEnvironment();
  environment.insert(QStringLiteral("PATH"), QStringLiteral("/usr/bin"));
  environment.insert(QStringLiteral("LANG"), QStringLiteral("C"));
  environment.insert(QStringLiteral("LC_ALL"), QStringLiteral("C"));
  environment.insert(QStringLiteral("HOME"), QStringLiteral("/nonexistent"));
  process.setProcessEnvironment(environment);
  process.setProgram(QStringLiteral(OMARCHY_SYSTEM_OBSERVE_HYPRCTL));
  process.setArguments({QStringLiteral("-j"), query});
  process.setProcessChannelMode(QProcess::SeparateChannels);
  process.start(QIODevice::ReadOnly);
  if (!process.waitForStarted(1000))
    return std::nullopt;
  QByteArray output;
  QByteArray error;
  QElapsedTimer timer;
  timer.start();
  while (process.state() != QProcess::NotRunning &&
         timer.elapsed() < 3000 && output.size() <= kMaximumOutputBytes &&
         error.size() <= kMaximumOutputBytes) {
    process.waitForReadyRead(50);
    output += process.readAllStandardOutput();
    error += process.readAllStandardError();
  }
  output += process.readAllStandardOutput();
  error += process.readAllStandardError();
  if (process.state() != QProcess::NotRunning ||
      output.size() > kMaximumOutputBytes || error.size() > kMaximumOutputBytes) {
    process.kill();
    process.waitForFinished(500);
    return std::nullopt;
  }
  if (process.exitStatus() != QProcess::NormalExit || process.exitCode() != 0 ||
      !error.trimmed().isEmpty())
    return std::nullopt;
  QJsonParseError parse_error{};
  const auto document = QJsonDocument::fromJson(output, &parse_error);
  if (parse_error.error != QJsonParseError::NoError || !document.isArray())
    return std::nullopt;
  return document.array();
}

QString opaque_window_id(const QString &address) {
  static QHash<QString, QString> identities;
  const auto found = identities.constFind(address);
  if (found != identities.cend())
    return *found;
  const auto value = QStringLiteral("window-%1").arg(identities.size() + 1);
  identities.insert(address, value);
  return value;
}

QByteArray observe_compositor(const QString &requested_output) {
  const auto monitors = hyprland(QStringLiteral("monitors"));
  const auto clients = hyprland(QStringLiteral("clients"));
  if (!monitors || !clients || monitors->isEmpty())
    return QJsonDocument(QJsonObject{{"ok", false}, {"error", "unavailable"}})
        .toJson(QJsonDocument::Compact);
  QJsonArray output_names;
  QJsonObject selected;
  for (const auto &value : *monitors) {
    if (!value.isObject())
      continue;
    const auto monitor = value.toObject();
    const auto name = monitor.value("name").toString();
    const auto bytes = name.toUtf8();
    if (bytes.isEmpty() || bytes.size() > 128 ||
        std::ranges::any_of(bytes, [](const char value) {
          const auto byte = static_cast<unsigned char>(value);
          return byte < 0x21 || byte > 0x7e;
        }))
      continue;
    output_names.append(name);
    if (name == requested_output ||
        (selected.isEmpty() && monitor.value("focused").toBool()))
      selected = monitor;
  }
  if (!requested_output.isEmpty()) {
    const auto selected_name = selected.value("name").toString();
    if (selected_name != requested_output)
      selected = {};
  }
  if (selected.isEmpty()) {
    for (const auto &value : *monitors) {
      if (value.isObject() && output_names.contains(
                                  value.toObject().value("name"))) {
        selected = value.toObject();
        break;
      }
    }
  }
  const int width = selected.value("width").toInt();
  const int height = selected.value("height").toInt();
  const int origin_x = selected.value("x").toInt();
  const int origin_y = selected.value("y").toInt();
  const int workspace = selected.value("activeWorkspace").toObject()
                            .value("id").toInt(-1);
  const auto reserved = selected.value("reserved").toArray();
  const int reserved_bottom = reserved.size() == 4 ? reserved.at(3).toInt() : 0;
  if (width < 1 || height < 1 || width > 16384 || height > 16384 ||
      workspace < 0 || output_names.isEmpty() || output_names.size() > 32)
    return QJsonDocument(QJsonObject{{"ok", false}, {"error", "invalid-source"}})
        .toJson(QJsonDocument::Compact);
  QJsonArray windows;
  for (const auto &value : *clients) {
    if (windows.size() >= 64 || !value.isObject())
      break;
    const auto client = value.toObject();
    const auto at = client.value("at").toArray();
    const auto size = client.value("size").toArray();
    const auto client_workspace =
        client.value("workspace").toObject().value("id").toInt(-2);
    if (at.size() != 2 || size.size() != 2 || client_workspace != workspace ||
        client.value("hidden").toBool() || !client.value("mapped").toBool(true) ||
        client.value("fullscreen").toInt() != 0)
      continue;
    const int x = at.at(0).toInt() - origin_x;
    const int y = at.at(1).toInt() - origin_y;
    const int window_width = size.at(0).toInt();
    const int window_height = size.at(1).toInt();
    const auto address = client.value("address").toString();
    if (address.isEmpty() || window_width < 1 || window_height < 1 ||
        x >= width || y >= height || x + window_width <= 0 ||
        y + window_height <= 0)
      continue;
    windows.append(QJsonObject{{"id", opaque_window_id(address)},
                               {"x", std::max(0, x)},
                               {"y", std::max(0, y)},
                               {"width", std::min(width, x + window_width) -
                                             std::max(0, x)},
                               {"height", std::min(height, y + window_height) -
                                              std::max(0, y)}});
  }
  return QJsonDocument(QJsonObject{{"ok", true},
                                   {"output", selected.value("name")},
                                   {"outputs", output_names},
                                   {"width", width},
                                   {"height", height},
                                   {"reservedBottom", std::clamp(reserved_bottom, 0, height)},
                                   {"windows", windows}})
      .toJson(QJsonDocument::Compact);
}

bool send_response(std::uint64_t correlation, const QByteArray &payload) {
  std::vector<std::byte> frame;
  put_u32(frame, kMagic);
  frame.push_back(std::byte{1});
  frame.push_back(std::byte{2});
  frame.push_back(std::byte{0});
  frame.push_back(std::byte{0});
  put_u64(frame, correlation);
  put_u32(frame, static_cast<std::uint32_t>(payload.size() + 1));
  frame.push_back(std::byte{0});
  const auto bytes = std::as_bytes(
      std::span(payload.constData(), static_cast<std::size_t>(payload.size())));
  frame.insert(frame.end(), bytes.begin(), bytes.end());
  iovec part{.iov_base = frame.data(), .iov_len = frame.size()};
  msghdr message{};
  message.msg_iov = &part;
  message.msg_iovlen = 1;
  return ::sendmsg(3, &message, MSG_NOSIGNAL) ==
         static_cast<ssize_t>(frame.size());
}

} // namespace

int main() {
  std::array<std::byte, kMaximumFrameBytes + 1> frame{};
  while (true) {
    iovec part{.iov_base = frame.data(), .iov_len = frame.size()};
    msghdr message{};
    message.msg_iov = &part;
    message.msg_iovlen = 1;
    const auto count = ::recvmsg(3, &message, MSG_TRUNC);
    if (count == 0)
      return 0;
    if (count < 0)
      return 1;
    if (count > static_cast<ssize_t>(kMaximumFrameBytes))
      return 2;
    const auto request =
        decode(std::span(frame.data(), static_cast<std::size_t>(count)));
    if (!request)
      return 2;
    const auto payload = authorized(*request)
                             ? (request->dataset == QStringLiteral("packages.summary")
                                    ? observe()
                                    : observe_compositor(request->output))
                             : QJsonDocument(QJsonObject{{"ok", false},
                                                         {"error", "rejected"}})
                                   .toJson(QJsonDocument::Compact);
    if (!send_response(request->correlation, payload))
      return 3;
  }
}
