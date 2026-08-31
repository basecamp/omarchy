#include "authenticated_channel.hpp"
#include "omarchy/plugin_runtime/broker/broker_schema.hpp"
#include "omarchy/plugin_runtime/launcher/test_supervisor.h"
#include "omarchy/plugin_runtime/surface/render_messages.hpp"

#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <sys/stat.h>
#include <unistd.h>

#include <array>
#include <atomic>
#include <chrono>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <memory>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace channel = omarchy::plugin_runtime::channel;
namespace broker = omarchy::plugin_runtime::broker;
namespace permissions = omarchy::plugins::permissions;
namespace launcher = omarchy::plugin_runtime::launcher;
namespace sandbox = omarchy::plugin_runtime::sandbox;
namespace surface = omarchy::plugin_runtime::surface;
namespace wire = omarchy::plugin::wire;

namespace {
using namespace std::chrono_literals;

[[noreturn]] void fail(std::string_view message) {
  std::cerr << message << '\n';
  std::exit(1);
}

void require(bool condition, std::string_view message) {
  if (!condition) {
    fail(message);
  }
}

launcher::Deadline deadline_after(std::chrono::milliseconds delay) {
  return std::chrono::steady_clock::now() + delay;
}

class Descriptor {
public:
  Descriptor() = default;
  explicit Descriptor(int value) : value_(value) {}
  Descriptor(const Descriptor &) = delete;
  Descriptor &operator=(const Descriptor &) = delete;
  ~Descriptor() {
    if (value_ >= 0) {
      close(value_);
    }
  }
  [[nodiscard]] int get() const { return value_; }

private:
  int value_ = -1;
};

class Scope final : public launcher::ResourceScopeController {
public:
  bool probe(launcher::Deadline, std::string &) override { return true; }
  bool prepare_cleanup(launcher::Deadline, std::string &) override {
    return true;
  }
  AttachResult attach(std::string_view unit, pid_t monitor_pid,
                      pid_t worker_pid, const sandbox::SandboxPlan &plan,
                      launcher::Deadline deadline, std::string &) override {
    require(monitor_pid > 0 && worker_pid > 0 &&
                deadline > std::chrono::steady_clock::now(),
            "resource scope did not receive bounded process identities");
    require(plan.worker_descriptors == std::vector<int>({3, 4, 5}),
            "resource scope saw a changed endpoint contract");
    name = unit;
    attached = true;
    return {.attached = true, .cleanup_required = true};
  }
  bool terminate_scope_validated(std::string_view unit, launcher::Deadline,
                                  std::string &) noexcept override {
    if (unit == name) {
      ++terminations;
    }
    return true;
  }

  std::string name;
  bool attached = false;
  std::atomic<unsigned> terminations = 0;
};

bool eventually_removed(const std::shared_ptr<Scope> &scope) {
  const auto deadline = std::chrono::steady_clock::now() + 2s;
  while (scope->terminations.load() == 0 &&
         std::chrono::steady_clock::now() < deadline)
    usleep(1000);
  return scope->terminations.load() == 1;
}

bool await_channel_readable(channel::AuthenticatedBrokerChannel &channel) {
  pollfd ready{.fd = channel.readiness_fd(), .events = POLLIN, .revents = 0};
  return poll(&ready, 1, 2000) == 1 && (ready.revents & POLLIN) != 0;
}

class Authority final : public channel::GenerationAuthority {
public:
  void revoke_after_successful_checks(unsigned allowed_checks) noexcept {
    checks_before_revocation = static_cast<int>(allowed_checks);
  }

  bool
  is_current(const launcher::LaunchIdentity &identity) const noexcept override {
    const auto check = checks.fetch_add(1) + 1;
    if (check == sleep_on_check.load())
      usleep(sleep_microseconds.load());
    int remaining = checks_before_revocation.load();
    while (remaining > 0 && !checks_before_revocation.compare_exchange_weak(
                                remaining, remaining - 1)) {
    }
    const bool semantically_current = remaining != 0;
    return current && identity.generation == generation &&
           (revoke_on_check == 0 || check < revoke_on_check) &&
           semantically_current;
  }

  std::atomic<bool> current = true;
  std::atomic<std::uint64_t> generation = 47;
  mutable std::atomic<unsigned> checks = 0;
  std::atomic<unsigned> revoke_on_check = 0;
  std::atomic<unsigned> sleep_on_check = 0;
  std::atomic<unsigned> sleep_microseconds = 0;
  mutable std::atomic<int> checks_before_revocation = -1;
};

class Fixture {
public:
  explicit Fixture(std::string_view mode) {
    std::string pattern = "/tmp/omarchy-authenticated-channel-XXXXXX";
    root_ = mkdtemp(pattern.data());
    require(!root_.empty(),
            "cannot create authenticated-channel fixture root");
    revision_ = root_ / "revision";
    state_ = root_ / "state";
    std::filesystem::create_directories(revision_);
    std::filesystem::create_directories(state_);
    std::ofstream(revision_ / "worker-mode") << mode << '\n';
    require(chmod((revision_ / "worker-mode").c_str(), 0444) == 0 &&
                chmod(revision_.c_str(), 0555) == 0,
            "cannot make authenticated-channel revision immutable");
    revision_fd_ = std::make_unique<Descriptor>(
        open(revision_.c_str(), O_RDONLY | O_DIRECTORY | O_CLOEXEC));
    state_fd_ = std::make_unique<Descriptor>(
        open(state_.c_str(), O_RDONLY | O_DIRECTORY | O_CLOEXEC));
    require(revision_fd_->get() >= 0 && state_fd_->get() >= 0,
            "cannot open authenticated-channel fixture descriptors");
  }

  ~Fixture() {
    revision_fd_.reset();
    state_fd_.reset();
    static_cast<void>(chmod(revision_.c_str(), 0755));
    std::error_code ignored;
    std::filesystem::remove_all(root_, ignored);
  }

  launcher::TrustedLaunchRequest request() const {
    return {.plugin_id = "org.omarchy_d1",
            .revision_sha256 = std::string(64, 'd'),
            .generation = 47,
            .revision_directory_fd = revision_fd_->get(),
            .private_state_directory_fd = state_fd_->get()};
  }

private:
  std::filesystem::path root_;
  std::filesystem::path revision_;
  std::filesystem::path state_;
  std::unique_ptr<Descriptor> revision_fd_;
  std::unique_ptr<Descriptor> state_fd_;
};

std::unique_ptr<launcher::Worker>
launch_transport(Fixture &fixture, std::shared_ptr<Scope> scope) {
  auto supervisor = launcher::test_support::make_supervisor(
      FAKE_BWRAP_PATH, CHANNEL_PEER_PATH, std::move(scope));
  auto launched = supervisor.launch(fixture.request(), deadline_after(4s));
  if (!launched)
    std::cerr << "transport launch failure="
              << static_cast<int>(launched.failure)
              << " detail=" << launched.detail << '\n';
  require(static_cast<bool>(launched), "transport worker launch failed");
  return std::move(launched.worker);
}

void transport_suite() {
  {
    launcher::TerminationState termination;
    require(termination.begin(), "fresh teardown state did not start");
    termination.complete(false);
    require(!termination.succeeded() && !termination.begin(),
            "failed teardown was retried or reported as successful");
    termination.complete(true);
    require(!termination.succeeded(),
            "completed teardown failure was overwritten by later success");
  }
  {
    Fixture fixture("transport-max");
    auto worker = launch_transport(fixture, std::make_shared<Scope>());
    std::vector<std::byte> maximum(
        omarchy::plugin::wire::kHeaderSize +
        omarchy::plugin::wire::payload_cap(
            omarchy::plugin::wire::EndpointRole::broker));
    require(worker->try_send(launcher::EndpointRole::broker, maximum,
                             launcher::PacketSizeLimit{maximum.size()}) ==
                launcher::SendStatus::complete,
            "maximum legal broker datagram was rejected");
    const auto acknowledgement =
        worker->receive(launcher::EndpointRole::control,
                        launcher::PacketSizeLimit{1}, deadline_after(2s));
    require(acknowledgement && acknowledgement.payload.size() == 1 &&
                acknowledgement.payload.front() == std::byte{0x5a},
            "worker did not receive the complete maximum broker datagram");
    maximum.push_back(std::byte{});
    require(worker->try_send(launcher::EndpointRole::broker, maximum,
                             launcher::PacketSizeLimit{maximum.size()}) !=
                launcher::SendStatus::complete,
            "above-cap broker datagram was accepted");
    require(worker->terminate(deadline_after(4s)),
            "maximum-datagram worker did not terminate");
  }

  {
    Fixture fixture("transport-saturation");
    auto worker = launch_transport(fixture, std::make_shared<Scope>());
    const auto saturate = [&worker](launcher::EndpointRole role,
                                    std::size_t size) {
      std::vector<std::byte> datagram(size);
      const auto started = std::chrono::steady_clock::now();
      bool refused = false;
      for (unsigned attempt = 0; attempt < 10'000; ++attempt) {
        if (worker->try_send(role, datagram,
                             launcher::PacketSizeLimit{datagram.size()}) !=
            launcher::SendStatus::complete) {
          refused = true;
          break;
        }
      }
      require(refused && std::chrono::steady_clock::now() - started < 1s,
              "saturated endpoint blocked the trusted host");
    };
    saturate(launcher::EndpointRole::broker,
             omarchy::plugin::wire::kHeaderSize +
                 omarchy::plugin::wire::payload_cap(
                     omarchy::plugin::wire::EndpointRole::broker));
    saturate(launcher::EndpointRole::render,
             omarchy::plugin::wire::kHeaderSize +
                 omarchy::plugin::wire::payload_cap(
                     omarchy::plugin::wire::EndpointRole::render));
    require(worker->terminate(deadline_after(4s)),
            "saturated worker did not terminate");
  }
}

std::size_t descriptor_count() {
  std::size_t count = 0;
  for (const auto &entry :
       std::filesystem::directory_iterator("/proc/self/fd")) {
    (void)entry;
    ++count;
  }
  return count;
}

bool eventually_descriptor_count_at_most(std::size_t expected) {
  const auto deadline = std::chrono::steady_clock::now() + 2s;
  while (descriptor_count() > expected &&
         std::chrono::steady_clock::now() < deadline)
    usleep(1000);
  return descriptor_count() <= expected;
}

struct Session {
  Fixture fixture;
  std::shared_ptr<Scope> scope = std::make_shared<Scope>();
  std::shared_ptr<Authority> authority = std::make_shared<Authority>();
  launcher::Supervisor supervisor;
  channel::OpenResult opened;

  Session(std::string_view mode, std::string bwrap)
      : fixture(mode),
        supervisor(launcher::test_support::make_supervisor(
            std::move(bwrap), CHANNEL_PEER_PATH, scope)),
        opened(channel::AuthenticatedBrokerChannel::open(
            supervisor, fixture.request(), authority, deadline_after(2s))) {
    if (!opened) {
      std::cerr << "launch failure=" << static_cast<int>(opened.launch_failure)
                << " detail=" << opened.detail << '\n';
      fail("authenticated launch failed");
    }
    const auto &identity = opened.channel->identity();
    require(identity.plugin_id == "org.omarchy_d1" &&
                identity.revision_sha256 == std::string(64, 'd') &&
                identity.generation == 47 && identity.outer_worker_pid > 0 &&
                identity.outer_uid == getuid() &&
                identity.outer_gid == getgid(),
            "trusted launch identity was not bound exactly");
    require(scope->attached, "startup barrier released before scope attach");
  }
};

bool is_storage_request(const channel::AuthenticatedReceiveResult &result) {
  return result && result.message->role == wire::EndpointRole::broker &&
         result.message->message_type ==
             static_cast<std::uint16_t>(
                 permissions::OperationId::storage_read) &&
         result.message->correlation_id == 1 &&
         result.message->payload.size() == 24 &&
         result.message->descriptors.empty();
}

void fake_suite() {
  transport_suite();
  {
    Fixture fixture("valid");
    auto scope = std::make_shared<Scope>();
    auto authority = std::make_shared<Authority>();
    auto supervisor = launcher::test_support::make_supervisor(
        FAKE_BWRAP_PATH, CHANNEL_PEER_PATH, scope);
    const auto deadline = std::chrono::steady_clock::now() + 2s;
    auto opened = channel::AuthenticatedBrokerChannel::open(
        supervisor, fixture.request(), authority, deadline);
    channel::AuthenticatedReceiveResult request;
    require(opened && opened.channel->negotiate(deadline) &&
                (request = opened.channel->receive_authenticated(
                     launcher::EndpointMask::broker, deadline_after(2s))) &&
                is_storage_request(request),
            "one absolute launch-and-negotiate deadline was reset or lost");
  }
  {
    Fixture fixture("valid");
    auto supervisor = launcher::test_support::make_supervisor(
        FAKE_BWRAP_PATH, CHANNEL_PEER_PATH, std::make_shared<Scope>());
    auto opened = channel::AuthenticatedBrokerChannel::open(
        supervisor, fixture.request(), std::make_shared<Authority>(),
        std::chrono::steady_clock::now());
    require(!opened && opened.failure == channel::ChannelFailure::launch_failed,
            "expired caller deadline reached launch authority");
  }
  {
    Fixture fixture("valid");
    auto scope = std::make_shared<Scope>();
    auto authority = std::make_shared<Authority>();
    authority->sleep_on_check = 1;
    authority->sleep_microseconds = 300'000;
    auto supervisor = launcher::test_support::make_supervisor(
        FAKE_BWRAP_PATH, CHANNEL_PEER_PATH, scope);
    auto opened = channel::AuthenticatedBrokerChannel::open(
        supervisor, fixture.request(), authority, deadline_after(200ms));
    require(!opened &&
                opened.failure == channel::ChannelFailure::deadline_expired &&
                authority->checks.load() == 1 && eventually_removed(scope),
            "open published authority after its absolute deadline");
  }
  {
    Fixture fixture("valid");
    auto scope = std::make_shared<Scope>();
    auto authority = std::make_shared<Authority>();
    auto supervisor = launcher::test_support::make_supervisor(
        FAKE_BWRAP_PATH, CHANNEL_PEER_PATH, scope);
    const auto opening_deadline = std::chrono::steady_clock::now() + 200ms;
    auto opened = channel::AuthenticatedBrokerChannel::open(
        supervisor, fixture.request(), authority, opening_deadline);
    require(static_cast<bool>(opened),
            "opening-deadline clamp fixture did not launch");
    const auto checks_after_open = authority->checks.load();
    while (std::chrono::steady_clock::now() <= opening_deadline)
      usleep(1000);
    require(!opened.channel->negotiate(deadline_after(2s)) &&
                authority->checks.load() == checks_after_open &&
                opened.channel->failure() ==
                    channel::ChannelFailure::negotiation_failed,
            "fresh negotiation deadline reset the opening budget");
  }
  {
    Fixture fixture("valid");
    auto scope = std::make_shared<Scope>();
    auto authority = std::make_shared<Authority>();
    auto supervisor = launcher::test_support::make_supervisor(
        FAKE_BWRAP_PATH, CHANNEL_PEER_PATH, scope);
    auto opened = channel::AuthenticatedBrokerChannel::open(
        supervisor, fixture.request(), authority, deadline_after(2s));
    require(static_cast<bool>(opened),
            "WELCOME deadline fixture did not launch");
    const auto delayed_check = authority->checks.load() + 1;
    authority->sleep_on_check = delayed_check;
    authority->sleep_microseconds = 20'000;
    require(!opened.channel->negotiate(deadline_after(5ms)) &&
                authority->checks.load() >= delayed_check &&
                opened.channel->failure() ==
                    channel::ChannelFailure::negotiation_failed &&
                opened.channel->detail() ==
                    "endpoint negotiation deadline elapsed before WELCOME",
            "WELCOME was emitted after its absolute deadline");
  }
  {
    Fixture fixture("valid");
    auto scope = std::make_shared<Scope>();
    auto authority = std::make_shared<Authority>();
    auto supervisor = launcher::test_support::make_supervisor(
        FAKE_BWRAP_PATH, CHANNEL_PEER_PATH, scope);
    auto opened = channel::AuthenticatedBrokerChannel::open(
        supervisor, fixture.request(), authority, deadline_after(2s));
    require(static_cast<bool>(opened),
            "aggregate deadline fixture did not launch");
    const auto delayed_check = authority->checks.load() + 4;
    authority->sleep_on_check = delayed_check;
    authority->sleep_microseconds = 20'000;
    require(!opened.channel->negotiate(deadline_after(10ms)) &&
                authority->checks.load() >= delayed_check &&
                !opened.channel->ready(),
            "aggregate readiness published after its absolute deadline");
  }
  {
    Session reversed("reverse-order", FAKE_BWRAP_PATH);
    channel::AuthenticatedReceiveResult request;
    require(reversed.opened.channel->negotiate(deadline_after(2s)) &&
                (request = reversed.opened.channel->receive_authenticated(
                     launcher::EndpointMask::broker, deadline_after(2s))) &&
                is_storage_request(request),
            "arbitrary-order endpoint negotiation was serialized by lane");
  }
  {
    Session multi("multi-lane", FAKE_BWRAP_PATH);
    require(
        multi.opened.channel->negotiate(deadline_after(2s)) &&
            multi.opened.channel->arm_readiness(
                launcher::EndpointMask::all, launcher::EndpointMask::control),
        "authenticated multi-lane fixture did not become ready");
    auto render = multi.opened.channel->receive_authenticated(
        launcher::EndpointMask::render, deadline_after(2s));
    require(render && render.message->role == wire::EndpointRole::render &&
                render.message->message_type ==
                    static_cast<std::uint16_t>(
                        surface::RenderMessageType::frame_ready) &&
                render.message->correlation_id == 0 &&
                render.message->payload.size() == 40 &&
                render.message->descriptors.empty(),
            "allowed render lane did not publish an owning semantic message");
    auto broker_message = multi.opened.channel->receive_authenticated(
        launcher::EndpointMask::broker, deadline_after(2s));
    require(broker_message &&
                broker_message.message->role == wire::EndpointRole::broker &&
                broker_message.message->message_type ==
                    static_cast<std::uint16_t>(
                        permissions::OperationId::storage_read) &&
                broker_message.message->correlation_id == 1 &&
                broker_message.message->payload.size() == 24 &&
                broker_message.message->descriptors.empty(),
            "disallowed queued broker lane was consumed early");
    auto owned = std::move(*broker_message.message);
    require(multi.opened.channel->terminate(deadline_after(2s)) &&
                owned.payload.size() == 24 && owned.correlation_id == 1,
            "authenticated payload lifetime remained tied to channel storage");
  }
  {
    Session empty("host-saturation", FAKE_BWRAP_PATH);
    require(empty.opened.channel->negotiate(deadline_after(2s)),
            "nonblocking empty fixture did not negotiate");
    const auto first = empty.opened.channel->try_receive_authenticated(
        launcher::EndpointMask::all);
    const auto second = empty.opened.channel->try_receive_authenticated(
        launcher::EndpointMask::all);
    require(first.status == channel::AuthenticatedReceiveStatus::would_block &&
                !first.message &&
                second.status ==
                    channel::AuthenticatedReceiveStatus::would_block &&
                !second.message && !empty.opened.channel->failed(),
            "empty authenticated try blocked or consumed state");
  }
  {
    Session multi("multi-lane", FAKE_BWRAP_PATH);
    require(multi.opened.channel->negotiate(deadline_after(2s)) &&
                await_channel_readable(*multi.opened.channel),
            "nonblocking fair fixture did not become readable");
    const auto broker_message = multi.opened.channel->try_receive_authenticated(
        launcher::EndpointMask::all);
    require(broker_message &&
                broker_message.message->role == wire::EndpointRole::broker &&
                broker_message.message->message_type ==
                    static_cast<std::uint16_t>(
                        permissions::OperationId::storage_read) &&
                broker_message.message->correlation_id == 1 &&
                broker_message.message->payload.size() == 24 &&
                broker_message.message->descriptors.empty(),
            "authenticated try lost the first fair semantic message");
    require(await_channel_readable(*multi.opened.channel),
            "render lane was not readable after the fair first receive");
    const auto render_message = multi.opened.channel->try_receive_authenticated(
        launcher::EndpointMask::all);
    const auto empty = multi.opened.channel->try_receive_authenticated(
        launcher::EndpointMask::all);
    require(
        render_message &&
            render_message.message->role == wire::EndpointRole::render &&
            render_message.message->message_type ==
                static_cast<std::uint16_t>(
                    surface::RenderMessageType::frame_ready) &&
            render_message.message->correlation_id == 0 &&
            render_message.message->payload.size() == 40 &&
            render_message.message->descriptors.empty() &&
            empty.status == channel::AuthenticatedReceiveStatus::would_block &&
            !empty.message && !multi.opened.channel->failed(),
        "authenticated try consumed more than one lane or changed fairness");
  }
  {
    Session error("render-typed-error", FAKE_BWRAP_PATH);
    require(error.opened.channel->negotiate(deadline_after(2s)),
            "render typed-error fixture did not negotiate");
    const auto received = error.opened.channel->receive_authenticated(
        launcher::EndpointMask::render, deadline_after(2s));
    surface::RenderTypedError decoded{};
    require(received &&
                received.message->role == wire::EndpointRole::render &&
                received.message->message_type ==
                    static_cast<std::uint16_t>(
                        wire::CommonMessageType::typed_error) &&
                received.message->descriptors.empty() &&
                surface::decode_render_error(received.message->payload,
                                             decoded) &&
                decoded.reason ==
                    surface::RenderErrorReason::invalid_allocation &&
                !error.opened.channel->failed(),
            "zero-descriptor render typed error failed authentication");
  }
  {
    Session replay("replay", FAKE_BWRAP_PATH);
    require(replay.opened.channel->negotiate(deadline_after(2s)) &&
                await_channel_readable(*replay.opened.channel),
            "nonblocking replay fixture did not become readable");
    const auto first = replay.opened.channel->try_receive_authenticated(
        launcher::EndpointMask::broker);
    require(first && await_channel_readable(*replay.opened.channel),
            "nonblocking replay fixture lost its first message");
    const auto repeated = replay.opened.channel->try_receive_authenticated(
        launcher::EndpointMask::broker);
    require(repeated.status == channel::AuthenticatedReceiveStatus::fatal &&
                !repeated.message && replay.opened.channel->failed(),
            "authenticated try published a replayed lane sequence");
  }
  {
    Session malformed("wrong-sequence-tag", FAKE_BWRAP_PATH);
    require(malformed.opened.channel->negotiate(deadline_after(2s)) &&
                await_channel_readable(*malformed.opened.channel),
            "nonblocking schema fixture did not become readable");
    const auto result = malformed.opened.channel->try_receive_authenticated(
        launcher::EndpointMask::broker);
    require(result.status == channel::AuthenticatedReceiveStatus::fatal &&
                !result.message && malformed.opened.channel->failed(),
            "authenticated try bypassed envelope schema validation");
  }
  {
    Session revoked("multi-lane", FAKE_BWRAP_PATH);
    require(revoked.opened.channel->negotiate(deadline_after(2s)) &&
                await_channel_readable(*revoked.opened.channel),
            "nonblocking authority fixture did not become readable");
    revoked.authority->revoke_after_successful_checks(1);
    const auto result = revoked.opened.channel->try_receive_authenticated(
        launcher::EndpointMask::broker);
    require(result.status == channel::AuthenticatedReceiveStatus::fatal &&
                !result.message && revoked.opened.channel->failed(),
            "authenticated try published across its final authority fence");
  }
  {
    Session exited("ready-loss", FAKE_BWRAP_PATH);
    require(exited.opened.channel->negotiate(deadline_after(2s)) &&
                kill(exited.opened.channel->identity().outer_worker_pid,
                     SIGUSR1) == 0,
            "nonblocking pidfd fixture did not negotiate or exit");
    const auto deadline = std::chrono::steady_clock::now() + 2s;
    while (exited.opened.channel->alive() &&
           std::chrono::steady_clock::now() < deadline)
      usleep(1000);
    const auto result = exited.opened.channel->try_receive_authenticated(
        launcher::EndpointMask::broker);
    require(
        (result.status == channel::AuthenticatedReceiveStatus::peer_closed ||
         result.status == channel::AuthenticatedReceiveStatus::fatal) &&
            !result.message && exited.opened.channel->failed() &&
            exited.opened.channel->failure() ==
                channel::ChannelFailure::peer_failure,
        "authenticated try ignored authoritative pidfd exit state");
  }
  {
    Session exited("stderr-ready-loss", FAKE_BWRAP_PATH);
    require(exited.opened.channel->negotiate(deadline_after(2s)) &&
                kill(exited.opened.channel->identity().outer_worker_pid,
                     SIGUSR1) == 0,
            "stderr preservation fixture did not negotiate or exit");
    const auto deadline = std::chrono::steady_clock::now() + 2s;
    while (exited.opened.channel->alive() &&
           std::chrono::steady_clock::now() < deadline)
      usleep(1000);
    std::array<int, 2> diagnostic_pipe{};
    require(pipe2(diagnostic_pipe.data(), O_CLOEXEC) == 0,
            "could not create host diagnostic capture pipe");
    Descriptor diagnostic_read(diagnostic_pipe[0]);
    Descriptor diagnostic_write(diagnostic_pipe[1]);
    Descriptor saved_standard_error(dup(STDERR_FILENO));
    require(saved_standard_error.get() >= 0 &&
                dup2(diagnostic_write.get(), STDERR_FILENO) >= 0,
            "could not capture host diagnostic output");
    const auto result = exited.opened.channel->try_receive_authenticated(
        launcher::EndpointMask::broker);
    require(dup2(saved_standard_error.get(), STDERR_FILENO) >= 0,
            "could not restore host diagnostic output");
    std::array<char, 512> diagnostic{};
    const auto diagnostic_size =
        read(diagnostic_read.get(), diagnostic.data(), diagnostic.size());
    const std::string_view diagnostic_text(
        diagnostic.data(), diagnostic_size > 0
                               ? static_cast<std::size_t>(diagnostic_size)
                               : 0);
    require((result.status ==
                 channel::AuthenticatedReceiveStatus::peer_closed ||
             result.status == channel::AuthenticatedReceiveStatus::fatal) &&
                diagnostic_text.find("untrusted-stderr-bytes=8192") !=
                    std::string_view::npos &&
                diagnostic_text.find("forged") == std::string_view::npos &&
                diagnostic_text.find("secret") == std::string_view::npos &&
                diagnostic_text.find("Service.qml") ==
                    std::string_view::npos,
            "forged sidecar or QML stderr crossed the host diagnostic "
            "boundary");
  }
  {
    Session replay("replay", FAKE_BWRAP_PATH);
    require(replay.opened.channel->negotiate(deadline_after(2s)),
            "typed replay fixture did not negotiate");
    const auto first = replay.opened.channel->receive_authenticated(
        launcher::EndpointMask::broker, deadline_after(2s));
    const auto second = replay.opened.channel->receive_authenticated(
        launcher::EndpointMask::broker, deadline_after(2s));
    require(first &&
                second.status == channel::AuthenticatedReceiveStatus::fatal &&
                replay.opened.channel->failed(),
        "typed receive published a same-lane replay or broker effect");
  }
  {
    Session wrong_tag("wrong-sequence-tag", FAKE_BWRAP_PATH);
    require(wrong_tag.opened.channel->negotiate(deadline_after(2s)) &&
                wrong_tag.opened.channel
                        ->receive_authenticated(launcher::EndpointMask::broker,
                                                deadline_after(2s))
                        .status == channel::AuthenticatedReceiveStatus::fatal,
            "typed receive accepted a transplanted lane sequence");
  }
  {
    Session revoked("multi-lane", FAKE_BWRAP_PATH);
    require(revoked.opened.channel->negotiate(deadline_after(2s)),
            "post-receive revocation fixture did not negotiate");
    revoked.authority->revoke_on_check = revoked.authority->checks.load() + 3;
    auto result = revoked.opened.channel->receive_authenticated(
        launcher::EndpointMask::render, deadline_after(2s));
    require(result.status == channel::AuthenticatedReceiveStatus::fatal &&
                !result.message && revoked.opened.channel->failed(),
            "revoked message was published after its final authority fence");
  }
  {
    Session delayed("multi-lane", FAKE_BWRAP_PATH);
    require(delayed.opened.channel->negotiate(deadline_after(2s)),
            "final receive deadline fixture did not negotiate");
    delayed.authority->sleep_on_check = delayed.authority->checks.load() + 3;
    delayed.authority->sleep_microseconds = 20'000;
    auto result = delayed.opened.channel->receive_authenticated(
        launcher::EndpointMask::render, deadline_after(5ms));
    require(result.status == channel::AuthenticatedReceiveStatus::fatal &&
                !result.message &&
                delayed.opened.channel->failure() ==
                    channel::ChannelFailure::deadline_expired,
            "slow final authority check published after receive deadline");
  }
  {
    Session first("valid", FAKE_BWRAP_PATH);
    Session second("valid", FAKE_BWRAP_PATH);
    require(first.opened.channel->negotiate(deadline_after(2s)) &&
                second.opened.channel->negotiate(deadline_after(2s)),
            "prepared-send origin fixtures did not negotiate");
    auto prepared = first.opened.channel->prepare_send(
        wire::EndpointRole::broker, broker::kBrokerResultMessage, 1, {});
    require(prepared.has_value(), "origin-bound send was not prepared");
    channel::PreparedSend moved(std::move(*prepared));
    require(first.opened.channel->try_send(*prepared, deadline_after(2s)) ==
                    channel::ChannelSendStatus::fatal &&
                second.opened.channel->try_send(moved, deadline_after(2s)) ==
                    channel::ChannelSendStatus::fatal &&
                moved.pending() &&
                first.opened.channel->try_send(moved, deadline_after(2s)) ==
                    channel::ChannelSendStatus::complete &&
                !moved.pending(),
            "moved-from or foreign prepared datagram retained send authority");
  }
  {
    Session stale("valid", FAKE_BWRAP_PATH);
    require(stale.opened.channel->negotiate(deadline_after(2s)),
            "stale prepared-send fixture did not negotiate");
    stale.authority->generation = 48;
    require(!stale.opened.channel->prepare_send(
                wire::EndpointRole::broker, broker::kBrokerResultMessage, 1,
                {}) &&
                stale.opened.channel->failed(),
            "revoked binding retained packet preparation authority");
  }
  {
    Session stale("valid", FAKE_BWRAP_PATH);
    require(stale.opened.channel->negotiate(deadline_after(2s)),
            "prepared-send revocation fixture did not negotiate");
    auto prepared = stale.opened.channel->prepare_send(
        wire::EndpointRole::broker, broker::kBrokerResultMessage, 1, {});
    stale.authority->generation = 48;
    require(
        prepared &&
            stale.opened.channel->try_send(*prepared, deadline_after(2s)) ==
                channel::ChannelSendStatus::not_ready &&
            !prepared->pending() && stale.opened.channel->failed() &&
            eventually_removed(stale.scope),
        "authority loss between prepare and send retained transport authority");
  }
  {
    Session session("valid", FAKE_BWRAP_PATH);
    require(session.opened.channel->negotiate(deadline_after(2s)),
            "lifecycle-transition fixture did not become ready");
    session.authority->generation = 48;
    const auto received = session.opened.channel->receive_authenticated(
        launcher::EndpointMask::broker, deadline_after(2s));
    require(received.status == channel::AuthenticatedReceiveStatus::fatal &&
                session.opened.channel->failure() ==
                    channel::ChannelFailure::stale_generation &&
                eventually_removed(session.scope),
            "superseded lifecycle generation reached typed receive");
  }
  {
    Session session("valid", FAKE_BWRAP_PATH);
    const auto received = session.opened.channel->receive_authenticated(
        launcher::EndpointMask::broker, std::chrono::steady_clock::now());
    require(received.status == channel::AuthenticatedReceiveStatus::not_ready &&
                session.opened.channel->failed() &&
                eventually_removed(session.scope),
            "typed receive was not gated on aggregate readiness");
    require(session.opened.channel->terminate(deadline_after(6s)),
            "pre-readiness refusal did not tear down cleanly");
  }
  {
    Session session("valid", FAKE_BWRAP_PATH);
    require(session.opened.channel->negotiate(deadline_after(2s)) &&
                session.opened.channel->ready(),
            "valid aggregate endpoint negotiation failed");
    const auto request = session.opened.channel->receive_authenticated(
        launcher::EndpointMask::broker, deadline_after(2s));
    const auto empty = session.opened.channel->try_receive_authenticated(
        launcher::EndpointMask::broker);
    require(is_storage_request(request) &&
                empty.status ==
                    channel::AuthenticatedReceiveStatus::would_block &&
                !empty.message,
            "authenticated broker request was not published exactly once");
    require(session.opened.channel->terminate(deadline_after(6s)) &&
                eventually_removed(session.scope),
            "valid channel teardown was not bounded");
  }
  for (const std::string_view mode :
       {"pre-ready", "wrong-role", "bad-version", "descendant", "peer-loss"}) {
    Session session(mode, FAKE_BWRAP_PATH);
    require(!session.opened.channel->negotiate(deadline_after(2s)) &&
                session.opened.channel->failed() &&
                eventually_removed(session.scope),
            "unauthenticated handshake reached broker receive");
  }

  for (const std::string_view mode : {"descriptor", "descriptor-flood"}) {
    const auto descriptors_before = descriptor_count();
    for (unsigned attempt = 0; attempt < 16; ++attempt) {
      Session session(mode, FAKE_BWRAP_PATH);
      require(!session.opened.channel->negotiate(deadline_after(2s)),
              "descriptor-bearing HELLO was not quarantined");
    }
    require(eventually_descriptor_count_at_most(descriptors_before),
            "descriptor quarantine leaked broker-side descriptors");
  }
  {
    const auto descriptors_before = descriptor_count();
    for (unsigned attempt = 0; attempt < 16; ++attempt) {
      Session injected("post-ready-descriptor", FAKE_BWRAP_PATH);
      require(injected.opened.channel->negotiate(deadline_after(2s)),
              "typed descriptor quarantine did not negotiate");
      const auto received = injected.opened.channel->receive_authenticated(
          launcher::EndpointMask::broker, deadline_after(2s));
      require(received.status == channel::AuthenticatedReceiveStatus::fatal &&
                  !received.message,
              "typed receive published an undeclared descriptor");
    }
    require(eventually_descriptor_count_at_most(descriptors_before),
            "typed receive quarantine leaked owned descriptors");
  }

  for (const std::string_view mode : {"stale", "bad-role-version"}) {
    Session session(mode, FAKE_BWRAP_PATH);
    require(session.opened.channel->negotiate(deadline_after(2s)),
            "post-readiness attack did not negotiate first");
    const auto received = session.opened.channel->receive_authenticated(
        launcher::EndpointMask::broker, deadline_after(2s));
    require(received.status == channel::AuthenticatedReceiveStatus::fatal &&
                session.opened.channel->failed() &&
                eventually_removed(session.scope),
            "post-readiness authentication failure reached broker receive");
  }

  for (const std::string_view mode :
       {"wrong-sequence-tag", "unsupported-envelope-version-after-ready",
        "unknown-message", "wrong-direction", "inbound-typed-error",
        "short-payload", "zero-correlation", "post-ready-descriptor"}) {
    Session session(mode, FAKE_BWRAP_PATH);
    require(session.opened.channel->negotiate(deadline_after(2s)),
            "post-ready lane/type/descriptor attack did not negotiate");
    const auto received = session.opened.channel->receive_authenticated(
        launcher::EndpointMask::broker, deadline_after(2s));
    require(received.status == channel::AuthenticatedReceiveStatus::fatal,
            "post-ready lane/type/descriptor attack reached publication");
  }
  {
    Session descriptors("valid", FAKE_BWRAP_PATH);
    require(descriptors.opened.channel->negotiate(deadline_after(2s)),
            "prepared descriptor fixture did not negotiate");
    auto prepared = descriptors.opened.channel->prepare_send(
        wire::EndpointRole::broker, broker::kBrokerResultMessage, 9, {});
    Descriptor injected(open("/dev/null", O_RDONLY | O_CLOEXEC));
    const std::array borrowed{injected.get()};
    require(prepared && injected.get() >= 0 &&
                descriptors.opened.channel->try_send(
                    *prepared, deadline_after(2s), borrowed) ==
                    channel::ChannelSendStatus::fatal &&
                !prepared->pending() && descriptors.opened.channel->failed(),
            "broker prepared send accepted an undeclared descriptor");
  }
  {
    Session descriptors("valid", FAKE_BWRAP_PATH);
    require(descriptors.opened.channel->negotiate(deadline_after(2s)),
            "render descriptor fixture did not negotiate");
    const std::array<std::byte, 96> allocation{};
    auto prepared = descriptors.opened.channel->prepare_send(
        wire::EndpointRole::render,
        static_cast<std::uint16_t>(
            surface::RenderMessageType::surface_allocate),
        10, allocation);
    require(prepared &&
                descriptors.opened.channel->try_send(*prepared,
                                                     deadline_after(2s)) ==
                    channel::ChannelSendStatus::fatal &&
                descriptors.opened.channel->failed(),
            "render prepared send omitted its required descriptor");
  }
  {
    Session common("valid", FAKE_BWRAP_PATH);
    require(common.opened.channel->negotiate(deadline_after(2s)),
            "render common-message fixture did not negotiate");
    auto prepared = common.opened.channel->prepare_send(
        wire::EndpointRole::render,
        static_cast<std::uint16_t>(wire::CommonMessageType::cancel), 10, {});
    require(prepared &&
                common.opened.channel->try_send(*prepared,
                                                deadline_after(2s)) ==
                    channel::ChannelSendStatus::complete &&
                !common.opened.channel->failed(),
            "zero-descriptor render cancellation failed preparation");
  }
  {
    Session saturated("host-saturation", FAKE_BWRAP_PATH);
    require(saturated.opened.channel->negotiate(deadline_after(2s)),
            "prepared-send saturation fixture did not negotiate");
    const auto timed_receive = saturated.opened.channel->receive_authenticated(
        launcher::EndpointMask::render, deadline_after(5ms));
    require(timed_receive.status ==
                    channel::AuthenticatedReceiveStatus::would_block &&
                !timed_receive.message && !saturated.opened.channel->failed(),
            "healthy typed receive timeout failed the channel");
    std::vector<std::byte> payload(65536);
    std::optional<channel::PreparedSend> blocked;
    for (unsigned attempt = 0; attempt < 10'000 && !blocked; ++attempt) {
      auto prepared = saturated.opened.channel->prepare_send(
          wire::EndpointRole::broker, broker::kBrokerResultMessage,
          attempt + 1, payload);
      require(prepared.has_value(), "broker datagram preparation failed");
      const auto status =
          saturated.opened.channel->try_send(*prepared, deadline_after(2s));
      if (status == channel::ChannelSendStatus::would_block)
        blocked.emplace(std::move(*prepared));
      else
        require(status == channel::ChannelSendStatus::complete,
                "prepared send failed before transport saturation");
    }
    require(blocked.has_value(), "trusted channel could not be saturated");
    require(
        saturated.opened.channel->try_send(*blocked, deadline_after(2s)) ==
                channel::ChannelSendStatus::would_block &&
            saturated.opened.channel->arm_readiness(
                launcher::EndpointMask::none, launcher::EndpointMask::broker),
        "would-block retry lost its pending datagram or lane interest");
    const auto invalid_receive =
        saturated.opened.channel->receive_authenticated(
            launcher::EndpointMask::render, deadline_after(20ms));
    require(invalid_receive.status ==
                    channel::AuthenticatedReceiveStatus::not_ready &&
                !invalid_receive.message && !saturated.opened.channel->failed(),
            "unarmed receive consumed transport state or killed the channel");
    pollfd readiness{.fd = saturated.opened.channel->readiness_fd(),
                     .events = POLLIN,
                     .revents = 0};
    require(poll(&readiness, 1, 20) == 0,
            "masked read lane spuriously woke blocked-write readiness");
    require(
        kill(saturated.opened.channel->identity().outer_worker_pid, SIGUSR1) ==
                0 &&
            poll(&readiness, 1, 2000) == 1 &&
            saturated.opened.channel->try_send(*blocked, deadline_after(2s)) ==
                channel::ChannelSendStatus::complete &&
            !blocked->pending(),
        "blocked prepared datagram did not complete after write readiness");
  }

  {
    Session bounded("host-saturation", FAKE_BWRAP_PATH);
    require(bounded.opened.channel->negotiate(deadline_after(2s)),
            "bounded termination fixture did not negotiate");
    const auto started = std::chrono::steady_clock::now();
    const auto first = bounded.opened.channel->terminate(started);
    const auto repeated = bounded.opened.channel->terminate(deadline_after(2s));
    require(first == repeated &&
                std::chrono::steady_clock::now() - started < 100ms,
            "expired termination deadline blocked or reset on retry");
  }

  {
    Session session("ready-loss", FAKE_BWRAP_PATH);
    require(session.opened.channel->negotiate(deadline_after(2s)),
            "silent-exit liveness fixture did not negotiate");
    require(
        kill(session.opened.channel->identity().outer_worker_pid, SIGUSR1) == 0,
        "host could not release the post-readiness exit barrier");
    const auto deadline = std::chrono::steady_clock::now() + 2s;
    while (session.opened.channel->alive() &&
           std::chrono::steady_clock::now() < deadline) {
      usleep(1000);
    }
    const auto terminal = session.opened.channel->receive_authenticated(
        launcher::EndpointMask::broker, deadline_after(2s));
    require(
        !session.opened.channel->alive() &&
            (terminal.status ==
                 channel::AuthenticatedReceiveStatus::peer_closed ||
             terminal.status == channel::AuthenticatedReceiveStatus::fatal) &&
            !terminal.message &&
            session.opened.channel->failure() ==
                channel::ChannelFailure::peer_failure &&
            session.opened.channel->terminate(deadline_after(6s)) &&
            eventually_removed(session.scope),
        "post-readiness peer exit remained live or published a message");
  }
}

int bwrap_suite() {
  if (access(BWRAP_PATH, X_OK) < 0) {
    return 77;
  }
  try {
    Session valid("valid", BWRAP_PATH);
    if (!valid.opened.channel->negotiate(deadline_after(4s))) {
      return 77;
    }
    const auto request = valid.opened.channel->receive_authenticated(
        launcher::EndpointMask::broker, deadline_after(4s));
    require(is_storage_request(request),
            "real Bubblewrap authenticated receive failed");
    require(valid.opened.channel->terminate(deadline_after(6s)),
            "real Bubblewrap teardown failed");

    Session stale("stale", BWRAP_PATH);
    require(stale.opened.channel->negotiate(deadline_after(4s)),
            "real Bubblewrap stale fixture did not negotiate");
    const auto rejected = stale.opened.channel->receive_authenticated(
        launcher::EndpointMask::broker, deadline_after(4s));
    require(rejected.status == channel::AuthenticatedReceiveStatus::fatal,
            "real Bubblewrap stale generation reached publication");
  } catch (...) {
    return 77;
  }
  return 0;
}

} // namespace

int main(int argc, char **argv) {
  require(argc == 2, "expected fake or bwrap suite selector");
  if (std::string_view(argv[1]) == "fake") {
    fake_suite();
    return 0;
  }
  if (std::string_view(argv[1]) == "bwrap") {
    return bwrap_suite();
  }
  fail("unknown suite selector");
}
