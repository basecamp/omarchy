#include <fcntl.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <unistd.h>

#include <array>
#include <cstddef>
#include <cstdint>

namespace {
struct Claim {
  std::uint32_t magic;
  std::int32_t claimed_pid;
};

[[noreturn]] void fail(int code) { _exit(code); }

void transmit(int descriptor, Claim claim) {
  if (send(descriptor, &claim, sizeof(claim), MSG_NOSIGNAL) != sizeof(claim)) {
    fail(110);
  }
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
  transmit(5, {.magic = 0x43575037,
               .claimed_pid = static_cast<std::int32_t>(getpid())});
  std::byte acknowledgement{};
  if (recv(3, &acknowledgement, sizeof(acknowledgement), 0) != 1) {
    fail(114);
  }
  return 0;
}
