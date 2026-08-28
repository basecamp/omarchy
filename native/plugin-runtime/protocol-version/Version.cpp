#include "omarchy/plugin_runtime/Version.h"

#include "omarchy/plugin_runtime/PluginRuntimeVersion.h"

namespace omarchy::plugin_runtime {
std::string_view build_version() { return kBuildVersion; }

unsigned envelope_version() { return kEnvelopeVersion; }
} // namespace omarchy::plugin_runtime
