#include "structured_broker.hpp"

#include "omarchy/plugin_runtime/broker/broker_schema.hpp"

#include <algorithm>
#include <stdexcept>

namespace omarchy::plugin_runtime::host_session {
class BrokerInstanceOrigin final {
  BrokerInstanceOrigin() = default;
  friend class StructuredBroker;
};

namespace {

thread_local const StructuredBroker *active_dispatch = nullptr;

class DispatchScope final {
public:
  explicit DispatchScope(const StructuredBroker &broker) noexcept
      : previous_(std::exchange(active_dispatch, &broker)) {}
  ~DispatchScope() { active_dispatch = previous_; }

private:
  const StructuredBroker *previous_ = nullptr;
};

permissions::GrantDecisionCode
dynamic_decision_code(definitions::DynamicDecision decision) {
  switch (decision) {
  case definitions::DynamicDecision::allowed:
    return permissions::GrantDecisionCode::allowed;
  case definitions::DynamicDecision::revoked:
    return permissions::GrantDecisionCode::revoked;
  case definitions::DynamicDecision::scope_expanded:
    return permissions::GrantDecisionCode::outside_scope;
  case definitions::DynamicDecision::operation_undeclared:
    return permissions::GrantDecisionCode::capability_undeclared;
  case definitions::DynamicDecision::operation_ungranted:
    return permissions::GrantDecisionCode::ungranted;
  case definitions::DynamicDecision::gesture_missing:
    return permissions::GrantDecisionCode::gesture_missing;
  case definitions::DynamicDecision::unknown_definition:
  case definitions::DynamicDecision::stale_definition:
  case definitions::DynamicDecision::denied:
  case definitions::DynamicDecision::adapter_mismatch:
    return permissions::GrantDecisionCode::ungranted;
  }
  return permissions::GrantDecisionCode::ungranted;
}

} // namespace

AdmittedBrokerRequest::AdmittedBrokerRequest(
    wire::PacketView packet, permissions::ActivationBinding binding,
    std::uint64_t session_nonce,
    std::shared_ptr<const BrokerInstanceOrigin> origin)
    : header_(packet.header), payload_size_(packet.payload.size()),
      binding_(std::move(binding)), session_nonce_(session_nonce),
      origin_(std::move(origin)), available_(true) {
  if (payload_size_ > payload_.size() || origin_ == nullptr)
    throw std::invalid_argument("admitted broker request is not bounded");
  std::ranges::copy(packet.payload, payload_.begin());
}

AdmittedBrokerRequest::AdmittedBrokerRequest(
    AdmittedBrokerRequest &&other) noexcept
    : header_(other.header_), payload_size_(other.payload_size_),
      binding_(std::move(other.binding_)),
      session_nonce_(other.session_nonce_), origin_(std::move(other.origin_)),
      available_(other.available_) {
  std::copy_n(other.payload_.begin(), payload_size_, payload_.begin());
  other.consume();
}

wire::PacketView AdmittedBrokerRequest::packet() const noexcept {
  return {.header = header_,
          .payload = std::span(payload_).first(payload_size_)};
}

void AdmittedBrokerRequest::consume() noexcept {
  header_ = {};
  payload_size_ = 0;
  binding_ = {};
  session_nonce_ = 0;
  origin_.reset();
  available_ = false;
}

AuthenticatedBrokerAdmission::AuthenticatedBrokerAdmission(
    permissions::ActivationBinding binding,
    std::uint64_t session_nonce,
    std::shared_ptr<const BrokerInstanceOrigin> origin) noexcept
    : binding_(std::move(binding)), session_nonce_(session_nonce),
      origin_(std::move(origin)) {}

AdmissionResult
AuthenticatedBrokerAdmission::admit(const wire::PacketView &packet) {
  if (packet.header.magic != wire::kMagic ||
      packet.header.envelope_version != wire::kEnvelopeVersion ||
      packet.header.header_size != wire::kHeaderSize ||
      packet.header.flags != 0 || packet.header.reserved != 0)
    return {.request = std::nullopt,
            .failure = AdmissionFailure::noncanonical_header};
  if (session_nonce_ == 0 || origin_ == nullptr ||
      packet.header.endpoint_role != wire::EndpointRole::broker)
    return {.request = std::nullopt, .failure = AdmissionFailure::wrong_role};
  if (packet.header.role_protocol_version != broker::kBrokerRoleVersion)
    return {.request = std::nullopt,
            .failure = AdmissionFailure::wrong_version};
  if (packet.header.launch_generation != binding_.generation)
    return {.request = std::nullopt,
            .failure = AdmissionFailure::stale_binding};
  if (packet.header.payload_length != packet.payload.size() ||
      packet.payload.size() > wire::payload_cap(wire::EndpointRole::broker))
    return {.request = std::nullopt,
            .failure = AdmissionFailure::malformed_length};
  if (packet.header.correlation_id == 0)
    return {.request = std::nullopt,
            .failure = AdmissionFailure::invalid_correlation};
  if (packet.header.correlation_id <= last_correlation_)
    return {.request = std::nullopt, .failure = AdmissionFailure::replay};
  last_correlation_ = packet.header.correlation_id;
  return {.request =
              AdmittedBrokerRequest(packet, binding_, session_nonce_, origin_),
          .failure = AdmissionFailure::none};
}

BrokerTransaction::BrokerTransaction(BrokerTransaction &&other) noexcept
    : state_(other.state_), reply_kind_(other.reply_kind_), fatal_(other.fatal_),
      route_(other.route_), correlation_(other.correlation_),
      message_type_(other.message_type_), payload_size_(other.payload_size_),
      provider_response_bytes_(other.provider_response_bytes_),
      binding_(std::move(other.binding_)), session_nonce_(other.session_nonce_),
      origin_(std::move(other.origin_)), settled_(other.settled_) {
  std::copy_n(other.payload_.begin(), payload_size_, payload_.begin());
  other.consume();
}

void BrokerTransaction::consume() noexcept {
  state_ = TransactionState::fatal;
  reply_kind_ = ReplyKind::provider_failed;
  fatal_ = DispatchFatal::runtime_failed;
  route_ = Route::none;
  correlation_ = 0;
  message_type_ = 0;
  payload_size_ = 0;
  provider_response_bytes_ = 0;
  binding_ = {};
  session_nonce_ = 0;
  origin_.reset();
  settled_ = true;
}

BrokerTransaction
BrokerTransaction::fatal_result(DispatchFatal fatal,
                                std::uint64_t correlation) noexcept {
  BrokerTransaction result;
  result.state_ = TransactionState::fatal;
  result.fatal_ = fatal;
  result.route_ = Route::none;
  result.correlation_ = correlation;
  result.message_type_ = 0;
  result.payload_size_ = 0;
  result.provider_response_bytes_ = 0;
  result.settled_ = true;
  return result;
}

BrokerTransaction BrokerTransaction::reply_result(
    Route route, ReplyKind kind, std::uint64_t correlation,
    std::uint16_t message_type, std::span<const std::byte> wire_payload,
    std::size_t provider_response_bytes,
    permissions::ActivationBinding binding, std::uint64_t session_nonce,
    std::shared_ptr<const BrokerInstanceOrigin> origin) {
  if (route == Route::none || correlation == 0 || message_type == 0 ||
      wire_payload.size() > kMaximumOwnedBrokerReplyBytes ||
      (kind != ReplyKind::result && provider_response_bytes != 0) ||
      session_nonce == 0 || origin == nullptr)
    return fatal_result(DispatchFatal::runtime_failed, correlation);
  BrokerTransaction result;
  result.state_ = TransactionState::reply;
  result.reply_kind_ = kind;
  result.fatal_ = DispatchFatal::none;
  result.route_ = route;
  result.correlation_ = correlation;
  result.message_type_ = message_type;
  std::ranges::copy(wire_payload, result.payload_.begin());
  result.payload_size_ = wire_payload.size();
  result.provider_response_bytes_ = provider_response_bytes;
  result.binding_ = std::move(binding);
  result.session_nonce_ = session_nonce;
  result.origin_ = std::move(origin);
  result.settled_ = false;
  return result;
}

StructuredBroker::StructuredBroker(permissions::ActivationBinding binding,
                                   std::uint64_t session_nonce,
                                   runtime::AuditedBrokerRuntime &builtin,
                                   runtime::DynamicBrokerRuntime &dynamic,
                                   DispatchAuthority &authority)
    : binding_(std::move(binding)), session_nonce_(session_nonce),
      origin_(std::shared_ptr<const BrokerInstanceOrigin>(
          new BrokerInstanceOrigin)),
      builtin_(builtin), dynamic_(dynamic), authority_(authority) {
  if (session_nonce_ == 0 || builtin_.binding() != binding_)
    throw std::invalid_argument(
        "broker runtimes do not match the admitted activation");
  // N4B must add an exact DynamicBrokerRuntime activation-binding accessor so
  // this constructor can reject a route set reconstructed for another plugin
  // or generation. Dynamic updates are still fail-closed below, but dispatch
  // cannot distinguish a runtime-wide binding mismatch from an ordinary
  // dynamic denial until that accessor exists.
}

AdmissionExtractionResult StructuredBroker::take_admission() {
  if (admission_extracted_.exchange(true))
    return {.admission = std::nullopt,
            .failure = AdmissionExtractionFailure::already_extracted};
  return {.admission = AuthenticatedBrokerAdmission(binding_, session_nonce_,
                                                     origin_),
          .failure = AdmissionExtractionFailure::none};
}

bool StructuredBroker::owns(
    const BrokerTransaction &transaction) const noexcept {
  return transaction.origin_ == origin_ && transaction.binding_ == binding_ &&
         transaction.session_nonce_ == session_nonce_;
}

BrokerTransaction
StructuredBroker::dispatch(AdmittedBrokerRequest &&request,
                           std::uint64_t now_monotonic_ns,
                           std::span<std::byte> provider_response,
                           permissions::GestureProof *builtin_gesture,
                           runtime::DynamicGestureAuthority *dynamic_gesture) {
  if (!request.available_)
    return BrokerTransaction::fatal_result(DispatchFatal::admission_reused);
  if (request.origin_ != origin_ || request.binding_ != binding_ ||
      request.session_nonce_ != session_nonce_)
    return BrokerTransaction::fatal_result(DispatchFatal::identity_mismatch);
  const auto packet = request.packet();
  const auto admitted_binding = request.binding_;
  const auto admitted_nonce = request.session_nonce_;
  request.consume();
  if (failed_.load())
    return BrokerTransaction::fatal_result(DispatchFatal::runtime_failed,
                                           packet.header.correlation_id);
  if (admitted_binding != binding_ || admitted_nonce != session_nonce_ ||
      packet.header.launch_generation != binding_.generation)
    return BrokerTransaction::fatal_result(DispatchFatal::identity_mismatch,
                                           packet.header.correlation_id);

  std::unique_ptr<DispatchAuthorityLease> lease;
  try {
    lease = authority_.acquire(binding_, session_nonce_, packet);
  } catch (...) {
    fail_closed();
    return BrokerTransaction::fatal_result(DispatchFatal::runtime_failed,
                                           packet.header.correlation_id);
  }
  if (!lease || !lease->current_at_effect())
    return BrokerTransaction::fatal_result(DispatchFatal::authority_stale,
                                           packet.header.correlation_id);
  DispatchScope dispatch_scope(*this);
  try {
    if (packet.header.message_type == broker::kDynamicInvokeMessage)
      return dispatch_dynamic(packet, provider_response, dynamic_gesture);
    return dispatch_builtin(packet, now_monotonic_ns, provider_response,
                            builtin_gesture);
  } catch (...) {
    fail_closed();
    return BrokerTransaction::fatal_result(DispatchFatal::runtime_failed,
                                           packet.header.correlation_id);
  }
}

BrokerTransaction
StructuredBroker::dispatch_builtin(const wire::PacketView &packet,
                                   std::uint64_t now_monotonic_ns,
                                   std::span<std::byte> provider_response,
                                   permissions::GestureProof *gesture) {
  const auto result =
      builtin_.dispatch(packet, now_monotonic_ns, provider_response, gesture);
  switch (result.outcome) {
  case broker::DispatchOutcome::dispatched:
    if (result.response_bytes > provider_response.size())
      return BrokerTransaction::fatal_result(DispatchFatal::runtime_failed,
                                             packet.header.correlation_id);
    return BrokerTransaction::reply_result(
        BrokerTransaction::Route::builtin, ReplyKind::result,
        packet.header.correlation_id, broker::kBrokerResultMessage,
        std::span<const std::byte>(provider_response)
            .first(result.response_bytes),
        result.response_bytes, binding_, session_nonce_, origin_);
  case broker::DispatchOutcome::denied: {
    const auto error =
        typed_error(packet, ReplyKind::denied, result.decision.code);
    return BrokerTransaction::reply_result(
        BrokerTransaction::Route::builtin, ReplyKind::denied,
        packet.header.correlation_id,
        static_cast<std::uint16_t>(wire::CommonMessageType::typed_error), error,
        0, binding_, session_nonce_, origin_);
  }
  case broker::DispatchOutcome::provider_unavailable: {
    const auto error = typed_error(packet, ReplyKind::provider_unavailable,
                                   result.decision.code);
    return BrokerTransaction::reply_result(
        BrokerTransaction::Route::builtin, ReplyKind::provider_unavailable,
        packet.header.correlation_id,
        static_cast<std::uint16_t>(wire::CommonMessageType::typed_error), error,
        0, binding_, session_nonce_, origin_);
  }
  case broker::DispatchOutcome::provider_failed: {
    const auto error =
        typed_error(packet, ReplyKind::provider_failed, result.decision.code);
    return BrokerTransaction::reply_result(
        BrokerTransaction::Route::builtin, ReplyKind::provider_failed,
        packet.header.correlation_id,
        static_cast<std::uint16_t>(wire::CommonMessageType::typed_error), error,
        0, binding_, session_nonce_, origin_);
  }
  case broker::DispatchOutcome::pending:
    fail_closed();
    return BrokerTransaction::fatal_result(DispatchFatal::pending_unsupported,
                                           packet.header.correlation_id);
  case broker::DispatchOutcome::malformed:
    return BrokerTransaction::fatal_result(DispatchFatal::malformed,
                                           packet.header.correlation_id);
  case broker::DispatchOutcome::protocol_fatal:
    return BrokerTransaction::fatal_result(DispatchFatal::protocol,
                                           packet.header.correlation_id);
  case broker::DispatchOutcome::core_failed:
  case broker::DispatchOutcome::core_busy:
    return BrokerTransaction::fatal_result(DispatchFatal::runtime_failed,
                                           packet.header.correlation_id);
  }
  return BrokerTransaction::fatal_result(DispatchFatal::runtime_failed,
                                         packet.header.correlation_id);
}

BrokerTransaction
StructuredBroker::dispatch_dynamic(const wire::PacketView &packet,
                                   std::span<std::byte> provider_response,
                                   runtime::DynamicGestureAuthority *gesture) {
  const auto result =
      dynamic_.dispatch(packet, binding_, provider_response, gesture);
  if (dynamic_.failed())
    return BrokerTransaction::fatal_result(DispatchFatal::runtime_failed,
                                           packet.header.correlation_id);
  if (result.outcome == definitions::DynamicDispatchResult::dispatched) {
    if (result.response_bytes > provider_response.size())
      return BrokerTransaction::fatal_result(DispatchFatal::runtime_failed,
                                             packet.header.correlation_id);
    return BrokerTransaction::reply_result(
        BrokerTransaction::Route::dynamic, ReplyKind::result,
        packet.header.correlation_id, broker::kBrokerResultMessage,
        std::span<const std::byte>(provider_response)
            .first(result.response_bytes),
        result.response_bytes, binding_, session_nonce_, origin_);
  }
  if (result.outcome == definitions::DynamicDispatchResult::denied) {
    const auto error = typed_error(packet, ReplyKind::denied,
                                   dynamic_decision_code(result.decision));
    return BrokerTransaction::reply_result(
        BrokerTransaction::Route::dynamic, ReplyKind::denied,
        packet.header.correlation_id,
        static_cast<std::uint16_t>(wire::CommonMessageType::typed_error), error,
        0, binding_, session_nonce_, origin_);
  }
  if (result.outcome == definitions::DynamicDispatchResult::adapter_failed) {
    const auto error = typed_error(packet, ReplyKind::provider_failed,
                                   dynamic_decision_code(result.decision));
    return BrokerTransaction::reply_result(
        BrokerTransaction::Route::dynamic, ReplyKind::provider_failed,
        packet.header.correlation_id,
        static_cast<std::uint16_t>(wire::CommonMessageType::typed_error), error,
        0, binding_, session_nonce_, origin_);
  }
  if (result.outcome == definitions::DynamicDispatchResult::stale_activation)
    return BrokerTransaction::fatal_result(DispatchFatal::identity_mismatch,
                                           packet.header.correlation_id);
  return BrokerTransaction::fatal_result(DispatchFatal::malformed,
                                         packet.header.correlation_id);
}

bool StructuredBroker::commit_sent(BrokerTransaction &&transaction) {
  if (!owns(transaction) || transaction.state_ != TransactionState::reply ||
      transaction.settled_)
    return false;
  if (failed_.load()) {
    transaction.consume();
    return false;
  }
  transaction.settled_ = true;
  if (transaction.route_ == BrokerTransaction::Route::dynamic) {
    transaction.consume();
    return true;
  }
  if (transaction.route_ != BrokerTransaction::Route::builtin) {
    transaction.consume();
    return false;
  }
  const auto payload = transaction.wire_payload();
  const wire::PacketView terminal{
      .header = {.endpoint_role = wire::EndpointRole::broker,
                 .message_type = transaction.message_type_,
                 .role_protocol_version = broker::kBrokerRoleVersion,
                 .payload_length = static_cast<std::uint32_t>(payload.size()),
                 .launch_generation = binding_.generation,
                 .correlation_id = transaction.correlation_},
      .payload = payload};
  transaction.consume();
  try {
    if (builtin_.accept_terminal(terminal) ==
        broker::TerminalResult::accepted)
      return true;
  } catch (...) {
  }
  fail_closed();
  return false;
}

bool StructuredBroker::abort_send(BrokerTransaction &&transaction) {
  if (!owns(transaction) || transaction.state_ != TransactionState::reply ||
      transaction.settled_)
    return false;
  if (failed_.load()) {
    transaction.consume();
    return false;
  }
  transaction.settled_ = true;
  if (transaction.route_ == BrokerTransaction::Route::builtin) {
    transaction.consume();
    try {
      if (builtin_.shutdown() == runtime::RuntimeStatus::accepted)
        return true;
    } catch (...) {
    }
    fail_closed();
    return false;
  }
  transaction.consume();
  // DynamicBrokerRuntime has no shutdown/fail-stop entry point yet. Returning
  // false requires the session owner to terminate the entire channel.
  failed_.store(true);
  return false;
}

runtime::RevocationResult StructuredBroker::apply_builtin_revocation(
    const policy::Revocation &revocation) {
  // A provider holds a DispatchAuthorityLease. Waiting for that same lease on
  // its thread would deadlock, so reentrant revocation is rejected immediately.
  if (failed_.load() || active_dispatch == this)
    return {.status = runtime::RuntimeStatus::binding_mismatch};
  if (!authority_.fence_builtin(revocation))
    return {.status = runtime::RuntimeStatus::binding_mismatch};
  try {
    return builtin_.apply_revocation(revocation);
  } catch (...) {
    fail_closed();
    return {.status = runtime::RuntimeStatus::failed};
  }
}

bool StructuredBroker::apply_dynamic_update(
    const definitions::DynamicRevisionGrant &updated) {
  if (failed_.load() || active_dispatch == this ||
      !authority_.fence_dynamic(updated))
    return false;
  try {
    // DynamicBrokerRuntime does not expose its exact activation binding yet;
    // N4B owns that accessor. The runtime still validates the updated grant,
    // and any false/throw here fail-closes this broker instance.
    if (dynamic_.apply_reconstructed_update(updated))
      return true;
  } catch (...) {
  }
  fail_closed();
  return false;
}

void StructuredBroker::fail_closed() noexcept {
  failed_.store(true);
  try {
    (void)builtin_.shutdown();
  } catch (...) {
    // A violated noexcept dynamic adapter cannot be contained; C++ terminates
    // before this seam can observe it. Other runtime/audit exceptions remain
    // contained and force the channel to tear down this failed broker.
  }
}

std::array<std::byte, broker::kBrokerErrorBytes>
StructuredBroker::typed_error(const wire::PacketView &request, ReplyKind kind,
                              permissions::GrantDecisionCode decision) {
  auto reason = broker::BrokerErrorReason::denied;
  if (kind == ReplyKind::provider_unavailable)
    reason = broker::BrokerErrorReason::provider_unavailable;
  else if (kind == ReplyKind::provider_failed)
    reason = broker::BrokerErrorReason::provider_failed;
  return broker::encode_broker_error(
      {.failed_operation =
           static_cast<permissions::OperationId>(request.header.message_type),
       .reason = reason,
       .decision = decision});
}

} // namespace omarchy::plugin_runtime::host_session
