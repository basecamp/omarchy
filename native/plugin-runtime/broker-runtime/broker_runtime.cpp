#include "broker_runtime.hpp"

#include "omarchy/plugin_runtime/broker/broker_schema.hpp"

#include <algorithm>
#include <array>
#include <limits>
#include <utility>

namespace omarchy::plugin_runtime::runtime {
namespace {

constexpr std::array kOperations{
    permissions::OperationId::storage_read,
    permissions::OperationId::storage_write,
    permissions::OperationId::storage_remove,
    permissions::OperationId::notification_send,
    permissions::OperationId::audio_play_cue,
    permissions::OperationId::fake_status_list,
    permissions::OperationId::fake_status_acknowledge,
};

std::uint64_t epoch_for(const grant::RevisionGrants &revision,
                        std::string_view capability) {
  for (const auto &record : revision.grants.values()) {
    if (record.capability.version == 1 &&
        record.capability.id.view() == capability)
      return record.epoch;
  }
  return 0;
}

permissions::GrantDecisionCode
handle_denial(permissions::HandleDecision value) {
  switch (value) {
  case permissions::HandleDecision::stale_grant:
    return permissions::GrantDecisionCode::revoked;
  case permissions::HandleDecision::wrong_plugin:
  case permissions::HandleDecision::wrong_revision:
  case permissions::HandleDecision::wrong_policy:
  case permissions::HandleDecision::wrong_generation:
    return permissions::GrantDecisionCode::activation_mismatch;
  case permissions::HandleDecision::outside_scope:
  case permissions::HandleDecision::wrong_operation:
    return permissions::GrantDecisionCode::outside_scope;
  default:
    return permissions::GrantDecisionCode::ungranted;
  }
}

} // namespace

providers::ProviderConfiguration AuditedBrokerRuntime::normalize_configuration(
    const grant::RevisionGrants &revision,
    providers::ProviderConfiguration configuration) {
  configuration.binding = revision.binding;
  configuration.storage_epoch = epoch_for(revision, "storage.private");
  configuration.notification_epoch = epoch_for(revision, "notifications.send");
  configuration.audio_epoch = epoch_for(revision, "audio.play-cue");
  configuration.fake_service_epoch = epoch_for(revision, "service.fake-status");
  return configuration;
}

AuditedBrokerRuntime::GateRegistry::GateRegistry(
    const broker::ProviderRegistry<7> &providers) {
  for (std::size_t index = 0; index < kOperations.size(); ++index) {
    const auto *provider = providers.find(kOperations[index]);
    if (provider == nullptr)
      continue;
    contexts[index].provider = *provider;
    const auto added = registry.add({
        .operation = provider->operation,
        .dispatch = AuditedBrokerRuntime::gate_dispatch,
        .cancel = provider->cancel == nullptr
                      ? nullptr
                      : AuditedBrokerRuntime::gate_cancel,
        .context = &contexts[index],
    });
    if (!added)
      registry = {};
  }
}

AuditedBrokerRuntime::AuditedBrokerRuntime(
    grant::RevisionGrants revision,
    providers::ProviderConfiguration configuration,
    audit::AuditStore &audit_store)
    : revision_(std::move(revision)), binding_(revision_.binding),
      authority_(binding_, revision_.requests, revision_.grants),
      audit_(audit_store),
      providers_(normalize_configuration(revision_, std::move(configuration))),
      provider_registry_(providers_.registry()), gate_(provider_registry_),
      core_(binding_, authority_, gate_.registry, kMaximumRuntimeRequests) {
  for (auto &context : gate_.contexts)
    context.owner = this;
  if (!audit_.recover().ok())
    failed_ = true;
}

broker::ProviderResult
AuditedBrokerRuntime::gate_dispatch(const broker::AuthorizedRequest &request,
                                    std::span<std::byte> response,
                                    void *opaque) noexcept {
  try {
    auto *context = static_cast<GateContext *>(opaque);
    if (context == nullptr || context->owner == nullptr ||
        context->provider.dispatch == nullptr)
      return {};
    auto &self = *context->owner;
    const auto *definition = permissions::find_operation(request.operation);
    if (definition == nullptr)
      return {};
    auto *tracked = self.track(
        request.correlation, request.operation, definition->key, request.demand,
        request.grant_epoch, true, permissions::GrantDecisionCode::allowed);
    if (tracked == nullptr ||
        !self.audit_operation(permissions::AuditOutcome::allowed,
                              request.correlation, request.operation,
                              permissions::GrantDecisionCode::allowed,
                              request.payload.size()))
      return {};
    const auto result = context->provider.dispatch(request, response,
                                                   context->provider.context);
    if (result.status == broker::ProviderStatus::failed) {
      if (!self.audit_operation(permissions::AuditOutcome::failed,
                                request.correlation, request.operation,
                                permissions::GrantDecisionCode::allowed))
        return {};
    }
    return result;
  } catch (...) {
    return {};
  }
}

bool AuditedBrokerRuntime::gate_cancel(std::uint64_t correlation,
                                       void *opaque) noexcept {
  try {
    auto *context = static_cast<GateContext *>(opaque);
    if (context == nullptr || context->owner == nullptr ||
        context->provider.cancel == nullptr)
      return false;
    auto &self = *context->owner;
    auto *tracked = self.find(correlation);
    if (tracked == nullptr ||
        !self.audit_operation(permissions::AuditOutcome::cancelled, correlation,
                              tracked->operation,
                              permissions::GrantDecisionCode::allowed))
      return false;
    tracked->cancel_requested = true;
    return context->provider.cancel(correlation, context->provider.context);
  } catch (...) {
    return false;
  }
}

broker::DispatchResult AuditedBrokerRuntime::dispatch(
    const wire::PacketView &packet, std::uint64_t now_monotonic_ns,
    std::span<std::byte> response, permissions::GestureProof *gesture) {
  if (failed_)
    return {.outcome = broker::DispatchOutcome::core_failed};
  broker::DecodedBrokerRequest decoded{};
  const bool decodable = broker::decode_broker_request(
                             packet.header.message_type, packet.payload,
                             decoded) == broker::BrokerDecodeResult::accepted;
  const auto result =
      core_.dispatch(packet, now_monotonic_ns, response, gesture);
  if (result.outcome == broker::DispatchOutcome::denied && decodable) {
    const auto *definition = permissions::find_operation(decoded.operation);
    if (definition != nullptr) {
      const auto tracked =
          track(packet.header.correlation_id, decoded.operation,
                definition->key, decoded.demand, result.decision.grant_epoch,
                false, result.decision.code);
      if (tracked == nullptr ||
          !audit_operation(permissions::AuditOutcome::denied,
                           packet.header.correlation_id, decoded.operation,
                           result.decision.code,
                           decoded.provider_payload.size()))
        return {.outcome = broker::DispatchOutcome::core_failed};
    }
  } else if ((result.outcome == broker::DispatchOutcome::provider_unavailable ||
              result.outcome == broker::DispatchOutcome::provider_failed) &&
             decodable) {
    if (!audit_operation(permissions::AuditOutcome::failed,
                         packet.header.correlation_id, decoded.operation,
                         result.decision.code, decoded.provider_payload.size()))
      return {.outcome = broker::DispatchOutcome::core_failed};
  } else if (result.outcome == broker::DispatchOutcome::malformed ||
             result.outcome == broker::DispatchOutcome::protocol_fatal ||
             result.outcome == broker::DispatchOutcome::core_failed) {
    const auto operation =
        static_cast<permissions::OperationId>(packet.header.message_type);
    if (packet.header.correlation_id != 0 &&
        permissions::find_operation(operation) != nullptr &&
        !audit_operation(permissions::AuditOutcome::failed,
                         packet.header.correlation_id, operation,
                         permissions::GrantDecisionCode::ungranted))
      return {.outcome = broker::DispatchOutcome::core_failed};
  }
  return result;
}

broker::CancelResult
AuditedBrokerRuntime::accept_cancel(const wire::PacketView &packet) {
  if (failed_)
    return broker::CancelResult::core_failed;
  auto *before = find(packet.header.correlation_id);
  const bool audited_by_gate = before != nullptr && before->cancel_requested;
  const auto result = core_.accept_cancel(packet);
  auto *tracked = find(packet.header.correlation_id);
  if (tracked != nullptr && !audited_by_gate && !tracked->cancel_requested &&
      (result == broker::CancelResult::unsupported ||
       result == broker::CancelResult::accepted)) {
    if (!audit_operation(permissions::AuditOutcome::cancelled,
                         tracked->correlation, tracked->operation,
                         tracked->authorized
                             ? permissions::GrantDecisionCode::allowed
                             : permissions::GrantDecisionCode::ungranted))
      return broker::CancelResult::core_failed;
    tracked->cancel_requested = true;
  }
  if ((result == broker::CancelResult::protocol_fatal ||
       result == broker::CancelResult::core_failed) &&
      tracked != nullptr)
    (void)audit_operation(permissions::AuditOutcome::failed,
                          tracked->correlation, tracked->operation,
                          tracked->decision);
  return result;
}

broker::CancelResult
AuditedBrokerRuntime::accept_cancel_result(const wire::PacketView &packet) {
  if (failed_)
    return broker::CancelResult::core_failed;
  auto *tracked = find(packet.header.correlation_id);
  const auto result = core_.accept_cancel_result(packet);
  if (result == broker::CancelResult::accepted && tracked != nullptr &&
      tracked->terminal_received)
    erase(*tracked);
  else if (result != broker::CancelResult::accepted && tracked != nullptr)
    (void)audit_operation(permissions::AuditOutcome::failed,
                          tracked->correlation, tracked->operation,
                          tracked->decision);
  return result;
}

broker::TerminalResult
AuditedBrokerRuntime::accept_terminal(const wire::PacketView &packet) {
  if (failed_)
    return broker::TerminalResult::core_failed;
  auto *tracked = find(packet.header.correlation_id);
  const auto result = core_.accept_terminal(packet);
  if (result != broker::TerminalResult::accepted || tracked == nullptr) {
    if (tracked != nullptr)
      (void)audit_operation(permissions::AuditOutcome::failed,
                            tracked->correlation, tracked->operation,
                            tracked->decision);
    return result;
  }
  const bool typed_error =
      packet.header.message_type ==
      static_cast<std::uint16_t>(wire::CommonMessageType::typed_error);
  const auto outcome = tracked->cancel_requested
                           ? permissions::AuditOutcome::cancelled
                       : typed_error ? permissions::AuditOutcome::failed
                                     : permissions::AuditOutcome::allowed;
  if (!audit_operation(outcome, tracked->correlation, tracked->operation,
                       tracked->decision))
    return broker::TerminalResult::core_failed;
  if (tracked->cancel_requested)
    tracked->terminal_received = true;
  else
    erase(*tracked);
  return result;
}

RevocationResult AuditedBrokerRuntime::apply_revocation(
    const grant::RevocationResult &revocation) {
  RevocationResult result;
  const auto *definition =
      permissions::find_capability(revocation.grant.capability);
  const auto *current = grant_for(revocation.grant.capability);
  if (failed_ || revocation.target != grant::TargetRevision::active ||
      definition == nullptr || current == nullptr ||
      revocation.grant.state != permissions::GrantState::revoked ||
      current->epoch == std::numeric_limits<std::uint64_t>::max() ||
      revocation.grant.epoch != current->epoch + 1 ||
      revocation.action != definition->revocation) {
    result.status = RuntimeStatus::binding_mismatch;
    return result;
  }
  if (!audit_capability(permissions::AuditEvent::capability_revoked,
                        permissions::AuditOutcome::denied,
                        revocation.grant.capability,
                        permissions::GrantDecisionCode::revoked)) {
    result.status = RuntimeStatus::audit_failed;
    return result;
  }
  const auto plan = core_.revoke(revocation.grant.capability);
  if (!plan.accepted || plan.new_epoch != revocation.grant.epoch ||
      plan.restart_worker != (definition->revocation ==
                              permissions::RevocationMode::restart_worker)) {
    failed_ = true;
    result.status = RuntimeStatus::failed;
    return result;
  }
  for (std::size_t index = 0; index < plan.cancel_count; ++index) {
    auto *tracked = find(plan.cancel_correlations[index]);
    if (tracked == nullptr ||
        !audit_operation(permissions::AuditOutcome::cancelled,
                         tracked->correlation, tracked->operation,
                         permissions::GrantDecisionCode::revoked)) {
      result.status = RuntimeStatus::audit_failed;
      return result;
    }
    tracked->cancel_requested = true;
  }
  const auto cancelled =
      providers_.revoke(revocation.grant.capability, revocation.grant.epoch);
  if (cancelled != plan.cancel_count) {
    failed_ = true;
    result.status = RuntimeStatus::failed;
    return result;
  }
  for (auto &record : revision_.grants.values()) {
    if (record.capability == revocation.grant.capability) {
      record = revocation.grant;
      break;
    }
  }
  result.status = RuntimeStatus::accepted;
  result.cancelled_count = plan.cancel_count;
  std::copy_n(plan.cancel_correlations.begin(), plan.cancel_count,
              result.cancelled.begin());
  result.restart_worker = plan.restart_worker;
  return result;
}

RuntimeStatus AuditedBrokerRuntime::shutdown() {
  if (shutdown_)
    return shutdown_audited_ ? RuntimeStatus::accepted
                             : RuntimeStatus::audit_failed;
  shutdown_ = true;
  failed_ = true;

  bool audited = true;
  for (auto &request : requests_) {
    if (!request.occupied || !request.authorized)
      continue;
    if (!audit_operation(permissions::AuditOutcome::cancelled,
                         request.correlation, request.operation,
                         permissions::GrantDecisionCode::activation_mismatch)) {
      audited = false;
      continue;
    }
    request.cancel_requested = true;
  }
  if (!audited)
    shutdown_audited_ = false;
  if (!audited)
    return RuntimeStatus::audit_failed;

  for (const auto &grant : revision_.grants.values()) {
    if (grant.state != permissions::GrantState::granted ||
        grant.epoch == std::numeric_limits<std::uint64_t>::max())
      continue;
    (void)providers_.revoke(grant.capability, grant.epoch + 1);
  }
  return RuntimeStatus::accepted;
}

HandleResult AuditedBrokerRuntime::issue_handle(
    const permissions::HandleId &id, std::uint64_t correlation,
    permissions::OperationId operation, const permissions::Scope &scope,
    std::uint64_t expires_monotonic_ns) {
  auto *tracked = find(correlation);
  const auto deny = [&](permissions::HandleDecision decision) {
    if (!audit_handle(permissions::AuditEvent::handle_denied,
                      permissions::AuditOutcome::denied, correlation, operation,
                      handle_denial(decision)))
      return HandleResult{RuntimeStatus::audit_failed, decision};
    return HandleResult{RuntimeStatus::denied, decision};
  };
  if (failed_ || tracked == nullptr || !tracked->authorized ||
      tracked->operation != operation)
    return deny(permissions::HandleDecision::invalid);
  const auto *current = grant_for(tracked->capability);
  const auto relation = permissions::compare_scope(scope, tracked->demand);
  if (current == nullptr ||
      current->state != permissions::GrantState::granted ||
      current->epoch != tracked->grant_epoch ||
      (relation != permissions::ScopeRelation::equal &&
       relation != permissions::ScopeRelation::narrower))
    return deny(permissions::HandleDecision::stale_grant);
  if (std::any_of(
          handle_ids_.begin(), handle_ids_.end(),
          [&](const auto &value) { return value.has_value() && *value == id; }))
    return deny(permissions::HandleDecision::duplicate);
  const auto free =
      std::find(handle_ids_.begin(), handle_ids_.end(), std::nullopt);
  if (free == handle_ids_.end())
    return deny(permissions::HandleDecision::table_full);
  permissions::HandleRecord record{
      .id = id,
      .plugin = binding_.plugin,
      .revision = binding_.revision,
      .policy_fingerprint = binding_.policy_fingerprint,
      .generation = binding_.generation,
      .operation = operation,
      .scope = scope,
      .grant_epoch = tracked->grant_epoch,
      .expires_monotonic_ns = expires_monotonic_ns};
  if (!permissions::valid_handle_record(record))
    return deny(permissions::HandleDecision::invalid);
  if (!audit_handle(permissions::AuditEvent::handle_issued,
                    permissions::AuditOutcome::allowed, correlation, operation,
                    permissions::GrantDecisionCode::allowed))
    return {RuntimeStatus::audit_failed, permissions::HandleDecision::invalid};
  const auto decision = handles_.issue(std::move(record));
  if (decision != permissions::HandleDecision::allowed) {
    failed_ = true;
    return {RuntimeStatus::failed, decision};
  }
  *free = id;
  return {RuntimeStatus::accepted, decision};
}

HandleResult AuditedBrokerRuntime::resolve_handle(
    const permissions::HandleId &id, std::uint64_t audit_correlation,
    permissions::OperationId operation, const permissions::Scope &scope,
    std::uint64_t now_monotonic_ns) {
  if (failed_ || core_.failed())
    return {RuntimeStatus::audit_failed, permissions::HandleDecision::invalid};
  const auto *definition = permissions::find_operation(operation);
  const auto *grant =
      definition == nullptr ? nullptr : grant_for(definition->key);
  const auto decision = grant == nullptr
                            ? permissions::HandleDecision::invalid
                            : handles_.resolve(id, binding_, operation, scope,
                                               grant->epoch, now_monotonic_ns);
  if (decision == permissions::HandleDecision::allowed)
    return {RuntimeStatus::accepted, decision};
  if (!audit_handle(permissions::AuditEvent::handle_denied,
                    permissions::AuditOutcome::denied, audit_correlation,
                    operation, handle_denial(decision)))
    return {RuntimeStatus::audit_failed, decision};
  return {RuntimeStatus::denied, decision};
}

bool AuditedBrokerRuntime::add_fake_status(std::uint32_t resource,
                                           std::uint32_t status,
                                           std::string_view text) noexcept {
  return !failed_ && providers_.add_fake_status(resource, status, text);
}

providers::CompletionResult
AuditedBrokerRuntime::complete_fake_list(std::uint64_t correlation,
                                         std::span<std::byte> output,
                                         std::size_t &bytes_written) {
  bytes_written = 0;
  auto *tracked = find(correlation);
  if (failed_)
    return providers::CompletionResult::cancelled;
  if (tracked == nullptr || output.size() < kMaximumFakeResultBytes)
    return providers::CompletionResult::output_too_small;
  std::array<std::byte, kMaximumFakeResultBytes> scratch{};
  std::size_t written = 0;
  const auto completion =
      providers_.complete_fake_list(correlation, scratch, written);
  if (completion == providers::CompletionResult::completed) {
    if (!audit_operation(permissions::AuditOutcome::allowed, correlation,
                         tracked->operation,
                         permissions::GrantDecisionCode::allowed, 0, written))
      return providers::CompletionResult::cancelled;
    std::copy_n(scratch.begin(), written, output.begin());
    bytes_written = written;
  }
  return completion;
}

bool AuditedBrokerRuntime::audit_operation(
    permissions::AuditOutcome outcome, std::uint64_t correlation,
    permissions::OperationId operation, permissions::GrantDecisionCode decision,
    std::size_t request_bytes, std::size_t response_bytes) {
  const auto *definition = permissions::find_operation(operation);
  if (definition == nullptr || correlation == 0) {
    failed_ = true;
    return false;
  }
  permissions::AuditDraft draft{.event =
                                    permissions::AuditEvent::operation_decided,
                                .outcome = outcome,
                                .plugin = binding_.plugin,
                                .revision = binding_.revision,
                                .generation = binding_.generation,
                                .correlation = correlation,
                                .operation = operation,
                                .capability = definition->key,
                                .decision = decision,
                                .metadata = {}};
  if (request_bytes > 0)
    draft.metadata.push_back({permissions::AuditMetric::request_bytes,
                              static_cast<std::int64_t>(request_bytes)});
  if (response_bytes > 0)
    draft.metadata.push_back({permissions::AuditMetric::response_bytes,
                              static_cast<std::int64_t>(response_bytes)});
  const auto appended =
      audit_.append(permissions::AuditProducer::broker, std::move(draft));
  if (!appended.status.ok())
    failed_ = true;
  return appended.status.ok();
}

bool AuditedBrokerRuntime::audit_capability(
    permissions::AuditEvent event, permissions::AuditOutcome outcome,
    const permissions::CapabilityKey &capability,
    permissions::GrantDecisionCode decision) {
  permissions::AuditDraft draft{.event = event,
                                .outcome = outcome,
                                .plugin = binding_.plugin,
                                .revision = binding_.revision,
                                .generation = binding_.generation,
                                .correlation = 0,
                                .operation = std::nullopt,
                                .capability = capability,
                                .decision = decision,
                                .metadata = {}};
  const auto appended =
      audit_.append(permissions::AuditProducer::broker, std::move(draft));
  if (!appended.status.ok())
    failed_ = true;
  return appended.status.ok();
}

bool AuditedBrokerRuntime::audit_handle(
    permissions::AuditEvent event, permissions::AuditOutcome outcome,
    std::uint64_t correlation, permissions::OperationId operation,
    permissions::GrantDecisionCode decision) {
  const auto *definition = permissions::find_operation(operation);
  if (definition == nullptr || correlation == 0) {
    failed_ = true;
    return false;
  }
  permissions::AuditDraft draft{.event = event,
                                .outcome = outcome,
                                .plugin = binding_.plugin,
                                .revision = binding_.revision,
                                .generation = binding_.generation,
                                .correlation = correlation,
                                .operation = operation,
                                .capability = definition->key,
                                .decision = decision,
                                .metadata = {}};
  const auto appended =
      audit_.append(permissions::AuditProducer::broker, std::move(draft));
  if (!appended.status.ok())
    failed_ = true;
  return appended.status.ok();
}

AuditedBrokerRuntime::TrackedRequest *
AuditedBrokerRuntime::find(std::uint64_t correlation) {
  for (auto &request : requests_) {
    if (request.occupied && request.correlation == correlation)
      return &request;
  }
  return nullptr;
}

AuditedBrokerRuntime::TrackedRequest *AuditedBrokerRuntime::track(
    std::uint64_t correlation, permissions::OperationId operation,
    const permissions::CapabilityKey &capability,
    const permissions::Scope &demand, std::uint64_t grant_epoch,
    bool authorized, permissions::GrantDecisionCode decision) {
  if (correlation == 0)
    return nullptr;
  if (auto *existing = find(correlation); existing != nullptr)
    return existing;
  for (auto &request : requests_) {
    if (!request.occupied) {
      request = {.correlation = correlation,
                 .operation = operation,
                 .capability = capability,
                 .demand = demand,
                 .grant_epoch = grant_epoch,
                 .decision = decision,
                 .authorized = authorized,
                 .cancel_requested = false,
                 .terminal_received = false,
                 .occupied = true};
      return &request;
    }
  }
  return nullptr;
}

void AuditedBrokerRuntime::erase(TrackedRequest &request) { request = {}; }

const permissions::GrantRecord *AuditedBrokerRuntime::grant_for(
    const permissions::CapabilityKey &capability) const {
  for (const auto &record : revision_.grants.values()) {
    if (record.capability == capability)
      return &record;
  }
  return nullptr;
}

} // namespace omarchy::plugin_runtime::runtime
