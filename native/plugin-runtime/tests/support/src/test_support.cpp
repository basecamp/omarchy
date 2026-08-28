#include "omarchy/plugin_runtime/test_support/test_support.h"

#include <dirent.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

#include <algorithm>
#include <array>
#include <cerrno>
#include <charconv>
#include <cstring>
#include <fstream>
#include <stdexcept>

namespace omarchy::plugin_runtime::test_support {
namespace {
constexpr std::size_t kMaximumPassedDescriptors = 16;

std::byte hex_nibble(char value) {
  if (value >= '0' && value <= '9') {
    return std::byte(value - '0');
  }
  if (value >= 'a' && value <= 'f') {
    return std::byte(value - 'a' + 10);
  }
  if (value >= 'A' && value <= 'F') {
    return std::byte(value - 'A' + 10);
  }
  throw std::invalid_argument("invalid hexadecimal digit");
}

void add_mutation(std::vector<Mutation> &output, std::size_t offset,
                  std::byte mask, std::vector<std::byte> bytes,
                  std::size_t maximum_cases) {
  if (output.size() < maximum_cases) {
    output.push_back({.ordinal = output.size(),
                      .offset = offset,
                      .mask = mask,
                      .bytes = std::move(bytes)});
  }
}
} // namespace

UniqueFd::UniqueFd(int descriptor) : descriptor_(descriptor) {}

UniqueFd::UniqueFd(UniqueFd &&other) noexcept : descriptor_(other.release()) {}

UniqueFd &UniqueFd::operator=(UniqueFd &&other) noexcept {
  if (this != &other) {
    reset(other.release());
  }
  return *this;
}

UniqueFd::~UniqueFd() { reset(); }

int UniqueFd::get() const { return descriptor_; }

UniqueFd::operator bool() const { return descriptor_ >= 0; }

int UniqueFd::release() {
  const int descriptor = descriptor_;
  descriptor_ = -1;
  return descriptor;
}

void UniqueFd::reset(int descriptor) {
  if (descriptor_ >= 0) {
    close(descriptor_);
  }
  descriptor_ = descriptor;
}

ManualClock::ManualClock(Tick initial) : now_(initial) {}

ManualClock::Tick ManualClock::now() const { return now_; }

ManualClock::Tick ManualClock::deadline_after(Tick duration) const {
  if (duration > std::numeric_limits<Tick>::max() - now_) {
    throw std::overflow_error("manual clock deadline overflow");
  }
  return now_ + duration;
}

bool ManualClock::expired(Tick deadline) const { return now_ >= deadline; }

void ManualClock::advance(Tick duration) { now_ = deadline_after(duration); }

DeterministicIdSource::DeterministicIdSource(std::uint64_t first)
    : next_(first) {
  if (first == 0) {
    throw std::invalid_argument("deterministic ids start above zero");
  }
}

std::uint64_t DeterministicIdSource::next() {
  if (next_ == 0) {
    throw std::overflow_error("deterministic id source exhausted");
  }
  const std::uint64_t result = next_;
  if (next_ == std::numeric_limits<std::uint64_t>::max()) {
    next_ = 0;
  } else {
    ++next_;
  }
  return result;
}

std::vector<Mutation> bounded_mutations(std::span<const std::byte> input,
                                        std::size_t maximum_cases) {
  std::vector<Mutation> output;
  output.reserve(std::min(maximum_cases, input.size() * 2 + 5));
  if (maximum_cases == 0) {
    return output;
  }
  if (input.empty()) {
    add_mutation(output, 0, std::byte{0}, {std::byte{0}}, maximum_cases);
    return output;
  }

  for (const std::size_t length :
       {std::size_t{0}, std::min<std::size_t>(1, input.size()),
        std::min<std::size_t>(39, input.size()),
        std::min<std::size_t>(40, input.size()), input.size() - 1}) {
    add_mutation(output, length, std::byte{0},
                 std::vector<std::byte>(input.begin(), input.begin() + length),
                 maximum_cases);
  }
  for (std::size_t offset = 0;
       offset < input.size() && output.size() < maximum_cases; ++offset) {
    for (const std::byte mask : {std::byte{0x01}, std::byte{0x80}}) {
      std::vector<std::byte> bytes(input.begin(), input.end());
      bytes.at(offset) ^= mask;
      add_mutation(output, offset, mask, std::move(bytes), maximum_cases);
    }
  }
  return output;
}

std::vector<std::byte> decode_hex(std::string_view text) {
  std::vector<std::byte> output;
  int high = -1;
  for (const char value : text) {
    if (value == ' ' || value == '\n' || value == '\r' || value == '\t') {
      continue;
    }
    const int nibble = std::to_integer<int>(hex_nibble(value));
    if (high < 0) {
      high = nibble;
    } else {
      output.push_back(std::byte((high << 4) | nibble));
      high = -1;
    }
  }
  if (high >= 0) {
    throw std::invalid_argument("odd hexadecimal input length");
  }
  return output;
}

std::string encode_hex(std::span<const std::byte> bytes) {
  constexpr std::string_view digits = "0123456789abcdef";
  std::string output;
  output.reserve(bytes.size() * 2);
  for (const std::byte byte : bytes) {
    const unsigned value = std::to_integer<unsigned>(byte);
    output.push_back(digits.at(value >> 4));
    output.push_back(digits.at(value & 0x0f));
  }
  return output;
}

std::vector<int> open_fd_set() {
  UniqueFd directory_fd(
      open("/proc/self/fd", O_RDONLY | O_DIRECTORY | O_CLOEXEC));
  if (!directory_fd) {
    throw std::runtime_error("cannot open /proc/self/fd");
  }
  DIR *directory = fdopendir(directory_fd.release());
  if (directory == nullptr) {
    throw std::runtime_error("cannot enumerate /proc/self/fd");
  }
  const int enumeration_fd = dirfd(directory);
  std::vector<int> output;
  while (const dirent *entry = readdir(directory)) {
    int value = -1;
    const std::string_view name(entry->d_name);
    const auto result =
        std::from_chars(name.data(), name.data() + name.size(), value);
    if (result.ec == std::errc{} && result.ptr == name.data() + name.size() &&
        value != enumeration_fd) {
      output.push_back(value);
    }
  }
  closedir(directory);
  std::ranges::sort(output);
  return output;
}

bool relocate_descriptors_exact(std::span<const int> sources,
                                std::span<const int> destinations,
                                unsigned close_from) {
  if (sources.size() != destinations.size() || sources.empty()) {
    return false;
  }
  std::vector<UniqueFd> staged;
  staged.reserve(sources.size());
  int minimum = 64;
  for (const int source : sources) {
    const int duplicate = fcntl(source, F_DUPFD_CLOEXEC, minimum);
    if (duplicate < 0) {
      return false;
    }
    staged.emplace_back(duplicate);
    minimum = duplicate + 1;
  }
  for (std::size_t index = 0; index < staged.size(); ++index) {
    if (dup2(staged.at(index).get(), destinations[index]) < 0) {
      return false;
    }
  }
  staged.clear();
  return syscall(SYS_close_range, close_from, ~0U, 0U) == 0;
}

SeqpacketPair SeqpacketPair::create() {
  std::array<int, 2> descriptors{};
  if (socketpair(AF_UNIX, SOCK_SEQPACKET | SOCK_CLOEXEC, 0,
                 descriptors.data()) < 0) {
    throw std::runtime_error("socketpair failed");
  }
  return {.trusted = UniqueFd(descriptors.at(0)),
          .worker = UniqueFd(descriptors.at(1))};
}

void enable_kernel_credentials(int descriptor) {
  const int enabled = 1;
  if (setsockopt(descriptor, SOL_SOCKET, SO_PASSCRED, &enabled,
                 sizeof(enabled)) < 0) {
    throw std::runtime_error("SO_PASSCRED failed");
  }
}

void send_packet(int descriptor, std::span<const std::byte> payload,
                 std::span<const int> descriptors) {
  if (descriptors.size() > kMaximumPassedDescriptors) {
    throw std::invalid_argument("too many descriptors for fixture packet");
  }
  iovec vector{.iov_base = const_cast<std::byte *>(payload.data()),
               .iov_len = payload.size()};
  alignas(cmsghdr)
      std::array<std::byte, CMSG_SPACE(kMaximumPassedDescriptors * sizeof(int))>
          control{};
  msghdr message{};
  message.msg_iov = &vector;
  message.msg_iovlen = 1;
  if (!descriptors.empty()) {
    message.msg_control = control.data();
    message.msg_controllen = CMSG_SPACE(descriptors.size() * sizeof(int));
    cmsghdr *header = CMSG_FIRSTHDR(&message);
    header->cmsg_level = SOL_SOCKET;
    header->cmsg_type = SCM_RIGHTS;
    header->cmsg_len = CMSG_LEN(descriptors.size() * sizeof(int));
    std::memcpy(CMSG_DATA(header), descriptors.data(),
                descriptors.size() * sizeof(int));
  }
  if (sendmsg(descriptor, &message, MSG_NOSIGNAL) !=
      static_cast<ssize_t>(payload.size())) {
    throw std::runtime_error("sendmsg failed");
  }
}

ReceivedPacket receive_packet(int descriptor, std::size_t maximum_payload,
                              std::size_t maximum_descriptors) {
  if (maximum_descriptors > kMaximumPassedDescriptors || maximum_payload == 0) {
    throw std::invalid_argument("invalid receive fixture bounds");
  }
  ReceivedPacket output;
  output.payload.resize(maximum_payload);
  iovec vector{.iov_base = output.payload.data(),
               .iov_len = output.payload.size()};
  alignas(cmsghdr)
      std::array<std::byte,
                 CMSG_SPACE(sizeof(ucred)) +
                     CMSG_SPACE(kMaximumPassedDescriptors * sizeof(int))>
          control{};
  msghdr message{};
  message.msg_iov = &vector;
  message.msg_iovlen = 1;
  message.msg_control = control.data();
  message.msg_controllen = control.size();
  const ssize_t received =
      recvmsg(descriptor, &message, MSG_CMSG_CLOEXEC | MSG_TRUNC);
  if (received < 0) {
    throw std::runtime_error("recvmsg failed");
  }
  output.truncated = (message.msg_flags & (MSG_TRUNC | MSG_CTRUNC)) != 0 ||
                     static_cast<std::size_t>(received) > maximum_payload;
  output.payload.resize(std::min<std::size_t>(
      static_cast<std::size_t>(received), maximum_payload));

  for (cmsghdr *header = CMSG_FIRSTHDR(&message); header != nullptr;
       header = CMSG_NXTHDR(&message, header)) {
    if (header->cmsg_level != SOL_SOCKET) {
      output.ancillary_invalid = true;
      continue;
    }
    if (header->cmsg_type == SCM_CREDENTIALS) {
      if (header->cmsg_len != CMSG_LEN(sizeof(ucred)) ||
          output.has_credentials) {
        output.ancillary_invalid = true;
        continue;
      }
      std::memcpy(&output.credentials, CMSG_DATA(header), sizeof(ucred));
      output.has_credentials = true;
      continue;
    }
    if (header->cmsg_type == SCM_RIGHTS) {
      if (header->cmsg_len < CMSG_LEN(0) ||
          (header->cmsg_len - CMSG_LEN(0)) % sizeof(int) != 0) {
        output.ancillary_invalid = true;
        continue;
      }
      const std::size_t count = (header->cmsg_len - CMSG_LEN(0)) / sizeof(int);
      const auto *values = reinterpret_cast<const int *>(CMSG_DATA(header));
      for (std::size_t index = 0; index < count; ++index) {
        UniqueFd received_fd(values[index]);
        if (output.descriptors.size() < maximum_descriptors) {
          output.descriptors.push_back(std::move(received_fd));
        } else {
          output.ancillary_invalid = true;
        }
      }
      continue;
    }
    output.ancillary_invalid = true;
  }
  return output;
}

UniqueFd open_pidfd(pid_t process) {
  return UniqueFd(static_cast<int>(syscall(SYS_pidfd_open, process, 0)));
}

PidfdState pidfd_state(int descriptor) {
  pollfd polled{.fd = descriptor, .events = POLLIN, .revents = 0};
  const int result = poll(&polled, 1, 0);
  if (result == 0) {
    return PidfdState::alive;
  }
  if (result == 1 && polled.revents == POLLIN) {
    return PidfdState::exited;
  }
  return PidfdState::unusable;
}

bool wait_pidfd_exit(int descriptor, int timeout_milliseconds) {
  if (timeout_milliseconds < 0) {
    return false;
  }
  pollfd polled{.fd = descriptor, .events = POLLIN, .revents = 0};
  return poll(&polled, 1, timeout_milliseconds) == 1 &&
         polled.revents == POLLIN;
}

bool bounded_reap(pid_t process, int pidfd, int timeout_milliseconds,
                  int *status_output) {
  if (timeout_milliseconds < 0) {
    return false;
  }
  if (!wait_pidfd_exit(pidfd, timeout_milliseconds)) {
    static_cast<void>(
        syscall(SYS_pidfd_send_signal, pidfd, SIGKILL, nullptr, 0));
    if (!wait_pidfd_exit(pidfd, timeout_milliseconds)) {
      return false;
    }
  }
  int status = 0;
  if (waitpid(process, &status, WNOHANG) != process) {
    return false;
  }
  if (status_output != nullptr) {
    *status_output = status;
  }
  return true;
}

SyntheticResourceTree::SyntheticResourceTree() {
  std::array<char, 64> pattern{};
  std::strcpy(pattern.data(), "/tmp/omarchy-plugin-fixture.XXXXXX");
  char *created = mkdtemp(pattern.data());
  if (created == nullptr) {
    throw std::runtime_error("cannot create synthetic resource tree");
  }
  root_ = created;
  std::filesystem::create_directories(revision());
  std::filesystem::create_directories(private_state());
  std::filesystem::create_directories(synthetic_home());
  std::ofstream(revision() / "plugin.qml") << "import QtQml\nQtObject {}\n";
  std::ofstream(sentinel()) << "must-not-cross-sandbox\n";
}

SyntheticResourceTree::~SyntheticResourceTree() {
  std::error_code error;
  std::filesystem::remove_all(root_, error);
}

const std::filesystem::path &SyntheticResourceTree::root() const {
  return root_;
}

std::filesystem::path SyntheticResourceTree::revision() const {
  return root_ / "revision";
}

std::filesystem::path SyntheticResourceTree::private_state() const {
  return root_ / "state";
}

std::filesystem::path SyntheticResourceTree::synthetic_home() const {
  return root_ / "home";
}

std::filesystem::path SyntheticResourceTree::sentinel() const {
  return synthetic_home() / "host-secret";
}

} // namespace omarchy::plugin_runtime::test_support
