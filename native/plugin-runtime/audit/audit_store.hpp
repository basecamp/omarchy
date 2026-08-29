#pragma once

#include "permission_contract.hpp"

#include <cstddef>
#include <cstdint>
#include <optional>
#include <string>
#include <vector>

namespace omarchy::plugins::audit {

namespace permissions = omarchy::plugins::permissions;

inline constexpr std::size_t kHardMaximumRecords = 4096;

enum class ErrorCode { ok, invalid_argument, sequence_exhausted };

struct Result {
  ErrorCode code = ErrorCode::ok;
  std::string detail;
  [[nodiscard]] bool ok() const noexcept { return code == ErrorCode::ok; }
};

struct AppendResult {
  Result status;
  std::optional<permissions::AuditRecord> record;
};

class AuditSink {
public:
  virtual ~AuditSink() = default;
  [[nodiscard]] virtual AppendResult
  append(permissions::AuditProducer producer,
         permissions::AuditDraft draft) = 0;
};

struct Query {
  std::optional<permissions::PluginId> plugin;
  std::optional<permissions::AuditEvent> event;
  std::size_t maximum_results = kHardMaximumRecords;
};

struct QueryResult {
  Result status;
  std::vector<permissions::AuditRecord> records;
};

// Runtime audit is deliberately bounded and non-administrative. Durable storage,
// export, migration, and inspection can implement AuditSink outside the core.
class BoundedAuditLog final : public AuditSink {
public:
  explicit BoundedAuditLog(std::size_t maximum_records = 1024);

  [[nodiscard]] AppendResult
  append(permissions::AuditProducer producer,
         permissions::AuditDraft draft) override;
  [[nodiscard]] QueryResult query(const Query &query = {}) const;

private:
  std::size_t maximum_records_;
  std::uint64_t next_sequence_ = 1;
  std::uint64_t last_monotonic_ns_ = 0;
  std::vector<permissions::AuditRecord> records_;
};

} // namespace omarchy::plugins::audit
