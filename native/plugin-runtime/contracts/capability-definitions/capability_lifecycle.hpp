#pragma once

#include "capability_definition.hpp"

#include <span>

namespace omarchy::plugins::definitions {

struct DefinitionDependency {
  permissions::PluginId plugin;
  Digest revision;
  CapabilityReference reference;
  bool required = false;
};

enum class DefinitionChangeDecision : std::uint8_t {
  installable,
  unchanged,
  requires_plugin_review,
  blocked_by_dependents,
  namespace_conflict,
};

struct DefinitionChangeAssessment {
  DefinitionChangeDecision decision = DefinitionChangeDecision::namespace_conflict;
  permissions::FixedVector<DefinitionDependency, 128> dependents;
};

// Definitions are staged independently of plugins. Replacing an exact name or
// authority identity never mutates the live registry in place: installed plugin
// revisions pin the old generation and digest and must be reviewed first.
[[nodiscard]] DefinitionChangeAssessment assess_definition_install(
    const TrustedDefinitionRegistry &registry,
    const CapabilityDefinition &candidate, std::uint32_t generation,
    std::span<const DefinitionDependency> dependencies);

[[nodiscard]] DefinitionChangeAssessment assess_definition_removal(
    const TrustedDefinitionRegistry &registry, std::string_view canonical_name,
    std::span<const DefinitionDependency> dependencies);

} // namespace omarchy::plugins::definitions
