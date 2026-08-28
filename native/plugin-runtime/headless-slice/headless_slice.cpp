#include "headless_slice.hpp"

#include <utility>

namespace omarchy::plugin_runtime::headless {
namespace {

bool exact_request_binding(const launcher::TrustedLaunchRequest &request,
                           const permissions::ActivationBinding &binding) {
  return request.plugin_id == binding.plugin.view() &&
         request.revision_sha256 == binding.revision.view() &&
         request.generation == binding.generation;
}

class ChannelControl final : public health::WorkerControl {
public:
  explicit ChannelControl(
      std::shared_ptr<channel::AuthenticatedBrokerChannel> channel)
      : channel_(std::move(channel)) {}

  [[nodiscard]] const launcher::LaunchIdentity &identity() const override {
    return channel_->identity();
  }
  [[nodiscard]] bool alive() const override { return channel_->alive(); }
  [[nodiscard]] bool terminate() override { return channel_->terminate(); }

private:
  std::shared_ptr<channel::AuthenticatedBrokerChannel> channel_;
};

} // namespace

class Session::HealthDispatcher final : public channel::BrokerDispatcher {
public:
  HealthDispatcher(health::HealthSupervisor &health,
                   permissions::ActivationBinding binding,
                   std::shared_ptr<channel::BrokerDispatcher> downstream)
      : health_(health), binding_(std::move(binding)),
        downstream_(std::move(downstream)) {}

  void set_now(std::uint64_t now_seconds) { now_seconds_ = now_seconds; }

  [[nodiscard]] bool
  accepts(const launcher::LaunchIdentity &identity) const noexcept override {
    return identity.plugin_id == binding_.plugin.view() &&
           identity.revision_sha256 == binding_.revision.view() &&
           identity.generation == binding_.generation;
  }

  [[nodiscard]] bool dispatch(const omarchy::plugin::wire::PacketView &packet)
      override {
    if (dispatching_ || downstream_ == nullptr)
      return false;
    const std::size_t bytes =
        omarchy::plugin::wire::kHeaderSize + packet.payload.size();
    if (health_.admit_request(binding_, packet.header.correlation_id, bytes,
                              now_seconds_) != health::Status::accepted)
      return false;
    struct Dispatching {
      bool &value;
      ~Dispatching() { value = false; }
    } guard{dispatching_};
    dispatching_ = true;
    bool dispatched = false;
    try {
      dispatched = downstream_->dispatch(packet);
    } catch (...) {
      (void)health_.complete_request(binding_, packet.header.correlation_id);
      throw;
    }
    return health_.complete_request(binding_, packet.header.correlation_id) ==
               health::Status::accepted &&
           dispatched;
  }

private:
  health::HealthSupervisor &health_;
  permissions::ActivationBinding binding_;
  std::shared_ptr<channel::BrokerDispatcher> downstream_;
  std::uint64_t now_seconds_ = 0;
  bool dispatching_ = false;
};

StartResult Session::start(
    launcher::Supervisor &launcher,
    const launcher::TrustedLaunchRequest &request,
    permissions::ActivationBinding binding,
    health::HealthSupervisor &health_supervisor,
    std::shared_ptr<channel::BrokerDispatcher> no_authority_dispatcher,
    std::shared_ptr<const channel::GenerationAuthority> authority,
    std::uint64_t now_seconds,
    std::chrono::milliseconds negotiation_timeout) {
  if (!exact_request_binding(request, binding) ||
      no_authority_dispatcher == nullptr || authority == nullptr)
    return {.session = nullptr,
            .failure = StartFailure::invalid_binding,
            .detail = "headless launch identity is not exact"};
  auto gated = std::make_shared<HealthDispatcher>(
      health_supervisor, binding, std::move(no_authority_dispatcher));
  auto opened = channel::AuthenticatedBrokerChannel::open(
      launcher, request, gated, std::move(authority));
  if (!opened)
    return {.session = nullptr,
            .failure = StartFailure::launch,
            .detail = std::move(opened.detail)};
  auto authenticated = std::shared_ptr<channel::AuthenticatedBrokerChannel>(
      std::move(opened.channel));
  const auto adopted = health_supervisor.adopt(
      std::make_unique<ChannelControl>(authenticated), binding, now_seconds);
  if (adopted != health::Status::accepted)
    return {.session = nullptr,
            .failure = StartFailure::health_admission,
            .detail = "health supervisor rejected authenticated worker"};
  if (!authenticated->negotiate(negotiation_timeout)) {
    (void)health_supervisor.stop(binding);
    return {.session = nullptr,
            .failure = StartFailure::negotiation,
            .detail = authenticated->detail()};
  }
  if (health_supervisor.ready(binding, now_seconds) !=
      health::Status::accepted) {
    (void)health_supervisor.stop(binding);
    return {.session = nullptr,
            .failure = StartFailure::readiness,
            .detail = "authenticated worker failed the health readiness gate"};
  }
  return {.session = std::unique_ptr<Session>(new Session(
              std::move(binding), health_supervisor, std::move(authenticated),
              std::move(gated))),
          .failure = StartFailure::none,
          .detail = {}};
}

Session::Session(
    permissions::ActivationBinding binding,
    health::HealthSupervisor &health_supervisor,
    std::shared_ptr<channel::AuthenticatedBrokerChannel> authenticated,
    std::shared_ptr<HealthDispatcher> dispatcher)
    : binding_(std::move(binding)), health_(health_supervisor),
      channel_(std::move(authenticated)), dispatcher_(std::move(dispatcher)) {}

Session::~Session() {
  if (active_)
    (void)stop();
}

channel::DispatchStatus
Session::dispatch_one(std::uint64_t now_seconds,
                      std::chrono::milliseconds timeout) {
  if (!active_)
    return channel::DispatchStatus::not_ready;
  dispatcher_->set_now(now_seconds);
  const auto status = channel_->dispatch_one(timeout);
  if (status == channel::DispatchStatus::fatal ||
      status == channel::DispatchStatus::not_ready) {
    active_ = false;
    (void)health_.stop(binding_);
  }
  return status;
}

health::Status Session::observe_resources(health::ResourceSample sample,
                                          std::uint64_t now_seconds) {
  if (!active_)
    return health::Status::stale_generation;
  const auto status = health_.observe_resources(binding_, sample, now_seconds);
  if (status != health::Status::accepted)
    active_ = false;
  return status;
}

health::Status Session::stop() {
  if (!active_)
    return health::Status::stale_generation;
  active_ = false;
  return health_.stop(binding_);
}

bool Session::active() const {
  return active_ && channel_->ready() && channel_->alive();
}

const permissions::ActivationBinding &Session::binding() const {
  return binding_;
}

} // namespace omarchy::plugin_runtime::headless
