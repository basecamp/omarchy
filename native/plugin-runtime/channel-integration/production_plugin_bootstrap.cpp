#include "production_plugin_bootstrap.hpp"

#include "capability_definition_loader.hpp"
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
    if ((!alphanumeric && !separator) ||
        (separator && previous_separator))
      return false;
    previous_separator = separator;
  }
  return !previous_separator && value.front() >= 'a' && value.front() <= 'z';
}

OwnedDescriptor open_plugin_authority(int container_fd,
                                      std::string_view plugin,
                                      std::uint32_t uid) {
  // Installation owns creation. Runtime composition only opens the exact
  // pre-provisioned child and never repairs or widens its filesystem policy.
  struct stat metadata{};
  if (container_fd < 0 || !exact_plugin_id(plugin) ||
      ::fstat(container_fd, &metadata) < 0 ||
      !exact_private_directory(metadata, uid))
    return {};
  const std::string name(plugin);
  OwnedDescriptor child(::openat(container_fd, name.c_str(),
                                 O_RDONLY | O_DIRECTORY | O_CLOEXEC |
                                     O_NOFOLLOW));
  if (!child || ::fstat(child.get(), &metadata) < 0 ||
      !exact_private_directory(metadata, uid))
    return {};
  return child;
}

FixedDirectoryResult open_fixed_directory(
    int filesystem_root_fd, std::span<const std::string_view> components,
    std::uint32_t uid, OwnedDescriptor &output) {
  OwnedDescriptor current(::openat(filesystem_root_fd, ".",
                                   O_RDONLY | O_DIRECTORY | O_CLOEXEC |
                                       O_NOFOLLOW));
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
    OwnedDescriptor next(::openat(current.get(), name.c_str(),
                                  O_RDONLY | O_DIRECTORY | O_CLOEXEC |
                                      O_NOFOLLOW));
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

// No dynamic native adapter is safe to expose yet. Extending this verifier is
// a compiled host change paired with a fixed service implementation; it never
// dlopens a path named by a definition.
bool compiled_adapter_available(std::string_view, const definitions::Digest &,
                                std::uint32_t, void *) noexcept {
  return false;
}

ProductionPluginBootstrapError
definition_error(definitions::LoadResult result) noexcept {
  switch (result) {
  case definitions::LoadResult::loaded:
    return ProductionPluginBootstrapError::none;
  case definitions::LoadResult::adapter_unavailable:
    return ProductionPluginBootstrapError::definition_adapter_unavailable;
  case definitions::LoadResult::registry_rejected:
    return ProductionPluginBootstrapError::definition_registry_rejected;
  case definitions::LoadResult::bound_exceeded:
    return ProductionPluginBootstrapError::definition_bound_exceeded;
  case definitions::LoadResult::invalid_document:
  case definitions::LoadResult::untrusted_path:
    return ProductionPluginBootstrapError::definition_document_rejected;
  }
  return ProductionPluginBootstrapError::internal_failure;
}

} // namespace

std::unique_ptr<ProductionPluginBootstrap>
ProductionPluginBootstrap::compose_from_filesystem_root(
    std::unique_ptr<ProductionPluginRoots> roots, int filesystem_root_fd,
    std::uint32_t definition_uid, ProductionPluginBootstrapError &error) {
  const std::string_view version = build_version();
  const std::array<std::string_view, 6> package_components{
      "usr", "lib", "omarchy", "plugin-security", version,
      "capabilities.d"};
  const std::array<std::string_view, 3> admin_components{
      "etc", "omarchy", "plugin-capabilities.d"};
  OwnedDescriptor package;
  const auto package_result = open_fixed_directory(
      filesystem_root_fd, package_components, definition_uid, package);
  if (package_result != FixedDirectoryResult::opened) {
    error = package_result == FixedDirectoryResult::absent
                ? ProductionPluginBootstrapError::package_definitions_unavailable
                : ProductionPluginBootstrapError::package_definitions_untrusted;
    return {};
  }
  OwnedDescriptor admin;
  const auto admin_result = open_fixed_directory(
      filesystem_root_fd, admin_components, definition_uid, admin);
  if (admin_result == FixedDirectoryResult::rejected) {
    error = ProductionPluginBootstrapError::admin_definitions_untrusted;
    return {};
  }

  definitions::TrustedDefinitionRegistry registry;
  const definitions::AdapterVerifier verifier{
      .available = compiled_adapter_available};
  std::size_t loaded = 0;
  auto load_result = definitions::load_definition_directory_fd(
      package.get(), definitions::DefinitionSource::omarchy_package,
      definition_uid, verifier, registry, loaded);
  if (load_result != definitions::LoadResult::loaded) {
    error = load_result == definitions::LoadResult::untrusted_path
                ? ProductionPluginBootstrapError::package_definitions_untrusted
                : definition_error(load_result);
    return {};
  }
  if (admin_result == FixedDirectoryResult::opened) {
    load_result = definitions::load_definition_directory_fd(
        admin.get(), definitions::DefinitionSource::local_admin,
        definition_uid, verifier, registry, loaded);
    if (load_result != definitions::LoadResult::loaded) {
      error = load_result == definitions::LoadResult::untrusted_path
                  ? ProductionPluginBootstrapError::admin_definitions_untrusted
                  : definition_error(load_result);
      return {};
    }
  }

  auto definitions =
      std::make_shared<const definitions::TrustedDefinitionRegistry>(
          std::move(registry));
  auto services = std::make_shared<const ProductionRuntimeServices>();
  error = ProductionPluginBootstrapError::none;
  return std::unique_ptr<ProductionPluginBootstrap>(
      new ProductionPluginBootstrap(std::move(roots), std::move(definitions),
                                    std::move(services)));
}

ProductionPluginBootstrap::ProductionPluginBootstrap(
    std::unique_ptr<ProductionPluginRoots> roots,
    std::shared_ptr<const definitions::TrustedDefinitionRegistry> definitions,
    std::shared_ptr<const ProductionRuntimeServices> services) noexcept
    : roots_(std::move(roots)), definitions_(std::move(definitions)),
      services_(std::move(services)) {}

std::unique_ptr<ProductionPluginBootstrap>
ProductionPluginBootstrap::open(ProductionPluginBootstrapError &error) noexcept {
  error = ProductionPluginBootstrapError::none;
  try {
    ProductionPluginRootsError roots_error{};
    auto roots = ProductionPluginRoots::open(roots_error);
    if (!roots) {
      error = ProductionPluginBootstrapError::roots_unavailable;
      return {};
    }
    OwnedDescriptor filesystem_root(
        ::open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW));
    if (!filesystem_root) {
      error = ProductionPluginBootstrapError::package_definitions_unavailable;
      return {};
    }
    return compose_from_filesystem_root(std::move(roots), filesystem_root.get(),
                                        0, error);
  } catch (const std::bad_alloc &) {
    error = ProductionPluginBootstrapError::resource_exhausted;
    return {};
  } catch (...) {
    error = ProductionPluginBootstrapError::internal_failure;
    return {};
  }
}

std::optional<ProductionPluginRuntimeConfiguration>
ProductionPluginBootstrap::configuration(
    std::string_view record_name, const permissions::PluginId &plugin,
    ProductionPluginRuntimeHooks *hooks) const {
  if (record_name != plugin.view() || hooks == nullptr ||
      !exact_plugin_id(plugin.view()))
    return std::nullopt;
  auto authority = open_plugin_authority(
      roots_->authority_fd(), plugin.view(), roots_->trusted_uid());
  if (!authority)
    return std::nullopt;
  return ProductionPluginRuntimeConfiguration{
      .activation_root_fd = roots_->activations_fd(),
      .revision_root_fd = roots_->revisions_fd(),
      .state_root_fd = roots_->state_fd(),
      .authority_root = std::move(authority),
      .plugin = plugin,
      .trusted_uid = roots_->trusted_uid(),
      .activation_record = std::string(record_name),
      .definitions = definitions_,
      .services = services_,
      .runtime_limits = runtime_limits_,
      .session_limits = session_limits_,
      .hooks = hooks,
  };
}

std::unique_ptr<ProductionPluginRuntimeRoot>
ProductionPluginBootstrap::open_runtime(
    std::string_view record_name, const permissions::PluginId &plugin,
    ProductionPluginRuntimeHooks &hooks) const noexcept {
  try {
    auto candidate = configuration(record_name, plugin, &hooks);
    return candidate ? ProductionPluginRuntimeRoot::open(std::move(*candidate))
                     : nullptr;
  } catch (...) {
    return {};
  }
}

#ifdef OMARCHY_PRODUCTION_PLUGIN_BOOTSTRAP_TESTING
std::unique_ptr<ProductionPluginBootstrap>
ProductionPluginBootstrap::open_from_test_filesystem_root(
    std::unique_ptr<ProductionPluginRoots> roots, int filesystem_root_fd,
    std::uint32_t definition_uid,
    ProductionPluginBootstrapError &error) noexcept {
  error = ProductionPluginBootstrapError::none;
  try {
    if (!roots) {
      error = ProductionPluginBootstrapError::roots_unavailable;
      return {};
    }
    return compose_from_filesystem_root(std::move(roots), filesystem_root_fd,
                                        definition_uid, error);
  } catch (const std::bad_alloc &) {
    error = ProductionPluginBootstrapError::resource_exhausted;
    return {};
  } catch (...) {
    error = ProductionPluginBootstrapError::internal_failure;
    return {};
  }
}

bool ProductionPluginBootstrap::adapter_available_for_test(
    std::string_view adapter_class, const definitions::Digest &digest,
    std::uint32_t abi_version) noexcept {
  return compiled_adapter_available(adapter_class, digest, abi_version,
                                    nullptr);
}

bool ProductionPluginBootstrap::authority_directory_accepted_for_test(
    std::uint32_t owner_uid, std::uint32_t mode,
    std::uint32_t trusted_uid) noexcept {
  struct stat metadata{};
  metadata.st_uid = static_cast<uid_t>(owner_uid);
  metadata.st_mode = static_cast<mode_t>(mode);
  return exact_private_directory(metadata, trusted_uid);
}
#endif

} // namespace omarchy::plugin_runtime::channel
