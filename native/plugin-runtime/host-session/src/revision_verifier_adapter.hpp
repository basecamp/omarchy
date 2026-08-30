#pragma once

#include "activation_snapshot.hpp"

namespace omarchy::plugin_runtime::host_session {

// Runtime adapter from the activation seam to descriptor-relative plugin
// discovery. It intentionally has no pathname-based fallback.
class DescriptorRevisionVerifier final : public RevisionVerifier {
public:
  [[nodiscard]] std::optional<VerifiedRevision>
  verify_open_revision(int revision_directory_fd) const override;
};

} // namespace omarchy::plugin_runtime::host_session
