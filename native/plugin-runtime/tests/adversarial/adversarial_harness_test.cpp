#include "omarchy/plugin/wire/envelope.hpp"
#include "omarchy/plugin/wire/state.hpp"

#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <sys/socket.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

#include <array>
#include <cerrno>
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <stdexcept>
#include <string>
#include <string_view>
#include <thread>
#include <utility>
#include <vector>

namespace {

namespace wire = omarchy::plugin::wire;

constexpr std::uint64_t kGeneration = 0x1020304050607080ULL;

void require(bool condition, std::string_view message) {
  if (!condition) {
    throw std::runtime_error(std::string(message));
  }
}

struct Received {
  std::vector<std::byte> payload;
  ucred credentials{};
  std::vector<int> descriptors;
  bool has_credentials = false;

  Received() = default;
  Received(const Received &) = delete;
  Received &operator=(const Received &) = delete;
  Received(Received &&other) noexcept
      : payload(std::move(other.payload)), credentials(other.credentials),
        descriptors(std::move(other.descriptors)),
        has_credentials(other.has_credentials) {
    other.descriptors.clear();
  }

  ~Received() {
    for (const int descriptor : descriptors) {
      close(descriptor);
    }
  }
};

struct Worker {
  int channel = -1;
  pid_t pid = -1;
  int pidfd = -1;

  Worker() = default;
  Worker(const Worker &) = delete;
  Worker &operator=(const Worker &) = delete;
  Worker(Worker &&other) noexcept
      : channel(std::exchange(other.channel, -1)),
        pid(std::exchange(other.pid, -1)),
        pidfd(std::exchange(other.pidfd, -1)) {}
  ~Worker() {
    if (channel >= 0) {
      close(channel);
    }
    if (pidfd >= 0) {
      close(pidfd);
    }
    if (pid > 0) {
      kill(pid, SIGKILL);
      waitpid(pid, nullptr, 0);
    }
  }
};

Worker spawn(std::string_view attack) {
  std::array<int, 2> pair{};
  require(socketpair(AF_UNIX, SOCK_SEQPACKET | SOCK_CLOEXEC, 0, pair.data()) ==
              0,
          "attack channel creation failed");
  int enabled = 1;
  require(setsockopt(pair[0], SOL_SOCKET, SO_PASSCRED, &enabled,
                     sizeof(enabled)) == 0,
          "attack channel credential setup failed");
  const pid_t child = fork();
  require(child >= 0, "malicious worker fork failed");
  if (child == 0) {
    close(pair[0]);
    const int staged = fcntl(pair[1], F_DUPFD_CLOEXEC, 32);
    if (staged < 0 || dup2(staged, 3) < 0) {
      _exit(120);
    }
    close(staged);
    close(pair[1]);
    static_cast<void>(syscall(SYS_close_range, 4U, ~0U, 0U));
    const std::string argument(attack);
    execl(MALICIOUS_WORKER_PATH, MALICIOUS_WORKER_PATH, argument.c_str(),
          nullptr);
    _exit(121);
  }
  close(pair[1]);
  Worker worker;
  worker.channel = pair[0];
  worker.pid = child;
  worker.pidfd = static_cast<int>(syscall(SYS_pidfd_open, child, 0));
  require(worker.pidfd >= 0, "malicious worker pidfd acquisition failed");
  return worker;
}

Received receive(Worker &worker) {
  pollfd ready{.fd = worker.channel, .events = POLLIN, .revents = 0};
  require(poll(&ready, 1, 2000) == 1 && (ready.revents & POLLIN) != 0,
          "malicious worker did not produce its attack");
  std::array<std::byte, 8192> payload{};
  std::array<std::byte, CMSG_SPACE(sizeof(ucred)) + CMSG_SPACE(sizeof(int) * 4)>
      ancillary{};
  iovec data{.iov_base = payload.data(), .iov_len = payload.size()};
  msghdr message{};
  message.msg_iov = &data;
  message.msg_iovlen = 1;
  message.msg_control = ancillary.data();
  message.msg_controllen = ancillary.size();
  const ssize_t size = recvmsg(worker.channel, &message, MSG_CMSG_CLOEXEC);
  require(size >= 0 && (message.msg_flags & (MSG_TRUNC | MSG_CTRUNC)) == 0,
          "attack receive was truncated");
  Received received;
  received.payload.assign(payload.begin(), payload.begin() + size);
  for (cmsghdr *header = CMSG_FIRSTHDR(&message); header != nullptr;
       header = CMSG_NXTHDR(&message, header)) {
    if (header->cmsg_level != SOL_SOCKET) {
      continue;
    }
    if (header->cmsg_type == SCM_CREDENTIALS &&
        header->cmsg_len == CMSG_LEN(sizeof(ucred))) {
      std::memcpy(&received.credentials, CMSG_DATA(header), sizeof(ucred));
      received.has_credentials = true;
    } else if (header->cmsg_type == SCM_RIGHTS &&
               header->cmsg_len >= CMSG_LEN(sizeof(int))) {
      const auto count = (header->cmsg_len - CMSG_LEN(0)) / sizeof(int);
      const auto *descriptors = reinterpret_cast<const int *>(CMSG_DATA(header));
      received.descriptors.insert(received.descriptors.end(), descriptors,
                                  descriptors + count);
    }
  }
  return received;
}

int finish(Worker &worker, int timeout_ms = 2000) {
  pollfd ready{.fd = worker.pidfd, .events = POLLIN, .revents = 0};
  require(poll(&ready, 1, timeout_ms) == 1 && (ready.revents & POLLIN) != 0,
          "malicious worker exceeded its exit bound");
  int status = 0;
  require(waitpid(worker.pid, &status, 0) == worker.pid,
          "malicious worker could not be reaped");
  worker.pid = -1;
  return status;
}

void test_protocol_attacks() {
  {
    auto worker = spawn("role-swap");
    auto received = receive(worker);
    require(received.has_credentials && received.credentials.pid == worker.pid,
            "role-swap attack lacked bound credentials");
    const auto decoded =
        wire::decode_packet(received.payload, wire::EndpointRole::control);
    require(!decoded && decoded.error == wire::FatalReason::endpoint_role_mismatch,
            "role substitution was not a fatal envelope error");
    require(WIFEXITED(finish(worker)), "role-swap worker did not exit cleanly");
  }
  {
    auto worker = spawn("stale-generation");
    auto received = receive(worker);
    const auto decoded =
        wire::decode_packet(received.payload, wire::EndpointRole::control);
    require(static_cast<bool>(decoded), "stale-generation attack was malformed");
    const std::array<wire::MessageRule, 1> rules{{
        {.message_type = 0x1100,
         .directions = wire::DirectionMask::worker_to_host,
         .correlation = wire::CorrelationRule::nonzero,
         .semantic = wire::MessageSemantic::request,
         .minimum_payload = 0,
         .maximum_payload = 64},
    }};
    const std::array<wire::RoleSchemaView, 1> schemas{{
        {.role = wire::EndpointRole::control,
         .version = 1,
         .messages = rules,
         .typed_error_minimum_payload = 2,
         .typed_error_maximum_payload = 64},
    }};
    const wire::RoleSchemaRegistryView registry(schemas);
    wire::SelectedEndpointState<4> selected(wire::EndpointRole::control, 1,
                                            kGeneration, 4096, 4, registry);
    const auto result =
        selected.accept(decoded.packet, wire::Direction::worker_to_host);
    require(!result && result.error == wire::FatalReason::stale_generation,
            "stale generation passed selected endpoint authentication");
    require(WIFEXITED(finish(worker)),
            "stale-generation worker did not exit cleanly");
  }
  {
    auto worker = spawn("oversized");
    auto received = receive(worker);
    const auto decoded =
        wire::decode_packet(received.payload, wire::EndpointRole::control);
    require(!decoded && decoded.error == wire::FatalReason::payload_cap_exceeded,
            "oversized control claim was not rejected at its endpoint cap");
    require(WIFEXITED(finish(worker)), "oversized worker did not exit cleanly");
  }
}

void test_identity_and_descriptor_attacks() {
  {
    auto worker = spawn("descriptor-injection");
    auto received = receive(worker);
    require(received.has_credentials && received.credentials.pid == worker.pid &&
                received.descriptors.size() == 1,
            "descriptor injection corpus did not carry exact hostile state");
    const auto decoded =
        wire::decode_packet(received.payload, wire::EndpointRole::control);
    require(static_cast<bool>(decoded),
            "descriptor denial was confounded by a malformed envelope");
    require(WIFEXITED(finish(worker)),
            "descriptor-injection worker did not exit cleanly");
  }
  {
    auto worker = spawn("descendant");
    auto received = receive(worker);
    require(received.has_credentials && received.credentials.pid != worker.pid &&
                received.credentials.uid == getuid() &&
                received.credentials.gid == getgid(),
            "descendant attack did not prove peer-credential substitution");
    const auto decoded =
        wire::decode_packet(received.payload, wire::EndpointRole::control);
    require(static_cast<bool>(decoded),
            "descendant denial was confounded by a malformed envelope");
    require(WIFEXITED(finish(worker)),
            "descendant worker did not exit cleanly");
  }
}

void test_failure_bounds() {
  {
    auto worker = spawn("crash");
    const int status = finish(worker);
    require(WIFSIGNALED(status) && WTERMSIG(status) == SIGABRT,
            "crashing worker did not produce the frozen failure signal");
  }
  {
    auto worker = spawn("hang");
    pollfd ready{.fd = worker.pidfd, .events = POLLIN, .revents = 0};
    require(poll(&ready, 1, 50) == 0,
            "hanging worker unexpectedly terminated before teardown");
    require(kill(worker.pid, SIGKILL) == 0, "hanging worker kill failed");
    const int status = finish(worker);
    require(WIFSIGNALED(status) && WTERMSIG(status) == SIGKILL,
            "hanging worker escaped bounded teardown");
  }
}

} // namespace

int main() {
  try {
    test_protocol_attacks();
    test_identity_and_descriptor_attacks();
    test_failure_bounds();
  } catch (const std::exception &error) {
    dprintf(STDERR_FILENO, "%s\n", error.what());
    return 1;
  }
  return 0;
}
