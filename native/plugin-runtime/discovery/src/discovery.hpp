#pragma once

#include "manifest_contract.hpp"

namespace omarchy::plugins::discovery {

// A verified view of the exact directory object named by an already-open file
// descriptor. The implementation performs every lookup relative to that
// descriptor and never converts it back into a pathname.
struct DescriptorVerifiedPlugin {
  manifest::ManifestV2 manifest;
  manifest::ContentIdentity identity;
};

// Parse manifest.json and identify the complete plugin tree rooted at
// revision_directory_fd. Throws std::runtime_error when the descriptor or any
// tree entry is invalid, unsafe, unstable, or exceeds the normal tree limits.
[[nodiscard]] DescriptorVerifiedPlugin
discover_open_revision(int revision_directory_fd);

} // namespace omarchy::plugins::discovery
