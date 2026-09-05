#include <dirent.h>
#include <fcntl.h>
#include <sys/prctl.h>
#include <sys/resource.h>
#include <sys/socket.h>
#include <unistd.h>

#include <array>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <set>

namespace {
struct Probe {
  std::uint32_t magic;
  std::int32_t pid;
  std::uint32_t uid;
  std::uint32_t gid;
  std::uint32_t descriptor_mask;
  std::uint32_t no_new_privileges;
  std::uint64_t open_files_max;
  std::uint64_t file_size_max;
  std::uint64_t core_size_max;
};

[[noreturn]] void fail(int code) { _exit(code); }

std::uint32_t descriptor_mask() {
  DIR *directory = opendir("/proc/self/fd");
  if (directory == nullptr) {
    fail(100);
  }
  const int enumeration_fd = dirfd(directory);
  std::uint32_t mask = 0;
  while (const dirent *entry = readdir(directory)) {
    char *end = nullptr;
    const long descriptor = std::strtol(entry->d_name, &end, 10);
    if (end != nullptr && *end == '\0' && descriptor >= 0 && descriptor < 32 &&
        descriptor != enumeration_fd) {
      mask |= 1U << descriptor;
    }
  }
  closedir(directory);
  return mask;
}

void inject_descriptor() {
  const int injected = open("/dev/null", O_RDONLY | O_CLOEXEC);
  if (injected < 0) {
    fail(103);
  }
  const std::byte payload{0x44};
  iovec vector{.iov_base = const_cast<std::byte *>(&payload), .iov_len = 1};
  alignas(cmsghdr) std::array<std::byte, CMSG_SPACE(sizeof(int))> control{};
  msghdr message{};
  message.msg_iov = &vector;
  message.msg_iovlen = 1;
  message.msg_control = control.data();
  message.msg_controllen = control.size();
  cmsghdr *header = CMSG_FIRSTHDR(&message);
  header->cmsg_level = SOL_SOCKET;
  header->cmsg_type = SCM_RIGHTS;
  header->cmsg_len = CMSG_LEN(sizeof(int));
  *reinterpret_cast<int *>(CMSG_DATA(header)) = injected;
  if (sendmsg(4, &message, MSG_NOSIGNAL) != 1) {
    close(injected);
    fail(104);
  }
  close(injected);
}

void inject_many_descriptors() {
  std::array<int, 24> injected{};
  for (int &descriptor : injected) {
    descriptor = open("/dev/null", O_RDONLY | O_CLOEXEC);
    if (descriptor < 0)
      fail(107);
  }
  const std::byte payload{0x55};
  iovec vector{.iov_base = const_cast<std::byte *>(&payload), .iov_len = 1};
  alignas(cmsghdr)
      std::array<std::byte, CMSG_SPACE(sizeof(int) * injected.size())>
          control{};
  msghdr message{};
  message.msg_iov = &vector;
  message.msg_iovlen = 1;
  message.msg_control = control.data();
  message.msg_controllen = control.size();
  cmsghdr *header = CMSG_FIRSTHDR(&message);
  header->cmsg_level = SOL_SOCKET;
  header->cmsg_type = SCM_RIGHTS;
  header->cmsg_len = CMSG_LEN(sizeof(int) * injected.size());
  std::memcpy(CMSG_DATA(header), injected.data(), sizeof(injected));
  if (sendmsg(5, &message, MSG_NOSIGNAL) != 1)
    fail(108);
  for (const int descriptor : injected)
    close(descriptor);
}
} // namespace

int main() {
  for (const int descriptor : {3, 4, 5}) {
    if (fcntl(descriptor, F_SETFD, FD_CLOEXEC) < 0) {
      fail(101);
    }
  }
  rlimit open_files{};
  rlimit file_size{};
  rlimit core_size{};
  if (getrlimit(RLIMIT_NOFILE, &open_files) < 0 ||
      getrlimit(RLIMIT_FSIZE, &file_size) < 0 ||
      getrlimit(RLIMIT_CORE, &core_size) < 0) {
    fail(106);
  }
  const Probe probe{.magic = 0x43575037,
                    .pid = static_cast<std::int32_t>(getpid()),
                    .uid = getuid(),
                    .gid = getgid(),
                    .descriptor_mask = descriptor_mask(),
                    .no_new_privileges = static_cast<std::uint32_t>(
                        prctl(PR_GET_NO_NEW_PRIVS, 0, 0, 0, 0)),
                    .open_files_max = open_files.rlim_cur,
                    .file_size_max = file_size.rlim_cur,
                    .core_size_max = core_size.rlim_cur};
  if (send(3, &probe, sizeof(probe), MSG_NOSIGNAL) != sizeof(probe)) {
    fail(102);
  }
  inject_descriptor();
  inject_many_descriptors();
  std::byte acknowledgement{};
  if (recv(3, &acknowledgement, sizeof(acknowledgement), 0) != 1) {
    fail(105);
  }
  return 0;
}
