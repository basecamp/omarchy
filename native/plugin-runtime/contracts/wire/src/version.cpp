#include "omarchy/plugin_runtime/Version.h"

namespace omarchy::plugin_runtime {
std::string_view build_version() { return OMARCHY_PLUGIN_BUILD_VERSION; }

unsigned envelope_version() { return 1; }
} // namespace omarchy::plugin_runtime
