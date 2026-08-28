#include <arpa/inet.h>
#include <atomic>
#include <dirent.h>
#include <fcntl.h>
#include <sched.h>
#include <sys/socket.h>
#include <unistd.h>

#include <cerrno>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <iostream>
#include <set>
#include <string>
#include <string_view>
#include <thread>

extern char **environ;

namespace {
[[noreturn]] void fail(std::string_view message) {
  std::cerr << "sandbox probe: " << message << " errno=" << errno << " ("
            << std::strerror(errno) << ")\n";
  std::exit(1);
}

void require(bool condition, std::string_view message) {
  if (!condition) {
    fail(message);
  }
}

void verify_environment() {
  const std::set<std::string> expected = {
      "HOME=/home/plugin",
      "LANG=C.UTF-8",
      "LC_ALL=C.UTF-8",
      "PATH=/runtime",
      "PWD=/plugin",
      "QT_QPA_PLATFORM=offscreen",
      "QSG_RHI_BACKEND=software",
      "XDG_CACHE_HOME=/tmp/cache",
      "XDG_CONFIG_HOME=/state/config",
      "XDG_DATA_HOME=/state/data",
      "XDG_RUNTIME_DIR=/run/plugin",
  };
  std::set<std::string> actual;
  for (char **entry = environ; *entry != nullptr; ++entry) {
    actual.emplace(*entry);
  }
  require(actual == expected, "worker environment differs from the allowlist");
}

void verify_descriptors() {
  DIR *directory = opendir("/proc/self/fd");
  require(directory != nullptr, "cannot enumerate descriptors");
  const int enumeration_fd = dirfd(directory);
  std::set<int> descriptors;
  while (const dirent *entry = readdir(directory)) {
    char *end = nullptr;
    const long value = std::strtol(entry->d_name, &end, 10);
    if (*entry->d_name != '\0' && end != nullptr && *end == '\0' &&
        value != enumeration_fd) {
      descriptors.insert(static_cast<int>(value));
    }
  }
  closedir(directory);
  require(descriptors == std::set<int>({0, 1, 2, 3, 4, 5}),
          "worker received a non-allowlisted descriptor");
}

void require_file(std::string_view path, std::string_view expected) {
  std::ifstream stream{std::string(path)};
  std::string value;
  std::getline(stream, value);
  require(stream.good() || stream.eof(), "cannot read expected fixture");
  require(value == expected, "fixture content mismatch");
}

void require_create(std::string_view path) {
  const int descriptor = open(std::string(path).c_str(),
                              O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0600);
  require(descriptor >= 0, "writable private mount rejected a file");
  require(write(descriptor, "ok", 2) == 2, "private file write failed");
  close(descriptor);
}
} // namespace

int main() {
  verify_environment();
  verify_descriptors();
  require(getpid() == 1 && getuid() == 0 && getgid() == 0,
          "worker namespace identity changed");

  char hostname[64] = {};
  require(gethostname(hostname, sizeof(hostname)) == 0 &&
              std::string_view(hostname) == "omarchy-plugin",
          "worker hostname is not fixed");
  char working_directory[256] = {};
  require(getcwd(working_directory, sizeof(working_directory)) != nullptr &&
              std::string_view(working_directory) == "/plugin",
          "worker did not start in the immutable revision");

  require_file("/plugin/fixture", "revision");
  errno = 0;
  const int revision_write =
      open("/plugin/forbidden", O_WRONLY | O_CREAT | O_CLOEXEC, 0600);
  require(revision_write < 0 && (errno == EROFS || errno == EACCES),
          "immutable revision accepted a write");
  require_create("/state/persisted");
  require_create("/tmp/scratch");

  require(access("/home/plugin/host-secret", F_OK) < 0 && errno == ENOENT,
          "host home leaked into sandbox");
  require(access("/run/user/1000/bus", F_OK) < 0 && errno == ENOENT,
          "host user bus leaked into sandbox");
  require(access("/dev/dri/renderD128", F_OK) < 0 && errno == ENOENT,
          "GPU device leaked into sandbox");
  require(access("/dev/input/event0", F_OK) < 0 && errno == ENOENT,
          "input device leaked into sandbox");
  require(access("/usr/bin/sh", F_OK) < 0 && errno == ENOENT,
          "host executables leaked into sandbox");

  std::atomic<bool> thread_ran = false;
  std::thread thread([&thread_ran]() { thread_ran.store(true); });
  thread.join();
  require(thread_ran.load(), "seccomp rejected an ordinary worker thread");
  errno = 0;
  require(fork() < 0 && errno == EPERM,
          "seccomp allowed an unsupervised child process");

  errno = 0;
  const int network = socket(AF_INET, SOCK_STREAM | SOCK_CLOEXEC, 0);
  require(network < 0 && errno == EPERM,
          "seccomp allowed creation of a network socket");
  errno = 0;
  require(unshare(CLONE_NEWUSER) < 0 && errno == EPERM,
          "nested user namespace was allowed");

  std::ifstream status("/proc/self/status");
  std::string line;
  bool zero_capabilities = false;
  while (std::getline(status, line)) {
    if (line == "CapEff:\t0000000000000000") {
      zero_capabilities = true;
    }
  }
  require(zero_capabilities, "effective capabilities are not empty");
  return 0;
}
