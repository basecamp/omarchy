#pragma once

#include <algorithm>
#include <array>
#include <compare>
#include <cstddef>
#include <cstdint>
#include <optional>
#include <span>
#include <stdexcept>
#include <string>
#include <string_view>
#include <utility>
#include <variant>
#include <vector>

namespace omarchy::plugins::permissions {

template <std::size_t Maximum> class BoundedString {
public:
  BoundedString() = default;
  explicit BoundedString(std::string_view value) { assign(value); }

  void assign(std::string_view value) {
    if (value.empty() || value.size() > Maximum ||
        value.find('\0') != std::string_view::npos) {
      throw std::runtime_error("bounded string has invalid length or NUL");
    }
    bytes_.fill(0);
    size_ = value.size();
    std::copy(value.begin(), value.end(), bytes_.begin());
  }

  [[nodiscard]] std::string_view view() const { return {bytes_.data(), size_}; }
  [[nodiscard]] std::size_t size() const { return size_; }
  auto operator<=>(const BoundedString &) const = default;

private:
  std::array<char, Maximum> bytes_{};
  std::size_t size_ = 0;
};

template <typename T, std::size_t Capacity> class FixedSet {
public:
  bool insert(T value) {
    const auto position =
        std::lower_bound(values_.begin(), values_.begin() + size_, value);
    if (position != values_.begin() + size_ && *position == value)
      return false;
    if (size_ == Capacity)
      throw std::runtime_error("fixed set is full");
    std::move_backward(position, values_.begin() + size_,
                       values_.begin() + size_ + 1);
    *position = std::move(value);
    ++size_;
    return true;
  }
  [[nodiscard]] bool contains(const T &value) const {
    return std::binary_search(values_.begin(), values_.begin() + size_, value);
  }
  [[nodiscard]] std::span<const T> values() const {
    return {values_.data(), size_};
  }
  [[nodiscard]] std::size_t size() const { return size_; }
  bool operator==(const FixedSet &other) const {
    return size_ == other.size_ &&
           std::equal(values_.begin(), values_.begin() + size_,
                      other.values_.begin());
  }

private:
  std::array<T, Capacity> values_{};
  std::size_t size_ = 0;
};

template <typename T, std::size_t Capacity> class FixedVector {
public:
  FixedVector() { values_.reserve(Capacity); }

  void push_back(T value) {
    if (values_.size() == Capacity)
      throw std::runtime_error("fixed vector is full");
    values_.push_back(std::move(value));
  }
  [[nodiscard]] std::span<const T> values() const {
    return values_;
  }
  [[nodiscard]] std::span<T> values() { return values_; }
  [[nodiscard]] std::size_t size() const { return values_.size(); }
  [[nodiscard]] bool empty() const { return values_.empty(); }
  T &operator[](std::size_t index) {
    if (index >= values_.size())
      throw std::runtime_error("fixed vector index out of range");
    return values_[index];
  }
  const T &operator[](std::size_t index) const {
    if (index >= values_.size())
      throw std::runtime_error("fixed vector index out of range");
    return values_[index];
  }

private:
  std::vector<T> values_;
};

using PluginId = BoundedString<128>;
using CapabilityId = BoundedString<128>;
using ScopeToken = BoundedString<96>;
using Digest = BoundedString<64>;

enum class OperationId : std::uint16_t {
  storage_read = 0x0101,
  storage_write = 0x0102,
  storage_remove = 0x0103,
  notification_send = 0x0201,
  audio_play_cue = 0x0301,
  fake_status_list = 0x0401,
  fake_status_acknowledge = 0x0402,
};

struct CapabilityKey {
  CapabilityId id;
  std::uint16_t version = 0;
  auto operator<=>(const CapabilityKey &) const = default;
};

struct NoScope {
  bool operator==(const NoScope &) const = default;
};

struct QuotaScope {
  std::uint64_t total_bytes = 0;
  std::uint64_t item_bytes = 0;
  bool operator==(const QuotaScope &) const = default;
};

struct TokenScope {
  FixedSet<ScopeToken, 16> tokens;
  bool operator==(const TokenScope &) const = default;
};

struct ResourceScope {
  FixedSet<std::uint32_t, 32> resources;
  FixedSet<OperationId, 16> operations;
  bool operator==(const ResourceScope &) const = default;
};

struct HttpScope {
  FixedSet<ScopeToken, 4> schemes;
  FixedSet<ScopeToken, 16> hosts;
  FixedSet<ScopeToken, 8> methods;
  FixedSet<std::uint16_t, 16> ports;
  bool allow_redirects = false;
  bool allow_loopback = false;
  bool allow_unix_socket = false;
  bool operator==(const HttpScope &) const = default;
};

using Scope =
    std::variant<NoScope, QuotaScope, TokenScope, ResourceScope, HttpScope>;

enum class ScopeKind : std::uint8_t { none, quota, tokens, resources, http };
enum class GestureRule : std::uint8_t { none, fresh_single_use };
enum class RevocationMode : std::uint8_t {
  deny_new,
  cancel_inflight,
  restart_worker
};

struct CapabilityDefinition {
  CapabilityKey key;
  ScopeKind scope_kind = ScopeKind::none;
  std::array<OperationId, 4> operations{};
  std::uint8_t operation_count = 0;
  GestureRule gesture = GestureRule::none;
  RevocationMode revocation = RevocationMode::deny_new;
};

std::span<const CapabilityDefinition> capability_registry();
const CapabilityDefinition *find_capability(const CapabilityKey &key);
const CapabilityDefinition *find_operation(OperationId operation);
bool valid_scope(const CapabilityDefinition &definition, const Scope &scope);

enum class ScopeRelation : std::uint8_t {
  equal,
  narrower,
  expanded,
  incomparable
};
ScopeRelation compare_scope(const Scope &candidate, const Scope &baseline);
std::string canonical_scope(const Scope &scope);

struct CapabilityRequest {
  CapabilityKey capability;
  Scope scope;
  bool required = false;
  bool operator==(const CapabilityRequest &) const = default;
};

using RequestSet = FixedVector<CapabilityRequest, 64>;
std::string policy_request_fingerprint(const RequestSet &requests);
void validate_requests(const RequestSet &requests);

enum class UserDecision : std::uint8_t { grant, deny };
enum class DecisionActor : std::uint8_t {
  trusted_ui,
  interactive_cli,
  reviewed_policy
};

struct UserDecisionRecord {
  std::uint64_t sequence = 0;
  PluginId plugin;
  Digest revision;
  Digest source_request_fingerprint;
  Digest policy_request_fingerprint;
  CapabilityKey capability;
  Scope requested_scope;
  Scope decided_scope;
  UserDecision decision = UserDecision::deny;
  DecisionActor actor = DecisionActor::trusted_ui;
  std::uint64_t decided_wall_seconds = 0;
};

void validate_decision(const UserDecisionRecord &decision);

enum class GrantState : std::uint8_t { granted, denied, revoked };

struct GrantRecord {
  CapabilityKey capability;
  Scope scope;
  GrantState state = GrantState::denied;
  std::uint64_t epoch = 0;
  bool operator==(const GrantRecord &) const = default;
};

using GrantSet = FixedVector<GrantRecord, 64>;
std::string grant_fingerprint(const PluginId &plugin, const Digest &revision,
                              const Digest &policy_fingerprint,
                              const GrantSet &grants);

enum class DeltaKind : std::uint8_t {
  unchanged,
  narrowed,
  expanded,
  incomparable,
  added,
  removed,
  requirement_changed,
};

struct PermissionDelta {
  CapabilityKey capability;
  DeltaKind kind = DeltaKind::unchanged;
  std::optional<GrantRecord> inherited_grant;
};

using DeltaSet = FixedVector<PermissionDelta, 128>;
DeltaSet compute_update_delta(const RequestSet &old_requests,
                              const GrantSet &old_grants,
                              const RequestSet &new_requests);

struct ActivationBinding {
  PluginId plugin;
  Digest revision;
  Digest policy_fingerprint;
  std::uint64_t generation = 0;
  bool operator==(const ActivationBinding &) const = default;
};

struct GestureId {
  std::array<std::byte, 16> bytes{};
  auto operator<=>(const GestureId &) const = default;
};

struct GestureProof {
  GestureId id;
  PluginId plugin;
  std::uint64_t generation = 0;
  std::uint64_t surface = 0;
  OperationId operation{};
  std::uint64_t expires_monotonic_ns = 0;
  bool consumed = false;
};

enum class GrantDecisionCode : std::uint8_t {
  allowed,
  unknown_operation,
  capability_undeclared,
  ungranted,
  explicitly_denied,
  revoked,
  activation_mismatch,
  outside_scope,
  gesture_missing,
  gesture_expired,
  gesture_wrong_binding,
  gesture_used,
};

struct GrantDecision {
  GrantDecisionCode code = GrantDecisionCode::ungranted;
  CapabilityKey capability;
  std::uint64_t grant_epoch = 0;
  [[nodiscard]] bool allowed() const {
    return code == GrantDecisionCode::allowed;
  }
};

class PermissionAuthority {
public:
  PermissionAuthority(ActivationBinding binding, RequestSet requests,
                      GrantSet grants);
  GrantDecision authorize(OperationId operation, const Scope &demand,
                          const ActivationBinding &channel,
                          std::uint64_t now_monotonic_ns,
                          GestureProof *gesture = nullptr) const;
  std::uint64_t revoke(const CapabilityKey &capability);
  [[nodiscard]] const GrantSet &grants() const { return grants_; }

private:
  ActivationBinding binding_;
  RequestSet requests_;
  GrantSet grants_;
};

struct HandleId {
  std::array<std::byte, 16> bytes{};
  auto operator<=>(const HandleId &) const = default;
};

enum class HandleDecision : std::uint8_t {
  allowed,
  invalid,
  unknown,
  wrong_plugin,
  wrong_revision,
  wrong_policy,
  wrong_generation,
  wrong_operation,
  stale_grant,
  expired,
  outside_scope,
  duplicate,
  table_full,
};

struct HandleRecord {
  HandleId id;
  PluginId plugin;
  Digest revision;
  Digest policy_fingerprint;
  std::uint64_t generation = 0;
  OperationId operation{};
  Scope scope;
  std::uint64_t grant_epoch = 0;
  std::uint64_t expires_monotonic_ns = 0;
};

bool valid_handle_record(const HandleRecord &record);

template <std::size_t Capacity> class HandleTable {
public:
  HandleDecision issue(HandleRecord record) {
    if (!valid_handle_record(record))
      return HandleDecision::invalid;
    if (find(record.id) != nullptr)
      return HandleDecision::duplicate;
    for (auto &slot : slots_) {
      if (!slot.has_value()) {
        slot = std::move(record);
        return HandleDecision::allowed;
      }
    }
    return HandleDecision::table_full;
  }

  HandleDecision resolve(const HandleId &id, const ActivationBinding &binding,
                         OperationId operation, const Scope &demand,
                         std::uint64_t current_grant_epoch,
                         std::uint64_t now_monotonic_ns) const {
    const HandleRecord *record = find(id);
    if (record == nullptr)
      return HandleDecision::unknown;
    if (record->plugin != binding.plugin)
      return HandleDecision::wrong_plugin;
    if (record->revision != binding.revision)
      return HandleDecision::wrong_revision;
    if (record->policy_fingerprint != binding.policy_fingerprint)
      return HandleDecision::wrong_policy;
    if (record->generation != binding.generation)
      return HandleDecision::wrong_generation;
    if (record->operation != operation)
      return HandleDecision::wrong_operation;
    if (record->grant_epoch != current_grant_epoch)
      return HandleDecision::stale_grant;
    if (now_monotonic_ns >= record->expires_monotonic_ns)
      return HandleDecision::expired;
    const auto *definition = find_operation(operation);
    if (definition == nullptr || !valid_scope(*definition, demand))
      return HandleDecision::outside_scope;
    const auto relation = compare_scope(demand, record->scope);
    return relation == ScopeRelation::equal ||
                   relation == ScopeRelation::narrower
               ? HandleDecision::allowed
               : HandleDecision::outside_scope;
  }

  bool erase(const HandleId &id) {
    for (auto &slot : slots_) {
      if (slot.has_value() && slot->id == id) {
        slot.reset();
        return true;
      }
    }
    return false;
  }

private:
  const HandleRecord *find(const HandleId &id) const {
    for (const auto &slot : slots_) {
      if (slot.has_value() && slot->id == id)
        return &*slot;
    }
    return nullptr;
  }
  std::array<std::optional<HandleRecord>, Capacity> slots_{};
};

enum class AuditProducer : std::uint8_t {
  lifecycle,
  supervisor,
  broker,
  surface_host
};
bool valid_audit_producer(AuditProducer producer);
enum class AuditEvent : std::uint8_t {
  grant_changed,
  operation_decided,
  capability_revoked,
  handle_issued,
  handle_denied,
  worker_started,
  worker_health,
  worker_crashed,
  worker_stopped,
  worker_disabled,
};
enum class AuditOutcome : std::uint8_t { allowed, denied, cancelled, failed };
enum class AuditMetric : std::uint8_t {
  request_bytes,
  response_bytes,
  item_count,
  duration_milliseconds,
  retry_after_seconds,
};

struct AuditMetadata {
  AuditMetric metric{};
  std::int64_t value = 0;
  bool operator==(const AuditMetadata &) const = default;
};

struct AuditDraft {
  AuditEvent event{};
  AuditOutcome outcome{};
  PluginId plugin;
  Digest revision;
  std::uint64_t generation = 0;
  std::uint64_t correlation = 0;
  std::optional<OperationId> operation;
  std::optional<CapabilityKey> capability;
  GrantDecisionCode decision = GrantDecisionCode::ungranted;
  FixedVector<AuditMetadata, 8> metadata;
};

struct AuditRecord : AuditDraft {
  std::uint64_t sequence = 0;
  std::uint64_t wall_seconds = 0;
  std::uint64_t monotonic_ns = 0;
  AuditProducer producer = AuditProducer::broker;
};

void validate_audit_draft(const AuditDraft &draft);
std::string audit_record_fingerprint(const AuditRecord &record);

template <std::size_t Capacity> class AuditLog {
public:
  const AuditRecord &append(AuditProducer producer, AuditDraft draft,
                            std::uint64_t wall_seconds,
                            std::uint64_t monotonic_ns) {
    if (!valid_audit_producer(producer))
      throw std::runtime_error("invalid audit producer");
    validate_audit_draft(draft);
    AuditRecord record;
    static_cast<AuditDraft &>(record) = std::move(draft);
    record.sequence = ++sequence_;
    record.wall_seconds = wall_seconds;
    record.monotonic_ns = monotonic_ns;
    record.producer = producer;
    records_[next_] = std::move(record);
    const std::size_t written = next_;
    next_ = (next_ + 1) % Capacity;
    if (size_ < Capacity)
      ++size_;
    return records_[written];
  }
  [[nodiscard]] std::size_t size() const { return size_; }
  [[nodiscard]] const AuditRecord &oldest(std::size_t index) const {
    if (index >= size_)
      throw std::runtime_error("audit index out of range");
    const std::size_t start = size_ == Capacity ? next_ : 0;
    return records_[(start + index) % Capacity];
  }

private:
  static_assert(Capacity > 0);
  std::array<AuditRecord, Capacity> records_{};
  std::size_t next_ = 0;
  std::size_t size_ = 0;
  std::uint64_t sequence_ = 0;
};

} // namespace omarchy::plugins::permissions
