#include "audit_store.hpp"

#include <algorithm>
#include <array>
#include <cerrno>
#include <cstring>
#include <dirent.h>
#include <fcntl.h>
#include <limits>
#include <span>
#include <stdexcept>
#include <string_view>
#include <sys/file.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <time.h>
#include <unistd.h>

namespace omarchy::plugins::audit {
namespace {

constexpr std::string_view kMagic = "OMARCHY-AUDIT-V1";
constexpr std::uint32_t kFormatVersion = 1;
constexpr std::size_t kHeaderBytes = 32;
constexpr std::size_t kMaximumRecordBytes = 512;
constexpr std::size_t kMaximumSnapshotBytes =
    kHeaderBytes + kHardMaximumRecords * (4 + kMaximumRecordBytes);

class Failure final : public std::runtime_error {
public:
  Failure(ErrorCode code, std::string detail)
      : std::runtime_error(std::move(detail)), code(code) {}
  ErrorCode code;
};

class Fd {
public:
  explicit Fd(int value = -1) : value_(value) {}
  ~Fd() {
    if (value_ >= 0)
      ::close(value_);
  }
  Fd(const Fd &) = delete;
  Fd &operator=(const Fd &) = delete;
  Fd(Fd &&other) noexcept : value_(other.value_) { other.value_ = -1; }
  [[nodiscard]] int get() const { return value_; }

private:
  int value_;
};

[[noreturn]] void fail_errno(std::string_view operation) {
  throw Failure(ErrorCode::io_error,
                std::string(operation) + ": " + std::strerror(errno));
}

void check(bool condition, std::string_view operation) {
  if (!condition)
    fail_errno(operation);
}

bool canonical_id(std::string_view value) {
  if (value.empty() || value.size() > 128)
    return false;
  bool separator_before = true;
  for (const char character : value) {
    const bool separator =
        character == '.' || character == '-' || character == '_';
    const bool alphanumeric = (character >= 'a' && character <= 'z') ||
                              (character >= '0' && character <= '9');
    if ((!separator && !alphanumeric) || (separator && separator_before))
      return false;
    separator_before = separator;
  }
  return !separator_before;
}

Fd open_store(const std::filesystem::path &root, bool create) {
  if (create && ::mkdir(root.c_str(), 0700) < 0 && errno != EEXIST)
    fail_errno("create audit root");
  const int raw =
      ::open(root.c_str(), O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
  if (raw < 0)
    fail_errno("open audit root");
  Fd descriptor(raw);
  struct stat status{};
  check(::fstat(descriptor.get(), &status) == 0, "inspect audit root");
  if (status.st_uid != ::geteuid() || (status.st_mode & 0077) != 0)
    throw Failure(ErrorCode::unsafe_store, "audit root is not owner-only");
  if (::flock(descriptor.get(), LOCK_EX) < 0)
    fail_errno("lock audit root");
  return descriptor;
}

void put8(std::vector<std::byte> &output, std::uint8_t value) {
  output.push_back(static_cast<std::byte>(value));
}

void put16(std::vector<std::byte> &output, std::uint16_t value) {
  put8(output, static_cast<std::uint8_t>(value >> 8U));
  put8(output, static_cast<std::uint8_t>(value));
}

void put32(std::vector<std::byte> &output, std::uint32_t value) {
  for (int shift = 24; shift >= 0; shift -= 8)
    put8(output, static_cast<std::uint8_t>(value >> shift));
}

void put64(std::vector<std::byte> &output, std::uint64_t value) {
  for (int shift = 56; shift >= 0; shift -= 8)
    put8(output, static_cast<std::uint8_t>(value >> shift));
}

void put_text(std::vector<std::byte> &output, std::string_view value) {
  if (value.size() > std::numeric_limits<std::uint16_t>::max())
    throw Failure(ErrorCode::invalid_argument, "audit field is oversized");
  put16(output, static_cast<std::uint16_t>(value.size()));
  for (const char character : value)
    put8(output, static_cast<std::uint8_t>(character));
}

class Reader {
public:
  explicit Reader(std::span<const std::byte> bytes) : bytes_(bytes) {}

  std::uint8_t get8() {
    require(1);
    return std::to_integer<std::uint8_t>(bytes_[offset_++]);
  }
  std::uint16_t get16() {
    std::uint16_t result = 0;
    for (int index = 0; index < 2; ++index)
      result = static_cast<std::uint16_t>((result << 8U) | get8());
    return result;
  }
  std::uint32_t get32() {
    std::uint32_t result = 0;
    for (int index = 0; index < 4; ++index)
      result = (result << 8U) | get8();
    return result;
  }
  std::uint64_t get64() {
    std::uint64_t result = 0;
    for (int index = 0; index < 8; ++index)
      result = (result << 8U) | get8();
    return result;
  }
  std::string get_text(std::size_t maximum) {
    const std::size_t size = get16();
    if (size > maximum)
      throw Failure(ErrorCode::corrupt_store, "audit text bound exceeded");
    require(size);
    const auto start = bytes_.subspan(offset_, size);
    offset_ += size;
    return {reinterpret_cast<const char *>(start.data()), start.size()};
  }
  std::span<const std::byte> take(std::size_t size) {
    require(size);
    const auto result = bytes_.subspan(offset_, size);
    offset_ += size;
    return result;
  }
  [[nodiscard]] bool empty() const { return offset_ == bytes_.size(); }

private:
  void require(std::size_t size) const {
    if (size > bytes_.size() - offset_)
      throw Failure(ErrorCode::corrupt_store, "audit record is truncated");
  }
  std::span<const std::byte> bytes_;
  std::size_t offset_ = 0;
};

std::vector<std::byte> encode_record(const permissions::AuditRecord &record) {
  permissions::validate_audit_draft(record);
  if (!permissions::valid_audit_producer(record.producer) ||
      record.sequence == 0 || record.wall_seconds == 0 ||
      record.monotonic_ns == 0)
    throw Failure(ErrorCode::invalid_argument,
                  "audit authority fields are invalid");
  std::vector<std::byte> output;
  output.reserve(kMaximumRecordBytes);
  put64(output, record.sequence);
  put64(output, record.wall_seconds);
  put64(output, record.monotonic_ns);
  put8(output, static_cast<std::uint8_t>(record.producer));
  put8(output, static_cast<std::uint8_t>(record.event));
  put8(output, static_cast<std::uint8_t>(record.outcome));
  put8(output, static_cast<std::uint8_t>(record.decision));
  put_text(output, record.plugin.view());
  put_text(output, record.revision.view());
  put64(output, record.generation);
  put64(output, record.correlation);
  put8(output, record.operation ? 1 : 0);
  put16(output,
        record.operation ? static_cast<std::uint16_t>(*record.operation) : 0);
  put8(output, record.capability ? 1 : 0);
  put_text(output, record.capability ? record.capability->id.view() : "");
  put16(output, record.capability ? record.capability->version : 0);
  put8(output, static_cast<std::uint8_t>(record.metadata.size()));
  for (std::uint8_t metric = 0;
       metric <=
       static_cast<std::uint8_t>(permissions::AuditMetric::retry_after_seconds);
       ++metric) {
    const auto found = std::find_if(
        record.metadata.values().begin(), record.metadata.values().end(),
        [metric](const permissions::AuditMetadata &item) {
          return static_cast<std::uint8_t>(item.metric) == metric;
        });
    if (found != record.metadata.values().end()) {
      put8(output, metric);
      put64(output, static_cast<std::uint64_t>(found->value));
    }
  }
  put_text(output, permissions::audit_record_fingerprint(record));
  if (output.size() > kMaximumRecordBytes)
    throw Failure(ErrorCode::invalid_argument,
                  "encoded audit record is oversized");
  return output;
}

permissions::AuditRecord decode_record(std::span<const std::byte> bytes) {
  Reader reader(bytes);
  permissions::AuditRecord record;
  record.sequence = reader.get64();
  record.wall_seconds = reader.get64();
  record.monotonic_ns = reader.get64();
  record.producer = static_cast<permissions::AuditProducer>(reader.get8());
  record.event = static_cast<permissions::AuditEvent>(reader.get8());
  record.outcome = static_cast<permissions::AuditOutcome>(reader.get8());
  record.decision = static_cast<permissions::GrantDecisionCode>(reader.get8());
  record.plugin = permissions::PluginId(reader.get_text(128));
  record.revision = permissions::Digest(reader.get_text(64));
  record.generation = reader.get64();
  record.correlation = reader.get64();
  const auto operation_present = reader.get8();
  const auto operation = reader.get16();
  if (operation_present > 1 || (!operation_present && operation != 0))
    throw Failure(ErrorCode::corrupt_store, "invalid operation presence field");
  if (operation_present)
    record.operation = static_cast<permissions::OperationId>(operation);
  const auto capability_present = reader.get8();
  const auto capability_id = reader.get_text(128);
  const auto capability_version = reader.get16();
  if (capability_present > 1 ||
      (!capability_present &&
       (!capability_id.empty() || capability_version != 0)))
    throw Failure(ErrorCode::corrupt_store,
                  "invalid capability presence field");
  if (capability_present)
    record.capability = permissions::CapabilityKey{
        permissions::CapabilityId(capability_id), capability_version};
  const auto metric_count = reader.get8();
  if (metric_count > 8)
    throw Failure(ErrorCode::corrupt_store, "audit metric count exceeded");
  for (std::size_t index = 0; index < metric_count; ++index) {
    const auto metric = static_cast<permissions::AuditMetric>(reader.get8());
    const auto raw_value = reader.get64();
    if (raw_value >
        static_cast<std::uint64_t>(std::numeric_limits<std::int64_t>::max()))
      throw Failure(ErrorCode::corrupt_store, "audit metric value is negative");
    record.metadata.push_back(
        {.metric = metric, .value = static_cast<std::int64_t>(raw_value)});
  }
  const auto fingerprint = reader.get_text(64);
  if (!reader.empty() || record.sequence == 0 || record.wall_seconds == 0 ||
      record.monotonic_ns == 0 ||
      !permissions::valid_audit_producer(record.producer))
    throw Failure(ErrorCode::corrupt_store,
                  "audit record authority fields are invalid");
  try {
    permissions::validate_audit_draft(record);
    if (permissions::audit_record_fingerprint(record) != fingerprint)
      throw Failure(ErrorCode::corrupt_store,
                    "audit record fingerprint mismatch");
  } catch (const Failure &) {
    throw;
  } catch (const std::exception &) {
    throw Failure(ErrorCode::corrupt_store, "audit record validation failed");
  }
  return record;
}

struct Snapshot {
  std::uint64_t last_sequence = 0;
  std::vector<permissions::AuditRecord> records;
};

std::vector<std::byte> encode_snapshot(const Snapshot &snapshot) {
  if (snapshot.records.size() > kHardMaximumRecords ||
      (snapshot.records.empty()
           ? snapshot.last_sequence != 0
           : snapshot.records.back().sequence != snapshot.last_sequence))
    throw Failure(ErrorCode::corrupt_store, "audit snapshot state is invalid");
  std::vector<std::byte> output;
  output.reserve(kHeaderBytes + snapshot.records.size() * kMaximumRecordBytes);
  for (const char character : kMagic)
    put8(output, static_cast<std::uint8_t>(character));
  put32(output, kFormatVersion);
  put64(output, snapshot.last_sequence);
  put32(output, static_cast<std::uint32_t>(snapshot.records.size()));
  for (const auto &record : snapshot.records) {
    const auto encoded = encode_record(record);
    put32(output, static_cast<std::uint32_t>(encoded.size()));
    output.insert(output.end(), encoded.begin(), encoded.end());
  }
  return output;
}

Snapshot decode_snapshot(std::span<const std::byte> bytes) {
  if (bytes.size() < kHeaderBytes)
    throw Failure(ErrorCode::corrupt_store,
                  "audit snapshot header is truncated");
  Reader reader(bytes);
  const auto magic = reader.take(kMagic.size());
  if (!std::equal(magic.begin(), magic.end(),
                  reinterpret_cast<const std::byte *>(kMagic.data())))
    throw Failure(ErrorCode::corrupt_store, "audit snapshot magic is invalid");
  if (reader.get32() != kFormatVersion)
    throw Failure(ErrorCode::corrupt_store,
                  "audit snapshot version is invalid");
  Snapshot snapshot;
  snapshot.last_sequence = reader.get64();
  const auto count = reader.get32();
  if (count > kHardMaximumRecords)
    throw Failure(ErrorCode::corrupt_store, "audit record count exceeded");
  snapshot.records.reserve(count);
  for (std::size_t index = 0; index < count; ++index) {
    const auto length = reader.get32();
    if (length == 0 || length > kMaximumRecordBytes)
      throw Failure(ErrorCode::corrupt_store, "audit frame length is invalid");
    auto record = decode_record(reader.take(length));
    if (!snapshot.records.empty() &&
        record.sequence != snapshot.records.back().sequence + 1)
      throw Failure(ErrorCode::corrupt_store,
                    "audit sequence is not contiguous");
    snapshot.records.push_back(std::move(record));
  }
  if (!reader.empty() ||
      (snapshot.records.empty()
           ? snapshot.last_sequence != 0
           : snapshot.records.back().sequence != snapshot.last_sequence))
    throw Failure(ErrorCode::corrupt_store,
                  "audit snapshot trailer is invalid");
  return snapshot;
}

void write_all(int descriptor, std::span<const std::byte> bytes) {
  while (!bytes.empty()) {
    const ssize_t count = ::write(descriptor, bytes.data(), bytes.size());
    if (count < 0 && errno == EINTR)
      continue;
    if (count < 0)
      fail_errno("write audit snapshot");
    bytes = bytes.subspan(static_cast<std::size_t>(count));
  }
}

std::optional<std::vector<std::byte>> read_snapshot_file(int root,
                                                         bool missing_allowed) {
  const int raw =
      ::openat(root, "audit.snapshot", O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
  if (raw < 0 && missing_allowed && errno == ENOENT)
    return std::nullopt;
  if (raw < 0)
    fail_errno("open audit snapshot");
  Fd descriptor(raw);
  struct stat status{};
  check(::fstat(descriptor.get(), &status) == 0, "inspect audit snapshot");
  if (!S_ISREG(status.st_mode) || status.st_uid != ::geteuid() ||
      (status.st_mode & 0077) != 0 || status.st_size < 0 ||
      static_cast<std::uint64_t>(status.st_size) > kMaximumSnapshotBytes)
    throw Failure(ErrorCode::unsafe_store,
                  "audit snapshot type, owner, mode, or size is unsafe");
  std::vector<std::byte> bytes(static_cast<std::size_t>(status.st_size));
  std::size_t offset = 0;
  while (offset < bytes.size()) {
    const ssize_t count =
        ::read(descriptor.get(), bytes.data() + offset, bytes.size() - offset);
    if (count < 0 && errno == EINTR)
      continue;
    if (count <= 0)
      throw Failure(ErrorCode::corrupt_store, "audit snapshot was torn");
    offset += static_cast<std::size_t>(count);
  }
  struct stat after{};
  check(::fstat(descriptor.get(), &after) == 0, "reinspect audit snapshot");
  if (after.st_size != status.st_size ||
      after.st_mtim.tv_sec != status.st_mtim.tv_sec ||
      after.st_mtim.tv_nsec != status.st_mtim.tv_nsec ||
      after.st_ctim.tv_sec != status.st_ctim.tv_sec ||
      after.st_ctim.tv_nsec != status.st_ctim.tv_nsec)
    throw Failure(ErrorCode::corrupt_store,
                  "audit snapshot changed while being read");
  return bytes;
}

Snapshot load_snapshot(int root) {
  const auto bytes = read_snapshot_file(root, true);
  return bytes ? decode_snapshot(*bytes) : Snapshot{};
}

std::pair<std::uint64_t, std::uint64_t> authoritative_time() {
  timespec wall{};
  timespec monotonic{};
  if (::clock_gettime(CLOCK_REALTIME, &wall) < 0 ||
      ::clock_gettime(CLOCK_BOOTTIME, &monotonic) < 0)
    fail_errno("read authoritative audit clock");
  constexpr std::uint64_t billion = 1'000'000'000;
  if (wall.tv_sec <= 0 || monotonic.tv_sec < 0 || monotonic.tv_nsec < 0 ||
      monotonic.tv_nsec >= static_cast<long>(billion) ||
      static_cast<std::uint64_t>(monotonic.tv_sec) >
          (std::numeric_limits<std::uint64_t>::max() -
           static_cast<std::uint64_t>(monotonic.tv_nsec)) /
              billion)
    throw Failure(ErrorCode::io_error, "authoritative audit clock is invalid");
  return {static_cast<std::uint64_t>(wall.tv_sec),
          static_cast<std::uint64_t>(monotonic.tv_sec) * billion +
              static_cast<std::uint64_t>(monotonic.tv_nsec)};
}

void publish_snapshot(int root, const Snapshot &snapshot, FaultPoint fault) {
  const auto bytes = encode_snapshot(snapshot);
  const int raw =
      ::openat(root, ".audit.tmp",
               O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, 0600);
  if (raw < 0)
    fail_errno("create audit transaction");
  Fd descriptor(raw);
  try {
    write_all(descriptor.get(), bytes);
    if (fault == FaultPoint::append_after_write)
      throw Failure(ErrorCode::injected_failure, "injected after audit write");
    check(::fsync(descriptor.get()) == 0, "sync audit transaction");
    if (fault == FaultPoint::append_after_file_sync)
      throw Failure(ErrorCode::injected_failure,
                    "injected after audit file sync");
    check(::renameat(root, ".audit.tmp", root, "audit.snapshot") == 0,
          "publish audit snapshot");
    if (fault == FaultPoint::append_after_rename)
      throw Failure(ErrorCode::injected_failure, "injected after audit rename");
    check(::fsync(root) == 0, "sync audit root");
  } catch (...) {
    if (fault != FaultPoint::append_after_rename)
      ::unlinkat(root, ".audit.tmp", 0);
    throw;
  }
}

bool matches(const permissions::AuditRecord &record, const Query &query) {
  return (query.sequence_at_least == 0 ||
          record.sequence >= query.sequence_at_least) &&
         (query.sequence_at_most == 0 ||
          record.sequence <= query.sequence_at_most) &&
         (!query.plugin || record.plugin == *query.plugin) &&
         (!query.producer || record.producer == *query.producer) &&
         (!query.event || record.event == *query.event) &&
         (!query.outcome || record.outcome == *query.outcome);
}

void validate_query(const Query &query) {
  if (query.maximum_results == 0 ||
      query.maximum_results > kHardMaximumRecords ||
      (query.sequence_at_least != 0 && query.sequence_at_most != 0 &&
       query.sequence_at_least > query.sequence_at_most) ||
      (query.plugin && !canonical_id(query.plugin->view())) ||
      (query.producer && !permissions::valid_audit_producer(*query.producer)) ||
      (query.event &&
       static_cast<std::uint8_t>(*query.event) >
           static_cast<std::uint8_t>(permissions::AuditEvent::handle_denied)) ||
      (query.outcome &&
       static_cast<std::uint8_t>(*query.outcome) >
           static_cast<std::uint8_t>(permissions::AuditOutcome::failed)))
    throw Failure(ErrorCode::invalid_argument, "audit query is invalid");
}

std::string optional_number(const auto &value) {
  return value ? std::to_string(static_cast<std::uint64_t>(*value)) : "-";
}

} // namespace

AuditStore::AuditStore(std::filesystem::path root, Options options)
    : root_(std::move(root)), options_(options) {}

Result AuditStore::recover() {
  try {
    if (options_.maximum_records == 0 ||
        options_.maximum_records > kHardMaximumRecords)
      throw Failure(ErrorCode::invalid_argument,
                    "audit retention bound is invalid");
    auto root = open_store(root_, true);
    if (::unlinkat(root.get(), ".audit.tmp", 0) < 0 && errno != ENOENT)
      fail_errno("remove incomplete audit transaction");
    auto snapshot = load_snapshot(root.get());
    if (snapshot.records.size() > options_.maximum_records) {
      snapshot.records.erase(
          snapshot.records.begin(),
          snapshot.records.end() -
              static_cast<std::ptrdiff_t>(options_.maximum_records));
      publish_snapshot(root.get(), snapshot, FaultPoint::none);
    }
    check(::fsync(root.get()) == 0, "sync recovered audit root");
    return {};
  } catch (const Failure &failure) {
    return {failure.code, failure.what()};
  } catch (const std::exception &failure) {
    return {ErrorCode::corrupt_store, failure.what()};
  }
}

AppendResult AuditStore::append(permissions::AuditProducer producer,
                                permissions::AuditDraft draft,
                                FaultPoint fault) {
  try {
    if (options_.maximum_records == 0 ||
        options_.maximum_records > kHardMaximumRecords ||
        !permissions::valid_audit_producer(producer))
      throw Failure(ErrorCode::invalid_argument,
                    "audit append authority is invalid");
    try {
      permissions::validate_audit_draft(draft);
    } catch (const std::exception &) {
      throw Failure(ErrorCode::invalid_argument, "audit draft is invalid");
    }
    auto root = open_store(root_, true);
    if (::unlinkat(root.get(), ".audit.tmp", 0) < 0 && errno != ENOENT)
      fail_errno("remove stale audit transaction");
    auto snapshot = load_snapshot(root.get());
    if (snapshot.last_sequence == std::numeric_limits<std::uint64_t>::max())
      throw Failure(ErrorCode::sequence_exhausted,
                    "audit sequence is exhausted");
    auto [wall_seconds, monotonic_ns] = authoritative_time();
    if (!snapshot.records.empty() &&
        monotonic_ns <= snapshot.records.back().monotonic_ns) {
      if (snapshot.records.back().monotonic_ns ==
          std::numeric_limits<std::uint64_t>::max())
        throw Failure(ErrorCode::sequence_exhausted,
                      "audit monotonic sequence is exhausted");
      monotonic_ns = snapshot.records.back().monotonic_ns + 1;
    }
    permissions::AuditRecord record;
    static_cast<permissions::AuditDraft &>(record) = std::move(draft);
    record.sequence = snapshot.last_sequence + 1;
    record.wall_seconds = wall_seconds;
    record.monotonic_ns = monotonic_ns;
    record.producer = producer;
    (void)encode_record(record);
    snapshot.last_sequence = record.sequence;
    snapshot.records.push_back(record);
    if (snapshot.records.size() > options_.maximum_records)
      snapshot.records.erase(snapshot.records.begin());
    publish_snapshot(root.get(), snapshot, fault);
    return {{}, record};
  } catch (const Failure &failure) {
    return {{failure.code, failure.what()}, std::nullopt};
  } catch (const std::exception &failure) {
    return {{ErrorCode::corrupt_store, failure.what()}, std::nullopt};
  }
}

QueryResult AuditStore::query(const Query &query_value) const {
  QueryResult result;
  try {
    validate_query(query_value);
    auto root = open_store(root_, false);
    const auto snapshot = load_snapshot(root.get());
    result.records.reserve(
        std::min(query_value.maximum_results, snapshot.records.size()));
    for (const auto &record : snapshot.records) {
      if (matches(record, query_value) &&
          result.records.size() < query_value.maximum_results)
        result.records.push_back(record);
    }
  } catch (const Failure &failure) {
    result.status = {failure.code, failure.what()};
  } catch (const std::exception &failure) {
    result.status = {ErrorCode::corrupt_store, failure.what()};
  }
  return result;
}

Result AuditStore::export_tsv(const Query &query_value,
                              std::string &output) const {
  const auto selected = query(query_value);
  if (!selected.status.ok())
    return selected.status;
  std::string result =
      "sequence\twall_seconds\tmonotonic_"
      "ns\tproducer\tevent\toutcome\tplugin\trevision\tgeneration\tcorrelation"
      "\toperation\tcapability\tdecision\tmetrics\tfingerprint\n";
  for (const auto &record : selected.records) {
    result +=
        std::to_string(record.sequence) + "\t" +
        std::to_string(record.wall_seconds) + "\t" +
        std::to_string(record.monotonic_ns) + "\t" +
        std::to_string(static_cast<std::uint8_t>(record.producer)) + "\t" +
        std::to_string(static_cast<std::uint8_t>(record.event)) + "\t" +
        std::to_string(static_cast<std::uint8_t>(record.outcome)) + "\t" +
        std::string(record.plugin.view()) + "\t" +
        std::string(record.revision.view()) + "\t" +
        std::to_string(record.generation) + "\t" +
        std::to_string(record.correlation) + "\t" +
        optional_number(record.operation) + "\t" +
        (record.capability ? std::string(record.capability->id.view()) + ":" +
                                 std::to_string(record.capability->version)
                           : "-") +
        "\t" + std::to_string(static_cast<std::uint8_t>(record.decision)) +
        "\t";
    bool first = true;
    for (const auto &metric : record.metadata.values()) {
      if (!first)
        result += ',';
      first = false;
      result += std::to_string(static_cast<std::uint8_t>(metric.metric)) + ":" +
                std::to_string(metric.value);
    }
    result += "\t" + permissions::audit_record_fingerprint(record) + "\n";
  }
  output = std::move(result);
  return {};
}

} // namespace omarchy::plugins::audit
