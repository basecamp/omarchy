#include <fcntl.h>
#include <signal.h>
#include <sched.h>
#include <sys/socket.h>
#include <unistd.h>

#include <cerrno>
#include <cstdio>
#include <fstream>
#include <string>

namespace {

bool descriptor_closed(int descriptor) {
  errno = 0;
  return fcntl(descriptor, F_GETFD) < 0 && errno == EBADF;
}

bool cannot_open(std::string_view path) {
  const std::string owned(path);
  const int descriptor = open(owned.c_str(), O_RDONLY | O_CLOEXEC);
  if (descriptor >= 0)
    close(descriptor);
  return descriptor < 0;
}

} // namespace

int main(int argc, char **argv) {
  if (argc != 2)
    return 2;
  const bool descriptors_closed = descriptor_closed(3) &&
                                  descriptor_closed(4) &&
                                  descriptor_closed(5);
  const bool role_fds_unreachable =
      cannot_open("/proc/1/fd/3") && cannot_open("/proc/1/fd/4") &&
      cannot_open("/proc/1/fd/5");
  const bool host_paths_absent = cannot_open("/etc/passwd") &&
                                 cannot_open("/home/plugin/.host-canary");
  const bool session_authority_absent = getenv("DBUS_SESSION_BUS_ADDRESS") == nullptr &&
                                        getenv("WAYLAND_DISPLAY") == nullptr;
  errno = 0;
  const bool namespace_creation_denied =
      unshare(CLONE_NEWNS | CLONE_NEWUSER) < 0;
  const std::string temporary = std::string(argv[1]) + ".tmp";
  std::ofstream output(temporary, std::ios::binary | std::ios::trunc);
  output << getpid() << ' ' << (descriptors_closed ? "closed" : "open")
         << ' ' << (role_fds_unreachable ? "fds-denied" : "fds-reopened")
         << ' ' << (host_paths_absent ? "host-denied" : "host-visible")
         << ' '
         << (session_authority_absent ? "session-denied" : "session-visible")
         << ' '
         << (namespace_creation_denied ? "namespace-denied"
                                       : "namespace-created")
         << '\n';
  output.close();
  if (!output || rename(temporary.c_str(), argv[1]) < 0)
    return 3;
  for (;;)
    pause();
}
