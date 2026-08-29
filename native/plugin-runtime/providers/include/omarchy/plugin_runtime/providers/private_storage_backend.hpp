#pragma once

#include "omarchy/plugin_runtime/providers/provider_set.hpp"

#include <cstdint>

namespace omarchy::plugin_runtime::providers {

// A revision-private storage backend. The caller supplies an already opened,
// trusted directory; plugin data can therefore never select a host path.
class PrivateStorageBackend {
public:
  PrivateStorageBackend(int directory_fd, std::uint64_t maximum_total_bytes,
                        std::uint64_t maximum_item_bytes) noexcept;
  PrivateStorageBackend(const PrivateStorageBackend &) = delete;
  PrivateStorageBackend &operator=(const PrivateStorageBackend &) = delete;
  ~PrivateStorageBackend();

  [[nodiscard]] bool valid() const noexcept { return directory_fd_ >= 0; }
  [[nodiscard]] StorageBackend configuration() noexcept;

private:
  static bool read(std::string_view key, std::span<std::byte> output,
                   std::size_t &written, bool &found, void *context) noexcept;
  static bool write(std::string_view key, std::span<const std::byte> value,
                    void *context) noexcept;
  static bool remove(std::string_view key, void *context) noexcept;
  [[nodiscard]] bool within_total_limit(std::string_view replacing,
                                        std::size_t new_size) const noexcept;

  int directory_fd_ = -1;
  std::uint64_t maximum_total_bytes_ = 0;
  std::uint64_t maximum_item_bytes_ = 0;
  std::uint64_t temporary_sequence_ = 0;
};

} // namespace omarchy::plugin_runtime::providers
