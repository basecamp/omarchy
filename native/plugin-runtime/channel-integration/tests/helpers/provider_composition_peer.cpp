#include <sys/socket.h>
#include <unistd.h>

#include <array>
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <fstream>
#include <span>
#include <string>
#include <thread>
#include <vector>

namespace {
constexpr std::uint32_t kMagic = 0x4f505256;
constexpr std::size_t kHeader = 20;

std::uint32_t read32(const std::byte *bytes) {
  std::uint32_t value = 0;
  for (int index = 0; index < 4; ++index)
    value = (value << 8U) | std::to_integer<unsigned char>(bytes[index]);
  return value;
}

std::uint64_t read64(const std::byte *bytes) {
  std::uint64_t value = 0;
  for (int index = 0; index < 8; ++index)
    value = (value << 8U) | std::to_integer<unsigned char>(bytes[index]);
  return value;
}

void append32(std::vector<std::byte> &bytes, std::uint32_t value) {
  for (int shift = 24; shift >= 0; shift -= 8)
    bytes.push_back(static_cast<std::byte>(value >> shift));
}

void append64(std::vector<std::byte> &bytes, std::uint64_t value) {
  for (int shift = 56; shift >= 0; shift -= 8)
    bytes.push_back(static_cast<std::byte>(value >> shift));
}
} // namespace

int main(int argc, char **argv) {
  const std::string mode = argc > 1 ? argv[1] : "ok";
  if (argc > 2) {
    std::ofstream marker(argv[2], std::ios::app);
    marker << ::getpid() << '\n';
  }
  std::array<std::byte, 1024 * 1024 + 1024> request{};
  while (true) {
    iovec request_part{.iov_base = request.data(), .iov_len = request.size()};
    msghdr request_message{};
    request_message.msg_iov = &request_part;
    request_message.msg_iovlen = 1;
    const auto received = ::recvmsg(3, &request_message, 0);
    if (received <= 0)
      return 0;
    if (static_cast<std::size_t>(received) < kHeader ||
        read32(request.data()) != kMagic)
      return 2;
    if (mode == "crash")
      return 3;
    if (mode == "delayed-pid")
      std::this_thread::sleep_for(std::chrono::milliseconds(50));
    if (mode == "timeout" || mode == "late")
      std::this_thread::sleep_for(std::chrono::milliseconds(1200));

    const auto correlation = read64(request.data() + 8);
    const std::string payload = (mode == "pid" || mode == "delayed-pid")
                                    ? std::to_string(::getpid())
                                    : "composition-ok";
    std::vector<std::byte> response;
    append32(response, mode == "malformed" ? 0U : kMagic);
    response.insert(response.end(),
                    {std::byte{1}, std::byte{2}, std::byte{0}, std::byte{0}});
    append64(response, correlation);
    append32(response, static_cast<std::uint32_t>(payload.size() + 1));
    response.push_back(std::byte{0});
    const auto raw = std::as_bytes(std::span(payload.data(), payload.size()));
    response.insert(response.end(), raw.begin(), raw.end());
    if (mode == "truncated")
      response.resize(10);
    if (mode == "oversized")
      response.resize(1024 * 1024, std::byte{0});
    iovec response_part{.iov_base = response.data(),
                        .iov_len = response.size()};
    msghdr response_message{};
    response_message.msg_iov = &response_part;
    response_message.msg_iovlen = 1;
    if (::sendmsg(3, &response_message, MSG_NOSIGNAL) !=
        static_cast<ssize_t>(response.size()))
      return 4;
    if (mode == "late")
      return 0;
  }
}
