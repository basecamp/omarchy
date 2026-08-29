#include "capability_definition_loader.hpp"
#include "grant_store.hpp"
#include "lifecycle.hpp"
#include "manifest_contract.hpp"
#include "omarchy/plugin_runtime/providers/audio_device_provider.hpp"
#include "omarchy/plugin_runtime/providers/github_provider.hpp"
#include "omarchy/plugin_runtime/providers/radio_provider.hpp"
#include "omarchy/plugin_runtime/providers/system_observe_provider.hpp"

#include <fstream>
#include <array>
#include <iostream>
#include <iterator>
#include <ranges>
#include <stdexcept>
#include <string>
#include <unistd.h>
#include <vector>

namespace definitions = omarchy::plugins::definitions;
namespace grants = omarchy::plugins::grants;
namespace manifest = omarchy::plugins::manifest;
namespace lifecycle = omarchy::plugins::lifecycle;
namespace permissions = omarchy::plugins::permissions;
namespace providers = omarchy::plugin_runtime::providers;

namespace {
struct Adapters {
  std::array<definitions::DynamicAdapter, 8> values;
};

bool available(std::string_view name, const definitions::Digest &digest,
               std::uint32_t abi, void *opaque) noexcept {
  const auto &adapters = *static_cast<const Adapters *>(opaque);
  return std::ranges::any_of(adapters.values, [&](const auto &adapter) {
    return adapter.binding.adapter_class.view() == name &&
           adapter.binding.implementation_digest == digest &&
           adapter.binding.abi_version == abi;
  });
}
definitions::DynamicScopeRelation exact(const definitions::CapabilityDefinition &,
                                        std::string_view left,
                                        std::string_view right, void *) noexcept {
  return left == right ? definitions::DynamicScopeRelation::equal
                       : definitions::DynamicScopeRelation::incomparable;
}
}

int main(int argc, char **argv) try {
  if (argc == 5 && std::string_view(argv[1]) == "revoke") {
    grants::GrantStore store(argv[2]);
    const auto state = store.read();
    const auto plugin = std::ranges::find_if(state.plugins, [&](const auto &item) {
      return item.plugin.view() == std::string_view(argv[3]);
    });
    if (plugin == state.plugins.end() || !plugin->active) return 69;
    auto bundle = grants::make_bundle(
        2, plugin->active->binding.plugin, plugin->active->binding.revision,
        plugin->active->source_request_fingerprint,
        plugin->active->binding.generation, plugin->active->requests,
        plugin->active->dynamic_grants);
    (void)store.revoke_dynamic(bundle, argv[4]);
    return 0;
  }
  if (argc != 7) return 64;
  std::ifstream input(argv[1]);
  const std::string document((std::istreambuf_iterator<char>(input)), {});
  const auto parsed = manifest::parse_manifest_v2(document);
  providers::RadioProvider provider({.binding = {}, .fetch_epoch = 0,
                                     .media_epoch = 0, .https = {}, .media = {}});
  providers::AudioDeviceProvider audio_provider(
      {.binding = {}, .observe_epoch = 0, .control_epoch = 0, .backend = {}});
  providers::GitHubProvider github_provider(
      {.binding = {}, .read_epoch = 0, .write_epoch = 0,
       .open_epoch = 0, .backend = {}});
  providers::SystemObserveProvider system_observe_provider(
      {.binding = {}, .epoch = 0, .backend = {}});
  Adapters adapters{{provider.fetch_adapter(), provider.media_adapter(),
                     audio_provider.observe_adapter(),
                     audio_provider.control_adapter(),
                     github_provider.read_adapter(),
                     github_provider.write_adapter(),
                     github_provider.open_adapter(),
                     system_observe_provider.adapter()}};
  definitions::TrustedDefinitionRegistry registry;
  std::size_t loaded = 0;
  const definitions::AdapterVerifier verifier{.available = available,
                                                .context = &adapters};
  if (definitions::load_definition_directory(
          argv[6], definitions::DefinitionSource::omarchy_package,
          static_cast<std::uint32_t>(getuid()), verifier, registry, loaded) !=
          definitions::LoadResult::loaded || loaded == 0 ||
      loaded > adapters.values.size())
    return 65;
  std::vector<definitions::DynamicRevisionGrant> dynamic;
  for (const auto &item : parsed.requests) {
    if (item.definition_generation == 0) continue;
    if (!item.required) continue;
    const auto request = definitions::dynamic_request_from_manifest(item, registry);
    if (!request) return 66;
    definitions::DynamicRevisionGrant record{
        .binding = {.plugin = permissions::PluginId(argv[2]),
                    .revision = permissions::Digest(argv[3]),
                    .policy_fingerprint = permissions::Digest(std::string(64, 'a')),
                    .generation = 1},
        .request = *request,
        .grant = {.definition = request->definition, .operations = {},
                  .scope = request->scope,
                  .state = permissions::GrantState::granted, .epoch = 1}};
    for (const auto &operation : request->operations.values())
      record.grant.operations.insert(operation);
    if (!definitions::review_dynamic_grant(
            registry, record, {.compare = exact})) return 67;
    dynamic.push_back(std::move(record));
  }
  if (dynamic.empty()) return 66;
  auto compiled = lifecycle::translate_requests(parsed);
  auto bundle = grants::make_bundle(2, permissions::PluginId(argv[2]),
      permissions::Digest(argv[3]), permissions::Digest(argv[4]), 1,
      std::move(compiled), std::move(dynamic));
  grants::GrantStore store(argv[5]);
  const auto staged = store.stage_candidate(bundle);
  for (const auto &request : bundle.requests.values()) {
    if (!request.required) continue;
    const auto preview = store.preview(bundle, request.capability);
    (void)store.decide(bundle, request.capability, std::nullopt,
                       permissions::UserDecision::grant,
                       permissions::DecisionActor::trusted_ui, 1,
                       preview.expected_mutation_sequence);
  }
  store.activate_candidate(staged.revision.binding);
  return 0;
} catch (const std::exception &error) {
  std::cerr << "dynamic grant failed: " << error.what() << '\n';
  return 68;
}
