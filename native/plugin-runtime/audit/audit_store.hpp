#pragma once

#include "permission_contract.hpp"

#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <optional>
#include <string>
#include <vector>

namespace omarchy::plugins::audit {

namespace permissions = omarchy::plugins::permissions;

inline constexpr std::size_t kHardMaximumRecords = 4096;

enum class ErrorCode {
  ok,
  invalid_argument,
  unsafe_store,
  corrupt_store,
  sequence_exhausted,
  injected_failure,
  io_error,
};

struct Result {
  ErrorCode code = ErrorCode::ok;
  std::string detail;
  [[nodiscard]] bool ok() const { return code == ErrorCode::ok; }
};

enum class FaultPoint {
  none,
  append_after_write,
  append_after_file_sync,
  append_after_rename,
};

struct Options {
  std::size_t maximum_records = 1024;
};

struct Query {
  std::uint64_t sequence_at_least = 0;
  std::uint64_t sequence_at_most = 0;
  std::optional<permissions::PluginId> plugin;
  std::optional<permissions::AuditProducer> producer;
  std::optional<permissions::AuditEvent> event;
  std::optional<permissions::AuditOutcome> outcome;
  std::size_t maximum_results = 1024;
};

struct QueryResult {
  Result status;
  std::vector<permissions::AuditRecord> records;
};

struct AppendResult {
  Result status;
  std::optional<permissions::AuditRecord> record;
};

class AuditStore {
public:
  AuditStore(std::filesystem::path root, Options options);

  [[nodiscard]] Result recover();
  [[nodiscard]] AppendResult append(permissions::AuditProducer producer,
                                    permissions::AuditDraft draft,
                                    FaultPoint fault = FaultPoint::none);
  [[nodiscard]] QueryResult query(const Query &query) const;
  [[nodiscard]] Result export_tsv(const Query &query,
                                  std::string &output) const;
  [[nodiscard]] Result export_human(const Query &query,
                                    std::string &output) const;

private:
  std::filesystem::path root_;
  Options options_;
};

} // namespace omarchy::plugins::audit
