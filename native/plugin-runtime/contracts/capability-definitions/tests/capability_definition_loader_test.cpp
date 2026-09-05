#include "capability_definition_loader.hpp"

#include <atomic>
#include <fcntl.h>
#include <filesystem>
#include <fstream>
#include <stdexcept>
#include <string>
#include <sys/stat.h>
#include <thread>
#include <unistd.h>

namespace {
using namespace omarchy::plugins::definitions;

void require(bool condition, std::string_view message) {
  if (!condition)
    throw std::runtime_error(std::string(message));
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
      .risk_text =
          Label("Sends bounded requests to explicitly granted weather origins"),
      .risk = RiskLevel::moderate,
      .revocation = RevocationPolicy::cancel_inflight,
      .audit = {},
      .adapter = {.adapter_class = Name("bounded-https-fetch"),
                  .contract_digest = Digest(std::string(64, 'a')),
                  .abi_version = 1},
      .operations = {},
  };
  definition.operations.insert(
      {.name = Name("forecast.read"), .label = Label("Read a forecast")});
  return definition;
}
} // namespace

void capability_definition_loader_tests() {
  const auto definition = fixture();
  const auto document = canonical_definition_document(definition, 7);
  require(!document.empty(), "canonical definition document was empty");
  LoadedDefinition parsed;
  require(parse_definition_document(document, DefinitionSource::local_admin,
                                    parsed) == LoadResult::loaded &&
              parsed.generation == 7 && parsed.definition == definition,
          "canonical admin definition did not parse");
  auto mutated = document;
  mutated.replace(mutated.find("bounded-https-fetch"),
                  std::string("bounded-https-fetch").size(), "unknown-adapter");
  require(parse_definition_document(mutated, DefinitionSource::local_admin,
                                    parsed) == LoadResult::invalid_document,
          "digest-bound document mutation was accepted");
  auto old_digest_field = document;
  old_digest_field.replace(old_digest_field.find("contract-digest"),
                           std::string("contract-digest").size(),
                           "adapter-digest");
  require(parse_definition_document(old_digest_field,
                                    DefinitionSource::local_admin, parsed) ==
              LoadResult::invalid_document,
          "removed adapter-digest field remained an accepted alias");

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
  const int root_fd = open(root.c_str(), O_RDONLY | O_DIRECTORY | O_CLOEXEC);
  require(root_fd >= 0, "trusted root descriptor did not open");
  require(load_definition_directory_fd(root_fd, DefinitionSource::local_admin,
                                       static_cast<std::uint32_t>(getuid()),
                                       registry,
                                       loaded) == LoadResult::loaded &&
              loaded == 1 && registry.find("local.weather-fetch"),
          "trusted descriptor-rooted local-admin directory did not load");

  TrustedDefinitionRegistry wrong_owner_registry;
  require(load_definition_directory_fd(root_fd, DefinitionSource::local_admin,
                                       static_cast<std::uint32_t>(getuid()) + 1,
                                       wrong_owner_registry,
                                       loaded) == LoadResult::untrusted_path &&
              loaded == 0 && wrong_owner_registry.size() == 0,
          "definition root with a mismatched trusted uid was accepted");

  TrustedDefinitionRegistry invalid_descriptor_registry;
  loaded = 99;
  require(load_definition_directory_fd(-1, DefinitionSource::local_admin,
                                       static_cast<std::uint32_t>(getuid()),
                                       invalid_descriptor_registry,
                                       loaded) == LoadResult::untrusted_path &&
              loaded == 0 && invalid_descriptor_registry.size() == 0,
          "invalid definition root descriptor did not fail transactionally");
  const int regular_file_fd =
      open((root / "weather.capability").c_str(), O_RDONLY | O_CLOEXEC);
  require(regular_file_fd >= 0, "regular-file root fixture did not open");
  loaded = 99;
  require(load_definition_directory_fd(
              regular_file_fd, DefinitionSource::local_admin,
              static_cast<std::uint32_t>(getuid()), invalid_descriptor_registry,
              loaded) == LoadResult::untrusted_path &&
              loaded == 0 && invalid_descriptor_registry.size() == 0,
          "non-directory definition root did not fail transactionally");
  close(regular_file_fd);
  close(root_fd);

  const auto assert_rejected = [&](std::string_view message) {
    TrustedDefinitionRegistry candidate = registry;
    const auto before = candidate.size();
    const int descriptor =
        open(root.c_str(), O_RDONLY | O_DIRECTORY | O_CLOEXEC);
    require(descriptor >= 0, "negative root descriptor did not open");
    const auto result = load_definition_directory_fd(
        descriptor, DefinitionSource::local_admin,
        static_cast<std::uint32_t>(getuid()), candidate, loaded);
    close(descriptor);
    require(result != LoadResult::loaded && loaded == 0 &&
                candidate.size() == before &&
                candidate.find("local.weather-fetch"),
            message);
  };

  chmod((root / "weather.capability").c_str(), 0600);
  assert_rejected("mode-0600 definition entered the trust registry");
  chmod((root / "weather.capability").c_str(), 0644);

  chmod(root.c_str(), 0775);
  assert_rejected("mode-0775 definition root entered the trust registry");
  chmod(root.c_str(), 0755);

  std::filesystem::create_hard_link(root / "weather.capability",
                                    root / "alias.capability");
  assert_rejected("hard-linked definition entered the trust registry");
  std::filesystem::remove(root / "alias.capability");

  std::atomic<bool> mutate{true};
  std::atomic<std::size_t> mutations{0};
  std::thread mutator([&] {
    while (mutate.load(std::memory_order_acquire)) {
      chmod((root / "weather.capability").c_str(), 0600);
      chmod((root / "weather.capability").c_str(), 0644);
      mutations.fetch_add(1, std::memory_order_release);
    }
  });
  while (mutations.load(std::memory_order_acquire) < 100) {
  }
  bool rejected_mutation = false;
  for (int attempt = 0; attempt < 100 && !rejected_mutation; ++attempt) {
    TrustedDefinitionRegistry mutation_registry;
    const int descriptor =
        open(root.c_str(), O_RDONLY | O_DIRECTORY | O_CLOEXEC);
    require(descriptor >= 0, "mutation root descriptor did not open");
    const auto result = load_definition_directory_fd(
        descriptor, DefinitionSource::local_admin,
        static_cast<std::uint32_t>(getuid()), mutation_registry, loaded);
    close(descriptor);
    if (result != LoadResult::loaded) {
      require(loaded == 0 && mutation_registry.size() == 0,
              "file mutation failure published a partial registry");
      rejected_mutation = true;
    }
  }
  mutate.store(false, std::memory_order_release);
  mutator.join();
  chmod((root / "weather.capability").c_str(), 0644);
  require(rejected_mutation,
          "concurrent definition metadata mutation was never rejected");

  std::atomic<bool> mutate_directory{true};
  std::atomic<std::size_t> directory_mutations{0};
  std::thread directory_mutator([&] {
    const auto churn = root / "churn";
    while (mutate_directory.load(std::memory_order_acquire)) {
      const int descriptor =
          open(churn.c_str(), O_WRONLY | O_CREAT | O_CLOEXEC, 0644);
      if (descriptor >= 0)
        close(descriptor);
      unlink(churn.c_str());
      directory_mutations.fetch_add(1, std::memory_order_release);
    }
  });
  while (directory_mutations.load(std::memory_order_acquire) < 100) {
  }
  bool rejected_directory_mutation = false;
  for (int attempt = 0; attempt < 100 && !rejected_directory_mutation;
       ++attempt) {
    TrustedDefinitionRegistry mutation_registry;
    const int descriptor =
        open(root.c_str(), O_RDONLY | O_DIRECTORY | O_CLOEXEC);
    require(descriptor >= 0, "directory mutation root did not open");
    const auto result = load_definition_directory_fd(
        descriptor, DefinitionSource::local_admin,
        static_cast<std::uint32_t>(getuid()), mutation_registry, loaded);
    close(descriptor);
    if (result != LoadResult::loaded) {
      require(loaded == 0 && mutation_registry.size() == 0,
              "directory mutation failure published a partial registry");
      rejected_directory_mutation = true;
    }
  }
  mutate_directory.store(false, std::memory_order_release);
  directory_mutator.join();
  std::filesystem::remove(root / "churn");
  require(rejected_directory_mutation,
          "concurrent definition directory mutation was never rejected");

  std::filesystem::remove(root / "weather.capability");
  std::filesystem::create_symlink("/etc/passwd", root / "escape.capability");
  TrustedDefinitionRegistry symlink_registry;
  const int symlink_root_fd =
      open(root.c_str(), O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
  require(symlink_root_fd >= 0, "symlink root descriptor did not open");
  require(load_definition_directory_fd(
              symlink_root_fd, DefinitionSource::local_admin,
              static_cast<std::uint32_t>(getuid()), symlink_registry,
              loaded) == LoadResult::untrusted_path &&
              symlink_registry.size() == 0,
          "symlink definition entered the trust registry");
  close(symlink_root_fd);
  std::filesystem::remove_all(root);
}
