#pragma once

#include "activation_catalog.hpp"
#include "runtime_roots.hpp"
#include "plugin_runtime_root.hpp"
#include "revision_ingress.hpp"

#include <cstdint>
#include <memory>
#include <string_view>
#include <utility>

namespace omarchy::plugin_runtime::bridge::detail {
class PluginRuntimeController;
}

namespace omarchy::plugin_runtime::channel {

enum class RuntimeBootstrapError : std::uint8_t {
  none,
  roots_unavailable,
  package_definitions_unavailable,
  package_definitions_untrusted,
  admin_definitions_untrusted,
  definition_document_rejected,
  definition_registry_rejected,
  definition_bound_exceeded,
  provider_profiles_untrusted,
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
      const std::shared_ptr<PluginPermissionAuthority> &permissions,
      std::optional<std::string> settings = std::nullopt) const
      noexcept;
  [[nodiscard]] std::shared_ptr<PluginPermissionAuthority>
  open_permissions(std::string_view record_name,
                   const permissions::PluginId &plugin) const noexcept;
  [[nodiscard]] std::unique_ptr<ActivationCatalog>
  scan_catalog(ActivationCatalogError &error) const noexcept;
  [[nodiscard]] omarchy::plugins::discovery::PublishedRevision
  stage_revision_for_review(int archive_fd) const;
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
  authority_directory_accepted_for_test(std::uint32_t owner_uid,
                                        std::uint32_t mode,
      std::uint32_t trusted_uid) noexcept;
  friend class RuntimeBootstrapTestAccess;
#endif
  friend class omarchy::plugin_runtime::bridge::detail::PluginRuntimeController;

  std::unique_ptr<RuntimeRoots> roots_;
  std::shared_ptr<const definitions::TrustedDefinitionRegistry> definitions_;
  std::shared_ptr<const RuntimeServices> services_;
  const Limits runtime_limits_{};
  const session::SessionLimits session_limits_{
      provider_backed_session_limits()};
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
  [[nodiscard]] static std::optional<definitions::ResolvedDefinition>
  definition(const RuntimeBootstrap &bootstrap, std::string_view name) {
    return bootstrap.definitions_->find(name);
  }
  [[nodiscard]] static bool
  authority_directory_accepted(std::uint32_t owner_uid, std::uint32_t mode,
      std::uint32_t trusted_uid) noexcept {
    return RuntimeBootstrap::authority_directory_accepted_for_test(
        owner_uid, mode, trusted_uid);
  }
  [[nodiscard]] static PluginRuntimePreparationResult
  prepare_runtime(const RuntimeBootstrap &bootstrap,
                  const std::shared_ptr<PluginPermissionAuthority> &permissions,
                  std::optional<std::string> settings = std::nullopt)
      noexcept {
    return bootstrap.prepare_runtime(permissions, std::move(settings));
  }
  [[nodiscard]] static std::optional<
      plugin::wire::permission_snapshot::PermissionSnapshot>
  project_permissions(const RuntimeBootstrap &bootstrap,
                      const plugins::manifest::ManifestV2 &manifest,
                      const session::policy::GrantSnapshot &grants) {
    SessionRuntimeFactory factory(bootstrap.definitions_, bootstrap.services_);
    return factory.project_permissions(manifest, grants);
  }
  [[nodiscard]] static std::unique_ptr<AuthenticatedSessionRuntime>
  create_session_runtime(
      const RuntimeBootstrap &bootstrap,
      const plugins::manifest::ManifestV2 &manifest,
      const session::policy::GrantSnapshot &grants, int revision_directory_fd,
      int private_state_directory_fd, std::uint64_t session_nonce,
      std::shared_ptr<session::LiveGenerationState> live_generation,
      std::shared_ptr<runtime::GestureEligibilityLatch> gesture_eligibility) {
    SessionRuntimeFactory factory(bootstrap.definitions_, bootstrap.services_);
    return factory.create(manifest, grants, revision_directory_fd,
                          private_state_directory_fd, session_nonce,
                          std::move(live_generation),
                          std::move(gesture_eligibility));
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
#ifdef OMARCHY_PLUGIN_SESSION_TESTING
           bootstrap.services_->compare_scope == nullptr &&
           bootstrap.services_->dynamic_services.empty() &&
#endif
           bootstrap.services_->provider_catalog;
  }
  static void set_services(RuntimeBootstrap &bootstrap,
                           RuntimeServices services) {
    bootstrap.services_ =
        std::make_shared<const RuntimeServices>(std::move(services));
  }
};
#endif

} // namespace omarchy::plugin_runtime::channel
