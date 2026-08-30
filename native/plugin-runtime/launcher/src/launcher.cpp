#include "omarchy/plugin_runtime/launcher/launcher.h"
#include "omarchy/plugin_runtime/launcher/termination_state.h"
#include "omarchy/plugin_runtime/runtime_paths.hpp"
#include "process_cleanup.hpp"

#include "omarchy/plugin/wire/envelope.hpp"

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonParseError>

#include <dirent.h>
#include <fcntl.h>
#include <linux/memfd.h>
#include <poll.h>
#include <sched.h>
#include <seccomp.h>
#include <signal.h>
#include <sys/prctl.h>
#include <sys/epoll.h>
#include <sys/resource.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <systemd/sd-bus.h>
#include <unistd.h>

#include <algorithm>
#include <array>
#include <cerrno>
#include <charconv>
#include <chrono>
#include <condition_variable>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <limits>
#include <mutex>
#include <optional>
#include <stdexcept>
#include <string_view>
#include <thread>
#include <utility>

namespace omarchy::plugin_runtime::launcher {
namespace {
using detail::CleanupJob;
using detail::ProcessScopeReaper;
using detail::ReapCompletion;
constexpr std::string_view kSystemBwrapPath = "/usr/bin/bwrap";
constexpr std::size_t kMaximumStatusLine = 4096;
constexpr unsigned kMaximumStatusRecords = 32;
constexpr int kExecErrorFd = 11;

class Fd {
public:
  Fd() = default;
  explicit Fd(int descriptor) : descriptor_(descriptor) {}
  Fd(const Fd &) = delete;
  Fd &operator=(const Fd &) = delete;
  Fd(Fd &&other) noexcept : descriptor_(other.release()) {}
  Fd &operator=(Fd &&other) noexcept {
    if (this != &other) {
      reset(other.release());
    }
    return *this;
  }
  ~Fd() { reset(); }
  [[nodiscard]] int get() const { return descriptor_; }
  [[nodiscard]] explicit operator bool() const { return descriptor_ >= 0; }
  [[nodiscard]] int release() { return std::exchange(descriptor_, -1); }
  void reset(int descriptor = -1) {
    if (descriptor_ >= 0) {
      close(descriptor_);
    }
    descriptor_ = descriptor;
  }

private:
  int descriptor_ = -1;
};

struct Pipe {
  Fd read;
  Fd write;
};

struct Channel {
  Fd trusted;
  Fd worker;
};

struct StatusRecord {
  std::optional<pid_t> child_pid;
  std::optional<int> exit_code;
};

[[nodiscard]] int
milliseconds_remaining(std::chrono::steady_clock::time_point deadline) {
  const auto now = std::chrono::steady_clock::now();
  if (now >= deadline) {
    return 0;
  }
  const auto remaining =
      std::chrono::duration_cast<std::chrono::milliseconds>(deadline - now);
  return static_cast<int>(
      std::min<std::int64_t>(std::max<std::int64_t>(remaining.count(), 1),
                             std::numeric_limits<int>::max()));
}

[[nodiscard]] bool canonical_plugin_id(std::string_view value) {
  if (value.empty() || value.size() > 128 || value.front() < 'a' ||
      value.front() > 'z') {
    return false;
  }
  bool previous_separator = true;
  for (const char character : value) {
    const bool separator =
        character == '.' || character == '-' || character == '_';
    const bool accepted = (character >= 'a' && character <= 'z') ||
                          (character >= '0' && character <= '9') || separator;
    if (!accepted || (separator && previous_separator)) {
      return false;
    }
    previous_separator = separator;
  }
  return !previous_separator;
}

[[nodiscard]] bool canonical_digest(std::string_view value) {
  return value.size() == 64 && std::ranges::all_of(value, [](char character) {
           return (character >= '0' && character <= '9') ||
                  (character >= 'a' && character <= 'f');
         });
}

[[nodiscard]] bool trusted_executable(std::string_view path,
                                      bool require_root_owner,
                                      std::string &error) {
  const std::filesystem::path candidate(path);
  if (!candidate.is_absolute() || candidate.lexically_normal() != candidate) {
    error = "trusted executable path is not absolute and normalized";
    return false;
  }
  struct stat metadata{};
  if (lstat(candidate.c_str(), &metadata) < 0 || !S_ISREG(metadata.st_mode) ||
      (metadata.st_mode & 0111) == 0 ||
      (metadata.st_mode & (S_IWGRP | S_IWOTH | S_ISUID | S_ISGID)) != 0 ||
      (require_root_owner && metadata.st_uid != 0)) {
    error = "trusted executable metadata is unsafe";
    return false;
  }
  return true;
}

[[nodiscard]] bool normalize_standard_descriptors(std::string &error) {
  for (int descriptor = 0; descriptor <= 2; ++descriptor) {
    errno = 0;
    if (fcntl(descriptor, F_GETFD) >= 0) {
      continue;
    }
    if (errno != EBADF) {
      error = "cannot inspect standard descriptors";
      return false;
    }
    const int flags = descriptor == STDIN_FILENO ? O_RDONLY : O_WRONLY;
    Fd replacement(open("/dev/null", flags | O_CLOEXEC));
    if (!replacement || dup2(replacement.get(), descriptor) < 0) {
      error = "cannot normalize a closed standard descriptor";
      return false;
    }
  }
  return true;
}

[[nodiscard]] Pipe make_pipe() {
  std::array<int, 2> descriptors{};
  if (pipe2(descriptors.data(), O_CLOEXEC) < 0) {
    throw std::runtime_error("pipe2 failed");
  }
  return {.read = Fd(descriptors.at(0)), .write = Fd(descriptors.at(1))};
}

[[nodiscard]] Channel make_channel() {
  std::array<int, 2> descriptors{};
  if (socketpair(AF_UNIX, SOCK_SEQPACKET | SOCK_CLOEXEC, 0,
                 descriptors.data()) < 0) {
    throw std::runtime_error("socketpair failed");
  }
  const int enabled = 1;
  if (setsockopt(descriptors.at(0), SOL_SOCKET, SO_PASSCRED, &enabled,
                 sizeof(enabled)) < 0) {
    close(descriptors.at(0));
    close(descriptors.at(1));
    throw std::runtime_error("SO_PASSCRED failed");
  }
  return {.trusted = Fd(descriptors.at(0)), .worker = Fd(descriptors.at(1))};
}

[[nodiscard]] Fd duplicate_directory(int descriptor, bool immutable,
                                     std::string &error) {
  Fd duplicate(fcntl(descriptor, F_DUPFD_CLOEXEC, 64));
  struct stat metadata{};
  if (!duplicate || fstat(duplicate.get(), &metadata) < 0 ||
      !S_ISDIR(metadata.st_mode) || metadata.st_uid != getuid() ||
      (metadata.st_mode & (S_IWGRP | S_IWOTH)) != 0 ||
      (immutable && (metadata.st_mode & 0222) != 0)) {
    error = immutable ? "revision descriptor is not immutable and private"
                      : "state descriptor is not private and owned";
    return {};
  }
  return duplicate;
}

[[nodiscard]] int resolve_syscall(std::string_view name) {
  const std::string owned(name);
  return seccomp_syscall_resolve_name(owned.c_str());
}

[[nodiscard]] Fd compile_seccomp(const sandbox::SeccompPolicy &policy,
                                 std::string &error) {
  Fd descriptor(
      static_cast<int>(syscall(SYS_memfd_create, "omarchy-plugin-seccomp",
                               MFD_CLOEXEC | MFD_ALLOW_SEALING)));
  if (!descriptor) {
    error = "memfd_create is unavailable";
    return {};
  }
  scmp_filter_ctx context = seccomp_init(SCMP_ACT_ERRNO(policy.denied_errno));
  if (context == nullptr) {
    error = "seccomp_init failed";
    return {};
  }
  const auto release = [&context]() {
    seccomp_release(context);
    context = nullptr;
  };
  const int clone3 = resolve_syscall("clone3");
  if (clone3 != __NR_SCMP_ERROR &&
      seccomp_rule_add(context, SCMP_ACT_ERRNO(policy.clone3_errno), clone3,
                       0) < 0) {
    release();
    error = "cannot compile clone3 denial";
    return {};
  }
  for (const std::string &name : policy.launch_allowlist) {
    const int number = resolve_syscall(name);
    if (number == __NR_SCMP_ERROR) {
      release();
      error = "kernel architecture lacks required syscall: " + name;
      return {};
    }
    int result = 0;
    if (name == "clone") {
      const std::uint64_t mask = policy.thread_clone.required_flags |
                                 policy.thread_clone.forbidden_flags;
      result = seccomp_rule_add(context, SCMP_ACT_ALLOW, number, 1,
                                SCMP_A0(SCMP_CMP_MASKED_EQ, mask,
                                        policy.thread_clone.required_flags));
    } else {
      result = seccomp_rule_add(context, SCMP_ACT_ALLOW, number, 0);
    }
    if (result < 0) {
      release();
      error = "cannot compile required syscall rule: " + name;
      return {};
    }
  }
  if (seccomp_export_bpf(context, descriptor.get()) < 0 ||
      lseek(descriptor.get(), 0, SEEK_SET) < 0) {
    release();
    error = "cannot export seccomp filter";
    return {};
  }
  release();
  const int seals = F_SEAL_WRITE | F_SEAL_GROW | F_SEAL_SHRINK | F_SEAL_SEAL;
  if (fcntl(descriptor.get(), F_ADD_SEALS, seals) < 0) {
    error = "cannot seal seccomp program";
    return {};
  }
  return descriptor;
}

[[nodiscard]] Fd open_pidfd(pid_t process) {
  return Fd(static_cast<int>(syscall(SYS_pidfd_open, process, 0)));
}

enum class PidfdState { alive, exited, unusable };

[[nodiscard]] PidfdState pidfd_state(int descriptor) {
  pollfd polled{.fd = descriptor, .events = POLLIN, .revents = 0};
  const int result = poll(&polled, 1, 0);
  if (result == 0 && polled.revents == 0) {
    return PidfdState::alive;
  }
  if (result == 1 && polled.revents == POLLIN) {
    return PidfdState::exited;
  }
  return PidfdState::unusable;
}

[[nodiscard]] bool kernel_prerequisites(std::string &error) {
  Fd own_pidfd = open_pidfd(getpid());
  if (!own_pidfd || pidfd_state(own_pidfd.get()) != PidfdState::alive) {
    error = "pidfd_open or strict pidfd polling is unavailable";
    return false;
  }
  if (syscall(SYS_close_range, std::numeric_limits<unsigned>::max() - 1,
              std::numeric_limits<unsigned>::max(), CLOSE_RANGE_CLOEXEC) < 0) {
    error = "close_range is unavailable";
    return false;
  }
  return true;
}

[[nodiscard]] std::optional<std::string>
decode_json_string(std::string_view quoted) {
  const QByteArray document =
      QByteArray("[") + QByteArray(quoted.data(), quoted.size()) + "]";
  QJsonParseError error{};
  const QJsonDocument parsed = QJsonDocument::fromJson(document, &error);
  if (error.error != QJsonParseError::NoError || !parsed.isArray() ||
      parsed.array().size() != 1 || !parsed.array().at(0).isString()) {
    return std::nullopt;
  }
  return parsed.array().at(0).toString().toStdString();
}

[[nodiscard]] bool unique_authoritative_keys(std::string_view line) {
  unsigned object_depth = 0;
  unsigned array_depth = 0;
  bool expecting_top_key = false;
  unsigned child_pid_count = 0;
  unsigned exit_code_count = 0;
  for (std::size_t index = 0; index < line.size();) {
    const char character = line.at(index);
    if (character == '"') {
      const std::size_t start = index++;
      bool escaped = false;
      while (index < line.size()) {
        const char current = line.at(index++);
        if (!escaped && current == '"') {
          break;
        }
        if (!escaped && current == '\\') {
          escaped = true;
        } else {
          escaped = false;
        }
      }
      if (index > line.size() || line.at(index - 1) != '"') {
        return false;
      }
      if (object_depth == 1 && array_depth == 0 && expecting_top_key) {
        const auto key = decode_json_string(line.substr(start, index - start));
        if (!key) {
          return false;
        }
        child_pid_count += *key == "child-pid" ? 1U : 0U;
        exit_code_count += *key == "exit-code" ? 1U : 0U;
        expecting_top_key = false;
      }
      continue;
    }
    if (character == '{') {
      ++object_depth;
      if (object_depth == 1) {
        expecting_top_key = true;
      }
    } else if (character == '}') {
      if (object_depth == 0) {
        return false;
      }
      --object_depth;
    } else if (character == '[') {
      ++array_depth;
    } else if (character == ']') {
      if (array_depth == 0) {
        return false;
      }
      --array_depth;
    } else if (character == ',' && object_depth == 1 && array_depth == 0) {
      expecting_top_key = true;
    }
    ++index;
  }
  return object_depth == 0 && array_depth == 0 && child_pid_count <= 1 &&
         exit_code_count <= 1;
}

[[nodiscard]] std::optional<StatusRecord>
parse_status_record(std::string_view line) {
  if (line.empty() || line.size() > kMaximumStatusLine ||
      !unique_authoritative_keys(line)) {
    return std::nullopt;
  }
  QJsonParseError error{};
  const QJsonDocument document =
      QJsonDocument::fromJson(QByteArray(line.data(), line.size()), &error);
  if (error.error != QJsonParseError::NoError || !document.isObject()) {
    return std::nullopt;
  }
  const QJsonObject object = document.object();
  StatusRecord result;
  if (object.contains(QStringLiteral("child-pid"))) {
    const QJsonValue value = object.value(QStringLiteral("child-pid"));
    const double number = value.toDouble(-1);
    if (!value.isDouble() || number < 1 ||
        number > std::numeric_limits<pid_t>::max() ||
        number != static_cast<double>(static_cast<pid_t>(number))) {
      return std::nullopt;
    }
    result.child_pid = static_cast<pid_t>(number);
  }
  if (object.contains(QStringLiteral("exit-code"))) {
    const QJsonValue value = object.value(QStringLiteral("exit-code"));
    const double number = value.toDouble(-1);
    if (!value.isDouble() || number < 0 || number > 255 ||
        number != static_cast<double>(static_cast<int>(number))) {
      return std::nullopt;
    }
    result.exit_code = static_cast<int>(number);
  }
  return result;
}

[[nodiscard]] std::vector<char *> pointers(std::vector<std::string> &values) {
  std::vector<char *> output;
  output.reserve(values.size() + 1);
  for (std::string &value : values) {
    output.push_back(value.data());
  }
  output.push_back(nullptr);
  return output;
}

void write_child_error(int descriptor, int error) {
  const auto *cursor = reinterpret_cast<const std::byte *>(&error);
  std::size_t remaining = sizeof(error);
  while (remaining > 0) {
    const ssize_t written = write(descriptor, cursor, remaining);
    if (written > 0) {
      cursor += written;
      remaining -= static_cast<std::size_t>(written);
    } else if (written < 0 && errno == EINTR) {
      continue;
    } else {
      break;
    }
  }
}

[[noreturn]] void child_exec(std::string bwrap_path, sandbox::SandboxPlan plan,
                             std::span<const int> sources,
                             int exec_error_fd = kExecErrorFd) {
  if (exec_error_fd < 0 ||
      static_cast<std::size_t>(exec_error_fd) >= sources.size()) {
    _exit(126);
  }
  std::vector<Fd> staged(sources.size());
  int minimum = 64;
  for (std::size_t index = 0; index < sources.size(); ++index) {
    const int duplicate = fcntl(sources[index], F_DUPFD_CLOEXEC, minimum);
    if (duplicate < 0) {
      const int saved = errno;
      write_child_error(sources[static_cast<std::size_t>(exec_error_fd)], saved);
      _exit(126);
    }
    staged.at(index).reset(duplicate);
    minimum = duplicate + 1;
  }
  for (std::size_t destination = 0; destination < staged.size();
       ++destination) {
    if (dup2(staged.at(destination).get(), static_cast<int>(destination)) < 0) {
      const int saved = errno;
      write_child_error(staged[static_cast<std::size_t>(exec_error_fd)].get(),
                        saved);
      _exit(126);
    }
  }
  for (Fd &descriptor : staged) {
    descriptor.reset();
  }
  if (fcntl(exec_error_fd, F_SETFD, FD_CLOEXEC) < 0 ||
      syscall(SYS_close_range, static_cast<unsigned>(sources.size()), ~0U,
              0U) < 0) {
    const int saved = errno;
    write_child_error(exec_error_fd, saved);
    _exit(126);
  }
  const std::array limits = {
      std::pair{RLIMIT_NOFILE,
                rlimit{.rlim_cur = plan.resources.open_files_max,
                       .rlim_max = plan.resources.open_files_max}},
      std::pair{RLIMIT_FSIZE,
                rlimit{.rlim_cur = plan.resources.file_size_max_bytes,
                       .rlim_max = plan.resources.file_size_max_bytes}},
      std::pair{RLIMIT_CORE,
                rlimit{.rlim_cur = plan.resources.core_size_max_bytes,
                       .rlim_max = plan.resources.core_size_max_bytes}}};
  for (const auto &[resource, limit] : limits) {
    if (setrlimit(resource, &limit) < 0) {
      const int saved = errno;
      write_child_error(exec_error_fd, saved);
      _exit(126);
    }
  }
  if (prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) < 0) {
    const int saved = errno;
    write_child_error(exec_error_fd, saved);
    _exit(126);
  }

  std::vector<std::string> arguments = std::move(plan.argv);
  arguments.at(0) = bwrap_path;
  std::vector<std::string> environment = std::move(plan.pre_bwrap_environment);
  auto argument_pointers = pointers(arguments);
  auto environment_pointers = pointers(environment);
  execve(bwrap_path.c_str(), argument_pointers.data(),
         environment_pointers.data());
  const int saved = errno;
  write_child_error(exec_error_fd, saved);
  _exit(126);
}

} // namespace

OwnedDescriptor::OwnedDescriptor(int descriptor) noexcept
    : descriptor_(descriptor) {}
OwnedDescriptor::OwnedDescriptor(OwnedDescriptor &&other) noexcept
    : descriptor_(other.release()) {}
OwnedDescriptor &OwnedDescriptor::operator=(OwnedDescriptor &&other) noexcept {
  if (this != &other) reset(other.release());
  return *this;
}
OwnedDescriptor::~OwnedDescriptor() { reset(); }
int OwnedDescriptor::get() const noexcept { return descriptor_; }
int OwnedDescriptor::release() noexcept {
  return std::exchange(descriptor_, -1);
}
OwnedDescriptor::operator bool() const noexcept { return descriptor_ >= 0; }
void OwnedDescriptor::reset(int descriptor) noexcept {
  if (descriptor_ >= 0) close(descriptor_);
  descriptor_ = descriptor;
}

bool ResourceScopeController::probe(std::string &error) {
  return probe(std::chrono::steady_clock::now() + std::chrono::seconds(2),
               error);
}

ResourceScopeController::AttachResult ResourceScopeController::attach(
    std::string_view unit, pid_t monitor_pid, pid_t worker_pid,
    const sandbox::SandboxPlan &plan, std::chrono::milliseconds timeout,
    std::string &error) {
  if (timeout.count() <= 0) {
    error = "resource-scope attachment deadline expired";
    return {};
  }
  return attach(unit, monitor_pid, worker_pid, plan,
                std::chrono::steady_clock::now() + timeout, error);
}

namespace {
[[nodiscard]] std::size_t role_index(EndpointRole role) noexcept {
  switch (role) {
  case EndpointRole::control: return 0;
  case EndpointRole::broker: return 1;
  case EndpointRole::render: return 2;
  }
  return 3;
}

[[nodiscard]] bool mask_contains(EndpointMask mask, EndpointRole role) noexcept {
  const auto bits = static_cast<std::uint8_t>(mask);
  return (bits & (1U << role_index(role))) != 0;
}

[[nodiscard]] bool valid_mask(EndpointMask mask) noexcept {
  return (static_cast<std::uint8_t>(mask) &
          ~static_cast<std::uint8_t>(EndpointMask::all)) == 0;
}

[[nodiscard]] bool mask_is_subset(EndpointMask subset,
                                  EndpointMask superset) noexcept {
  const auto subset_bits = static_cast<std::uint8_t>(subset);
  const auto superset_bits = static_cast<std::uint8_t>(superset);
  return (subset_bits & ~superset_bits) == 0;
}

[[nodiscard]] bool valid_packet_limit(PacketSizeLimit limit) noexcept {
  return limit.bytes > 0 && limit.bytes <= kTransportPacketHardLimit;
}

[[nodiscard]] std::size_t v1_packet_limit(EndpointRole role) noexcept {
  using WireRole = omarchy::plugin::wire::EndpointRole;
  WireRole wire_role{};
  switch (role) {
  case EndpointRole::control: wire_role = WireRole::control; break;
  case EndpointRole::broker: wire_role = WireRole::broker; break;
  case EndpointRole::render: wire_role = WireRole::render; break;
  default: return 0;
  }
  return omarchy::plugin::wire::kHeaderSizeV1 +
         omarchy::plugin::wire::payload_cap(wire_role);
}
} // namespace

struct Worker::Impl {
  LaunchIdentity identity;
  std::array<Fd, 3> channels;
  Fd worker_pidfd;
  Fd standard_output;
  Fd standard_error;
  Fd readiness;
  std::shared_ptr<ProcessScopeReaper> reaper;
  std::unique_ptr<CleanupJob> cleanup;
  bool accepting = true;
  TerminationState termination;
  std::shared_ptr<ReapCompletion> completion;
  std::size_t next_receive_lane = 0;
  ReadinessInterests readiness_interests{};

  [[nodiscard]] int channel(EndpointRole role) const {
    switch (role) {
    case EndpointRole::control:
      return channels.at(0).get();
    case EndpointRole::broker:
      return channels.at(1).get();
    case EndpointRole::render:
      return channels.at(2).get();
    }
    return -1;
  }

  [[nodiscard]] ReceivedMessage
  receive(std::span<const EndpointRole> roles, std::size_t maximum_payload,
          Deadline deadline, bool fair, ReceiveMode mode);

  [[nodiscard]] bool
  set_readiness_interests(ReadinessInterests requested) noexcept {
    if (!readiness || !valid_mask(requested.read) ||
        !valid_mask(requested.write))
      return false;
    const auto events_for = [](ReadinessInterests interests,
                               EndpointRole role) {
      std::uint32_t events = 0;
      if (mask_contains(interests.read, role)) events |= EPOLLIN;
      if (mask_contains(interests.write, role)) events |= EPOLLOUT;
      if (events != 0) events |= EPOLLHUP | EPOLLERR;
      return events;
    };
    for (std::size_t index = 0; index < channels.size(); ++index) {
      const auto role = static_cast<EndpointRole>(index);
      const std::uint32_t old_events = events_for(readiness_interests, role);
      const std::uint32_t new_events = events_for(requested, role);
      if (old_events == new_events) continue;
      epoll_event event{.events = new_events, .data = {.u64 = index}};
      const int operation = old_events == 0   ? EPOLL_CTL_ADD
                            : new_events == 0 ? EPOLL_CTL_DEL
                                              : EPOLL_CTL_MOD;
      if (epoll_ctl(readiness.get(), operation, channels[index].get(),
                    new_events == 0 ? nullptr : &event) < 0) {
        // A partial epoll update cannot be rolled back reliably. Drop all
        // process and channel authority rather than retain divergent state.
        schedule_termination(false);
        return false;
      }
    }
    readiness_interests = requested;
    return true;
  }

  void schedule_termination(bool allow_graceful_exit) noexcept {
    if (!termination.begin()) return;
    accepting = false;
    readiness.reset();
    for (Fd &channel_descriptor : channels) {
      channel_descriptor.reset();
    }
    if (cleanup) {
      cleanup->worker_pidfd = worker_pidfd.release();
      cleanup->allow_graceful_exit = allow_graceful_exit;
      reaper->submit(std::move(cleanup));
    } else {
      detail::complete_reap(completion, false);
    }
  }

  [[nodiscard]] bool terminate(Deadline deadline) noexcept {
    schedule_termination(true);
    std::unique_lock lock(completion->mutex);
    if (!completion->completed)
      completion->ready.wait_until(
          lock, deadline, [this] { return completion->completed; });
    if (completion->completed) termination.complete(completion->succeeded);
    return termination.succeeded();
  }

  ~Impl() { schedule_termination(false); }
};

Worker::Worker(std::unique_ptr<Impl> implementation)
    : implementation_(std::move(implementation)) {}

Worker::Worker(Worker &&) noexcept = default;
Worker &Worker::operator=(Worker &&) noexcept = default;
Worker::~Worker() = default;

const LaunchIdentity &Worker::identity() const {
  return implementation_->identity;
}

ReceivedMessage Worker::Impl::receive(std::span<const EndpointRole> roles,
                                      std::size_t maximum_payload,
                                      Deadline deadline, bool fair,
                                      ReceiveMode mode) {
  const bool nonblocking = mode == ReceiveMode::nonblocking;
  ReceivedMessage output;
  if (!accepting || roles.size() > channels.size() ||
      maximum_payload == 0 ||
      maximum_payload > kTransportPacketHardLimit) {
    output.failure = ReceiveFailure::invalid_role;
    return output;
  }
  std::array<pollfd, 4> polled{};
  std::array<EndpointRole, 3> lane_map{};
  for (std::size_t index = 0; index < roles.size(); ++index) {
    const int endpoint = channel(roles[index]);
    if (endpoint < 0) {
      output.failure = ReceiveFailure::invalid_role;
      return output;
    }
    polled[index] = {.fd = endpoint, .events = POLLIN, .revents = 0};
    lane_map[index] = roles[index];
  }
  if (!nonblocking && std::chrono::steady_clock::now() >= deadline) {
    output.status = ReceiveStatus::would_block;
    output.failure = ReceiveFailure::timeout;
    return output;
  }
  const std::size_t pidfd_index = roles.size();
  polled[pidfd_index] =
      {.fd = worker_pidfd.get(), .events = POLLIN, .revents = 0};
  int ready = -1;
  do {
    ready = poll(polled.data(), pidfd_index + 1,
                 nonblocking ? 0 : milliseconds_remaining(deadline));
  } while (ready < 0 && errno == EINTR &&
           !nonblocking && std::chrono::steady_clock::now() < deadline);
  if (ready == 0) {
    output.status = ReceiveStatus::would_block;
    output.failure = nonblocking ? ReceiveFailure::none
                                 : ReceiveFailure::timeout;
    return output;
  }
  if (ready < 0 && nonblocking && errno == EINTR) {
    output.status = ReceiveStatus::would_block;
    output.failure = ReceiveFailure::none;
    return output;
  }
  if (ready < 0) {
    output.failure = ReceiveFailure::io_error;
    return output;
  }
  if (polled[pidfd_index].revents != 0 &&
      !pidfd_has_exited(polled[pidfd_index].revents)) {
    output.failure = ReceiveFailure::pidfd_unusable;
    return output;
  }
  if (pidfd_has_exited(polled[pidfd_index].revents)) {
    output.status = ReceiveStatus::peer_closed;
    output.failure = ReceiveFailure::worker_exited;
    return output;
  }

  std::optional<std::size_t> selected;
  for (std::size_t offset = 0; offset < 3 && !selected; ++offset) {
    const std::size_t desired = fair ? (next_receive_lane + offset) % 3 : offset;
    for (std::size_t index = 0; index < roles.size(); ++index) {
      if (role_index(lane_map[index]) == desired &&
          (polled[index].revents & POLLIN) != 0 &&
          (polled[index].revents & ~(POLLIN | POLLHUP)) == 0) {
        selected = index;
        break;
      }
    }
  }
  if (!selected && roles.empty()) {
    output.status = ReceiveStatus::would_block;
    output.failure = ReceiveFailure::timeout;
    return output;
  }
  if (!selected) {
    output.failure = ReceiveFailure::io_error;
    return output;
  }
  const int endpoint = polled[*selected].fd;
  output.role = lane_map[*selected];

  output.payload.resize(maximum_payload);
  iovec vector{.iov_base = output.payload.data(),
               .iov_len = output.payload.size()};
  alignas(cmsghdr) std::array<std::byte, CMSG_SPACE(sizeof(ucred)) +
                                             CMSG_SPACE(
                                                 kMaximumTransportDescriptors *
                                                 sizeof(int))>
      control{};
  msghdr message{};
  message.msg_iov = &vector;
  message.msg_iovlen = 1;
  message.msg_control = control.data();
  message.msg_controllen = control.size();
  const ssize_t received =
      recvmsg(endpoint, &message, MSG_CMSG_CLOEXEC | MSG_TRUNC | MSG_DONTWAIT);
  if (received < 0) {
    output.payload.clear();
    if (errno == EAGAIN || errno == EWOULDBLOCK) {
      output.status = ReceiveStatus::would_block;
      output.failure = nonblocking ? ReceiveFailure::none
                                   : ReceiveFailure::timeout;
    } else {
      output.failure = ReceiveFailure::io_error;
    }
    return output;
  }
  output.payload.resize(std::min<std::size_t>(
      static_cast<std::size_t>(received), maximum_payload));
  std::optional<ucred> credentials;
  bool malformed = false;
  constexpr std::size_t maximum_descriptors =
      kMaximumTransportDescriptors;
  for (cmsghdr *header = CMSG_FIRSTHDR(&message); header != nullptr;
       header = CMSG_NXTHDR(&message, header)) {
    if (header->cmsg_level != SOL_SOCKET) {
      malformed = true;
      continue;
    }
    if (header->cmsg_type == SCM_CREDENTIALS) {
      if (header->cmsg_len != CMSG_LEN(sizeof(ucred)) || credentials) {
        malformed = true;
      } else {
        ucred value{};
        std::memcpy(&value, CMSG_DATA(header), sizeof(value));
        credentials = value;
      }
      continue;
    }
    if (header->cmsg_type == SCM_RIGHTS) {
      if (header->cmsg_len < CMSG_LEN(0)) {
        malformed = true;
        continue;
      }
      const auto descriptor_bytes = header->cmsg_len - CMSG_LEN(0);
      const auto count = descriptor_bytes / sizeof(int);
      if (descriptor_bytes % sizeof(int) != 0 ||
          output.descriptors.size() + count > maximum_descriptors)
        malformed = true;
      for (std::size_t index = 0; index < count; ++index) {
        int descriptor = -1;
        std::memcpy(&descriptor,
                    reinterpret_cast<const std::byte *>(CMSG_DATA(header)) +
                        index * sizeof(int),
                    sizeof(descriptor));
        if (descriptor >= 0) output.descriptors.emplace_back(descriptor);
        else malformed = true;
      }
      continue;
    }
    malformed = true;
  }
  if ((message.msg_flags & (MSG_TRUNC | MSG_CTRUNC)) != 0 ||
      static_cast<std::size_t>(received) > maximum_payload) {
    output.failure = ReceiveFailure::truncated;
  } else if (malformed || !credentials) {
    output.failure = ReceiveFailure::malformed_ancillary;
  } else if (credentials->pid != identity.outer_worker_pid ||
             credentials->uid != identity.outer_uid ||
             credentials->gid != identity.outer_gid) {
    output.failure = ReceiveFailure::credential_mismatch;
  } else if (pidfd_state(worker_pidfd.get()) != PidfdState::alive) {
    output.status = ReceiveStatus::peer_closed;
    output.failure = ReceiveFailure::worker_exited;
  } else {
    output.status = ReceiveStatus::message;
    if (fair) next_receive_lane = (role_index(output.role) + 1) % 3;
    return output;
  }
  output.payload.clear();
  output.descriptors.clear();
  return output;
}

ReceivedMessage Worker::receive(EndpointRole role,
                                PacketSizeLimit maximum_packet,
                                Deadline deadline) {
  if (!implementation_ ||
      !mask_contains(implementation_->readiness_interests.read, role)) {
    return {.payload = {},
            .descriptors = {},
            .role = role,
            .status = ReceiveStatus::fatal,
            .failure = ReceiveFailure::invalid_role};
  }
  const std::array roles = {role};
  return implementation_->receive(roles, maximum_packet.bytes, deadline,
                                  false, ReceiveMode::blocking);
}

ReceivedMessage Worker::receive_any(PacketSizeLimit maximum_packet,
                                    Deadline deadline) {
  if (!implementation_)
    return {.payload = {},
            .descriptors = {},
            .role = EndpointRole::control,
            .status = ReceiveStatus::fatal,
            .failure = ReceiveFailure::invalid_role};
  return receive_any(maximum_packet, deadline,
                     implementation_->readiness_interests.read);
}

ReceivedMessage Worker::receive_any(PacketSizeLimit maximum_packet,
                                    Deadline deadline,
                                    EndpointMask allowed_reads) {
  return receive_any_impl(maximum_packet, deadline, allowed_reads,
                          ReceiveMode::blocking);
}

ReceivedMessage Worker::try_receive_any(PacketSizeLimit maximum_packet,
                                        EndpointMask allowed_reads) {
  return receive_any_impl(maximum_packet, Deadline::max(), allowed_reads,
                          ReceiveMode::nonblocking);
}

ReceivedMessage Worker::receive_any_impl(PacketSizeLimit maximum_packet,
                                         Deadline deadline,
                                         EndpointMask allowed_reads,
                                         ReceiveMode mode) {
  if (!implementation_)
    return {.payload = {},
            .descriptors = {},
            .role = EndpointRole::control,
            .status = ReceiveStatus::fatal,
            .failure = ReceiveFailure::invalid_role};
  if (!valid_packet_limit(maximum_packet) || !valid_mask(allowed_reads) ||
      !mask_is_subset(allowed_reads,
                      implementation_->readiness_interests.read))
    return {.payload = {},
            .descriptors = {},
            .role = EndpointRole::control,
            .status = ReceiveStatus::fatal,
            .failure = ReceiveFailure::invalid_role};
  std::array<EndpointRole, 3> roles{};
  std::size_t count = 0;
  for (const EndpointRole role : {EndpointRole::control, EndpointRole::broker,
                                  EndpointRole::render}) {
    if (mask_contains(allowed_reads, role)) roles[count++] = role;
  }
  return implementation_->receive(std::span(roles).first(count),
                                  maximum_packet.bytes, deadline, true,
                                  mode);
}

ReceivedMessage Worker::receive(EndpointRole role, std::size_t maximum_payload,
                                Deadline deadline) {
  if (maximum_payload > v1_packet_limit(role))
    return {.payload = {},
            .descriptors = {},
            .role = role,
            .status = ReceiveStatus::fatal,
            .failure = ReceiveFailure::invalid_role};
  return receive(role, PacketSizeLimit{maximum_payload}, deadline);
}

ReceivedMessage Worker::receive_any(std::size_t maximum_payload,
                                    Deadline deadline) {
  constexpr std::size_t maximum_v1_packet =
      omarchy::plugin::wire::kHeaderSizeV1 +
      omarchy::plugin::wire::payload_cap(
          omarchy::plugin::wire::EndpointRole::broker);
  if (maximum_payload == 0 || maximum_payload > maximum_v1_packet)
    return {.payload = {},
            .descriptors = {},
            .role = EndpointRole::control,
            .status = ReceiveStatus::fatal,
            .failure = ReceiveFailure::invalid_role};
  return receive_any(maximum_payload, deadline, EndpointMask::all);
}

ReceivedMessage Worker::receive_any(std::size_t maximum_payload,
                                    Deadline deadline, EndpointMask allowed) {
  constexpr std::size_t maximum_v1_packet =
      omarchy::plugin::wire::kHeaderSizeV1 +
      omarchy::plugin::wire::payload_cap(
          omarchy::plugin::wire::EndpointRole::broker);
  if (maximum_payload == 0 || maximum_payload > maximum_v1_packet)
    return {.payload = {},
            .descriptors = {},
            .role = EndpointRole::control,
            .status = ReceiveStatus::fatal,
            .failure = ReceiveFailure::invalid_role};
  if (!implementation_ || !valid_mask(allowed))
    return {.payload = {},
            .descriptors = {},
            .role = EndpointRole::control,
            .status = ReceiveStatus::fatal,
            .failure = ReceiveFailure::invalid_role};
  ReadinessInterests interests = implementation_->readiness_interests;
  interests.read = allowed;
  if (!implementation_->set_readiness_interests(interests))
    return {.payload = {},
            .descriptors = {},
            .role = EndpointRole::control,
            .status = ReceiveStatus::fatal,
            .failure = ReceiveFailure::invalid_role};
  return receive_any(PacketSizeLimit{maximum_payload}, deadline, allowed);
}

ReceivedMessage Worker::receive(EndpointRole role, std::size_t maximum_payload,
                                std::chrono::milliseconds timeout) {
  if (timeout.count() < 0)
    return {.payload = {},
            .descriptors = {},
            .role = role,
            .status = ReceiveStatus::fatal,
            .failure = ReceiveFailure::invalid_role};
  return receive(role, maximum_payload,
                 std::chrono::steady_clock::now() + timeout);
}

SendStatus Worker::try_send(EndpointRole role,
                            std::span<const std::byte> payload,
                            PacketSizeLimit maximum_packet,
                            std::span<const int> descriptors) noexcept {
  if (!implementation_) return SendStatus::peer_closed;
  const int endpoint = implementation_->channel(role);
  if (payload.empty() || maximum_packet.bytes == 0 ||
      maximum_packet.bytes > kTransportPacketHardLimit ||
      payload.size() > maximum_packet.bytes ||
      descriptors.size() > kMaximumTransportDescriptors || endpoint < 0) {
    return SendStatus::fatal;
  }
  if (!implementation_->accepting) return SendStatus::peer_closed;
  const auto process_state = pidfd_state(implementation_->worker_pidfd.get());
  if (process_state == PidfdState::exited) return SendStatus::peer_closed;
  if (process_state != PidfdState::alive) return SendStatus::fatal;
  for (const int descriptor : descriptors) {
    if (descriptor < 0 || fcntl(descriptor, F_GETFD) < 0) {
      return SendStatus::fatal;
    }
  }
  iovec vector{.iov_base = const_cast<std::byte *>(payload.data()),
               .iov_len = payload.size()};
  alignas(cmsghdr)
      std::array<std::byte,
                 CMSG_SPACE(kMaximumTransportDescriptors * sizeof(int))>
          control{};
  msghdr message{};
  message.msg_iov = &vector;
  message.msg_iovlen = 1;
  if (!descriptors.empty()) {
    message.msg_control = control.data();
    message.msg_controllen = control.size();
    cmsghdr *header = CMSG_FIRSTHDR(&message);
    header->cmsg_level = SOL_SOCKET;
    header->cmsg_type = SCM_RIGHTS;
    header->cmsg_len = CMSG_LEN(descriptors.size_bytes());
    message.msg_controllen = CMSG_SPACE(descriptors.size_bytes());
    std::memcpy(CMSG_DATA(header), descriptors.data(), descriptors.size_bytes());
  }
  const ssize_t sent = sendmsg(endpoint, &message, MSG_NOSIGNAL | MSG_DONTWAIT);
  if (sent == static_cast<ssize_t>(payload.size())) return SendStatus::complete;
  if (sent < 0 &&
      (errno == EAGAIN || errno == EWOULDBLOCK || errno == ENOBUFS))
    return SendStatus::would_block;
  if (sent < 0 &&
      (errno == EPIPE || errno == ECONNRESET || errno == ENOTCONN))
    return SendStatus::peer_closed;
  return SendStatus::fatal;
}

SendStatus Worker::try_send(EndpointRole role,
                            std::span<const std::byte> payload,
                            std::span<const int> descriptors) noexcept {
  return try_send(role, payload, PacketSizeLimit{v1_packet_limit(role)},
                  descriptors);
}

bool Worker::send(EndpointRole role, std::span<const std::byte> payload,
                  PacketSizeLimit maximum_packet) {
  return try_send(role, payload, maximum_packet) == SendStatus::complete;
}

bool Worker::send(EndpointRole role, std::span<const std::byte> payload) {
  return try_send(role, payload) == SendStatus::complete;
}

bool Worker::send_with_descriptors(EndpointRole role,
                                   std::span<const std::byte> payload,
                                   PacketSizeLimit maximum_packet,
                                   std::span<const int> descriptors) {
  return try_send(role, payload, maximum_packet, descriptors) ==
         SendStatus::complete;
}

bool Worker::send_with_descriptors(EndpointRole role,
                                   std::span<const std::byte> payload,
                                   std::span<const int> descriptors) {
  return try_send(role, payload, descriptors) == SendStatus::complete;
}

bool Worker::alive() const {
  return implementation_->accepting &&
         pidfd_state(implementation_->worker_pidfd.get()) == PidfdState::alive;
}

int Worker::readiness_fd() const noexcept {
  return implementation_ ? implementation_->readiness.get() : -1;
}

bool Worker::set_receive_mask(EndpointMask allowed) noexcept {
  if (!implementation_) return false;
  ReadinessInterests interests = implementation_->readiness_interests;
  interests.read = allowed;
  return implementation_->set_readiness_interests(interests);
}

bool Worker::set_readiness_interests(ReadinessInterests interests) noexcept {
  return implementation_ &&
         implementation_->set_readiness_interests(interests);
}

std::string Worker::take_standard_error() {
  std::string result;
  if (!implementation_ || !implementation_->standard_error)
    return result;
  const int descriptor = implementation_->standard_error.get();
  const int flags = fcntl(descriptor, F_GETFL);
  if (flags < 0 || fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) < 0)
    return result;
  std::array<char, 1024> buffer{};
  while (result.size() < 8192) {
    const auto count = read(descriptor, buffer.data(),
                            std::min(buffer.size(), 8192 - result.size()));
    if (count > 0) result.append(buffer.data(), static_cast<std::size_t>(count));
    else if (count < 0 && errno == EINTR) continue;
    else break;
  }
  return result;
}

bool Worker::terminate(Deadline deadline) noexcept {
  return implementation_->terminate(deadline);
}

bool Worker::terminate(std::chrono::milliseconds timeout) noexcept {
  if (timeout.count() < 0) return false;
  return terminate(std::chrono::steady_clock::now() + timeout);
}

bool Worker::terminate() {
  if (!implementation_) return false;
  if (!implementation_->cleanup)
    return terminate(std::chrono::steady_clock::now());
  const auto timeouts = implementation_->cleanup->timeouts;
  const auto timeout = std::chrono::seconds(
      timeouts.graceful_shutdown_seconds +
      2 * timeouts.forced_teardown_seconds + 1);
  return terminate(
      std::chrono::duration_cast<std::chrono::milliseconds>(timeout));
}

namespace {

[[nodiscard]] bool append_basic_property(sd_bus_message *message,
                                         const char *name,
                                         const char *signature,
                                         const void *value) {
  return sd_bus_message_open_container(message, 'r', "sv") >= 0 &&
         sd_bus_message_append_basic(message, 's', name) >= 0 &&
         sd_bus_message_open_container(message, 'v', signature) >= 0 &&
         sd_bus_message_append_basic(message, signature[0], value) >= 0 &&
         sd_bus_message_close_container(message) >= 0 &&
         sd_bus_message_close_container(message) >= 0;
}

[[nodiscard]] bool append_pid_property(sd_bus_message *message,
                                       pid_t monitor_pid, pid_t worker_pid) {
  const std::array<std::uint32_t, 2> pids = {
      static_cast<std::uint32_t>(monitor_pid),
      static_cast<std::uint32_t>(worker_pid)};
  if (sd_bus_message_open_container(message, 'r', "sv") < 0 ||
      sd_bus_message_append_basic(message, 's', "PIDs") < 0 ||
      sd_bus_message_open_container(message, 'v', "au") < 0 ||
      sd_bus_message_open_container(message, 'a', "u") < 0) {
    return false;
  }
  for (const std::uint32_t pid : pids) {
    if (sd_bus_message_append_basic(message, 'u', &pid) < 0) {
      return false;
    }
  }
  return sd_bus_message_close_container(message) >= 0 &&
         sd_bus_message_close_container(message) >= 0 &&
         sd_bus_message_close_container(message) >= 0;
}

class SystemdResourceScope final : public ResourceScopeController {
public:
  ~SystemdResourceScope() override {
    sd_bus_unref(cleanup_bus_);
    sd_bus_unref(bus_);
  }

  bool probe(Deadline deadline, std::string &error) override {
    std::unique_lock lock(mutex_, std::defer_lock);
    if (!lock.try_lock_until(deadline)) {
      error = "systemd user manager lock deadline expired";
      return false;
    }
    return probe_locked(deadline, error);
  }

  bool prepare_cleanup(Deadline deadline, std::string &error) override {
    std::unique_lock lock(cleanup_mutex_, std::defer_lock);
    if (!lock.try_lock_until(deadline)) {
      error = "systemd cleanup bus lock deadline expired";
      return false;
    }
    if (cleanup_failed_) {
      error = "systemd cleanup bus is unusable";
      return false;
    }
    if (cleanup_bus_ != nullptr) {
      if (sd_bus_is_open(cleanup_bus_) > 0) return true;
      cleanup_failed_ = true;
      error = "systemd cleanup bus became unusable";
      return false;
    }
    if (std::chrono::steady_clock::now() >= deadline) {
      error = "systemd cleanup bus setup deadline expired";
      return false;
    }
    if (sd_bus_open_user(&cleanup_bus_) < 0 ||
        std::chrono::steady_clock::now() >= deadline) {
      sd_bus_unref(cleanup_bus_);
      cleanup_bus_ = nullptr;
      error = "systemd cleanup bus is unavailable before launch";
      return false;
    }
    return true;
  }

  AttachResult attach(std::string_view unit, pid_t monitor_pid,
                      pid_t worker_pid, const sandbox::SandboxPlan &plan,
                      Deadline deadline, std::string &error) override {
    std::unique_lock lock(mutex_, std::defer_lock);
    if (!lock.try_lock_until(deadline)) {
      error = "systemd user manager lock deadline expired";
      return {};
    }
    if (!probe_locked(deadline, error)) return {};
    return attach_locked(unit, monitor_pid, worker_pid, plan, deadline, error);
  }

  void kill(std::string_view unit, Deadline deadline) noexcept override {
    cleanup_unit(unit, true, deadline);
  }

  void remove(std::string_view unit, Deadline deadline) noexcept override {
    cleanup_unit(unit, false, deadline);
  }

private:
  bool probe_locked(Deadline deadline, std::string &error) {
    const auto remaining = std::chrono::duration_cast<std::chrono::microseconds>(
        deadline - std::chrono::steady_clock::now());
    if (remaining.count() <= 0) {
      error = "systemd user manager deadline expired";
      return false;
    }
    if (bus_ != nullptr) {
      return true;
    }
    if (sd_bus_open_user(&bus_) < 0) {
      error = "systemd user manager bus is unavailable";
      bus_ = nullptr;
      return false;
    }
    if (sd_bus_set_method_call_timeout(
            bus_, static_cast<std::uint64_t>(remaining.count())) < 0) {
      error = "cannot bound systemd user manager calls";
      sd_bus_unref(bus_);
      bus_ = nullptr;
      return false;
    }
    return true;
  }

  AttachResult attach_locked(std::string_view unit, pid_t monitor_pid,
                             pid_t worker_pid,
                             const sandbox::SandboxPlan &plan,
                             Deadline deadline, std::string &error) {
    const auto call_remaining =
        std::chrono::duration_cast<std::chrono::microseconds>(
            deadline - std::chrono::steady_clock::now());
    if (call_remaining.count() <= 0) {
      error = "resource-scope attachment deadline expired";
      return {};
    }
    sd_bus_message *message = nullptr;
    sd_bus_message *reply = nullptr;
    sd_bus_error bus_error = SD_BUS_ERROR_NULL;
    const std::string unit_name(unit);
    const char *mode = "fail";
    const char *description = "Omarchy sandboxed plugin worker";
    const char *collect_mode = "inactive-or-failed";
    const auto &resources = plan.resources;
    const std::uint64_t cpu_quota =
        static_cast<std::uint64_t>(resources.cpu_quota_percent) * 10000ULL;
    const std::uint64_t memory_high = resources.memory_high_bytes;
    const std::uint64_t memory_max = resources.memory_max_bytes;
    const std::uint64_t tasks_max = resources.tasks_max;
    const std::uint64_t cpu_weight = resources.cpu_weight;
    const std::uint64_t io_weight = resources.io_weight;

    bool attempted = false;
    bool built =
        sd_bus_message_new_method_call(
            bus_, &message, "org.freedesktop.systemd1",
            "/org/freedesktop/systemd1", "org.freedesktop.systemd1.Manager",
            "StartTransientUnit") >= 0 &&
        sd_bus_message_append_basic(message, 's', unit_name.c_str()) >= 0 &&
        sd_bus_message_append_basic(message, 's', mode) >= 0 &&
        sd_bus_message_open_container(message, 'a', "(sv)") >= 0 &&
        append_basic_property(message, "Description", "s", description) &&
        append_pid_property(message, monitor_pid, worker_pid) &&
        append_basic_property(message, "MemoryHigh", "t", &memory_high) &&
        append_basic_property(message, "MemoryMax", "t", &memory_max) &&
        append_basic_property(message, "TasksMax", "t", &tasks_max) &&
        append_basic_property(message, "CPUQuotaPerSecUSec", "t", &cpu_quota) &&
        append_basic_property(message, "CPUWeight", "t", &cpu_weight) &&
        append_basic_property(message, "IOWeight", "t", &io_weight) &&
        append_basic_property(message, "CollectMode", "s", collect_mode) &&
        sd_bus_message_close_container(message) >= 0 &&
        sd_bus_message_open_container(message, 'a', "(sa(sv))") >= 0 &&
        sd_bus_message_close_container(message) >= 0;
    if (!built) {
      error = "cannot encode transient scope request";
    } else {
      attempted = true;
      const std::uint64_t timeout_usec =
          static_cast<std::uint64_t>(call_remaining.count());
      if (sd_bus_call(bus_, message, timeout_usec, &bus_error, &reply) < 0) {
        error = bus_error.message != nullptr ? bus_error.message
                                             : "StartTransientUnit failed";
        built = false;
      }
    }
    if (built) {
      const std::string expected = "/" + unit_name;
      bool applied = false;
      while (std::chrono::steady_clock::now() < deadline) {
        std::ifstream cgroup(std::filesystem::path("/proc") /
                             std::to_string(worker_pid) / "cgroup");
        std::string record;
        while (std::getline(cgroup, record)) {
          const auto separator = record.find("::");
          if (separator != std::string::npos &&
              record.substr(separator + 2).ends_with(expected)) {
            applied = true;
            break;
          }
        }
        if (applied) {
          break;
        }
        static_cast<void>(sd_bus_process(bus_, nullptr));
        const auto remaining =
            std::chrono::duration_cast<std::chrono::microseconds>(
                deadline - std::chrono::steady_clock::now());
        if (remaining.count() <= 0) {
          break;
        }
        static_cast<void>(
            sd_bus_wait(bus_, static_cast<std::uint64_t>(std::min<std::int64_t>(
                                  remaining.count(), 10000))));
      }
      if (!applied) {
        error = "transient scope did not bind the worker before its deadline";
        built = false;
      }
    }
    sd_bus_error_free(&bus_error);
    sd_bus_message_unref(reply);
    sd_bus_message_unref(message);
    return {.attached = built, .cleanup_required = attempted};
  }

  void cleanup_unit(std::string_view unit, bool kill,
                    Deadline deadline) noexcept {
    std::unique_lock lock(cleanup_mutex_, std::defer_lock);
    if (!lock.try_lock_until(deadline) || cleanup_failed_ ||
        cleanup_bus_ == nullptr)
      return;
    if (sd_bus_is_open(cleanup_bus_) <= 0) {
      cleanup_failed_ = true;
      return;
    }
    const std::string name(unit);
    sd_bus_error error = SD_BUS_ERROR_NULL;
    sd_bus_message *reply = nullptr;
    const auto remaining = std::chrono::duration_cast<std::chrono::microseconds>(
        deadline - std::chrono::steady_clock::now());
    if (remaining.count() <= 0 ||
        sd_bus_set_method_call_timeout(
            cleanup_bus_, static_cast<std::uint64_t>(remaining.count())) < 0)
      return;
    int call_result = 0;
    if (kill) {
      call_result = sd_bus_call_method(
          cleanup_bus_, "org.freedesktop.systemd1",
          "/org/freedesktop/systemd1", "org.freedesktop.systemd1.Manager",
          "KillUnit", &error, &reply, "ssi", name.c_str(), "all", SIGKILL);
    } else {
      call_result = sd_bus_call_method(
          cleanup_bus_, "org.freedesktop.systemd1",
          "/org/freedesktop/systemd1", "org.freedesktop.systemd1.Manager",
          "StopUnit", &error, &reply, "ss", name.c_str(), "replace");
    }
    if (call_result == -ENOTCONN || call_result == -ECONNRESET ||
        call_result == -EPIPE)
      cleanup_failed_ = true;
    sd_bus_error_free(&error);
    sd_bus_message_unref(reply);
  }

  std::timed_mutex mutex_;
  sd_bus *bus_ = nullptr;
  std::timed_mutex cleanup_mutex_;
  sd_bus *cleanup_bus_ = nullptr;
  bool cleanup_failed_ = false;
};

struct LaunchCleanup {
  std::shared_ptr<ProcessScopeReaper> reaper;
  std::unique_ptr<CleanupJob> job;
  bool armed = true;

  ~LaunchCleanup() {
    if (!armed || !job || job->monitor_pid <= 0) return;
    job->allow_graceful_exit = false;
    reaper->submit(std::move(job));
  }
};

} // namespace

std::shared_ptr<ResourceScopeController>
make_systemd_resource_scope_controller() {
  return std::make_shared<SystemdResourceScope>();
}

struct Supervisor::Impl {
  std::string bwrap_path;
  std::string worker_path;
  std::shared_ptr<ResourceScopeController> resource_scope;
  std::shared_ptr<ProcessScopeReaper> reaper;
  bool packaged_selection = true;
};

namespace {
[[nodiscard]] std::shared_ptr<ProcessScopeReaper>
shared_process_reaper(bool force_start_failure) {
  if (force_start_failure)
    return std::make_shared<ProcessScopeReaper>(true);
  // The handle is created while constructing a Supervisor, and its thread is
  // started by launch before fork. Worker destruction therefore only submits
  // to an already-running process-lifetime service.
  static const auto reaper = std::make_shared<ProcessScopeReaper>(false);
  return reaper;
}
} // namespace

Supervisor::Supervisor(std::unique_ptr<Impl> implementation)
    : implementation_(std::move(implementation)) {}
Supervisor::Supervisor(Supervisor &&) noexcept = default;
Supervisor &Supervisor::operator=(Supervisor &&) noexcept = default;
Supervisor::~Supervisor() = default;

Supervisor Supervisor::packaged() {
  return Supervisor(std::make_unique<Impl>(
      std::string(kSystemBwrapPath), std::string(kPackagedWorkerPath),
      make_systemd_resource_scope_controller(),
      shared_process_reaper(false), true));
}

Supervisor Supervisor::forTestOnly(
    std::string bwrap_path, std::string worker_path,
    std::shared_ptr<ResourceScopeController> resource_scope,
    bool force_reaper_start_failure) {
  return Supervisor(std::make_unique<Impl>(std::move(bwrap_path),
                                           std::move(worker_path),
                                           std::move(resource_scope),
                                           shared_process_reaper(
                                               force_reaper_start_failure),
                                           false));
}

bool Supervisor::prerequisites(std::string &error) const {
  return prerequisites(std::chrono::steady_clock::now() +
                           std::chrono::seconds(2),
                       error);
}

bool Supervisor::prerequisites(Deadline deadline, std::string &error) const {
  if (std::chrono::steady_clock::now() >= deadline) {
    error = "launcher preflight deadline expired";
    return false;
  }
  if (!implementation_->resource_scope) {
    error = "resource scope controller is absent";
    return false;
  }
  if (implementation_->packaged_selection &&
      (implementation_->bwrap_path != kSystemBwrapPath ||
       implementation_->worker_path != kPackagedWorkerPath)) {
    error = "packaged executable selection changed";
    return false;
  }
  if (!trusted_executable(
          implementation_->bwrap_path, implementation_->packaged_selection,
          error) ||
      !trusted_executable(implementation_->worker_path,
                          implementation_->packaged_selection, error) ||
      !kernel_prerequisites(error) ||
      !implementation_->resource_scope->probe(deadline, error) ||
      !implementation_->resource_scope->prepare_cleanup(deadline, error) ||
      std::chrono::steady_clock::now() >= deadline) {
    return false;
  }
  return true;
}

LaunchResult Supervisor::launch(const TrustedLaunchRequest &request) const {
  const sandbox::SandboxPlan plan =
      implementation_->packaged_selection
          ? sandbox::build_plan()
          : sandbox::build_test_plan_for_worker(implementation_->worker_path);
  return launch(request, std::chrono::steady_clock::now() +
                             std::chrono::seconds(plan.timeouts.launch_seconds));
}

LaunchResult Supervisor::launch(const TrustedLaunchRequest &request,
                                Deadline deadline) const {
  LaunchResult result;
  if (std::chrono::steady_clock::now() >= deadline) {
    result.failure = LaunchFailure::startup_timeout;
    result.detail = "launch deadline expired before preflight";
    return result;
  }
  if (!canonical_plugin_id(request.plugin_id) ||
      !canonical_digest(request.revision_sha256) || request.generation == 0) {
    result.failure = LaunchFailure::invalid_trusted_record;
    result.detail = "launch identity is not canonical";
    return result;
  }
  if (!implementation_->reaper->start(result.detail)) {
    result.failure = LaunchFailure::resource_scope_unavailable;
    return result;
  }
  if (!prerequisites(deadline, result.detail)) {
    result.failure = std::chrono::steady_clock::now() >= deadline
                         ? LaunchFailure::startup_timeout
                         : LaunchFailure::missing_kernel_prerequisite;
    return result;
  }
  if (!normalize_standard_descriptors(result.detail)) {
    result.failure = LaunchFailure::descriptor_setup_failed;
    return result;
  }
  if (std::chrono::steady_clock::now() >= deadline) {
    result.failure = LaunchFailure::startup_timeout;
    result.detail = "launch deadline expired during descriptor preflight";
    return result;
  }

  Fd revision =
      duplicate_directory(request.revision_directory_fd, true, result.detail);
  if (!revision) {
    result.failure = LaunchFailure::invalid_revision_descriptor;
    return result;
  }
  Fd state = duplicate_directory(request.private_state_directory_fd, false,
                                 result.detail);
  if (!state) {
    result.failure = LaunchFailure::invalid_state_descriptor;
    return result;
  }

  sandbox::SandboxPlan plan =
      implementation_->packaged_selection
          ? sandbox::build_plan()
          : sandbox::build_test_plan_for_worker(implementation_->worker_path);
  Fd seccomp = compile_seccomp(plan.seccomp, result.detail);
  if (!seccomp) {
    result.failure = LaunchFailure::seccomp_compile_failed;
    return result;
  }
  if (std::chrono::steady_clock::now() >= deadline) {
    result.failure = LaunchFailure::startup_timeout;
    result.detail = "launch deadline expired during sandbox preflight";
    return result;
  }

  try {
    Fd standard_input(open("/dev/null", O_RDONLY | O_CLOEXEC));
    Pipe standard_output = make_pipe();
    Pipe standard_error = make_pipe();
    Channel control = make_channel();
    Channel broker = make_channel();
    Channel render = make_channel();
    Pipe status = make_pipe();
    Pipe barrier = make_pipe();
    Pipe exec_error = make_pipe();
    if (!standard_input) {
      throw std::runtime_error("cannot open child standard input");
    }

    LaunchCleanup cleanup{
        .reaper = implementation_->reaper,
        .job = std::make_unique<CleanupJob>()};
    cleanup.job->completion = std::make_shared<ReapCompletion>();
    cleanup.job->resource_scope = implementation_->resource_scope;
    cleanup.job->timeouts = plan.timeouts;
    cleanup.job->scope.reserve(192);
    auto worker = std::make_unique<Worker::Impl>();

    const std::array sources = {standard_input.get(),
                                standard_output.write.get(),
                                standard_error.write.get(),
                                control.worker.get(),
                                broker.worker.get(),
                                render.worker.get(),
                                status.write.get(),
                                barrier.read.get(),
                                seccomp.get(),
                                revision.get(),
                                state.get(),
                                exec_error.write.get()};

    const pid_t monitor_pid = fork();
    if (monitor_pid < 0) {
      result.failure = LaunchFailure::fork_failed;
      result.detail = "fork failed";
      return result;
    }
    if (monitor_pid == 0) {
      child_exec(implementation_->bwrap_path, std::move(plan), sources);
    }

    cleanup.job->monitor_pid = monitor_pid;
    cleanup.job->scope = plan.process.transient_scope_prefix +
                    request.plugin_id.substr(0, 48) + "-" +
                    request.revision_sha256.substr(0, 12) + "-" +
                    std::to_string(request.generation) + "-m" +
                    std::to_string(monitor_pid) + ".scope";
    cleanup.job->monitor_pidfd = open_pidfd(monitor_pid).release();

    control.worker.reset();
    broker.worker.reset();
    render.worker.reset();
    standard_output.write.reset();
    standard_error.write.reset();
    status.write.reset();
    barrier.read.reset();
    exec_error.write.reset();
    revision.reset();
    state.reset();
    seccomp.reset();
    standard_input.reset();

    if (cleanup.job->monitor_pidfd < 0) {
      result.failure = LaunchFailure::pidfd_failed;
      result.detail = "cannot bind Bubblewrap monitor pidfd";
      return result;
    }

    const int current_flags = fcntl(status.read.get(), F_GETFL);
    const int exec_flags = fcntl(exec_error.read.get(), F_GETFL);
    if (current_flags < 0 || exec_flags < 0 ||
        fcntl(status.read.get(), F_SETFL, current_flags | O_NONBLOCK) < 0 ||
        fcntl(exec_error.read.get(), F_SETFL, exec_flags | O_NONBLOCK) < 0) {
      result.failure = LaunchFailure::descriptor_setup_failed;
      result.detail = "cannot make launch handshakes nonblocking";
      return result;
    }

    std::string status_buffer;
    unsigned records = 0;
    std::optional<pid_t> worker_pid;
    std::optional<int> observed_exit;
    bool exec_succeeded = false;
    while (!worker_pid) {
      const int remaining = milliseconds_remaining(deadline);
      if (remaining == 0) {
        result.failure = LaunchFailure::startup_timeout;
        result.detail = "Bubblewrap status deadline expired";
        return result;
      }
      std::array<pollfd, 3> polled = {
          pollfd{.fd = status.read.get(), .events = POLLIN, .revents = 0},
          pollfd{.fd = exec_error.read.get(), .events = POLLIN, .revents = 0},
          pollfd{.fd = cleanup.job->monitor_pidfd,
                 .events = POLLIN,
                 .revents = 0}};
      if (poll(polled.data(), polled.size(), remaining) <= 0) {
        continue;
      }
      if (polled.at(2).revents != 0) {
        result.failure = polled.at(2).revents == POLLIN
                             ? LaunchFailure::worker_exited_early
                             : LaunchFailure::pidfd_failed;
        result.detail = "Bubblewrap monitor exited before identity binding";
        return result;
      }
      if ((polled.at(0).revents & ~(POLLIN | POLLHUP)) != 0 ||
          (polled.at(1).revents & ~(POLLIN | POLLHUP)) != 0) {
        result.failure = LaunchFailure::status_protocol_failed;
        result.detail = "launch handshake descriptor became unusable";
        return result;
      }
      if ((polled.at(1).revents & POLLIN) != 0) {
        int child_errno = 0;
        const ssize_t count =
            read(exec_error.read.get(), &child_errno, sizeof(child_errno));
        if (count == sizeof(child_errno)) {
          result.failure = LaunchFailure::exec_failed;
          result.detail = "execve(/usr/bin/bwrap) failed: " +
                          std::string(std::strerror(child_errno));
          return result;
        }
      }
      if ((polled.at(1).revents & POLLHUP) != 0) {
        exec_succeeded = true;
      }
      if ((polled.at(0).revents & (POLLIN | POLLHUP)) == 0) {
        continue;
      }
      std::array<char, 1024> chunk{};
      while (true) {
        const ssize_t count =
            read(status.read.get(), chunk.data(), chunk.size());
        if (count > 0) {
          exec_succeeded = true;
          status_buffer.append(chunk.data(), static_cast<std::size_t>(count));
          if ((status_buffer.find('\n') == std::string::npos &&
               status_buffer.size() > kMaximumStatusLine) ||
              status_buffer.size() >
                  kMaximumStatusLine * kMaximumStatusRecords) {
            result.failure = LaunchFailure::status_protocol_failed;
            result.detail = "Bubblewrap status stream exceeded its bound";
            return result;
          }
          continue;
        }
        if (count < 0 && errno != EAGAIN && errno != EWOULDBLOCK) {
          result.failure = LaunchFailure::status_protocol_failed;
          result.detail = "Bubblewrap status read failed";
          return result;
        }
        break;
      }
      std::size_t newline = 0;
      while ((newline = status_buffer.find('\n')) != std::string::npos) {
        if (newline > kMaximumStatusLine) {
          result.failure = LaunchFailure::status_protocol_failed;
          result.detail = "Bubblewrap status line exceeded its bound";
          return result;
        }
        const std::string line = status_buffer.substr(0, newline);
        status_buffer.erase(0, newline + 1);
        if (++records > kMaximumStatusRecords) {
          result.failure = LaunchFailure::status_protocol_failed;
          result.detail = "too many Bubblewrap status records";
          return result;
        }
        const auto record = parse_status_record(line);
        if (!record) {
          result.failure = LaunchFailure::status_protocol_failed;
          result.detail = "malformed Bubblewrap status JSON";
          return result;
        }
        if (record->child_pid) {
          if (worker_pid) {
            result.failure = LaunchFailure::status_protocol_failed;
            result.detail = "duplicate authoritative child PID";
            return result;
          }
          worker_pid = record->child_pid;
        }
        if (record->exit_code) {
          if (observed_exit) {
            result.failure = LaunchFailure::status_protocol_failed;
            result.detail = "duplicate authoritative exit code";
            return result;
          }
          observed_exit = record->exit_code;
        }
      }
      if (status_buffer.size() > kMaximumStatusLine) {
        result.failure = LaunchFailure::status_protocol_failed;
        result.detail = "Bubblewrap partial status line exceeded its bound";
        return result;
      }
    }
    if (!exec_succeeded || observed_exit) {
      result.failure = LaunchFailure::worker_exited_early;
      result.detail = "worker exited during Bubblewrap identity binding";
      return result;
    }

    cleanup.job->worker_pidfd = open_pidfd(*worker_pid).release();
    if (cleanup.job->worker_pidfd < 0 ||
        pidfd_state(cleanup.job->worker_pidfd) != PidfdState::alive) {
      result.failure = LaunchFailure::pidfd_failed;
      result.detail = "reported worker PID was not live and bindable";
      return result;
    }
    const auto attachment = implementation_->resource_scope->attach(
        cleanup.job->scope, monitor_pid, *worker_pid, plan, deadline,
        result.detail);
    cleanup.job->scope_attached = attachment.cleanup_required;
    if (!attachment.attached) {
      result.failure = std::chrono::steady_clock::now() >= deadline
                           ? LaunchFailure::startup_timeout
                           : LaunchFailure::resource_scope_failed;
      return result;
    }
    if (std::chrono::steady_clock::now() >= deadline) {
      result.failure = LaunchFailure::startup_timeout;
      result.detail = "launch deadline expired before startup barrier release";
      return result;
    }
    if (pidfd_state(cleanup.job->worker_pidfd) != PidfdState::alive) {
      result.failure = LaunchFailure::worker_exited_early;
      result.detail = "worker exited before startup barrier release";
      return result;
    }

    Fd readiness(epoll_create1(EPOLL_CLOEXEC));
    const std::array readiness_sources = {
        control.trusted.get(), broker.trusted.get(), render.trusted.get(),
        cleanup.job->worker_pidfd};
    if (!readiness) {
      result.failure = LaunchFailure::descriptor_setup_failed;
      result.detail = "cannot create aggregate worker readiness descriptor";
      return result;
    }
    for (std::size_t index = 0; index < readiness_sources.size(); ++index) {
      epoll_event event{.events = EPOLLIN | EPOLLHUP | EPOLLERR,
                        .data = {.u64 = index}};
      if (epoll_ctl(readiness.get(), EPOLL_CTL_ADD, readiness_sources[index],
                    &event) < 0) {
        result.failure = LaunchFailure::descriptor_setup_failed;
        result.detail = "cannot bind aggregate worker readiness descriptor";
        return result;
      }
    }
    barrier.write.reset();
    if (std::chrono::steady_clock::now() >= deadline ||
        pidfd_state(cleanup.job->worker_pidfd) != PidfdState::alive) {
      result.failure = std::chrono::steady_clock::now() >= deadline
                           ? LaunchFailure::startup_timeout
                           : LaunchFailure::worker_exited_early;
      result.detail = "worker lost authority during startup barrier release";
      return result;
    }

    worker->identity = {.plugin_id = request.plugin_id,
                        .revision_sha256 = request.revision_sha256,
                        .generation = request.generation,
                        .outer_worker_pid = *worker_pid,
                        .outer_uid = getuid(),
                        .outer_gid = getgid()};
    worker->channels = {std::move(control.trusted), std::move(broker.trusted),
                        std::move(render.trusted)};
    worker->worker_pidfd = Fd(cleanup.job->worker_pidfd);
    cleanup.job->worker_pidfd = -1;
    worker->standard_output = std::move(standard_output.read);
    worker->standard_error = std::move(standard_error.read);
    worker->readiness = std::move(readiness);
    worker->reaper = cleanup.reaper;
    worker->completion = cleanup.job->completion;
    worker->cleanup = std::move(cleanup.job);
    cleanup.armed = false;
    result.worker = std::unique_ptr<Worker>(new Worker(std::move(worker)));
    return result;
  } catch (const std::exception &error) {
    result.failure = LaunchFailure::descriptor_setup_failed;
    result.detail = error.what();
    return result;
  }
}


} // namespace omarchy::plugin_runtime::launcher
