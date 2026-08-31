#include "omarchy/plugin_runtime/provider_host/provider_host.hpp"

#include "manifest_contract.hpp"

#include <dirent.h>
#include <fcntl.h>
#include <linux/close_range.h>
#include <poll.h>
#include <sched.h>
#include <signal.h>
#include <sys/prctl.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

#include <algorithm>
#include <array>
#include <cerrno>
#include <charconv>
#include <climits>
#include <condition_variable>
#include <limits>
#include <map>
#include <mutex>
#include <new>
#include <optional>
#include <string>
#include <thread>
#include <utility>

namespace omarchy::plugin_runtime::provider_host {
namespace {

constexpr std::uint32_t kProtocolMagic = 0x4f505256; // OPRV
constexpr std::uint8_t kProtocolVersion = 1;
constexpr std::uint8_t kRequestType = 1;
constexpr std::uint8_t kResponseType = 2;
constexpr std::size_t kHeaderBytes = 20;
constexpr std::size_t kMaximumProfileBytes = 16 * 1024;
constexpr std::size_t kMaximumExecutableBytes = 128 * 1024 * 1024;
constexpr std::size_t kMaximumArguments = 16;
constexpr std::size_t kMaximumArgumentBytes = 512;
constexpr std::size_t kMaximumProfiles = 128;
constexpr std::uint64_t kProviderMemoryHighBytes = 96ULL * 1024ULL * 1024ULL;
constexpr std::uint64_t kProviderMemoryMaxBytes = 128ULL * 1024ULL * 1024ULL;
constexpr std::uint64_t kProviderTasksMax = 8;
constexpr std::uint64_t kProviderCpuQuotaUsec = 250000;
constexpr std::uint64_t kProviderCpuWeight = 10;
constexpr std::uint64_t kProviderIoWeight = 10;

class Descriptor final {
public:
  Descriptor() = default;
  explicit Descriptor(int value) : value_(value) {}
  Descriptor(const Descriptor &) = delete;
  Descriptor &operator=(const Descriptor &) = delete;
  Descriptor(Descriptor &&other) noexcept
      : value_(std::exchange(other.value_, -1)) {}
  Descriptor &operator=(Descriptor &&other) noexcept {
    if (this != &other) {
      reset();
      value_ = std::exchange(other.value_, -1);
    }
    return *this;
  }
  ~Descriptor() { reset(); }
  [[nodiscard]] int get() const noexcept { return value_; }
  [[nodiscard]] explicit operator bool() const noexcept { return value_ >= 0; }
  int release() noexcept { return std::exchange(value_, -1); }
  void reset(int value = -1) noexcept {
    if (value_ >= 0)
      ::close(value_);
    value_ = value;
  }

private:
  int value_ = -1;
};

void put_u16(std::vector<std::byte> &bytes, std::uint16_t value) {
  bytes.push_back(static_cast<std::byte>(value >> 8));
  bytes.push_back(static_cast<std::byte>(value));
}

void put_u32(std::vector<std::byte> &bytes, std::uint32_t value) {
  for (int shift = 24; shift >= 0; shift -= 8)
    bytes.push_back(static_cast<std::byte>(value >> shift));
}

void put_u64(std::vector<std::byte> &bytes, std::uint64_t value) {
  for (int shift = 56; shift >= 0; shift -= 8)
    bytes.push_back(static_cast<std::byte>(value >> shift));
}

bool get_u32(std::span<const std::byte> bytes, std::size_t offset,
             std::uint32_t &value) {
  if (offset + 4 > bytes.size())
    return false;
  value = 0;
  for (std::size_t index = 0; index < 4; ++index)
    value = (value << 8) | std::to_integer<unsigned char>(bytes[offset + index]);
  return true;
}

bool get_u64(std::span<const std::byte> bytes, std::size_t offset,
             std::uint64_t &value) {
  if (offset + 8 > bytes.size())
    return false;
  value = 0;
  for (std::size_t index = 0; index < 8; ++index)
    value = (value << 8) | std::to_integer<unsigned char>(bytes[offset + index]);
  return true;
}

bool put_text(std::vector<std::byte> &bytes, std::string_view value) {
  if (value.size() > std::numeric_limits<std::uint16_t>::max())
    return false;
  put_u16(bytes, static_cast<std::uint16_t>(value.size()));
  const auto raw = std::as_bytes(std::span(value.data(), value.size()));
  bytes.insert(bytes.end(), raw.begin(), raw.end());
  return true;
}

bool secure_directory(const struct stat &metadata,
                      std::uint32_t trusted_uid) noexcept {
  return S_ISDIR(metadata.st_mode) && metadata.st_uid == trusted_uid &&
         (metadata.st_mode & 0022) == 0;
}

enum class RootResult { opened, absent, rejected };

RootResult open_root(int filesystem_root_fd,
                     std::span<const std::string_view> components,
                     std::uint32_t trusted_uid, Descriptor &output) {
  Descriptor current(::openat(filesystem_root_fd, ".",
                              O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW));
  struct stat metadata {};
  if (!current || ::fstat(current.get(), &metadata) < 0 ||
      !secure_directory(metadata, trusted_uid))
    return RootResult::rejected;
  for (const auto component : components) {
    if (component.empty() || component == "." || component == ".." ||
        component.find('/') != std::string_view::npos)
      return RootResult::rejected;
    const std::string name(component);
    Descriptor next(::openat(current.get(), name.c_str(),
                             O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW));
    if (!next)
      return errno == ENOENT ? RootResult::absent : RootResult::rejected;
    if (::fstat(next.get(), &metadata) < 0 ||
        !secure_directory(metadata, trusted_uid))
      return RootResult::rejected;
    current = std::move(next);
  }
  output = std::move(current);
  return RootResult::opened;
}

std::optional<std::string> read_bounded(int fd, std::size_t maximum) {
  std::string result;
  std::array<char, 16 * 1024> buffer{};
  if (::lseek(fd, 0, SEEK_SET) < 0)
    return std::nullopt;
  while (true) {
    const auto count = ::read(fd, buffer.data(), buffer.size());
    if (count < 0) {
      if (errno == EINTR)
        continue;
      return std::nullopt;
    }
    if (count == 0)
      break;
    if (result.size() + static_cast<std::size_t>(count) > maximum)
      return std::nullopt;
    result.append(buffer.data(), static_cast<std::size_t>(count));
  }
  if (::lseek(fd, 0, SEEK_SET) < 0)
    return std::nullopt;
  return result;
}

bool canonical_absolute_path(std::string_view path) {
  if (path.size() < 2 || path.size() > 4096 || path.front() != '/' ||
      path.back() == '/' || path.find('\0') != std::string_view::npos)
    return false;
  std::size_t begin = 1;
  while (begin < path.size()) {
    const auto end = path.find('/', begin);
    const auto component = path.substr(
        begin, end == std::string_view::npos ? path.size() - begin : end - begin);
    if (component.empty() || component == "." || component == "..")
      return false;
    begin = end == std::string_view::npos ? path.size() : end + 1;
  }
  return true;
}

Descriptor open_executable(int filesystem_root_fd, std::string_view path,
                           std::uint32_t trusted_uid) {
  if (!canonical_absolute_path(path))
    return {};
  Descriptor current(::openat(filesystem_root_fd, ".",
                              O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW));
  struct stat metadata {};
  if (!current || ::fstat(current.get(), &metadata) < 0 ||
      !secure_directory(metadata, trusted_uid))
    return {};
  std::size_t begin = 1;
  while (begin < path.size()) {
    const auto end = path.find('/', begin);
    const auto component = path.substr(
        begin, end == std::string_view::npos ? path.size() - begin : end - begin);
    const std::string name(component);
    const bool leaf = end == std::string_view::npos;
    Descriptor next(::openat(current.get(), name.c_str(),
                             (leaf ? O_RDONLY | O_NONBLOCK : O_RDONLY | O_DIRECTORY) |
                                 O_CLOEXEC | O_NOFOLLOW));
    if (!next || ::fstat(next.get(), &metadata) < 0)
      return {};
    if (leaf) {
      if (!S_ISREG(metadata.st_mode) || metadata.st_uid != trusted_uid ||
          (metadata.st_mode & 0022) != 0 || (metadata.st_mode & 0100) == 0 ||
          (metadata.st_mode & (S_ISUID | S_ISGID)) != 0 ||
          metadata.st_size < 0 ||
          static_cast<std::uint64_t>(metadata.st_size) > kMaximumExecutableBytes)
        return {};
      return next;
    }
    if (!secure_directory(metadata, trusted_uid))
      return {};
    current = std::move(next);
    begin = end + 1;
  }
  return {};
}

std::map<std::string, std::vector<std::string>>
parse_document(std::string_view document) {
  std::map<std::string, std::vector<std::string>> fields;
  std::size_t begin = 0;
  while (begin < document.size()) {
    const auto end = document.find('\n', begin);
    auto line = document.substr(
        begin, end == std::string_view::npos ? document.size() - begin : end - begin);
    if (!line.empty() && line.back() == '\r')
      line.remove_suffix(1);
    if (!line.empty() && line.front() != '#') {
      const auto separator = line.find('=');
      if (separator == std::string_view::npos || separator == 0 ||
          separator + 1 >= line.size())
        return {};
      fields[std::string(line.substr(0, separator))].emplace_back(
          line.substr(separator + 1));
    }
    begin = end == std::string_view::npos ? document.size() : end + 1;
  }
  return fields;
}

bool single(const std::map<std::string, std::vector<std::string>> &fields,
            std::string_view key, std::string &output) {
  const auto found = fields.find(std::string(key));
  if (found == fields.end() || found->second.size() != 1)
    return false;
  output = found->second.front();
  return true;
}

std::uint32_t parse_u32(std::string_view value) {
  std::uint32_t result = 0;
  const auto [end, error] =
      std::from_chars(value.data(), value.data() + value.size(), result);
  return error == std::errc{} && end == value.data() + value.size() ? result : 0;
}

bool same_process(const ProviderCatalog::Profile &left,
                  const ProviderCatalog::Profile &right);

} // namespace

struct ProviderCatalog::Profile final {
  definitions::AdapterBinding binding;
  std::string group;
  std::string executable_path;
  definitions::Digest executable_digest;
  std::vector<std::string> arguments;
  Descriptor executable;
};

namespace {

bool same_process(const ProviderCatalog::Profile &left,
                  const ProviderCatalog::Profile &right) {
  return left.executable_path == right.executable_path &&
         left.executable_digest == right.executable_digest &&
         left.arguments == right.arguments;
}

std::optional<ProviderCatalog::Profile>
load_profile(int root_fd, std::string_view name, int filesystem_root_fd,
             std::uint32_t trusted_uid, CatalogError &error) {
  if (name.size() < 9 || !name.ends_with(".profile"))
    return std::nullopt;
  const std::string filename(name);
  Descriptor profile(::openat(root_fd, filename.c_str(),
                              O_RDONLY | O_NONBLOCK | O_CLOEXEC | O_NOFOLLOW));
  struct stat metadata {};
  if (!profile || ::fstat(profile.get(), &metadata) < 0 ||
      !S_ISREG(metadata.st_mode) || metadata.st_uid != trusted_uid ||
      (metadata.st_mode & 0022) != 0 || metadata.st_size < 0 ||
      static_cast<std::size_t>(metadata.st_size) > kMaximumProfileBytes) {
    error = CatalogError::profile_rejected;
    return std::nullopt;
  }
  const auto document = read_bounded(profile.get(), kMaximumProfileBytes);
  if (!document) {
    error = CatalogError::profile_rejected;
    return std::nullopt;
  }
  const auto fields = parse_document(*document);
  std::string schema, adapter_class, contract_digest, abi, group, executable_path,
      executable_digest;
  if (fields.empty() || !single(fields, "schema", schema) || schema != "1" ||
      !single(fields, "adapter-class", adapter_class) ||
      !single(fields, "contract-digest", contract_digest) ||
      !single(fields, "abi-version", abi) || !single(fields, "group", group) ||
      !single(fields, "executable", executable_path) ||
      !single(fields, "executable-sha256", executable_digest) ||
      !definitions::canonical_identifier(adapter_class) ||
      !definitions::canonical_identifier(group) ||
      !definitions::valid_digest(contract_digest) ||
      !definitions::valid_digest(executable_digest) || parse_u32(abi) == 0) {
    error = CatalogError::profile_rejected;
    return std::nullopt;
  }
  for (const auto &[key, values] : fields) {
    if (key != "schema" && key != "adapter-class" &&
        key != "contract-digest" && key != "abi-version" && key != "group" &&
        key != "executable" && key != "executable-sha256" && key != "arg") {
      error = CatalogError::profile_rejected;
      return std::nullopt;
    }
    if (key != "arg" && values.size() != 1) {
      error = CatalogError::profile_rejected;
      return std::nullopt;
    }
  }
  std::vector<std::string> arguments;
  if (const auto found = fields.find("arg"); found != fields.end()) {
    if (found->second.size() > kMaximumArguments ||
        std::ranges::any_of(found->second, [](const auto &argument) {
          return argument.empty() || argument.size() > kMaximumArgumentBytes ||
                 argument.find('\0') != std::string::npos;
        })) {
      error = CatalogError::profile_rejected;
      return std::nullopt;
    }
    arguments = found->second;
  }
  auto executable =
      open_executable(filesystem_root_fd, executable_path, trusted_uid);
  const auto executable_bytes =
      executable ? read_bounded(executable.get(), kMaximumExecutableBytes)
                 : std::nullopt;
  if (!executable_bytes ||
      plugins::manifest::sha256_hex(*executable_bytes) != executable_digest) {
    error = CatalogError::executable_rejected;
    return std::nullopt;
  }
  try {
    return ProviderCatalog::Profile{
        .binding = {.adapter_class = definitions::Name(adapter_class),
                    .contract_digest = definitions::Digest(contract_digest),
                    .abi_version = parse_u32(abi)},
        .group = std::move(group),
        .executable_path = std::move(executable_path),
        .executable_digest = definitions::Digest(executable_digest),
        .arguments = std::move(arguments),
        .executable = std::move(executable)};
  } catch (...) {
    error = CatalogError::profile_rejected;
    return std::nullopt;
  }
}

bool load_directory(int directory_fd, int filesystem_root_fd,
                    std::uint32_t trusted_uid,
                    std::vector<ProviderCatalog::Profile> &profiles,
                    CatalogError &error) {
  Descriptor duplicate(::fcntl(directory_fd, F_DUPFD_CLOEXEC, 3));
  DIR *directory = duplicate ? ::fdopendir(duplicate.release()) : nullptr;
  if (!directory) {
    error = CatalogError::root_rejected;
    return false;
  }
  std::vector<std::string> names;
  errno = 0;
  while (const auto *entry = ::readdir(directory)) {
    const std::string_view name(entry->d_name);
    if (name != "." && name != ".." && name.ends_with(".profile"))
      names.emplace_back(name);
    if (names.size() > kMaximumProfiles) {
      error = CatalogError::profile_rejected;
      ::closedir(directory);
      return false;
    }
  }
  const int read_error = errno;
  ::closedir(directory);
  if (read_error != 0) {
    error = CatalogError::root_rejected;
    return false;
  }
  std::ranges::sort(names);
  for (const auto &name : names) {
    auto profile = load_profile(directory_fd, name, filesystem_root_fd,
                                trusted_uid, error);
    if (!profile)
      return false;
    if (std::ranges::any_of(profiles, [&](const auto &existing) {
          return existing.binding == profile->binding;
        })) {
      error = CatalogError::duplicate_binding;
      return false;
    }
    if (std::ranges::any_of(profiles, [&](const auto &existing) {
          return existing.group == profile->group &&
                 !same_process(existing, *profile);
        })) {
      error = CatalogError::profile_rejected;
      return false;
    }
    profiles.push_back(std::move(*profile));
  }
  return true;
}

struct Process final {
  pid_t pid = -1;
  Descriptor pidfd;
  Descriptor channel;
  std::string scope;
  bool scope_cleanup_required = false;
  bool failed = false;
  std::uint64_t next_correlation = 1;

  Process() = default;
  Process(const Process &) = delete;
  Process &operator=(const Process &) = delete;
  Process(Process &&) noexcept = default;
  Process &operator=(Process &&) noexcept = default;
};

bool stop(Process &process,
          launcher::ResourceScopeController &resource_scope,
          launcher::Deadline deadline) noexcept {
  process.channel.reset();
  bool scope_terminated = true;
  if (process.scope_cleanup_required && !process.scope.empty()) {
    std::string cleanup_error;
    scope_terminated = resource_scope.terminate_scope(
        process.scope, deadline, cleanup_error);
  }
  if (process.pid > 0) {
    if (process.pidfd) {
      if (::syscall(SYS_pidfd_send_signal, process.pidfd.get(), SIGKILL,
                    nullptr, 0U) < 0 &&
          errno != ESRCH)
        (void)::kill(process.pid, SIGKILL);
    } else {
      (void)::kill(process.pid, SIGKILL);
    }
    while (true) {
      const pid_t waited = ::waitpid(process.pid, nullptr, WNOHANG);
      if (waited == process.pid || (waited < 0 && errno == ECHILD)) {
        process.pid = -1;
        process.pidfd.reset();
        break;
      }
      if (waited < 0 && errno != EINTR)
        break;
      if (std::chrono::steady_clock::now() >= deadline)
        break;
      pollfd ready{.fd = process.pidfd.get(), .events = POLLIN, .revents = 0};
      const auto remaining =
          std::chrono::duration_cast<std::chrono::milliseconds>(
              deadline - std::chrono::steady_clock::now() +
              std::chrono::milliseconds(1));
      if (process.pidfd &&
          ::poll(&ready, 1, static_cast<int>(remaining.count())) < 0 &&
          errno != EINTR)
        break;
      if (!process.pidfd)
        ::sched_yield();
    }
  }
  if (scope_terminated) {
    process.scope.clear();
    process.scope_cleanup_required = false;
  }
  process.failed = true;
  return scope_terminated && process.pid <= 0;
}

Descriptor open_pidfd(pid_t pid) noexcept {
  while (true) {
    const auto result = static_cast<int>(::syscall(SYS_pidfd_open, pid, 0U));
    if (result >= 0)
      return Descriptor(result);
    if (errno != EINTR)
      return {};
  }
}

std::string scope_name(const permissions::ActivationBinding &activation,
                       std::string_view group, pid_t pid) {
  return "app-omarchy-plugin-provider-" +
         std::string(activation.plugin.view().substr(0, 40)) + "-" +
         std::string(activation.revision.view().substr(0, 12)) + "-g" +
         std::to_string(activation.generation) + "-" +
         std::string(group.substr(0, 32)) + "-p" + std::to_string(pid) +
         ".scope";
}

bool start(Process &process, const ProviderCatalog::Profile &profile,
           const permissions::ActivationBinding &activation,
           launcher::ResourceScopeController &resource_scope,
           std::chrono::milliseconds timeout) {
  std::vector<char *> arguments;
  arguments.reserve(profile.arguments.size() + 2);
  arguments.push_back(const_cast<char *>(profile.executable_path.c_str()));
  for (const auto &argument : profile.arguments)
    arguments.push_back(const_cast<char *>(argument.c_str()));
  arguments.push_back(nullptr);
  Descriptor executable(
      ::fcntl(profile.executable.get(), F_DUPFD_CLOEXEC, 4));
  if (!executable)
    return false;
  int pair[2] = {-1, -1};
  if (::socketpair(AF_UNIX, SOCK_SEQPACKET | SOCK_CLOEXEC, 0, pair) < 0)
    return false;
  Descriptor parent(pair[0]);
  Descriptor child(pair[1]);
  int barrier_descriptors[2] = {-1, -1};
  if (::socketpair(AF_UNIX, SOCK_SEQPACKET | SOCK_CLOEXEC, 0,
                   barrier_descriptors) < 0)
    return false;
  Descriptor barrier_read(barrier_descriptors[0]);
  Descriptor barrier_write(barrier_descriptors[1]);
  std::array<char *, 5> environment{
      const_cast<char *>("PATH=/usr/bin"), const_cast<char *>("LANG=C"),
      const_cast<char *>("LC_ALL=C"), const_cast<char *>("HOME=/nonexistent"),
      nullptr};
  const pid_t pid = ::fork();
  if (pid < 0)
    return false;
  if (pid == 0) {
    barrier_write.reset();
    const int child_fd = child.get();
    parent.reset();
    if (child_fd != 3 && ::dup2(child_fd, 3) != 3)
      _exit(126);
    if (child_fd != 3)
      child.reset();
    if (::fcntl(3, F_SETFD, 0) < 0)
      _exit(126);
    const int null_fd = ::open("/dev/null", O_RDWR | O_CLOEXEC | O_NOFOLLOW);
    if (null_fd < 0)
      _exit(126);
    for (int target = STDIN_FILENO; target <= STDERR_FILENO; ++target) {
      if (null_fd != target && ::dup2(null_fd, target) != target)
        _exit(126);
    }
    if (null_fd > STDERR_FILENO)
      ::close(null_fd);
    if (::prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) < 0 ||
        ::syscall(SYS_close_range, 4U, UINT_MAX, CLOSE_RANGE_CLOEXEC) < 0)
      _exit(126);
    unsigned char release = 0;
    ssize_t released = -1;
    do {
      released = ::recv(barrier_read.get(), &release, sizeof(release), 0);
    } while (released < 0 && errno == EINTR);
    if (released != static_cast<ssize_t>(sizeof(release)) || release != 0xa5)
      _exit(126);
    (void)::syscall(SYS_execveat, executable.get(), "",
                    arguments.data(), environment.data(), AT_EMPTY_PATH);
    _exit(127);
  }
  child.reset();
  barrier_read.reset();
  process.pid = pid;
  process.channel = std::move(parent);
  auto pidfd = open_pidfd(pid);
  if (!pidfd) {
    stop(process, resource_scope, std::chrono::steady_clock::now() + timeout);
    return false;
  }
  process.pidfd = std::move(pidfd);
  process.scope = scope_name(activation, profile.group, pid);
  // Cleanup is conservative once direct child authority exists. Even an
  // exception or ambiguous resource-manager reply tears down this exact unit.
  process.scope_cleanup_required = true;
  const std::array<pid_t, 1> pids{pid};
  const launcher::ProcessScopeRequest scope_request{
      .unit = process.scope,
      .description = "Omarchy trusted plugin provider",
      .pids = pids,
      .resources = {.memory_high_bytes = kProviderMemoryHighBytes,
                    .memory_max_bytes = kProviderMemoryMaxBytes,
                    .tasks_max = kProviderTasksMax,
                    .cpu_quota_per_second_usec = kProviderCpuQuotaUsec,
                    .cpu_weight = kProviderCpuWeight,
                    .io_weight = kProviderIoWeight}};
  std::string scope_error;
  const auto attached = resource_scope.attach(
      scope_request, std::chrono::steady_clock::now() + timeout, scope_error);
  if (!attached.attached) {
    stop(process, resource_scope, std::chrono::steady_clock::now() + timeout);
    return false;
  }
  const unsigned char release = 0xa5;
  iovec release_part{.iov_base = const_cast<unsigned char *>(&release),
                     .iov_len = sizeof(release)};
  msghdr release_message{};
  release_message.msg_iov = &release_part;
  release_message.msg_iovlen = 1;
  ssize_t released = -1;
  do {
    released = ::sendmsg(barrier_write.get(), &release_message, MSG_NOSIGNAL);
  } while (released < 0 && errno == EINTR);
  barrier_write.reset();
  if (released != static_cast<ssize_t>(sizeof(release))) {
    stop(process, resource_scope, std::chrono::steady_clock::now() + timeout);
    return false;
  }
  return true;
}

bool wait_ready(int fd, short events, std::chrono::milliseconds timeout) {
  const auto deadline = std::chrono::steady_clock::now() + timeout;
  while (true) {
    const auto now = std::chrono::steady_clock::now();
    if (now >= deadline)
      return false;
    const auto remaining = std::chrono::duration_cast<std::chrono::milliseconds>(
        deadline - now + std::chrono::milliseconds(1));
    pollfd item{.fd = fd, .events = events, .revents = 0};
    const int result = ::poll(&item, 1, static_cast<int>(remaining.count()));
    if (result < 0 && errno == EINTR)
      continue;
    return result == 1 && (item.revents & events) != 0 &&
           (item.revents & (POLLERR | POLLHUP | POLLNVAL)) == 0;
  }
}

ssize_t send_packet(int fd, const void *data, std::size_t size) {
  iovec part{.iov_base = const_cast<void *>(data), .iov_len = size};
  msghdr message{};
  message.msg_iov = &part;
  message.msg_iovlen = 1;
  return ::sendmsg(fd, &message, MSG_NOSIGNAL);
}

ssize_t receive_packet(int fd, void *data, std::size_t size) {
  iovec part{.iov_base = data, .iov_len = size};
  msghdr message{};
  message.msg_iov = &part;
  message.msg_iovlen = 1;
  return ::recvmsg(fd, &message, MSG_TRUNC);
}

std::vector<std::byte>
request_frame(std::uint64_t correlation,
              const definitions::AdapterBinding &binding,
              const definitions::AuthorizedDynamicRequest &request) {
  std::vector<std::byte> body;
  body.reserve(256 + request.payload.size());
  if (!put_text(body, binding.adapter_class.view()) ||
      !put_text(body, binding.contract_digest.view()))
    return {};
  put_u32(body, binding.abi_version);
  if (!put_text(body, request.operation) ||
      !put_text(body, request.demand_scope))
    return {};
  put_u32(body, static_cast<std::uint32_t>(request.payload.size()));
  body.insert(body.end(), request.payload.begin(), request.payload.end());
  if (body.size() > kMaximumProviderPayload)
    return {};
  std::vector<std::byte> frame;
  frame.reserve(kHeaderBytes + body.size());
  put_u32(frame, kProtocolMagic);
  frame.push_back(static_cast<std::byte>(kProtocolVersion));
  frame.push_back(static_cast<std::byte>(kRequestType));
  put_u16(frame, 0);
  put_u64(frame, correlation);
  put_u32(frame, static_cast<std::uint32_t>(body.size()));
  frame.insert(frame.end(), body.begin(), body.end());
  return frame;
}

bool exchange(Process &process, const ProviderCatalog::Profile &profile,
              const permissions::ActivationBinding &activation,
              launcher::ResourceScopeController &resource_scope,
              const definitions::AdapterBinding &binding,
              const definitions::AuthorizedDynamicRequest &request,
              std::span<std::byte> response, std::size_t &written,
              std::chrono::milliseconds timeout) noexcept {
  try {
    if (process.failed)
      return false;
    if (process.next_correlation == 0) {
      stop(process, resource_scope,
           std::chrono::steady_clock::now() + timeout);
      return false;
    }
    const auto correlation = process.next_correlation;
    const auto frame = request_frame(correlation, binding, request);
    std::vector<std::byte> incoming(kHeaderBytes + kMaximumProviderPayload + 1);
    if (frame.empty())
      return false;
    if (process.pid <= 0 &&
        !start(process, profile, activation, resource_scope, timeout)) {
      process.failed = true;
      return false;
    }
    ++process.next_correlation;
    if (!wait_ready(process.channel.get(), POLLOUT, timeout) ||
        send_packet(process.channel.get(), frame.data(), frame.size()) !=
            static_cast<ssize_t>(frame.size())) {
      stop(process, resource_scope,
           std::chrono::steady_clock::now() + timeout);
      return false;
    }
    if (!wait_ready(process.channel.get(), POLLIN, timeout)) {
      stop(process, resource_scope,
           std::chrono::steady_clock::now() + timeout);
      return false;
    }
    const auto count =
        receive_packet(process.channel.get(), incoming.data(), incoming.size());
    if (count < static_cast<ssize_t>(kHeaderBytes) ||
        count > static_cast<ssize_t>(incoming.size())) {
      stop(process, resource_scope,
           std::chrono::steady_clock::now() + timeout);
      return false;
    }
    incoming.resize(static_cast<std::size_t>(count));
    std::uint32_t magic = 0;
    std::uint32_t body_size = 0;
    std::uint64_t response_correlation = 0;
    if (!get_u32(incoming, 0, magic) || magic != kProtocolMagic ||
        std::to_integer<std::uint8_t>(incoming[4]) != kProtocolVersion ||
        std::to_integer<std::uint8_t>(incoming[5]) != kResponseType ||
        std::to_integer<std::uint8_t>(incoming[6]) != 0 ||
        std::to_integer<std::uint8_t>(incoming[7]) != 0 ||
        !get_u64(incoming, 8, response_correlation) ||
        response_correlation != correlation ||
        !get_u32(incoming, 16, body_size) ||
        body_size + kHeaderBytes != incoming.size() || body_size < 1 ||
        std::to_integer<std::uint8_t>(incoming[kHeaderBytes]) != 0 ||
        body_size - 1 > response.size()) {
      stop(process, resource_scope,
           std::chrono::steady_clock::now() + timeout);
      return false;
    }
    written = body_size - 1;
    std::copy_n(incoming.begin() + kHeaderBytes + 1, written, response.begin());
    return true;
  } catch (...) {
    if (process.pid > 0)
      stop(process, resource_scope,
           std::chrono::steady_clock::now() + timeout);
    return false;
  }
}

} // namespace

ProviderCatalog::ProviderCatalog(std::vector<Profile> profiles)
    : profiles_(std::move(profiles)) {}
ProviderCatalog::~ProviderCatalog() = default;

std::shared_ptr<const ProviderCatalog> ProviderCatalog::load(
    int filesystem_root_fd,
    std::span<const std::string_view> package_components,
    std::span<const std::string_view> admin_components,
    std::uint32_t trusted_uid, CatalogError &error) noexcept {
  error = CatalogError::none;
  try {
    if (::fcntl(filesystem_root_fd, F_GETFD) < 0) {
      error = CatalogError::root_rejected;
      return {};
    }
    std::vector<Profile> profiles;
    for (const auto components : {package_components, admin_components}) {
      Descriptor root;
      const auto result =
          open_root(filesystem_root_fd, components, trusted_uid, root);
      if (result == RootResult::rejected) {
        error = CatalogError::root_rejected;
        return {};
      }
      if (result == RootResult::opened &&
          !load_directory(root.get(), filesystem_root_fd, trusted_uid,
                          profiles, error))
        return {};
    }
    return std::shared_ptr<const ProviderCatalog>(
        new ProviderCatalog(std::move(profiles)));
  } catch (const std::bad_alloc &) {
    error = CatalogError::resource_exhausted;
    return {};
  } catch (...) {
    error = CatalogError::profile_rejected;
    return {};
  }
}

const ProviderCatalog::Profile *ProviderCatalog::find(
    const definitions::AdapterBinding &binding) const noexcept {
  const auto found =
      std::ranges::find(profiles_, binding, &Profile::binding);
  return found == profiles_.end() ? nullptr : &*found;
}

bool ProviderCatalog::available(
    const definitions::AdapterBinding &binding) const noexcept {
  return find(binding) != nullptr;
}

std::size_t ProviderCatalog::size() const noexcept { return profiles_.size(); }

struct ProviderActivation::Impl final {
  Impl(std::shared_ptr<const ProviderCatalog> initial_catalog,
       permissions::ActivationBinding initial_binding,
       std::shared_ptr<launcher::ResourceScopeController> initial_resource_scope,
       std::chrono::milliseconds initial_timeout)
      : catalog(std::move(initial_catalog)), binding(std::move(initial_binding)),
        resource_scope(std::move(initial_resource_scope)),
        timeout(initial_timeout) {}

  std::shared_ptr<const ProviderCatalog> catalog;
  permissions::ActivationBinding binding;
  std::shared_ptr<launcher::ResourceScopeController> resource_scope;
  std::chrono::milliseconds timeout;
  mutable std::mutex mutex;
  std::map<std::string, Process> processes;
  bool cancelled = false;
  std::unique_ptr<Impl> cleanup_next;
};

struct ProviderActivation::CleanupService final {
  [[nodiscard]] static bool cleanup(Impl &implementation) noexcept {
    std::lock_guard lock(implementation.mutex);
    implementation.cancelled = true;
    const auto deadline =
        std::chrono::steady_clock::now() + implementation.timeout;
    bool cleaned = true;
    for (auto &[name, process] : implementation.processes) {
      (void)name;
      cleaned = stop(process, *implementation.resource_scope, deadline) &&
                cleaned;
    }
    return cleaned;
  }

  void retain(std::unique_ptr<Impl> implementation) noexcept {
    {
      std::lock_guard lock(mutex);
      implementation->cleanup_next = std::move(pending);
      pending = std::move(implementation);
    }
    ready.notify_one();
  }

  [[noreturn]] void run() noexcept {
    while (true) {
      std::unique_ptr<Impl> batch;
      {
        std::unique_lock lock(mutex);
        ready.wait(lock, [this] { return pending != nullptr; });
        batch = std::move(pending);
      }

      std::unique_ptr<Impl> retry;
      while (batch) {
        auto current = std::move(batch);
        batch = std::move(current->cleanup_next);
        if (!cleanup(*current)) {
          current->cleanup_next = std::move(retry);
          retry = std::move(current);
        }
      }
      if (retry) {
        std::unique_lock lock(mutex);
        while (retry) {
          auto current = std::move(retry);
          retry = std::move(current->cleanup_next);
          current->cleanup_next = std::move(pending);
          pending = std::move(current);
        }
        // Avoid spinning on a resource manager that is still unavailable.
        ready.wait_for(lock, std::chrono::milliseconds(100));
      }
    }
  }

  std::mutex mutex;
  std::condition_variable ready;
  std::unique_ptr<Impl> pending;
};

ProviderActivation::CleanupService *
ProviderActivation::cleanup_service(bool create) noexcept {
  static std::mutex creation_mutex;
  static CleanupService *service = nullptr;
  std::lock_guard lock(creation_mutex);
  if (service || !create)
    return service;

  auto *candidate = new (std::nothrow) CleanupService;
  if (!candidate)
    return nullptr;
  try {
    std::thread([candidate] { candidate->run(); }).detach();
  } catch (...) {
    delete candidate;
    return nullptr;
  }
  // The detached cleanup authority intentionally lives until process exit.
  service = candidate;
  return service;
}

void ProviderActivation::retain_cleanup(
    std::unique_ptr<Impl> implementation) noexcept {
  auto *service = cleanup_service(false);
  if (!service)
    std::terminate();
  service->retain(std::move(implementation));
}

ProviderActivation::ProviderActivation(
    std::shared_ptr<const ProviderCatalog> catalog,
    permissions::ActivationBinding binding,
    std::shared_ptr<launcher::ResourceScopeController> resource_scope,
    std::chrono::milliseconds timeout)
    : implementation_(std::make_unique<Impl>(
          std::move(catalog), std::move(binding), std::move(resource_scope),
          timeout)) {}

ProviderActivation::~ProviderActivation() {
  if (!cancel())
    retain_cleanup(std::move(implementation_));
}

std::shared_ptr<ProviderActivation> ProviderActivation::create(
    std::shared_ptr<const ProviderCatalog> catalog,
    permissions::ActivationBinding binding, std::chrono::milliseconds timeout) {
  return create(std::move(catalog), std::move(binding),
                launcher::make_systemd_resource_scope_controller(), timeout);
}

std::shared_ptr<ProviderActivation> ProviderActivation::create(
    std::shared_ptr<const ProviderCatalog> catalog,
    permissions::ActivationBinding binding,
    std::shared_ptr<launcher::ResourceScopeController> resource_scope,
    std::chrono::milliseconds timeout) {
  if (!catalog || !resource_scope || binding.generation == 0 ||
      timeout.count() <= 0 ||
      timeout > std::chrono::seconds(5))
    return {};
  const auto deadline = std::chrono::steady_clock::now() + timeout;
  std::string error;
  if (!resource_scope->probe(deadline, error) ||
      !resource_scope->prepare_cleanup(deadline, error))
    return {};
  if (!cleanup_service(true))
    return {};
  return std::shared_ptr<ProviderActivation>(
      new ProviderActivation(std::move(catalog), std::move(binding),
                             std::move(resource_scope), timeout));
}

std::shared_ptr<ProviderRoute>
ProviderActivation::route(const definitions::AdapterBinding &binding) {
  if (!implementation_->catalog->available(binding))
    return {};
  return std::shared_ptr<ProviderRoute>(
      new ProviderRoute(shared_from_this(), binding));
}

bool ProviderActivation::cancel() noexcept {
  if (!implementation_)
    return true;
  return CleanupService::cleanup(*implementation_);
}

bool ProviderActivation::cleanup_pending() const noexcept {
  if (!implementation_)
    return false;
  std::lock_guard lock(implementation_->mutex);
  return std::ranges::any_of(
      implementation_->processes, [](const auto &entry) {
        const auto &process = entry.second;
        return process.pid > 0 || process.scope_cleanup_required;
      });
}

bool ProviderActivation::invoke(
    const definitions::AdapterBinding &binding,
    const definitions::AuthorizedDynamicRequest &request,
    std::span<std::byte> response, std::size_t &written) noexcept {
  written = 0;
  try {
    std::lock_guard lock(implementation_->mutex);
    if (implementation_->cancelled ||
        request.authorization.binding != implementation_->binding ||
        request.authorization.definition.canonical_name.size() == 0 ||
        request.authorization.grant_epoch == 0)
      return false;
    const auto *profile = implementation_->catalog->find(binding);
    if (!profile)
      return false;
    auto &[group, process] =
        *implementation_->processes.try_emplace(profile->group).first;
    (void)group;
    return exchange(process, *profile, implementation_->binding,
                    *implementation_->resource_scope, binding, request,
                    response, written, implementation_->timeout);
  } catch (...) {
    return false;
  }
}

ProviderRoute::ProviderRoute(std::shared_ptr<ProviderActivation> activation,
                             definitions::AdapterBinding binding)
    : activation_(std::move(activation)), binding_(std::move(binding)) {}

const definitions::AdapterBinding &ProviderRoute::binding() const noexcept {
  return binding_;
}

bool ProviderRoute::dispatch(
    const definitions::AuthorizedDynamicRequest &request,
    std::span<std::byte> response, std::size_t &written,
    void *context) noexcept {
  auto *route = static_cast<ProviderRoute *>(context);
  if (!route || !route->activation_)
    return false;
  return route->activation_->invoke(route->binding_, request, response, written);
}

} // namespace omarchy::plugin_runtime::provider_host
