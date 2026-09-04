#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcess>
#include <QProcessEnvironment>
#include <QUrl>

#include <pwd.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <unistd.h>

#include <algorithm>
#include <array>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <limits>
#include <optional>
#include <span>
#include <string>
#include <string_view>
#include <vector>

namespace {

constexpr std::uint32_t kMagic = 0x4f505256;
constexpr std::uint8_t kVersion = 1;
constexpr std::size_t kHeaderBytes = 20;
constexpr std::size_t kMaximumFrameBytes = 64 * 1024 + kHeaderBytes;
constexpr qsizetype kMaximumUrlBytes = 2048;
constexpr qsizetype kMaximumOrigins = 32;

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

template <std::size_t Size>
bool exact_keys(const QJsonObject &object,
                const std::array<std::string_view, Size> &allowed) {
  return std::ranges::all_of(object.keys(), [&](const QString &key) {
    const auto utf8 = key.toUtf8();
    return std::ranges::find(allowed, std::string_view(utf8.constData(),
                                                       utf8.size())) !=
           allowed.end();
  });
}

struct Request final {
  std::uint64_t correlation = 0;
  QString demand_scope;
  QString url;
  QString presentation;
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
      adapter != "desktop-open-uri" || operation != "open" || abi != 1 ||
      contract != OMARCHY_DESKTOP_OPEN_CONTRACT_DIGEST)
    return std::nullopt;
  QJsonParseError error{};
  const auto document = QJsonDocument::fromJson(
      QByteArray(reinterpret_cast<const char *>(frame.data() + offset),
                 static_cast<qsizetype>(payload_size)),
      &error);
  if (error.error != QJsonParseError::NoError || !document.isObject())
    return std::nullopt;
  const auto payload = document.object();
  constexpr std::array keys{std::string_view("url"),
                            std::string_view("presentation")};
  if (payload.size() != 2 || !exact_keys(payload, keys) ||
      !payload.value("url").isString() ||
      !payload.value("presentation").isString())
    return std::nullopt;
  return Request{.correlation = correlation,
                 .demand_scope = QString::fromUtf8(scope),
                 .url = payload.value("url").toString(),
                 .presentation = payload.value("presentation").toString()};
}

std::optional<QString> origin(const QUrl &url, bool origin_only) {
  if (!url.isValid() || url.isRelative() ||
      url.scheme().compare(QStringLiteral("https"), Qt::CaseInsensitive) != 0 ||
      url.host().isEmpty() || !url.userName().isEmpty() ||
      !url.password().isEmpty() || (url.port(-1) != -1 && url.port() != 443) ||
      (origin_only && (!url.path().isEmpty() || url.hasQuery() || url.hasFragment())))
    return std::nullopt;
  const auto ace = QUrl::toAce(url.host()).toLower();
  if (ace.isEmpty())
    return std::nullopt;
  return QStringLiteral("https://") + QString::fromLatin1(ace);
}

std::optional<QByteArray> authorized_url(const Request &request) {
  const auto raw = request.url.toUtf8();
  if (raw.isEmpty() || raw.size() > kMaximumUrlBytes ||
      raw.contains('\0') || raw.contains('\r') || raw.contains('\n'))
    return std::nullopt;
  QJsonParseError error{};
  const auto document = QJsonDocument::fromJson(request.demand_scope.toUtf8(),
                                                 &error);
  if (error.error != QJsonParseError::NoError || !document.isObject())
    return std::nullopt;
  const auto scope = document.object();
  constexpr std::array keys{std::string_view("origins"),
                            std::string_view("userGesture")};
  if (scope.size() != 2 || !exact_keys(scope, keys) ||
      scope.value("userGesture") != true || !scope.value("origins").isArray())
    return std::nullopt;
  const auto requested = QUrl::fromEncoded(raw, QUrl::StrictMode);
  const auto requested_origin = origin(requested, false);
  if (!requested_origin)
    return std::nullopt;
  const auto origins = scope.value("origins").toArray();
  if (origins.isEmpty() || origins.size() > kMaximumOrigins)
    return std::nullopt;
  bool allowed = false;
  for (const auto &value : origins) {
    if (!value.isString())
      return std::nullopt;
    const auto candidate = origin(QUrl(value.toString(), QUrl::StrictMode), true);
    if (!candidate)
      return std::nullopt;
    allowed = allowed || *candidate == *requested_origin;
  }
  if (!allowed)
    return std::nullopt;
  return requested.toEncoded(QUrl::FullyEncoded);
}

bool trusted_owner(const struct stat &metadata) {
#ifdef OMARCHY_DESKTOP_OPEN_TESTING
  (void)metadata;
  return true;
#else
  return metadata.st_uid == 0;
#endif
}

bool secure_directory(const char *path) {
  struct stat metadata {};
  if (::lstat(path, &metadata) != 0)
    return false;
  return S_ISDIR(metadata.st_mode) && trusted_owner(metadata) &&
         (metadata.st_mode & 0022) == 0;
}

bool secure_executable(const char *path) {
  struct stat metadata {};
  if (!secure_directory("/") || !secure_directory("/usr") ||
      !secure_directory("/usr/bin") || ::lstat(path, &metadata) != 0)
    return false;
  return S_ISREG(metadata.st_mode) && trusted_owner(metadata) &&
         (metadata.st_mode & 0022) == 0 && (metadata.st_mode & 06000) == 0 &&
         (metadata.st_mode & 0100) != 0;
}

#ifndef OMARCHY_DESKTOP_OPEN_TESTING
QString account_home() {
  const auto *account = ::getpwuid(::getuid());
  if (!account || !account->pw_dir)
    return QStringLiteral("/nonexistent");
  const QString result = QString::fromLocal8Bit(account->pw_dir);
  return result.startsWith('/') && !result.contains(QChar::Null)
             ? result
             : QStringLiteral("/nonexistent");
}
#endif

bool launch(const QByteArray &url, const QString &presentation,
            std::uint64_t correlation) {
  constexpr auto systemd_run = "/usr/bin/systemd-run";
  constexpr auto xdg_open = "/usr/bin/xdg-open";
  constexpr auto chromium = "/usr/bin/chromium";
  if (!secure_executable(systemd_run) ||
      (presentation == QStringLiteral("browser-tab") &&
       !secure_executable(xdg_open)) ||
      (presentation == QStringLiteral("web-app-window") &&
       !secure_executable(chromium)))
    return false;
#ifdef OMARCHY_DESKTOP_OPEN_TESTING
  (void)url;
  (void)correlation;
  return true;
#else
  const auto uid = ::getuid();
  const QString runtime_dir = QStringLiteral("/run/user/") + QString::number(uid);
  QProcess process;
  QProcessEnvironment environment;
  environment.insert(QStringLiteral("PATH"), QStringLiteral("/usr/bin"));
  environment.insert(QStringLiteral("LANG"), QStringLiteral("C.UTF-8"));
  environment.insert(QStringLiteral("LC_ALL"), QStringLiteral("C.UTF-8"));
  environment.insert(QStringLiteral("HOME"), account_home());
  environment.insert(QStringLiteral("XDG_RUNTIME_DIR"), runtime_dir);
  environment.insert(QStringLiteral("DBUS_SESSION_BUS_ADDRESS"),
                     QStringLiteral("unix:path=") + runtime_dir +
                         QStringLiteral("/bus"));
  process.setProcessEnvironment(environment);
  process.setProgram(QString::fromLatin1(systemd_run));
  QStringList arguments{
      QStringLiteral("--user"), QStringLiteral("--quiet"),
      QStringLiteral("--collect"),
      QStringLiteral("--unit=omarchy-plugin-open-") +
          QString::number(::getpid()) + QStringLiteral("-") +
          QString::number(correlation),
      QStringLiteral("--property=Type=exec"),
      QStringLiteral("--property=StandardOutput=null"),
      QStringLiteral("--property=StandardError=null"), QStringLiteral("--")};
  if (presentation == QStringLiteral("browser-tab")) {
    arguments << QString::fromLatin1(xdg_open) << QString::fromUtf8(url);
  } else {
    arguments << QString::fromLatin1(chromium)
              << QStringLiteral("--app=") + QString::fromUtf8(url);
  }
  process.setArguments(arguments);
  process.start(QIODevice::ReadOnly);
  if (!process.waitForStarted(1000))
    return false;
  if (!process.waitForFinished(2500)) {
    process.kill();
    process.waitForFinished(500);
    return false;
  }
  return process.exitStatus() == QProcess::NormalExit &&
         process.exitCode() == 0;
#endif
}

bool send_response(std::uint64_t correlation, bool success,
                   std::string_view error) {
  const auto payload = QJsonDocument(QJsonObject{
      {"ok", success}, {"error", QString::fromUtf8(error)}})
                           .toJson(QJsonDocument::Compact);
  std::vector<std::byte> frame;
  put_u32(frame, kMagic);
  frame.push_back(std::byte{1});
  frame.push_back(std::byte{2});
  frame.push_back(std::byte{0});
  frame.push_back(std::byte{0});
  put_u64(frame, correlation);
  put_u32(frame, static_cast<std::uint32_t>(payload.size() + 1));
  frame.push_back(std::byte{0});
  const auto bytes = std::as_bytes(std::span(payload.constData(),
                                              static_cast<std::size_t>(payload.size())));
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
    const auto request = decode(
        std::span(frame.data(), static_cast<std::size_t>(count)));
    if (!request)
      return 2;
    const auto url = authorized_url(*request);
    if (!url || (request->presentation != QStringLiteral("browser-tab") &&
                 request->presentation != QStringLiteral("web-app-window"))) {
      if (!send_response(request->correlation, false, "url-rejected"))
        return 3;
      continue;
    }
    const bool opened =
        launch(*url, request->presentation, request->correlation);
    if (!send_response(request->correlation, opened,
                       opened ? "" : "desktop-open-failed"))
      return 3;
  }
}
