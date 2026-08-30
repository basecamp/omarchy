#include "audit_store.hpp"

#include <algorithm>
#include <chrono>
#include <limits>
#include <stdexcept>
#include <utility>

namespace omarchy::plugins::audit {
namespace {

std::pair<std::uint64_t, std::uint64_t> authoritative_time() {
  using namespace std::chrono;
  const auto wall = duration_cast<seconds>(system_clock::now().time_since_epoch());
  const auto monotonic =
      duration_cast<nanoseconds>(steady_clock::now().time_since_epoch());
  return {static_cast<std::uint64_t>(wall.count()),
          static_cast<std::uint64_t>(monotonic.count())};
}

} // namespace

BoundedAuditLog::BoundedAuditLog(std::size_t maximum_records)
    : maximum_records_(maximum_records) {
  if (maximum_records == 0 || maximum_records > kHardMaximumRecords)
    throw std::invalid_argument("audit retention bound is invalid");
  records_.reserve(maximum_records);
}

AppendResult BoundedAuditLog::append(permissions::AuditProducer producer,
                                     permissions::AuditDraft draft) {
  try {
    if (!permissions::valid_audit_producer(producer))
      throw std::invalid_argument("audit producer is invalid");
    permissions::validate_audit_draft(draft);
    if (next_sequence_ == 0)
      return {{ErrorCode::sequence_exhausted,
               "audit sequence is exhausted"},
              std::nullopt};

    auto [wall_seconds, monotonic_ns] = authoritative_time();
    if (wall_seconds == 0 || monotonic_ns == 0)
      throw std::runtime_error("audit clock is unavailable");
    if (monotonic_ns <= last_monotonic_ns_) {
      if (last_monotonic_ns_ == std::numeric_limits<std::uint64_t>::max())
        return {{ErrorCode::sequence_exhausted,
                 "audit monotonic clock is exhausted"},
                std::nullopt};
      monotonic_ns = last_monotonic_ns_ + 1;
    }

    permissions::AuditRecord record;
    static_cast<permissions::AuditDraft &>(record) = std::move(draft);
    record.sequence = next_sequence_++;
    record.wall_seconds = wall_seconds;
    record.monotonic_ns = monotonic_ns;
    record.producer = producer;
    (void)permissions::audit_record_fingerprint(record);

    if (records_.size() == maximum_records_)
      records_.erase(records_.begin());
    records_.push_back(record);
    last_monotonic_ns_ = monotonic_ns;
    return {{}, record};
  } catch (const std::exception &error) {
    return {{ErrorCode::invalid_argument, error.what()}, std::nullopt};
  }
}

QueryResult BoundedAuditLog::query(const Query &query) const {
  QueryResult result;
  if (query.maximum_results == 0 ||
      query.maximum_results > kHardMaximumRecords) {
    result.status = {ErrorCode::invalid_argument,
                     "audit query bound is invalid"};
    return result;
  }
  result.records.reserve(std::min(query.maximum_results, records_.size()));
  for (const auto &record : records_) {
    if (query.plugin && record.plugin != *query.plugin)
      continue;
    if (query.event && record.event != *query.event)
      continue;
    if (result.records.size() == query.maximum_results)
      break;
    result.records.push_back(record);
  }
  return result;
}

} // namespace omarchy::plugins::audit
