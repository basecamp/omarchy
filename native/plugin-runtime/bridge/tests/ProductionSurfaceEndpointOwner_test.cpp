#include "ProductionSurfaceEndpointOwner.h"

#include "ProductionSurfaceEndpoint.h"
#include "omarchy/plugin/wire/state.hpp"
#include "remote_surface.hpp"
#include "surface_host.hpp"

#include <QQuickWindow>

#include <array>
#include <cmath>
#include <limits>
#include <optional>
#include <stdexcept>
#include <string>
#include <string_view>

namespace {

namespace bridge = omarchy::plugin_runtime::bridge;
namespace channel = omarchy::plugin_runtime::channel;
namespace host = omarchy::plugin_runtime::host_session;
namespace permissions = omarchy::plugins::permissions;
namespace surface_host = omarchy::plugin_runtime::surface_host;
namespace wire = omarchy::plugin::wire;

void require(bool condition, std::string_view message) {
  if (!condition)
    throw std::runtime_error(std::string(message));
}

permissions::ActivationBinding binding(std::uint64_t generation = 7) {
  return {.plugin = permissions::PluginId("org.example.owner"),
          .revision = permissions::Digest(std::string(64, 'a')),
          .policy_fingerprint = permissions::Digest(std::string(64, 'b')),
          .generation = generation};
}

class Port final : public channel::ProductionSurfaceSessionPort {
public:
  explicit Port(std::uint64_t generation = 7) {
    description = {
        .binding = binding(generation),
        .key = {.id = 1, .generation = generation},
        .session_nonce = generation + 40,
        .plugin_id = "org.example.owner",
        .surface_name = "pet",
        .canonical_surfaces =
            R"({"pet":{"keyboardFocus":false,"maximumFramesPerSecond":60,"maximumHeight":64,"maximumWidth":128,"role":"desktop-overlay"}})",
    };
  }

  std::optional<channel::ProductionSurfaceDescription>
  describe(std::string_view name) const noexcept override {
    ++describe_calls;
    if (!running || name != description.surface_name)
      return {};
    return description;
  }

  bool attach(const channel::ProductionSurfaceDescription &expected,
              host::SurfaceEndpoint &candidate) noexcept override {
    ++attach_calls;
    if (!running || fail_attach || expected != description ||
        endpoint != nullptr)
      return false;
    endpoint = &candidate;
    return true;
  }

  bool detach(const channel::ProductionSurfaceDescription &expected,
              const host::SurfaceEndpoint &candidate) noexcept override {
    ++detach_calls;
    if (expected != description)
      return true;
    if (endpoint != &candidate)
      return false;
    endpoint = nullptr;
    return true;
  }

  bool arm_surface_intent(const channel::ProductionSurfaceDescription &,
                          std::uint64_t) noexcept override {
    return false;
  }

  void clear_surface_intent_eligibility(
      const channel::ProductionSurfaceDescription &) noexcept override {}

  mutable std::size_t describe_calls = 0;
  std::size_t attach_calls = 0;
  std::size_t detach_calls = 0;
  channel::ProductionSurfaceDescription description;
  host::SurfaceEndpoint *endpoint = nullptr;
  bool running = true;
  bool fail_attach = false;

private:
  bool
  send_render_packet_impl(const channel::ProductionSurfaceDescription &expected,
                          const wire::EnvelopeHeader &, std::vector<std::byte>,
                          std::vector<host::OwnedFd>) noexcept override {
    ++send_calls;
    return expected == description;
  }

public:
  std::size_t send_calls = 0;
};

class MultiplexPort final : public channel::ProductionSurfaceSessionPort {
public:
  MultiplexPort() {
    for (std::size_t index = 0; index < endpoints.size(); ++index) {
      if (!canonical.empty())
        canonical += ',';
      const auto name = "surface" + std::to_string(index);
      canonical += "\"" + name +
                   "\":{\"keyboardFocus\":false,\"maximumFramesPerSecond\":60,"
                   "\"maximumHeight\":64,\"maximumWidth\":128,"
                   "\"role\":\"desktop-overlay\"}";
    }
    canonical = '{' + canonical + '}';
  }

  std::optional<channel::ProductionSurfaceDescription>
  describe(std::string_view name) const noexcept override {
    ++describe_calls;
    for (std::size_t index = 0; index < endpoints.size(); ++index)
      if (name == "surface" + std::to_string(index))
        return description(index);
    return {};
  }

  bool attach(const channel::ProductionSurfaceDescription &expected,
              host::SurfaceEndpoint &candidate) noexcept override {
    const auto index =
        expected.key.id == 0 ? endpoints.size() : expected.key.id - 1;
    if (index >= endpoints.size() || expected != description(index) ||
        endpoints[index] != nullptr)
      return false;
    endpoints[index] = &candidate;
    ++attach_calls;
    return true;
  }

  bool detach(const channel::ProductionSurfaceDescription &expected,
              const host::SurfaceEndpoint &candidate) noexcept override {
    const auto index =
        expected.key.id == 0 ? endpoints.size() : expected.key.id - 1;
    if (index >= endpoints.size() || endpoints[index] != &candidate)
      return false;
    endpoints[index] = nullptr;
    ++detach_calls;
    return true;
  }

  bool arm_surface_intent(const channel::ProductionSurfaceDescription &,
                          std::uint64_t) noexcept override {
    return false;
  }

  void clear_surface_intent_eligibility(
      const channel::ProductionSurfaceDescription &) noexcept override {}

  permissions::ActivationBinding exact_binding = binding();
  mutable std::size_t describe_calls = 0;
  std::size_t attach_calls = 0;
  std::size_t detach_calls = 0;

private:
  channel::ProductionSurfaceDescription description(std::size_t index) const {
    const auto name = "surface" + std::to_string(index);
    return {.binding = exact_binding,
            .key = {.id = index + 1, .generation = exact_binding.generation},
            .session_nonce = 47,
            .plugin_id = "org.example.owner",
            .surface_name = name,
            .canonical_surfaces = canonical};
  }

  bool
  send_render_packet_impl(const channel::ProductionSurfaceDescription &expected,
                          const wire::EnvelopeHeader &, std::vector<std::byte>,
                          std::vector<host::OwnedFd>) noexcept override {
    return expected.key.id > 0 && expected.key.id <= endpoints.size();
  }

  std::array<const host::SurfaceEndpoint *, 8> endpoints{};
  std::string canonical;
};

class Inspection final : public surface_host::InspectionAuthority {
public:
  bool perform(surface_host::InspectionAction, std::string_view,
               std::string_view, std::string_view) override {
    return true;
  }
};

class Clock final : public surface_host::MonotonicClock {
public:
  std::uint64_t now_nanoseconds() const override { return 1'000'000'000; }
};

void place(bridge::RemotePluginSurface &remote, QQuickWindow &window,
           qreal width = 64, qreal height = 32) {
  remote.setParentItem(window.contentItem());
  remote.setWidth(width);
  remote.setHeight(height);
}

bridge::PublishedSurfaceAttachment published(Port &port, QString key,
                                             qulonglong revision = 1) {
  return bridge::ProductionSurfaceEndpointOwnerTestAccess::published(
      std::move(key), port.description.binding, port.description.surface_name,
      revision);
}

void trusted_geometry_is_derived_and_retryable() {
  Port port;
  Inspection inspection;
  Clock clock;
  auto owner = bridge::ProductionSurfaceEndpointOwnerTestAccess::create(
      inspection, clock, port.description.binding, 1, port);
  const QString key = QStringLiteral("opaque-current-row");
  auto slot = published(port, key);
  bridge::RemotePluginSurface remote;
  remote.setWidth(64);
  remote.setHeight(32);
  require(bridge::ProductionSurfaceEndpointOwnerTestAccess::attach(
              *owner, slot, key, remote) ==
                  bridge::ProductionEndpointAttachResult::not_ready &&
              bridge::ProductionSurfaceEndpointOwnerTestAccess::count(*owner) ==
                  0 &&
              port.describe_calls == 0 && port.attach_calls == 0,
          "windowless surface consumed an exact published slot");

  QQuickWindow window;
  place(remote, window);
  const auto geometry =
      bridge::ProductionSurfaceEndpointOwnerTestAccess::geometry(remote);
  require(geometry && geometry->logical_width == 64 &&
              geometry->logical_height == 32 && geometry->dpr_numerator > 0 &&
              geometry->dpr_denominator > 0,
          "trusted QQuickItem/window geometry was not derived");
  require(bridge::ProductionSurfaceEndpointOwnerTestAccess::attach(
              *owner, slot, key, remote) ==
                  bridge::ProductionEndpointAttachResult::attached &&
              bridge::ProductionSurfaceEndpointOwnerTestAccess::count(*owner) ==
                  1 &&
              port.attach_calls == 1 && port.send_calls == 1,
          "settled trusted surface did not attach on retry");
}

void invalid_geometry_and_context_fail_without_ownership() {
  Port port;
  Inspection inspection;
  Clock clock;
  auto owner = bridge::ProductionSurfaceEndpointOwnerTestAccess::create(
      inspection, clock, port.description.binding, 1, port);
  const QString key = QStringLiteral("opaque-exact");
  auto slot = published(port, key);
  QQuickWindow window;
  bridge::RemotePluginSurface remote;
  place(remote, window, 64.5, 32);
  require(bridge::ProductionSurfaceEndpointOwnerTestAccess::attach(
              *owner, slot, key, remote) ==
              bridge::ProductionEndpointAttachResult::rejected,
          "fractional logical geometry was accepted");
  remote.setWidth(std::numeric_limits<qreal>::quiet_NaN());
  require(bridge::ProductionSurfaceEndpointOwnerTestAccess::attach(
              *owner, slot, key, remote) ==
              bridge::ProductionEndpointAttachResult::rejected,
          "non-finite logical geometry was accepted");
  remote.setWidth(4097);
  require(bridge::ProductionSurfaceEndpointOwnerTestAccess::attach(
              *owner, slot, key, remote) ==
              bridge::ProductionEndpointAttachResult::rejected,
          "out-of-contract logical geometry was accepted");
  remote.setWidth(0);
  require(bridge::ProductionSurfaceEndpointOwnerTestAccess::attach(
              *owner, slot, key, remote) ==
              bridge::ProductionEndpointAttachResult::not_ready,
          "settling zero geometry was permanently rejected");
  remote.setWidth(64);
  require(bridge::ProductionSurfaceEndpointOwnerTestAccess::attach(
              *owner, slot, QStringLiteral("spoofed"), remote) ==
                  bridge::ProductionEndpointAttachResult::rejected &&
              bridge::ProductionSurfaceEndpointOwnerTestAccess::count(*owner) ==
                  0,
          "wrong QML key reached exact slot authority");

  Port replacement(8);
  auto stale = bridge::ProductionSurfaceEndpointOwnerTestAccess::published(
      key, replacement.description.binding,
      replacement.description.surface_name, 2);
  require(bridge::ProductionSurfaceEndpointOwnerTestAccess::attach(
              *owner, stale, key, remote) ==
              bridge::ProductionEndpointAttachResult::rejected,
          "stale binding reached a replacement session");
  auto stale_revision = published(port, key, 2);
  require(bridge::ProductionSurfaceEndpointOwnerTestAccess::attach(
              *owner, stale_revision, key, remote) ==
              bridge::ProductionEndpointAttachResult::rejected,
          "stale publication revision reached the current session");
  auto zero_revision = published(port, key, 0);
  require(bridge::ProductionSurfaceEndpointOwnerTestAccess::attach(
              *owner, zero_revision, key, remote) ==
              bridge::ProductionEndpointAttachResult::rejected,
          "unpublished revision zero acquired endpoint ownership");
}

void duplicate_key_and_cross_slot_remote_reuse_fail() {
  Port first;
  Inspection inspection;
  Clock clock;
  auto owner = bridge::ProductionSurfaceEndpointOwnerTestAccess::create(
      inspection, clock, first.description.binding, 1, first);
  QQuickWindow window;
  bridge::RemotePluginSurface first_remote;
  bridge::RemotePluginSurface second_remote;
  place(first_remote, window);
  place(second_remote, window);
  const QString first_key = QStringLiteral("opaque-first");
  const QString second_key = QStringLiteral("opaque-second");
  auto first_slot = published(first, first_key);
  auto second_slot =
      bridge::ProductionSurfaceEndpointOwnerTestAccess::published(
          second_key, first.description.binding, first.description.surface_name,
          1);
  require(bridge::ProductionSurfaceEndpointOwnerTestAccess::attach(
              *owner, first_slot, first_key, first_remote) ==
              bridge::ProductionEndpointAttachResult::attached,
          "first exact endpoint did not attach");
  require(bridge::ProductionSurfaceEndpointOwnerTestAccess::attach(
              *owner, first_slot, first_key, second_remote) ==
              bridge::ProductionEndpointAttachResult::rejected,
          "duplicate surface key acquired a second endpoint");
  require(bridge::ProductionSurfaceEndpointOwnerTestAccess::attach(
              *owner, second_slot, second_key, first_remote) ==
                  bridge::ProductionEndpointAttachResult::rejected &&
              first.attach_calls == 1,
          "one RemotePluginSurface was reused across exact slots");
}

void key_and_expanded_pixel_bounds_are_exact() {
  Inspection inspection;
  Clock clock;
  QQuickWindow window;
  bridge::RemotePluginSurface remote;
  place(remote, window);
  Port oversized_port;
  auto oversized_owner =
      bridge::ProductionSurfaceEndpointOwnerTestAccess::create(
          inspection, clock, oversized_port.description.binding, 1,
          oversized_port);
  const QString oversized_key(513, QLatin1Char('k'));
  auto oversized = published(oversized_port, oversized_key);
  require(bridge::ProductionSurfaceEndpointOwnerTestAccess::attach(
              *oversized_owner, oversized, oversized_key, remote) ==
              bridge::ProductionEndpointAttachResult::rejected,
          "513-character opaque key crossed the manager boundary");

  Port exact_port;
  auto exact_owner = bridge::ProductionSurfaceEndpointOwnerTestAccess::create(
      inspection, clock, exact_port.description.binding, 1, exact_port);
  bridge::RemotePluginSurface exact_remote;
  place(exact_remote, window);
  const QString exact_key(512, QLatin1Char('k'));
  auto exact = published(exact_port, exact_key);
  require(bridge::ProductionSurfaceEndpointOwnerTestAccess::attach(
              *exact_owner, exact, exact_key, exact_remote) ==
              bridge::ProductionEndpointAttachResult::attached,
          "512-character opaque key was not accepted exactly");
  bridge::ProductionSurfaceEndpointOwnerTestAccess::close_all(*exact_owner);

  require(!bridge::ProductionSurfaceEndpointOwnerTestAccess::geometry(
              4096, 4096, 2.0),
          "DPR-expanded allocation exceeded the pixel dimension bound");
}

void eighth_endpoint_is_accepted_and_ninth_is_rejected() {
  MultiplexPort port;
  Inspection inspection;
  Clock clock;
  auto owner = bridge::ProductionSurfaceEndpointOwnerTestAccess::create(
      inspection, clock, port.exact_binding, 1, port);
  QQuickWindow window;
  std::vector<std::unique_ptr<bridge::RemotePluginSurface>> remotes;
  for (std::size_t index = 0; index < 9; ++index) {
    auto remote = std::make_unique<bridge::RemotePluginSurface>();
    place(*remote, window);
    const auto name = "surface" + std::to_string(index);
    const auto key = QStringLiteral("opaque-") + QString::number(index);
    auto exact = bridge::ProductionSurfaceEndpointOwnerTestAccess::published(
        key, port.exact_binding, name, 1);
    const auto result =
        bridge::ProductionSurfaceEndpointOwnerTestAccess::attach(*owner, exact,
                                                                 key, *remote);
    require(result == (index < 8
                           ? bridge::ProductionEndpointAttachResult::attached
                           : bridge::ProductionEndpointAttachResult::rejected),
            "live endpoint count bound was not exact");
    remotes.push_back(std::move(remote));
  }
  require(bridge::ProductionSurfaceEndpointOwnerTestAccess::count(*owner) ==
                  8 &&
              port.attach_calls == 8,
          "owner did not retain exactly eight endpoints");
  bridge::ProductionSurfaceEndpointOwnerTestAccess::close_all(*owner);
  require(port.detach_calls == 8,
          "bounded endpoint set did not close before session teardown");
}

void teardown_replacement_and_remote_destruction_are_exact() {
  Inspection inspection;
  Clock clock;
  Port first(7);
  auto owner = bridge::ProductionSurfaceEndpointOwnerTestAccess::create(
      inspection, clock, first.description.binding, 1, first);
  QQuickWindow window;
  auto remote = std::make_unique<bridge::RemotePluginSurface>();
  place(*remote, window);
  const QString key = QStringLiteral("opaque-replaced");
  auto first_slot = published(first, key);
  require(bridge::ProductionSurfaceEndpointOwnerTestAccess::attach(
              *owner, first_slot, key, *remote) ==
              bridge::ProductionEndpointAttachResult::attached,
          "generation one did not attach");
  bridge::ProductionSurfaceEndpointOwnerTestAccess::close_all(*owner);
  require(first.detach_calls == 1 &&
              bridge::ProductionSurfaceEndpointOwnerTestAccess::count(*owner) ==
                  0,
          "exact generation was not closed before root replacement");

  Port second(8);
  owner = bridge::ProductionSurfaceEndpointOwnerTestAccess::create(
      inspection, clock, second.description.binding, 2, second);
  auto second_slot = published(second, key, 2);
  remote = std::make_unique<bridge::RemotePluginSurface>();
  place(*remote, window);
  require(bridge::ProductionSurfaceEndpointOwnerTestAccess::attach(
              *owner, second_slot, key, *remote) ==
              bridge::ProductionEndpointAttachResult::attached,
          "replacement generation did not claim the released exact key");
  remote.reset();
  require(second.detach_calls == 1,
          "Remote destruction did not synchronously close its endpoint");
  auto replacement_remote = std::make_unique<bridge::RemotePluginSurface>();
  place(*replacement_remote, window);
  require(bridge::ProductionSurfaceEndpointOwnerTestAccess::attach(
              *owner, second_slot, key, *replacement_remote) ==
                  bridge::ProductionEndpointAttachResult::attached &&
              bridge::ProductionSurfaceEndpointOwnerTestAccess::count(*owner) ==
                  1,
          "closed Remote record prevented a clean exact retry");
  bridge::ProductionSurfaceEndpointOwnerTestAccess::close_all(*owner);
  require(second.detach_calls == 2 &&
              bridge::ProductionSurfaceEndpointOwnerTestAccess::count(*owner) ==
                  0,
          "close-all did not fence every endpoint before root teardown");
}

void failed_endpoint_attach_is_transactional() {
  Port port;
  port.fail_attach = true;
  Inspection inspection;
  Clock clock;
  auto owner = bridge::ProductionSurfaceEndpointOwnerTestAccess::create(
      inspection, clock, port.description.binding, 1, port);
  QQuickWindow window;
  bridge::RemotePluginSurface remote;
  place(remote, window);
  const QString key = QStringLiteral("opaque-fault");
  auto slot = published(port, key);
  require(
      bridge::ProductionSurfaceEndpointOwnerTestAccess::attach(*owner, slot,
                                                               key, remote) ==
              bridge::ProductionEndpointAttachResult::rejected &&
          bridge::ProductionSurfaceEndpointOwnerTestAccess::count(*owner) == 0,
      "failed endpoint attach retained owner state");
  port.fail_attach = false;
  require(bridge::ProductionSurfaceEndpointOwnerTestAccess::attach(
              *owner, slot, key, remote) ==
              bridge::ProductionEndpointAttachResult::attached,
          "failed attach retained Remote/session ownership");
}

} // namespace

void run_production_surface_endpoint_owner_tests() {
  trusted_geometry_is_derived_and_retryable();
  invalid_geometry_and_context_fail_without_ownership();
  duplicate_key_and_cross_slot_remote_reuse_fail();
  key_and_expanded_pixel_bounds_are_exact();
  eighth_endpoint_is_accepted_and_ninth_is_rejected();
  teardown_replacement_and_remote_destruction_are_exact();
  failed_endpoint_attach_is_transactional();
}
