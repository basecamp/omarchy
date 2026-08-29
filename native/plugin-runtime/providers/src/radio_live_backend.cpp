#include "omarchy/plugin_runtime/providers/radio_live_backend.hpp"

#include <curl/curl.h>

#include <arpa/inet.h>
#include <netinet/in.h>
#include <sys/socket.h>

#include <algorithm>
#include <array>
#include <cstring>
#include <mutex>
#include <string>

namespace omarchy::plugin_runtime::providers {
namespace {

constexpr std::string_view kOrigin = "https://all.api.radio-browser.info";

struct CurlOutput {
  std::span<std::byte> bytes;
  std::size_t used = 0;
  bool overflow = false;
};

std::size_t write_response(char *data, std::size_t size, std::size_t count,
                           void *opaque) noexcept {
  auto &output = *static_cast<CurlOutput *>(opaque);
  if (count != 0 && size > static_cast<std::size_t>(-1) / count) {
    output.overflow = true;
    return 0;
  }
  const auto length = size * count;
  if (length > output.bytes.size() - output.used) {
    output.overflow = true;
    return 0;
  }
  std::memcpy(output.bytes.data() + output.used, data, length);
  output.used += length;
  return length;
}

bool public_ipv4(std::uint32_t address) noexcept {
  const auto value = ntohl(address);
  const auto first = value >> 24;
  const auto second = (value >> 16) & 0xff;
  return first != 0 && first != 10 && first != 127 && first < 224 &&
         !(first == 100 && second >= 64 && second <= 127) &&
         !(first == 169 && second == 254) &&
         !(first == 172 && second >= 16 && second <= 31) &&
         !(first == 192 && second == 168) &&
         !(first == 198 && (second == 18 || second == 19));
}

bool public_ipv6(const in6_addr &address) noexcept {
  static constexpr std::array<unsigned char, 16> zero{};
  static constexpr std::array<unsigned char, 16> loopback{
      0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1};
  const auto *bytes = address.s6_addr;
  return !std::equal(zero.begin(), zero.end(), bytes) &&
         !std::equal(loopback.begin(), loopback.end(), bytes) &&
         (bytes[0] & 0xfe) != 0xfc &&
         !(bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80) &&
         bytes[0] != 0xff;
}

curl_socket_t open_public_socket(void *, curlsocktype purpose,
                                 struct curl_sockaddr *address) noexcept {
  if (purpose != CURLSOCKTYPE_IPCXN || address == nullptr) return CURL_SOCKET_BAD;
  bool allowed = false;
  if (address->family == AF_INET &&
      address->addrlen >= static_cast<int>(sizeof(sockaddr_in))) {
    allowed = public_ipv4(reinterpret_cast<const sockaddr_in *>(&address->addr)->sin_addr.s_addr);
  } else if (address->family == AF_INET6 &&
             address->addrlen >= static_cast<int>(sizeof(sockaddr_in6))) {
    allowed = public_ipv6(reinterpret_cast<const sockaddr_in6 *>(&address->addr)->sin6_addr);
  }
  if (!allowed) return CURL_SOCKET_BAD;
  return ::socket(address->family, address->socktype | SOCK_CLOEXEC,
                  address->protocol);
}

bool safe_path(std::string_view path) noexcept {
  return path.starts_with("/json/stations/topvote/") &&
         path.size() <= 128 && path.find_first_of("\r\n#@\\") == path.npos;
}

bool write_player(QProcess &player, const QByteArray &command) noexcept {
  if (player.state() != QProcess::Running) return false;
  return player.write(command) == command.size() && player.waitForBytesWritten(1000);
}

} // namespace

RadioLiveBackend::RadioLiveBackend() {
  static std::once_flag curl_once;
  std::call_once(curl_once, [] { (void)curl_global_init(CURL_GLOBAL_DEFAULT); });
  player_.setProcessChannelMode(QProcess::ForwardedErrorChannel);
  player_.setStandardOutputFile(QProcess::nullDevice());
}

RadioLiveBackend::~RadioLiveBackend() {
  if (player_.state() == QProcess::NotRunning) return;
  player_.write("quit\n");
  player_.waitForFinished(1500);
  if (player_.state() != QProcess::NotRunning) player_.kill();
  player_.waitForFinished(1500);
}

RadioHttpsBackend RadioLiveBackend::https_configuration() noexcept {
  return {.get = get, .context = this};
}

RadioMediaBackend RadioLiveBackend::media_configuration() noexcept {
  return {.play = play, .control = control, .context = this};
}

bool RadioLiveBackend::get(std::string_view origin, std::string_view path,
                           std::span<std::byte> output, std::size_t &written,
                           void *) noexcept {
  written = 0;
  if (origin != kOrigin || !safe_path(path) || output.empty()) return false;
  try {
    const std::string url = std::string(origin) + std::string(path);
    std::unique_ptr<CURL, decltype(&curl_easy_cleanup)> curl(curl_easy_init(),
                                                            curl_easy_cleanup);
    if (!curl) return false;
    CurlOutput destination{.bytes = output};
    curl_easy_setopt(curl.get(), CURLOPT_URL, url.c_str());
    curl_easy_setopt(curl.get(), CURLOPT_HTTPGET, 1L);
    curl_easy_setopt(curl.get(), CURLOPT_PROTOCOLS_STR, "https");
    curl_easy_setopt(curl.get(), CURLOPT_FOLLOWLOCATION, 0L);
    curl_easy_setopt(curl.get(), CURLOPT_CONNECTTIMEOUT_MS, 5000L);
    curl_easy_setopt(curl.get(), CURLOPT_TIMEOUT_MS, 15000L);
    curl_easy_setopt(curl.get(), CURLOPT_LOW_SPEED_LIMIT, 1024L);
    curl_easy_setopt(curl.get(), CURLOPT_LOW_SPEED_TIME, 5L);
    curl_easy_setopt(curl.get(), CURLOPT_MAXFILESIZE_LARGE,
                     static_cast<curl_off_t>(output.size()));
    curl_easy_setopt(curl.get(), CURLOPT_FAILONERROR, 1L);
    curl_easy_setopt(curl.get(), CURLOPT_PROXY, "");
    curl_easy_setopt(curl.get(), CURLOPT_USERAGENT,
                     "Omarchy-Secure-Radio-Provider/1");
    curl_easy_setopt(curl.get(), CURLOPT_WRITEFUNCTION, write_response);
    curl_easy_setopt(curl.get(), CURLOPT_WRITEDATA, &destination);
    curl_easy_setopt(curl.get(), CURLOPT_OPENSOCKETFUNCTION, open_public_socket);
    const auto result = curl_easy_perform(curl.get());
    long status = 0;
    char *content_type = nullptr;
    curl_easy_getinfo(curl.get(), CURLINFO_RESPONSE_CODE, &status);
    curl_easy_getinfo(curl.get(), CURLINFO_CONTENT_TYPE, &content_type);
    if (result != CURLE_OK || destination.overflow || status != 200 ||
        content_type == nullptr ||
        std::string_view(content_type).find("application/json") == std::string_view::npos)
      return false;
    written = destination.used;
    return written > 0;
  } catch (...) {
    return false;
  }
}

bool RadioLiveBackend::play(std::string_view stream_url, void *opaque) noexcept {
  auto &self = *static_cast<RadioLiveBackend *>(opaque);
  if (!stream_url.starts_with("https://") || stream_url.size() > 2047 ||
      stream_url.find_first_of("\r\n") != stream_url.npos)
    return false;
  if (self.player_.state() != QProcess::NotRunning) {
    self.player_.write("quit\n");
    self.player_.waitForFinished(1500);
    if (self.player_.state() != QProcess::NotRunning) self.player_.kill();
    self.player_.waitForFinished(1500);
  }
  self.player_.setProgram(QStringLiteral("/usr/bin/mpv"));
  self.player_.setArguments({QStringLiteral("--no-video"),
                             QStringLiteral("--force-window=no"),
                             QStringLiteral("--audio-display=no"),
                             QStringLiteral("--input-terminal=yes"),
                             QStringLiteral("--volume=70"),
                             QStringLiteral("--"),
                             QString::fromUtf8(stream_url)});
  self.player_.start(QIODevice::ReadWrite);
  return self.player_.waitForStarted(5000);
}

bool RadioLiveBackend::control(std::string_view control, std::uint32_t value,
                               void *opaque) noexcept {
  auto &player = static_cast<RadioLiveBackend *>(opaque)->player_;
  if (control == "status") return player.state() == QProcess::Running;
  if (control == "pause") return write_player(player, "cycle pause\n");
  if (control == "stop") return write_player(player, "stop\n");
  if (control == "mute") return write_player(player, "cycle mute\n");
  if (control == "volume" && value <= 100)
    return write_player(player, "set volume " + QByteArray::number(value) + "\n");
  return false;
}

} // namespace omarchy::plugin_runtime::providers
