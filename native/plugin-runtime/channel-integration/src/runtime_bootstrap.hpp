#pragma once

#include "activation_catalog.hpp"
#include "runtime_roots.hpp"
#include "plugin_runtime_root.hpp"

#include <cstdint>
#include <memory>
#include <optional>
#include <string_view>
#include <utility>

namespace omarchy::plugin_runtime::channel {

enum class RuntimeBootstrapError : std::uint8_t {
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

// Immutable runtime composition shared by every v2 plugin runtime. All
// paths, adapters, providers and limits are compiled host policy. Activation
// candidates contribute only the exact record and plugin names already
// selected by the trusted activation catalog.
class RuntimeBootstrap final {
public:
  RuntimeBootstrap(const RuntimeBootstrap &) = delete;
  RuntimeBootstrap &
  operator=(const RuntimeBootstrap &) = delete;

  [[nodiscard]] static std::unique_ptr<RuntimeBootstrap>
  open(RuntimeBootstrapError &error) noexcept;

  [[nodiscard]] std::unique_ptr<PluginRuntimeRoot>
  open_runtime(std::string_view record_name,
               const permissions::PluginId &plugin,
               PluginRuntimeHooks &hooks) const noexcept;
  [[nodiscard]] std::unique_ptr<PreparedPluginRuntime>
  prepare_runtime(std::string_view record_name,
                  const permissions::PluginId &plugin) const noexcept;
  [[nodiscard]] std::unique_ptr<ActivationCatalog>
  scan_catalog(ActivationCatalogError &error) const noexcept;

  [[nodiscard]] const definitions::TrustedDefinitionRegistry &
  definitions() const noexcept {
    return *definitions_;
  }
  [[nodiscard]] const RuntimeServices &services() const noexcept {
    return *services_;
  }

private:
  RuntimeBootstrap(
      std::unique_ptr<RuntimeRoots> roots,
      std::shared_ptr<const definitions::TrustedDefinitionRegistry> definitions,
      std::shared_ptr<const RuntimeServices> services) noexcept;
  [[nodiscard]] static std::unique_ptr<RuntimeBootstrap>
  compose_from_filesystem_root(std::unique_ptr<RuntimeRoots> roots,
                               int filesystem_root_fd,
      std::uint32_t definition_uid,
      RuntimeBootstrapError &error);
  [[nodiscard]] std::optional<PluginRuntimeConfiguration>
  configuration(std::string_view record_name,
                const permissions::PluginId &plugin,
                PluginRuntimeHooks *hooks,
                bool preparation = false) const;

#ifdef OMARCHY_RUNTIME_BOOTSTRAP_TESTING
  [[nodiscard]] static std::unique_ptr<RuntimeBootstrap>
  open_from_test_filesystem_root(
      std::unique_ptr<RuntimeRoots> roots, int filesystem_root_fd,
      std::uint32_t definition_uid,
      RuntimeBootstrapError &error) noexcept;
  [[nodiscard]] static bool
  adapter_available_for_test(std::string_view adapter_class,
                             const definitions::Digest &digest,
      std::uint32_t abi_version) noexcept;
  [[nodiscard]] static bool
  authority_directory_accepted_for_test(std::uint32_t owner_uid,
                                        std::uint32_t mode,
      std::uint32_t trusted_uid) noexcept;
  friend class RuntimeBootstrapTestAccess;
#endif

  std::unique_ptr<RuntimeRoots> roots_;
  std::shared_ptr<const definitions::TrustedDefinitionRegistry> definitions_;
  std::shared_ptr<const RuntimeServices> services_;
  const Limits runtime_limits_{};
  const session::SessionLimits session_limits_{};
};

#ifdef OMARCHY_RUNTIME_BOOTSTRAP_TESTING
class RuntimeBootstrapTestAccess final {
public:
  [[nodiscard]] static std::unique_ptr<RuntimeBootstrap>
  open_from_filesystem_root(std::unique_ptr<RuntimeRoots> roots,
                            int filesystem_root_fd,
      std::uint32_t definition_uid,
      RuntimeBootstrapError &error) noexcept {
    return RuntimeBootstrap::open_from_test_filesystem_root(
        std::move(roots), filesystem_root_fd, definition_uid, error);
  }
  [[nodiscard]] static bool
  adapter_available(std::string_view adapter_class,
                    const definitions::Digest &digest,
                    std::uint32_t abi_version) noexcept {
    return RuntimeBootstrap::adapter_available_for_test(
        adapter_class, digest, abi_version);
  }
  [[nodiscard]] static bool
  authority_directory_accepted(std::uint32_t owner_uid, std::uint32_t mode,
      std::uint32_t trusted_uid) noexcept {
    return RuntimeBootstrap::authority_directory_accepted_for_test(
        owner_uid, mode, trusted_uid);
  }
  [[nodiscard]] static std::optional<PluginRuntimeConfiguration>
  configuration(const RuntimeBootstrap &bootstrap,
                std::string_view record_name,
                const permissions::PluginId &plugin,
                PluginRuntimeHooks *hooks) {
    return bootstrap.configuration(record_name, plugin, hooks);
  }
};
#endif

} // namespace omarchy::plugin_runtime::channel
