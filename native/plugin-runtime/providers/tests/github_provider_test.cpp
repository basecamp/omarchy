#include "omarchy/plugin_runtime/providers/github_provider.hpp"

#include <algorithm>
#include <array>
#include <cstring>
#include <iostream>
#include <stdexcept>
#include <string>

namespace definitions = omarchy::plugins::definitions;
namespace permissions = omarchy::plugins::permissions;
namespace providers = omarchy::plugin_runtime::providers;

namespace {
constexpr std::string_view kReadDigest = "9fbba69a1eefaa3ac03d950e0582b7fd81c1ec468638f04f05225a362f7bbd52";
constexpr std::string_view kReadScope = "{\"account\":\"user-selected\",\"datasets\":[\"notifications\",\"review-requests\",\"pull-requests\",\"issues\",\"actions\",\"repositories\"],\"service\":\"github.com\"}";

struct BackendState { std::size_t calls = 0; };

void require(bool value, std::string_view message) {
  if (!value) throw std::runtime_error(std::string(message));
}

bool backend(std::string_view operation, std::string_view argument,
             std::span<std::byte> response, std::size_t &written,
             void *context) noexcept {
  auto &state = *static_cast<BackendState *>(context);
  if (operation != "read" ||
      argument != "notifications,review-requests,pull-requests,issues,actions,repositories")
    return false;
  constexpr std::string_view value = "{\"schemaVersion\":1,\"login\":\"proof\"}";
  if (response.size() < value.size()) return false;
  std::memcpy(response.data(), value.data(), value.size());
  written = value.size();
  ++state.calls;
  return true;
}

permissions::ActivationBinding binding() {
  return {.plugin = permissions::PluginId("robzolkos.github"),
          .revision = permissions::Digest(std::string(64, 'a')),
          .policy_fingerprint = permissions::Digest(std::string(64, 'b')),
          .generation = 1};
}
}

int main() try {
  BackendState state;
  providers::GitHubProvider provider({.binding = binding(), .read_epoch = 7,
      .write_epoch = 8, .open_epoch = 9,
      .backend = {.invoke = backend, .context = &state}});
  auto adapter = provider.read_adapter();
  const std::string payload = "{\"resource\":\"selected\",\"datasets\":[\"notifications\",\"review-requests\",\"pull-requests\",\"issues\",\"actions\",\"repositories\"]}";
  const definitions::AuthorizedDynamicRequest request{
      .authorization = {.binding = binding(),
          .definition = {.canonical_name = definitions::Name("remote-account.read"),
              .definition_generation = 1,
              .definition_digest = definitions::Digest(kReadDigest)},
          .grant_epoch = 7},
      .operation = "read", .demand_scope = kReadScope,
      .payload = std::as_bytes(std::span(payload.data(), payload.size()))};
  std::array<std::byte, providers::kMaximumGitHubResponseBytes> output{};
  std::size_t written = 0;
  require(adapter.dispatch(request, output, written, adapter.context),
          "authorized read failed");
  require(state.calls == 1 && written > 0, "backend not reached exactly once");
  auto stale = request;
  stale.authorization.grant_epoch = 6;
  require(!adapter.dispatch(stale, output, written, adapter.context),
          "stale epoch reached backend");
  require(state.calls == 1, "denied request caused an effect");
  (void)provider.revoke_read(8);
  require(!adapter.dispatch(request, output, written, adapter.context),
          "revoked request reached backend");
  require(state.calls == 1, "revoked request caused an effect");
  std::cout << "github provider: PASS\n";
  return 0;
} catch (const std::exception &error) {
  std::cerr << "github provider: FAIL: " << error.what() << '\n';
  return 1;
}
