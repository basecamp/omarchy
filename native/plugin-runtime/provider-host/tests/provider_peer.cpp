#include <arpa/inet.h>
#include <sys/socket.h>
#include <unistd.h>

#include <array>
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <cstdlib>
#include <span>
#include <string>
#include <thread>
#include <vector>

namespace {
constexpr std::uint32_t kMagic = 0x4f505256;
constexpr std::size_t kHeader = 20;

std::uint32_t u32(const std::byte *bytes) {
  std::uint32_t value = 0;
  for (int index = 0; index < 4; ++index)
    value = (value << 8) | std::to_integer<unsigned char>(bytes[index]);
  return value;
}
std::uint64_t u64(const std::byte *bytes) {
  std::uint64_t value = 0;
  for (int index = 0; index < 8; ++index)
    value = (value << 8) | std::to_integer<unsigned char>(bytes[index]);
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
std::string argument(int argc, char **argv) {
  return argc == 2 ? argv[1] : "echo";
}
} // namespace

int main(int argc, char **argv) {
  const auto mode = argument(argc, argv);
  std::array<std::byte, 1024 * 1024 + 1024> request{};
  while (true) {
    iovec request_part{.iov_base = request.data(), .iov_len = request.size()};
    msghdr request_message{};
    request_message.msg_iov = &request_part;
    request_message.msg_iovlen = 1;
    const auto count = ::recvmsg(3, &request_message, 0);
    if (count <= 0)
      return 0;
    if (static_cast<std::size_t>(count) < kHeader || u32(request.data()) != kMagic)
      return 2;
    if (mode == "crash")
      return 3;
    if (mode == "late")
      std::this_thread::sleep_for(std::chrono::milliseconds(250));
    const auto correlation = u64(request.data() + 8);
    std::string payload;
    if (mode == "pid")
      payload = std::to_string(::getpid());
    else if (mode == "environment")
      payload = std::string(::getenv("PATH") ? ::getenv("PATH") : "") + "|" +
                (::getenv("HOME") ? ::getenv("HOME") : "");
    else
      payload = "ok";
    std::vector<std::byte> response;
    put32(response, mode == "malformed" ? 0U : kMagic);
    response.push_back(std::byte{1});
    response.push_back(std::byte{2});
    response.push_back(std::byte{0});
    response.push_back(std::byte{0});
    put64(response, mode == "wrong-correlation" ? correlation + 1 : correlation);
    put32(response, static_cast<std::uint32_t>(payload.size() + 1));
    response.push_back(std::byte{0});
    const auto raw = std::as_bytes(std::span(payload.data(), payload.size()));
    response.insert(response.end(), raw.begin(), raw.end());
    iovec response_part{.iov_base = response.data(), .iov_len = response.size()};
    msghdr response_message{};
    response_message.msg_iov = &response_part;
    response_message.msg_iovlen = 1;
    if (::sendmsg(3, &response_message, MSG_NOSIGNAL) !=
        static_cast<ssize_t>(response.size()))
      return 4;
  }
}
