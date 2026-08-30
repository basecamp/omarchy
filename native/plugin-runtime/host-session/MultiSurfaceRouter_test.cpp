#include "MultiSurfaceRouter.h"

#include <array>
#include <cstddef>
#include <cstdint>
#include <cerrno>
#include <fcntl.h>
#include <iostream>
#include <optional>
#include <stdexcept>
#include <unistd.h>
#include <vector>

namespace runtime = omarchy::plugin_runtime;
namespace host = runtime::host_session;
namespace surface = runtime::surface;
namespace wire = omarchy::plugin::wire;

namespace {

constexpr std::uint64_t kGeneration = 41;

struct Endpoint final : host::SurfaceEndpoint {
  bool accept = true;
  std::size_t deliveries = 0;
  std::optional<host::OwnedAuthenticatedRenderMessage> last;

  bool receive(host::OwnedAuthenticatedRenderMessage message) override {
    ++deliveries;
    last.emplace(std::move(message));
    return accept;
  }
};

[[noreturn]] void fail(const char *message) {
  std::cerr << "FAIL: " << message << '\n';
  std::exit(1);
}

void expect(bool condition, const char *message) {
  if (!condition) {
    fail(message);
  }
}

host::OwnedAuthenticatedRenderMessage message(
    std::uint64_t generation, std::uint64_t correlation = 0,
    std::optional<surface::SurfaceKey> key = std::nullopt) {
  return {.launch_generation = generation,
          .message_type = 0x2020,
          .correlation = correlation,
          .surface = key,
          .payload = {std::byte{0x2a}},
          .descriptors = {}};
}

int descriptor_message(host::OwnedAuthenticatedRenderMessage &value) {
  int descriptors[2] = {-1, -1};
  expect(::pipe2(descriptors, O_CLOEXEC) == 0, "could not create routed fd");
  ::close(descriptors[1]);
  value.descriptors.emplace_back(descriptors[0]);
  return descriptors[0];
}

bool closed(int descriptor) {
  errno = 0;
  return ::fcntl(descriptor, F_GETFD) == -1 && errno == EBADF;
}

} // namespace

int main() {
  bool rejected_zero_generation = false;
  try {
    host::MultiSurfaceRouter invalid(0);
  } catch (const std::invalid_argument &) {
    rejected_zero_generation = true;
  }
  expect(rejected_zero_generation, "accepted zero launch generation");

  host::MultiSurfaceRouter router(kGeneration);
  Endpoint first;
  Endpoint second;
  const surface::SurfaceKey first_key{.id = 1, .generation = kGeneration};
  const surface::SurfaceKey second_key{.id = 2, .generation = kGeneration};
  const std::array<std::uint64_t, 2> first_correlations{101, 102};
  const std::array<std::uint64_t, 1> second_correlations{201};
  const std::array<std::uint64_t, 1> duplicate_existing{101};
  const std::array<std::uint64_t, 2> duplicate_local{201, 201};
  const std::array<std::uint64_t, 1> zero_correlation{0};

  expect(router.launchGeneration() == kGeneration,
         "lost fixed launch generation");
  expect(router.attach(first_key, first_correlations, first) ==
             host::AttachResult::attached,
         "failed first attachment");
  expect(router.attach(first_key, {}, second) ==
             host::AttachResult::duplicate_surface,
         "accepted duplicate surface");
  expect(router.attach(second_key, duplicate_existing, second) ==
             host::AttachResult::duplicate_correlation,
         "accepted cross-surface duplicate correlation");
  expect(router.attach(second_key, duplicate_local, second) ==
             host::AttachResult::invalid_registration,
         "accepted within-registration duplicate correlation");
  expect(router.attach(second_key, zero_correlation, second) ==
             host::AttachResult::invalid_registration,
         "accepted zero correlation");
  expect(router.attach({.id = 0, .generation = kGeneration}, {}, second) ==
             host::AttachResult::invalid_registration,
         "accepted zero surface id");
  expect(router.attach({.id = 2, .generation = kGeneration + 1}, {}, second) ==
             host::AttachResult::invalid_registration,
         "accepted cross-generation registration");
  std::array<std::uint64_t,
             host::MultiSurfaceRouter::kMaximumCorrelationsPerEndpoint + 1>
      excessive{};
  for (std::size_t index = 0; index < excessive.size(); ++index) {
    excessive[index] = 300 + index;
  }
  expect(router.attach(second_key, excessive, second) ==
             host::AttachResult::invalid_registration,
         "accepted excessive correlations");
  expect(router.attach(second_key, second_correlations, second) ==
             host::AttachResult::attached,
         "failed second attachment");

  expect(router.route(message(kGeneration, 0, first_key)) ==
             host::RouteResult::delivered,
         "surface-only route failed");
  expect(router.route(message(kGeneration, 201)) ==
             host::RouteResult::delivered,
         "correlation-only route failed");
  expect(router.route(message(kGeneration, 102, first_key)) ==
             host::RouteResult::delivered,
         "agreeing dual route failed");
  expect(router.route(message(kGeneration, 201, first_key)) ==
             host::RouteResult::conflicting_destination,
         "conflicting dual route reached an endpoint");
  expect(router.route(message(kGeneration)) ==
             host::RouteResult::missing_destination,
         "accepted missing destination");
  expect(router.route(message(kGeneration, 999)) ==
             host::RouteResult::unknown_correlation,
         "accepted unknown correlation");
  expect(router.route(message(kGeneration, 0,
                              surface::SurfaceKey{.id = 999,
                                                  .generation = kGeneration})) ==
             host::RouteResult::unknown_surface,
         "accepted unknown surface");
  expect(router.route(message(kGeneration - 1, 101)) ==
             host::RouteResult::stale_generation,
         "accepted stale message generation");
  expect(router.route(message(kGeneration, 0,
                              surface::SurfaceKey{.id = 1,
                                                  .generation = kGeneration - 1})) ==
             host::RouteResult::stale_generation,
         "accepted stale surface generation");
  expect(first.deliveries == 2 && second.deliveries == 1,
         "rejected traffic reached an endpoint");

  auto owned = message(kGeneration, 101, first_key);
  owned.message_type = 0x2010;
  owned.payload = {std::byte{0x10}, std::byte{0x20}};
  const int delivered_fd = descriptor_message(owned);
  expect(router.route(std::move(owned)) == host::RouteResult::delivered &&
             first.last && first.last->message_type == 0x2010 &&
             first.last->payload ==
                 std::vector<std::byte>({std::byte{0x10}, std::byte{0x20}}) &&
             first.last->descriptors.size() == 1 &&
             first.last->descriptors.front().get() == delivered_fd,
         "owned type, payload, or descriptor did not arrive exactly once");
  first.last.reset();
  expect(closed(delivered_fd), "delivered descriptor ownership was not closed");

  auto unknown_owned = message(
      kGeneration, 0,
      surface::SurfaceKey{.id = 999, .generation = kGeneration});
  const int unknown_fd = descriptor_message(unknown_owned);
  const auto unknown_result = router.route(std::move(unknown_owned));
  expect(unknown_result == host::RouteResult::unknown_surface &&
             closed(unknown_fd),
         "unknown-surface rejection leaked an owned descriptor");
  auto conflict_owned = message(kGeneration, 201, first_key);
  const int conflict_fd = descriptor_message(conflict_owned);
  const auto conflict_result = router.route(std::move(conflict_owned));
  expect(conflict_result == host::RouteResult::conflicting_destination &&
             closed(conflict_fd),
         "conflicting-destination rejection leaked an owned descriptor");

  first.accept = false;
  expect(router.route(message(kGeneration, 101)) ==
             host::RouteResult::endpoint_rejected,
         "lost endpoint rejection");

  expect(!router.detach(first_key, second),
         "stale owner detached active registration");
  expect(!router.detach({.id = 1, .generation = kGeneration - 1}, first),
         "cross-generation detach was treated as valid");
  expect(router.detach(first_key, first), "owner could not detach surface");
  expect(router.detach(first_key, first), "detach was not idempotent");
  expect(router.size() == 1, "detach changed unrelated registration");
  expect(router.route(message(kGeneration, 101)) ==
             host::RouteResult::unknown_correlation,
         "detached correlation remained routable");

  first.accept = true;
  expect(router.attach(first_key, first_correlations, first) ==
             host::AttachResult::attached,
         "reattach required a relaunch");
  expect(router.route(message(kGeneration, 101, first_key)) ==
             host::RouteResult::delivered,
         "reattached surface did not route");

  router.detachAll();
  expect(router.size() == 0, "detachAll left registrations behind");

  std::vector<Endpoint> endpoints(wire::kMaximumPluginSurfaces);
  for (std::size_t index = 0; index < endpoints.size(); ++index) {
    const surface::SurfaceKey key{.id = 1000 + index,
                                  .generation = kGeneration};
    expect(router.attach(key, {}, endpoints[index]) ==
               host::AttachResult::attached,
           "failed attachment below capacity");
  }
  Endpoint overflow;
  expect(router.attach({.id = 9999, .generation = kGeneration}, {}, overflow) ==
             host::AttachResult::capacity_exceeded,
         "accepted attachment above capacity");

  std::cout << "MultiSurfaceRouter tests passed\n";
  return 0;
}
