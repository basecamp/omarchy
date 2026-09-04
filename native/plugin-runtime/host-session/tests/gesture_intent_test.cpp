#include "gesture_intent.hpp"

#include <stdexcept>
#include <string>
#include <memory>

namespace host = omarchy::plugin_runtime::host_session;
namespace permissions = omarchy::plugins::permissions;
namespace runtime = omarchy::plugin_runtime::runtime;
namespace surface = omarchy::plugin_runtime::surface;
namespace wire = omarchy::plugin::wire;

namespace {
struct Clock final : runtime::GestureEligibilityClock {
  std::uint64_t now_nanoseconds() const override { return 100; }
};
void require(bool value, const char *message) {
  if (!value)
    throw std::runtime_error(message);
}
permissions::Digest digest(char value) {
  return permissions::Digest(std::string(64, value));
}
} // namespace

int main() {
  auto clock = std::make_shared<Clock>();
  runtime::GestureEligibilityLatch eligibility(clock);
  const permissions::ActivationBinding binding{
      .plugin = permissions::PluginId("fixture.plugin"),
      .revision = digest('1'),
      .policy_fingerprint = digest('2'),
      .generation = 7};
  host::GestureIntentAuthority authority(binding, eligibility);
  const surface::SurfaceKey bar{.id = 1, .generation = 7};
  const surface::SurfaceKey panel{.id = 2, .generation = 7};
  const surface::SurfaceKey maximum{.id = 3, .generation = 7};
  const surface::SurfaceKey invalid{.id = 4, .generation = 7};
  require(authority.declare_surface(bar, "bar") ==
              host::SurfaceDeclarationResult::declared &&
              authority.declare_surface(panel, "PanelWidget") ==
                  host::SurfaceDeclarationResult::declared &&
              authority.declare_surface(maximum, std::string(64, 'X')) ==
                  host::SurfaceDeclarationResult::declared &&
              authority.declare_surface(invalid, "Panel.Widget") ==
                  host::SurfaceDeclarationResult::invalid &&
              authority.declare_surface(invalid, std::string(65, 'X')) ==
                  host::SurfaceDeclarationResult::invalid,
          "surface declarations failed");
  require(!authority.arm(bar, 10) && authority.attach_surface(bar) &&
              !authority.attach_surface(bar) && authority.arm(bar, 11),
          "only an attached physical-input source could arm");
  const surface::SurfaceIntentRequest request{
      .source = bar,
      .target = panel,
      .input_sequence = 11,
      .action = surface::SurfaceIntentAction::toggle,
      .requested_output = "DP-1"};
  auto admitted = authority.admit(request);
  require(admitted.intent && admitted.intent->available() &&
              admitted.intent->source_name() == "bar" &&
              admitted.intent->target_name() == "PanelWidget" &&
              admitted.intent->action() == surface::SurfaceIntentAction::toggle &&
              admitted.intent->requested_output() == "DP-1",
          "exact intent was not admitted");
  auto moved = std::move(*admitted.intent);
  require(moved.available() && !admitted.intent->available(),
          "admitted intent was copyable or move did not consume source");
  require(authority.admit(request).failure ==
              host::SurfaceIntentAdmissionFailure::gesture_missing,
          "intent replay was accepted");

  require(authority.arm(bar, 12), "probe gesture did not arm");
  auto invalid_output = request;
  invalid_output.input_sequence = 12;
  invalid_output.requested_output = std::string(129, 'x');
  require(authority.admit(invalid_output).failure ==
              host::SurfaceIntentAdmissionFailure::malformed,
          "oversized output placement hint was accepted");
  auto unknown = request;
  unknown.input_sequence = 12;
  unknown.target.id = 99;
  require(authority.admit(unknown).failure ==
              host::SurfaceIntentAdmissionFailure::unknown_target &&
              authority.admit(request).failure ==
                  host::SurfaceIntentAdmissionFailure::gesture_missing,
          "denied target probe retained eligibility");

  require(authority.attach_surface(panel) && authority.arm(bar, 13) &&
              authority.detach_surface(panel),
          "detach fixture failed");
  auto surviving_source = request;
  surviving_source.input_sequence = 13;
  auto detached_target = authority.admit(surviving_source);
  require(detached_target.intent &&
              detached_target.intent->target_name() == "PanelWidget",
          "detached canonical target became unknown");

  surviving_source.input_sequence = 14;
  require(authority.arm(bar, 14),
          "unrelated source-clear fixture did not arm");
  authority.clear_surface_eligibility(maximum);
  require(authority.admit(surviving_source).intent.has_value(),
          "clearing another surface erased the source gesture");

  surviving_source.input_sequence = 15;
  require(authority.arm(bar, 15), "exact source-clear fixture did not arm");
  authority.clear_surface_eligibility(bar);
  require(authority.admit(surviving_source).failure ==
              host::SurfaceIntentAdmissionFailure::gesture_missing,
          "clearing the exact source retained gesture eligibility");

  surviving_source.input_sequence = 16;
  require(authority.arm(bar, 16) && authority.detach_surface(bar),
          "source detach fixture failed");
  require(authority.admit(surviving_source).failure ==
              host::SurfaceIntentAdmissionFailure::gesture_missing,
          "detaching the source retained gesture eligibility");
  require(!authority.arm(bar, 17),
          "detached source minted new gesture eligibility");
  require(authority.attach_surface(bar) && authority.arm(bar, 18),
          "reattached source could not regain physical-input authority");
  auto stale_target = request;
  stale_target.input_sequence = 18;
  stale_target.target.generation++;
  auto canonical_after_spoof = request;
  canonical_after_spoof.input_sequence = 18;
  require(authority.admit(stale_target).failure ==
                  host::SurfaceIntentAdmissionFailure::stale_activation &&
              authority.admit(canonical_after_spoof).failure ==
                  host::SurfaceIntentAdmissionFailure::gesture_missing,
          "spoofed target generation was accepted or retained eligibility");
  auto dismiss = authority.admit(
      {.source = panel,
       .target = panel,
       .input_sequence = 0,
       .action = surface::SurfaceIntentAction::dismiss,
       .requested_output = {}});
  require(dismiss.intent && dismiss.intent->source_name() == "PanelWidget" &&
              dismiss.intent->target_name() == "PanelWidget" &&
              dismiss.intent->input_sequence() == 0 &&
              dismiss.intent->take_if_fresh().has_value(),
          "declared self-dismiss required ambient gesture authority");
  require(authority
                  .admit({.source = bar,
                          .target = panel,
                          .input_sequence = 0,
                          .action = surface::SurfaceIntentAction::dismiss,
                          .requested_output = {}})
                  .failure == host::SurfaceIntentAdmissionFailure::malformed &&
              authority
                      .admit({.source = panel,
                              .target = panel,
                              .input_sequence = 18,
                              .action =
                                  surface::SurfaceIntentAction::dismiss,
                              .requested_output = {}})
                      .failure ==
                  host::SurfaceIntentAdmissionFailure::malformed,
          "self-dismiss accepted a forged source or gesture sequence");
  authority.revoke();
  require(!authority.attach_surface(panel) && !authority.arm(bar, 19) &&
              authority.admit(request).failure ==
                  host::SurfaceIntentAdmissionFailure::revoked,
          "revoked intent authority remained usable");

  runtime::GestureEligibilityLatch destruction_eligibility(clock);
  std::unique_ptr<host::AdmittedSurfaceIntent> after_destruction;
  {
    host::GestureIntentAuthority temporary(binding,
                                            destruction_eligibility);
    require(temporary.declare_surface(bar, "BarWidget") ==
                host::SurfaceDeclarationResult::declared &&
                temporary.declare_surface(panel, "PanelWidget") ==
                    host::SurfaceDeclarationResult::declared &&
                temporary.attach_surface(bar) &&
                temporary.arm(bar, 21),
            "authority destruction fixture failed");
    auto result = temporary.admit(
        {.source = bar,
         .target = panel,
         .input_sequence = 21,
         .action = surface::SurfaceIntentAction::open,
         .requested_output = {}});
    require(result.intent.has_value(),
            "authority destruction intent was not admitted");
    after_destruction = std::make_unique<host::AdmittedSurfaceIntent>(
        std::move(*result.intent));
  }
  require(!after_destruction->take_if_fresh(),
          "intent survived authority destruction");

  runtime::GestureEligibilityLatch capacity_eligibility(clock);
  host::GestureIntentAuthority capacity(binding, capacity_eligibility);
  for (std::size_t index = 0; index < wire::kMaximumPluginSurfaces; ++index) {
    require(capacity.declare_surface(
                {.id = 100 + index, .generation = binding.generation},
                "surface" + std::to_string(index)) ==
                host::SurfaceDeclarationResult::declared,
            "intent authority rejected a surface below capacity");
  }
  require(capacity.declare_surface(
              {.id = 999, .generation = binding.generation}, "overflow") ==
              host::SurfaceDeclarationResult::capacity_exceeded,
          "intent authority accepted a surface above capacity");
}
