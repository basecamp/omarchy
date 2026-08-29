#pragma once

#include <string_view>

namespace omarchy::plugin_runtime {
std::string_view build_version();
unsigned envelope_version();
} // namespace omarchy::plugin_runtime
