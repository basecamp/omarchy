#include "gesture_eligibility.hpp"

#include <atomic>
#include <barrier>
#include <memory>
#include <stdexcept>
#include <string>
#include <thread>

namespace runtime = omarchy::plugin_runtime::runtime;
namespace definitions = omarchy::plugins::definitions;
namespace permissions = omarchy::plugins::permissions;

namespace {
struct Clock final : runtime::GestureEligibilityClock {
  std::uint64_t now = 100;
  std::uint64_t now_nanoseconds() const override { return now; }
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
  runtime::GestureEligibilityLatch latch(clock);
  const permissions::ActivationBinding binding{
      .plugin = permissions::PluginId("fixture.gesture"),
      .revision = digest('1'),
      .policy_fingerprint = digest('2'),
      .generation = 7};
  const definitions::DynamicInvocation::GestureClaim claim{
      .surface_id = 3, .surface_generation = 7, .input_sequence = 11};
  require(latch.arm(binding, claim), "gesture arm failed");
  auto wrong = claim;
  ++wrong.surface_id;
  require(!latch.consume(binding, wrong), "wrong source consumed as allowed");
  require(!latch.consume(binding, claim), "probe retained one-use gesture");
  require(latch.arm(binding, claim), "gesture rearm failed");
  require(latch.consume(binding, claim).has_value(),
          "exact gesture rejected");
  require(!latch.consume(binding, claim), "gesture replay accepted");
  require(latch.arm(binding, claim), "expiry arm failed");
  clock->now += 5'000'000'000ULL;
  require(!latch.consume(binding, claim), "expired gesture accepted");
  auto stale_generation = claim;
  --stale_generation.surface_generation;
  require(!latch.arm(binding, stale_generation),
          "cross-generation gesture armed");

  auto other_surface = claim;
  ++other_surface.surface_id;
  other_surface.input_sequence = 12;
  require(latch.arm(binding, other_surface),
          "other-surface clear fixture did not arm");
  latch.clear_surface(binding, claim.surface_id, claim.surface_generation);
  require(latch.consume(binding, other_surface).has_value(),
          "clearing one surface erased another surface's gesture");

  auto other_binding = binding;
  other_binding.revision = digest('3');
  other_surface.input_sequence = 13;
  require(latch.arm(binding, other_surface),
          "wrong-binding clear fixture did not arm");
  latch.clear_surface(other_binding, other_surface.surface_id,
                      other_surface.surface_generation);
  require(latch.consume(binding, other_surface).has_value(),
          "a different activation binding erased gesture eligibility");

  other_surface.input_sequence = 14;
  require(latch.arm(binding, other_surface),
          "exact-source clear fixture did not arm");
  latch.clear_surface(binding, other_surface.surface_id,
                      other_surface.surface_generation);
  require(!latch.consume(binding, other_surface),
          "exact-source clear retained gesture eligibility");

  other_surface.input_sequence = 15;
  require(latch.arm(binding, other_surface),
          "global clear fixture did not arm");
  latch.clear();
  require(!latch.consume(binding, other_surface),
          "global clear retained gesture eligibility");

  constexpr int kRaceIterations = 500;
  std::barrier race_phase(4);
  std::atomic<int> successes = 0;
  definitions::DynamicInvocation::GestureClaim race_claim = claim;
  auto consume_racer = [&] {
    for (int iteration = 0; iteration < kRaceIterations; ++iteration) {
      race_phase.arrive_and_wait();
      if (latch.consume(binding, race_claim))
        successes.fetch_add(1, std::memory_order_relaxed);
      race_phase.arrive_and_wait();
    }
  };
  std::thread first_consumer(consume_racer);
  std::thread second_consumer(consume_racer);
  std::thread armer([&] {
    for (int iteration = 0; iteration < kRaceIterations; ++iteration) {
      race_phase.arrive_and_wait();
      static_cast<void>(latch.arm(binding, race_claim));
      race_phase.arrive_and_wait();
    }
  });
  for (int iteration = 0; iteration < kRaceIterations; ++iteration) {
    latch.clear();
    successes.store(0, std::memory_order_relaxed);
    race_claim.input_sequence = 100 + static_cast<std::uint64_t>(iteration);
    race_phase.arrive_and_wait();
    race_phase.arrive_and_wait();
    require(successes.load(std::memory_order_relaxed) <= 1,
            "concurrent arm admitted one gesture more than once");
  }
  armer.join();
  first_consumer.join();
  second_consumer.join();

  std::barrier clear_phase(4);
  auto clear_consumer = [&] {
    for (int iteration = 0; iteration < kRaceIterations; ++iteration) {
      clear_phase.arrive_and_wait();
      if (latch.consume(binding, race_claim))
        successes.fetch_add(1, std::memory_order_relaxed);
      clear_phase.arrive_and_wait();
    }
  };
  std::thread third_consumer(clear_consumer);
  std::thread fourth_consumer(clear_consumer);
  std::thread clearer([&] {
    for (int iteration = 0; iteration < kRaceIterations; ++iteration) {
      clear_phase.arrive_and_wait();
      latch.clear();
      clear_phase.arrive_and_wait();
    }
  });
  for (int iteration = 0; iteration < kRaceIterations; ++iteration) {
    successes.store(0, std::memory_order_relaxed);
    race_claim.input_sequence = 1'000 + static_cast<std::uint64_t>(iteration);
    require(latch.arm(binding, race_claim), "clear race arm failed");
    clear_phase.arrive_and_wait();
    clear_phase.arrive_and_wait();
    require(successes.load(std::memory_order_relaxed) <= 1,
            "concurrent clear admitted one gesture more than once");
  }
  clearer.join();
  third_consumer.join();
  fourth_consumer.join();
}
