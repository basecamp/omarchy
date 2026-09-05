#pragma once

#include "grant_snapshot.hpp"
#include "manifest_contract.hpp"
#include "omarchy/plugin/wire/permission_snapshot.hpp"

#include <optional>

namespace omarchy::plugin_runtime::host_session {

// Projects one already-authoritative activation snapshot into the manifest's
// canonical request index space. Failure is transactional and produces no
// payload for the worker.
[[nodiscard]] std::optional<plugin::wire::permission_snapshot::PermissionSnapshot>
project_permission_snapshot(const plugins::manifest::ManifestV2 &manifest,
                            const policy::GrantSnapshot &grants) noexcept;

} // namespace omarchy::plugin_runtime::host_session
