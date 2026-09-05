#include "omarchy/plugin_runtime/surface/profile.hpp"

#include <algorithm>

namespace omarchy::plugin_runtime::surface {

std::optional<ProfileSelection>
select_software_profile(std::span<const std::uint32_t> offered_versions) {
  if (std::ranges::find(offered_versions, kSoftwareProfileVersion) ==
      offered_versions.end()) {
    return std::nullopt;
  }
  return ProfileSelection{.version = kSoftwareProfileVersion,
                          .pixel_format = kRgba8888Premultiplied};
}

} // namespace omarchy::plugin_runtime::surface
