#include <QCryptographicHash>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonValue>

#include <arpa/inet.h>
#include <curl/curl.h>
#include <fcntl.h>
#include <netdb.h>
#include <poll.h>
#include <signal.h>
#include <sys/eventfd.h>
#include <sys/prctl.h>
#include <sys/random.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

#include <algorithm>
#include <array>
#include <atomic>
#include <charconv>
#include <cerrno>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <map>
#include <memory>
#include <optional>
#include <span>
#include <stdexcept>
#include <string>
#include <string_view>
#include <thread>
#include <vector>

namespace {

constexpr std::uint32_t kMagic = 0x4f505256;
constexpr std::size_t kHeaderBytes = 20;
constexpr std::size_t kMaximumFrameBytes = 64 * 1024 + kHeaderBytes;
constexpr std::size_t kMaximumRequestBody = 32 * 1024;
constexpr std::size_t kMaximumResponseBody = 56 * 1024;
constexpr std::size_t kMaximumMediaPointers = 64;
constexpr std::size_t kMaximumHandles = 256;
#ifndef OMARCHY_PROVIDER_CHANNEL_FD
#define OMARCHY_PROVIDER_CHANNEL_FD 3
#endif
constexpr int kProviderChannel = OMARCHY_PROVIDER_CHANNEL_FD;

struct Request final {
  std::uint64_t correlation = 0;
  std::string adapter;
  std::string contract;
  std::string operation;
  QByteArray scope;
  QJsonObject payload;
};

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

void put32(std::vector<std::byte> &bytes, std::uint32_t value) {
  for (int shift = 24; shift >= 0; shift -= 8)
    bytes.push_back(static_cast<std::byte>(value >> shift));
}

void put64(std::vector<std::byte> &bytes, std::uint64_t value) {
  for (int shift = 56; shift >= 0; shift -= 8)
    bytes.push_back(static_cast<std::byte>(value >> shift));
}

bool read_text(std::span<const std::byte> bytes, std::size_t &offset,
               std::string &output) {
  bool ok = true;
  const auto length = u16(bytes, offset, ok);
  offset += 2;
  if (!ok || length == 0 || offset + length > bytes.size())
    return false;
  output.assign(reinterpret_cast<const char *>(bytes.data() + offset), length);
  offset += length;
  return output.find('\0') == std::string::npos;
}

std::optional<Request> decode(std::span<const std::byte> bytes) {
  bool ok = true;
  if (bytes.size() < kHeaderBytes || u32(bytes, 0, ok) != kMagic || !ok ||
      bytes[4] != std::byte{1} || bytes[5] != std::byte{1} ||
      bytes[6] != std::byte{0} || bytes[7] != std::byte{0})
    return std::nullopt;
  const auto correlation = u64(bytes, 8, ok);
  const auto body_size = u32(bytes, 16, ok);
  if (!ok || correlation == 0 || body_size + kHeaderBytes != bytes.size())
    return std::nullopt;
  std::size_t offset = kHeaderBytes;
  Request request;
  request.correlation = correlation;
  if (!read_text(bytes, offset, request.adapter) ||
      !read_text(bytes, offset, request.contract))
    return std::nullopt;
  const auto abi = u32(bytes, offset, ok);
  offset += 4;
  if (!ok || abi != 1 || !read_text(bytes, offset, request.operation))
    return std::nullopt;
  std::string scope;
  if (!read_text(bytes, offset, scope))
    return std::nullopt;
  request.scope = QByteArray::fromStdString(scope);
  const auto payload_size = u32(bytes, offset, ok);
  offset += 4;
  if (!ok || payload_size > kMaximumRequestBody ||
      offset + payload_size != bytes.size())
    return std::nullopt;
  QJsonParseError error{};
  const auto document = QJsonDocument::fromJson(
      QByteArray(reinterpret_cast<const char *>(bytes.data() + offset),
                 static_cast<qsizetype>(payload_size)),
      &error);
  if (error.error != QJsonParseError::NoError || !document.isObject())
    return std::nullopt;
  request.payload = document.object();
  return request;
}

std::vector<std::byte> response(std::uint64_t correlation,
                                const QJsonObject &payload) {
  const auto json = QJsonDocument(payload).toJson(QJsonDocument::Compact);
  if (json.size() > static_cast<qsizetype>(64 * 1024))
    return {};
  std::vector<std::byte> frame;
  frame.reserve(kHeaderBytes + 1 + static_cast<std::size_t>(json.size()));
  put32(frame, kMagic);
  frame.insert(frame.end(),
               {std::byte{1}, std::byte{2}, std::byte{0}, std::byte{0}});
  put64(frame, correlation);
  put32(frame, static_cast<std::uint32_t>(json.size() + 1));
  frame.push_back(std::byte{0});
  const auto raw = std::as_bytes(std::span(json.constData(),
                                           static_cast<std::size_t>(json.size())));
  frame.insert(frame.end(), raw.begin(), raw.end());
  return frame;
}

QJsonObject failure(QString code) {
  return {{QStringLiteral("ok"), false}, {QStringLiteral("error"), code}};
}

bool exact_keys(const QJsonObject &object,
                std::initializer_list<QStringView> required,
                std::initializer_list<QStringView> optional = {}) {
  for (const auto key : required)
    if (!object.contains(key))
      return false;
  for (auto it = object.begin(); it != object.end(); ++it) {
    const auto key = QStringView(it.key());
    const bool known = std::ranges::any_of(required, [&](const auto value) {
      return value == key;
    }) || std::ranges::any_of(optional, [&](const auto value) {
      return value == key;
    });
    if (!known)
      return false;
  }
  return true;
}

bool public_ipv4(std::uint32_t address) noexcept {
  const auto value = ntohl(address);
  const auto first = value >> 24U;
  const auto second = (value >> 16U) & 0xffU;
  const auto third = (value >> 8U) & 0xffU;
  return first != 0 && first != 10 && first != 127 && first < 224 &&
         !(first == 100 && second >= 64 && second <= 127) &&
         !(first == 169 && second == 254) &&
         !(first == 172 && second >= 16 && second <= 31) &&
         !(first == 192 && second == 0 && third == 0) &&
         !(first == 192 && second == 0 && third == 2) &&
         !(first == 192 && second == 88 && third == 99) &&
         !(first == 192 && second == 168) &&
         !(first == 198 && (second == 18 || second == 19)) &&
         !(first == 198 && second == 51 && third == 100) &&
         !(first == 203 && second == 0 && third == 113);
}

bool public_ipv6(const in6_addr &address) noexcept {
  const auto *bytes = address.s6_addr;
  const bool global_unicast = (bytes[0] & 0xe0U) == 0x20U;
  const bool translation_prefix = bytes[0] == 0 && bytes[1] == 0x64 &&
                                  bytes[2] == 0xff && bytes[3] == 0x9b;
  const bool special_2001 = bytes[0] == 0x20 && bytes[1] == 0x01 &&
                            bytes[2] <= 0x01;
  const bool documentation = bytes[0] == 0x20 && bytes[1] == 0x01 &&
                             bytes[2] == 0x0d && bytes[3] == 0xb8;
  return global_unicast && !IN6_IS_ADDR_V4MAPPED(&address) &&
         (bytes[0] & 0xfeU) != 0xfcU &&
         !(bytes[0] == 0xfe && (bytes[1] & 0xc0U) == 0x80U) &&
         bytes[0] != 0xff && !translation_prefix && !special_2001 &&
         !documentation && !(bytes[0] == 0x20 && bytes[1] == 0x02);
}

curl_socket_t open_public_socket(void *, curlsocktype purpose,
                                 struct curl_sockaddr *address) noexcept {
  if (purpose != CURLSOCKTYPE_IPCXN || address == nullptr)
    return CURL_SOCKET_BAD;
  bool allowed = false;
  if (address->family == AF_INET &&
      address->addrlen >= static_cast<int>(sizeof(sockaddr_in)))
    allowed = public_ipv4(
        reinterpret_cast<const sockaddr_in *>(&address->addr)->sin_addr.s_addr);
  else if (address->family == AF_INET6 &&
           address->addrlen >= static_cast<int>(sizeof(sockaddr_in6)))
    allowed = public_ipv6(
        reinterpret_cast<const sockaddr_in6 *>(&address->addr)->sin6_addr);
  return allowed ? ::socket(address->family,
                            address->socktype | SOCK_CLOEXEC,
                            address->protocol)
                 : CURL_SOCKET_BAD;
}

bool safe_url(std::string_view value, bool media_source) {
  if (value.size() > 4096 || value.find('\0') != value.npos ||
      value.find_first_of("\r\n") != value.npos)
    return false;
  std::unique_ptr<CURLU, decltype(&curl_url_cleanup)> parsed(curl_url(),
                                                             curl_url_cleanup);
  if (!parsed || curl_url_set(parsed.get(), CURLUPART_URL,
                              std::string(value).c_str(), 0) != CURLUE_OK)
    return false;
  char *scheme = nullptr;
  char *host = nullptr;
  char *user = nullptr;
  char *password = nullptr;
  char *port = nullptr;
  const bool got_scheme =
      curl_url_get(parsed.get(), CURLUPART_SCHEME, &scheme, 0) == CURLUE_OK;
  const bool got_host =
      curl_url_get(parsed.get(), CURLUPART_HOST, &host, 0) == CURLUE_OK;
  const std::string_view scheme_value = scheme != nullptr ? scheme : "";
  const bool basic = got_scheme && got_host &&
      (scheme_value == "https" || (media_source && scheme_value == "http")) &&
      host != nullptr && std::string_view(host) != "localhost" &&
      !std::string_view(host).ends_with(".localhost");
  const bool has_user =
      curl_url_get(parsed.get(), CURLUPART_USER, &user, 0) == CURLUE_OK;
  const bool has_password =
      curl_url_get(parsed.get(), CURLUPART_PASSWORD, &password, 0) == CURLUE_OK;
  const bool has_port =
      curl_url_get(parsed.get(), CURLUPART_PORT, &port, 0) == CURLUE_OK;
  bool good_port = !has_port;
  if (has_port && port != nullptr) {
    unsigned parsed_port = 0;
    const auto port_value = std::string_view(port);
    const auto [end, error] = std::from_chars(
        port_value.data(), port_value.data() + port_value.size(), parsed_port);
    good_port = error == std::errc{} &&
                end == port_value.data() + port_value.size() &&
                parsed_port > 0 && parsed_port <= 65535 &&
                (media_source || (scheme_value == "https" && parsed_port == 443));
  }
  curl_free(scheme);
  curl_free(host);
  curl_free(user);
  curl_free(password);
  curl_free(port);
  return basic && !has_user && !has_password && good_port;
}

bool safe_https_url(std::string_view value) { return safe_url(value, false); }

bool safe_media_url(std::string_view value) { return safe_url(value, true); }

bool resolves_only_public(std::string_view url) {
  std::unique_ptr<CURLU, decltype(&curl_url_cleanup)> parsed(curl_url(),
                                                             curl_url_cleanup);
  if (!parsed || curl_url_set(parsed.get(), CURLUPART_URL,
                              std::string(url).c_str(), 0) != CURLUE_OK)
    return false;
  char *raw_host = nullptr;
  if (curl_url_get(parsed.get(), CURLUPART_HOST, &raw_host, 0) != CURLUE_OK ||
      raw_host == nullptr)
    return false;
  std::unique_ptr<char, decltype(&curl_free)> host(raw_host, curl_free);
#ifdef OMARCHY_NETWORK_MEDIA_TESTING
  if (std::string_view(host.get()) == "stream.example")
    return true;
#endif
  std::string lookup_host(host.get());
  if (lookup_host.size() > 2 && lookup_host.front() == '[' &&
      lookup_host.back() == ']')
    lookup_host = lookup_host.substr(1, lookup_host.size() - 2);
  addrinfo hints{};
  hints.ai_family = AF_UNSPEC;
  hints.ai_socktype = SOCK_STREAM;
  hints.ai_flags = AI_ADDRCONFIG;
  addrinfo *raw = nullptr;
  if (::getaddrinfo(lookup_host.c_str(), nullptr, &hints, &raw) != 0 ||
      raw == nullptr)
    return false;
  std::unique_ptr<addrinfo, decltype(&freeaddrinfo)> addresses(raw,
                                                               freeaddrinfo);
  bool found = false;
  for (auto *current = raw; current != nullptr; current = current->ai_next) {
    bool allowed = false;
    if (current->ai_family == AF_INET &&
        current->ai_addrlen >= static_cast<socklen_t>(sizeof(sockaddr_in)))
      allowed = public_ipv4(
          reinterpret_cast<const sockaddr_in *>(current->ai_addr)
              ->sin_addr.s_addr);
    else if (current->ai_family == AF_INET6 &&
             current->ai_addrlen >=
                 static_cast<socklen_t>(sizeof(sockaddr_in6)))
      allowed = public_ipv6(
          reinterpret_cast<const sockaddr_in6 *>(current->ai_addr)->sin6_addr);
    if (!allowed)
      return false;
    found = true;
  }
  return found;
}

std::optional<std::string> normalized_origin(std::string_view value) {
  if (!safe_https_url(value))
    return std::nullopt;
  std::unique_ptr<CURLU, decltype(&curl_url_cleanup)> parsed(curl_url(),
                                                             curl_url_cleanup);
  if (!parsed || curl_url_set(parsed.get(), CURLUPART_URL,
                              std::string(value).c_str(), 0) != CURLUE_OK)
    return std::nullopt;
  char *scheme = nullptr;
  char *host = nullptr;
  char *port = nullptr;
  if (curl_url_get(parsed.get(), CURLUPART_SCHEME, &scheme, 0) != CURLUE_OK ||
      curl_url_get(parsed.get(), CURLUPART_HOST, &host, 0) != CURLUE_OK) {
    curl_free(scheme);
    curl_free(host);
    return std::nullopt;
  }
  (void)curl_url_get(parsed.get(), CURLUPART_PORT, &port, 0);
  std::string result = std::string(scheme) + "://" + host;
  if (port != nullptr && std::string_view(port) != "443")
    result += ":" + std::string(port);
  curl_free(scheme);
  curl_free(host);
  curl_free(port);
  return result;
}

struct Scope final {
  std::vector<std::string> origins;
  std::vector<std::string> methods;
};

std::optional<Scope> parse_network_scope(const QByteArray &bytes) {
  QJsonParseError error{};
  const auto document = QJsonDocument::fromJson(bytes, &error);
  if (error.error != QJsonParseError::NoError || !document.isObject())
    return std::nullopt;
  const auto object = document.object();
  if (!exact_keys(object, {u"origins", u"methods"}) ||
      !object.value(QStringLiteral("origins")).isArray() ||
      !object.value(QStringLiteral("methods")).isArray())
    return std::nullopt;
  Scope scope;
  const auto origins = object.value(QStringLiteral("origins")).toArray();
  const auto methods = object.value(QStringLiteral("methods")).toArray();
  if (origins.isEmpty() || origins.size() > 32 || methods.isEmpty() ||
      methods.size() > 8)
    return std::nullopt;
  for (const auto &entry : origins) {
    if (!entry.isString())
      return std::nullopt;
    const auto normalized = normalized_origin(entry.toString().toStdString());
    if (!normalized || std::ranges::find(scope.origins, *normalized) !=
                           scope.origins.end())
      return std::nullopt;
    scope.origins.push_back(*normalized);
  }
  for (const auto &entry : methods) {
    if (!entry.isString())
      return std::nullopt;
    const auto method = entry.toString().toUpper().toStdString();
    if ((method != "GET" && method != "POST") ||
        std::ranges::find(scope.methods, method) != scope.methods.end())
      return std::nullopt;
    scope.methods.push_back(method);
  }
  return scope;
}

struct CurlOutput final {
  QByteArray bytes;
  bool overflow = false;
};

std::size_t bounded_write(char *data, std::size_t size, std::size_t count,
                          void *opaque) noexcept {
  auto &output = *static_cast<CurlOutput *>(opaque);
  if (count != 0 && size > std::numeric_limits<std::size_t>::max() / count) {
    output.overflow = true;
    return 0;
  }
  const auto length = size * count;
  if (length > kMaximumResponseBody -
                   static_cast<std::size_t>(output.bytes.size())) {
    output.overflow = true;
    return 0;
  }
  output.bytes.append(data, static_cast<qsizetype>(length));
  return length;
}

std::optional<QJsonValue> json_pointer(QJsonValue value,
                                       const QString &pointer) {
  if (pointer.isEmpty())
    return value;
  if (!pointer.startsWith('/') || pointer.size() > 512)
    return std::nullopt;
  const auto parts = pointer.mid(1).split('/');
  for (auto part : parts) {
    part.replace(QStringLiteral("~1"), QStringLiteral("/"));
    part.replace(QStringLiteral("~0"), QStringLiteral("~"));
    if (value.isObject()) {
      const auto object = value.toObject();
      if (!object.contains(part))
        return std::nullopt;
      value = object.value(part);
    } else if (value.isArray()) {
      bool ok = false;
      const auto index = part.toInt(&ok);
      const auto array = value.toArray();
      if (!ok || index < 0 || index >= array.size() ||
          QString::number(index) != part)
        return std::nullopt;
      value = array.at(index);
    } else {
      return std::nullopt;
    }
  }
  return value;
}

#ifndef OMARCHY_NETWORK_MEDIA_TESTING
bool secure_executable(const char *path) {
  for (const auto directory : {"/", "/usr", "/usr/bin"}) {
    struct stat metadata{};
    if (::lstat(directory, &metadata) < 0 || !S_ISDIR(metadata.st_mode) ||
        metadata.st_uid != 0 || (metadata.st_mode & 0022) != 0)
      return false;
  }
  struct stat metadata{};
  return ::lstat(path, &metadata) == 0 && S_ISREG(metadata.st_mode) &&
         metadata.st_uid == 0 && (metadata.st_mode & 0022) == 0 &&
         (metadata.st_mode & 06000) == 0 && (metadata.st_mode & 0100) != 0;
}
#endif

class Player final {
public:
  ~Player() { stop(); }

  bool play(const std::string &url, int volume) {
    if (!safe_media_url(url) || volume < 0 || volume > 100)
      return false;
    stop();
#ifdef OMARCHY_NETWORK_MEDIA_TESTING
    running_ = true;
    paused_ = false;
    muted_ = false;
    volume_ = volume;
    return true;
#endif
    int commands[2] = {-1, -1};
    int media[2] = {-1, -1};
    const int stop_event = ::eventfd(0, EFD_CLOEXEC | EFD_NONBLOCK);
    if (stop_event < 0 || ::pipe2(commands, O_CLOEXEC) < 0 ||
        ::pipe2(media, O_CLOEXEC) < 0) {
      close_pair(commands);
      close_pair(media);
      if (stop_event >= 0)
        ::close(stop_event);
      return false;
    }
    if (::fcntl(commands[1], F_SETFL,
                ::fcntl(commands[1], F_GETFL) | O_NONBLOCK) < 0 ||
        ::fcntl(media[1], F_SETFL,
                ::fcntl(media[1], F_GETFL) | O_NONBLOCK) < 0) {
      close_pair(commands);
      close_pair(media);
      ::close(stop_event);
      return false;
    }
    const pid_t child = ::fork();
    if (child < 0) {
      close_pair(commands);
      close_pair(media);
      ::close(stop_event);
      return false;
    }
    if (child == 0) {
      (void)::prctl(PR_SET_PDEATHSIG, SIGKILL, 0, 0, 0);
      (void)::setpgid(0, 0);
      ::close(stop_event);
      ::close(3);
      if (::dup2(commands[0], STDIN_FILENO) != STDIN_FILENO ||
          ::dup2(media[0], 3) != 3)
        _exit(126);
      const int null_fd = ::open("/dev/null", O_RDWR | O_CLOEXEC | O_NOFOLLOW);
      if (null_fd < 0 || ::dup2(null_fd, STDOUT_FILENO) != STDOUT_FILENO ||
          ::dup2(null_fd, STDERR_FILENO) != STDERR_FILENO)
        _exit(126);
      ::close(commands[0]);
      ::close(commands[1]);
      if (media[0] != 3)
        ::close(media[0]);
      ::close(media[1]);
      if (null_fd > STDERR_FILENO)
        ::close(null_fd);
      const std::string runtime = "/run/user/" + std::to_string(::getuid());
      const std::string pipewire = runtime + "/pipewire-0";
      const std::string volume_argument = "--volume=" + std::to_string(volume);
      std::array<char *, 70> arguments{
          const_cast<char *>("/usr/bin/bwrap"),
          const_cast<char *>("--die-with-parent"),
          const_cast<char *>("--new-session"),
          const_cast<char *>("--unshare-all"),
          const_cast<char *>("--ro-bind"), const_cast<char *>("/usr"),
          const_cast<char *>("/usr"), const_cast<char *>("--symlink"),
          const_cast<char *>("usr/lib"), const_cast<char *>("/lib"),
          const_cast<char *>("--symlink"), const_cast<char *>("usr/lib"),
          const_cast<char *>("/lib64"), const_cast<char *>("--symlink"),
          const_cast<char *>("usr/bin"), const_cast<char *>("/bin"),
          const_cast<char *>("--ro-bind"), const_cast<char *>("/etc"),
          const_cast<char *>("/etc"), const_cast<char *>("--proc"),
          const_cast<char *>("/proc"), const_cast<char *>("--dev"),
          const_cast<char *>("/dev"), const_cast<char *>("--tmpfs"),
          const_cast<char *>("/tmp"), const_cast<char *>("--dir"),
          const_cast<char *>("/run"), const_cast<char *>("--dir"),
          const_cast<char *>("/run/user"), const_cast<char *>("--dir"),
          const_cast<char *>(runtime.c_str()),
          const_cast<char *>("--ro-bind-try"),
          const_cast<char *>(pipewire.c_str()),
          const_cast<char *>(pipewire.c_str()),
          const_cast<char *>("--setenv"), const_cast<char *>("XDG_RUNTIME_DIR"),
          const_cast<char *>(runtime.c_str()), const_cast<char *>("--setenv"),
          const_cast<char *>("HOME"), const_cast<char *>("/nonexistent"),
          const_cast<char *>("--setenv"), const_cast<char *>("PATH"),
          const_cast<char *>("/usr/bin"), const_cast<char *>("--setenv"),
          const_cast<char *>("LANG"), const_cast<char *>("C"),
          const_cast<char *>("/usr/bin/mpv"), const_cast<char *>("--no-config"),
          const_cast<char *>("--load-scripts=no"),
          const_cast<char *>("--ytdl=no"),
          const_cast<char *>("--access-references=no"),
          const_cast<char *>("--autoload-files=no"),
          const_cast<char *>("--no-video"),
          const_cast<char *>("--force-window=no"),
          const_cast<char *>("--audio-display=no"),
          const_cast<char *>("--input-terminal=yes"),
          const_cast<char *>(volume_argument.c_str()),
          const_cast<char *>("--demuxer-lavf-o=protocol_whitelist=file"),
          const_cast<char *>("--"), const_cast<char *>("/proc/self/fd/3"),
          nullptr};
      std::array<char *, 4> environment{
          const_cast<char *>("PATH=/usr/bin"), const_cast<char *>("LANG=C"),
          const_cast<char *>("HOME=/nonexistent"), nullptr};
      ::execve("/usr/bin/bwrap", arguments.data(), environment.data());
      _exit(127);
    }
    ::close(commands[0]);
    ::close(media[0]);
    input_ = commands[1];
    media_ = media[1];
    stop_event_ = stop_event;
    pid_ = child;
    stopping_.store(false);
    stream_ = std::thread([this, url] { stream(url); });
    running_ = true;
    paused_ = false;
    muted_ = false;
    volume_ = volume;
    return true;
  }

  bool control(const std::string &name, int value) {
    reap();
    if (name == "status")
      return true;
    if (!running_)
      return false;
#ifdef OMARCHY_NETWORK_MEDIA_TESTING
    if (name == "pause") {
      paused_ = !paused_;
      return true;
    }
    if (name == "mute") {
      muted_ = !muted_;
      return true;
    }
    if (name == "volume" && value >= 0 && value <= 100) {
      volume_ = value;
      return true;
    }
    if (name == "stop") {
      stop();
      return true;
    }
    return false;
#endif
    if (name == "pause" && command("cycle pause\n")) {
      paused_ = !paused_;
      return true;
    }
    if (name == "mute" && command("cycle mute\n")) {
      muted_ = !muted_;
      return true;
    }
    if (name == "volume" && value >= 0 && value <= 100 &&
        command("set volume " + std::to_string(value) + "\n")) {
      volume_ = value;
      return true;
    }
    if (name == "stop") {
      stop();
      return true;
    }
    return false;
  }

  bool running() {
    reap();
    return running_;
  }
  bool paused() const { return paused_; }
  bool muted() const { return muted_; }
  int volume() const { return volume_; }

private:
  static void close_pair(int (&pair)[2]) noexcept {
    for (auto &descriptor : pair) {
      if (descriptor >= 0)
        ::close(descriptor);
      descriptor = -1;
    }
  }

  bool stream_write(const char *data, std::size_t length) noexcept {
    std::size_t offset = 0;
    while (offset < length && !stopping_.load()) {
      std::array<pollfd, 2> descriptors{{
          {.fd = media_, .events = POLLOUT, .revents = 0},
          {.fd = stop_event_, .events = POLLIN, .revents = 0}}};
      const int ready = ::poll(descriptors.data(), descriptors.size(), 50);
      if (ready < 0 && errno == EINTR)
        continue;
      if (ready <= 0)
        continue;
      if ((descriptors[1].revents & (POLLIN | POLLERR | POLLHUP)) != 0 ||
          (descriptors[0].revents & (POLLERR | POLLHUP | POLLNVAL)) != 0)
        return false;
      if ((descriptors[0].revents & POLLOUT) == 0)
        continue;
      const auto written = ::write(media_, data + offset, length - offset);
      if (written > 0)
        offset += static_cast<std::size_t>(written);
      else if (written < 0 && (errno == EINTR || errno == EAGAIN))
        continue;
      else
        return false;
    }
    return offset == length;
  }

  void stream(const std::string &url) noexcept {
    std::unique_ptr<CURL, decltype(&curl_easy_cleanup)> curl(curl_easy_init(),
                                                             curl_easy_cleanup);
    if (curl) {
      curl_easy_setopt(curl.get(), CURLOPT_URL, url.c_str());
      curl_easy_setopt(curl.get(), CURLOPT_HTTPGET, 1L);
      curl_easy_setopt(curl.get(), CURLOPT_PROTOCOLS_STR, "http,https");
      curl_easy_setopt(curl.get(), CURLOPT_REDIR_PROTOCOLS_STR, "http,https");
      curl_easy_setopt(curl.get(), CURLOPT_FOLLOWLOCATION, 1L);
      curl_easy_setopt(curl.get(), CURLOPT_MAXREDIRS, 5L);
      curl_easy_setopt(curl.get(), CURLOPT_CONNECTTIMEOUT_MS, 3000L);
      curl_easy_setopt(curl.get(), CURLOPT_LOW_SPEED_LIMIT, 128L);
      curl_easy_setopt(curl.get(), CURLOPT_LOW_SPEED_TIME, 10L);
      curl_easy_setopt(curl.get(), CURLOPT_FAILONERROR, 1L);
      curl_easy_setopt(curl.get(), CURLOPT_PROXY, "");
      curl_easy_setopt(curl.get(), CURLOPT_USERAGENT, "Omarchy-Media-Provider/1");
      curl_easy_setopt(curl.get(), CURLOPT_OPENSOCKETFUNCTION,
                       open_public_socket);
      curl_easy_setopt(curl.get(), CURLOPT_NOPROGRESS, 0L);
      curl_easy_setopt(curl.get(), CURLOPT_XFERINFOFUNCTION,
                       +[](void *opaque, curl_off_t, curl_off_t, curl_off_t,
                          curl_off_t) noexcept -> int {
                         return static_cast<Player *>(opaque)->stopping_.load()
                                    ? 1
                                    : 0;
                       });
      curl_easy_setopt(curl.get(), CURLOPT_XFERINFODATA, this);
      curl_easy_setopt(curl.get(), CURLOPT_WRITEFUNCTION,
                       +[](char *data, std::size_t size, std::size_t count,
                          void *opaque) noexcept -> std::size_t {
                         auto *self = static_cast<Player *>(opaque);
                         if (count != 0 && size >
                                               std::numeric_limits<std::size_t>::max() /
                                                   count)
                           return 0;
                         const auto length = size * count;
                         return self->stream_write(data, length) ? length : 0;
                       });
      curl_easy_setopt(curl.get(), CURLOPT_WRITEDATA, this);
      (void)curl_easy_perform(curl.get());
    }
    if (media_ >= 0) {
      ::close(media_);
      media_ = -1;
    }
  }

  bool command(const std::string &value) {
    return input_ >= 0 &&
           ::write(input_, value.data(), value.size()) ==
               static_cast<ssize_t>(value.size());
  }

  void wake_stream() noexcept {
    stopping_.store(true);
    if (stop_event_ >= 0) {
      const std::uint64_t wake = 1;
      (void)::write(stop_event_, &wake, sizeof(wake));
    }
  }

  void join_stream() noexcept {
    wake_stream();
    if (stream_.joinable())
      stream_.join();
    if (stop_event_ >= 0)
      ::close(stop_event_);
    stop_event_ = -1;
  }

  static void drain_children() noexcept {
    while (true) {
      const auto reaped = ::waitpid(-1, nullptr, 0);
      if (reaped > 0)
        continue;
      if (reaped < 0 && errno == EINTR)
        continue;
      return;
    }
  }

  void reap() {
    if (pid_ <= 0)
      return;
    const auto result = ::waitpid(pid_, nullptr, WNOHANG);
    if (result == pid_ || (result < 0 && errno == ECHILD)) {
      const pid_t group = pid_;
      if (input_ >= 0)
        ::close(input_);
      input_ = -1;
      join_stream();
      (void)::kill(-group, SIGKILL);
      drain_children();
      pid_ = -1;
      running_ = false;
      paused_ = false;
    }
  }

  void stop() {
#ifdef OMARCHY_NETWORK_MEDIA_TESTING
    running_ = false;
    paused_ = false;
    return;
#endif
    reap();
    if (pid_ <= 0) {
      join_stream();
      return;
    }
    (void)command("quit\n");
    wake_stream();
    if (input_ >= 0)
      ::close(input_);
    input_ = -1;
    const pid_t group = pid_;
    (void)::kill(-group, SIGTERM);
    (void)::kill(pid_, SIGTERM);
    join_stream();
    for (int index = 0; index < 16; ++index) {
      if (::waitpid(pid_, nullptr, WNOHANG) == pid_) {
        (void)::kill(-group, SIGKILL);
        drain_children();
        pid_ = -1;
        running_ = false;
        return;
      }
      ::usleep(10000);
    }
    (void)::kill(-group, SIGKILL);
    (void)::kill(pid_, SIGKILL);
    drain_children();
    pid_ = -1;
    running_ = false;
  }

  pid_t pid_ = -1;
  int input_ = -1;
  int media_ = -1;
  int stop_event_ = -1;
  std::atomic<bool> stopping_{false};
  std::thread stream_;
  bool running_ = false;
  bool paused_ = false;
  bool muted_ = false;
  int volume_ = 70;
};

class Provider final {
public:
  Provider() {
#ifndef OMARCHY_NETWORK_MEDIA_TESTING
    if (!secure_executable("/usr/bin/bwrap") ||
        !secure_executable("/usr/bin/mpv"))
      throw std::runtime_error("fixed media executables are unavailable");
#endif
    std::size_t offset = 0;
    while (offset < secret_.size()) {
      const auto count = ::getrandom(secret_.data() + offset,
                                     secret_.size() - offset, 0);
      if (count > 0) {
        offset += static_cast<std::size_t>(count);
      } else if (count < 0 && errno == EINTR) {
        continue;
      } else {
        throw std::runtime_error("secure randomness is unavailable");
      }
    }
  }

  QJsonObject dispatch(const Request &request) {
    if (request.adapter == "bounded-network-fetch" &&
        request.contract == OMARCHY_NETWORK_FETCH_CONTRACT_DIGEST &&
        request.operation == "fetch")
      return fetch(request);
    if (request.adapter == "activation-media-stream" &&
        request.contract == OMARCHY_MEDIA_STREAM_CONTRACT_DIGEST &&
        (request.operation == "play" || request.operation == "control"))
      return media(request);
    return failure(QStringLiteral("outside-contract"));
  }

private:
  std::string mint_handle(const std::string &url) {
    QByteArray input(reinterpret_cast<const char *>(secret_.data()),
                     static_cast<qsizetype>(secret_.size()));
    input.append('\0');
    input.append(QByteArray::fromStdString(url));
    const auto token = QCryptographicHash::hash(input, QCryptographicHash::Sha256)
                           .toHex()
                           .left(32)
                           .toStdString();
    if (handles_.size() >= kMaximumHandles)
      handles_.erase(handles_.begin());
    handles_[token] = url;
    return token;
  }

  QJsonObject fetch(const Request &request) {
    const auto scope = parse_network_scope(request.scope);
    if (!scope ||
        !exact_keys(request.payload, {u"method", u"origin", u"path"},
                    {u"headers", u"body", u"responseType",
                     u"mediaJsonPointers"}) ||
        !request.payload.value(QStringLiteral("method")).isString() ||
        !request.payload.value(QStringLiteral("origin")).isString() ||
        !request.payload.value(QStringLiteral("path")).isString())
      return failure(QStringLiteral("invalid-request"));
    const auto method = request.payload.value(QStringLiteral("method"))
                            .toString()
                            .toUpper()
                            .toStdString();
    const auto origin_value =
        request.payload.value(QStringLiteral("origin")).toString().toStdString();
    const auto origin = normalized_origin(origin_value);
    const auto path = request.payload.value(QStringLiteral("path"))
                          .toString()
                          .toStdString();
    if (!origin || std::ranges::find(scope->origins, *origin) ==
                       scope->origins.end() ||
        std::ranges::find(scope->methods, method) == scope->methods.end() ||
        path.empty() || path.front() != '/' || path.size() > 4096 ||
        path.find_first_of("\r\n") != path.npos)
      return failure(QStringLiteral("outside-scope"));
    const std::string url = *origin + path;
    if (!safe_https_url(url) || normalized_origin(url) != origin)
      return failure(QStringLiteral("invalid-url"));

    QByteArray body;
    if (request.payload.contains(QStringLiteral("body"))) {
      if (!request.payload.value(QStringLiteral("body")).isString())
        return failure(QStringLiteral("invalid-body"));
      body = request.payload.value(QStringLiteral("body")).toString().toUtf8();
      if (body.size() > static_cast<qsizetype>(kMaximumRequestBody))
        return failure(QStringLiteral("request-limit"));
    }
    if ((method == "GET" && !body.isEmpty()) ||
        (method == "POST" && body.isEmpty()))
      return failure(QStringLiteral("invalid-body"));
    const auto response_type =
        request.payload.value(QStringLiteral("responseType"));
    if (!response_type.isUndefined() &&
        (!response_type.isString() ||
         (response_type.toString() != QStringLiteral("text") &&
          response_type.toString() != QStringLiteral("json"))))
      return failure(QStringLiteral("invalid-response-type"));

    curl_slist *headers = nullptr;
    if (request.payload.contains(QStringLiteral("headers"))) {
      if (!request.payload.value(QStringLiteral("headers")).isObject())
        return failure(QStringLiteral("invalid-headers"));
      const auto object =
          request.payload.value(QStringLiteral("headers")).toObject();
      if (object.size() > 2)
        return failure(QStringLiteral("invalid-headers"));
      for (auto it = object.begin(); it != object.end(); ++it) {
        const auto name = it.key().toLower();
        if ((name != QStringLiteral("accept") &&
             name != QStringLiteral("content-type")) ||
            !it.value().isString() || it.value().toString().isEmpty() ||
            it.value().toString().toUtf8().size() > 256 ||
            it.value().toString().contains('\r') ||
            it.value().toString().contains('\n')) {
          curl_slist_free_all(headers);
          return failure(QStringLiteral("invalid-headers"));
        }
        const auto line = (name + QStringLiteral(": ") + it.value().toString())
                              .toUtf8();
        auto *next = curl_slist_append(headers, line.constData());
        if (!next) {
          curl_slist_free_all(headers);
          return failure(QStringLiteral("resource-exhausted"));
        }
        headers = next;
      }
    }

    CurlOutput output;
    long status = 0;
    QByteArray content_type;
#ifdef OMARCHY_NETWORK_MEDIA_TESTING
    if (*origin == "https://fixture.invalid") {
      if (path == "/redirect") {
        status = 302;
      } else if (path == "/private-source") {
        status = 200;
        output.bytes = R"([{"url":"https://127.0.0.1/audio"}])";
      } else {
        status = 200;
        output.bytes = R"([{"name":"secure","url":"https://stream.example/audio"},{"name":"cleartext","url":"http://stream.example:8000/audio"}])";
      }
      content_type = "application/json";
    } else
#endif
    {
      std::unique_ptr<CURL, decltype(&curl_easy_cleanup)> curl(
          curl_easy_init(), curl_easy_cleanup);
      if (!curl) {
        curl_slist_free_all(headers);
        return failure(QStringLiteral("resource-exhausted"));
      }
      curl_easy_setopt(curl.get(), CURLOPT_URL, url.c_str());
      curl_easy_setopt(curl.get(), CURLOPT_CUSTOMREQUEST, method.c_str());
      curl_easy_setopt(curl.get(), CURLOPT_PROTOCOLS_STR, "https");
      curl_easy_setopt(curl.get(), CURLOPT_FOLLOWLOCATION, 0L);
      curl_easy_setopt(curl.get(), CURLOPT_CONNECTTIMEOUT_MS, 3000L);
      curl_easy_setopt(curl.get(), CURLOPT_TIMEOUT_MS, 20000L);
      curl_easy_setopt(curl.get(), CURLOPT_MAXFILESIZE_LARGE,
                       static_cast<curl_off_t>(kMaximumResponseBody));
      curl_easy_setopt(curl.get(), CURLOPT_PROXY, "");
      curl_easy_setopt(curl.get(), CURLOPT_USERAGENT,
                       "Omarchy-Network-Provider/1");
      curl_easy_setopt(curl.get(), CURLOPT_OPENSOCKETFUNCTION,
                       open_public_socket);
      curl_easy_setopt(curl.get(), CURLOPT_WRITEFUNCTION, bounded_write);
      curl_easy_setopt(curl.get(), CURLOPT_WRITEDATA, &output);
      if (headers)
        curl_easy_setopt(curl.get(), CURLOPT_HTTPHEADER, headers);
      if (!body.isEmpty()) {
        curl_easy_setopt(curl.get(), CURLOPT_POSTFIELDS, body.constData());
        curl_easy_setopt(curl.get(), CURLOPT_POSTFIELDSIZE,
                         static_cast<long>(body.size()));
      }
      const auto result = curl_easy_perform(curl.get());
      char *raw_content_type = nullptr;
      curl_easy_getinfo(curl.get(), CURLINFO_RESPONSE_CODE, &status);
      curl_easy_getinfo(curl.get(), CURLINFO_CONTENT_TYPE, &raw_content_type);
      content_type = raw_content_type ? QByteArray(raw_content_type) : QByteArray();
      if (result != CURLE_OK || output.overflow) {
        curl_slist_free_all(headers);
        return failure(output.overflow ? QStringLiteral("response-limit")
                                       : QStringLiteral("network-failed"));
      }
    }
    curl_slist_free_all(headers);
    if (status >= 300 && status < 400)
      return failure(QStringLiteral("redirect-rejected"));

    QJsonDocument response_document;
    const bool json_response =
        response_type.toString() == QStringLiteral("json");
    const bool needs_json = json_response ||
        request.payload.contains(QStringLiteral("mediaJsonPointers"));
    if (needs_json) {
      QJsonParseError parse_error{};
      response_document = QJsonDocument::fromJson(output.bytes, &parse_error);
      if (parse_error.error != QJsonParseError::NoError ||
          (!response_document.isArray() && !response_document.isObject()))
        return failure(QStringLiteral("response-json-invalid"));
    }

    QJsonObject source_handles;
    if (request.payload.contains(QStringLiteral("mediaJsonPointers"))) {
      const auto pointers_value =
          request.payload.value(QStringLiteral("mediaJsonPointers"));
      if (!pointers_value.isArray() ||
          pointers_value.toArray().size() >
              static_cast<qsizetype>(kMaximumMediaPointers))
        return failure(QStringLiteral("invalid-media-pointers"));
      for (const auto &pointer_value : pointers_value.toArray()) {
        if (!pointer_value.isString() ||
            source_handles.contains(pointer_value.toString()))
          return failure(QStringLiteral("invalid-media-pointers"));
        QStringList concrete_pointers;
        const auto pointer = pointer_value.toString();
        if (pointer.startsWith(QStringLiteral("/*/"))) {
          if (!response_document.isArray())
            return failure(QStringLiteral("media-source-document-invalid"));
          const auto count = std::min<qsizetype>(
              response_document.array().size(),
              static_cast<qsizetype>(kMaximumMediaPointers -
                                     source_handles.size()));
          for (qsizetype index = 0; index < count; ++index)
            concrete_pointers.push_back(QStringLiteral("/") +
                                        QString::number(index) +
                                        pointer.mid(2));
        } else {
          concrete_pointers.push_back(pointer);
        }
        for (const auto &concrete : concrete_pointers) {
          const auto selected = json_pointer(
              response_document.isArray()
                  ? QJsonValue(response_document.array())
                  : QJsonValue(response_document.object()),
              concrete);
          if (!selected || !selected->isString()) {
            if (pointer.startsWith(QStringLiteral("/*/")))
              continue;
            return failure(QStringLiteral("media-source-missing"));
          }
          const auto source = selected->toString().toStdString();
          // Fetch authority remains HTTPS-only. Media sources are opaque
          // provider-minted handles and may preserve public HTTP streams; every
          // connection and redirect is independently restricted to public IPs.
          if (!safe_media_url(source) || !resolves_only_public(source)) {
            if (pointer.startsWith(QStringLiteral("/*/")))
              continue;
            return failure(QStringLiteral("media-source-invalid"));
          }
          source_handles.insert(concrete,
                                QString::fromStdString(mint_handle(source)));
        }
      }
    }
    QJsonObject reply{{QStringLiteral("ok"), true},
                      {QStringLiteral("status"), static_cast<qint64>(status)},
                      {QStringLiteral("contentType"),
                       QString::fromUtf8(content_type)},
                      {QStringLiteral("sourceHandles"), source_handles}};
    if (json_response) {
      reply.insert(QStringLiteral("json"),
                   response_document.isArray()
                       ? QJsonValue(response_document.array())
                       : QJsonValue(response_document.object()));
    } else {
      reply.insert(QStringLiteral("body"), QString::fromUtf8(output.bytes));
    }
    if (QJsonDocument(reply).toJson(QJsonDocument::Compact).size() > 60 * 1024)
      return failure(QStringLiteral("response-limit"));
    return reply;
  }

  bool media_scope(const QByteArray &bytes, const std::string &control) const {
    QJsonParseError error{};
    const auto document = QJsonDocument::fromJson(bytes, &error);
    if (error.error != QJsonParseError::NoError || !document.isObject())
      return false;
    const auto object = document.object();
    if (!exact_keys(object, {u"controls", u"sourceHandles"}) ||
        !object.value(QStringLiteral("controls")).isArray() ||
        !object.value(QStringLiteral("sourceHandles")).isArray())
      return false;
    const auto handles = object.value(QStringLiteral("sourceHandles")).toArray();
    const auto controls = object.value(QStringLiteral("controls")).toArray();
    if (handles.size() != 1 || !handles.at(0).isString() ||
        handles.at(0).toString() != QStringLiteral("network.fetch") ||
        controls.isEmpty() || controls.size() > 8)
      return false;
    std::vector<std::string> seen;
    for (const auto &entry : controls) {
      if (!entry.isString())
        return false;
      const auto value = entry.toString().toStdString();
      if ((value != "pause" && value != "stop" && value != "mute" &&
           value != "volume" && value != "status") ||
          std::ranges::find(seen, value) != seen.end())
        return false;
      seen.push_back(value);
    }
    return control.empty() || std::ranges::find(seen, control) != seen.end();
  }

  QJsonObject media(const Request &request) {
    std::string control;
    int volume = 70;
    if (request.operation == "play") {
      if (!exact_keys(request.payload, {u"handle"}, {u"volume"}) ||
          !request.payload.value(QStringLiteral("handle")).isString())
        return failure(QStringLiteral("invalid-request"));
      if (request.payload.contains(QStringLiteral("volume"))) {
        if (!request.payload.value(QStringLiteral("volume")).isDouble())
          return failure(QStringLiteral("invalid-request"));
        const auto requested =
            request.payload.value(QStringLiteral("volume")).toDouble(-1);
        if (requested < 0 || requested > 100)
          return failure(QStringLiteral("invalid-request"));
        volume = static_cast<int>(requested);
        if (requested != static_cast<double>(volume))
          return failure(QStringLiteral("invalid-request"));
      }
      const auto handle = request.payload.value(QStringLiteral("handle"))
                              .toString()
                              .toStdString();
      const auto found = handles_.find(handle);
      if (!media_scope(request.scope, {}) || handle.size() != 32 ||
          found == handles_.end() || volume < 0 || volume > 100 ||
          !player_.play(found->second, volume))
        return failure(QStringLiteral("invalid-handle"));
    } else {
      if (!exact_keys(request.payload, {u"control"}, {u"value"}) ||
          !request.payload.value(QStringLiteral("control")).isString())
        return failure(QStringLiteral("invalid-request"));
      control = request.payload.value(QStringLiteral("control"))
                    .toString()
                    .toStdString();
      int value = 0;
      if (control == "volume") {
        if (!request.payload.value(QStringLiteral("value")).isDouble())
          return failure(QStringLiteral("invalid-request"));
        const auto requested =
            request.payload.value(QStringLiteral("value")).toDouble(-1);
        if (requested < 0 || requested > 100)
          return failure(QStringLiteral("invalid-request"));
        value = static_cast<int>(requested);
        if (requested != static_cast<double>(value))
          return failure(QStringLiteral("invalid-request"));
      } else if (request.payload.contains(QStringLiteral("value"))) {
        return failure(QStringLiteral("invalid-request"));
      }
      if (!media_scope(request.scope, control) ||
          !player_.control(control, value))
        return failure(QStringLiteral("provider-failed"));
    }
    return {{QStringLiteral("ok"), true},
            {QStringLiteral("running"), player_.running()},
            {QStringLiteral("paused"), player_.paused()},
            {QStringLiteral("muted"), player_.muted()},
            {QStringLiteral("volume"), player_.volume()}};
  }

  std::array<unsigned char, 32> secret_{};
  std::map<std::string, std::string> handles_;
  Player player_;
};

} // namespace

int main() {
  struct sigaction ignored_pipe {};
  ignored_pipe.sa_handler = SIG_IGN;
  ::sigemptyset(&ignored_pipe.sa_mask);
  if (::sigaction(SIGPIPE, &ignored_pipe, nullptr) < 0 ||
      ::prctl(PR_SET_CHILD_SUBREAPER, 1) < 0 ||
      curl_global_init(CURL_GLOBAL_DEFAULT) != CURLE_OK)
    return 78;
  try {
    Provider provider;
    std::array<std::byte, kMaximumFrameBytes> incoming{};
    while (true) {
      const auto count =
          ::recv(kProviderChannel, incoming.data(), incoming.size(), 0);
      if (count == 0)
        return 0;
      if (count < 0) {
        if (errno == EINTR)
          continue;
        return 74;
      }
      auto request = decode(std::span(incoming.data(),
                                      static_cast<std::size_t>(count)));
      if (!request)
        return 65;
      auto frame = response(request->correlation, provider.dispatch(*request));
      if (frame.empty() ||
          ::send(kProviderChannel, frame.data(), frame.size(), MSG_NOSIGNAL) !=
              static_cast<ssize_t>(frame.size()))
        return 74;
    }
  } catch (...) {
    return 78;
  }
}
