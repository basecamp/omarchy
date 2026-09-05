#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>

#include <fcntl.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <unistd.h>

#include <array>
#include <cerrno>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <span>
#include <string_view>
#include <vector>

namespace {

constexpr std::uint32_t kMagic = 0x4f505256;

[[noreturn]] void fail(std::string_view message) {
  std::cerr << "FAIL: " << message << '\n';
  std::exit(1);
}
void require(bool condition, std::string_view message) {
  if (!condition)
    fail(message);
}
void put_u16(std::vector<std::byte> &bytes, std::uint16_t value) {
  bytes.push_back(static_cast<std::byte>(value >> 8));
  bytes.push_back(static_cast<std::byte>(value));
}
void put_u32(std::vector<std::byte> &bytes, std::uint32_t value) {
  for (int shift = 24; shift >= 0; shift -= 8)
    bytes.push_back(static_cast<std::byte>(value >> shift));
}
void put_u64(std::vector<std::byte> &bytes, std::uint64_t value) {
  for (int shift = 56; shift >= 0; shift -= 8)
    bytes.push_back(static_cast<std::byte>(value >> shift));
}
void put_text(std::vector<std::byte> &bytes, std::string_view value) {
  put_u16(bytes, static_cast<std::uint16_t>(value.size()));
  const auto raw = std::as_bytes(std::span(value.data(), value.size()));
  bytes.insert(bytes.end(), raw.begin(), raw.end());
}

std::vector<std::byte> request(std::uint64_t correlation,
                               std::string_view dataset,
                               std::string_view output = {},
                               std::string_view scope =
                                   R"({"datasets":["packages.summary","compositor.window-rectangles"]})") {
  QJsonObject payload{{"dataset", QString::fromUtf8(dataset)}};
  if (!output.empty())
    payload.insert("output", QString::fromUtf8(output));
  const auto payload_bytes =
      QJsonDocument(payload).toJson(QJsonDocument::Compact);
  std::vector<std::byte> body;
  put_text(body, "sanitized-system-observe");
  put_text(body, SYSTEM_OBSERVE_CONTRACT_DIGEST);
  put_u32(body, 1);
  put_text(body, "observe");
  put_text(body, scope);
  put_u32(body, static_cast<std::uint32_t>(payload_bytes.size()));
  const auto raw = std::as_bytes(
      std::span(payload_bytes.constData(),
                static_cast<std::size_t>(payload_bytes.size())));
  body.insert(body.end(), raw.begin(), raw.end());
  std::vector<std::byte> frame;
  put_u32(frame, kMagic);
  frame.insert(frame.end(), {std::byte{1}, std::byte{1}, std::byte{0},
                             std::byte{0}});
  put_u64(frame, correlation);
  put_u32(frame, static_cast<std::uint32_t>(body.size()));
  frame.insert(frame.end(), body.begin(), body.end());
  return frame;
}

struct Child final {
  pid_t pid;
  int channel;
};
Child start() {
  int pair[2] = {-1, -1};
  require(::socketpair(AF_UNIX, SOCK_SEQPACKET | SOCK_CLOEXEC, 0, pair) == 0,
          "socketpair failed");
  const auto pid = ::fork();
  require(pid >= 0, "fork failed");
  if (pid == 0) {
    ::close(pair[0]);
    if (pair[1] != 3 && ::dup2(pair[1], 3) != 3)
      _exit(126);
    if (pair[1] != 3)
      ::close(pair[1]);
    (void)::fcntl(3, F_SETFD, 0);
    ::execl(SYSTEM_OBSERVER_PATH, SYSTEM_OBSERVER_PATH,
            static_cast<char *>(nullptr));
    _exit(127);
  }
  ::close(pair[1]);
  return {.pid = pid, .channel = pair[0]};
}
QJsonObject roundtrip(int channel, const std::vector<std::byte> &frame) {
  iovec request_part{.iov_base = const_cast<std::byte *>(frame.data()),
                     .iov_len = frame.size()};
  msghdr request_message{};
  request_message.msg_iov = &request_part;
  request_message.msg_iovlen = 1;
  const auto sent = ::sendmsg(channel, &request_message, MSG_NOSIGNAL);
  if (sent != static_cast<ssize_t>(frame.size())) {
    std::cerr << "send result=" << sent << " errno=" << errno << '\n';
    fail("request send failed");
  }
  std::array<std::byte, 4096> response{};
  iovec response_part{.iov_base = response.data(), .iov_len = response.size()};
  msghdr response_message{};
  response_message.msg_iov = &response_part;
  response_message.msg_iovlen = 1;
  const auto count = ::recvmsg(channel, &response_message, 0);
  require(count > 21 && response[4] == std::byte{1} &&
              response[5] == std::byte{2} && response[20] == std::byte{0},
          "response framing failed");
  const auto document = QJsonDocument::fromJson(QByteArray(
      reinterpret_cast<const char *>(response.data() + 21), count - 21));
  require(document.isObject(), "response JSON failed");
  return document.object();
}

} // namespace

int main() {
  const auto child = start();
  auto response = roundtrip(child.channel, request(1, "packages.summary"));
  require(response.value("ok").toBool() &&
              response.value("pendingUpdates").toInt() == 2 &&
              response.value("orphanCount").toInt() == 1,
          "fixed package probes did not return counts only");
  response = roundtrip(child.channel,
                       request(2, "compositor.window-rectangles", "DP-1"));
  require(response.value("ok").toBool() &&
              response.value("output").toString() == "DP-1" &&
              response.value("reservedBottom").toInt() == 32 &&
              response.value("windows").toArray().size() == 1,
          "sanitized compositor snapshot did not preserve bounded geometry");
  const auto encoded = QJsonDocument(response).toJson(QJsonDocument::Compact);
  require(!encoded.contains("0xsecret") && !encoded.contains("must-not-leak"),
          "raw compositor identity or metadata crossed the provider");
  response = roundtrip(
      child.channel,
      request(3, "packages.summary", {},
              R"({"datasets":["compositor.window-rectangles"]})"));
  require(!response.value("ok").toBool(),
          "package summary escaped its granted dataset scope");
  ::close(child.channel);
  int status = 0;
  while (::waitpid(child.pid, &status, 0) < 0 && errno == EINTR) {}
  require(WIFEXITED(status) && WEXITSTATUS(status) == 0,
          "system observer did not exit cleanly");
  std::cout << "system observer tests passed\n";
}
