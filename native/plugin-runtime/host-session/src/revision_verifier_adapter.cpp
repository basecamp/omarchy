#include "revision_verifier_adapter.hpp"

#include "discovery.hpp"

#include <exception>

namespace omarchy::plugin_runtime::host_session {

std::optional<VerifiedRevision>
DescriptorRevisionVerifier::verify_open_revision(
    int revision_directory_fd) const {
  try {
    auto verified =
        plugins::discovery::discover_open_revision(revision_directory_fd);
    return VerifiedRevision{
        .manifest = std::move(verified.manifest),
        .tree_sha256 = std::move(verified.identity.tree_sha256),
        .request_sha256 = std::move(verified.identity.request_sha256)};
  } catch (const std::exception &) {
    return std::nullopt;
  }
}

} // namespace omarchy::plugin_runtime::host_session
