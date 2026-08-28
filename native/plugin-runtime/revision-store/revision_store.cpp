#include "revision_store.hpp"

#include "manifest_contract.hpp"

#include <algorithm>
#include <array>
#include <cerrno>
#include <charconv>
#include <cstring>
#include <dirent.h>
#include <fcntl.h>
#include <limits>
#include <stdexcept>
#include <string_view>
#include <sys/file.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>
#include <vector>

namespace omarchy::plugins::store {
namespace {

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
  Fd &operator=(Fd &&other) noexcept {
    if (this != &other) {
      if (value_ >= 0)
        ::close(value_);
      value_ = other.value_;
      other.value_ = -1;
    }
    return *this;
  }
  [[nodiscard]] int get() const { return value_; }

private:
  int value_;
};

[[noreturn]] void fail_errno(std::string_view operation) {
  throw Failure(ErrorCode::io_error,
                std::string(operation) + ": " + std::strerror(errno));
}

void check(bool value, std::string_view operation) {
  if (!value)
    fail_errno(operation);
}

bool valid_digest(std::string_view value) {
  return value.size() == 64 &&
         std::all_of(value.begin(), value.end(), [](char character) {
           return (character >= '0' && character <= '9') ||
                  (character >= 'a' && character <= 'f');
         });
}

bool valid_plugin_id(std::string_view value) {
  if (value.empty() || value.size() > 128)
    return false;
  bool previous_separator = true;
  for (const char character : value) {
    const bool separator =
        character == '.' || character == '-' || character == '_';
    const bool alphanumeric = (character >= 'a' && character <= 'z') ||
                              (character >= '0' && character <= '9');
    if ((!alphanumeric && !separator) || (separator && previous_separator))
      return false;
    previous_separator = separator;
  }
  return !previous_separator;
}

Fd open_directory_at(int parent, const char *name) {
  const int descriptor =
      ::openat(parent, name, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
  if (descriptor < 0)
    fail_errno(std::string("open directory ") + name);
  return Fd(descriptor);
}

std::filesystem::path descriptor_path(int descriptor) {
  return std::filesystem::path("/proc/self/fd") / std::to_string(descriptor);
}

void ensure_directory_at(int parent, const char *name, mode_t mode) {
  if (::mkdirat(parent, name, mode) < 0 && errno != EEXIST)
    fail_errno(std::string("create directory ") + name);
  auto directory = open_directory_at(parent, name);
  struct stat status{};
  check(::fstat(directory.get(), &status) == 0, "inspect directory");
  if (status.st_uid != ::geteuid() || (status.st_mode & 0077) != 0)
    throw Failure(ErrorCode::unsafe_store,
                  std::string(name) + " is not owner-only");
}

Fd open_store(const std::filesystem::path &root, bool create) {
  if (create && ::mkdir(root.c_str(), 0700) < 0 && errno != EEXIST)
    fail_errno("create store root");
  const int descriptor =
      ::open(root.c_str(), O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
  if (descriptor < 0)
    fail_errno("open store root");
  Fd result(descriptor);
  struct stat status{};
  check(::fstat(result.get(), &status) == 0, "inspect store root");
  if (status.st_uid != ::geteuid() || (status.st_mode & 0077) != 0)
    throw Failure(ErrorCode::unsafe_store, "store root is not owner-only");
  if (::flock(result.get(), LOCK_EX) < 0)
    fail_errno("lock store root");
  ensure_directory_at(result.get(), "revisions", 0700);
  ensure_directory_at(result.get(), "metadata", 0700);
  ensure_directory_at(result.get(), "state", 0700);
  return result;
}

std::vector<std::string> entries(int directory,
                                 std::size_t maximum_entries = 8192) {
  const int duplicate = ::dup(directory);
  if (duplicate < 0)
    fail_errno("duplicate directory descriptor");
  DIR *stream = ::fdopendir(duplicate);
  if (stream == nullptr) {
    ::close(duplicate);
    fail_errno("open directory stream");
  }
  std::vector<std::string> result;
  errno = 0;
  while (const dirent *entry = ::readdir(stream)) {
    const std::string name(entry->d_name);
    if (name != "." && name != "..") {
      if (result.size() == maximum_entries) {
        ::closedir(stream);
        throw Failure(ErrorCode::limit_exceeded,
                      "directory entry limit exceeded");
      }
      result.push_back(name);
    }
    errno = 0;
  }
  const int read_error = errno;
  ::closedir(stream);
  if (read_error != 0) {
    errno = read_error;
    fail_errno("read directory");
  }
  std::sort(result.begin(), result.end());
  return result;
}

void write_all(int descriptor, std::string_view bytes) {
  while (!bytes.empty()) {
    const ssize_t written = ::write(descriptor, bytes.data(), bytes.size());
    if (written < 0) {
      if (errno == EINTR)
        continue;
      fail_errno("write file");
    }
    bytes.remove_prefix(static_cast<std::size_t>(written));
  }
}

std::string read_small_at(int parent, const char *name, std::size_t maximum,
                          bool missing_allowed = false) {
  const int raw = ::openat(parent, name, O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
  if (raw < 0 && missing_allowed && errno == ENOENT)
    return {};
  if (raw < 0)
    fail_errno(std::string("open ") + name);
  Fd descriptor(raw);
  struct stat status{};
  check(::fstat(descriptor.get(), &status) == 0, "inspect record");
  if (!S_ISREG(status.st_mode) || status.st_size < 0 ||
      static_cast<std::uint64_t>(status.st_size) > maximum)
    throw Failure(ErrorCode::corrupt_revision,
                  "record type or size is invalid");
  std::string bytes(static_cast<std::size_t>(status.st_size), '\0');
  std::size_t offset = 0;
  while (offset < bytes.size()) {
    const ssize_t count =
        ::read(descriptor.get(), bytes.data() + offset, bytes.size() - offset);
    if (count < 0 && errno == EINTR)
      continue;
    if (count <= 0)
      throw Failure(ErrorCode::corrupt_revision, "record was truncated");
    offset += static_cast<std::size_t>(count);
  }
  return bytes;
}

void atomic_record(int directory, const char *temporary, const char *name,
                   std::string_view bytes, FaultPoint fault,
                   FaultPoint after_write, FaultPoint after_sync,
                   FaultPoint after_rename) {
  const int raw =
      ::openat(directory, temporary,
               O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, 0600);
  if (raw < 0)
    fail_errno("create transaction record");
  Fd descriptor(raw);
  try {
    write_all(descriptor.get(), bytes);
    if (after_write != FaultPoint::none && fault == after_write)
      throw Failure(ErrorCode::injected_failure, "injected after record write");
    check(::fsync(descriptor.get()) == 0, "sync transaction record");
    if (after_sync != FaultPoint::none && fault == after_sync)
      throw Failure(ErrorCode::injected_failure, "injected after record sync");
    check(::renameat(directory, temporary, directory, name) == 0,
          "publish transaction record");
    if (after_rename != FaultPoint::none && fault == after_rename)
      throw Failure(ErrorCode::injected_failure,
                    "injected after record rename");
    check(::fsync(directory) == 0, "sync transaction directory");
  } catch (...) {
    if (after_rename == FaultPoint::none || fault != after_rename)
      ::unlinkat(directory, temporary, 0);
    throw;
  }
}

struct CopyBudget {
  std::size_t files = 0;
  std::size_t directories = 0;
  std::uint64_t bytes = 0;
};

void copy_tree(int source, int destination, const Options &options,
               CopyBudget &budget, std::size_t depth = 0) {
  for (const auto &name : entries(source)) {
    if (name == ".git")
      continue;
    struct stat before{};
    if (::fstatat(source, name.c_str(), &before, AT_SYMLINK_NOFOLLOW) < 0)
      fail_errno("inspect source entry");
    if (S_ISLNK(before.st_mode))
      throw Failure(ErrorCode::unsupported_entry, "source symlink rejected");
    if (S_ISDIR(before.st_mode)) {
      if (++budget.directories > options.maximum_directories ||
          depth >= options.maximum_depth)
        throw Failure(ErrorCode::limit_exceeded,
                      "staging directory limit exceeded");
      check(::mkdirat(destination, name.c_str(), 0700) == 0,
            "create staged directory");
      auto source_child = open_directory_at(source, name.c_str());
      auto destination_child = open_directory_at(destination, name.c_str());
      copy_tree(source_child.get(), destination_child.get(), options, budget,
                depth + 1);
      check(::fsync(destination_child.get()) == 0, "sync staged directory");
      check(::fchmod(destination_child.get(), 0500) == 0,
            "seal staged directory");
      continue;
    }
    if (!S_ISREG(before.st_mode) || before.st_size < 0)
      throw Failure(ErrorCode::unsupported_entry,
                    "source contains a non-regular entry");
    if (++budget.files > options.maximum_files ||
        static_cast<std::uint64_t>(before.st_size) >
            options.maximum_bytes - budget.bytes)
      throw Failure(ErrorCode::limit_exceeded, "staging budget exceeded");
    budget.bytes += static_cast<std::uint64_t>(before.st_size);

    const int source_raw =
        ::openat(source, name.c_str(), O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
    if (source_raw < 0)
      fail_errno("open source file");
    Fd source_file(source_raw);
    struct stat opened{};
    check(::fstat(source_file.get(), &opened) == 0, "inspect opened source");
    if (opened.st_dev != before.st_dev || opened.st_ino != before.st_ino ||
        opened.st_size != before.st_size || opened.st_mode != before.st_mode)
      throw Failure(ErrorCode::source_changed, "source changed before copy");
    const mode_t destination_mode = (before.st_mode & 0111) != 0 ? 0700 : 0600;
    const int destination_raw = ::openat(
        destination, name.c_str(),
        O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, destination_mode);
    if (destination_raw < 0)
      fail_errno("create staged file");
    Fd destination_file(destination_raw);
    std::array<char, 64 * 1024> buffer{};
    std::uint64_t copied = 0;
    for (;;) {
      const ssize_t count =
          ::read(source_file.get(), buffer.data(), buffer.size());
      if (count < 0 && errno == EINTR)
        continue;
      if (count < 0)
        fail_errno("read source file");
      if (count == 0)
        break;
      write_all(destination_file.get(),
                {buffer.data(), static_cast<std::size_t>(count)});
      copied += static_cast<std::uint64_t>(count);
    }
    struct stat after{};
    check(::fstat(source_file.get(), &after) == 0, "reinspect source file");
    if (copied != static_cast<std::uint64_t>(before.st_size) ||
        after.st_size != before.st_size ||
        after.st_mtim.tv_sec != opened.st_mtim.tv_sec ||
        after.st_mtim.tv_nsec != opened.st_mtim.tv_nsec ||
        after.st_ctim.tv_sec != opened.st_ctim.tv_sec ||
        after.st_ctim.tv_nsec != opened.st_ctim.tv_nsec)
      throw Failure(ErrorCode::source_changed, "source changed during copy");
    check(::fsync(destination_file.get()) == 0, "sync staged file");
    check(::fchmod(destination_file.get(),
                   (before.st_mode & 0111) != 0 ? 0500 : 0400) == 0,
          "seal staged file");
  }
}

void remove_tree(int parent, const std::string &name) {
  struct stat status{};
  if (::fstatat(parent, name.c_str(), &status, AT_SYMLINK_NOFOLLOW) < 0) {
    if (errno == ENOENT)
      return;
    fail_errno("inspect removal target");
  }
  if (!S_ISDIR(status.st_mode)) {
    check(::unlinkat(parent, name.c_str(), 0) == 0, "remove file");
    return;
  }
  auto directory = open_directory_at(parent, name.c_str());
  check(::fchmod(directory.get(), 0700) == 0, "open immutable directory");
  for (const auto &child : entries(directory.get()))
    remove_tree(directory.get(), child);
  check(::unlinkat(parent, name.c_str(), AT_REMOVEDIR) == 0,
        "remove directory");
}

std::string revision_record(const discovery::VerifiedPlugin &plugin) {
  return "OMARCHY-REVISION-V1\nplugin=" + plugin.manifest.id +
         "\ntree=" + plugin.identity.tree_sha256 +
         "\nmanifest=" + plugin.identity.manifest_sha256 +
         "\nrequest=" + plugin.identity.request_sha256 + "\n";
}

std::vector<std::string> lines(std::string_view bytes) {
  std::vector<std::string> result;
  while (!bytes.empty()) {
    const auto separator = bytes.find('\n');
    if (separator == std::string_view::npos)
      throw Failure(ErrorCode::corrupt_revision, "record lacks final newline");
    result.emplace_back(bytes.substr(0, separator));
    bytes.remove_prefix(separator + 1);
  }
  return result;
}

PolicyBinding parse_binding(const std::vector<std::string> &record,
                            std::size_t offset, std::string_view prefix) {
  if (offset + 7 > record.size())
    throw Failure(ErrorCode::corrupt_revision,
                  "activation binding is truncated");
  const std::array<std::string_view, 7> keys = {
      "plugin=", "revision=", "manifest=",  "source_request=",
      "policy=", "grant=",    "generation="};
  std::array<std::string, 7> values;
  for (std::size_t index = 0; index < keys.size(); ++index) {
    const std::string expected = std::string(prefix) + std::string(keys[index]);
    if (!record[offset + index].starts_with(expected))
      throw Failure(ErrorCode::corrupt_revision,
                    "activation field order is invalid");
    values[index] = record[offset + index].substr(expected.size());
  }
  PolicyBinding binding{values[0], values[1], values[2], values[3],
                        values[4], values[5], 0};
  const auto conversion =
      std::from_chars(values[6].data(), values[6].data() + values[6].size(),
                      binding.generation);
  if (conversion.ec != std::errc{} ||
      conversion.ptr != values[6].data() + values[6].size())
    throw Failure(ErrorCode::corrupt_revision,
                  "activation generation is invalid");
  return binding;
}

std::string serialize_binding(std::string_view prefix,
                              const PolicyBinding &binding) {
  return std::string(prefix) + "plugin=" + binding.plugin_id + "\n" +
         std::string(prefix) + "revision=" + binding.revision_sha256 + "\n" +
         std::string(prefix) + "manifest=" + binding.manifest_sha256 + "\n" +
         std::string(prefix) +
         "source_request=" + binding.source_request_sha256 + "\n" +
         std::string(prefix) + "policy=" + binding.policy_sha256 + "\n" +
         std::string(prefix) + "grant=" + binding.grant_sha256 + "\n" +
         std::string(prefix) +
         "generation=" + std::to_string(binding.generation) + "\n";
}

void validate_binding_shape(const PolicyBinding &binding) {
  if (!valid_plugin_id(binding.plugin_id) ||
      !valid_digest(binding.revision_sha256) ||
      !valid_digest(binding.manifest_sha256) ||
      !valid_digest(binding.source_request_sha256) ||
      !valid_digest(binding.policy_sha256) ||
      !valid_digest(binding.grant_sha256) || binding.generation == 0)
    throw Failure(ErrorCode::invalid_argument, "activation binding is invalid");
}

std::string activation_record(const Activation &activation) {
  std::string result = "OMARCHY-ACTIVATION-V1\n";
  result += serialize_binding("active.", activation.active);
  result += std::string("rollback=") + (activation.rollback ? "1\n" : "0\n");
  if (activation.rollback)
    result += serialize_binding("rollback.", *activation.rollback);
  return result;
}

Activation parse_activation(std::string_view bytes) {
  const auto record = lines(bytes);
  if (record.size() != 9 && record.size() != 16)
    throw Failure(ErrorCode::corrupt_revision,
                  "activation field count is invalid");
  if (record[0] != "OMARCHY-ACTIVATION-V1")
    throw Failure(ErrorCode::corrupt_revision, "activation version is invalid");
  Activation result{parse_binding(record, 1, "active."), std::nullopt};
  if (record[8] == "rollback=1") {
    if (record.size() != 16)
      throw Failure(ErrorCode::corrupt_revision, "rollback binding is absent");
    result.rollback = parse_binding(record, 9, "rollback.");
  } else if (record[8] != "rollback=0" || record.size() != 9) {
    throw Failure(ErrorCode::corrupt_revision, "rollback marker is invalid");
  }
  validate_binding_shape(result.active);
  if (result.rollback)
    validate_binding_shape(*result.rollback);
  return result;
}

void verify_metadata(int metadata, const PolicyBinding &binding) {
  const std::string record =
      read_small_at(metadata, binding.revision_sha256.c_str(), 1024);
  const auto fields = lines(record);
  const std::vector<std::string> expected = {
      "OMARCHY-REVISION-V1", "plugin=" + binding.plugin_id,
      "tree=" + binding.revision_sha256, "manifest=" + binding.manifest_sha256,
      "request=" + binding.source_request_sha256};
  if (fields != expected)
    throw Failure(ErrorCode::binding_mismatch,
                  "activation does not exactly match staged identity");
}

void verify_revision(int revisions, const PolicyBinding &binding) {
  auto revision = open_directory_at(revisions, binding.revision_sha256.c_str());
  const std::string manifest_bytes =
      read_small_at(revision.get(), "manifest.json", 1024U * 1024U);
  const auto parsed = manifest::parse_manifest_v2(manifest_bytes);
  const auto identity =
      manifest::identify_tree(descriptor_path(revision.get()), parsed);
  if (parsed.id != binding.plugin_id ||
      identity.tree_sha256 != binding.revision_sha256 ||
      identity.manifest_sha256 != binding.manifest_sha256 ||
      identity.request_sha256 != binding.source_request_sha256)
    throw Failure(ErrorCode::corrupt_revision,
                  "stored revision no longer matches its binding");
}

Result capture(const auto &operation) {
  try {
    operation();
    return {};
  } catch (const Failure &failure) {
    return {failure.code, failure.what()};
  } catch (const std::exception &failure) {
    return {ErrorCode::corrupt_revision, failure.what()};
  }
}

} // namespace

RevisionStore::RevisionStore(std::filesystem::path root, Options options)
    : root_(std::move(root)), options_(options) {}

std::filesystem::path
RevisionStore::revision_path(std::string_view digest) const {
  return root_ / "revisions" / digest;
}

Result RevisionStore::recover() {
  return capture([&] {
    auto root = open_store(root_, true);
    auto revisions = open_directory_at(root.get(), "revisions");
    auto metadata = open_directory_at(root.get(), "metadata");
    auto state = open_directory_at(root.get(), "state");
    for (const auto &name : entries(revisions.get())) {
      if (name.starts_with(".stage-"))
        remove_tree(revisions.get(), name);
    }
    for (const auto &name : entries(state.get())) {
      if (name.starts_with(".activation-"))
        remove_tree(state.get(), name);
    }
    for (const auto &name : entries(metadata.get())) {
      if (name.starts_with(".revision-"))
        remove_tree(metadata.get(), name);
    }
    const std::string record =
        read_small_at(state.get(), "activation", 4096, true);
    if (!record.empty()) {
      const Activation activation = parse_activation(record);
      verify_metadata(metadata.get(), activation.active);
      verify_revision(revisions.get(), activation.active);
      if (activation.rollback) {
        verify_metadata(metadata.get(), *activation.rollback);
        verify_revision(revisions.get(), *activation.rollback);
      }
    }
    check(::fsync(revisions.get()) == 0, "sync recovered revisions");
    check(::fsync(state.get()) == 0, "sync recovered state");
  });
}

Result RevisionStore::stage(const discovery::VerifiedPlugin &plugin,
                            FaultPoint fault) {
  return capture([&] {
    if (!options_.schema_v2_enabled)
      throw Failure(ErrorCode::feature_disabled,
                    "schema v2 staging is disabled");
    if (!valid_plugin_id(plugin.manifest.id) ||
        !valid_digest(plugin.identity.tree_sha256) ||
        !valid_digest(plugin.identity.manifest_sha256) ||
        !valid_digest(plugin.identity.request_sha256))
      throw Failure(ErrorCode::invalid_argument,
                    "verified identity is invalid");

    auto root = open_store(root_, true);
    auto revisions = open_directory_at(root.get(), "revisions");
    auto metadata = open_directory_at(root.get(), "metadata");
    bool revision_exists = false;
    struct stat existing{};
    if (::fstatat(revisions.get(), plugin.identity.tree_sha256.c_str(),
                  &existing, AT_SYMLINK_NOFOLLOW) == 0) {
      if (!S_ISDIR(existing.st_mode))
        throw Failure(ErrorCode::corrupt_revision,
                      "revision target is not a directory");
      auto existing_revision = open_directory_at(
          revisions.get(), plugin.identity.tree_sha256.c_str());
      const auto reparsed = manifest::parse_manifest_v2(read_small_at(
          existing_revision.get(), "manifest.json", 1024U * 1024U));
      if (reparsed != plugin.manifest ||
          manifest::identify_tree(descriptor_path(existing_revision.get()),
                                  reparsed) != plugin.identity)
        throw Failure(ErrorCode::corrupt_revision,
                      "existing revision identity is corrupt");
      revision_exists = true;
    } else if (errno != ENOENT) {
      fail_errno("inspect revision target");
    }

    if (!revision_exists) {
      const std::string temporary = ".stage-" + std::to_string(::getpid()) +
                                    "-" +
                                    plugin.identity.tree_sha256.substr(0, 16);
      if (::mkdirat(revisions.get(), temporary.c_str(), 0700) < 0)
        fail_errno("create staging tree");
      try {
        auto destination =
            open_directory_at(revisions.get(), temporary.c_str());
        const int source_raw =
            ::open(plugin.root.c_str(),
                   O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
        if (source_raw < 0)
          fail_errno("open plugin source");
        Fd source(source_raw);
        CopyBudget budget;
        copy_tree(source.get(), destination.get(), options_, budget);
        check(::fsync(destination.get()) == 0, "sync staging root");
        if (fault == FaultPoint::stage_after_copy)
          throw Failure(ErrorCode::injected_failure,
                        "injected after tree copy");

        const std::string manifest_bytes =
            read_small_at(destination.get(), "manifest.json", 1024U * 1024U);
        const auto staged_manifest =
            manifest::parse_manifest_v2(manifest_bytes);
        const auto staged_identity = manifest::identify_tree(
            descriptor_path(destination.get()), staged_manifest);
        if (staged_manifest != plugin.manifest ||
            staged_identity != plugin.identity)
          throw Failure(ErrorCode::source_changed,
                        "staged identity differs from discovery");
        if (fault == FaultPoint::stage_after_verify)
          throw Failure(ErrorCode::injected_failure,
                        "injected after staging verification");
        check(::fchmod(destination.get(), 0500) == 0, "seal staging root");
        check(::renameat(revisions.get(), temporary.c_str(), revisions.get(),
                         plugin.identity.tree_sha256.c_str()) == 0,
              "publish revision");
        check(::fsync(revisions.get()) == 0, "sync revision publication");
      } catch (...) {
        remove_tree(revisions.get(), temporary);
        throw;
      }
    }

    const std::string expected_record = revision_record(plugin);
    const std::string existing_record = read_small_at(
        metadata.get(), plugin.identity.tree_sha256.c_str(), 1024, true);
    if (!existing_record.empty() && existing_record != expected_record)
      throw Failure(ErrorCode::corrupt_revision,
                    "existing revision metadata is inconsistent");
    if (!existing_record.empty())
      return;
    const std::string metadata_temporary =
        ".revision-" + std::to_string(::getpid());
    atomic_record(metadata.get(), metadata_temporary.c_str(),
                  plugin.identity.tree_sha256.c_str(), expected_record,
                  FaultPoint::none, FaultPoint::none, FaultPoint::none,
                  FaultPoint::none);
  });
}

std::optional<Activation> RevisionStore::current(Result *status) const {
  std::optional<Activation> result;
  const Result captured = capture([&] {
    auto root = open_store(root_, false);
    auto state = open_directory_at(root.get(), "state");
    const std::string bytes =
        read_small_at(state.get(), "activation", 4096, true);
    if (!bytes.empty())
      result = parse_activation(bytes);
  });
  if (status != nullptr)
    *status = captured;
  if (!captured.ok())
    return std::nullopt;
  return result;
}

Result RevisionStore::activate(const PolicyBinding &binding, FaultPoint fault) {
  return capture([&] {
    if (!options_.schema_v2_enabled)
      throw Failure(ErrorCode::feature_disabled,
                    "schema v2 activation is disabled");
    validate_binding_shape(binding);
    auto root = open_store(root_, false);
    auto revisions = open_directory_at(root.get(), "revisions");
    auto metadata = open_directory_at(root.get(), "metadata");
    auto state = open_directory_at(root.get(), "state");
    verify_metadata(metadata.get(), binding);
    verify_revision(revisions.get(), binding);
    const std::string existing =
        read_small_at(state.get(), "activation", 4096, true);
    Activation next{binding, std::nullopt};
    if (!existing.empty()) {
      const Activation old = parse_activation(existing);
      if (binding.generation <= old.active.generation)
        throw Failure(ErrorCode::binding_mismatch,
                      "activation generation must increase monotonically");
      next.rollback = old.active;
    }
    const std::string temporary = ".activation-" + std::to_string(::getpid());
    atomic_record(state.get(), temporary.c_str(), "activation",
                  activation_record(next), fault,
                  FaultPoint::activate_after_write,
                  FaultPoint::activate_after_file_sync,
                  FaultPoint::activate_after_rename);
  });
}

Result RevisionStore::rebind_active(const PolicyBinding &binding,
                                    FaultPoint fault) {
  return capture([&] {
    if (!options_.schema_v2_enabled)
      throw Failure(ErrorCode::feature_disabled,
                    "schema v2 activation is disabled");
    validate_binding_shape(binding);
    auto root = open_store(root_, false);
    auto revisions = open_directory_at(root.get(), "revisions");
    auto metadata = open_directory_at(root.get(), "metadata");
    auto state = open_directory_at(root.get(), "state");
    const std::string existing =
        read_small_at(state.get(), "activation", 4096, true);
    if (existing.empty())
      throw Failure(ErrorCode::binding_mismatch,
                    "cannot rebind without an active revision");
    const Activation old = parse_activation(existing);
    const bool exact_revision =
        binding.plugin_id == old.active.plugin_id &&
        binding.revision_sha256 == old.active.revision_sha256 &&
        binding.manifest_sha256 == old.active.manifest_sha256 &&
        binding.source_request_sha256 == old.active.source_request_sha256 &&
        binding.policy_sha256 == old.active.policy_sha256 &&
        binding.generation == old.active.generation;
    if (!exact_revision)
      throw Failure(ErrorCode::binding_mismatch,
                    "active rebind may change only the grant fingerprint");
    verify_metadata(metadata.get(), binding);
    verify_revision(revisions.get(), binding);
    const Activation next{binding, old.rollback};
    const std::string temporary = ".activation-" + std::to_string(::getpid());
    atomic_record(state.get(), temporary.c_str(), "activation",
                  activation_record(next), fault,
                  FaultPoint::activate_after_write,
                  FaultPoint::activate_after_file_sync,
                  FaultPoint::activate_after_rename);
  });
}

Result RevisionStore::rollback(FaultPoint fault) {
  return capture([&] {
    if (!options_.schema_v2_enabled)
      throw Failure(ErrorCode::feature_disabled,
                    "schema v2 rollback is disabled");
    auto root = open_store(root_, false);
    auto revisions = open_directory_at(root.get(), "revisions");
    auto metadata = open_directory_at(root.get(), "metadata");
    auto state = open_directory_at(root.get(), "state");
    const std::string existing =
        read_small_at(state.get(), "activation", 4096, true);
    if (existing.empty())
      throw Failure(ErrorCode::no_rollback, "no activation exists");
    const Activation old = parse_activation(existing);
    if (!old.rollback)
      throw Failure(ErrorCode::no_rollback, "no rollback target exists");
    verify_metadata(metadata.get(), *old.rollback);
    verify_revision(revisions.get(), *old.rollback);
    if (old.active.generation == std::numeric_limits<std::uint64_t>::max())
      throw Failure(ErrorCode::binding_mismatch,
                    "activation generation cannot advance");
    PolicyBinding target_binding = *old.rollback;
    target_binding.generation = old.active.generation + 1;
    const Activation next{target_binding, old.active};
    const std::string temporary = ".activation-" + std::to_string(::getpid());
    atomic_record(state.get(), temporary.c_str(), "activation",
                  activation_record(next), fault,
                  FaultPoint::activate_after_write,
                  FaultPoint::activate_after_file_sync,
                  FaultPoint::activate_after_rename);
  });
}

Result RevisionStore::prune(std::size_t maximum_revisions) {
  return capture([&] {
    if (maximum_revisions == 0)
      throw Failure(ErrorCode::invalid_argument,
                    "retention bound must be nonzero");
    auto root = open_store(root_, false);
    auto revisions = open_directory_at(root.get(), "revisions");
    auto metadata = open_directory_at(root.get(), "metadata");
    auto state = open_directory_at(root.get(), "state");
    std::vector<std::string> digests;
    for (const auto &name : entries(revisions.get())) {
      if (valid_digest(name))
        digests.push_back(name);
    }
    const std::string record =
        read_small_at(state.get(), "activation", 4096, true);
    std::vector<std::string> protected_digests;
    if (!record.empty()) {
      const Activation activation = parse_activation(record);
      protected_digests.push_back(activation.active.revision_sha256);
      if (activation.rollback)
        protected_digests.push_back(activation.rollback->revision_sha256);
    }
    if (protected_digests.size() > maximum_revisions)
      throw Failure(ErrorCode::retention_blocked,
                    "active and rollback revisions exceed retention bound");
    std::sort(digests.begin(), digests.end());
    std::size_t remaining = digests.size();
    for (const auto &digest : digests) {
      if (remaining <= maximum_revisions)
        break;
      if (std::find(protected_digests.begin(), protected_digests.end(),
                    digest) != protected_digests.end())
        continue;
      remove_tree(revisions.get(), digest);
      if (::unlinkat(metadata.get(), digest.c_str(), 0) < 0 && errno != ENOENT)
        fail_errno("remove revision metadata");
      --remaining;
    }
    remaining = 0;
    for (const auto &name : entries(revisions.get()))
      remaining += valid_digest(name) ? 1U : 0U;
    if (remaining > maximum_revisions)
      throw Failure(ErrorCode::retention_blocked,
                    "retention cannot remove protected revisions");
    check(::fsync(revisions.get()) == 0, "sync revision retention");
    check(::fsync(metadata.get()) == 0, "sync metadata retention");
  });
}

} // namespace omarchy::plugins::store
