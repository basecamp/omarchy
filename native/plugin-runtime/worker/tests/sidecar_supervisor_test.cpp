#include "sidecar_supervisor.hpp"

#include <array>
#include <fcntl.h>
#include <signal.h>
#include <sys/socket.h>
#include <unistd.h>

#include <cerrno>
#include <chrono>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>
#include <thread>

namespace {

void require(bool condition, std::string_view message) {
  if (!condition)
    throw std::runtime_error(std::string(message));
}

void run() {
  const auto temporary =
      std::filesystem::temp_directory_path() /
      ("omarchy-sidecar-supervisor-" +
       std::to_string(
           std::chrono::steady_clock::now().time_since_epoch().count()));
  struct Cleanup {
    std::filesystem::path path;
    ~Cleanup() {
      std::error_code ignored;
      std::filesystem::remove_all(path, ignored);
    }
  } cleanup{temporary};
  std::filesystem::create_directories(temporary / "bin");
  std::filesystem::copy_file(SIDECAR_PROBE_PATH, temporary / "bin/probe");
  const auto report = temporary / "report";
  omarchy::plugins::manifest::Runtime::Sidecar declaration{
      .name = "probe",
      .command = {"bin/probe", report.string()}};
  pid_t child = -1;
  {
    omarchy::plugin_runtime::worker::SidecarSupervisor supervisor;
    std::string error;
    require(supervisor.startForTestOnly({declaration}, temporary, error),
            error);
    const auto deadline = std::chrono::steady_clock::now() +
                          std::chrono::seconds(2);
    while (!std::filesystem::exists(report) &&
           std::chrono::steady_clock::now() < deadline)
      std::this_thread::yield();
    std::ifstream input(report);
    std::string state;
    input >> child >> state;
    require(child > 0 && state == "closed",
            "sidecar inherited a privileged worker descriptor");
    require(supervisor.healthy(error), "live sidecar failed health check");
  }
  require(kill(child, 0) < 0 && errno == ESRCH,
          "sidecar survived supervisor teardown");

  omarchy::plugin_runtime::worker::SidecarSupervisor rejected;
  std::string error;
  auto missing = declaration;
  missing.command.front() = "bin/missing";
  require(!rejected.startForTestOnly({missing}, temporary, error) &&
              error.starts_with("cannot execute declared sidecar"),
          "missing declared executable did not fail closed");
}

void run_inside_bwrap() {
  require(getpid() == 1 && getuid() == 0 && getgid() == 0,
          "supervisor is not sandbox PID 1");
  std::array<int, 3> role_peers{};
  for (int role = 3; role <= 5; ++role) {
    std::array<int, 2> pair{};
    require(socketpair(AF_UNIX, SOCK_SEQPACKET | SOCK_CLOEXEC, 0,
                       pair.data()) == 0,
            "cannot create role descriptor probe");
    const int staged = fcntl(pair[0], F_DUPFD_CLOEXEC, 64);
    role_peers[static_cast<std::size_t>(role - 3)] =
        fcntl(pair[1], F_DUPFD_CLOEXEC, 64);
    close(pair[0]);
    close(pair[1]);
    require(staged >= 0 &&
                role_peers[static_cast<std::size_t>(role - 3)] >= 0 &&
                dup2(staged, role) == role,
            "cannot stage role descriptor probe");
    close(staged);
  }
  const std::filesystem::path report = "/tmp/sidecar-report";
  omarchy::plugins::manifest::Runtime::Sidecar declaration{
      .name = "probe",
      .command = {"bin/probe", report.string()}};
  pid_t child = -1;
  {
    omarchy::plugin_runtime::worker::SidecarSupervisor supervisor;
    std::string error;
    require(supervisor.startForTestOnly({declaration}, "/plugin", error),
            error);
    const auto deadline = std::chrono::steady_clock::now() +
                          std::chrono::seconds(2);
    while (!std::filesystem::exists(report) &&
           std::chrono::steady_clock::now() < deadline)
      std::this_thread::yield();
    std::ifstream input(report);
    std::string state, role_fds, host_paths, session, namespaces;
    input >> child >> state >> role_fds >> host_paths >> session >> namespaces;
    require(child > 1 && state == "closed" && role_fds == "fds-denied" &&
                host_paths == "host-denied" && session == "session-denied" &&
                namespaces == "namespace-denied",
            "sandbox sidecar reached worker or host authority: " + state +
                " " + role_fds + " " + host_paths + " " + session + " " +
                namespaces);
  }
  require(kill(child, 0) < 0 && errno == ESRCH,
          "sandbox sidecar survived PID 1 teardown");
  for (const int descriptor : role_peers)
    close(descriptor);
  for (const int descriptor : {3, 4, 5})
    close(descriptor);
}

} // namespace

int main(int argc, char **argv) {
  try {
    if (argc == 2 && std::string_view(argv[1]) == "--inside-bwrap")
      run_inside_bwrap();
    else {
      require(argc == 1, "unexpected test arguments");
      run();
    }
    std::cout << "sidecar supervisor: PASS\n";
    return 0;
  } catch (const std::exception &error) {
    std::cerr << "sidecar-supervisor-test: " << error.what() << '\n';
    return 1;
  }
}
