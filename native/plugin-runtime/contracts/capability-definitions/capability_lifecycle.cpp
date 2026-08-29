#include "capability_lifecycle.hpp"

namespace omarchy::plugins::definitions {
namespace {
void collect(DefinitionChangeAssessment &assessment,
             const CapabilityReference &reference,
             std::span<const DefinitionDependency> dependencies) {
  for (const auto &dependency : dependencies) {
    if (dependency.reference.canonical_name == reference.canonical_name &&
        dependency.reference.definition_generation ==
            reference.definition_generation &&
        dependency.reference.definition_digest == reference.definition_digest)
      assessment.dependents.push_back(dependency);
  }
}
} // namespace

DefinitionChangeAssessment assess_definition_install(
    const TrustedDefinitionRegistry &registry,
    const CapabilityDefinition &candidate, std::uint32_t generation,
    std::span<const DefinitionDependency> dependencies) {
  DefinitionChangeAssessment result;
  if (!valid_definition(candidate) || generation == 0)
    return result;
  const auto installed = registry.find(candidate.canonical_name.view());
  if (!installed) {
    auto copy = registry;
    result.decision = copy.install(candidate, DefinitionSource::local_admin,
                                   generation)
                          ? DefinitionChangeDecision::installable
                          : DefinitionChangeDecision::namespace_conflict;
    return result;
  }
  collect(result,
          {.canonical_name = installed->definition->canonical_name,
           .definition_generation = installed->generation,
           .definition_digest = installed->digest},
          dependencies);
  if (*installed->definition == candidate && installed->generation == generation) {
    result.decision = DefinitionChangeDecision::unchanged;
    return result;
  }
  result.decision = result.dependents.empty()
                        ? DefinitionChangeDecision::requires_plugin_review
                        : DefinitionChangeDecision::blocked_by_dependents;
  return result;
}

DefinitionChangeAssessment assess_definition_removal(
    const TrustedDefinitionRegistry &registry, std::string_view canonical_name,
    std::span<const DefinitionDependency> dependencies) {
  DefinitionChangeAssessment result;
  const auto installed = registry.find(canonical_name);
  if (!installed) {
    result.decision = DefinitionChangeDecision::unchanged;
    return result;
  }
  collect(result,
          {.canonical_name = installed->definition->canonical_name,
           .definition_generation = installed->generation,
           .definition_digest = installed->digest},
          dependencies);
  result.decision = result.dependents.empty()
                        ? DefinitionChangeDecision::installable
                        : DefinitionChangeDecision::blocked_by_dependents;
  return result;
}
} // namespace omarchy::plugins::definitions
