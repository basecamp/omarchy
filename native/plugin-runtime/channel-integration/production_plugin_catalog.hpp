#pragma once

#include "activation_snapshot.hpp"

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

// The retained record FD pins the catalog's inventory epoch and detects a
// mutation before the snapshot is handed off. It is not a second activation
// authority: ProductionPluginRuntimeRoot still selects and verifies through
// ActivationSource. A future descriptor-consuming activation API must replace,
// rather than supplement, that one selection path.
class ProductionPluginCatalogEntry final {
public:
  ProductionPluginCatalogEntry(ProductionPluginCatalogEntry &&) noexcept =
      default;
  ProductionPluginCatalogEntry &
  operator=(ProductionPluginCatalogEntry &&) noexcept = default;
  ProductionPluginCatalogEntry(const ProductionPluginCatalogEntry &) = delete;
  ProductionPluginCatalogEntry &
  operator=(const ProductionPluginCatalogEntry &) = delete;

  [[nodiscard]] std::string_view record_name() const noexcept {
    return record_name_;
  }
  [[nodiscard]] const host_session::ActivationRecord &record() const noexcept {
    return inspected_.record();
  }
  [[nodiscard]] int inventory_record_fd() const noexcept {
    return inspected_.descriptor();
  }
  [[nodiscard]] bool unchanged() const noexcept {
    return inspected_.unchanged();
  }

private:
  ProductionPluginCatalogEntry(
      std::string record_name,
      host_session::InspectedActivationRecord inspected) noexcept;

  std::string record_name_;
  host_session::InspectedActivationRecord inspected_;

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

  [[nodiscard]] int activation_root_fd() const noexcept {
    return activation_root_.get();
  }
  [[nodiscard]] std::span<const ProductionPluginCatalogEntry>
  entries() const noexcept {
    return entries_;
  }

private:
  ProductionPluginCatalog(host_session::OwnedDescriptor activation_root,
                          std::vector<ProductionPluginCatalogEntry> entries);

  host_session::OwnedDescriptor activation_root_;
  std::vector<ProductionPluginCatalogEntry> entries_;
};

} // namespace omarchy::plugin_runtime::channel
