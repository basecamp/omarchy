#pragma once

#include "activation_snapshot.hpp"

#include <cstdint>
#include <memory>

#ifdef OMARCHY_PRODUCTION_PLUGIN_ROOTS_TESTING
#include <cstddef>
#include <sys/types.h>
struct passwd;
#endif

namespace omarchy::plugin_runtime::channel {

enum class ProductionPluginRootsError : std::uint8_t {
  none,
  account_unavailable,
  home_untrusted,
  path_unavailable,
  root_untrusted,
  aliased_roots,
  resource_exhausted,
  internal_failure,
};

// The only production bootstrap for v2 filesystem authority. Paths come from
// the effective user's passwd entry plus fixed host constants; environment,
// QML, and plugin data cannot select or replace them.
class ProductionPluginRoots final {
public:
  ProductionPluginRoots(ProductionPluginRoots &&) noexcept = default;
  ProductionPluginRoots &operator=(ProductionPluginRoots &&) noexcept = default;
  ProductionPluginRoots(const ProductionPluginRoots &) = delete;
  ProductionPluginRoots &operator=(const ProductionPluginRoots &) = delete;

  [[nodiscard]] static std::unique_ptr<ProductionPluginRoots>
  open(ProductionPluginRootsError &error) noexcept;

  [[nodiscard]] std::uint32_t trusted_uid() const noexcept {
    return trusted_uid_;
  }
  [[nodiscard]] int revisions_fd() const noexcept { return revisions_.get(); }
  [[nodiscard]] int activations_fd() const noexcept {
    return activations_.get();
  }
  [[nodiscard]] int authority_fd() const noexcept { return authority_.get(); }
  [[nodiscard]] int state_fd() const noexcept { return state_.get(); }

private:
  ProductionPluginRoots(std::uint32_t trusted_uid,
                        host_session::OwnedDescriptor revisions,
                        host_session::OwnedDescriptor activations,
                        host_session::OwnedDescriptor authority,
                        host_session::OwnedDescriptor state) noexcept;
  [[nodiscard]] static std::unique_ptr<ProductionPluginRoots>
  open_from_home_fd_impl(int home_fd, std::uint32_t trusted_uid,
                         ProductionPluginRootsError &error);

#ifdef OMARCHY_PRODUCTION_PLUGIN_ROOTS_TESTING
  using AccountLookupForTest = int (*)(uid_t, struct passwd *, char *,
                                       std::size_t, struct passwd **);
  [[nodiscard]] static std::unique_ptr<ProductionPluginRoots>
  open_from_home_fd(int home_fd, std::uint32_t trusted_uid,
                    ProductionPluginRootsError &error) noexcept;
  [[nodiscard]] static int
  open_absolute_home_for_test(const char *path, std::uint32_t trusted_uid,
                              ProductionPluginRootsError &error) noexcept;
  [[nodiscard]] static int resolve_account_home_for_test(
      std::uint32_t trusted_uid, std::size_t initial_buffer_size,
      AccountLookupForTest lookup,
      ProductionPluginRootsError &error) noexcept;
  [[nodiscard]] static bool absolute_ancestor_is_secure_for_test(
      std::uint32_t owner_uid, std::uint32_t mode,
      std::uint32_t trusted_uid) noexcept;
  friend class ProductionPluginRootsTestAccess;
#endif

  std::uint32_t trusted_uid_ = 0;
  host_session::OwnedDescriptor revisions_;
  host_session::OwnedDescriptor activations_;
  host_session::OwnedDescriptor authority_;
  host_session::OwnedDescriptor state_;
};

#ifdef OMARCHY_PRODUCTION_PLUGIN_ROOTS_TESTING
class ProductionPluginRootsTestAccess final {
public:
  using AccountLookup = ProductionPluginRoots::AccountLookupForTest;
  [[nodiscard]] static std::unique_ptr<ProductionPluginRoots>
  open_from_home_fd(int home_fd, std::uint32_t trusted_uid,
                    ProductionPluginRootsError &error) noexcept {
    return ProductionPluginRoots::open_from_home_fd(home_fd, trusted_uid,
                                                    error);
  }
  [[nodiscard]] static int
  open_absolute_home(const char *path, std::uint32_t trusted_uid,
                     ProductionPluginRootsError &error) noexcept {
    return ProductionPluginRoots::open_absolute_home_for_test(
        path, trusted_uid, error);
  }
  [[nodiscard]] static int
  resolve_account_home(std::uint32_t trusted_uid,
                       std::size_t initial_buffer_size, AccountLookup lookup,
                       ProductionPluginRootsError &error) noexcept {
    return ProductionPluginRoots::resolve_account_home_for_test(
        trusted_uid, initial_buffer_size, lookup, error);
  }
  [[nodiscard]] static bool
  absolute_ancestor_is_secure(std::uint32_t owner_uid, std::uint32_t mode,
                              std::uint32_t trusted_uid) noexcept {
    return ProductionPluginRoots::absolute_ancestor_is_secure_for_test(
        owner_uid, mode, trusted_uid);
  }
};
#endif

} // namespace omarchy::plugin_runtime::channel
