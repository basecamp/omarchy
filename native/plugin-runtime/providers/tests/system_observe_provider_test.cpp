#include "omarchy/plugin_runtime/providers/system_observe_provider.hpp"

#include <array>
#include <stdexcept>

namespace providers = omarchy::plugin_runtime::providers;
namespace definitions = omarchy::plugins::definitions;
namespace permissions = omarchy::plugins::permissions;

namespace {
void require(bool value, const char *message) { if (!value) throw std::runtime_error(message); }
permissions::Digest digest(char value) { return permissions::Digest(std::string(64, value)); }
permissions::ActivationBinding binding() { return {.plugin = permissions::PluginId("slcode777.omagotchi"), .revision = digest('a'), .policy_fingerprint = digest('b'), .generation = 4}; }
bool observe(providers::SanitizedWindowSnapshot &out, void *) noexcept {
  out = {.width = 1920, .height = 1080, .reserved_bottom = 48, .window_count = 2};
  out.windows[0] = {.opaque_id = 0x1234, .x = 80, .y = 100, .width = 800, .height = 600};
  out.windows[1] = {.opaque_id = 0x5678, .x = 1000, .y = 200, .width = 600, .height = 500};
  return true;
}
definitions::AuthorizedDynamicRequest request(std::uint64_t epoch = 7) {
  return {.authorization = {.binding = binding(), .definition = {
      .canonical_name = definitions::Name("system.observe"), .definition_generation = 1,
      .definition_digest = definitions::Digest("dc22d694f498eeb21af02a9e6d0313b20fd2a0e20db5cab64c08630999cfa84c")},
      .grant_epoch = epoch}, .operation = "observe",
      .demand_scope = "{\"datasets\":[\"compositor.window-rectangles\"]}",
      .payload = {}};
}
}

int main() {
  providers::SystemObserveProvider provider({.binding = binding(), .epoch = 7,
      .backend = {.window_rectangles = observe}});
  const auto adapter = provider.adapter();
  std::array<std::byte, 8192> output{};
  std::size_t written = 0;
  require(adapter.dispatch(request(), output, written, adapter.context), "observation failed");
  const std::string result(reinterpret_cast<const char *>(output.data()), written);
  require(result.find("1234") != std::string::npos && result.find("reservedBottom") != std::string::npos,
          "sanitized geometry missing");
  require(result.find("address") == std::string::npos && result.find("title") == std::string::npos &&
              result.find("class") == std::string::npos && result.find("pid") == std::string::npos,
          "identity metadata leaked");
  auto denied = request(); denied.demand_scope = "{\"datasets\":[\"compositor.clients\"]}";
  require(!adapter.dispatch(denied, output, written, adapter.context), "broader dataset was accepted");
  require(provider.revoke(8), "revocation failed");
  require(!adapter.dispatch(request(), output, written, adapter.context), "stale epoch survived revocation");
  require(adapter.dispatch(request(8), output, written, adapter.context), "new epoch was rejected");
}
