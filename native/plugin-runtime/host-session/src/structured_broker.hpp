#pragma once

#include "broker_runtime.hpp"
#include "dynamic_broker_runtime.hpp"
#include "omarchy/plugin/wire/envelope.hpp"

#include <array>
#include <atomic>
#include <cstddef>
#include <cstdint>
#include <memory>
#include <optional>
#include <span>
#include <utility>

namespace omarchy::plugin_runtime::host_session {

namespace broker = omarchy::plugin_runtime::broker;
namespace definitions = omarchy::plugins::definitions;
namespace permissions = omarchy::plugins::permissions;
namespace runtime = omarchy::plugin_runtime::runtime;
namespace wire = omarchy::plugin::wire;

class BrokerInstanceOrigin;
// One exact, broker-minted identity follows a request through settlement.
// Its opaque origin prevents equal visible binding fields from being replayed.
class BrokerAuthorityStamp final {
  BrokerAuthorityStamp() = default;
  BrokerAuthorityStamp(permissions::ActivationBinding binding,
                       std::uint64_t session_nonce,
                       std::shared_ptr<const BrokerInstanceOrigin> origin);

  [[nodiscard]] bool valid() const noexcept;
  [[nodiscard]] bool
  exactly_matches(const BrokerAuthorityStamp &other) const noexcept;

  permissions::ActivationBinding binding_{};
  std::uint64_t session_nonce_ = 0;
  std::shared_ptr<const BrokerInstanceOrigin> origin_;

  friend class AdmittedBrokerRequest;
  friend class AuthenticatedBrokerAdmission;
  friend class BrokerTransaction;
  friend class StructuredBroker;
};

inline constexpr std::size_t kMaximumOwnedBrokerRequestBytes =
    wire::payload_cap(wire::EndpointRole::broker);

class AdmittedBrokerRequest final {
public:
  AdmittedBrokerRequest(const AdmittedBrokerRequest &) = delete;
  AdmittedBrokerRequest &operator=(const AdmittedBrokerRequest &) = delete;
  AdmittedBrokerRequest(AdmittedBrokerRequest &&other) noexcept;
  AdmittedBrokerRequest &operator=(AdmittedBrokerRequest &&) = delete;

private:
  AdmittedBrokerRequest(wire::PacketView packet,
                        const BrokerAuthorityStamp &authority);

  [[nodiscard]] wire::PacketView packet() const noexcept;
  void consume() noexcept;

  wire::EnvelopeHeader header_{};
  std::array<std::byte, kMaximumOwnedBrokerRequestBytes> payload_{};
  std::size_t payload_size_ = 0;
  BrokerAuthorityStamp authority_;
  bool available_ = false;

  friend class AuthenticatedBrokerAdmission;
  friend class StructuredBroker;
};

// Semantic broker fields copied from an already authenticated channel. The
// opaque admission supplies every wire-authority field; callers cannot choose
// a role, protocol version, generation, or activation binding.
struct AuthenticatedBrokerRequestView final {
  std::uint16_t message_type = 0;
  std::uint64_t correlation_id = 0;
  std::span<const std::byte> payload;
};

enum class AdmissionFailure : std::uint8_t {
  none,
  stale_binding,
  malformed_length,
  invalid_message_type,
  invalid_correlation,
  replay,
};

struct AdmissionResult {
  std::optional<AdmittedBrokerRequest> request;
  AdmissionFailure failure = AdmissionFailure::none;
  [[nodiscard]] explicit operator bool() const noexcept {
    return request.has_value();
  }
};

// Minted only by its StructuredBroker, which shares the same opaque origin with
// every admitted request. PacketView has no descriptor field; the complete
// bounded header and payload are owned by AdmittedBrokerRequest.
class AuthenticatedBrokerAdmission final {
public:
  AuthenticatedBrokerAdmission(const AuthenticatedBrokerAdmission &) = delete;
  AuthenticatedBrokerAdmission &
  operator=(const AuthenticatedBrokerAdmission &) = delete;
  AuthenticatedBrokerAdmission(AuthenticatedBrokerAdmission &&) noexcept =
      default;
  AuthenticatedBrokerAdmission &
  operator=(AuthenticatedBrokerAdmission &&) noexcept = default;

  [[nodiscard]] AdmissionResult admit(AuthenticatedBrokerRequestView request);

private:
  explicit AuthenticatedBrokerAdmission(
      const BrokerAuthorityStamp &authority) noexcept;

  BrokerAuthorityStamp authority_;
  std::uint64_t last_correlation_ = 0;

  friend class StructuredBroker;
};

enum class AdmissionExtractionFailure : std::uint8_t {
  none,
  already_extracted,
};

struct AdmissionExtractionResult {
  std::optional<AuthenticatedBrokerAdmission> admission;
  AdmissionExtractionFailure failure = AdmissionExtractionFailure::none;
  [[nodiscard]] explicit operator bool() const noexcept {
    return admission.has_value();
  }
};

// The authority owns the mechanism that prevents a grant epoch from changing
// between authorization and provider effect. A lease may use an RCU reader,
// active-use counter, or another non-reentrant-safe implementation; the broker
// does not hold a general mutex across provider code.
class DispatchAuthorityLease {
public:
  virtual ~DispatchAuthorityLease() = default;
  [[nodiscard]] virtual bool current_at_effect() const noexcept = 0;
};

class DispatchAuthority {
public:
  virtual ~DispatchAuthority() = default;
  [[nodiscard]] virtual std::unique_ptr<DispatchAuthorityLease>
  acquire(const permissions::ActivationBinding &binding,
          std::uint64_t session_nonce, const wire::PacketView &request) = 0;
  [[nodiscard]] virtual bool
  fence_builtin(const policy::Revocation &revocation) noexcept = 0;
  [[nodiscard]] virtual bool
  fence_dynamic(const definitions::DynamicRevisionGrant &updated) noexcept = 0;
};

enum class TransactionState : std::uint8_t { reply, fatal };
enum class ReplyKind : std::uint8_t {
  result,
  denied,
  provider_unavailable,
  provider_failed,
};
enum class DispatchFatal : std::uint8_t {
  none,
  admission_reused,
  identity_mismatch,
  authority_stale,
  malformed,
  protocol,
  runtime_failed,
  pending_unsupported,
};

inline constexpr std::size_t kMaximumOwnedBrokerReplyBytes =
    wire::payload_cap(wire::EndpointRole::broker);

class BrokerTransaction final {
public:
  BrokerTransaction(const BrokerTransaction &) = delete;
  BrokerTransaction &operator=(const BrokerTransaction &) = delete;
  BrokerTransaction(BrokerTransaction &&other) noexcept;
  BrokerTransaction &operator=(BrokerTransaction &&) = delete;

  [[nodiscard]] TransactionState state() const noexcept { return state_; }
  [[nodiscard]] ReplyKind reply_kind() const noexcept { return reply_kind_; }
  [[nodiscard]] DispatchFatal fatal() const noexcept { return fatal_; }
  [[nodiscard]] std::uint64_t correlation() const noexcept {
    return correlation_;
  }
  [[nodiscard]] std::uint16_t message_type() const noexcept {
    return message_type_;
  }
  [[nodiscard]] std::span<const std::byte> wire_payload() const noexcept {
    return std::span(payload_).first(payload_size_);
  }
  [[nodiscard]] std::size_t provider_response_bytes() const noexcept {
    return provider_response_bytes_;
  }
  [[nodiscard]] bool settled() const noexcept { return settled_; }

private:
  enum class Route : std::uint8_t { none, builtin, dynamic };

  static BrokerTransaction fatal_result(DispatchFatal fatal,
                                        std::uint64_t correlation = 0) noexcept;
  static BrokerTransaction reply_result(Route route, ReplyKind kind,
                                        std::uint64_t correlation,
                                        std::uint16_t message_type,
                                        std::span<const std::byte> wire_payload,
                                        std::size_t provider_response_bytes,
                                        const BrokerAuthorityStamp &authority);
  BrokerTransaction() = default;
  void consume() noexcept;

  TransactionState state_ = TransactionState::fatal;
  ReplyKind reply_kind_ = ReplyKind::provider_failed;
  DispatchFatal fatal_ = DispatchFatal::runtime_failed;
  Route route_ = Route::none;
  std::uint64_t correlation_ = 0;
  std::uint16_t message_type_ = 0;
  std::array<std::byte, kMaximumOwnedBrokerReplyBytes> payload_{};
  std::size_t payload_size_ = 0;
  std::size_t provider_response_bytes_ = 0;
  BrokerAuthorityStamp authority_;
  bool settled_ = false;

  friend class StructuredBroker;
};

class StructuredBroker final {
public:
  StructuredBroker(permissions::ActivationBinding binding,
                   std::uint64_t session_nonce,
                   runtime::AuditedBrokerRuntime &builtin,
                   runtime::DynamicBrokerRuntime &dynamic,
                   DispatchAuthority &authority);
  StructuredBroker(const StructuredBroker &) = delete;
  StructuredBroker &operator=(const StructuredBroker &) = delete;
  StructuredBroker(StructuredBroker &&) = delete;
  StructuredBroker &operator=(StructuredBroker &&) = delete;

  // The trusted channel extracts the sole admission authority exactly once.
  // Correlation replay state consequently cannot be reset or split by lane.
  [[nodiscard]] AdmissionExtractionResult take_admission();
  [[nodiscard]] bool accepts(const permissions::ActivationBinding &binding,
                             std::uint64_t session_nonce) const noexcept;

  [[nodiscard]] BrokerTransaction
  dispatch(AdmittedBrokerRequest &&request, std::uint64_t now_monotonic_ns,
           std::span<std::byte> provider_response,
           permissions::GestureProof *builtin_gesture = nullptr,
           runtime::DynamicGestureAuthority *dynamic_gesture = nullptr);

  // Foreign-origin settlement is rejected without consuming the transaction or
  // touching either runtime. Accepted settlement consumes the transaction
  // before applying its one terminal runtime effect.
  [[nodiscard]] bool commit_sent(BrokerTransaction &&transaction);
  [[nodiscard]] bool abort_send(BrokerTransaction &&transaction);

  [[nodiscard]] runtime::RevocationResult
  apply_builtin_revocation(const policy::Revocation &revocation);
  [[nodiscard]] runtime::DynamicRevocationResult
  apply_dynamic_update(const definitions::DynamicRevisionGrant &updated);

private:
  [[nodiscard]] bool owns(const BrokerTransaction &transaction) const noexcept;
  void fail_closed() noexcept;

  [[nodiscard]] BrokerTransaction
  dispatch_builtin(const wire::PacketView &packet,
                   std::uint64_t now_monotonic_ns,
                   std::span<std::byte> provider_response,
                   permissions::GestureProof *gesture);
  [[nodiscard]] BrokerTransaction
  dispatch_dynamic(const wire::PacketView &packet,
                   std::span<std::byte> provider_response,
                   runtime::DynamicGestureAuthority *gesture);
  [[nodiscard]] BrokerTransaction
  typed_error_reply(BrokerTransaction::Route route,
                    const wire::PacketView &request, ReplyKind kind,
                    permissions::GrantDecisionCode decision);
  [[nodiscard]] static std::array<std::byte, broker::kBrokerErrorBytes>
  typed_error(const wire::PacketView &request, ReplyKind kind,
              permissions::GrantDecisionCode decision);

  BrokerAuthorityStamp authority_stamp_;
  std::atomic<bool> admission_extracted_{false};
  std::atomic<bool> failed_{false};
  runtime::AuditedBrokerRuntime &builtin_;
  runtime::DynamicBrokerRuntime &dynamic_;
  DispatchAuthority &authority_;
};

} // namespace omarchy::plugin_runtime::host_session
