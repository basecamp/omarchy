#pragma once

#include "dynamic_activation.hpp"

#include <cstddef>
#include <cstdint>
#include <span>
#include <string_view>

namespace omarchy::plugin_runtime::providers {

namespace definitions = omarchy::plugins::definitions;
namespace permissions = omarchy::plugins::permissions;

inline constexpr std::size_t kMaximumGitHubResponseBytes = 32768;

struct GitHubBackend {
  bool (*invoke)(std::string_view operation, std::string_view argument,
                 std::span<std::byte> response, std::size_t &written,
                 void *context) noexcept = nullptr;
  void *context = nullptr;
};

struct GitHubProviderConfiguration {
  permissions::ActivationBinding binding;
  std::uint64_t read_epoch = 0;
  std::uint64_t write_epoch = 0;
  std::uint64_t open_epoch = 0;
  GitHubBackend backend;
};

class GitHubProvider {
public:
  explicit GitHubProvider(GitHubProviderConfiguration configuration);
  [[nodiscard]] definitions::DynamicAdapter read_adapter() noexcept;
  [[nodiscard]] definitions::DynamicAdapter write_adapter() noexcept;
  [[nodiscard]] definitions::DynamicAdapter open_adapter() noexcept;
  [[nodiscard]] std::size_t revoke_read(std::uint64_t new_epoch) noexcept;
  [[nodiscard]] std::size_t revoke_write(std::uint64_t new_epoch) noexcept;
  [[nodiscard]] std::size_t revoke_open(std::uint64_t new_epoch) noexcept;

private:
  static bool dispatch_read(const definitions::AuthorizedDynamicRequest &,
                            std::span<std::byte>, std::size_t &,
                            void *) noexcept;
  static bool dispatch_write(const definitions::AuthorizedDynamicRequest &,
                             std::span<std::byte>, std::size_t &,
                             void *) noexcept;
  static bool dispatch_open(const definitions::AuthorizedDynamicRequest &,
                            std::span<std::byte>, std::size_t &,
                            void *) noexcept;
  [[nodiscard]] bool authorized(
      const definitions::AuthorizedDynamicRequest &, std::string_view,
      std::string_view, std::uint64_t) const noexcept;

  GitHubProviderConfiguration configuration_;
};

} // namespace omarchy::plugin_runtime::providers
