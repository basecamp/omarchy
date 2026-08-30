#pragma once

#include "production_plugin_roots.hpp"
#include "production_plugin_runtime_root.hpp"

#include <cstdint>
#include <memory>
#include <optional>
#include <string_view>
#include <utility>

namespace omarchy::plugin_runtime::channel {

enum class ProductionPluginBootstrapError : std::uint8_t {
  none,
  roots_unavailable,
  package_definitions_unavailable,
  package_definitions_untrusted,
  admin_definitions_untrusted,
  definition_document_rejected,
  definition_adapter_unavailable,
  definition_registry_rejected,
  definition_bound_exceeded,
  resource_exhausted,
  internal_failure,
};

// Immutable production composition shared by every v2 plugin runtime. All
// paths, adapters, providers and limits are compiled host policy. Activation
// candidates contribute only the exact record and plugin names already
// selected by the trusted activation catalog.
class ProductionPluginBootstrap final {
public:
  ProductionPluginBootstrap(const ProductionPluginBootstrap &) = delete;
  ProductionPluginBootstrap &
  operator=(const ProductionPluginBootstrap &) = delete;

  [[nodiscard]] static std::unique_ptr<ProductionPluginBootstrap>
  open(ProductionPluginBootstrapError &error) noexcept;

  [[nodiscard]] std::unique_ptr<ProductionPluginRuntimeRoot>
  open_runtime(std::string_view record_name,
               const permissions::PluginId &plugin,
               ProductionPluginRuntimeHooks &hooks) const noexcept;

  [[nodiscard]] const definitions::TrustedDefinitionRegistry &
  definitions() const noexcept {
    return *definitions_;
  }
  [[nodiscard]] const ProductionRuntimeServices &services() const noexcept {
    return *services_;
  }

private:
  ProductionPluginBootstrap(
      std::unique_ptr<ProductionPluginRoots> roots,
      std::shared_ptr<const definitions::TrustedDefinitionRegistry> definitions,
      std::shared_ptr<const ProductionRuntimeServices> services) noexcept;
  [[nodiscard]] static std::unique_ptr<ProductionPluginBootstrap>
  compose_from_filesystem_root(
      std::unique_ptr<ProductionPluginRoots> roots, int filesystem_root_fd,
      std::uint32_t definition_uid,
      ProductionPluginBootstrapError &error);
  [[nodiscard]] std::optional<ProductionPluginRuntimeConfiguration>
  configuration(std::string_view record_name,
                const permissions::PluginId &plugin,
                ProductionPluginRuntimeHooks *hooks) const;

#ifdef OMARCHY_PRODUCTION_PLUGIN_BOOTSTRAP_TESTING
  [[nodiscard]] static std::unique_ptr<ProductionPluginBootstrap>
  open_from_test_filesystem_root(
      std::unique_ptr<ProductionPluginRoots> roots, int filesystem_root_fd,
      std::uint32_t definition_uid,
      ProductionPluginBootstrapError &error) noexcept;
  [[nodiscard]] static bool adapter_available_for_test(
      std::string_view adapter_class, const definitions::Digest &digest,
      std::uint32_t abi_version) noexcept;
  friend class ProductionPluginBootstrapTestAccess;
#endif

  std::unique_ptr<ProductionPluginRoots> roots_;
  std::shared_ptr<const definitions::TrustedDefinitionRegistry> definitions_;
  std::shared_ptr<const ProductionRuntimeServices> services_;
  const ProductionRuntimeLimits runtime_limits_{};
  const session::SessionLimits session_limits_{};
};

#ifdef OMARCHY_PRODUCTION_PLUGIN_BOOTSTRAP_TESTING
class ProductionPluginBootstrapTestAccess final {
public:
  [[nodiscard]] static std::unique_ptr<ProductionPluginBootstrap>
  open_from_filesystem_root(
      std::unique_ptr<ProductionPluginRoots> roots, int filesystem_root_fd,
      std::uint32_t definition_uid,
      ProductionPluginBootstrapError &error) noexcept {
    return ProductionPluginBootstrap::open_from_test_filesystem_root(
        std::move(roots), filesystem_root_fd, definition_uid, error);
  }
  [[nodiscard]] static bool
  adapter_available(std::string_view adapter_class,
                    const definitions::Digest &digest,
                    std::uint32_t abi_version) noexcept {
    return ProductionPluginBootstrap::adapter_available_for_test(
        adapter_class, digest, abi_version);
  }
  [[nodiscard]] static std::optional<ProductionPluginRuntimeConfiguration>
  configuration(const ProductionPluginBootstrap &bootstrap,
                std::string_view record_name,
                const permissions::PluginId &plugin,
                ProductionPluginRuntimeHooks *hooks) {
    return bootstrap.configuration(record_name, plugin, hooks);
  }
};
#endif

} // namespace omarchy::plugin_runtime::channel
