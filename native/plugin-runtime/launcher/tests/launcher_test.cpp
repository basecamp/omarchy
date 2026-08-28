#include "omarchy/plugin_runtime/launcher/launcher.h"
#include "omarchy/plugin_runtime/launcher/termination_state.h"
#include "omarchy/plugin_runtime/test_support/test_support.h"

#include <fcntl.h>
#include <poll.h>
#include <sys/syscall.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

#include <array>
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <memory>
#include <span>
#include <string>
#include <string_view>

namespace launcher = omarchy::plugin_runtime::launcher;
namespace sandbox = omarchy::plugin_runtime::sandbox;
namespace support = omarchy::plugin_runtime::test_support;

namespace {
using namespace std::chrono_literals;

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

struct Claim {
  std::uint32_t magic;
  std::int32_t claimed_pid;
};

struct DescriptorReport {
  std::uint32_t count;
  std::uint32_t close_on_exec;
};

[[noreturn]] void fail(std::string_view message) {
  std::cerr << message << '\n';
  std::exit(1);
}

void require(bool condition, std::string_view message) {
  if (!condition) {
    fail(message);
  }
}

std::size_t open_descriptor_count() {
  std::size_t count = 0;
  for (const auto &entry :
       std::filesystem::directory_iterator("/proc/self/fd")) {
    (void)entry;
    ++count;
  }
  return count;
}

template <typename Value> Value decode(std::span<const std::byte> bytes) {
  require(bytes.size() == sizeof(Value), "probe payload size changed");
  Value value{};
  std::memcpy(&value, bytes.data(), sizeof(value));
  return value;
}

class FakeScope final : public launcher::ResourceScopeController {
public:
  bool probe(std::string &error) override {
    if (!available) {
      error = "synthetic resource controller unavailable";
    }
    return available;
  }

  bool attach(std::string_view unit, pid_t monitor_pid, pid_t worker_pid,
              const sandbox::SandboxPlan &plan,
              std::chrono::milliseconds timeout, std::string &error) override {
    if (!attach_succeeds) {
      error = "synthetic scope attachment rejected";
      return false;
    }
    require(unit.starts_with("app-omarchy-plugin-worker-"),
            "scope name escaped the trusted prefix");
    require(monitor_pid > 0 && worker_pid > 0,
            "scope received an invalid process identity");
    require(plan.worker_descriptors == std::vector<int>({3, 4, 5}) &&
                plan.launcher_descriptors ==
                    std::vector<int>({3, 4, 5, 6, 7, 8, 9, 10}),
            "launcher did not consume the B5 descriptor contract");
    require(plan.resources.memory_max_bytes == 512ULL * 1024ULL * 1024ULL &&
                plan.resources.tasks_max == 16 && timeout == 5s,
            "launcher did not consume the B5 resource/deadline contract");
    attached = true;
    attached_before_release = true;
    scope.assign(unit);
    return true;
  }

  void kill(std::string_view unit) noexcept override {
    if (unit == scope) {
      ++kill_count;
    }
  }

  void remove(std::string_view unit) noexcept override {
    if (unit == scope) {
      ++remove_count;
    }
  }

  bool available = true;
  bool attach_succeeds = true;
  bool attached = false;
  bool attached_before_release = false;
  unsigned kill_count = 0;
  unsigned remove_count = 0;
  std::string scope;
};

struct LaunchFixture {
  LaunchFixture() {
    require(chmod(tree.revision().c_str(), 0555) == 0,
            "cannot make synthetic revision immutable");
    revision.reset(
        open(tree.revision().c_str(), O_RDONLY | O_DIRECTORY | O_CLOEXEC));
    state.reset(
        open(tree.private_state().c_str(), O_RDONLY | O_DIRECTORY | O_CLOEXEC));
    require(revision && state, "cannot open synthetic launch directories");
  }

  ~LaunchFixture() { static_cast<void>(chmod(tree.revision().c_str(), 0755)); }

  [[nodiscard]] launcher::TrustedLaunchRequest request() const {
    return {.plugin_id = "org.omarchy_fixture",
            .revision_sha256 = std::string(64, 'a'),
            .generation = 17,
            .revision_directory_fd = revision.get(),
            .private_state_directory_fd = state.get()};
  }

  support::SyntheticResourceTree tree;
  support::UniqueFd revision;
  support::UniqueFd state;
};

void validate_probe(launcher::Worker &worker) {
  const auto message =
      worker.receive(launcher::EndpointRole::control, sizeof(Probe), 2s);
  require(static_cast<bool>(message), "bound worker control packet failed");
  const Probe probe = decode<Probe>(message.payload);
  require(probe.magic == 0x43575037 && probe.pid == 1 && probe.uid == 0 &&
              probe.gid == 0 && probe.descriptor_mask == 0x3f &&
              probe.no_new_privileges == 1 && probe.open_files_max == 64 &&
              probe.file_size_max == 64ULL * 1024ULL * 1024ULL &&
              probe.core_size_max == 0,
          "worker identity, exact FD set, NNP, or rlimit contract changed");
}

void pidfd_reap_state_test() {
  const pid_t child = fork();
  require(child >= 0, "cannot fork pidfd reap-state fixture");
  if (child == 0) {
    _exit(0);
  }
  support::UniqueFd pidfd(
      static_cast<int>(syscall(SYS_pidfd_open, child, 0)));
  require(static_cast<bool>(pidfd),
          "cannot open pidfd reap-state fixture");
  pollfd before{.fd = pidfd.get(), .events = POLLIN, .revents = 0};
  require(poll(&before, 1, 2000) == 1 &&
              launcher::pidfd_has_exited(before.revents),
          "pidfd did not report child exit before reap");
  int status = 0;
  require(waitpid(child, &status, 0) == child,
          "cannot reap pidfd state fixture");
  pollfd after{.fd = pidfd.get(), .events = POLLIN, .revents = 0};
  require(poll(&after, 1, 0) == 1 &&
              after.revents == (POLLIN | POLLHUP) &&
              launcher::pidfd_has_exited(after.revents),
          "reaped pidfd POLLIN|POLLHUP was not accepted as exited");
  require(!launcher::pidfd_has_exited(POLLHUP) &&
              !launcher::pidfd_has_exited(POLLIN | POLLERR) &&
              !launcher::pidfd_has_exited(POLLIN | POLLNVAL),
          "unexpected pidfd events were accepted as an exit certificate");
}

void contract_test() {
  pidfd_reap_state_test();
  auto scope = std::make_shared<FakeScope>();
  auto supervisor =
      launcher::Supervisor::forTestOnly(FAKE_BWRAP_PATH, PROBE_PATH, scope);
  LaunchFixture fixture;

  auto invalid = fixture.request();
  invalid.plugin_id = "../forged";
  require(supervisor.launch(invalid).failure ==
              launcher::LaunchFailure::invalid_trusted_record,
          "plugin-controlled identity syntax reached process launch");
  invalid = fixture.request();
  invalid.plugin_id = "1.invalid";
  require(supervisor.launch(invalid).failure ==
              launcher::LaunchFailure::invalid_trusted_record,
          "non-letter plugin identity reached process launch");
  invalid = fixture.request();
  invalid.generation = 0;
  require(supervisor.launch(invalid).failure ==
              launcher::LaunchFailure::invalid_trusted_record,
          "zero generation reached process launch");

  auto unavailable_scope = std::make_shared<FakeScope>();
  unavailable_scope->available = false;
  auto unavailable = launcher::Supervisor::forTestOnly(
      FAKE_BWRAP_PATH, PROBE_PATH, unavailable_scope);
  require(unavailable.launch(fixture.request()).failure ==
              launcher::LaunchFailure::missing_kernel_prerequisite,
          "launch proceeded without a resource controller");

  auto duplicate = launcher::Supervisor::forTestOnly(
      DUPLICATE_STATUS_BWRAP_PATH, PROBE_PATH, std::make_shared<FakeScope>());
  const auto duplicate_result = duplicate.launch(fixture.request());
  if (duplicate_result.failure !=
      launcher::LaunchFailure::status_protocol_failed) {
    std::cerr << "duplicate status failure="
              << static_cast<int>(duplicate_result.failure)
              << " detail=" << duplicate_result.detail << '\n';
  }
  require(duplicate_result.failure ==
              launcher::LaunchFailure::status_protocol_failed,
          "escaped duplicate authoritative status key was accepted");

  auto string_status = launcher::Supervisor::forTestOnly(
      STRING_STATUS_BWRAP_PATH, PROBE_PATH, std::make_shared<FakeScope>());
  require(string_status.launch(fixture.request()).failure ==
              launcher::LaunchFailure::status_protocol_failed,
          "string child PID was accepted as authoritative status");

  auto exited_status = launcher::Supervisor::forTestOnly(
      EXITED_STATUS_BWRAP_PATH, PROBE_PATH, std::make_shared<FakeScope>());
  require(exited_status.launch(fixture.request()).failure ==
              launcher::LaunchFailure::worker_exited_early,
          "combined child/exit status lost its early-exit authority");

  const auto invalid_executable = fixture.tree.root() / "invalid-bwrap";
  std::ofstream(invalid_executable) << "not an executable format\n";
  require(chmod(invalid_executable.c_str(), 0700) == 0,
          "cannot prepare exec-error fixture");
  auto exec_error = launcher::Supervisor::forTestOnly(
      invalid_executable.string(), PROBE_PATH, std::make_shared<FakeScope>());
  const auto failed_exec = exec_error.launch(fixture.request());
  require(failed_exec.failure == launcher::LaunchFailure::exec_failed,
          "exec-error handshake did not distinguish execve failure");
}

void malicious_test() {
  auto scope = std::make_shared<FakeScope>();
  auto supervisor = launcher::Supervisor::forTestOnly(
      FAKE_BWRAP_PATH, MALICIOUS_PROBE_PATH, scope);
  LaunchFixture fixture;
  auto launched = supervisor.launch(fixture.request());
  require(static_cast<bool>(launched) && scope->attached,
          "synthetic malicious worker launch failed");
  require(
      launched.worker->receive(static_cast<launcher::EndpointRole>(99), 16, 0ms)
              .failure == launcher::ReceiveFailure::invalid_role,
      "unknown trusted endpoint role reached polling");

  const auto control = launched.worker->receive(launcher::EndpointRole::control,
                                                sizeof(Claim), 2s);
  require(static_cast<bool>(control) &&
              decode<Claim>(control.payload).claimed_pid ==
                  launched.worker->identity().outer_worker_pid,
          "bound worker message was not accepted");
  const auto descendant = launched.worker->receive(
      launcher::EndpointRole::broker, sizeof(Claim), 2s);
  require(descendant.failure == launcher::ReceiveFailure::credential_mismatch,
          "forked inherited-endpoint holder passed kernel PID binding");
  const auto maximum_broker =
      launched.worker->receive(launcher::EndpointRole::broker, 40 + 65536, 2s);
  require(static_cast<bool>(maximum_broker) &&
              maximum_broker.payload.size() == 40 + 65536,
          "legal maximum broker envelope was rejected by the raw channel");
  const auto render = launched.worker->receive(launcher::EndpointRole::render,
                                               sizeof(Claim), 2s);
  require(static_cast<bool>(render),
          "bound render message failed after descendant rejection");
  const std::array acknowledgement{std::byte{1}};
  require(
      launched.worker->send(launcher::EndpointRole::control, acknowledgement),
      "descriptor-free launcher send failed");
  support::UniqueFd passed(open("/dev/null", O_RDONLY | O_CLOEXEC));
  const std::array one{passed.get()};
  require(passed && launched.worker->send_with_descriptors(
                        launcher::EndpointRole::control, acknowledgement, one),
          "single descriptor launcher send failed");
  const std::array excess{passed.get(), passed.get()};
  require(!launched.worker->send_with_descriptors(
              launcher::EndpointRole::control, acknowledgement, excess) &&
              fcntl(passed.get(), F_GETFD) >= 0,
          "excess descriptors were sent or caller ownership was consumed");
  const auto descriptor_report = launched.worker->receive(
      launcher::EndpointRole::render, sizeof(DescriptorReport), 2s);
  require(static_cast<bool>(descriptor_report),
          "worker descriptor report was not received");
  const auto report = decode<DescriptorReport>(descriptor_report.payload);
  require(report.count == 1 && report.close_on_exec == 1,
          "worker did not receive exactly one close-on-exec descriptor");
  require(launched.worker->terminate() && scope->remove_count == 1,
          "bounded normal teardown failed");
}

void bwrap_test() {
  if (access(BWRAP_PATH, X_OK) < 0) {
    std::cerr << "Bubblewrap unavailable; launcher integration skipped\n";
    std::exit(77);
  }
  auto scope = std::make_shared<FakeScope>();
  auto supervisor =
      launcher::Supervisor::forTestOnly(BWRAP_PATH, PROBE_PATH, scope);
  LaunchFixture fixture;
  auto launched = supervisor.launch(fixture.request());
  if (!launched &&
      (launched.detail.find("Operation not permitted") != std::string::npos ||
       launched.detail.find("SO_PASSCRED") != std::string::npos)) {
    std::cerr << "Outer sandbox denied kernel launch proof; skipped\n";
    std::exit(77);
  }
  require(static_cast<bool>(launched) && scope->attached_before_release,
          "real Bubblewrap launch failed before barrier-bound scope attach");
  validate_probe(*launched.worker);
  const auto injection =
      launched.worker->receive(launcher::EndpointRole::broker, 16, 2s);
  require(injection.failure == launcher::ReceiveFailure::descriptor_injection,
          "worker-originated descriptor was not quarantined and rejected");
  const auto descriptors_before = open_descriptor_count();
  const auto truncated_ancillary =
      launched.worker->receive(launcher::EndpointRole::render, 16, 2s);
  const auto descriptors_after = open_descriptor_count();
  require(truncated_ancillary.failure == launcher::ReceiveFailure::truncated &&
              descriptors_after == descriptors_before,
          "MSG_CTRUNC leaked a delivered SCM_RIGHTS descriptor");
  const std::array acknowledgement{std::byte{1}};
  require(
      launched.worker->send(launcher::EndpointRole::control, acknowledgement) &&
          launched.worker->terminate() && scope->remove_count == 1,
      "real Bubblewrap worker did not tear down within bounds");
}

std::string read_one_line(const std::filesystem::path &path) {
  std::ifstream stream(path);
  std::string line;
  std::getline(stream, line);
  if (!stream && !stream.eof()) {
    fail("cannot read enforced cgroup value: " + path.string());
  }
  return line;
}

void systemd_scope_test() {
  if (access(BWRAP_PATH, X_OK) < 0) {
    std::cerr << "Bubblewrap unavailable; systemd scope test skipped\n";
    std::exit(77);
  }
  auto supervisor = launcher::Supervisor::forTestOnly(
      BWRAP_PATH, PROBE_PATH,
      launcher::make_systemd_resource_scope_controller());
  LaunchFixture fixture;
  auto launched = supervisor.launch(fixture.request());
  if (!launched &&
      (launched.failure == launcher::LaunchFailure::resource_scope_failed ||
       launched.failure ==
           launcher::LaunchFailure::missing_kernel_prerequisite)) {
    std::cerr << "systemd user scope unavailable: " << launched.detail << '\n';
    std::exit(77);
  }
  require(static_cast<bool>(launched),
          "real systemd-scoped Bubblewrap launch failed");
  validate_probe(*launched.worker);

  const auto cgroup_file =
      std::filesystem::path("/proc") /
      std::to_string(launched.worker->identity().outer_worker_pid) / "cgroup";
  const std::string cgroup_record = read_one_line(cgroup_file);
  const auto separator = cgroup_record.find("::");
  require(separator != std::string::npos,
          "worker did not enter a unified cgroup");
  const std::string cgroup_path = cgroup_record.substr(separator + 2);
  require(cgroup_path.find("app-omarchy-plugin-worker-") != std::string::npos,
          "worker was released outside its generation scope");
  const std::filesystem::path cgroup_root =
      std::filesystem::path("/sys/fs/cgroup") /
      cgroup_path.substr(cgroup_path.starts_with('/') ? 1 : 0);
  require(read_one_line(cgroup_root / "memory.high") == "402653184" &&
              read_one_line(cgroup_root / "memory.max") == "536870912" &&
              read_one_line(cgroup_root / "pids.max") == "16" &&
              read_one_line(cgroup_root / "cpu.weight") == "20" &&
              read_one_line(cgroup_root / "cpu.max").starts_with("50000 "),
          "systemd did not realize the B5 cgroup ceilings");
  const auto io_weight = cgroup_root / "io.weight";
  if (std::filesystem::exists(io_weight)) {
    require(read_one_line(io_weight) == "default 10",
            "systemd did not realize B5 IOWeight");
  } else {
    std::cerr << "io controller is not delegated on this host; IOWeight "
                 "enforcement remains a VM gate\n";
  }

  const auto injection =
      launched.worker->receive(launcher::EndpointRole::broker, 16, 2s);
  require(injection.failure == launcher::ReceiveFailure::descriptor_injection,
          "systemd-scoped worker descriptor injection passed");
  const std::array acknowledgement{std::byte{1}};
  require(
      launched.worker->send(launcher::EndpointRole::control, acknowledgement) &&
          launched.worker->terminate(),
      "systemd-scoped worker did not tear down within bounds");
}
} // namespace

int main(int argc, char **argv) {
  if (argc != 2) {
    return 64;
  }
  const std::string_view mode(argv[1]);
  if (mode == "contract") {
    contract_test();
  } else if (mode == "malicious") {
    malicious_test();
  } else if (mode == "bwrap") {
    bwrap_test();
  } else if (mode == "systemd") {
    systemd_scope_test();
  } else {
    return 64;
  }
  return 0;
}
