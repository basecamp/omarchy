#include "capability_definition_loader.hpp"

#include <filesystem>
#include <fstream>
#include <stdexcept>
#include <string>
#include <sys/stat.h>
#include <unistd.h>

namespace {
using namespace omarchy::plugins::definitions;

void require(bool condition, std::string_view message) {
  if (!condition)
    throw std::runtime_error(std::string(message));
}

bool adapter_available(std::string_view adapter_class, const Digest &digest,
                       std::uint32_t abi, void *) noexcept {
  return adapter_class == "bounded-https-fetch" &&
         digest.view() == std::string(64, 'a') && abi == 1;
}

CapabilityDefinition fixture() {
  CapabilityDefinition definition{
      .canonical_name = Name("local.weather-fetch"),
      .authority_identity = Name("local.weather-fetch-v1"),
      .enforcement_family = EnforcementFamily::network_fetch,
      .display_category_id = Name("local.weather"),
      .display_category_label = Label("Local weather tools"),
      .scope_schema = ScopeSchema::https_origins_and_methods,
      .title = Label("Fetch weather from selected origins"),
      .risk_text = Label("Sends bounded requests to explicitly granted weather origins"),
      .risk = RiskLevel::moderate,
      .revocation = RevocationPolicy::cancel_inflight,
      .audit = {},
      .adapter = {.adapter_class = Name("bounded-https-fetch"),
                  .implementation_digest = Digest(std::string(64, 'a')),
                  .abi_version = 1},
      .operations = {},
  };
  definition.operations.insert({.name = Name("forecast.read"),
                                .label = Label("Read a forecast")});
  return definition;
}
} // namespace

void capability_definition_loader_tests() {
  const AdapterVerifier verifier{.available = adapter_available};
  const auto definition = fixture();
  const auto document = canonical_definition_document(definition, 7);
  require(!document.empty(), "canonical definition document was empty");
  LoadedDefinition parsed;
  require(parse_definition_document(document, DefinitionSource::local_admin,
                                    verifier, parsed) == LoadResult::loaded &&
              parsed.generation == 7 && parsed.definition == definition,
          "canonical admin definition did not parse");
  auto mutated = document;
  mutated.replace(mutated.find("bounded-https-fetch"),
                  std::string("bounded-https-fetch").size(), "unknown-adapter");
  require(parse_definition_document(mutated, DefinitionSource::local_admin,
                                    verifier, parsed) ==
              LoadResult::invalid_document,
          "digest-bound document mutation was accepted");

  char temporary[] = "/tmp/omarchy-capability-loader.XXXXXX";
  const char *directory = mkdtemp(temporary);
  require(directory != nullptr, "temporary trust root failed");
  const auto root = std::filesystem::path(directory);
  {
    std::ofstream output(root / "weather.capability", std::ios::binary);
    output << document;
  }
  chmod((root / "weather.capability").c_str(), 0644);
  chmod(root.c_str(), 0755);
  TrustedDefinitionRegistry registry;
  std::size_t loaded = 0;
  require(load_definition_directory(root.string(), DefinitionSource::local_admin,
                                    static_cast<std::uint32_t>(getuid()), verifier,
                                    registry, loaded) == LoadResult::loaded &&
              loaded == 1 && registry.find("local.weather-fetch"),
          "trusted local-admin directory did not load");

  std::filesystem::remove(root / "weather.capability");
  std::filesystem::create_symlink("/etc/passwd", root / "escape.capability");
  TrustedDefinitionRegistry symlink_registry;
  require(load_definition_directory(root.string(), DefinitionSource::local_admin,
                                    static_cast<std::uint32_t>(getuid()), verifier,
                                    symlink_registry, loaded) ==
              LoadResult::untrusted_path &&
              symlink_registry.size() == 0,
          "symlink definition entered the trust registry");
  std::filesystem::remove_all(root);
}
