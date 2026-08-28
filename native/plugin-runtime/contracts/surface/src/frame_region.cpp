#include "omarchy/plugin_runtime/surface/frame_region.hpp"

#include "omarchy/plugin_runtime/surface/checked_math.hpp"
#include "omarchy/plugin_runtime/surface/frame_transport.hpp"

#include <fcntl.h>
#include <linux/memfd.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <unistd.h>

#include <cstring>
#include <memory>
#include <utility>

namespace omarchy::plugin_runtime::surface {

HostFrameRegion::HostFrameRegion(int fd, std::byte *mapping, std::size_t size)
    : fd_(fd), mapping_(mapping), size_(size) {}

HostFrameRegion::HostFrameRegion(HostFrameRegion &&other) noexcept
    : fd_(std::exchange(other.fd_, -1)),
      mapping_(std::exchange(other.mapping_, nullptr)),
      size_(std::exchange(other.size_, 0)) {}

HostFrameRegion &HostFrameRegion::operator=(HostFrameRegion &&other) noexcept {
  if (this != &other) {
    reset();
    fd_ = std::exchange(other.fd_, -1);
    mapping_ = std::exchange(other.mapping_, nullptr);
    size_ = std::exchange(other.size_, 0);
  }
  return *this;
}

HostFrameRegion::~HostFrameRegion() { reset(); }

void HostFrameRegion::reset() {
  if (mapping_ != nullptr) {
    (void)munmap(mapping_, size_);
  }
  if (fd_ >= 0) {
    (void)close(fd_);
  }
  fd_ = -1;
  mapping_ = nullptr;
  size_ = 0;
}

std::optional<HostFrameRegion>
HostFrameRegion::create(const TrustedAllocation &allocation) {
  const long system_page_size = sysconf(_SC_PAGESIZE);
  if (system_page_size <= 0) {
    return std::nullopt;
  }
  const auto mapping_size = checked_cast<std::size_t>(allocation.mapping_bytes);
  const auto file_size = checked_cast<off_t>(allocation.mapping_bytes);
  if (!allocation_is_consistent(allocation) ||
      allocation.page_size != static_cast<std::uint64_t>(system_page_size) ||
      !mapping_size || !file_size || *mapping_size == 0) {
    return std::nullopt;
  }
  const int fd =
      static_cast<int>(syscall(SYS_memfd_create, "omarchy-plugin-frame",
                               MFD_CLOEXEC | MFD_ALLOW_SEALING));
  if (fd < 0) {
    return std::nullopt;
  }
  if (ftruncate(fd, *file_size) != 0) {
    (void)close(fd);
    return std::nullopt;
  }
  void *mapping =
      mmap(nullptr, *mapping_size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
  if (mapping == MAP_FAILED) {
    (void)close(fd);
    return std::nullopt;
  }
  if (!initialize_frame_mapping(
          {static_cast<std::byte *>(mapping), *mapping_size}, allocation)) {
    (void)munmap(mapping, *mapping_size);
    (void)close(fd);
    return std::nullopt;
  }
  constexpr int required_seals = F_SEAL_GROW | F_SEAL_SHRINK | F_SEAL_SEAL;
  if (fcntl(fd, F_ADD_SEALS, required_seals) != 0 ||
      mprotect(mapping, *mapping_size, PROT_READ) != 0) {
    (void)munmap(mapping, *mapping_size);
    (void)close(fd);
    return std::nullopt;
  }
  return HostFrameRegion(fd, static_cast<std::byte *>(mapping), *mapping_size);
}

int HostFrameRegion::duplicate_worker_fd() const {
  if (fd_ < 0) {
    return -1;
  }
  return fcntl(fd_, F_DUPFD_CLOEXEC, 3);
}

std::span<const std::byte> HostFrameRegion::host_mapping() const {
  return {mapping_, size_};
}

int HostFrameRegion::seals() const {
  return fd_ < 0 ? -1 : fcntl(fd_, F_GET_SEALS);
}

} // namespace omarchy::plugin_runtime::surface
