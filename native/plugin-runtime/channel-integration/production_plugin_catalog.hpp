#pragma once

#include "activation_snapshot.hpp"

#include <sys/stat.h>

#include <cstddef>
#include <cstdint>
#include <memory>
#include <span>
#include <string>
#include <string_view>
#include <vector>

namespace omarchy::plugin_runtime::channel {

inline constexpr std::size_t kMaximumProductionPluginCatalogEntries = 1024;

enum class ProductionPluginCatalogError : std::uint8_t {
  none,
  root_untrusted,
  enumeration_failed,
  bound_exceeded,
  unexpected_entry,
  invalid_record,
  duplicate_plugin,
  mutated,
  resource_exhausted,
  internal_failure,
};

// Candidate labels are inventory only. Opaque epoch predicates let the manager
// preserve a last-good scan and identify additions, removals or changes without
// exposing parsed activation authority or record descriptors.
class ProductionPluginCatalogEntry final {
public:
  ProductionPluginCatalogEntry(ProductionPluginCatalogEntry &&) noexcept =
      default;
  ProductionPluginCatalogEntry &
  operator=(ProductionPluginCatalogEntry &&) noexcept = default;
  ProductionPluginCatalogEntry(const ProductionPluginCatalogEntry &) = delete;
  ProductionPluginCatalogEntry &
  operator=(const ProductionPluginCatalogEntry &) = delete;

  [[nodiscard]] std::string_view plugin_id() const noexcept {
    return record_name_;
  }
  [[nodiscard]] bool
  same_epoch(const ProductionPluginCatalogEntry &other) const noexcept;

private:
  struct Epoch final {
    std::uint64_t device = 0;
    std::uint64_t inode = 0;
    std::uint64_t size = 0;
    std::int64_t modified_seconds = 0;
    std::int64_t modified_nanoseconds = 0;
    std::int64_t changed_seconds = 0;
    std::int64_t changed_nanoseconds = 0;
    std::uint32_t mode = 0;
    std::uint32_t uid = 0;
    std::uint32_t gid = 0;
    std::uint64_t links = 0;
    bool operator==(const Epoch &) const = default;
  };

  ProductionPluginCatalogEntry(
      std::string record_name,
      host_session::InspectedActivationRecord inspected, Epoch epoch) noexcept;
  [[nodiscard]] bool currently_unchanged() const noexcept {
    return inspected_.unchanged();
  }

  std::string record_name_;
  host_session::InspectedActivationRecord inspected_;
  Epoch epoch_;

  friend class ProductionPluginCatalog;
};

class ProductionPluginCatalog final {
public:
  ProductionPluginCatalog(ProductionPluginCatalog &&) noexcept = default;
  ProductionPluginCatalog &
  operator=(ProductionPluginCatalog &&) noexcept = default;
  ProductionPluginCatalog(const ProductionPluginCatalog &) = delete;
  ProductionPluginCatalog &operator=(const ProductionPluginCatalog &) = delete;

  [[nodiscard]] static std::unique_ptr<ProductionPluginCatalog>
  load(int activation_root_fd, std::uint32_t trusted_uid,
       ProductionPluginCatalogError &error) noexcept;

  [[nodiscard]] std::span<const ProductionPluginCatalogEntry>
  entries() const noexcept {
    return entries_;
  }
  [[nodiscard]] bool unchanged() const noexcept;
  [[nodiscard]] bool
  same_epoch(const ProductionPluginCatalog &other) const noexcept;

private:
  ProductionPluginCatalog(host_session::OwnedDescriptor activation_root,
                          ProductionPluginCatalogEntry::Epoch root_epoch,
                          std::vector<ProductionPluginCatalogEntry> entries);
  [[nodiscard]] static bool
  capture_epoch(int descriptor,
                ProductionPluginCatalogEntry::Epoch &epoch) noexcept;
  [[nodiscard]] static ProductionPluginCatalogEntry::Epoch
  epoch_from_metadata(const struct stat &metadata) noexcept;

  host_session::OwnedDescriptor activation_root_;
  ProductionPluginCatalogEntry::Epoch root_epoch_;
  std::vector<ProductionPluginCatalogEntry> entries_;
};

} // namespace omarchy::plugin_runtime::channel
