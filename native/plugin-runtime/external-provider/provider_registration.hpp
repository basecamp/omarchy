#pragma once

#include "external_provider.hpp"

#include <span>
#include <vector>

namespace omarchy::plugins::external_provider {

enum class RegistrationLoadResult : std::uint8_t {
  loaded,
  untrusted_path,
  invalid_document,
  invalid_provider,
  duplicate_identity,
  bound_exceeded,
};

struct ProviderDependency {
  permissions::PluginId plugin;
  Digest revision;
  definitions::AdapterBinding adapter;
};

enum class RegistrationChangeDecision : std::uint8_t {
  installable,
  unchanged,
  requires_plugin_review,
  blocked_by_dependents,
  identity_conflict,
};

struct RegistrationChangeAssessment {
  RegistrationChangeDecision decision =
      RegistrationChangeDecision::identity_conflict;
  std::vector<ProviderDependency> dependents;
};

[[nodiscard]] std::string canonical_registration_document(
    const Registration &registration);
[[nodiscard]] RegistrationLoadResult parse_registration_document(
    std::string_view document, std::uint32_t expected_uid,
    Registration &registration);
[[nodiscard]] RegistrationLoadResult load_registration_directory(
    std::string_view path, std::uint32_t expected_uid,
    std::vector<Registration> &registrations);
[[nodiscard]] RegistrationChangeAssessment assess_registration_install(
    std::span<const Registration> installed, const Registration &candidate,
    std::span<const ProviderDependency> dependencies);
[[nodiscard]] RegistrationChangeAssessment assess_registration_removal(
    std::span<const Registration> installed, std::string_view service_id,
    std::span<const ProviderDependency> dependencies);
[[nodiscard]] definitions::DynamicAdapter
compose_dynamic_adapter(Registration &registration);

} // namespace omarchy::plugins::external_provider
