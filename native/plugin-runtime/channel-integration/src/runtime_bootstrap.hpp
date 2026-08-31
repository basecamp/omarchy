#pragma once

#include "activation_catalog.hpp"
#include "runtime_roots.hpp"
#include "plugin_runtime_root.hpp"

#include <cstdint>
#include <memory>
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

private:
  [[nodiscard]] static std::unique_ptr<RuntimeBootstrap>
  open(RuntimeBootstrapError &error) noexcept;
  [[nodiscard]] PluginRuntimePreparationResult
  prepare_runtime(
      const std::shared_ptr<PluginPermissionAuthority> &permissions) const
      noexcept;
  [[nodiscard]] std::shared_ptr<PluginPermissionAuthority>
  open_permissions(std::string_view record_name,
                   const permissions::PluginId &plugin) const noexcept;
  [[nodiscard]] std::unique_ptr<ActivationCatalog>
  scan_catalog(ActivationCatalogError &error) const noexcept;
  RuntimeBootstrap(
      std::unique_ptr<RuntimeRoots> roots,
      std::shared_ptr<const definitions::TrustedDefinitionRegistry> definitions,
      std::shared_ptr<const RuntimeServices> services) noexcept;
  [[nodiscard]] static std::unique_ptr<RuntimeBootstrap>
  compose_from_filesystem_root(std::unique_ptr<RuntimeRoots> roots,
                               int filesystem_root_fd,
      std::uint32_t definition_uid,
      RuntimeBootstrapError &error);
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
  friend class omarchy::plugin_runtime::bridge::PluginManager;

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
  compose_with_context(
      std::unique_ptr<RuntimeRoots> roots,
      std::shared_ptr<const definitions::TrustedDefinitionRegistry> definitions,
      std::shared_ptr<const RuntimeServices> services) {
    if (!roots || !definitions || !services)
      return {};
    return std::unique_ptr<RuntimeBootstrap>(new RuntimeBootstrap(
        std::move(roots), std::move(definitions), std::move(services)));
  }
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
  [[nodiscard]] static PluginRuntimePreparationResult
  prepare_runtime(const RuntimeBootstrap &bootstrap,
                  const std::shared_ptr<PluginPermissionAuthority> &permissions)
      noexcept {
    return bootstrap.prepare_runtime(permissions);
  }
  [[nodiscard]] static std::shared_ptr<PluginPermissionAuthority>
  open_permissions(const RuntimeBootstrap &bootstrap,
                   std::string_view record_name,
                   const permissions::PluginId &plugin) noexcept {
    return bootstrap.open_permissions(record_name, plugin);
  }
  [[nodiscard]] static std::unique_ptr<ActivationCatalog>
  scan_catalog(const RuntimeBootstrap &bootstrap,
               ActivationCatalogError &error) noexcept {
    return bootstrap.scan_catalog(error);
  }
  [[nodiscard]] static bool
  has_fixed_service_context(const RuntimeBootstrap &bootstrap) noexcept {
    return bootstrap.definitions_ && bootstrap.definitions_->size() == 0 &&
           bootstrap.services_ &&
           bootstrap.services_->context &&
           bootstrap.services_->notification_send != nullptr &&
           bootstrap.services_->audio_play == nullptr &&
           bootstrap.services_->compare_scope == nullptr &&
           bootstrap.services_->dynamic_services.empty();
  }
  static void set_services(RuntimeBootstrap &bootstrap,
                           RuntimeServices services) {
    bootstrap.services_ =
        std::make_shared<const RuntimeServices>(std::move(services));
  }
};
#endif

} // namespace omarchy::plugin_runtime::channel
