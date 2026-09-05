#pragma once

#include "capability_definition.hpp"

#include <cstdint>
#include <string>
#include <string_view>

namespace omarchy::plugins::definitions {

struct LoadedDefinition {
  CapabilityDefinition definition;
  DefinitionSource source = DefinitionSource::omarchy_package;
  std::uint32_t generation = 0;
  Digest digest;
};

enum class LoadResult : std::uint8_t {
  loaded,
  invalid_document,
  untrusted_path,
  registry_rejected,
  bound_exceeded,
};

[[nodiscard]] std::string canonical_definition_document(
    const CapabilityDefinition &definition, std::uint32_t generation);
[[nodiscard]] LoadResult parse_definition_document(
    std::string_view document, DefinitionSource source, LoadedDefinition &output);
// Trusted callers open the fixed package or administrator trust root and
// pass that exact directory object here. The loader never recovers a pathname
// from the descriptor and does not take ownership of it.
[[nodiscard]] LoadResult load_definition_directory_fd(
    int directory_fd, DefinitionSource source, std::uint32_t expected_uid,
    TrustedDefinitionRegistry &registry, std::size_t &loaded_count);

} // namespace omarchy::plugins::definitions
