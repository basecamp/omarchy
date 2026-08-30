#pragma once

#include "activation_snapshot.hpp"

#include <cstdint>
#include <memory>

#ifdef OMARCHY_RUNTIME_ROOTS_TESTING
#include <cstddef>
#include <sys/types.h>
struct passwd;
#endif

namespace omarchy::plugin_runtime::channel {

#ifdef OMARCHY_RUNTIME_ROOTS_TESTING
class RuntimeRootsTestAccess;
#endif

enum class RuntimeRootsError : std::uint8_t {
  none,
  account_unavailable,
  home_untrusted,
  path_unavailable,
  root_untrusted,
  aliased_roots,
  resource_exhausted,
  internal_failure,
};

// The only runtime bootstrap for v2 filesystem authority. Paths come from
// the effective user's passwd entry plus fixed host constants; environment,
// QML, and plugin data cannot select or replace them.
class RuntimeRoots final {
public:
  RuntimeRoots(RuntimeRoots &&) noexcept = default;
  RuntimeRoots &operator=(RuntimeRoots &&) noexcept = default;
  RuntimeRoots(const RuntimeRoots &) = delete;
  RuntimeRoots &operator=(const RuntimeRoots &) = delete;

  [[nodiscard]] static std::unique_ptr<RuntimeRoots>
  open(RuntimeRootsError &error) noexcept;

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
  RuntimeRoots(std::uint32_t trusted_uid,
                        host_session::OwnedDescriptor revisions,
                        host_session::OwnedDescriptor activations,
                        host_session::OwnedDescriptor authority,
                        host_session::OwnedDescriptor state) noexcept;
  [[nodiscard]] static std::unique_ptr<RuntimeRoots>
  open_from_home_fd_impl(int home_fd, std::uint32_t trusted_uid,
                         RuntimeRootsError &error);

#ifdef OMARCHY_RUNTIME_ROOTS_TESTING
  using AccountLookupForTest = int (*)(uid_t, struct passwd *, char *,
                                       std::size_t, struct passwd **);
  [[nodiscard]] static std::unique_ptr<RuntimeRoots>
  open_from_home_fd(int home_fd, std::uint32_t trusted_uid,
                    RuntimeRootsError &error) noexcept;
  [[nodiscard]] static int
  open_absolute_home_for_test(const char *path, std::uint32_t trusted_uid,
                              RuntimeRootsError &error) noexcept;
  [[nodiscard]] static int resolve_account_home_for_test(
      std::uint32_t trusted_uid, std::size_t initial_buffer_size,
      AccountLookupForTest lookup,
      RuntimeRootsError &error) noexcept;
  [[nodiscard]] static bool absolute_ancestor_is_secure_for_test(
      std::uint32_t owner_uid, std::uint32_t mode,
      std::uint32_t trusted_uid) noexcept;
  friend class RuntimeRootsTestAccess;
#endif

  std::uint32_t trusted_uid_ = 0;
  host_session::OwnedDescriptor revisions_;
  host_session::OwnedDescriptor activations_;
  host_session::OwnedDescriptor authority_;
  host_session::OwnedDescriptor state_;
};

} // namespace omarchy::plugin_runtime::channel
