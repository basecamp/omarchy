#pragma once

#include "omarchy/plugin_runtime/providers/github_provider.hpp"

#include <filesystem>
#include <optional>

namespace omarchy::plugin_runtime::providers {

// Host-owned launcher for an independently packaged, provenance-checked GitHub
// adapter. The sandbox receives only opaque handles and bounded JSON results.
class GitHubCliBackend {
public:
  GitHubCliBackend(std::filesystem::path program,
                   std::filesystem::path state_root,
                   std::uint32_t expected_owner);

  [[nodiscard]] bool available() const noexcept;
  [[nodiscard]] GitHubBackend configuration() noexcept;

private:
  static bool invoke(std::string_view, std::string_view,
                     std::span<std::byte>, std::size_t &, void *) noexcept;

  std::filesystem::path program_;
  std::filesystem::path state_root_;
  bool available_ = false;
};

} // namespace omarchy::plugin_runtime::providers
