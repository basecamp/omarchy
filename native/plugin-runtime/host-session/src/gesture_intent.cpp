#include "gesture_intent.hpp"

#include <algorithm>
#include <limits>
#include <utility>

namespace omarchy::plugin_runtime::host_session {
namespace {

namespace wire = omarchy::plugin::wire;

bool valid_action(surface::SurfaceIntentAction action) {
  return action == surface::SurfaceIntentAction::open ||
         action == surface::SurfaceIntentAction::toggle ||
         action == surface::SurfaceIntentAction::dismiss;
}

} // namespace

bool GestureIntentLifetime::current(std::uint64_t epoch) const noexcept {
  return !revoked_ && epoch != 0 && epoch == epoch_;
}

std::uint64_t GestureIntentLifetime::epoch() const noexcept { return epoch_; }

void GestureIntentLifetime::invalidate() noexcept {
  if (epoch_ != std::numeric_limits<std::uint64_t>::max())
    ++epoch_;
  else
    revoked_ = true;
}

void GestureIntentLifetime::revoke() noexcept {
  invalidate();
  revoked_ = true;
}

SurfaceIntentPublication::SurfaceIntentPublication(
    permissions::ActivationBinding binding,
    surface::SurfaceIntentRequest request, std::string source_name,
    std::string target_name)
    : binding_(std::move(binding)), request_(request),
      source_name_(std::move(source_name)),
      target_name_(std::move(target_name)) {}

const permissions::ActivationBinding &SurfaceIntentPublication::binding()
    const {
  return binding_;
}

surface::SurfaceKey SurfaceIntentPublication::source() const noexcept {
  return request_.source;
}

surface::SurfaceKey SurfaceIntentPublication::target() const noexcept {
  return request_.target;
}

std::string_view SurfaceIntentPublication::source_name() const noexcept {
  return source_name_;
}

std::string_view SurfaceIntentPublication::target_name() const noexcept {
  return target_name_;
}

surface::SurfaceIntentAction SurfaceIntentPublication::action() const noexcept {
  return request_.action;
}

std::uint64_t SurfaceIntentPublication::input_sequence() const noexcept {
  return request_.input_sequence;
}

AdmittedSurfaceIntent::AdmittedSurfaceIntent(
    permissions::ActivationBinding binding,
    const surface::SurfaceIntentRequest &request, std::string source_name,
    std::string target_name,
    runtime::ConsumedGestureEligibility eligibility,
    std::shared_ptr<const GestureIntentLifetime> lifetime,
    std::uint64_t lifetime_epoch)
    : binding_(std::move(binding)), request_(request),
      source_name_(std::move(source_name)), target_name_(std::move(target_name)),
      eligibility_(std::move(eligibility)),
      lifetime_(std::move(lifetime)), lifetime_epoch_(lifetime_epoch),
      available_(true) {}

AdmittedSurfaceIntent::AdmittedSurfaceIntent(
    AdmittedSurfaceIntent &&other) noexcept
    : binding_(std::move(other.binding_)), request_(other.request_),
      source_name_(std::move(other.source_name_)),
      target_name_(std::move(other.target_name_)),
      eligibility_(std::move(other.eligibility_)),
      lifetime_(std::move(other.lifetime_)),
      lifetime_epoch_(other.lifetime_epoch_),
      available_(other.available_) {
  other.invalidate();
}

const permissions::ActivationBinding &AdmittedSurfaceIntent::binding() const {
  return binding_;
}

surface::SurfaceKey AdmittedSurfaceIntent::source() const noexcept {
  return request_.source;
}

surface::SurfaceKey AdmittedSurfaceIntent::target() const noexcept {
  return request_.target;
}

std::string_view AdmittedSurfaceIntent::source_name() const noexcept {
  return source_name_;
}

std::string_view AdmittedSurfaceIntent::target_name() const noexcept {
  return target_name_;
}

surface::SurfaceIntentAction AdmittedSurfaceIntent::action() const noexcept {
  return request_.action;
}

std::uint64_t AdmittedSurfaceIntent::input_sequence() const noexcept {
  return request_.input_sequence;
}

std::uint64_t
AdmittedSurfaceIntent::expires_monotonic_ns() const noexcept {
  return eligibility_.expires_monotonic_ns;
}

std::optional<SurfaceIntentPublication>
AdmittedSurfaceIntent::take_if_fresh() {
  const bool requires_gesture =
      request_.action != surface::SurfaceIntentAction::dismiss;
  if (!available_ || (requires_gesture && !eligibility_.current()) ||
      lifetime_ == nullptr ||
      !lifetime_->current(lifetime_epoch_)) {
    invalidate();
    return std::nullopt;
  }
  SurfaceIntentPublication publication(binding_, request_, source_name_,
                                         target_name_);
  invalidate();
  return publication;
}

bool AdmittedSurfaceIntent::available() const noexcept { return available_; }

void AdmittedSurfaceIntent::invalidate() noexcept {
  binding_ = {};
  request_ = {};
  source_name_.clear();
  target_name_.clear();
  eligibility_ = {};
  lifetime_.reset();
  lifetime_epoch_ = 0;
  available_ = false;
}

GestureIntentAuthority::GestureIntentAuthority(
    permissions::ActivationBinding binding,
    runtime::GestureEligibilityLatch &eligibility)
    : binding_(std::move(binding)), eligibility_(eligibility),
      lifetime_(std::make_shared<GestureIntentLifetime>()) {
  declarations_.reserve(wire::kMaximumPluginSurfaces);
}

GestureIntentAuthority::~GestureIntentAuthority() { revoke(); }

SurfaceDeclarationResult GestureIntentAuthority::declare_surface(
    surface::SurfaceKey key, std::string display_name) noexcept {
  if (revoked_)
    return SurfaceDeclarationResult::revoked;
  if (key.id == 0 || key.generation != binding_.generation ||
      !wire::valid_surface_name(display_name))
    return SurfaceDeclarationResult::invalid;
  if (find(key) != nullptr)
    return SurfaceDeclarationResult::duplicate_key;
  if (std::ranges::any_of(declarations_, [&](const Declaration &candidate) {
        return candidate.name == display_name;
      }))
    return SurfaceDeclarationResult::duplicate_name;
  if (declarations_.size() == wire::kMaximumPluginSurfaces)
    return SurfaceDeclarationResult::capacity_exceeded;
  declarations_.push_back(
      {.key = key, .name = std::move(display_name), .attached = false});
  return SurfaceDeclarationResult::declared;
}

bool GestureIntentAuthority::attach_surface(surface::SurfaceKey key) noexcept {
  const auto found = std::ranges::find_if(
      declarations_, [&](const Declaration &candidate) {
        return candidate.key == key;
      });
  if (revoked_ || found == declarations_.end() || found->attached)
    return false;
  found->attached = true;
  return true;
}

bool GestureIntentAuthority::detach_surface(surface::SurfaceKey key) noexcept {
  const auto found = std::ranges::find_if(
      declarations_, [&](const Declaration &candidate) {
        return candidate.key == key;
      });
  if (found == declarations_.end() || !found->attached)
    return false;
  clear_surface_eligibility(key);
  found->attached = false;
  lifetime_->invalidate();
  return true;
}

bool GestureIntentAuthority::arm(surface::SurfaceKey source,
                                 std::uint64_t input_sequence) {
  const auto *declaration = find(source);
  if (revoked_ || input_sequence == 0 || declaration == nullptr ||
      !declaration->attached)
    return false;
  return eligibility_.arm(
      binding_, {.surface_id = source.id,
                 .surface_generation = source.generation,
                 .input_sequence = input_sequence});
}

void GestureIntentAuthority::clear_surface_eligibility(
    surface::SurfaceKey source) noexcept {
  eligibility_.clear_surface(binding_, source.id, source.generation);
}

SurfaceIntentAdmissionResult
GestureIntentAuthority::admit(const surface::SurfaceIntentRequest &request) {
  if (revoked_)
    return {.intent = std::nullopt,
            .failure = SurfaceIntentAdmissionFailure::revoked};
  if (request.source.id == 0 || request.source.generation == 0 ||
      request.target.id == 0 || request.target.generation == 0 ||
      !valid_action(request.action))
    return {.intent = std::nullopt,
            .failure = SurfaceIntentAdmissionFailure::malformed};

  if (request.action == surface::SurfaceIntentAction::dismiss) {
    if (request.input_sequence != 0 || request.source != request.target)
      return {.intent = std::nullopt,
              .failure = SurfaceIntentAdmissionFailure::malformed};
    if (request.target.generation != binding_.generation)
      return {.intent = std::nullopt,
              .failure = SurfaceIntentAdmissionFailure::stale_activation};
    const auto *target = find(request.target);
    if (target == nullptr)
      return {.intent = std::nullopt,
              .failure = SurfaceIntentAdmissionFailure::unknown_target};
    return {.intent = AdmittedSurfaceIntent(
                binding_, request, target->name, target->name, {}, lifetime_,
                lifetime_->epoch()),
            .failure = SurfaceIntentAdmissionFailure::none};
  }

  if (request.input_sequence == 0)
    return {.intent = std::nullopt,
            .failure = SurfaceIntentAdmissionFailure::malformed};

  const definitions::DynamicInvocation::GestureClaim claim{
      .surface_id = request.source.id,
      .surface_generation = request.source.generation,
      .input_sequence = request.input_sequence};
  auto consumed = eligibility_.consume(binding_, claim);
  if (!consumed)
    return {.intent = std::nullopt,
            .failure = SurfaceIntentAdmissionFailure::gesture_missing};

  if (request.source.generation != binding_.generation ||
      request.target.generation != binding_.generation)
    return {.intent = std::nullopt,
            .failure = SurfaceIntentAdmissionFailure::stale_activation};
  const auto *source = find(request.source);
  if (source == nullptr)
    return {.intent = std::nullopt,
            .failure = SurfaceIntentAdmissionFailure::unknown_source};
  const auto *target = find(request.target);
  if (target == nullptr)
    return {.intent = std::nullopt,
            .failure = SurfaceIntentAdmissionFailure::unknown_target};
  return {.intent = AdmittedSurfaceIntent(binding_, request, source->name,
                                           target->name,
                                           std::move(*consumed), lifetime_,
                                           lifetime_->epoch()),
          .failure = SurfaceIntentAdmissionFailure::none};
}

void GestureIntentAuthority::revoke() noexcept {
  eligibility_.clear();
  declarations_.clear();
  lifetime_->revoke();
  revoked_ = true;
}

const GestureIntentAuthority::Declaration *
GestureIntentAuthority::find(surface::SurfaceKey key) const {
  const auto found = std::ranges::find_if(
      declarations_, [&](const Declaration &candidate) {
        return candidate.key == key;
      });
  return found == declarations_.end() ? nullptr : &*found;
}

} // namespace omarchy::plugin_runtime::host_session
