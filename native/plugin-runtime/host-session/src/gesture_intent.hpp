#pragma once

#include "gesture_eligibility.hpp"
#include "omarchy/plugin/wire/surface_name.hpp"
#include "omarchy/plugin_runtime/surface/render_messages.hpp"

#include <cstddef>
#include <cstdint>
#include <memory>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace omarchy::plugin_runtime::host_session {

namespace permissions = omarchy::plugins::permissions;
namespace definitions = omarchy::plugins::definitions;
namespace runtime = omarchy::plugin_runtime::runtime;
namespace surface = omarchy::plugin_runtime::surface;
namespace wire = omarchy::plugin::wire;

class GestureIntentLifetime final {
public:
  [[nodiscard]] bool current(std::uint64_t epoch) const noexcept;
  [[nodiscard]] std::uint64_t epoch() const noexcept;
  void invalidate() noexcept;
  void revoke() noexcept;

private:
  std::uint64_t epoch_ = 1;
  bool revoked_ = false;
};

class SurfaceIntentPublication final {
public:
  [[nodiscard]] const permissions::ActivationBinding &binding() const;
  [[nodiscard]] surface::SurfaceKey source() const noexcept;
  [[nodiscard]] surface::SurfaceKey target() const noexcept;
  [[nodiscard]] std::string_view source_name() const noexcept;
  [[nodiscard]] std::string_view target_name() const noexcept;
  [[nodiscard]] surface::SurfaceIntentAction action() const noexcept;
  [[nodiscard]] std::uint64_t input_sequence() const noexcept;
  [[nodiscard]] std::string_view requested_output() const noexcept;

private:
  SurfaceIntentPublication(permissions::ActivationBinding binding,
                           surface::SurfaceIntentRequest request,
                           std::string source_name,
                           std::string target_name);

  permissions::ActivationBinding binding_{};
  surface::SurfaceIntentRequest request_{};
  std::string source_name_;
  std::string target_name_;

  friend class AdmittedSurfaceIntent;
};

class AdmittedSurfaceIntent final {
public:
  AdmittedSurfaceIntent(const AdmittedSurfaceIntent &) = delete;
  AdmittedSurfaceIntent &operator=(const AdmittedSurfaceIntent &) = delete;
  AdmittedSurfaceIntent(AdmittedSurfaceIntent &&other) noexcept;
  AdmittedSurfaceIntent &operator=(AdmittedSurfaceIntent &&) = delete;

  [[nodiscard]] const permissions::ActivationBinding &binding() const;
  [[nodiscard]] surface::SurfaceKey source() const noexcept;
  [[nodiscard]] surface::SurfaceKey target() const noexcept;
  [[nodiscard]] std::string_view source_name() const noexcept;
  [[nodiscard]] std::string_view target_name() const noexcept;
  [[nodiscard]] surface::SurfaceIntentAction action() const noexcept;
  [[nodiscard]] std::uint64_t input_sequence() const noexcept;
  [[nodiscard]] std::string_view requested_output() const noexcept;
  [[nodiscard]] std::uint64_t expires_monotonic_ns() const noexcept;
  [[nodiscard]] std::optional<SurfaceIntentPublication> take_if_fresh();
  [[nodiscard]] bool available() const noexcept;

private:
  AdmittedSurfaceIntent(permissions::ActivationBinding binding,
                        const surface::SurfaceIntentRequest &request,
                        std::string source_name, std::string target_name,
                        runtime::ConsumedGestureEligibility eligibility,
                        std::shared_ptr<const GestureIntentLifetime> lifetime,
                        std::uint64_t lifetime_epoch);

  permissions::ActivationBinding binding_{};
  surface::SurfaceIntentRequest request_{};
  std::string source_name_;
  std::string target_name_;
  runtime::ConsumedGestureEligibility eligibility_;
  std::shared_ptr<const GestureIntentLifetime> lifetime_;
  std::uint64_t lifetime_epoch_ = 0;
  bool available_ = false;

  void invalidate() noexcept;

  friend class GestureIntentAuthority;
};

enum class SurfaceDeclarationResult : std::uint8_t {
  declared,
  invalid,
  duplicate_key,
  duplicate_name,
  capacity_exceeded,
  revoked,
};

enum class SurfaceIntentAdmissionFailure : std::uint8_t {
  none,
  malformed,
  gesture_missing,
  stale_activation,
  unknown_source,
  unknown_target,
  revoked,
};

struct SurfaceIntentAdmissionResult {
  std::optional<AdmittedSurfaceIntent> intent;
  SurfaceIntentAdmissionFailure failure = SurfaceIntentAdmissionFailure::none;
};

// Event-loop-confined authority for one authenticated plugin session. The
// Canonical manifest surfaces are declared for the session lifetime, including
// targets that have not mapped a render endpoint yet. Attachment separately
// controls which surfaces may arm from trusted physical input. The render
// request path atomically spends that eligibility before resolving targets.
class GestureIntentAuthority final {
public:
  GestureIntentAuthority(permissions::ActivationBinding binding,
                         runtime::GestureEligibilityLatch &eligibility);
  ~GestureIntentAuthority();

  [[nodiscard]] SurfaceDeclarationResult
  declare_surface(surface::SurfaceKey key, std::string display_name) noexcept;
  [[nodiscard]] bool attach_surface(surface::SurfaceKey key) noexcept;
  [[nodiscard]] bool detach_surface(surface::SurfaceKey key) noexcept;
  [[nodiscard]] bool arm(surface::SurfaceKey source,
                         std::uint64_t input_sequence);
  void clear_surface_eligibility(surface::SurfaceKey source) noexcept;
  [[nodiscard]] SurfaceIntentAdmissionResult
  admit(const surface::SurfaceIntentRequest &request);
  void revoke() noexcept;

private:
  struct Declaration {
    surface::SurfaceKey key{};
    std::string name;
    bool attached = false;
  };

  [[nodiscard]] const Declaration *find(surface::SurfaceKey key) const;

  permissions::ActivationBinding binding_{};
  runtime::GestureEligibilityLatch &eligibility_;
  std::shared_ptr<GestureIntentLifetime> lifetime_;
  std::vector<Declaration> declarations_;
  bool revoked_ = false;
};

} // namespace omarchy::plugin_runtime::host_session
