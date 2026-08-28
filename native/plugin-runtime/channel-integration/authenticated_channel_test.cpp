#include "authenticated_channel.hpp"

#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

#include <chrono>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <memory>
#include <string>
#include <string_view>
#include <vector>

namespace channel = omarchy::plugin_runtime::channel;
namespace launcher = omarchy::plugin_runtime::launcher;
namespace sandbox = omarchy::plugin_runtime::sandbox;

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
  bool probe(std::string &) override { return true; }
  bool attach(std::string_view unit, pid_t monitor_pid, pid_t worker_pid,
              const sandbox::SandboxPlan &plan,
              std::chrono::milliseconds timeout, std::string &) override {
    require(monitor_pid > 0 && worker_pid > 0 && timeout == 5s,
            "resource scope did not receive bounded process identities");
    require(plan.worker_descriptors == std::vector<int>({3, 4, 5}),
            "resource scope saw a changed endpoint contract");
    name = unit;
    attached = true;
    return true;
  }
  void kill(std::string_view unit) noexcept override {
    if (unit == name) {
      ++kills;
    }
  }
  void remove(std::string_view unit) noexcept override {
    if (unit == name) {
      ++removes;
    }
  }

  std::string name;
  bool attached = false;
  unsigned kills = 0;
  unsigned removes = 0;
};

class Dispatcher final : public channel::BrokerDispatcher {
public:
  bool accepts(const launcher::LaunchIdentity &identity) const noexcept override {
    return identity.plugin_id == accepted_plugin &&
           identity.revision_sha256 == accepted_revision &&
           identity.generation == accepted_generation;
  }
  bool dispatch(const omarchy::plugin::wire::PacketView &packet) override {
    ++calls;
    last_generation = packet.header.launch_generation;
    return true;
  }
  unsigned calls = 0;
  std::uint64_t last_generation = 0;
  std::string accepted_plugin = "org.omarchy_d1";
  std::string accepted_revision = std::string(64, 'd');
  std::uint64_t accepted_generation = 47;
};

class ThrowingDispatcher final : public channel::BrokerDispatcher {
public:
  bool accepts(const launcher::LaunchIdentity &identity) const noexcept override {
    return identity.plugin_id == "org.omarchy_d1" &&
           identity.revision_sha256 == std::string(64, 'd') &&
           identity.generation == 47;
  }
  bool dispatch(const omarchy::plugin::wire::PacketView &) override {
    ++calls;
    throw 7;
  }
  unsigned calls = 0;
};

class Authority final : public channel::GenerationAuthority {
public:
  bool
  is_current(const launcher::LaunchIdentity &identity) const noexcept override {
    return current && identity.generation == generation;
  }

  bool current = true;
  std::uint64_t generation = 47;
};

class Fixture {
public:
  explicit Fixture(std::string_view mode) {
    std::string pattern = "/tmp/omarchy-d1-XXXXXX";
    root_ = mkdtemp(pattern.data());
    require(!root_.empty(), "cannot create D1 fixture root");
    revision_ = root_ / "revision";
    state_ = root_ / "state";
    std::filesystem::create_directories(revision_);
    std::filesystem::create_directories(state_);
    std::ofstream(revision_ / "d1-mode") << mode << '\n';
    require(chmod((revision_ / "d1-mode").c_str(), 0444) == 0 &&
                chmod(revision_.c_str(), 0555) == 0,
            "cannot make D1 revision immutable");
    revision_fd_ = std::make_unique<Descriptor>(
        open(revision_.c_str(), O_RDONLY | O_DIRECTORY | O_CLOEXEC));
    state_fd_ = std::make_unique<Descriptor>(
        open(state_.c_str(), O_RDONLY | O_DIRECTORY | O_CLOEXEC));
    require(revision_fd_->get() >= 0 && state_fd_->get() >= 0,
            "cannot open D1 fixture descriptors");
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
  auto supervisor = launcher::Supervisor::forTestOnly(
      FAKE_BWRAP_PATH, CHANNEL_PEER_PATH, std::move(scope));
  auto launched = supervisor.launch(fixture.request());
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
    require(worker->send(launcher::EndpointRole::broker, maximum),
            "maximum legal broker datagram was rejected");
    const auto acknowledgement =
        worker->receive(launcher::EndpointRole::control, 1, 2s);
    require(acknowledgement && acknowledgement.payload.size() == 1 &&
                acknowledgement.payload.front() == std::byte{0x5a},
            "worker did not receive the complete maximum broker datagram");
    maximum.push_back(std::byte{});
    require(!worker->send(launcher::EndpointRole::broker, maximum),
            "above-cap broker datagram was accepted");
    require(worker->terminate(), "maximum-datagram worker did not terminate");
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
        if (!worker->send(role, datagram)) {
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
    require(worker->terminate(), "saturated worker did not terminate");
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

struct Session {
  Fixture fixture;
  std::shared_ptr<Scope> scope = std::make_shared<Scope>();
  std::shared_ptr<Dispatcher> dispatcher = std::make_shared<Dispatcher>();
  std::shared_ptr<Authority> authority = std::make_shared<Authority>();
  launcher::Supervisor supervisor;
  channel::OpenResult opened;

  Session(std::string_view mode, std::string bwrap)
      : fixture(mode), supervisor(launcher::Supervisor::forTestOnly(
                           std::move(bwrap), CHANNEL_PEER_PATH, scope)),
        opened(channel::AuthenticatedBrokerChannel::open(
            supervisor, fixture.request(), dispatcher, authority)) {
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

void fake_suite() {
  transport_suite();
  {
    Fixture fixture("valid");
    auto scope = std::make_shared<Scope>();
    auto dispatcher = std::make_shared<Dispatcher>();
    dispatcher->accepted_plugin = "org.other_plugin";
    auto authority = std::make_shared<Authority>();
    auto supervisor = launcher::Supervisor::forTestOnly(
        FAKE_BWRAP_PATH, CHANNEL_PEER_PATH, scope);
    auto opened = channel::AuthenticatedBrokerChannel::open(
        supervisor, fixture.request(), dispatcher, authority);
    require(!opened &&
                opened.failure == channel::ChannelFailure::identity_mismatch &&
                dispatcher->calls == 0 && scope->removes == 1,
            "mismatched broker dispatcher retained cross-plugin authority");
  }
  {
    Session session("valid", FAKE_BWRAP_PATH);
    require(!session.opened.channel->negotiate(std::chrono::hours(24)) &&
                session.opened.channel->failed() &&
                session.dispatcher->calls == 0,
            "unbounded negotiation timeout reached deadline arithmetic");
  }

  {
    Fixture fixture("valid");
    auto scope = std::make_shared<Scope>();
    auto dispatcher = std::make_shared<ThrowingDispatcher>();
    auto authority = std::make_shared<Authority>();
    auto supervisor = launcher::Supervisor::forTestOnly(
        FAKE_BWRAP_PATH, CHANNEL_PEER_PATH, scope);
    auto opened = channel::AuthenticatedBrokerChannel::open(
        supervisor, fixture.request(), dispatcher, authority);
    require(opened && opened.channel->negotiate(2s) &&
                opened.channel->dispatch_one(2s) ==
                    channel::DispatchStatus::fatal &&
                opened.channel->failure() ==
                    channel::ChannelFailure::dispatch_failed &&
                dispatcher->calls == 1 && scope->removes == 1,
            "throwing dispatcher escaped the authenticated channel boundary");
  }
  {
    Session session("valid", FAKE_BWRAP_PATH);
    require(session.opened.channel->negotiate(2s),
            "lifecycle-transition fixture did not become ready");
    session.authority->generation = 48;
    require(session.opened.channel->dispatch_one(2s) ==
                    channel::DispatchStatus::fatal &&
                session.opened.channel->failure() ==
                    channel::ChannelFailure::stale_generation &&
                session.dispatcher->calls == 0 && session.scope->removes == 1,
            "superseded lifecycle generation reached broker dispatch");
  }
  {
    Session session("valid", FAKE_BWRAP_PATH);
    require(session.opened.channel->negotiate(2s),
            "dispatcher-transition fixture did not become ready");
    session.dispatcher->accepted_plugin = "org.other_plugin";
    require(session.opened.channel->dispatch_one(2s) ==
                    channel::DispatchStatus::fatal &&
                session.opened.channel->failure() ==
                    channel::ChannelFailure::stale_generation &&
                session.dispatcher->calls == 0 && session.scope->removes == 1,
            "changed dispatcher binding reached authenticated dispatch");
  }
  {
    Session session("valid", FAKE_BWRAP_PATH);
    require(session.opened.channel->dispatch_one(0ms) ==
                    channel::DispatchStatus::not_ready &&
                session.opened.channel->failed() &&
                session.dispatcher->calls == 0 && session.scope->removes == 1,
            "broker dispatch was not gated on aggregate readiness");
    require(session.opened.channel->terminate(),
            "pre-readiness refusal did not tear down cleanly");
  }
  {
    Session session("valid", FAKE_BWRAP_PATH);
    require(session.opened.channel->negotiate(2s) &&
                session.opened.channel->ready(),
            "valid aggregate endpoint negotiation failed");
    require(session.opened.channel->dispatch_one(2s) ==
                    channel::DispatchStatus::dispatched &&
                session.dispatcher->calls == 1 &&
                session.dispatcher->last_generation == 47,
            "authenticated broker message was not dispatched exactly once");
    require(session.opened.channel->terminate() && session.scope->removes == 1,
            "valid channel teardown was not bounded");
  }

  for (const std::string_view mode :
       {"pre-ready", "wrong-role", "bad-version", "descendant", "peer-loss"}) {
    Session session(mode, FAKE_BWRAP_PATH);
    require(!session.opened.channel->negotiate(2s) &&
                session.opened.channel->failed() &&
                session.dispatcher->calls == 0 && session.scope->removes == 1,
            "unauthenticated handshake reached broker dispatch");
  }

  for (const std::string_view mode : {"descriptor", "descriptor-flood"}) {
    const auto descriptors_before = descriptor_count();
    for (unsigned attempt = 0; attempt < 16; ++attempt) {
      Session session(mode, FAKE_BWRAP_PATH);
      require(!session.opened.channel->negotiate(2s) &&
                  session.dispatcher->calls == 0,
              "descriptor-bearing HELLO was not quarantined");
    }
    require(descriptor_count() == descriptors_before,
            "descriptor quarantine leaked broker-side descriptors");
  }

  for (const std::string_view mode :
       {"stale", "bad-role-version", "ready-loss"}) {
    Session session(mode, FAKE_BWRAP_PATH);
    require(session.opened.channel->negotiate(2s),
            "post-readiness attack did not negotiate first");
    require(session.opened.channel->dispatch_one(2s) ==
                    channel::DispatchStatus::fatal &&
                session.opened.channel->failed() &&
                session.dispatcher->calls == 0 && session.scope->removes == 1,
            "post-readiness authentication failure reached broker dispatch");
  }

  {
    Session session("ready-loss", FAKE_BWRAP_PATH);
    require(session.opened.channel->negotiate(2s),
            "silent-exit liveness fixture did not negotiate");
    const auto deadline = std::chrono::steady_clock::now() + 2s;
    while (session.opened.channel->alive() &&
           std::chrono::steady_clock::now() < deadline) {
      usleep(1000);
    }
    require(
        !session.opened.channel->alive() && session.dispatcher->calls == 0 &&
            session.opened.channel->terminate() && session.scope->removes == 1,
        "silent peer exit remained live or reached broker dispatch");
  }
}

int bwrap_suite() {
  if (access(BWRAP_PATH, X_OK) < 0) {
    return 77;
  }
  try {
    Session valid("valid", BWRAP_PATH);
    if (!valid.opened.channel->negotiate(4s)) {
      return 77;
    }
    require(valid.opened.channel->dispatch_one(4s) ==
                    channel::DispatchStatus::dispatched &&
                valid.dispatcher->calls == 1,
            "real Bubblewrap authenticated dispatch failed");
    require(valid.opened.channel->terminate(),
            "real Bubblewrap teardown failed");

    Session stale("stale", BWRAP_PATH);
    require(stale.opened.channel->negotiate(4s) &&
                stale.opened.channel->dispatch_one(4s) ==
                    channel::DispatchStatus::fatal &&
                stale.dispatcher->calls == 0,
            "real Bubblewrap stale generation reached dispatch");
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
