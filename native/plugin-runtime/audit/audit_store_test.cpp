#include "audit_store.hpp"

#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>
#include <string_view>
#include <sys/stat.h>
#include <unistd.h>

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
      .operation = std::nullopt,
      .capability = storage_key(),
      .decision = permissions::GrantDecisionCode::revoked,
      .metadata = {},
  };
}

permissions::AuditDraft worker_draft() {
  permissions::AuditDraft draft{
      .event = permissions::AuditEvent::worker_crashed,
      .outcome = permissions::AuditOutcome::failed,
      .plugin = permissions::PluginId("org.example.timer"),
      .revision = digest('a'),
      .generation = 9,
      .correlation = 0,
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
    test_crash_boundaries();
    test_corruption_torn_and_symlink_fail_closed();
    std::cout << "audit store tests passed\n";
    return EXIT_SUCCESS;
  } catch (const std::exception &failure) {
    std::cerr << "audit store test failed: " << failure.what() << '\n';
    return EXIT_FAILURE;
  }
}
