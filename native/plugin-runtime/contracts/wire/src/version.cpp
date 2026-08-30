#include "omarchy/plugin_runtime/Version.h"

#include "omarchy/plugin/wire/envelope.hpp"

namespace omarchy::plugin_runtime {
std::string_view build_version() { return OMARCHY_PLUGIN_BUILD_VERSION; }

unsigned envelope_version() {
  return omarchy::plugin::wire::kEnvelopeVersion;
}
} // namespace omarchy::plugin_runtime
