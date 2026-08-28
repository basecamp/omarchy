#include "omarchy/plugin/wire/envelope.hpp"
#include "omarchy/plugin/wire/state.hpp"
#include "omarchy/plugin_runtime/launcher/launcher.h"
#include "omarchy/plugin_runtime/sandbox/policy.h"

#include <dirent.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

#include <array>
#include <algorithm>
#include <cerrno>
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <memory>
#include <set>
#include <stdexcept>
#include <string>
#include <string_view>
#include <thread>
#include <utility>
#include <vector>

namespace {

namespace wire = omarchy::plugin::wire;
namespace launcher = omarchy::plugin_runtime::launcher;
namespace sandbox = omarchy::plugin_runtime::sandbox;

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
  bool truncated = false;

  Received() = default;
  Received(const Received &) = delete;
  Received &operator=(const Received &) = delete;
  Received(Received &&other) noexcept
      : payload(std::move(other.payload)), credentials(other.credentials),
        descriptors(std::move(other.descriptors)),
        has_credentials(other.has_credentials), truncated(other.truncated) {
    other.descriptors.clear();
  }

  ~Received() {
    for (const int descriptor : descriptors) {
      close(descriptor);
    }
  }
};

class UniqueFd {
public:
  explicit UniqueFd(int value = -1) : value_(value) {}
  ~UniqueFd() {
    if (value_ >= 0) {
      close(value_);
    }
  }
  UniqueFd(const UniqueFd &) = delete;
  UniqueFd &operator=(const UniqueFd &) = delete;
  UniqueFd(UniqueFd &&other) noexcept
      : value_(std::exchange(other.value_, -1)) {}
  [[nodiscard]] int get() const { return value_; }
  [[nodiscard]] int release() { return std::exchange(value_, -1); }
  void reset(int value = -1) {
    if (value_ >= 0) {
      close(value_);
    }
    value_ = value;
  }

private:
  int value_ = -1;
};

bool bounded_reap(pid_t pid, int pidfd, int signal_number,
                  int timeout_ms) noexcept {
  if (pid <= 0) {
    return true;
  }
  if (signal_number != 0) {
    if (pidfd >= 0) {
      static_cast<void>(
          syscall(SYS_pidfd_send_signal, pidfd, signal_number, nullptr, 0));
    } else {
      static_cast<void>(kill(pid, signal_number));
    }
  }
  const int attempts = std::max(1, timeout_ms / 10);
  for (int attempt = 0; attempt < attempts; ++attempt) {
    int status = 0;
    const pid_t waited = waitpid(pid, &status, WNOHANG);
    if (waited == pid || (waited < 0 && errno == ECHILD)) {
      return true;
    }
    if (waited < 0 && errno != EINTR) {
      return false;
    }
    std::this_thread::sleep_for(std::chrono::milliseconds(10));
  }
  return false;
}

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
    if (pid > 0) {
      static_cast<void>(bounded_reap(pid, pidfd, SIGKILL, 2000));
    }
    if (pidfd >= 0) {
      close(pidfd);
    }
  }
};

Worker spawn(std::string_view attack) {
  std::array<int, 2> pair{};
  require(socketpair(AF_UNIX, SOCK_SEQPACKET | SOCK_CLOEXEC, 0, pair.data()) ==
              0,
          "attack channel creation failed");
  UniqueFd trusted(pair[0]);
  UniqueFd peer(pair[1]);
  int enabled = 1;
  require(setsockopt(trusted.get(), SOL_SOCKET, SO_PASSCRED, &enabled,
                     sizeof(enabled)) == 0,
          "attack channel credential setup failed");
  const pid_t child = fork();
  require(child >= 0, "malicious worker fork failed");
  if (child == 0) {
    close(trusted.get());
    const int staged = fcntl(peer.get(), F_DUPFD_CLOEXEC, 32);
    if (staged < 0 || dup2(staged, 3) < 0) {
      _exit(120);
    }
    close(staged);
    close(peer.get());
    if (syscall(SYS_close_range, 4U, ~0U, 0U) < 0) {
      _exit(122);
    }
    const std::string argument(attack);
    execl(MALICIOUS_WORKER_PATH, MALICIOUS_WORKER_PATH, argument.c_str(),
          nullptr);
    _exit(121);
  }
  Worker worker;
  worker.channel = trusted.release();
  worker.pid = child;
  peer.reset();
  worker.pidfd = static_cast<int>(syscall(SYS_pidfd_open, child, 0));
  require(worker.pidfd >= 0, "malicious worker pidfd acquisition failed");
  return worker;
}

Received receive(Worker &worker) {
  pollfd ready{.fd = worker.channel, .events = POLLIN, .revents = 0};
  require(poll(&ready, 1, 2000) == 1 && (ready.revents & POLLIN) != 0,
          "malicious worker did not produce its attack");
  std::array<std::byte, 8192> payload{};
  alignas(cmsghdr)
      std::array<std::byte,
                 CMSG_SPACE(sizeof(ucred)) + CMSG_SPACE(sizeof(int) * 4)>
          ancillary{};
  iovec data{.iov_base = payload.data(), .iov_len = payload.size()};
  msghdr message{};
  message.msg_iov = &data;
  message.msg_iovlen = 1;
  message.msg_control = ancillary.data();
  message.msg_controllen = ancillary.size();
  const ssize_t size = recvmsg(worker.channel, &message, MSG_CMSG_CLOEXEC);
  require(size >= 0, "attack receive failed");
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
  received.truncated =
      (message.msg_flags & (MSG_TRUNC | MSG_CTRUNC)) != 0;
  return received;
}

enum class ChannelDecision {
  accepted,
  malformed,
  unexpected_descriptor,
  credential_mismatch,
  truncated,
};

ChannelDecision verify_channel(const Received &received, const Worker &worker,
                               wire::EndpointRole role) {
  if (received.truncated) {
    return ChannelDecision::truncated;
  }
  if (!received.descriptors.empty()) {
    return ChannelDecision::unexpected_descriptor;
  }
  if (!received.has_credentials || received.credentials.pid != worker.pid ||
      received.credentials.uid != getuid() ||
      received.credentials.gid != getgid()) {
    return ChannelDecision::credential_mismatch;
  }
  return wire::decode_packet(received.payload, role)
             ? ChannelDecision::accepted
             : ChannelDecision::malformed;
}

std::set<int> open_fd_set() {
  DIR *directory = opendir("/proc/self/fd");
  require(directory != nullptr, "cannot enumerate trusted descriptors");
  const int enumeration_fd = dirfd(directory);
  std::set<int> result;
  while (const dirent *entry = readdir(directory)) {
    char *end = nullptr;
    const long value = std::strtol(entry->d_name, &end, 10);
    if (*entry->d_name != '\0' && end != nullptr && *end == '\0' &&
        value != enumeration_fd) {
      result.insert(static_cast<int>(value));
    }
  }
  closedir(directory);
  return result;
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
    require(verify_channel(received, worker, wire::EndpointRole::control) ==
                ChannelDecision::unexpected_descriptor,
            "descriptor injection reached fake channel dispatch");
    require(WIFEXITED(finish(worker)),
            "descriptor-injection worker did not exit cleanly");
  }
  for (int attempt = 0; attempt < 16; ++attempt) {
    const auto before = open_fd_set();
    {
      auto worker = spawn("descriptor-flood");
      auto received = receive(worker);
      require(received.truncated && !received.descriptors.empty() &&
                  verify_channel(received, worker,
                                 wire::EndpointRole::control) ==
                      ChannelDecision::truncated,
              "truncated descriptor flood was not quarantined and denied");
      require(WIFEXITED(finish(worker)),
              "descriptor-flood worker did not exit cleanly");
    }
    require(open_fd_set() == before,
            "truncated descriptor flood leaked a received descriptor");
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
    require(verify_channel(received, worker, wire::EndpointRole::control) ==
                ChannelDecision::credential_mismatch,
            "descendant substitution reached fake channel dispatch");
    require(WIFEXITED(finish(worker)),
            "descendant worker did not exit cleanly");
  }
}

class FakeScope final : public launcher::ResourceScopeController {
public:
  bool probe(std::string &) override { return true; }

  bool attach(std::string_view unit, pid_t monitor_pid, pid_t worker_pid,
              const sandbox::SandboxPlan &plan,
              std::chrono::milliseconds timeout,
              std::string &) override {
    require(unit.starts_with("app-omarchy-plugin-worker-") &&
                monitor_pid > 0 && worker_pid > 0 &&
                plan.worker_descriptors == std::vector<int>({3, 4, 5}) &&
                plan.process.descendants_permitted == false &&
                timeout == std::chrono::seconds(5),
            "sandbox launch did not consume the frozen B5 plan");
    unit_ = unit;
    attached = true;
    return true;
  }

  void kill(std::string_view unit) noexcept override {
    if (unit == unit_) {
      ++kills;
    }
  }

  void remove(std::string_view unit) noexcept override {
    if (unit == unit_) {
      ++removes;
    }
  }

  bool attached = false;
  unsigned kills = 0;
  unsigned removes = 0;

private:
  std::string unit_;
};

class SandboxTree {
public:
  SandboxTree() {
    std::array<char, 64> pattern{};
    std::strcpy(pattern.data(), "/tmp/omarchy-c11-sandbox.XXXXXX");
    const char *created = mkdtemp(pattern.data());
    require(created != nullptr, "sandbox fixture root creation failed");
    root_ = created;
    std::filesystem::create_directory(revision());
    std::filesystem::create_directory(state());
    const char *home = std::getenv("HOME");
    const char *runtime = std::getenv("XDG_RUNTIME_DIR");
    const char *wayland = std::getenv("WAYLAND_DISPLAY");
    require(home != nullptr && *home != '\0' && runtime != nullptr &&
                *runtime != '\0' && wayland != nullptr && *wayland != '\0',
            "C11 sandbox proof requires HOME, XDG_RUNTIME_DIR, and WAYLAND_DISPLAY");
    host_home_ = home;
    bus_socket_path_ = std::filesystem::path(runtime) / "bus";
    wayland_socket_path_ = std::filesystem::path(runtime) / wayland;
    struct stat home_status {};
    struct stat bus_status {};
    struct stat wayland_status {};
    require(lstat(host_home_.c_str(), &home_status) == 0 &&
                S_ISDIR(home_status.st_mode) &&
                lstat(bus_socket_path_.c_str(), &bus_status) == 0 &&
                S_ISSOCK(bus_status.st_mode) &&
                lstat(wayland_socket_path_.c_str(), &wayland_status) == 0 &&
                S_ISSOCK(wayland_status.st_mode),
            "actual host home, session bus, or Wayland socket is unavailable");
    std::ofstream(revision() / "fixture")
        << host_home_.string() << '\n'
        << bus_socket_path_.string() << '\n'
        << wayland_socket_path_.string() << '\n';
    const int host_write =
        open((revision() / "fixture").c_str(), O_WRONLY | O_CLOEXEC);
    require(host_write >= 0,
            "host revision fixture is not writable before read-only bind");
    close(host_write);
    require(chmod(revision().c_str(), 0555) == 0,
            "sandbox fixture revision could not be frozen");
  }

  ~SandboxTree() {
    static_cast<void>(chmod(revision().c_str(), 0755));
    std::error_code ignored;
    std::filesystem::remove_all(root_, ignored);
  }

  [[nodiscard]] std::filesystem::path revision() const {
    return root_ / "revision";
  }
  [[nodiscard]] std::filesystem::path state() const { return root_ / "state"; }

private:
  std::filesystem::path root_;
  std::filesystem::path host_home_;
  std::filesystem::path bus_socket_path_;
  std::filesystem::path wayland_socket_path_;
};

struct SandboxProbe {
  std::uint32_t magic = 0;
  std::uint32_t descriptor_mask = 0;
  std::uint32_t exact_descriptors = 0;
  std::uint32_t exact_environment = 0;
  std::uint32_t host_home_absent = 0;
  std::uint32_t bus_socket_absent = 0;
  std::uint32_t wayland_socket_absent = 0;
  std::uint32_t network_denied = 0;
  std::uint32_t descendant_denied = 0;
  std::uint32_t revision_write_denied = 0;
};

void test_standalone_sandbox() {
  require(access("/usr/bin/bwrap", X_OK) == 0,
          "Bubblewrap is required for the C11 standalone sandbox harness");
  SandboxTree tree;
  UniqueFd revision(
      open(tree.revision().c_str(), O_RDONLY | O_DIRECTORY | O_CLOEXEC));
  UniqueFd state(open(tree.state().c_str(), O_RDONLY | O_DIRECTORY | O_CLOEXEC));
  require(revision.get() >= 0 && state.get() >= 0,
          "sandbox fixture directories could not be opened");
  auto scope = std::make_shared<FakeScope>();
  auto supervisor = launcher::Supervisor::forTestOnly(
      "/usr/bin/bwrap", MALICIOUS_WORKER_PATH, scope);
  const launcher::TrustedLaunchRequest request{
      .plugin_id = "org.omarchy.fixture",
      .revision_sha256 = std::string(64, 'a'),
      .generation = 29,
      .revision_directory_fd = revision.get(),
      .private_state_directory_fd = state.get(),
  };
  auto launched = supervisor.launch(request);
  if (!launched) {
    throw std::runtime_error("standalone sandbox launch failed: " +
                             launched.detail);
  }
  require(scope->attached, "worker was released before fake scope attachment");
  const auto message = launched.worker->receive(
      launcher::EndpointRole::control, sizeof(SandboxProbe),
      std::chrono::seconds(2));
  require(static_cast<bool>(message) && message.payload.size() == sizeof(SandboxProbe),
          "sandbox denial certificate was not received from the bound worker");
  SandboxProbe probe{};
  std::memcpy(&probe, message.payload.data(), sizeof(probe));
  require(probe.magic == 0x53425831 && probe.descriptor_mask == 0x3f &&
              probe.exact_descriptors == 1 && probe.exact_environment == 1 &&
              probe.host_home_absent == 1 &&
              probe.bus_socket_absent == 1 &&
              probe.wayland_socket_absent == 1 &&
              probe.network_denied == 1 && probe.descendant_denied == 1 &&
              probe.revision_write_denied == 1,
          "standalone sandbox did not deny an ambient authority");
  const std::array acknowledgement{std::byte{1}};
  require(launched.worker->send(launcher::EndpointRole::control,
                                acknowledgement),
          "standalone sandbox acknowledgement send failed");
  require(launched.worker->terminate(),
          "standalone sandbox supervisor teardown failed");
  require(scope->removes == 1,
          "standalone sandbox scope was not removed exactly once");
  require(scope->kills == 0,
          "normally exited standalone sandbox required a scope kill");
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
    test_standalone_sandbox();
  } catch (const std::exception &error) {
    dprintf(STDERR_FILENO, "%s\n", error.what());
    return 1;
  }
  return 0;
}
