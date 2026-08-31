#include "plugin_permission_authority.hpp"
#include "session_runtime_factory.hpp"

#include <fcntl.h>

#include <ranges>
#include <utility>

namespace omarchy::plugin_runtime::channel {
namespace {

bool same_revision(const host_session::VerifiedRevision &left,
                   const host_session::VerifiedRevision &right) {
  // The verified tree digest authenticates the complete installed revision;
  // request identity is repeated here to make the consent binding explicit.
  return left.manifest.id == right.manifest.id &&
         left.tree_sha256 == right.tree_sha256 &&
         left.request_sha256 == right.request_sha256;
}

host_session::OwnedDescriptor duplicate_directory(int descriptor) {
  if (descriptor < 0)
    return {};
  return host_session::OwnedDescriptor(
      ::openat(descriptor, ".",
               O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW));
}

} // namespace

std::shared_ptr<PluginPermissionAuthority> PluginPermissionAuthority::open(
    int activation_root_fd, int revision_root_fd, int state_root_fd,
    host_session::OwnedDescriptor authority_root,
    permissions::PluginId expected_plugin, std::uint32_t trusted_uid,
    std::shared_ptr<const definitions::TrustedDefinitionRegistry> definitions,
    std::shared_ptr<const RuntimeServices> services,
    std::string fixed_record_name) {
  if (!definitions || !services)
    return {};
  auto activation_root = duplicate_directory(activation_root_fd);
  auto revision_root = duplicate_directory(revision_root_fd);
  auto state_root = duplicate_directory(state_root_fd);
  if (!activation_root || !revision_root || !state_root || !authority_root)
    return {};
  auto authority = host_session::AuthorityStore::open(
      authority_root.get(), trusted_uid, expected_plugin);
  if (!authority)
    return {};
  const auto authority_identity = authority->root_identity();
  if (!authority_identity)
    return {};
  return std::shared_ptr<PluginPermissionAuthority>(
      new PluginPermissionAuthority(
          std::move(activation_root), std::move(revision_root),
          std::move(state_root), std::move(authority), *authority_identity,
          std::move(expected_plugin), trusted_uid, std::move(definitions),
          std::move(services), std::move(fixed_record_name)));
}

PluginPermissionAuthority::PluginPermissionAuthority(
    host_session::OwnedDescriptor activation_root,
    host_session::OwnedDescriptor revision_root,
    host_session::OwnedDescriptor state_root,
    std::unique_ptr<host_session::AuthorityStore> authority,
    host_session::FilesystemIdentity authority_identity,
    permissions::PluginId expected_plugin, std::uint32_t trusted_uid,
    std::shared_ptr<const definitions::TrustedDefinitionRegistry> definitions,
    std::shared_ptr<const RuntimeServices> services,
    std::string fixed_record_name)
    : activation_root_(std::move(activation_root)),
      revision_root_(std::move(revision_root)),
      state_root_(std::move(state_root)), authority_(std::move(authority)),
      revision_verifier_(trusted_uid),
      activation_source_(activation_root_.get(), revision_root_.get(),
                         state_root_.get(), revision_verifier_, *authority_,
                         authority_identity, std::string(expected_plugin.view()),
                         trusted_uid),
      expected_plugin_(std::move(expected_plugin)),
      definitions_(std::move(definitions)), services_(std::move(services)),
      scope_validator_(runtime_scope_validator(*services_)),
      record_name_(std::move(fixed_record_name)) {}

std::optional<host_session::AuthorityView>
PluginPermissionAuthority::list() const {
  std::scoped_lock lock(mutex_);
  return authority_->read_authority_view();
}

std::shared_ptr<const host_session::ConsentReview>
PluginPermissionAuthority::prepare_review() {
  std::scoped_lock lock(mutex_);
  auto verified = activation_source_.verified_revision(record_name_);
  if (!verified)
    return {};
  auto review = host_session::prepare_consent_review(
      *authority_, *verified, *definitions_, scope_validator_);
  if (!review)
    return {};
  return std::make_shared<const host_session::ConsentReview>(std::move(*review));
}

ReviewedPermissionApplyResult PluginPermissionAuthority::apply_review(
    const host_session::ConsentReview &review,
    const host_session::ConsentConfirmation &confirmation,
    std::span<const host_session::BuiltinConsentDecision> builtin_decisions,
    std::span<const host_session::DynamicConsentDecision> dynamic_decisions,
    host_session::AuthorityFenceObserver *observer) {
  std::scoped_lock lock(mutex_);
  const auto verified = activation_source_.verified_revision(record_name_);
  if (!verified || !same_revision(*verified, review.verified))
    return {};

  ReviewedPermissionApplyResult result;
  try {
    result.binding = review.candidate_binding;
  } catch (...) {
    return result;
  }
  result.publication = host_session::publish_consent_review(
      *authority_, review, confirmation, builtin_decisions, dynamic_decisions,
      *definitions_, scope_validator_);
  if (result.publication != host_session::ConsentResult::applied)
    return {.publication = result.publication,
            .promotion = host_session::AuthorityMutationResult::invalid,
            .binding = std::nullopt};

  result.promotion = authority_->promote_candidate(
      review.candidate_binding, review.expected_sequence + 1, observer);
  if (result.promotion != host_session::AuthorityMutationResult::applied)
    result.binding.reset();
  return result;
}

host_session::AuthorityRevocationResult PluginPermissionAuthority::revoke(
    const permissions::CapabilityKey &capability,
    std::uint64_t expected_sequence,
    host_session::AuthorityFenceObserver *observer) {
  return revoke_exact(capability, expected_sequence, observer);
}

bool PluginPermissionAuthority::provider_available(
    const permissions::CapabilityKey &capability) const noexcept {
  return services_ && runtime_service_available(*services_, capability);
}

bool PluginPermissionAuthority::provider_available(
    const definitions::CapabilityReference &reference) const noexcept {
  return definitions_ && services_ &&
         runtime_service_available(*definitions_, *services_, reference);
}

host_session::AuthorityRevocationResult PluginPermissionAuthority::revoke(
    const definitions::CapabilityReference &definition,
    std::uint64_t expected_sequence,
    host_session::AuthorityFenceObserver *observer) {
  return revoke_exact(definition, expected_sequence, observer);
}

template <typename Selector>
host_session::AuthorityRevocationResult PluginPermissionAuthority::revoke_exact(
    const Selector &selector, std::uint64_t expected_sequence,
    host_session::AuthorityFenceObserver *observer) {
  std::scoped_lock lock(mutex_);
  try {
    return authority_->revoke_active(selector, expected_sequence, observer);
  } catch (...) {
    // AuthorityStore is specified to return a typed failure, but keep the
    // product boundary fail-closed if a future persistence path violates it.
    return {.status = host_session::AuthorityMutationResult::io_error,
            .binding = std::nullopt,
            .activatable = false};
  }
}

host_session::ActivationResult
PluginPermissionAuthority::load_activation() const {
  return activation_source_.load(record_name_);
}

std::optional<host_session::PreparedLiveBinding>
PluginPermissionAuthority::prepare_live_activation(
    const permissions::ActivationBinding &binding,
    const std::shared_ptr<host_session::LiveGenerationState> &live) {
  return authority_->prepare_live_activation(binding, live);
}

bool PluginPermissionAuthority::commit_live_activation(
    host_session::PreparedLiveBinding prepared,
    const permissions::ActivationBinding &expected_binding,
    const std::shared_ptr<host_session::LiveGenerationState> &expected_live) {
  return authority_->commit_live_activation(std::move(prepared),
                                            expected_binding, expected_live);
}

template host_session::AuthorityRevocationResult
PluginPermissionAuthority::revoke_exact(
    const permissions::CapabilityKey &, std::uint64_t,
    host_session::AuthorityFenceObserver *);
template host_session::AuthorityRevocationResult
PluginPermissionAuthority::revoke_exact(
    const definitions::CapabilityReference &, std::uint64_t,
    host_session::AuthorityFenceObserver *);

} // namespace omarchy::plugin_runtime::channel
