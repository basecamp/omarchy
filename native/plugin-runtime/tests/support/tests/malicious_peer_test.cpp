#include "omarchy/plugin_runtime/test_support/test_support.h"

#include "omarchy/plugin/wire/envelope.hpp"

#include <fcntl.h>
#include <poll.h>
#include <sys/wait.h>
#include <unistd.h>

#include <algorithm>
#include <array>
#include <cstdlib>
#include <iostream>
#include <ranges>
#include <span>
#include <string_view>
#include <vector>

namespace support = omarchy::plugin_runtime::test_support;
namespace wire = omarchy::plugin::wire;

namespace {
constexpr std::uint64_t kGeneration = 0x1020304050607080ULL;

[[noreturn]] void fail(std::string_view message) {
  std::cerr << message << '\n';
  std::exit(1);
}

void require(bool condition, std::string_view message) {
  if (!condition) {
    fail(message);
  }
}

std::vector<std::byte> packet(wire::EndpointRole role,
                              std::span<const std::byte> payload,
                              std::uint64_t correlation = 1) {
  wire::EnvelopeHeader header{.endpoint_role = role,
                              .message_type = 0x1100,
                              .role_protocol_version = 1,
                              .launch_generation = kGeneration,
                              .correlation_id = correlation};
  std::vector<std::byte> output(wire::kHeaderSize + payload.size());
  const auto result = wire::encode_packet(header, payload, output);
  if (!result || result.bytes_written != output.size()) {
    fail("malicious peer could not encode fixture packet");
  }
  return output;
}

void require_credential(const support::ReceivedPacket &received,
                        pid_t process) {
  require(received.has_credentials && !received.truncated &&
              !received.ancillary_invalid &&
              received.credentials.pid == process &&
              received.credentials.uid == getuid() &&
              received.credentials.gid == getgid(),
          "kernel credential tuple did not match the bound peer");
}

void require_readable(int descriptor) {
  pollfd polled{.fd = descriptor, .events = POLLIN, .revents = 0};
  require(poll(&polled, 1, 2000) == 1 && (polled.revents & POLLIN) != 0 &&
              (polled.revents & ~(POLLIN | POLLHUP)) == 0,
          "fixture channel did not become readable within its bound");
}

void child_main(int control_source, int broker_source, int render_source) {
  const std::array sources{control_source, broker_source, render_source};
  const std::array destinations{support::kWorkerControlFd,
                                support::kWorkerBrokerFd,
                                support::kWorkerRenderFd};
  if (!support::relocate_descriptors_exact(sources, destinations, 6)) {
    _exit(100);
  }
  for (const int descriptor : destinations) {
    if (fcntl(descriptor, F_SETFD, FD_CLOEXEC) < 0) {
      _exit(101);
    }
  }

  const std::array claim{std::byte{0x66}, std::byte{0x6f}, std::byte{0x72},
                         std::byte{0x67}, std::byte{0x65}, std::byte{0x64}};
  support::UniqueFd injected(open("/dev/null", O_RDONLY | O_CLOEXEC));
  if (!injected) {
    _exit(102);
  }
  const std::array injected_fds{injected.get()};
  support::send_packet(support::kWorkerControlFd,
                       packet(wire::EndpointRole::control, claim),
                       injected_fds);
  injected.reset();

  const auto open = support::open_fd_set();
  if (open != std::vector<int>({0, 1, 2, 3, 4, 5})) {
    _exit(103);
  }
  std::vector<std::byte> identity;
  for (const int descriptor : open) {
    identity.push_back(std::byte(descriptor));
  }
  support::send_packet(support::kWorkerControlFd,
                       packet(wire::EndpointRole::control, identity, 2));

  const pid_t descendant = fork();
  if (descendant < 0) {
    _exit(104);
  }
  if (descendant == 0) {
    support::send_packet(support::kWorkerBrokerFd,
                         packet(wire::EndpointRole::broker, claim, 3));
    _exit(0);
  }
  support::UniqueFd descendant_pidfd = support::open_pidfd(descendant);
  int descendant_status = 0;
  if (!descendant_pidfd ||
      !support::bounded_reap(descendant, descendant_pidfd.get(), 2000,
                             &descendant_status) ||
      !WIFEXITED(descendant_status) || WEXITSTATUS(descendant_status) != 0) {
    _exit(105);
  }

  support::send_packet(support::kWorkerRenderFd,
                       packet(wire::EndpointRole::render, claim, 4));
  pollfd acknowledgement{
      .fd = support::kWorkerControlFd, .events = POLLIN, .revents = 0};
  if (poll(&acknowledgement, 1, 2000) != 1 ||
      acknowledgement.revents != POLLIN) {
    _exit(106);
  }
  std::byte byte{};
  if (recv(support::kWorkerControlFd, &byte, sizeof(byte), 0) != 1) {
    _exit(107);
  }
  _exit(0);
}

void live_identity_test() {
  auto control = support::SeqpacketPair::create();
  auto broker = support::SeqpacketPair::create();
  auto render = support::SeqpacketPair::create();
  support::enable_kernel_credentials(control.trusted.get());
  support::enable_kernel_credentials(broker.trusted.get());
  support::enable_kernel_credentials(render.trusted.get());

  const pid_t worker = fork();
  require(worker >= 0, "worker fork failed");
  if (worker == 0) {
    child_main(control.worker.get(), broker.worker.get(), render.worker.get());
  }
  control.worker.reset();
  broker.worker.reset();
  render.worker.reset();
  support::UniqueFd pidfd = support::open_pidfd(worker);
  require(static_cast<bool>(pidfd) &&
              support::pidfd_state(pidfd.get()) == support::PidfdState::alive,
          "worker pidfd was not live before traffic");

  const auto before_injection = support::open_fd_set();
  {
    require_readable(control.trusted.get());
    const auto injected =
        support::receive_packet(control.trusted.get(), 4096, 4);
    require_credential(injected, worker);
    require(injected.descriptors.size() == 1,
            "SCM_RIGHTS injection was not quarantined");
    const auto decoded =
        wire::decode_packet(injected.payload, wire::EndpointRole::control);
    require(static_cast<bool>(decoded),
            "credentialed injection did not carry a valid envelope");
  }
  require(support::open_fd_set() == before_injection,
          "quarantined descriptor leaked into the trusted process");

  require_readable(control.trusted.get());
  const auto identity = support::receive_packet(control.trusted.get(), 4096, 0);
  require_credential(identity, worker);
  const auto identity_packet =
      wire::decode_packet(identity.payload, wire::EndpointRole::control);
  require(static_cast<bool>(identity_packet) &&
              std::ranges::equal(identity_packet.packet.payload,
                                 std::array{std::byte{0}, std::byte{1},
                                            std::byte{2}, std::byte{3},
                                            std::byte{4}, std::byte{5}}),
          "worker did not enter with the exact FD 0-5 identity set");

  require_readable(broker.trusted.get());
  const auto descendant =
      support::receive_packet(broker.trusted.get(), 65536, 0);
  require(descendant.has_credentials && descendant.credentials.pid != worker &&
              descendant.credentials.uid == getuid() &&
              descendant.credentials.gid == getgid() &&
              support::pidfd_state(pidfd.get()) == support::PidfdState::alive,
          "unbound descendant did not present a distinct kernel PID");
  require(static_cast<bool>(wire::decode_packet(descendant.payload,
                                                wire::EndpointRole::broker)),
          "descendant denial was caused by an invalid envelope");

  require_readable(render.trusted.get());
  const auto valid = support::receive_packet(render.trusted.get(), 16384, 0);
  require_credential(valid, worker);
  require(static_cast<bool>(
              wire::decode_packet(valid.payload, wire::EndpointRole::render)) &&
              support::pidfd_state(pidfd.get()) == support::PidfdState::alive,
          "bound worker render packet was not valid while live");

  const std::array acknowledgement{std::byte{1}};
  support::send_packet(control.trusted.get(), acknowledgement);
  int status = 0;
  require(support::bounded_reap(worker, pidfd.get(), 2000, &status) &&
              WIFEXITED(status) && WEXITSTATUS(status) == 0,
          "worker did not exit and reap within its bound");
}

void post_exit_queue_test() {
  auto channel = support::SeqpacketPair::create();
  support::enable_kernel_credentials(channel.trusted.get());
  const pid_t worker = fork();
  require(worker >= 0, "post-exit worker fork failed");
  if (worker == 0) {
    channel.trusted.reset();
    const std::array payload{std::byte{0x71}};
    support::send_packet(channel.worker.get(),
                         packet(wire::EndpointRole::control, payload));
    _exit(0);
  }
  channel.worker.reset();
  support::UniqueFd pidfd = support::open_pidfd(worker);
  require(static_cast<bool>(pidfd) &&
              support::wait_pidfd_exit(pidfd.get(), 2000),
          "post-exit worker lifetime did not end within bound");
  require_readable(channel.trusted.get());
  const auto queued = support::receive_packet(channel.trusted.get(), 4096, 0);
  require_credential(queued, worker);
  require(static_cast<bool>(
              wire::decode_packet(queued.payload, wire::EndpointRole::control)),
          "queued post-exit denial was caused by invalid traffic");
  require(support::pidfd_state(pidfd.get()) == support::PidfdState::exited,
          "queued correct-credential packet outlived an apparently live pidfd");
  int status = 0;
  require(support::bounded_reap(worker, pidfd.get(), 2000, &status) &&
              WIFEXITED(status) && WEXITSTATUS(status) == 0,
          "post-exit worker was not reaped");

  const int closed_pidfd = pidfd.release();
  close(closed_pidfd);
  require(support::pidfd_state(closed_pidfd) == support::PidfdState::unusable,
          "closed pidfd was treated as a live identity");
}
} // namespace

int main() {
  live_identity_test();
  post_exit_queue_test();
  return 0;
}
