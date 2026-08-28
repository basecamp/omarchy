#pragma once

#include "discovery.hpp"

#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <optional>
#include <string>

namespace omarchy::plugins::store {

enum class ErrorCode {
  ok,
  feature_disabled,
  unsafe_legacy_schema,
  invalid_argument,
  unsafe_store,
  source_changed,
  unsupported_entry,
  limit_exceeded,
  corrupt_revision,
  binding_mismatch,
  no_rollback,
  retention_blocked,
  injected_failure,
  io_error,
};

struct Result {
  ErrorCode code = ErrorCode::ok;
  std::string detail;

  [[nodiscard]] bool ok() const { return code == ErrorCode::ok; }
};

struct PolicyBinding {
  std::string plugin_id;
  std::string revision_sha256;
  std::string manifest_sha256;
  std::string source_request_sha256;
  std::string policy_sha256;
  std::string grant_sha256;
  std::uint64_t generation = 0;

  bool operator==(const PolicyBinding &) const = default;
};

struct Activation {
  PolicyBinding active;
  std::optional<PolicyBinding> rollback;

  bool operator==(const Activation &) const = default;
};

enum class FaultPoint {
  none,
  stage_after_copy,
  stage_after_verify,
  activate_after_write,
  activate_after_file_sync,
  activate_after_rename,
};

struct Options {
  bool schema_v2_enabled = false;
  std::size_t maximum_files = 4096;
  std::uint64_t maximum_bytes = 64U * 1024U * 1024U;
  std::size_t maximum_directories = 4096;
  std::size_t maximum_depth = 64;
};

class RevisionStore {
public:
  RevisionStore(std::filesystem::path root, Options options);

  [[nodiscard]] Result recover();
  [[nodiscard]] Result stage(const discovery::VerifiedPlugin &plugin,
                             FaultPoint fault = FaultPoint::none);
  [[nodiscard]] Result activate(const PolicyBinding &binding,
                                FaultPoint fault = FaultPoint::none);
  [[nodiscard]] Result rollback(FaultPoint fault = FaultPoint::none);
  [[nodiscard]] Result prune(std::size_t maximum_revisions);
  [[nodiscard]] std::optional<Activation>
  current(Result *status = nullptr) const;

  [[nodiscard]] std::filesystem::path
  revision_path(std::string_view digest) const;

private:
  std::filesystem::path root_;
  Options options_;
};

} // namespace omarchy::plugins::store
