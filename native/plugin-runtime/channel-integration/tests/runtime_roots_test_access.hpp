#pragma once

#include "runtime_roots.hpp"

namespace omarchy::plugin_runtime::channel {
class RuntimeRootsTestAccess final {
public:
  using AccountLookup = RuntimeRoots::AccountLookupForTest;
  [[nodiscard]] static std::unique_ptr<RuntimeRoots>
  open_from_home_fd(int home_fd, std::uint32_t trusted_uid,
                    RuntimeRootsError &error) noexcept {
    return RuntimeRoots::open_from_home_fd(home_fd, trusted_uid, error);
  }
  [[nodiscard]] static std::unique_ptr<RuntimeRoots>
  provision_from_home_fd(int home_fd, std::uint32_t trusted_uid,
                         RuntimeRootsError &error) noexcept {
    return RuntimeRoots::provision_from_home_fd(home_fd, trusted_uid, error);
  }
  [[nodiscard]] static int
  open_absolute_home(const char *path, std::uint32_t trusted_uid,
                     RuntimeRootsError &error) noexcept {
    return RuntimeRoots::open_absolute_home_for_test(path, trusted_uid, error);
  }
  [[nodiscard]] static int
  resolve_account_home(std::uint32_t trusted_uid,
                       std::size_t initial_buffer_size, AccountLookup lookup,
                       RuntimeRootsError &error) noexcept {
    return RuntimeRoots::resolve_account_home_for_test(
        trusted_uid, initial_buffer_size, lookup, error);
  }
  [[nodiscard]] static bool
  absolute_ancestor_is_secure(std::uint32_t owner_uid, std::uint32_t mode,
                              std::uint32_t trusted_uid) noexcept {
    return RuntimeRoots::absolute_ancestor_is_secure_for_test(owner_uid, mode,
                                                              trusted_uid);
  }
};
} // namespace omarchy::plugin_runtime::channel
