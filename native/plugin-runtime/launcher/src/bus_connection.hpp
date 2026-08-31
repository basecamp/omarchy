#pragma once

#include "omarchy/plugin_runtime/launcher/launcher.h"

#include <string>
#include <string_view>

struct sd_bus;

namespace omarchy::plugin_runtime::launcher::detail {

// Starts and authenticates one sd-bus connection through nonblocking I/O.
// Failure closes the complete attempt; callers may immediately start fresh.
[[nodiscard]] sd_bus *connect_bus(std::string_view address, Deadline deadline,
                                  std::string &error) noexcept;

} // namespace omarchy::plugin_runtime::launcher::detail
