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

using Deadline = std::chrono::steady_clock::time_point;

enum class EndpointRole { control, broker, render };
enum class EndpointMask : std::uint8_t {
  none = 0,
  control = 1U << 0,
  broker = 1U << 1,
  render = 1U << 2,
  all = 7,
};
[[nodiscard]] constexpr EndpointMask operator|(EndpointMask left,
                                                EndpointMask right) noexcept {
  return static_cast<EndpointMask>(static_cast<std::uint8_t>(left) |
                                   static_cast<std::uint8_t>(right));
}

// The launcher transports opaque packets. Protocol code supplies the exact
// bound it negotiated; this ceiling only bounds allocation and kernel I/O.
inline constexpr std::size_t kTransportPacketHardLimit = 48U + 65536U;

struct PacketSizeLimit {
  std::size_t bytes = 0;
};

struct ReadinessInterests {
  EndpointMask read = EndpointMask::all;
  EndpointMask write = EndpointMask::none;
};

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

enum class SendStatus { complete, would_block, peer_closed, fatal };
enum class ReceiveStatus { message, would_block, peer_closed, fatal };

class OwnedDescriptor final {
public:
  explicit OwnedDescriptor(int descriptor = -1) noexcept;
  OwnedDescriptor(OwnedDescriptor &&other) noexcept;
  OwnedDescriptor &operator=(OwnedDescriptor &&other) noexcept;
  OwnedDescriptor(const OwnedDescriptor &) = delete;
  OwnedDescriptor &operator=(const OwnedDescriptor &) = delete;
  ~OwnedDescriptor();

  [[nodiscard]] int get() const noexcept;
  [[nodiscard]] int release() noexcept;
  [[nodiscard]] explicit operator bool() const noexcept;
  void reset(int descriptor = -1) noexcept;

private:
  int descriptor_ = -1;
};

struct ReceivedMessage {
  std::vector<std::byte> payload{};
  std::vector<OwnedDescriptor> descriptors{};
  EndpointRole role = EndpointRole::control;
  ReceiveStatus status = ReceiveStatus::fatal;
  ReceiveFailure failure = ReceiveFailure::none;

  [[nodiscard]] explicit operator bool() const {
    return status == ReceiveStatus::message &&
           failure == ReceiveFailure::none;
  }
};

class ResourceScopeController {
public:
  struct AttachResult {
    bool attached = false;
    // True once scope creation may have reached the resource manager. The
    // launch owner must then perform exactly one asynchronous cleanup.
    bool cleanup_required = false;
  };

  virtual ~ResourceScopeController() = default;
  [[nodiscard]] bool probe(std::string &error);
  [[nodiscard]] virtual bool probe(Deadline deadline,
                                   std::string &error) = 0;
  // Establishes every resource needed for later teardown before process
  // authority exists. Cleanup operations must never reconnect lazily.
  [[nodiscard]] virtual bool prepare_cleanup(Deadline deadline,
                                             std::string &error) = 0;
  [[nodiscard]] AttachResult
  attach(std::string_view unit, pid_t monitor_pid, pid_t worker_pid,
         const sandbox::SandboxPlan &plan,
         std::chrono::milliseconds timeout, std::string &error);
  [[nodiscard]] virtual AttachResult
  attach(std::string_view unit, pid_t monitor_pid, pid_t worker_pid,
         const sandbox::SandboxPlan &plan, Deadline deadline,
         std::string &error) = 0;
  virtual void kill(std::string_view unit, Deadline deadline) noexcept = 0;
  virtual void remove(std::string_view unit, Deadline deadline) noexcept = 0;
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
                                        PacketSizeLimit maximum_packet,
                                        Deadline deadline);
  [[nodiscard]] ReceivedMessage receive_any(PacketSizeLimit maximum_packet,
                                            Deadline deadline);
  // Receives from a subset of the currently armed read interests without
  // changing readiness configuration.
  [[nodiscard]] ReceivedMessage receive_any(PacketSizeLimit maximum_packet,
                                            Deadline deadline,
                                            EndpointMask allowed_reads);
  // v1 compatibility: maximum_payload is additionally bounded by that
  // endpoint's v1 envelope maximum.
  [[nodiscard]] ReceivedMessage receive(EndpointRole role,
                                        std::size_t maximum_payload,
                                        Deadline deadline);
  [[nodiscard]] ReceivedMessage receive_any(std::size_t maximum_payload,
                                            Deadline deadline);
  [[nodiscard]] ReceivedMessage receive_any(std::size_t maximum_payload,
                                            Deadline deadline,
                                            EndpointMask allowed);
  [[nodiscard]] ReceivedMessage receive(EndpointRole role,
                                        std::size_t maximum_payload,
                                        std::chrono::milliseconds timeout);
  // Descriptor arguments are always borrowed. complete means the kernel made
  // its own references; every other status makes no transport progress and
  // retains, duplicates, or closes none of the caller's descriptors.
  [[nodiscard]] SendStatus
  try_send(EndpointRole role, std::span<const std::byte> payload,
           PacketSizeLimit maximum_packet,
           std::span<const int> borrowed_descriptors = {}) noexcept;
  // v1 compatibility: the role's v1 envelope maximum is used.
  [[nodiscard]] SendStatus
  try_send(EndpointRole role, std::span<const std::byte> payload,
           std::span<const int> borrowed_descriptors = {}) noexcept;
  [[nodiscard]] bool send(EndpointRole role,
                          std::span<const std::byte> payload,
                          PacketSizeLimit maximum_packet);
  [[nodiscard]] bool send(EndpointRole role,
                          std::span<const std::byte> payload);
  [[nodiscard]] bool send_with_descriptors(EndpointRole role,
                                           std::span<const std::byte> payload,
                                           PacketSizeLimit maximum_packet,
                                           std::span<const int> descriptors);
  [[nodiscard]] bool send_with_descriptors(EndpointRole role,
                                           std::span<const std::byte> payload,
                                           std::span<const int> descriptors);
  [[nodiscard]] bool alive() const;
  // Borrowed level-triggered aggregate readiness descriptor. It becomes
  // readable for armed endpoint events or worker exit. epoll_wait/poll may
  // observe it, but receive_any remains the sole multi-lane transport reader.
  [[nodiscard]] int readiness_fd() const noexcept;
  // Arms explicit level-triggered read/write interests. pidfd readiness is
  // permanently armed. receive_any consumes only lanes in interests.read.
  [[nodiscard]] bool
  set_readiness_interests(ReadinessInterests interests) noexcept;
  // v1 compatibility: changes read interests while preserving write.
  [[nodiscard]] bool set_receive_mask(EndpointMask allowed) noexcept;
  [[nodiscard]] std::string take_standard_error();
  [[nodiscard]] bool terminate(Deadline deadline) noexcept;
  [[nodiscard]] bool
  terminate(std::chrono::milliseconds timeout) noexcept;
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
              std::shared_ptr<ResourceScopeController> resource_scope,
              bool force_reaper_start_failure = false);

  Supervisor(const Supervisor &) = delete;
  Supervisor &operator=(const Supervisor &) = delete;
  Supervisor(Supervisor &&) noexcept;
  Supervisor &operator=(Supervisor &&) noexcept;
  ~Supervisor();

  [[nodiscard]] bool prerequisites(std::string &error) const;
  [[nodiscard]] bool prerequisites(Deadline deadline,
                                   std::string &error) const;
  [[nodiscard]] LaunchResult launch(const TrustedLaunchRequest &request) const;
  [[nodiscard]] LaunchResult launch(const TrustedLaunchRequest &request,
                                    Deadline deadline) const;
private:
  struct Impl;
  explicit Supervisor(std::unique_ptr<Impl> implementation);
  std::unique_ptr<Impl> implementation_;
};

} // namespace omarchy::plugin_runtime::launcher
