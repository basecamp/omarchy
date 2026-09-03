#include "runtime_bootstrap.hpp"

#include "capability_definition_loader.hpp"
#include "desktop_notification_service.hpp"
#include "omarchy/plugin_runtime/Version.h"

#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

#include <array>
#include <cerrno>
#include <new>
#include <span>
#include <string>
#include <string_view>
#include <utility>

namespace omarchy::plugin_runtime::channel {

omarchy::plugins::discovery::PublishedRevision
RuntimeBootstrap::stage_revision_for_review(int archive_fd) const {
  return roots_->stage_revision_for_review(archive_fd);
}
namespace {

using host_session::OwnedDescriptor;

enum class FixedDirectoryResult { opened, absent, rejected };

bool secure_root_directory(const struct stat &metadata,
                           std::uint32_t uid) noexcept {
  return S_ISDIR(metadata.st_mode) && metadata.st_uid == uid &&
         (metadata.st_mode & 0022) == 0;
}

bool exact_definition_root(const struct stat &metadata,
                           std::uint32_t uid) noexcept {
  return S_ISDIR(metadata.st_mode) && metadata.st_uid == uid &&
         (metadata.st_mode & 07777) == 0755;
}

bool exact_private_directory(const struct stat &metadata,
                             std::uint32_t uid) noexcept {
  return S_ISDIR(metadata.st_mode) && metadata.st_uid == uid &&
         (metadata.st_mode & 07777) == 0700;
}

bool exact_plugin_id(std::string_view value) noexcept {
  if (value.empty() || value.size() > 128)
    return false;
  bool previous_separator = true;
  for (const unsigned char character : value) {
    const bool alphanumeric = (character >= 'a' && character <= 'z') ||
                              (character >= '0' && character <= '9');
    const bool separator =
        character == '.' || character == '-' || character == '_';
    if ((!alphanumeric && !separator) || (separator && previous_separator))
      return false;
    previous_separator = separator;
  }
  return !previous_separator && value.front() >= 'a' && value.front() <= 'z';
}

OwnedDescriptor open_plugin_authority(int container_fd, std::string_view plugin,
                                      std::uint32_t uid) {
  // Installation owns creation. Runtime composition only opens the exact
  // pre-provisioned child and never repairs or widens its filesystem policy.
  struct stat metadata{};
  if (container_fd < 0 || !exact_plugin_id(plugin) ||
      ::fstat(container_fd, &metadata) < 0 ||
      !exact_private_directory(metadata, uid))
    return {};
  const std::string name(plugin);
  OwnedDescriptor child(
      ::openat(container_fd, name.c_str(),
               O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW));
  if (!child || ::fstat(child.get(), &metadata) < 0 ||
      !exact_private_directory(metadata, uid))
    return {};
  return child;
}

FixedDirectoryResult
open_fixed_directory(int filesystem_root_fd,
                     std::span<const std::string_view> components,
    std::uint32_t uid, OwnedDescriptor &output) {
  OwnedDescriptor current(
      ::openat(filesystem_root_fd, ".",
               O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW));
  struct stat metadata{};
  if (!current || ::fstat(current.get(), &metadata) < 0 ||
      !secure_root_directory(metadata, uid))
    return FixedDirectoryResult::rejected;
  for (std::size_t index = 0; index < components.size(); ++index) {
    const auto component = components[index];
    if (component.empty() || component == "." || component == ".." ||
        component.find('/') != std::string_view::npos)
      return FixedDirectoryResult::rejected;
    const std::string name(component);
    OwnedDescriptor next(
        ::openat(current.get(), name.c_str(),
                 O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW));
    if (!next) {
      if (errno == ENOENT)
        return FixedDirectoryResult::absent;
      return FixedDirectoryResult::rejected;
    }
    if (::fstat(next.get(), &metadata) < 0)
      return FixedDirectoryResult::rejected;
    const bool leaf = index + 1 == components.size();
    if ((leaf && !exact_definition_root(metadata, uid)) ||
        (!leaf && !secure_root_directory(metadata, uid)))
      return FixedDirectoryResult::rejected;
    current = std::move(next);
  }
  output = std::move(current);
  return FixedDirectoryResult::opened;
}

RuntimeBootstrapError
definition_error(definitions::LoadResult result) noexcept {
  switch (result) {
  case definitions::LoadResult::loaded:
    return RuntimeBootstrapError::none;
  case definitions::LoadResult::registry_rejected:
    return RuntimeBootstrapError::definition_registry_rejected;
  case definitions::LoadResult::bound_exceeded:
    return RuntimeBootstrapError::definition_bound_exceeded;
  case definitions::LoadResult::invalid_document:
  case definitions::LoadResult::untrusted_path:
    return RuntimeBootstrapError::definition_document_rejected;
  }
  return RuntimeBootstrapError::internal_failure;
}

} // namespace

std::unique_ptr<RuntimeBootstrap>
RuntimeBootstrap::compose_from_filesystem_root(
    std::unique_ptr<RuntimeRoots> roots, int filesystem_root_fd,
    std::uint32_t definition_uid, RuntimeBootstrapError &error) {
  const std::string_view version = build_version();
  const std::array<std::string_view, 6> package_components{
      "usr", "lib", "omarchy", "plugin-security", version, "capabilities.d"};
  const std::array<std::string_view, 3> admin_components{
      "etc", "omarchy", "plugin-capabilities.d"};
  OwnedDescriptor package;
  const auto package_result = open_fixed_directory(
      filesystem_root_fd, package_components, definition_uid, package);
  if (package_result != FixedDirectoryResult::opened) {
    error =
        package_result == FixedDirectoryResult::absent
                ? RuntimeBootstrapError::package_definitions_unavailable
                : RuntimeBootstrapError::package_definitions_untrusted;
    return {};
  }
  OwnedDescriptor admin;
  const auto admin_result = open_fixed_directory(
      filesystem_root_fd, admin_components, definition_uid, admin);
  if (admin_result == FixedDirectoryResult::rejected) {
    error = RuntimeBootstrapError::admin_definitions_untrusted;
    return {};
  }

  definitions::TrustedDefinitionRegistry registry;
  std::size_t loaded = 0;
  auto load_result = definitions::load_definition_directory_fd(
      package.get(), definitions::DefinitionSource::omarchy_package,
      definition_uid, registry, loaded);
  if (load_result != definitions::LoadResult::loaded) {
    error = load_result == definitions::LoadResult::untrusted_path
                ? RuntimeBootstrapError::package_definitions_untrusted
                : definition_error(load_result);
    return {};
  }
  if (admin_result == FixedDirectoryResult::opened) {
    load_result = definitions::load_definition_directory_fd(
        admin.get(), definitions::DefinitionSource::local_admin, definition_uid,
        registry, loaded);
    if (load_result != definitions::LoadResult::loaded) {
      error = load_result == definitions::LoadResult::untrusted_path
                  ? RuntimeBootstrapError::admin_definitions_untrusted
                  : definition_error(load_result);
      return {};
    }
  }

  auto definitions =
      std::make_shared<const definitions::TrustedDefinitionRegistry>(
          std::move(registry));
  const std::array<std::string_view, 6> package_provider_components{
      "usr", "lib", "omarchy", "plugin-security", version, "providers.d"};
  const std::array<std::string_view, 3> admin_provider_components{
      "etc", "omarchy", "plugin-providers.d"};
  provider_host::CatalogError provider_error{};
  auto provider_catalog = provider_host::ProviderCatalog::load(
      filesystem_root_fd, package_provider_components,
      admin_provider_components, definition_uid, provider_error);
  if (!provider_catalog) {
    error = provider_error == provider_host::CatalogError::resource_exhausted
                ? RuntimeBootstrapError::resource_exhausted
                : RuntimeBootstrapError::provider_profiles_untrusted;
    return {};
  }
  auto services = make_runtime_services(std::move(provider_catalog));
  if (!services) {
    error = RuntimeBootstrapError::resource_exhausted;
    return {};
  }
  error = RuntimeBootstrapError::none;
  return std::unique_ptr<RuntimeBootstrap>(
      new RuntimeBootstrap(std::move(roots), std::move(definitions),
                                    std::move(services)));
}

RuntimeBootstrap::RuntimeBootstrap(
    std::unique_ptr<RuntimeRoots> roots,
    std::shared_ptr<const definitions::TrustedDefinitionRegistry> definitions,
    std::shared_ptr<const RuntimeServices> services) noexcept
    : roots_(std::move(roots)), definitions_(std::move(definitions)),
      services_(std::move(services)) {}

std::unique_ptr<RuntimeBootstrap> RuntimeBootstrap::open(
    RuntimeBootstrapError &error) noexcept {
  error = RuntimeBootstrapError::none;
  try {
    RuntimeRootsError roots_error{};
    auto roots = RuntimeRoots::open(roots_error);
    if (!roots) {
      error = RuntimeBootstrapError::roots_unavailable;
      return {};
    }
    OwnedDescriptor filesystem_root(
        ::open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW));
    if (!filesystem_root) {
      error = RuntimeBootstrapError::package_definitions_unavailable;
      return {};
    }
    return compose_from_filesystem_root(std::move(roots), filesystem_root.get(),
                                        0, error);
  } catch (const std::bad_alloc &) {
    error = RuntimeBootstrapError::resource_exhausted;
    return {};
  } catch (...) {
    error = RuntimeBootstrapError::internal_failure;
    return {};
  }
}

std::shared_ptr<PluginPermissionAuthority>
RuntimeBootstrap::open_permissions(
    std::string_view record_name,
    const permissions::PluginId &plugin) const noexcept {
  try {
    if (record_name != plugin.view() || !exact_plugin_id(plugin.view()))
      return {};
    auto authority = open_plugin_authority(
        roots_->authority_fd(), plugin.view(), roots_->trusted_uid());
    if (!authority)
      return {};
    return PluginPermissionAuthority::open(
        roots_->activations_fd(), roots_->revisions_fd(), roots_->state_fd(),
        std::move(authority), plugin, roots_->trusted_uid(), definitions_,
        services_, std::string(record_name));
  } catch (...) {
    return {};
  }
}

PluginRuntimePreparationResult
RuntimeBootstrap::prepare_runtime(
    const std::shared_ptr<PluginPermissionAuthority> &permissions,
    std::optional<std::string> settings) const
    noexcept {
  try {
    if (!permissions || permissions->definitions_ != definitions_ ||
        permissions->services_ != services_)
      return {};
    return PluginRuntimeRoot::prepare({
        .permissions = permissions,
        .settings = std::move(settings),
        .runtime_limits = runtime_limits_,
        .session_limits = session_limits_,
#ifdef OMARCHY_PLUGIN_SESSION_TESTING
        .test_supervisor_factory = {},
        .test_before_final_fence = nullptr,
        .test_before_final_fence_context = nullptr,
#endif
    });
  } catch (...) {
    return {};
  }
}

std::unique_ptr<ActivationCatalog>
RuntimeBootstrap::scan_catalog(
    ActivationCatalogError &error) const noexcept {
  return ActivationCatalog::load(roots_->activations_fd(),
                                       roots_->trusted_uid(), error);
}

#ifdef OMARCHY_RUNTIME_BOOTSTRAP_TESTING
std::unique_ptr<RuntimeBootstrap>
RuntimeBootstrap::open_from_test_filesystem_root(
    std::unique_ptr<RuntimeRoots> roots, int filesystem_root_fd,
    std::uint32_t definition_uid,
    RuntimeBootstrapError &error) noexcept {
  error = RuntimeBootstrapError::none;
  try {
    if (!roots) {
      error = RuntimeBootstrapError::roots_unavailable;
      return {};
    }
    return compose_from_filesystem_root(std::move(roots), filesystem_root_fd,
                                        definition_uid, error);
  } catch (const std::bad_alloc &) {
    error = RuntimeBootstrapError::resource_exhausted;
    return {};
  } catch (...) {
    error = RuntimeBootstrapError::internal_failure;
    return {};
  }
}

bool RuntimeBootstrap::authority_directory_accepted_for_test(
    std::uint32_t owner_uid, std::uint32_t mode,
    std::uint32_t trusted_uid) noexcept {
  struct stat metadata{};
  metadata.st_uid = static_cast<uid_t>(owner_uid);
  metadata.st_mode = static_cast<mode_t>(mode);
  return exact_private_directory(metadata, trusted_uid);
}
#endif

} // namespace omarchy::plugin_runtime::channel
