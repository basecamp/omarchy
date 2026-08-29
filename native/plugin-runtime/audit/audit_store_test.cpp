#include "audit_store.hpp"

#include <array>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <iterator>
#include <stdexcept>
#include <string>
#include <string_view>
#include <sys/stat.h>
#include <unistd.h>
#include <vector>

namespace {

namespace audit = omarchy::plugins::audit;
namespace permissions = omarchy::plugins::permissions;

void require(bool condition, std::string_view message) {
  if (!condition)
    throw std::runtime_error(std::string(message));
}

class TemporaryDirectory {
public:
  TemporaryDirectory() {
    std::string pattern = "/tmp/omarchy-audit-store-XXXXXX";
    char *created = ::mkdtemp(pattern.data());
    if (created == nullptr)
      throw std::runtime_error("mkdtemp failed");
    path_ = created;
  }
  ~TemporaryDirectory() {
    std::error_code error;
    std::filesystem::remove_all(path_, error);
  }
  [[nodiscard]] const std::filesystem::path &path() const { return path_; }

private:
  std::filesystem::path path_;
};

permissions::Digest digest(char value) {
  return permissions::Digest(std::string(64, value));
}

permissions::CapabilityKey storage_key() {
  return {.id = permissions::CapabilityId("storage.private"), .version = 1};
}

permissions::AuditDraft operation_draft(std::uint64_t correlation = 7) {
  permissions::AuditDraft draft{
      .event = permissions::AuditEvent::operation_decided,
      .outcome = permissions::AuditOutcome::allowed,
      .plugin = permissions::PluginId("org.example.timer"),
      .revision = digest('a'),
      .generation = 9,
      .correlation = correlation,
      .dynamic_operation = std::nullopt,
      .operation = permissions::OperationId::storage_read,
      .capability = storage_key(),
      .decision = permissions::GrantDecisionCode::allowed,
      .metadata = {},
  };
  draft.metadata.push_back(
      {.metric = permissions::AuditMetric::request_bytes, .value = 128});
  draft.metadata.push_back(
      {.metric = permissions::AuditMetric::duration_milliseconds, .value = 4});
  return draft;
}

permissions::AuditDraft revocation_draft() {
  return {
      .event = permissions::AuditEvent::capability_revoked,
      .outcome = permissions::AuditOutcome::denied,
      .plugin = permissions::PluginId("org.example.timer"),
      .revision = digest('a'),
      .generation = 9,
      .correlation = 0,
      .dynamic_operation = std::nullopt,
      .operation = std::nullopt,
      .capability = storage_key(),
      .decision = permissions::GrantDecisionCode::revoked,
      .metadata = {},
  };
}

permissions::AuditDraft dynamic_draft() {
  return {.event = permissions::AuditEvent::operation_decided,
          .outcome = permissions::AuditOutcome::allowed,
          .plugin = permissions::PluginId("org.example.radio"),
          .revision = digest('b'),
          .generation = 3,
          .correlation = 19,
          .dynamic_operation = permissions::DynamicAuditIdentity{
              .capability = permissions::CapabilityId("network.fetch"),
              .definition_generation = 1,
              .definition_digest = digest('c'),
              .operation = permissions::BoundedString<128>("fetch"),
              .grant_epoch = 7},
          .operation = std::nullopt,
          .capability = std::nullopt,
          .decision = permissions::GrantDecisionCode::allowed,
          .metadata = {}};
}

void put8(std::vector<unsigned char> &out, std::uint8_t value) { out.push_back(value); }
void put16(std::vector<unsigned char> &out, std::uint16_t value) {
  put8(out, static_cast<std::uint8_t>(value >> 8)); put8(out, static_cast<std::uint8_t>(value));
}
void put32(std::vector<unsigned char> &out, std::uint32_t value) {
  for (int shift = 24; shift >= 0; shift -= 8) put8(out, static_cast<std::uint8_t>(value >> shift));
}
void put64(std::vector<unsigned char> &out, std::uint64_t value) {
  for (int shift = 56; shift >= 0; shift -= 8) put8(out, static_cast<std::uint8_t>(value >> shift));
}
void put_text(std::vector<unsigned char> &out, std::string_view value) {
  put16(out, static_cast<std::uint16_t>(value.size())); out.insert(out.end(), value.begin(), value.end());
}

std::vector<unsigned char> legacy_v1_snapshot() {
  permissions::AuditRecord record;
  static_cast<permissions::AuditDraft &>(record) = operation_draft();
  record.sequence = 1; record.wall_seconds = 1; record.monotonic_ns = 1;
  record.producer = permissions::AuditProducer::broker;
  std::vector<unsigned char> body;
  put64(body, 1); put64(body, 1); put64(body, 1);
  put8(body, static_cast<std::uint8_t>(record.producer));
  put8(body, static_cast<std::uint8_t>(record.event));
  put8(body, static_cast<std::uint8_t>(record.outcome));
  put8(body, static_cast<std::uint8_t>(record.decision));
  put_text(body, record.plugin.view()); put_text(body, record.revision.view());
  put64(body, record.generation); put64(body, record.correlation);
  put8(body, 1); put16(body, static_cast<std::uint16_t>(*record.operation));
  put8(body, 1); put_text(body, record.capability->id.view()); put16(body, record.capability->version);
  put8(body, static_cast<std::uint8_t>(record.metadata.size()));
  for (const auto &metric : record.metadata.values()) {
    put8(body, static_cast<std::uint8_t>(metric.metric)); put64(body, static_cast<std::uint64_t>(metric.value));
  }
  put_text(body, permissions::audit_record_fingerprint(record));
  std::vector<unsigned char> snapshot;
  const std::string_view magic = "OMARCHY-AUDIT-V1";
  snapshot.insert(snapshot.end(), magic.begin(), magic.end());
  put32(snapshot, 1); put64(snapshot, 1); put32(snapshot, 1);
  put32(snapshot, static_cast<std::uint32_t>(body.size()));
  snapshot.insert(snapshot.end(), body.begin(), body.end());
  return snapshot;
}

void write_bytes(const std::filesystem::path &path,
                 const std::vector<unsigned char> &bytes) {
  std::ofstream output(path, std::ios::binary | std::ios::trunc);
  output.write(reinterpret_cast<const char *>(bytes.data()),
               static_cast<std::streamsize>(bytes.size()));
  output.close();
  ::chmod(path.c_str(), 0600);
}

permissions::AuditDraft worker_draft() {
  permissions::AuditDraft draft{
      .event = permissions::AuditEvent::worker_crashed,
      .outcome = permissions::AuditOutcome::failed,
      .plugin = permissions::PluginId("org.example.timer"),
      .revision = digest('a'),
      .generation = 9,
      .correlation = 0,
      .dynamic_operation = std::nullopt,
      .operation = std::nullopt,
      .capability = std::nullopt,
      .decision = permissions::GrantDecisionCode::ungranted,
      .metadata = {},
  };
  draft.metadata.push_back(
      {.metric = permissions::AuditMetric::retry_after_seconds, .value = 2});
  return draft;
}

void test_append_query_export_and_retention() {
  TemporaryDirectory temporary;
  audit::AuditStore store(temporary.path() / "audit", {.maximum_records = 2});
  require(store.recover().ok(), "create audit store");
  const auto first =
      store.append(permissions::AuditProducer::broker, operation_draft(7));
  require(first.status.ok() && first.record && first.record->sequence == 1 &&
              first.record->wall_seconds > 0 && first.record->monotonic_ns > 0,
          "first authoritative append failed");
  const auto second =
      store.append(permissions::AuditProducer::supervisor, revocation_draft());
  require(second.status.ok() && second.record->sequence == 2 &&
              second.record->monotonic_ns > first.record->monotonic_ns,
          "second authoritative append failed");
  const auto third =
      store.append(permissions::AuditProducer::broker, operation_draft(8));
  require(third.status.ok() && third.record->sequence == 3,
          "third authoritative append failed");

  const auto all = store.query({});
  require(all.status.ok() && all.records.size() == 2 &&
              all.records[0].sequence == 2 && all.records[1].sequence == 3,
          "bounded retention or oldest-first order failed");
  audit::Query filtered;
  filtered.producer = permissions::AuditProducer::broker;
  filtered.sequence_at_least = 3;
  const auto selected = store.query(filtered);
  require(selected.status.ok() && selected.records.size() == 1 &&
              selected.records[0].correlation == 8,
          "deterministic audit query failed");

  std::string exported;
  require(store.export_tsv(filtered, exported).ok() &&
              exported.starts_with("sequence\twall_seconds\t") &&
              exported.find("org.example.timer") != std::string::npos &&
              exported.find("storage.private:1") != std::string::npos &&
              exported.find("secret") == std::string::npos,
          "redacted deterministic export failed");
  std::string human;
  require(
      store.export_human(filtered, human).ok() &&
          human.find("ALLOWED — plugin operation decided") !=
              std::string::npos &&
          human.find("Plugin ID: org.example.timer") != std::string::npos &&
          human.find("Revision: " + std::string(64, 'a')) !=
              std::string::npos &&
          human.find("Permission: storage.private@1") != std::string::npos &&
          human.find("Operation: read private storage") != std::string::npos &&
          human.find("Decision: granted") != std::string::npos &&
          human.find("secret") == std::string::npos,
      "human audit export is ambiguous or disclosed payload data");

  struct stat root_status{};
  struct stat file_status{};
  require(::lstat((temporary.path() / "audit").c_str(), &root_status) == 0 &&
              ::lstat((temporary.path() / "audit/audit.snapshot").c_str(),
                      &file_status) == 0 &&
              (root_status.st_mode & 0077) == 0 &&
              (file_status.st_mode & 0077) == 0,
          "audit storage is not owner-only");
}

void test_validation_and_authoritative_time() {
  TemporaryDirectory temporary;
  audit::AuditStore store(temporary.path() / "audit", {.maximum_records = 4});
  require(store.recover().ok(), "create validation store");
  auto invalid = operation_draft();
  invalid.correlation = 0;
  require(
      store.append(permissions::AuditProducer::broker, invalid).status.code ==
          audit::ErrorCode::invalid_argument,
      "invalid B2 draft entered durable audit");
  require(store.append(static_cast<permissions::AuditProducer>(255),
                       operation_draft())
                  .status.code == audit::ErrorCode::invalid_argument,
          "untrusted producer enumeration entered durable audit");
  require(store.append(permissions::AuditProducer::broker, operation_draft())
              .status.ok(),
          "authoritative time fixture append failed");
  require(store.append(permissions::AuditProducer::supervisor, worker_draft())
              .status.ok(),
          "supervisor worker event append failed");
  audit::Query worker_query;
  worker_query.event = permissions::AuditEvent::worker_crashed;
  const auto workers = store.query(worker_query);
  require(workers.status.ok() && workers.records.size() == 1 &&
              workers.records.front().producer ==
                  permissions::AuditProducer::supervisor &&
              !workers.records.front().operation &&
              !workers.records.front().capability,
          "supervisor worker event did not round-trip redacted");
  audit::Query unbounded;
  unbounded.maximum_results = 0;
  require(store.query(unbounded).status.code ==
              audit::ErrorCode::invalid_argument,
          "unbounded query shape was accepted");
}

void test_dynamic_identity_round_trip() {
  TemporaryDirectory temporary;
  audit::AuditStore store(temporary.path() / "audit", {.maximum_records = 4});
  require(store.recover().ok(), "create dynamic audit store");
  const auto appended =
      store.append(permissions::AuditProducer::broker, dynamic_draft());
  require(appended.status.ok() && appended.record &&
              appended.record->dynamic_operation.has_value(),
          "append dynamic audit identity");
  audit::AuditStore reopened(temporary.path() / "audit", {.maximum_records = 4});
  require(reopened.recover().ok(), "recover dynamic audit store");
  const auto records = reopened.query({});
  require(records.status.ok() && records.records.size() == 1 &&
              records.records[0].dynamic_operation ==
                  dynamic_draft().dynamic_operation,
          "dynamic audit identity did not survive durable round trip");
}

void test_audit_format_migration_and_malformed_dynamic() {
  TemporaryDirectory legacy;
  const auto legacy_root = legacy.path() / "audit";
  std::filesystem::create_directory(legacy_root);
  std::filesystem::permissions(legacy_root, std::filesystem::perms::owner_all);
  write_bytes(legacy_root / "audit.snapshot", legacy_v1_snapshot());
  audit::AuditStore old_store(legacy_root, {.maximum_records = 4});
  require(old_store.recover().ok(), "format-v1 audit snapshot did not recover");
  const auto old_records = old_store.query({});
  require(old_records.status.ok() && old_records.records.size() == 1 &&
              !old_records.records[0].dynamic_operation.has_value(),
          "format-v1 audit record acquired a dynamic identity");

  TemporaryDirectory malformed;
  const auto malformed_root = malformed.path() / "audit";
  audit::AuditStore new_store(malformed_root, {.maximum_records = 4});
  require(new_store.recover().ok() &&
              new_store.append(permissions::AuditProducer::broker,
                               dynamic_draft()).status.ok(),
          "malformed-v2 fixture setup failed");
  const auto snapshot = malformed_root / "audit.snapshot";
  std::ifstream input(snapshot, std::ios::binary);
  std::vector<unsigned char> bytes((std::istreambuf_iterator<char>(input)), {});
  input.close();
  const std::array<unsigned char, 8> epoch{0, 0, 0, 0, 0, 0, 0, 7};
  auto found = bytes.end();
  for (auto iterator = bytes.begin(); iterator + 8 <= bytes.end(); ++iterator)
    if (std::equal(epoch.begin(), epoch.end(), iterator)) found = iterator;
  require(found != bytes.end(), "dynamic epoch was not encoded");
  std::fill(found, found + 8, 0);
  write_bytes(snapshot, bytes);
  require(new_store.recover().code == audit::ErrorCode::corrupt_store,
          "format-v2 zero dynamic epoch was accepted");
}

void test_crash_boundaries() {
  TemporaryDirectory temporary;
  audit::AuditStore store(temporary.path() / "audit", {.maximum_records = 4});
  require(store.recover().ok(), "create crash store");
  require(store.append(permissions::AuditProducer::broker, operation_draft())
              .status.ok(),
          "crash baseline append failed");

  require(store.append(permissions::AuditProducer::broker, operation_draft(8),
                       audit::FaultPoint::append_after_write)
                  .status.code == audit::ErrorCode::injected_failure,
          "after-write fault did not fire");
  require(store.recover().ok() && store.query({}).records.size() == 1,
          "after-write recovery changed committed state");
  require(store.append(permissions::AuditProducer::broker, operation_draft(8),
                       audit::FaultPoint::append_after_file_sync)
                  .status.code == audit::ErrorCode::injected_failure,
          "after-sync fault did not fire");
  require(store.recover().ok() && store.query({}).records.size() == 1,
          "pre-rename recovery changed committed state");
  require(store.append(permissions::AuditProducer::broker, operation_draft(8),
                       audit::FaultPoint::append_after_rename)
                  .status.code == audit::ErrorCode::injected_failure,
          "after-rename fault did not fire");
  require(store.recover().ok(), "post-rename recovery failed");
  const auto recovered = store.query({});
  require(recovered.status.ok() && recovered.records.size() == 2 &&
              recovered.records.back().sequence == 2,
          "renamed complete snapshot did not recover");

  std::ofstream(temporary.path() / "audit/.audit.tmp") << "torn";
  require(store.recover().ok() &&
              !std::filesystem::exists(temporary.path() / "audit/.audit.tmp"),
          "orphan transaction was not removed");
}

void test_corruption_torn_and_symlink_fail_closed() {
  TemporaryDirectory temporary;
  const auto root = temporary.path() / "audit";
  audit::AuditStore store(root, {.maximum_records = 4});
  require(
      store.recover().ok() &&
          store.append(permissions::AuditProducer::broker, operation_draft())
              .status.ok(),
      "corruption fixture setup failed");
  const auto snapshot = root / "audit.snapshot";
  const auto size = std::filesystem::file_size(snapshot);
  std::filesystem::resize_file(snapshot, size - 1);
  require(store.recover().code == audit::ErrorCode::corrupt_store,
          "torn committed snapshot was silently accepted");

  std::filesystem::resize_file(snapshot, 0);
  require(store.recover().code == audit::ErrorCode::corrupt_store,
          "zero-length torn snapshot reset durable sequencing");

  std::filesystem::remove(snapshot);
  std::filesystem::create_symlink("/etc/passwd", snapshot);
  require(!store.query({}).status.ok(), "audit snapshot symlink was followed");

  const auto corrupt_root = temporary.path() / "corrupt";
  audit::AuditStore corrupt(corrupt_root, {.maximum_records = 4});
  require(
      corrupt.recover().ok() &&
          corrupt.append(permissions::AuditProducer::broker, operation_draft())
              .status.ok(),
      "fingerprint corruption fixture setup failed");
  const auto corrupt_snapshot = corrupt_root / "audit.snapshot";
  std::fstream mutation(corrupt_snapshot,
                        std::ios::in | std::ios::out | std::ios::binary);
  mutation.seekg(-1, std::ios::end);
  char byte = 0;
  mutation.read(&byte, 1);
  byte = static_cast<char>(static_cast<unsigned char>(byte) ^ 0x01U);
  mutation.seekp(-1, std::ios::end);
  mutation.write(&byte, 1);
  mutation.close();
  require(corrupt.recover().code == audit::ErrorCode::corrupt_store,
          "fingerprint mutation was silently accepted");

  const auto unsafe_root = temporary.path() / "unsafe";
  std::filesystem::create_directory(unsafe_root);
  std::filesystem::permissions(unsafe_root,
                               std::filesystem::perms::owner_all |
                                   std::filesystem::perms::group_read);
  audit::AuditStore unsafe(unsafe_root, {});
  require(unsafe.recover().code == audit::ErrorCode::unsafe_store,
          "non-owner-only audit root was accepted");
}

} // namespace

int main() {
  try {
    test_append_query_export_and_retention();
    test_validation_and_authoritative_time();
    test_dynamic_identity_round_trip();
    test_audit_format_migration_and_malformed_dynamic();
    test_crash_boundaries();
    test_corruption_torn_and_symlink_fail_closed();
    std::cout << "audit store tests passed\n";
    return EXIT_SUCCESS;
  } catch (const std::exception &failure) {
    std::cerr << "audit store test failed: " << failure.what() << '\n';
    return EXIT_FAILURE;
  }
}
