#include "audit_store.hpp"

#include <iostream>
#include <stdexcept>
#include <string>
#include <string_view>

namespace {

namespace audit = omarchy::plugins::audit;
namespace permissions = omarchy::plugins::permissions;

void require(bool condition, std::string_view message) {
  if (!condition)
    throw std::runtime_error(std::string(message));
}

permissions::Digest digest(char value) {
  return permissions::Digest(std::string(64, value));
}

permissions::AuditDraft operation(std::uint64_t correlation,
                                  std::string_view plugin = "org.example.one") {
  return {
      .event = permissions::AuditEvent::operation_decided,
      .outcome = permissions::AuditOutcome::allowed,
      .plugin = permissions::PluginId(plugin),
      .revision = digest('a'),
      .generation = 4,
      .correlation = correlation,
      .dynamic_operation = std::nullopt,
      .dynamic_attempt = std::nullopt,
      .operation = permissions::OperationId::storage_read,
      .capability =
          permissions::CapabilityKey{
              permissions::CapabilityId("storage.private"), 1},
      .decision = permissions::GrantDecisionCode::allowed,
      .metadata = {},
  };
}

void bounded_append_and_query() {
  audit::BoundedAuditLog log(2);
  const auto first =
      log.append(permissions::AuditProducer::broker, operation(1));
  const auto second =
      log.append(permissions::AuditProducer::broker, operation(2));
  const auto third = log.append(permissions::AuditProducer::broker,
                                operation(3, "org.example.two"));
  require(first.status.ok() && second.status.ok() && third.status.ok(),
          "valid append failed");
  require(first.record->sequence == 1 && second.record->sequence == 2 &&
              third.record->sequence == 3 &&
              first.record->monotonic_ns < second.record->monotonic_ns &&
              second.record->monotonic_ns < third.record->monotonic_ns,
          "audit authority did not assign monotonic identity");

  const auto retained = log.query();
  require(retained.status.ok() && retained.records.size() == 2 &&
              retained.records.front().correlation == 2 &&
              retained.records.back().correlation == 3,
          "bounded log did not retain the newest records");
  audit::Query filtered;
  filtered.plugin = permissions::PluginId("org.example.two");
  const auto selected = log.query(filtered);
  require(selected.records.size() == 1 &&
              selected.records.front().correlation == 3,
          "plugin filter crossed identity boundaries");
}

void rejects_invalid_input() {
  bool rejected_bound = false;
  try {
    audit::BoundedAuditLog invalid(0);
  } catch (const std::invalid_argument &) {
    rejected_bound = true;
  }
  require(rejected_bound, "zero retention bound accepted");

  audit::BoundedAuditLog log(1);
  auto invalid = operation(1);
  invalid.correlation = 0;
  require(!log.append(permissions::AuditProducer::broker, invalid).status.ok(),
          "invalid audit draft accepted");
  require(
      !log.append(static_cast<permissions::AuditProducer>(255), operation(1))
           .status.ok(),
      "untrusted audit producer accepted");
  audit::Query query;
  query.maximum_results = 0;
  require(!log.query(query).status.ok(), "unbounded audit query accepted");
}

} // namespace

int main() {
  try {
    bounded_append_and_query();
    rejects_invalid_input();
    std::cout << "bounded audit sink: ok\n";
    return 0;
  } catch (const std::exception &error) {
    std::cerr << "bounded audit sink: " << error.what() << '\n';
    return 1;
  }
}
