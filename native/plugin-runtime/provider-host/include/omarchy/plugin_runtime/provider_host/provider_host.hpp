#pragma once

#include "dynamic_activation.hpp"
#include "omarchy/plugin_runtime/launcher/launcher.h"

#include <chrono>
#include <cstddef>
#include <cstdint>
#include <memory>
#include <span>
#include <string>
#include <string_view>
#include <vector>

namespace omarchy::plugin_runtime::provider_host {

namespace definitions = omarchy::plugins::definitions;
namespace permissions = omarchy::plugins::permissions;
namespace launcher = omarchy::plugin_runtime::launcher;

constexpr std::size_t kMaximumProviderPayload = 64 * 1024;
constexpr std::chrono::milliseconds kProviderInvocationTimeout{750};
constexpr std::chrono::milliseconds kMaximumProviderInvocationTimeout{30000};

enum class CatalogError : std::uint8_t {
  none,
  root_rejected,
  profile_rejected,
  executable_rejected,
  duplicate_binding,
  resource_exhausted,
};

class ProviderCatalog final {
public:
  struct Profile;
  ProviderCatalog(const ProviderCatalog &) = delete;
  ProviderCatalog &operator=(const ProviderCatalog &) = delete;
  ~ProviderCatalog();

  [[nodiscard]] static std::shared_ptr<const ProviderCatalog>
  load(int filesystem_root_fd,
       std::span<const std::string_view> package_components,
       std::span<const std::string_view> admin_components,
       std::uint32_t trusted_uid, CatalogError &error) noexcept;

  [[nodiscard]] bool
  available(const definitions::AdapterBinding &binding) const noexcept;
  [[nodiscard]] std::size_t size() const noexcept;

private:
  explicit ProviderCatalog(std::vector<Profile> profiles);
  [[nodiscard]] const Profile *
  find(const definitions::AdapterBinding &binding) const noexcept;

  std::vector<Profile> profiles_;
  friend class ProviderActivation;
};

class ProviderRoute;

// One activation owns its provider processes. Construction starts nothing;
// route() validates a pinned trusted profile, and the first authorized invoke
// lazily starts the corresponding process group.
class ProviderActivation final
    : public std::enable_shared_from_this<ProviderActivation> {
public:
  ProviderActivation(const ProviderActivation &) = delete;
  ProviderActivation &operator=(const ProviderActivation &) = delete;
  ~ProviderActivation();

  [[nodiscard]] static std::shared_ptr<ProviderActivation>
  create(std::shared_ptr<const ProviderCatalog> catalog,
         permissions::ActivationBinding binding,
         std::chrono::milliseconds timeout = kProviderInvocationTimeout);
  // Trusted composition seam for tests and alternate host resource managers.
  // Plugin data never receives or selects this controller.
  [[nodiscard]] static std::shared_ptr<ProviderActivation>
  create(std::shared_ptr<const ProviderCatalog> catalog,
         permissions::ActivationBinding binding,
         std::shared_ptr<launcher::ResourceScopeController> resource_scope,
         std::chrono::milliseconds timeout = kProviderInvocationTimeout);
  [[nodiscard]] std::shared_ptr<ProviderRoute>
  route(const definitions::AdapterBinding &binding);
  // Permanently closes invocation authority. False means exact process/scope
  // cleanup remains retained and a later cancel() must retry it.
  bool cancel() noexcept;
  [[nodiscard]] bool cleanup_pending() const noexcept;

private:
  struct Impl;
  struct CleanupService;
  [[nodiscard]] static CleanupService *cleanup_service(bool create) noexcept;
  static void retain_cleanup(std::unique_ptr<Impl> implementation) noexcept;
  ProviderActivation(std::shared_ptr<const ProviderCatalog> catalog,
                     permissions::ActivationBinding binding,
                     std::shared_ptr<launcher::ResourceScopeController>
                         resource_scope,
                     std::chrono::milliseconds timeout);
  [[nodiscard]] bool invoke(const definitions::AdapterBinding &binding,
                            const definitions::AuthorizedDynamicRequest &request,
                            std::span<std::byte> response,
                            std::size_t &written) noexcept;
  std::unique_ptr<Impl> implementation_;
  friend class ProviderRoute;
};

class ProviderRoute final {
public:
  [[nodiscard]] const definitions::AdapterBinding &binding() const noexcept;
  [[nodiscard]] static bool dispatch(
      const definitions::AuthorizedDynamicRequest &request,
      std::span<std::byte> response, std::size_t &written,
      void *context) noexcept;

private:
  ProviderRoute(std::shared_ptr<ProviderActivation> activation,
                definitions::AdapterBinding binding);
  std::shared_ptr<ProviderActivation> activation_;
  definitions::AdapterBinding binding_;
  friend class ProviderActivation;
};

} // namespace omarchy::plugin_runtime::provider_host
