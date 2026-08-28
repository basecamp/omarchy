#include "test.hpp"

#include "omarchy/plugin_runtime/surface/frame_transport.hpp"

#include <atomic>
#include <cstddef>
#include <cstdint>
#include <vector>

using namespace omarchy::plugin_runtime::surface;

struct SequenceMutator {
  SequenceMutator(std::span<std::byte> mapping, CopyStage target,
                  std::uint64_t replacement)
      : mapping_(mapping), target_(target), replacement_(replacement) {}

  static void observe(CopyStage stage, void *context) noexcept {
    auto &self = *static_cast<SequenceMutator *>(context);
    if (stage != self.target_) {
      return;
    }
    auto &word = *reinterpret_cast<std::uint64_t *>(self.mapping_.data());
    std::atomic_ref<std::uint64_t>(word).store(self.replacement_,
                                               std::memory_order_release);
  }

  std::span<std::byte> mapping_;
  CopyStage target_;
  std::uint64_t replacement_;
};

struct ReentrantConsumer {
  static void observe(CopyStage, void *context) noexcept {
    auto &self = *static_cast<ReentrantConsumer *>(context);
    if (self.called) {
      return;
    }
    self.called = true;
    self.result = self.consumer->consume(self.mapping, self.notification);
  }

  FrameConsumer *consumer;
  std::span<const std::byte> mapping;
  FrameReady notification;
  ConsumeResult result = ConsumeResult::accepted;
  bool called = false;
};

int main() {
  const auto allocation =
      make_allocation({.id = 7, .generation = 3}, 8, 4, 8, 4, 1, 1, 4096);
  require(allocation.has_value(), "fixture allocation failed");
  std::vector<std::byte> mapping(allocation->mapping_bytes);
  require(initialize_frame_mapping(mapping, *allocation),
          "mapping initialization failed");
  std::vector<std::byte> first(allocation->frame_bytes, std::byte{0x11});
  std::vector<std::byte> second(allocation->frame_bytes, std::byte{0x82});
  auto consumer = FrameConsumer::create(*allocation);
  require(consumer.has_value(), "consumer construction failed");
  auto inconsistent = *allocation;
  ++inconsistent.frame_bytes;
  require(!FrameConsumer::create(inconsistent),
          "inconsistent consumer allocation accepted");

  require(publish_frame(mapping, *allocation, 0, 2, 1, first) ==
              PublishResult::published,
          "first publication failed");
  require(consumer->consume(mapping, {.surface = allocation->surface,
                                      .slot = 0,
                                      .slot_sequence = 2,
                                      .frame_sequence = 1}) ==
              ConsumeResult::accepted,
          "first consumption failed");
  require(consumer->last_frame() && consumer->last_frame()->pixels == first,
          "first private copy changed");

  require(publish_frame(mapping, *allocation, 1, 4, 2, second) ==
              PublishResult::published,
          "second-slot publication failed");
  require(consumer->consume(mapping, {.surface = allocation->surface,
                                      .slot = 1,
                                      .slot_sequence = 4,
                                      .frame_sequence = 2}) ==
              ConsumeResult::accepted,
          "second-slot consumption failed");
  require(consumer->last_frame()->pixels == second,
          "full-frame alternation failed");

  require(consumer->consume(mapping, {.surface = allocation->surface,
                                      .slot = 0,
                                      .slot_sequence = 2,
                                      .frame_sequence = 1}) ==
              ConsumeResult::invalid_sequence,
          "replayed frame accepted");
  require(consumer->consume(mapping, {.surface = {.id = 7, .generation = 2},
                                      .slot = 0,
                                      .slot_sequence = 2,
                                      .frame_sequence = 3}) ==
              ConsumeResult::stale_surface,
          "stale surface accepted");

  auto &sequence_word = *reinterpret_cast<std::uint64_t *>(mapping.data());
  std::atomic_ref<std::uint64_t>(sequence_word)
      .store(5, std::memory_order_release);
  require(consumer->consume(mapping, {.surface = allocation->surface,
                                      .slot = 0,
                                      .slot_sequence = 6,
                                      .frame_sequence = 3}) ==
              ConsumeResult::concurrent_write,
          "odd/racing slot accepted");
  require(consumer->last_frame()->pixels == second,
          "failed frame replaced last valid frame");

  require(publish_frame(mapping, *allocation, 0, 6, 3, first) ==
              PublishResult::published,
          "third publication failed");
  mapping[kSlotPixelOffset] = std::byte{0xff};
  require(consumer->consume(mapping, {.surface = allocation->surface,
                                      .slot = 0,
                                      .slot_sequence = 6,
                                      .frame_sequence = 3}) ==
              ConsumeResult::accepted,
          "bounded adversarial pixels were rejected as authority");
  require(consumer->last_frame()->pixels.size() == allocation->frame_bytes &&
              consumer->last_frame()->pixels.front() == std::byte{0xff},
          "private bounded copy failed");

  require(consumer->consume(mapping, {.surface = allocation->surface,
                                      .slot = 0,
                                      .slot_sequence = 6,
                                      .frame_sequence = 4}) ==
              ConsumeResult::invalid_sequence,
          "per-slot sequence reuse accepted");

  require(publish_frame(mapping, *allocation, 0, 8, 4, first) ==
              PublishResult::published,
          "fourth publication failed");

  mapping[67] ^= std::byte{1};
  require(consumer->consume(mapping, {.surface = allocation->surface,
                                      .slot = 0,
                                      .slot_sequence = 8,
                                      .frame_sequence = 4}) ==
              ConsumeResult::allocation_mismatch,
          "worker stride mutation accepted");
  require(consumer->last_frame()->frame_sequence == 3,
          "malformed header replaced last valid frame");

  const auto truncated =
      std::span<const std::byte>(mapping).first(mapping.size() - 1);
  require(consumer->consume(truncated, {.surface = allocation->surface,
                                        .slot = 0,
                                        .slot_sequence = 8,
                                        .frame_sequence = 4}) ==
              ConsumeResult::region_too_small,
          "truncated region accepted");

  require(publish_frame(mapping, *allocation, 0, 10, 5,
                        std::span(first).first(first.size() - 1)) ==
              PublishResult::invalid_frame,
          "short frame accepted");

  require(publish_frame(mapping, *allocation, 0, 12, 6, first) ==
              PublishResult::published,
          "header-race fixture publication failed");
  SequenceMutator header_mutator(mapping, CopyStage::header_copied, 13);
  auto header_race_consumer = FrameConsumer::create(*allocation);
  require(header_race_consumer &&
              header_race_consumer->consume(mapping,
                                            {.surface = allocation->surface,
                                             .slot = 0,
                                             .slot_sequence = 12,
                                             .frame_sequence = 6},
                                            SequenceMutator::observe,
                                            &header_mutator) ==
                  ConsumeResult::concurrent_write,
          "mutation during header copy was accepted");

  require(publish_frame(mapping, *allocation, 0, 14, 7, second) ==
              PublishResult::published,
          "pixel-race fixture publication failed");
  SequenceMutator pixel_mutator(mapping, CopyStage::pixels_copied, 15);
  auto pixel_race_consumer = FrameConsumer::create(*allocation);
  require(pixel_race_consumer &&
              pixel_race_consumer->consume(mapping,
                                           {.surface = allocation->surface,
                                            .slot = 0,
                                            .slot_sequence = 14,
                                            .frame_sequence = 7},
                                           SequenceMutator::observe,
                                           &pixel_mutator) ==
                  ConsumeResult::concurrent_write,
          "mutation during pixel copy was accepted");

  require(publish_frame(mapping, *allocation, 0, 16, 8, first) ==
              PublishResult::published,
          "reentry fixture publication failed");
  auto reentry_consumer = FrameConsumer::create(*allocation);
  require(reentry_consumer.has_value(), "reentry consumer creation failed");
  const FrameReady reentry_notification{.surface = allocation->surface,
                                        .slot = 0,
                                        .slot_sequence = 16,
                                        .frame_sequence = 8};
  ReentrantConsumer reentry{.consumer = &*reentry_consumer,
                            .mapping = mapping,
                            .notification = reentry_notification};
  require(reentry_consumer->consume(mapping, reentry_notification,
                                    ReentrantConsumer::observe,
                                    &reentry) == ConsumeResult::accepted &&
              reentry.called &&
              reentry.result == ConsumeResult::consumer_busy &&
              reentry_consumer->last_frame() &&
              reentry_consumer->last_frame()->pixels == first,
          "reentrant consumption corrupted the accepted private frame");
}
