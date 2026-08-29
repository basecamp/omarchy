#include "omarchy/plugin_runtime/providers/hyprland_window_backend.hpp"

#include <cstring>
#include <stdexcept>

namespace providers = omarchy::plugin_runtime::providers;

namespace {
void require(bool value, const char *message) { if (!value) throw std::runtime_error(message); }
bool read_json(std::string_view argument, std::span<char> output,
               std::size_t &written, void *) noexcept {
  const std::string_view monitors = R"([{"id":2,"focused":true,"x":100,"y":50,"width":2000,"height":1400,"scale":2,"reserved":[0,0,0,42],"activeWorkspace":{"id":7}}])";
  const std::string_view clients = R"([{"address":"0xsecret","title":"Private document","class":"secret-app","pid":4242,"mapped":true,"hidden":false,"fullscreen":0,"monitor":2,"workspace":{"id":7},"at":[150,100],"size":[400,300]},{"address":"0xother","mapped":true,"hidden":false,"fullscreen":0,"monitor":2,"workspace":{"id":8},"at":[200,200],"size":[200,200]},{"address":"0xfull","mapped":true,"hidden":false,"fullscreen":1,"monitor":2,"workspace":{"id":7},"at":[100,50],"size":[1000,700]}])";
  const auto source = argument == "monitors" ? monitors : argument == "clients" ? clients : std::string_view{};
  if (source.empty() || source.size() > output.size()) return false;
  std::memcpy(output.data(), source.data(), source.size());
  written = source.size();
  return true;
}
}

int main() {
  providers::HyprlandWindowBackend backend({.read_json = read_json});
  const auto configured = backend.configuration();
  providers::SanitizedWindowSnapshot first;
  providers::SanitizedWindowSnapshot second;
  require(configured.window_rectangles(first, configured.context), "snapshot failed");
  require(configured.window_rectangles(second, configured.context), "repeat snapshot failed");
  require(first.width == 1000 && first.height == 700 && first.reserved_bottom == 42,
          "monitor geometry was not sanitized");
  require(first.window_count == 1 && first.windows[0].x == 50 && first.windows[0].y == 50 &&
              first.windows[0].width == 400 && first.windows[0].height == 300,
          "workspace/fullscreen filtering or monitor-local conversion failed");
  require(first.windows[0].opaque_id != 0 && first.windows[0].opaque_id == second.windows[0].opaque_id,
          "opaque identity is absent or unstable");
}
