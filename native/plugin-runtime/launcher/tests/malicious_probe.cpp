#include <fcntl.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <unistd.h>

#include <array>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <vector>

namespace {
struct Claim {
  std::uint32_t magic;
  std::int32_t claimed_pid;
};

struct DescriptorReport {
  std::uint32_t count;
  std::uint32_t close_on_exec;
};

[[noreturn]] void fail(int code) { _exit(code); }

void transmit(int descriptor, Claim claim) {
  if (send(descriptor, &claim, sizeof(claim), MSG_NOSIGNAL) != sizeof(claim)) {
    fail(110);
  }
}

void receive_one_descriptor(int descriptor) {
  std::byte payload{};
  iovec vector{.iov_base = &payload, .iov_len = 1};
  alignas(cmsghdr) std::array<std::byte, CMSG_SPACE(sizeof(int))> control{};
  msghdr message{};
  message.msg_iov = &vector;
  message.msg_iovlen = 1;
  message.msg_control = control.data();
  message.msg_controllen = control.size();
  if (recvmsg(descriptor, &message, MSG_CMSG_CLOEXEC) != 1 ||
      (message.msg_flags & (MSG_TRUNC | MSG_CTRUNC)) != 0) {
    fail(115);
  }
  std::uint32_t count = 0;
  std::uint32_t close_on_exec = 0;
  for (cmsghdr *header = CMSG_FIRSTHDR(&message); header != nullptr;
       header = CMSG_NXTHDR(&message, header)) {
    if (header->cmsg_level != SOL_SOCKET || header->cmsg_type != SCM_RIGHTS ||
        header->cmsg_len != CMSG_LEN(sizeof(int))) {
      fail(116);
    }
    int received = -1;
    std::memcpy(&received, CMSG_DATA(header), sizeof(received));
    ++count;
    close_on_exec = fcntl(received, F_GETFD) == FD_CLOEXEC ? 1U : 0U;
    close(received);
  }
  const DescriptorReport report{.count = count, .close_on_exec = close_on_exec};
  if (send(5, &report, sizeof(report), MSG_NOSIGNAL) != sizeof(report))
    fail(117);
}
} // namespace

int main() {
  for (const int descriptor : {3, 4, 5}) {
    if (fcntl(descriptor, F_SETFD, FD_CLOEXEC) < 0) {
      fail(111);
    }
  }
  transmit(3, {.magic = 0x43575037,
               .claimed_pid = static_cast<std::int32_t>(getpid())});
  const pid_t descendant = fork();
  if (descendant < 0) {
    fail(112);
  }
  if (descendant == 0) {
    transmit(4, {.magic = 0x43575037,
                 .claimed_pid = static_cast<std::int32_t>(getppid())});
    _exit(0);
  }
  int status = 0;
  if (waitpid(descendant, &status, 0) != descendant || !WIFEXITED(status) ||
      WEXITSTATUS(status) != 0) {
    fail(113);
  }
  std::vector<std::byte> maximum_broker_datagram(40 + 65536, std::byte{0x4b});
  if (send(4, maximum_broker_datagram.data(), maximum_broker_datagram.size(),
           MSG_NOSIGNAL) !=
      static_cast<ssize_t>(maximum_broker_datagram.size()))
    fail(118);
  transmit(5, {.magic = 0x43575037,
               .claimed_pid = static_cast<std::int32_t>(getpid())});
  std::byte acknowledgement{};
  if (recv(3, &acknowledgement, sizeof(acknowledgement), 0) != 1) {
    fail(114);
  }
  receive_one_descriptor(3);
  return 0;
}
