#include <dirent.h>
#include <fcntl.h>
#include <json-c/json.h>
#include <poll.h>
#include <signal.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

#include <array>
#include <cerrno>
#include <charconv>
#include <chrono>
#include <cstdint>
#include <cstring>
#include <iostream>
#include <limits>
#include <optional>
#include <stdexcept>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace {

constexpr std::uint32_t kMagic = 0x4944454e;
constexpr int kControlFd = 3;
constexpr int kBrokerFd = 4;
constexpr int kRenderFd = 5;
constexpr int kStatusFd = 20;
constexpr int kBarrierFd = 21;
constexpr int kTimeoutMs = 5000;
constexpr std::size_t kMaximumLine = 4096;
constexpr std::size_t kMaximumRecords = 32;
using Clock = std::chrono::steady_clock;

enum class Role : std::uint16_t { control = 1, broker = 2, render = 3 };
enum class Kind : std::uint16_t {
  identity = 1,
  control_ready = 2,
  broker_request = 3,
  render_frame = 4,
};

struct Payload {
  std::uint32_t magic;
  Role role;
  Kind kind;
  pid_t inner_pid;
  uid_t inner_uid;
  gid_t inner_gid;
  std::uint32_t unexpected_fds;
  std::uint32_t standard_fd_aliases;
};

struct Received {
  Payload payload;
  ucred credentials;
  bool accepted;
};

struct StatusRecord {
  std::optional<pid_t> child_pid;
  std::optional<int> exit_code;
};

void require(bool condition, std::string_view message) {
  if (!condition) {
    throw std::runtime_error(std::string(message));
  }
}

void close_checked(int fd) {
  if (fd >= 0 && close(fd) < 0) {
    throw std::runtime_error(std::string("close failed: ") +
                             std::strerror(errno));
  }
}

void set_cloexec(int fd, bool enabled) {
  const int flags = fcntl(fd, F_GETFD);
  require(flags >= 0, "F_GETFD failed");
  require(fcntl(fd, F_SETFD,
                enabled ? flags | FD_CLOEXEC : flags & ~FD_CLOEXEC) == 0,
          "F_SETFD failed");
}

void normalize_standard_fds() {
  for (int fd = STDIN_FILENO; fd <= STDERR_FILENO; ++fd) {
    errno = 0;
    if (fcntl(fd, F_GETFD) >= 0) {
      continue;
    }
    require(errno == EBADF, "cannot inspect standard descriptor");
    const int flags = fd == STDIN_FILENO ? O_RDONLY : O_WRONLY;
    const int replacement = open("/dev/null", flags | O_CLOEXEC);
    require(replacement >= 0, "cannot normalize standard descriptor");
    if (replacement != fd) {
      require(dup2(replacement, fd) == fd,
              "cannot assign normalized standard descriptor");
      close_checked(replacement);
    }
    set_cloexec(fd, false);
  }
}

void relocate(const std::array<std::pair<int, int>, 5> &items) {
  std::array<int, 5> copies{};
  copies.fill(-1);
  try {
    for (std::size_t index = 0; index < items.size(); ++index) {
      copies[index] = fcntl(items[index].first, F_DUPFD_CLOEXEC, 64);
      require(copies[index] >= 0, "descriptor staging failed");
    }
    for (const auto &[source, destination] : items) {
      (void)destination;
      bool source_is_destination = false;
      for (const auto &[other_source, other_destination] : items) {
        (void)other_source;
        source_is_destination =
            source_is_destination || source == other_destination;
      }
      if (!source_is_destination) {
        close_checked(source);
      }
    }
    for (std::size_t index = 0; index < items.size(); ++index) {
      require(dup2(copies[index], items[index].second) >= 0,
              "descriptor relocation failed");
      set_cloexec(items[index].second, false);
    }
  } catch (...) {
    for (const int fd : copies) {
      if (fd >= 0) {
        close(fd);
      }
    }
    throw;
  }
  for (const int fd : copies) {
    close_checked(fd);
  }
}

void close_unlisted() {
  require(syscall(SYS_close_range, 6U, 19U, 0U) == 0 &&
              syscall(SYS_close_range, 22U,
                      std::numeric_limits<unsigned int>::max(), 0U) == 0,
          "close_range failed");
}

std::string executable_path() {
  std::array<char, 4096> path{};
  const auto length = readlink("/proc/self/exe", path.data(), path.size() - 1);
  require(length > 0 && static_cast<std::size_t>(length) < path.size() - 1,
          "cannot resolve executable path");
  return std::string(path.data(), static_cast<std::size_t>(length));
}

bool decoded_json_key_equals(std::string_view encoded, std::string_view key) {
  std::string quoted;
  quoted.reserve(encoded.size() + 2);
  quoted.push_back('"');
  quoted.append(encoded);
  quoted.push_back('"');
  json_object *decoded = json_tokener_parse(quoted.c_str());
  if (decoded == nullptr || !json_object_is_type(decoded, json_type_string)) {
    if (decoded != nullptr) {
      json_object_put(decoded);
    }
    return false;
  }
  const bool equal =
      json_object_get_string_len(decoded) == static_cast<int>(key.size()) &&
      std::string_view(json_object_get_string(decoded), key.size()) == key;
  json_object_put(decoded);
  return equal;
}

std::size_t count_top_level_key(std::string_view json, std::string_view key) {
  std::size_t count = 0;
  int depth = 0;
  bool in_string = false;
  bool escaped = false;
  std::size_t string_begin = 0;
  for (std::size_t index = 0; index < json.size(); ++index) {
    const char character = json[index];
    if (in_string) {
      if (escaped) {
        escaped = false;
      } else if (character == '\\') {
        escaped = true;
      } else if (character == '"') {
        in_string = false;
        std::size_t after = index + 1;
        while (after < json.size() &&
               (json[after] == ' ' || json[after] == '\t' ||
                json[after] == '\r')) {
          ++after;
        }
        if (depth == 1 && after < json.size() && json[after] == ':' &&
            decoded_json_key_equals(
                json.substr(string_begin, index - string_begin), key)) {
          ++count;
        }
      }
      continue;
    }
    if (character == '"') {
      in_string = true;
      escaped = false;
      string_begin = index + 1;
    } else if (character == '{' || character == '[') {
      ++depth;
    } else if (character == '}' || character == ']') {
      --depth;
    }
  }
  return count;
}

StatusRecord parse_status(std::string_view line) {
  require(count_top_level_key(line, "child-pid") <= 1,
          "duplicate bwrap child-pid field");
  require(count_top_level_key(line, "exit-code") <= 1,
          "duplicate bwrap exit-code field");
  json_tokener *tokener = json_tokener_new_ex(16);
  require(tokener != nullptr, "cannot allocate JSON parser");
  json_tokener_set_flags(tokener, JSON_TOKENER_STRICT);
  json_object *root = json_tokener_parse_ex(tokener, line.data(),
                                            static_cast<int>(line.size()));
  const auto error = json_tokener_get_error(tokener);
  const int consumed = tokener->char_offset;
  json_tokener_free(tokener);
  require(error == json_tokener_success && root != nullptr &&
              consumed == static_cast<int>(line.size()) &&
              json_object_is_type(root, json_type_object),
          "invalid bwrap JSON status record");

  StatusRecord result;
  json_object *value = nullptr;
  if (json_object_object_get_ex(root, "child-pid", &value)) {
    require(json_object_is_type(value, json_type_int),
            "bwrap child-pid is not an integer");
    const auto number = json_object_get_int64(value);
    require(number > 0 && number <= std::numeric_limits<pid_t>::max(),
            "invalid bwrap child-pid");
    result.child_pid = static_cast<pid_t>(number);
  }
  if (json_object_object_get_ex(root, "exit-code", &value)) {
    require(json_object_is_type(value, json_type_int),
            "bwrap exit-code is not an integer");
    const auto number = json_object_get_int64(value);
    require(number >= 0 && number <= std::numeric_limits<int>::max(),
            "invalid bwrap exit-code");
    result.exit_code = static_cast<int>(number);
  }
  json_object_put(root);
  return result;
}

class StatusReader {
public:
  explicit StatusReader(int fd) : fd_(fd) {}

  StatusRecord next(Clock::time_point deadline) {
    while (true) {
      const auto newline = buffered_.find('\n');
      if (newline != std::string::npos) {
        require(newline <= kMaximumLine, "bwrap status line is too long");
        const std::string line = buffered_.substr(0, newline);
        buffered_.erase(0, newline + 1);
        return parse_status(line);
      }
      require(buffered_.size() <= kMaximumLine,
              "bwrap status line is too long");
      const auto remaining =
          std::chrono::duration_cast<std::chrono::milliseconds>(deadline -
                                                                Clock::now());
      require(remaining.count() > 0, "bwrap status read timed out");
      pollfd descriptor{.fd = fd_, .events = POLLIN, .revents = 0};
      const int polled =
          poll(&descriptor, 1, static_cast<int>(remaining.count()));
      if (polled < 0 && errno == EINTR) {
        continue;
      }
      require(polled > 0 && (descriptor.revents & (POLLERR | POLLNVAL)) == 0,
              "bwrap status read failed");
      std::array<char, 512> chunk{};
      const auto count = read(fd_, chunk.data(), chunk.size());
      if (count < 0 && errno == EINTR) {
        continue;
      }
      require(count > 0, "bwrap status closed before a complete record");
      buffered_.append(chunk.data(), static_cast<std::size_t>(count));
    }
  }

private:
  int fd_;
  std::string buffered_;
};

template <typename Predicate>
StatusRecord read_until(StatusReader &reader, Predicate predicate,
                        std::string_view missing) {
  const auto deadline = Clock::now() + std::chrono::milliseconds(kTimeoutMs);
  for (std::size_t count = 0; count < kMaximumRecords; ++count) {
    auto record = reader.next(deadline);
    if (predicate(record)) {
      return record;
    }
  }
  throw std::runtime_error(std::string(missing));
}

int open_pidfd(pid_t pid) {
  const int fd = static_cast<int>(syscall(SYS_pidfd_open, pid, 0));
  require(fd >= 0, "pidfd_open failed");
  return fd;
}

void signal_pidfd(int fd) {
  if (fd >= 0 && syscall(SYS_pidfd_send_signal, fd, SIGKILL, nullptr, 0) < 0 &&
      errno != ESRCH) {
    std::cerr << "pidfd cleanup signal failed: " << std::strerror(errno)
              << '\n';
  }
}

class Cleanup {
public:
  Cleanup(pid_t monitor_pid, int monitor_pidfd)
      : monitor_pid_(monitor_pid), monitor_pidfd_(monitor_pidfd) {}
  ~Cleanup() {
    if (!armed_) {
      return;
    }
    signal_pidfd(worker_pidfd_);
    signal_pidfd(monitor_pidfd_);
    pollfd descriptor{.fd = monitor_pidfd_, .events = POLLIN, .revents = 0};
    (void)poll(&descriptor, 1, kTimeoutMs);
    int status = 0;
    const auto deadline = Clock::now() + std::chrono::milliseconds(kTimeoutMs);
    while (true) {
      const pid_t waited = waitpid(monitor_pid_, &status, WNOHANG);
      if (waited == monitor_pid_ || (waited < 0 && errno == ECHILD)) {
        break;
      }
      if (waited < 0 && errno != EINTR) {
        break;
      }
      if (Clock::now() >= deadline) {
        std::cerr << "timed out reaping bwrap monitor during cleanup\n";
        break;
      }
      pollfd retry{.fd = monitor_pidfd_, .events = POLLIN, .revents = 0};
      (void)poll(&retry, 1, 10);
    }
    if (worker_pidfd_ >= 0) {
      close(worker_pidfd_);
    }
    close(monitor_pidfd_);
  }
  void worker(int fd) { worker_pidfd_ = fd; }
  void disarm() {
    armed_ = false;
    close_checked(worker_pidfd_);
    close_checked(monitor_pidfd_);
    worker_pidfd_ = -1;
    monitor_pidfd_ = -1;
  }

private:
  pid_t monitor_pid_;
  int monitor_pidfd_;
  int worker_pidfd_ = -1;
  bool armed_ = true;
};

class ForkCleanup {
public:
  explicit ForkCleanup(pid_t pid) : pid_(pid) {}
  ~ForkCleanup() {
    if (!armed_) {
      return;
    }
    (void)kill(pid_, SIGKILL);
    int status = 0;
    const auto deadline = Clock::now() + std::chrono::milliseconds(kTimeoutMs);
    while (true) {
      const pid_t waited = waitpid(pid_, &status, WNOHANG);
      if (waited == pid_ || (waited < 0 && errno == ECHILD)) {
        break;
      }
      if (waited < 0 && errno != EINTR) {
        std::cerr << "pre-pidfd child reap failed: " << std::strerror(errno)
                  << '\n';
        break;
      }
      if (Clock::now() >= deadline) {
        std::cerr << "pre-pidfd child reap timed out\n";
        break;
      }
      (void)poll(nullptr, 0, 10);
    }
  }
  void disarm() { armed_ = false; }

private:
  pid_t pid_;
  bool armed_ = true;
};

void verify_pre_pidfd_cleanup_guard() {
  const pid_t child = fork();
  require(child >= 0, "cannot fork cleanup-guard fixture");
  if (child == 0) {
    for (;;) {
      pause();
    }
  }
  {
    ForkCleanup cleanup(child);
  }
  int status = 0;
  errno = 0;
  require(waitpid(child, &status, WNOHANG) < 0 && errno == ECHILD,
          "pre-pidfd cleanup guard did not reap its child");
}

void verify_status_parser_contract() {
  const auto unknown = parse_status(
      R"({"future-object":{"nested":[true,null,1.5]},"future-member":"ok"})");
  require(!unknown.child_pid.has_value() && !unknown.exit_code.has_value(),
          "unknown status object was treated as authoritative");
  const auto child =
      parse_status(R"({"future":17,"child-pid":123,"more":false})");
  require(child.child_pid == 123 && !child.exit_code.has_value(),
          "typed child-pid parser contract failed");
  bool rejected_string = false;
  try {
    (void)parse_status(R"({"child-pid":"123"})");
  } catch (const std::runtime_error &) {
    rejected_string = true;
  }
  require(rejected_string, "string child-pid was accepted");
  const auto combined = parse_status(R"({"child-pid":123,"exit-code":0})");
  require(combined.child_pid == 123 && combined.exit_code == 0,
          "combined status record lost an authoritative field");
  bool rejected_duplicate = false;
  try {
    (void)parse_status(R"({"child-pid":123,"child\u002dpid":124})");
  } catch (const std::runtime_error &) {
    rejected_duplicate = true;
  }
  require(rejected_duplicate, "duplicate child-pid was accepted");
}

bool role_accepts(Role role, Kind kind) {
  return (role == Role::control &&
          (kind == Kind::identity || kind == Kind::control_ready)) ||
         (role == Role::broker && kind == Kind::broker_request) ||
         (role == Role::render && kind == Kind::render_frame);
}

bool send_message(int fd, Role role, Kind kind, std::uint32_t unexpected,
                  std::uint32_t standard_aliases);

bool pidfd_is_readable(int pidfd) {
  pollfd descriptor{.fd = pidfd, .events = POLLIN, .revents = 0};
  const int result = poll(&descriptor, 1, 0);
  require(result >= 0, "pidfd poll failed");
  if (result == 0) {
    return false;
  }
  require(descriptor.revents == POLLIN,
          "pidfd returned an unusable or unexpected poll state");
  return true;
}

Received receive_message(int fd, Role expected_role, pid_t expected_pid,
                         int expected_pidfd) {
  Payload payload{};
  alignas(cmsghdr) std::array<std::byte, CMSG_SPACE(sizeof(ucred))> ancillary{};
  iovec iov{.iov_base = &payload, .iov_len = sizeof(payload)};
  msghdr message{};
  message.msg_iov = &iov;
  message.msg_iovlen = 1;
  message.msg_control = ancillary.data();
  message.msg_controllen = ancillary.size();
  std::array<pollfd, 2> descriptors{{
      {.fd = fd, .events = POLLIN, .revents = 0},
      {.fd = expected_pidfd, .events = POLLIN, .revents = 0},
  }};
  int polled;
  do {
    polled = poll(descriptors.data(), descriptors.size(), kTimeoutMs);
  } while (polled < 0 && errno == EINTR);
  require(polled > 0, "worker message timed out");
  require(descriptors[1].revents == 0,
          descriptors[1].revents == POLLIN
              ? "worker lifetime ended before packet acceptance"
              : "worker pidfd became unusable before packet acceptance");
  require((descriptors[0].revents & POLLIN) != 0, "worker message timed out");
  const auto count = recvmsg(fd, &message, MSG_CMSG_CLOEXEC | MSG_TRUNC);
  require(count == static_cast<ssize_t>(sizeof(payload)) &&
              (message.msg_flags & (MSG_TRUNC | MSG_CTRUNC)) == 0,
          "invalid worker packet");
  std::optional<ucred> credentials;
  for (auto *item = CMSG_FIRSTHDR(&message); item != nullptr;
       item = CMSG_NXTHDR(&message, item)) {
    require(item->cmsg_level == SOL_SOCKET &&
                item->cmsg_type == SCM_CREDENTIALS &&
                item->cmsg_len == CMSG_LEN(sizeof(ucred)) &&
                !credentials.has_value(),
            "invalid worker ancillary identity");
    ucred value;
    std::memcpy(&value, CMSG_DATA(item), sizeof(value));
    credentials = value;
  }
  require(credentials.has_value() && payload.magic == kMagic,
          "missing worker identity");
  require(!pidfd_is_readable(expected_pidfd),
          "worker lifetime ended during packet acceptance");
  const bool credential_match = credentials->pid == expected_pid &&
                                credentials->uid == getuid() &&
                                credentials->gid == getgid();
  return {.payload = payload,
          .credentials = *credentials,
          .accepted = credential_match && payload.role == expected_role &&
                      role_accepts(expected_role, payload.kind)};
}

void verify_closed_pidfd_rejection() {
  std::array<int, 2> sockets{};
  require(socketpair(AF_UNIX, SOCK_SEQPACKET | SOCK_CLOEXEC, 0,
                     sockets.data()) == 0,
          "cannot create closed-pidfd fixture socket");
  int enabled = 1;
  require(setsockopt(sockets[0], SOL_SOCKET, SO_PASSCRED, &enabled,
                     sizeof(enabled)) == 0,
          "cannot enable credentials for closed-pidfd fixture");
  const int pidfd = open_pidfd(getpid());
  require(send_message(sockets[1], Role::control, Kind::control_ready, 0, 0),
          "cannot queue closed-pidfd fixture packet");
  close_checked(pidfd);
  bool rejected = false;
  try {
    (void)receive_message(sockets[0], Role::control, getpid(), pidfd);
  } catch (const std::runtime_error &) {
    rejected = true;
  }
  close_checked(sockets[0]);
  close_checked(sockets[1]);
  require(rejected,
          "queued correct-credential packet passed with a closed pidfd");
}

bool send_message(int fd, Role role, Kind kind, std::uint32_t unexpected,
                  std::uint32_t standard_aliases) {
  const Payload payload{.magic = kMagic,
                        .role = role,
                        .kind = kind,
                        .inner_pid = getpid(),
                        .inner_uid = getuid(),
                        .inner_gid = getgid(),
                        .unexpected_fds = unexpected,
                        .standard_fd_aliases = standard_aliases};
  return send(fd, &payload, sizeof(payload), MSG_NOSIGNAL) == sizeof(payload);
}

std::uint32_t standard_fd_aliases() {
  std::array<struct stat, 6> states{};
  for (int fd = 0; fd <= kRenderFd; ++fd) {
    require(fstat(fd, &states[static_cast<std::size_t>(fd)]) == 0,
            "cannot inspect inherited descriptor identity");
  }
  std::uint32_t aliases = 0;
  for (int standard = 0; standard <= 2; ++standard) {
    for (int role = kControlFd; role <= kRenderFd; ++role) {
      const auto &left = states[static_cast<std::size_t>(standard)];
      const auto &right = states[static_cast<std::size_t>(role)];
      if (left.st_dev == right.st_dev && left.st_ino == right.st_ino) {
        ++aliases;
      }
    }
  }
  return aliases;
}

std::uint32_t unexpected_fds() {
  DIR *directory = opendir("/proc/self/fd");
  require(directory != nullptr, "cannot inspect worker descriptors");
  const int scan_fd = dirfd(directory);
  std::uint32_t count = 0;
  while (const auto *entry = readdir(directory)) {
    int fd = -1;
    const std::string_view name(entry->d_name);
    const auto parsed =
        std::from_chars(name.data(), name.data() + name.size(), fd);
    if (parsed.ec == std::errc() && (fd < 0 || fd > kRenderFd) &&
        fd != scan_fd) {
      ++count;
    }
  }
  closedir(directory);
  return count;
}

int worker_main() {
  const auto unexpected = unexpected_fds();
  const auto aliases = standard_fd_aliases();
  for (const int fd : {kControlFd, kBrokerFd, kRenderFd}) {
    set_cloexec(fd, true);
  }
  if (!send_message(kControlFd, Role::control, Kind::identity, unexpected,
                    aliases)) {
    return 1;
  }
  const pid_t child = fork();
  if (child < 0) {
    return 1;
  }
  if (child == 0) {
    const bool sent = send_message(kControlFd, Role::control,
                                   Kind::control_ready, unexpected, aliases) &&
                      send_message(kBrokerFd, Role::broker,
                                   Kind::broker_request, unexpected, aliases) &&
                      send_message(kRenderFd, Role::render, Kind::render_frame,
                                   unexpected, aliases);
    _exit(sent ? 0 : 1);
  }
  int status = 0;
  pid_t waited;
  do {
    waited = waitpid(child, &status, 0);
  } while (waited < 0 && errno == EINTR);
  if (waited != child || !WIFEXITED(status) || WEXITSTATUS(status) != 0) {
    return 1;
  }
  const bool sent = send_message(kControlFd, Role::broker, Kind::broker_request,
                                 unexpected, aliases) &&
                    send_message(kBrokerFd, Role::render, Kind::render_frame,
                                 unexpected, aliases) &&
                    send_message(kRenderFd, Role::control, Kind::control_ready,
                                 unexpected, aliases) &&
                    send_message(kControlFd, Role::control, Kind::control_ready,
                                 unexpected, aliases) &&
                    send_message(kBrokerFd, Role::broker, Kind::broker_request,
                                 unexpected, aliases) &&
                    send_message(kRenderFd, Role::render, Kind::render_frame,
                                 unexpected, aliases);
  if (!sent) {
    return 1;
  }
  char acknowledgement = 0;
  ssize_t received;
  do {
    received = recv(kControlFd, &acknowledgement, 1, 0);
  } while (received < 0 && errno == EINTR);
  if (received != 1 || acknowledgement != 'A') {
    return 1;
  }
  const pid_t holder = fork();
  if (holder < 0) {
    return 1;
  }
  if (holder == 0) {
    usleep(100000);
    const bool control = send_message(kControlFd, Role::control,
                                      Kind::control_ready, unexpected, aliases);
    const bool broker = send_message(kBrokerFd, Role::broker,
                                     Kind::broker_request, unexpected, aliases);
    const bool render = send_message(kRenderFd, Role::render,
                                     Kind::render_frame, unexpected, aliases);
    const bool attempted = control || broker || render;
    _exit(attempted ? 0 : 1);
  }
  return 0;
}

[[noreturn]] void launch(const std::array<int, 3> &sockets, int status,
                         int barrier, const std::string &executable) {
  try {
    relocate({{{sockets[0], kControlFd},
               {sockets[1], kBrokerFd},
               {sockets[2], kRenderFd},
               {status, kStatusFd},
               {barrier, kBarrierFd}}});
    close_unlisted();
    std::vector<std::string> arguments = {"/usr/bin/bwrap",
                                          "--unshare-user",
                                          "--unshare-pid",
                                          "--unshare-ipc",
                                          "--unshare-uts",
                                          "--unshare-net",
                                          "--unshare-cgroup-try",
                                          "--disable-userns",
                                          "--assert-userns-disabled",
                                          "--uid",
                                          "0",
                                          "--gid",
                                          "0",
                                          "--hostname",
                                          "omarchy-plugin",
                                          "--clearenv",
                                          "--setenv",
                                          "PATH",
                                          "/usr/bin",
                                          "--setenv",
                                          "PWD",
                                          "/app",
                                          "--new-session",
                                          "--die-with-parent",
                                          "--as-pid-1",
                                          "--cap-drop",
                                          "ALL",
                                          "--json-status-fd",
                                          std::to_string(kStatusFd),
                                          "--block-fd",
                                          std::to_string(kBarrierFd),
                                          "--proc",
                                          "/proc",
                                          "--dev",
                                          "/dev",
                                          "--tmpfs",
                                          "/tmp",
                                          "--ro-bind",
                                          "/usr",
                                          "/usr",
                                          "--symlink",
                                          "usr/bin",
                                          "/bin",
                                          "--symlink",
                                          "usr/lib",
                                          "/lib",
                                          "--symlink",
                                          "usr/lib64",
                                          "/lib64",
                                          "--dir",
                                          "/app",
                                          "--ro-bind",
                                          executable,
                                          "/app/worker",
                                          "--chdir",
                                          "/app",
                                          "/app/worker",
                                          "--worker"};
    std::vector<char *> argv;
    for (auto &argument : arguments) {
      argv.push_back(argument.data());
    }
    argv.push_back(nullptr);
    char path[] = "PATH=/usr/bin";
    char pwd[] = "PWD=/";
    std::array<char *, 3> environment{path, pwd, nullptr};
    execve("/usr/bin/bwrap", argv.data(), environment.data());
  } catch (const std::exception &) {
  }
  _exit(125);
}

std::vector<int> occupy_reserved_range() {
  std::vector<int> result;
  while (true) {
    const int fd = open("/dev/null", O_RDONLY | O_CLOEXEC);
    require(fd >= 0, "cannot occupy reserved descriptors");
    if (fd > kBarrierFd) {
      close_checked(fd);
      return result;
    }
    result.push_back(fd);
  }
}

int supervisor_main(bool collision_test) {
  normalize_standard_fds();
  verify_status_parser_contract();
  verify_pre_pidfd_cleanup_guard();
  verify_closed_pidfd_rejection();
  const auto occupied =
      collision_test ? occupy_reserved_range() : std::vector<int>{};
  std::array<std::array<int, 2>, 3> sockets{};
  int status[2];
  int barrier[2];
  for (auto &socket : sockets) {
    require(socketpair(AF_UNIX, SOCK_SEQPACKET | SOCK_CLOEXEC, 0,
                       socket.data()) == 0,
            "socketpair failed");
    int enabled = 1;
    require(setsockopt(socket[0], SOL_SOCKET, SO_PASSCRED, &enabled,
                       sizeof(enabled)) == 0,
            "SO_PASSCRED failed");
  }
  require(pipe2(status, O_CLOEXEC) == 0 && pipe2(barrier, O_CLOEXEC) == 0,
          "pipe2 failed");
  const auto executable = executable_path();
  const pid_t monitor_pid = fork();
  require(monitor_pid >= 0, "fork failed");
  if (monitor_pid == 0) {
    for (const auto &socket : sockets) {
      close(socket[0]);
    }
    close(status[0]);
    close(barrier[1]);
    launch({sockets[0][1], sockets[1][1], sockets[2][1]}, status[1], barrier[0],
           executable);
  }
  ForkCleanup fork_cleanup(monitor_pid);
  const int monitor_pidfd = open_pidfd(monitor_pid);
  Cleanup cleanup(monitor_pid, monitor_pidfd);
  fork_cleanup.disarm();
  for (const int fd : occupied) {
    close_checked(fd);
  }
  for (const auto &socket : sockets) {
    close_checked(socket[1]);
  }
  close_checked(status[1]);
  close_checked(barrier[0]);

  StatusReader reader(status[0]);
  const auto child_record = read_until(
      reader, [](const auto &record) { return record.child_pid.has_value(); },
      "bwrap omitted child-pid");
  const pid_t worker_pid = *child_record.child_pid;
  require(worker_pid != monitor_pid, "monitor PID mistaken for worker PID");
  const int worker_pidfd = open_pidfd(worker_pid);
  cleanup.worker(worker_pidfd);
  pollfd held{.fd = worker_pidfd, .events = POLLIN, .revents = 0};
  require(poll(&held, 1, 0) == 0, "worker exited before barrier release");
  const char release = '1';
  require(write(barrier[1], &release, 1) == 1, "barrier release failed");
  close_checked(barrier[1]);

  const auto identity =
      receive_message(sockets[0][0], Role::control, worker_pid, worker_pidfd);
  require(identity.accepted && identity.payload.inner_pid == 1 &&
              identity.payload.inner_uid == 0 &&
              identity.payload.inner_gid == 0 &&
              identity.payload.unexpected_fds == 0 &&
              identity.payload.standard_fd_aliases == 0,
          "worker identity contract failed");
  const auto descendant_control =
      receive_message(sockets[0][0], Role::control, worker_pid, worker_pidfd);
  const auto descendant_broker =
      receive_message(sockets[1][0], Role::broker, worker_pid, worker_pidfd);
  const auto descendant_render =
      receive_message(sockets[2][0], Role::render, worker_pid, worker_pidfd);
  require(!descendant_control.accepted && !descendant_broker.accepted &&
              !descendant_render.accepted &&
              descendant_control.credentials.pid != worker_pid &&
              descendant_broker.credentials.pid != worker_pid &&
              descendant_render.credentials.pid != worker_pid,
          "forked descendant was accepted");
  const auto wrong_control =
      receive_message(sockets[0][0], Role::control, worker_pid, worker_pidfd);
  const auto wrong_broker =
      receive_message(sockets[1][0], Role::broker, worker_pid, worker_pidfd);
  const auto wrong_render =
      receive_message(sockets[2][0], Role::render, worker_pid, worker_pidfd);
  require(!wrong_control.accepted && !wrong_broker.accepted &&
              !wrong_render.accepted,
          "wrong-role packet was accepted");
  require(
      receive_message(sockets[0][0], Role::control, worker_pid, worker_pidfd)
              .accepted &&
          receive_message(sockets[1][0], Role::broker, worker_pid, worker_pidfd)
              .accepted &&
          receive_message(sockets[2][0], Role::render, worker_pid, worker_pidfd)
              .accepted,
      "valid role packet was rejected");

  const char acknowledgement = 'A';
  require(send(sockets[0][0], &acknowledgement, 1, MSG_NOSIGNAL) == 1,
          "cannot acknowledge validated worker exchange");

  pollfd exited{.fd = worker_pidfd, .events = POLLIN, .revents = 0};
  require(poll(&exited, 1, kTimeoutMs) == 1 && (exited.revents & POLLIN) != 0,
          "worker pidfd did not become readable");
  for (const auto &socket : sockets) {
    std::array<std::byte, sizeof(Payload)> discarded{};
    const auto count = recv(socket[0], discarded.data(), discarded.size(),
                            MSG_DONTWAIT | MSG_TRUNC);
    require(count == 0 || (count < 0 && errno == EAGAIN),
            "traffic remained after worker lifetime ended");
  }
  for (const auto &socket : sockets) {
    close_checked(socket[0]);
  }
  std::optional<int> exit_code = child_record.exit_code;
  if (!exit_code.has_value()) {
    const auto exit_record = read_until(
        reader, [](const auto &record) { return record.exit_code.has_value(); },
        "bwrap omitted exit-code");
    exit_code = exit_record.exit_code;
  }
  require(*exit_code == 0, "worker failed");
  close_checked(status[0]);
  pollfd monitor_exited{.fd = monitor_pidfd, .events = POLLIN, .revents = 0};
  require(poll(&monitor_exited, 1, kTimeoutMs) == 1, "bwrap monitor timed out");
  int monitor_status = 0;
  require(waitpid(monitor_pid, &monitor_status, WNOHANG) == monitor_pid &&
              WIFEXITED(monitor_status) && WEXITSTATUS(monitor_status) == 0,
          "bwrap monitor failed");
  cleanup.disarm();

  std::cout << "bwrap_pid=" << monitor_pid
            << " reported_outer_worker_pid=" << worker_pid
            << " scm_pid=" << identity.credentials.pid
            << " broker_uid=" << getuid()
            << " scm_uid=" << identity.credentials.uid
            << " inner_pid=" << identity.payload.inner_pid
            << " inner_uid=" << identity.payload.inner_uid
            << " unexpected_fds=" << identity.payload.unexpected_fds
            << " standard_fd_aliases=" << identity.payload.standard_fd_aliases
            << " control_fd=3 broker_fd=4 render_fd=5"
            << " role_substitution=denied descendant_sender=denied"
            << " post_exit_holder=contained"
            << " invalid_pidfd=denied pre_pidfd_guard=bounded"
            << " reserved_fd_collision="
            << (collision_test ? "denied" : "not-exercised")
            << " pidfd_exit=readable\n";
  return 0;
}

} // namespace

int main(int argc, char **argv) {
  try {
    struct sigaction action{};
    action.sa_handler = SIG_IGN;
    sigemptyset(&action.sa_mask);
    require(sigaction(SIGPIPE, &action, nullptr) == 0, "sigaction failed");
    if (argc == 2 && std::string_view(argv[1]) == "--worker") {
      return worker_main();
    }
    if (argc == 2 && std::string_view(argv[1]) == "--occupied-reserved") {
      return supervisor_main(true);
    }
    if (argc == 2 && std::string_view(argv[1]) == "--closed-stdin") {
      close(STDIN_FILENO);
      return supervisor_main(false);
    }
    if (argc == 2 && std::string_view(argv[1]) == "--closed-stdout") {
      close(STDOUT_FILENO);
      return supervisor_main(false);
    }
    if (argc == 2 && std::string_view(argv[1]) == "--closed-stderr") {
      close(STDERR_FILENO);
      return supervisor_main(false);
    }
    if (argc == 1) {
      return supervisor_main(false);
    }
    std::cerr << "usage: " << argv[0]
              << " [--worker|--occupied-reserved|--closed-stdin|"
                 "--closed-stdout|--closed-stderr]\n";
    return 2;
  } catch (const std::exception &error) {
    std::cerr << "plugin-bwrap-identity-spike: " << error.what() << '\n';
    return 1;
  }
}
