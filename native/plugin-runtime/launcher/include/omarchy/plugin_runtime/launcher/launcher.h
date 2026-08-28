#pragma once

#include "omarchy/plugin_runtime/sandbox/policy.h"

#include <sys/types.h>

#include <chrono>
#include <cstddef>
#include <cstdint>
#include <memory>
#include <span>
#include <string>
#include <vector>

namespace omarchy::plugin_runtime::launcher {

enum class EndpointRole { control, broker, render };

struct LaunchIdentity {
  std::string plugin_id;
  std::string revision_sha256;
  std::uint64_t generation = 0;
  pid_t outer_worker_pid = -1;
  uid_t outer_uid = 0;
  gid_t outer_gid = 0;
};

struct TrustedLaunchRequest {
  std::string plugin_id;
  std::string revision_sha256;
  std::uint64_t generation = 0;
  int revision_directory_fd = -1;
  int private_state_directory_fd = -1;
};

enum class LaunchFailure {
  none,
  invalid_trusted_record,
  invalid_revision_descriptor,
  invalid_state_descriptor,
  missing_kernel_prerequisite,
  resource_scope_unavailable,
  resource_scope_failed,
  descriptor_setup_failed,
  seccomp_compile_failed,
  fork_failed,
  exec_failed,
  status_protocol_failed,
  startup_timeout,
  pidfd_failed,
  worker_exited_early,
  barrier_release_failed,
};

enum class ReceiveFailure {
  none,
  invalid_role,
  timeout,
  worker_exited,
  pidfd_unusable,
  truncated,
  malformed_ancillary,
  descriptor_injection,
  credential_mismatch,
  io_error,
};

struct ReceivedMessage {
  std::vector<std::byte> payload;
  ReceiveFailure failure = ReceiveFailure::none;

  [[nodiscard]] explicit operator bool() const {
    return failure == ReceiveFailure::none;
  }
};

class ResourceScopeController {
public:
  virtual ~ResourceScopeController() = default;
  [[nodiscard]] virtual bool probe(std::string &error) = 0;
  [[nodiscard]] virtual bool attach(std::string_view unit, pid_t monitor_pid,
                                    pid_t worker_pid,
                                    const sandbox::SandboxPlan &plan,
                                    std::chrono::milliseconds timeout,
                                    std::string &error) = 0;
  virtual void kill(std::string_view unit) noexcept = 0;
  virtual void remove(std::string_view unit) noexcept = 0;
};

[[nodiscard]] std::shared_ptr<ResourceScopeController>
make_systemd_resource_scope_controller();

class Worker {
public:
  Worker(const Worker &) = delete;
  Worker &operator=(const Worker &) = delete;
  Worker(Worker &&) noexcept;
  Worker &operator=(Worker &&) noexcept;
  ~Worker();

  [[nodiscard]] const LaunchIdentity &identity() const;
  [[nodiscard]] ReceivedMessage receive(EndpointRole role,
                                        std::size_t maximum_payload,
                                        std::chrono::milliseconds timeout);
  [[nodiscard]] bool send(EndpointRole role,
                          std::span<const std::byte> payload);
  [[nodiscard]] bool alive() const;
  [[nodiscard]] bool terminate();

private:
  struct Impl;
  explicit Worker(std::unique_ptr<Impl> implementation);
  std::unique_ptr<Impl> implementation_;
  friend class Supervisor;
};

struct LaunchResult {
  std::unique_ptr<Worker> worker;
  LaunchFailure failure = LaunchFailure::none;
  std::string detail;

  [[nodiscard]] explicit operator bool() const {
    return worker != nullptr && failure == LaunchFailure::none;
  }
};

class Supervisor {
public:
  [[nodiscard]] static Supervisor production();
  [[nodiscard]] static Supervisor
  forTestOnly(std::string bwrap_path, std::string worker_path,
              std::shared_ptr<ResourceScopeController> resource_scope);

  Supervisor(const Supervisor &) = delete;
  Supervisor &operator=(const Supervisor &) = delete;
  Supervisor(Supervisor &&) noexcept;
  Supervisor &operator=(Supervisor &&) noexcept;
  ~Supervisor();

  [[nodiscard]] bool prerequisites(std::string &error) const;
  [[nodiscard]] LaunchResult launch(const TrustedLaunchRequest &request) const;

private:
  struct Impl;
  explicit Supervisor(std::unique_ptr<Impl> implementation);
  std::unique_ptr<Impl> implementation_;
};

} // namespace omarchy::plugin_runtime::launcher
