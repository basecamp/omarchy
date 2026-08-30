#include "consent_review.hpp"

#include "manifest_contract.hpp"

#include <algorithm>
#include <ranges>
#include <tuple>
#include <utility>

namespace omarchy::plugin_runtime::host_session {
namespace {

void field(std::string &bytes, std::string_view value) {
  for (int shift = 56; shift >= 0; shift -= 8)
    bytes.push_back(static_cast<char>((value.size() >> shift) & 0xff));
  bytes.append(value);
}

void number(std::string &bytes, std::uint64_t value) {
  for (int shift = 56; shift >= 0; shift -= 8)
    bytes.push_back(static_cast<char>((value >> shift) & 0xff));
}

ConsentDeltaKind translate(permissions::DeltaKind kind) {
  using D = permissions::DeltaKind;
  switch (kind) {
  case D::unchanged:
    return ConsentDeltaKind::unchanged;
  case D::narrowed:
    return ConsentDeltaKind::narrowed;
  case D::expanded:
    return ConsentDeltaKind::expanded;
  case D::incomparable:
    return ConsentDeltaKind::incomparable;
  case D::added:
    return ConsentDeltaKind::added;
  case D::removed:
    return ConsentDeltaKind::removed;
  case D::requirement_changed:
    return ConsentDeltaKind::requirement_changed;
  }
  return ConsentDeltaKind::incomparable;
}

std::vector<definitions::DynamicRequest>
dynamic_requests(const plugins::manifest::ManifestV2 &manifest,
                 const definitions::TrustedDefinitionRegistry &registry) {
  std::vector<definitions::DynamicRequest> result;
  for (const auto &request : manifest.requests) {
    if (request.definition_generation == 0)
      continue;
    auto translated =
        definitions::dynamic_request_from_manifest(request, registry);
    if (!translated)
      return {};
    result.push_back(std::move(*translated));
  }
  std::ranges::sort(result, {}, [](const auto &request) {
    return request.definition.canonical_name;
  });
  return result;
}

const definitions::DynamicRevisionGrant *
dynamic_for(const std::optional<policy::GrantSnapshot> &snapshot,
            std::string_view name) {
  if (!snapshot)
    return nullptr;
  const auto found =
      std::ranges::find_if(snapshot->dynamic_grants, [&](const auto &grant) {
        return grant.request.definition.canonical_name.view() == name;
      });
  return found == snapshot->dynamic_grants.end() ? nullptr : &*found;
}

ConsentDeltaKind
dynamic_delta(const definitions::DynamicRequest &next,
              const definitions::DynamicRevisionGrant *prior,
              const definitions::CapabilityDefinition &definition,
              definitions::DynamicScopeValidator validator) {
  if (!prior)
    return ConsentDeltaKind::added;
  if (prior->request.definition != next.definition)
    return ConsentDeltaKind::definition_changed;
  if (prior->request.required != next.required)
    return ConsentDeltaKind::requirement_changed;
  if (prior->request.operations != next.operations)
    return ConsentDeltaKind::operations_changed;
  if (prior->request.scope == next.scope)
    return ConsentDeltaKind::unchanged;
  if (!validator.compare)
    return ConsentDeltaKind::incomparable;
  using R = definitions::DynamicScopeRelation;
  const auto relation =
      validator.compare(definition, next.scope.view(),
                        prior->request.scope.view(), validator.context);
  return relation == R::narrower   ? ConsentDeltaKind::narrowed
         : relation == R::expanded ? ConsentDeltaKind::expanded
                                   : ConsentDeltaKind::incomparable;
}

std::string review_fingerprint(const ConsentReview &review,
                               const AuthorityView &view) {
  std::string bytes = "OMARCHY-PLUGIN-CONSENT-REVIEW-V1\0";
  field(bytes, review.candidate_binding.plugin.view());
  field(bytes, review.candidate_binding.revision.view());
  field(bytes, review.verified.request_sha256);
  field(bytes, review.candidate_binding.policy_fingerprint.view());
  number(bytes, review.expected_sequence);
  number(bytes, review.candidate_binding.generation);
  if (view.authority_slots.active) {
    field(bytes, view.authority_slots.active->snapshot_digest.view());
    number(bytes, view.authority_slots.active->generation);
  } else {
    field(bytes, {});
  }
  return plugins::manifest::sha256_hex(bytes);
}

std::optional<ConsentReview>
build_review(const AuthorityView &view, const VerifiedRevision &verified,
             const definitions::TrustedDefinitionRegistry &registry,
             definitions::DynamicScopeValidator validator) {
  try {
    if (view.authority_slots.candidate ||
        view.authority_slots.generation_high_watermark == UINT64_MAX ||
        verified.request_sha256 !=
            plugins::manifest::requested_capability_fingerprint(
                verified.manifest.requests))
      return std::nullopt;
    const auto builtin = permissions::requests_from_manifest(verified.manifest);
    const auto policy_fingerprint =
        permissions::policy_request_fingerprint(builtin);
    std::vector<std::pair<permissions::CapabilityKey, std::string_view>>
        builtin_sources;
    std::size_t builtin_index = 0;
    for (const auto &source : verified.manifest.requests) {
      if (source.definition_generation == 0)
        builtin_sources.emplace_back(builtin[builtin_index++].capability,
                                     source.reason);
    }
    const auto dynamic = dynamic_requests(verified.manifest, registry);
    if (dynamic.size() !=
        static_cast<std::size_t>(std::ranges::count_if(
            verified.manifest.requests, [](const auto &request) {
              return request.definition_generation > 0;
            })))
      return std::nullopt;
    ConsentReview review{.verified = verified,
                         .fingerprint = {},
                         .expected_sequence = view.authority_slots.sequence,
                         .candidate_binding =
                             {.plugin = permissions::PluginId(
                                  verified.manifest.id),
                              .revision =
                                  permissions::Digest(verified.tree_sha256),
                              .policy_fingerprint =
                                  permissions::Digest(policy_fingerprint),
                              .generation =
                                  view.authority_slots
                                          .generation_high_watermark +
                                      1},
                         .builtin_rows = {},
                         .dynamic_rows = {}};

    permissions::DeltaSet deltas;
    if (view.active) {
      deltas = permissions::compute_update_delta(view.active->requests,
                                                 view.active->grants, builtin);
    } else {
      for (const auto &request : builtin.values())
        deltas.push_back({.capability = request.capability,
                          .kind = permissions::DeltaKind::added,
                          .inherited_grant = std::nullopt});
    }
    for (const auto &delta : deltas.values()) {
      const auto current =
          std::ranges::find(builtin.values(), delta.capability,
                            &permissions::CapabilityRequest::capability);
      const auto prior_request =
          view.active
              ? std::ranges::find(view.active->requests.values(),
                                  delta.capability,
                                  &permissions::CapabilityRequest::capability)
              : std::span<const permissions::CapabilityRequest>{}.end();
      const auto prior_grant =
          view.active ? std::ranges::find(view.active->grants.values(),
                                          delta.capability,
                                          &permissions::GrantRecord::capability)
                      : std::span<const permissions::GrantRecord>{}.end();
      const auto source = std::ranges::find(
          builtin_sources, delta.capability,
          &std::pair<permissions::CapabilityKey, std::string_view>::first);
      BuiltinReviewRow row{.publisher_reason =
                               source == builtin_sources.end()
                                   ? std::string{}
                                   : std::string(source->second),
                           .requested = current == builtin.values().end()
                                            ? std::nullopt
                                            : std::optional(*current),
                           .previous_request = std::nullopt,
                           .previous_grant = std::nullopt,
                           .delta = translate(delta.kind)};
      if (view.active && prior_request != view.active->requests.values().end())
        row.previous_request = *prior_request;
      if (view.active && prior_grant != view.active->grants.values().end())
        row.previous_grant = *prior_grant;
      review.builtin_rows.push_back(std::move(row));
    }

    for (const auto &request : dynamic) {
      const auto resolved = registry.resolve(request.definition);
      if (!resolved)
        return std::nullopt;
      const auto manifest_request = std::ranges::find(
          verified.manifest.requests, request.definition.canonical_name.view(),
          &plugins::manifest::CapabilityRequest::capability);
      const auto *prior =
          dynamic_for(view.active, request.definition.canonical_name.view());
      DynamicReviewRow row{
          .publisher_reason = manifest_request->reason,
          .requested = request,
          .previous_request =
              prior ? std::optional(prior->request) : std::nullopt,
          .previous_grant = prior ? std::optional(prior->grant) : std::nullopt,
          .trusted_definition = *resolved->definition,
          .delta =
              dynamic_delta(request, prior, *resolved->definition, validator)};
      review.dynamic_rows.push_back(std::move(row));
    }
    if (view.active) {
      for (const auto &prior : view.active->dynamic_grants) {
        if (std::ranges::any_of(dynamic, [&](const auto &request) {
              return request.definition.canonical_name ==
                     prior.request.definition.canonical_name;
            }))
          continue;
        const auto resolved = registry.resolve(prior.request.definition);
        DynamicReviewRow row{.publisher_reason = {},
                             .requested = std::nullopt,
                             .previous_request = prior.request,
                             .previous_grant = prior.grant,
                             .trusted_definition =
                                 resolved ? std::optional(*resolved->definition)
                                          : std::nullopt,
                             .delta = ConsentDeltaKind::removed};
        review.dynamic_rows.push_back(std::move(row));
      }
    }
    std::ranges::sort(review.builtin_rows, {}, [](const auto &row) {
      const auto &request =
          row.requested ? row.requested : row.previous_request;
      return request->capability;
    });
    std::ranges::sort(review.dynamic_rows, {}, [](const auto &row) {
      const auto &request =
          row.requested ? row.requested : row.previous_request;
      return request->definition.canonical_name;
    });
    review.fingerprint =
        permissions::Digest(review_fingerprint(review, view));
    return review;
  } catch (...) {
    return std::nullopt;
  }
}

permissions::Digest
compute_decision_fingerprint(const ConsentReview &review,
                             std::span<const BuiltinConsentDecision> builtin,
                             std::span<const DynamicConsentDecision> dynamic) {
  std::string bytes = "OMARCHY-PLUGIN-CONSENT-CHOICES-V1\0";
  field(bytes, review.fingerprint.view());
  std::vector<const BuiltinConsentDecision *> sorted_builtin;
  for (const auto &choice : builtin)
    sorted_builtin.push_back(&choice);
  std::ranges::sort(sorted_builtin, {},
                    [](const auto *choice) { return choice->capability; });
  number(bytes, sorted_builtin.size());
  for (const auto *choice : sorted_builtin) {
    field(bytes, choice->capability.id.view());
    number(bytes, choice->capability.version);
    field(bytes, permissions::canonical_scope(choice->decided_scope));
    number(bytes, static_cast<std::uint8_t>(choice->decision));
  }
  std::vector<const DynamicConsentDecision *> sorted_dynamic;
  for (const auto &choice : dynamic)
    sorted_dynamic.push_back(&choice);
  std::ranges::sort(sorted_dynamic, {}, [](const auto *choice) {
    return std::tuple(choice->definition.canonical_name.view(),
                      choice->definition.definition_generation,
                      choice->definition.definition_digest.view());
  });
  number(bytes, sorted_dynamic.size());
  for (const auto *choice : sorted_dynamic) {
    field(bytes, choice->definition.canonical_name.view());
    number(bytes, choice->definition.definition_generation);
    field(bytes, choice->definition.definition_digest.view());
    field(bytes, choice->decided_scope.view());
    number(bytes, choice->operations.size());
    for (const auto &operation : choice->operations.values())
      field(bytes, operation.view());
    number(bytes, static_cast<std::uint8_t>(choice->decision));
  }
  return permissions::Digest(plugins::manifest::sha256_hex(bytes));
}

bool confirmed(const ConsentReview &review,
               const ConsentConfirmation &confirmation,
               const permissions::Digest &choices) {
  return confirmation.review_fingerprint == review.fingerprint &&
         confirmation.decision_fingerprint == choices &&
         confirmation.confirmed_wall_seconds > 0 &&
         (confirmation.actor == permissions::DecisionActor::trusted_ui ||
          confirmation.actor == permissions::DecisionActor::interactive_cli);
}

} // namespace

std::optional<ConsentReview> prepare_consent_review(
    AuthorityStore &store, const VerifiedRevision &verified,
    const definitions::TrustedDefinitionRegistry &definitions,
    definitions::DynamicScopeValidator scope_validator) {
  const auto view = store.read_authority_view();
  return view ? build_review(*view, verified, definitions, scope_validator)
              : std::nullopt;
}

permissions::Digest consent_decision_fingerprint(
    const ConsentReview &review,
    std::span<const BuiltinConsentDecision> builtin_decisions,
    std::span<const DynamicConsentDecision> dynamic_decisions) {
  return compute_decision_fingerprint(review, builtin_decisions,
                                      dynamic_decisions);
}

ConsentResult publish_consent_review(
    AuthorityStore &store, const ConsentReview &review,
    const ConsentConfirmation &confirmation,
    std::span<const BuiltinConsentDecision> builtin_decisions,
    std::span<const DynamicConsentDecision> dynamic_decisions,
    const definitions::TrustedDefinitionRegistry &definitions,
    definitions::DynamicScopeValidator scope_validator) {
  try {
    const auto view = store.read_authority_view();
    if (!view)
      return ConsentResult::authority_error;
    if (view->authority_slots.sequence != review.expected_sequence)
      return ConsentResult::stale_authority;
    const auto exact =
        build_review(*view, review.verified, definitions, scope_validator);
    const auto choices = compute_decision_fingerprint(review, builtin_decisions,
                                                      dynamic_decisions);
    if (!exact || exact->fingerprint != review.fingerprint ||
        exact->candidate_binding != review.candidate_binding ||
        !confirmed(*exact, confirmation, choices))
      return ConsentResult::invalid_review;
    auto builtin =
        permissions::requests_from_manifest(review.verified.manifest);
    auto dynamic = dynamic_requests(review.verified.manifest, definitions);
    if (builtin_decisions.size() != builtin.size() ||
        dynamic_decisions.size() != dynamic.size())
      return ConsentResult::incomplete_decisions;
    const auto binding = review.candidate_binding;
    policy::GrantSnapshot snapshot{
        .binding = binding,
        .source_request_fingerprint =
            permissions::Digest(review.verified.request_sha256),
        .requests = builtin,
        .grants = {},
        .dynamic_grants = {}};
    for (const auto &request : builtin.values()) {
      if (std::ranges::count(builtin_decisions, request.capability,
                             &BuiltinConsentDecision::capability) != 1)
        return ConsentResult::spoofed_decision;
      const auto &choice =
          *std::ranges::find(builtin_decisions, request.capability,
                             &BuiltinConsentDecision::capability);
      if (choice.decision != permissions::UserDecision::grant &&
          choice.decision != permissions::UserDecision::deny)
        return ConsentResult::spoofed_decision;
      const auto *definition = permissions::find_capability(request.capability);
      if (!definition ||
          !permissions::valid_scope(*definition, choice.decided_scope))
        return ConsentResult::spoofed_decision;
      const auto relation =
          permissions::compare_scope(choice.decided_scope, request.scope);
      if ((choice.decision == permissions::UserDecision::grant &&
           relation != permissions::ScopeRelation::equal &&
           relation != permissions::ScopeRelation::narrower) ||
          (choice.decision == permissions::UserDecision::deny &&
           relation != permissions::ScopeRelation::equal))
        return ConsentResult::spoofed_decision;
      if (request.required &&
          choice.decision != permissions::UserDecision::grant)
        return ConsentResult::required_denied;
      snapshot.grants.push_back(
          {.capability = request.capability,
           .scope = choice.decided_scope,
           .state = choice.decision == permissions::UserDecision::grant
                        ? permissions::GrantState::granted
                        : permissions::GrantState::denied,
           .epoch = review.candidate_binding.generation});
    }
    for (const auto &request : dynamic) {
      if (std::ranges::count(dynamic_decisions, request.definition,
                             &DynamicConsentDecision::definition) != 1)
        return ConsentResult::spoofed_decision;
      const auto &choice =
          *std::ranges::find(dynamic_decisions, request.definition,
                             &DynamicConsentDecision::definition);
      if (choice.decision != permissions::UserDecision::grant &&
          choice.decision != permissions::UserDecision::deny)
        return ConsentResult::spoofed_decision;
      if (choice.decision == permissions::UserDecision::deny &&
          (choice.decided_scope != request.scope ||
           choice.operations != request.operations))
        return ConsentResult::spoofed_decision;
      if (choice.decision == permissions::UserDecision::grant &&
          choice.operations.size() == 0)
        return ConsentResult::spoofed_decision;
      definitions::DynamicGrant grant{
          .definition = request.definition,
          .operations = choice.operations,
          .scope = choice.decided_scope,
          .state = choice.decision == permissions::UserDecision::grant
                       ? permissions::GrantState::granted
                       : permissions::GrantState::denied,
          .epoch = review.candidate_binding.generation};
      if (request.required &&
          choice.decision != permissions::UserDecision::grant)
        return ConsentResult::required_denied;
      definitions::DynamicRevisionGrant revision{
          .binding = binding, .request = request, .grant = std::move(grant)};
      if (!definitions::review_dynamic_grant(definitions, revision,
                                             scope_validator))
        return ConsentResult::spoofed_decision;
      snapshot.dynamic_grants.push_back(std::move(revision));
    }
    std::ranges::sort(snapshot.dynamic_grants, {}, [](const auto &grant) {
      return grant.request.definition.canonical_name;
    });
    const auto result = store.publish_candidate(review.verified, snapshot,
                                                review.expected_sequence,
                                                definitions, scope_validator);
    if (result == AuthorityMutationResult::applied)
      return ConsentResult::applied;
    if (result == AuthorityMutationResult::stale_sequence)
      return ConsentResult::stale_authority;
    return result == AuthorityMutationResult::invalid
               ? ConsentResult::invalid_review
               : ConsentResult::authority_error;
  } catch (...) {
    return ConsentResult::spoofed_decision;
  }
}

} // namespace omarchy::plugin_runtime::host_session
