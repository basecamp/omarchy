#pragma once

#include "omarchy/plugin_runtime/launcher/launcher.h"

#include <memory>
#include <string>
#include <string_view>

namespace omarchy::plugin_runtime::launcher::test_support {

[[nodiscard]] Supervisor
make_supervisor(std::string bwrap_path, std::string worker_path,
                std::shared_ptr<ResourceScopeController> resource_scope,
                bool force_reaper_start_failure = false);

[[nodiscard]] bool connect_bus(std::string_view address, Deadline deadline,
                               std::string &error) noexcept;

} // namespace omarchy::plugin_runtime::launcher::test_support
