#include "test.hpp"

#include "omarchy/plugin_runtime/surface/frame_region.hpp"
#include "omarchy/plugin_runtime/surface/frame_transport.hpp"

#include <fcntl.h>
#include <sys/mman.h>
#include <unistd.h>

#include <cstddef>
#include <vector>

using namespace omarchy::plugin_runtime::surface;

int main() {
  const auto allocation =
      make_allocation({.id = 12, .generation = 1}, 8, 4, 8, 4, 1, 1, 4096);
  require(allocation.has_value(), "fixture allocation failed");
  auto region = HostFrameRegion::create(*allocation);
  require(region.has_value(), "host frame region creation failed");
  auto inconsistent = *allocation;
  ++inconsistent.slot_extent;
  require(!HostFrameRegion::create(inconsistent),
          "inconsistent frame region accepted");
  const int seals = region->seals();
  require((seals & (F_SEAL_GROW | F_SEAL_SHRINK | F_SEAL_SEAL)) ==
                  (F_SEAL_GROW | F_SEAL_SHRINK | F_SEAL_SEAL) &&
              (seals & F_SEAL_WRITE) == 0,
          "streaming memfd seals are wrong");
  const int worker_fd = region->duplicate_worker_fd();
  require(worker_fd >= 3 && (fcntl(worker_fd, F_GETFD) & FD_CLOEXEC) != 0,
          "worker descriptor duplication failed");
  void *worker_mapping = mmap(nullptr, allocation->mapping_bytes,
                              PROT_READ | PROT_WRITE, MAP_SHARED, worker_fd, 0);
  require(worker_mapping != MAP_FAILED, "worker writable mapping failed");
  std::vector<std::byte> pixels(allocation->frame_bytes, std::byte{0x42});
  require(publish_frame({static_cast<std::byte *>(worker_mapping),
                         static_cast<std::size_t>(allocation->mapping_bytes)},
                        *allocation, 0, 2, 1,
                        pixels) == PublishResult::published,
          "shared-region publication failed");
  auto consumer = FrameConsumer::create(*allocation);
  require(consumer.has_value(), "consumer construction failed");
  require(consumer->consume(region->host_mapping(),
                            {.surface = allocation->surface,
                             .slot = 0,
                             .slot_sequence = 2,
                             .frame_sequence = 1}) == ConsumeResult::accepted,
          "read-only host mapping consumption failed");
  require(consumer->last_frame() && consumer->last_frame()->pixels == pixels,
          "host private copy changed");
  require(munmap(worker_mapping, allocation->mapping_bytes) == 0,
          "worker mapping cleanup failed");
  require(close(worker_fd) == 0, "worker descriptor cleanup failed");
}
