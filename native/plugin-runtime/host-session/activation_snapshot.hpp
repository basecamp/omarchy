#pragma once

#include "grant_snapshot.hpp"
#include "manifest_contract.hpp"

#include <atomic>
#include <cstdint>
#include <memory>
#include <optional>
#include <span>
#include <string>
#include <string_view>

namespace omarchy::plugin_runtime::host_session {

namespace permissions = omarchy::plugins::permissions;
namespace policy = omarchy::plugin_runtime::policy;

// A descriptor is the lifetime of an activated filesystem object.  Activation
// never converts it back to a pathname: the verifier, sandbox launcher and
// state broker must use descriptor-relative operations on these exact objects.
class OwnedDescriptor {
public:
  OwnedDescriptor() = default;
  explicit OwnedDescriptor(int descriptor) noexcept : descriptor_(descriptor) {}
  ~OwnedDescriptor();
  OwnedDescriptor(OwnedDescriptor &&other) noexcept;
  OwnedDescriptor &operator=(OwnedDescriptor &&other) noexcept;
  OwnedDescriptor(const OwnedDescriptor &) = delete;
  OwnedDescriptor &operator=(const OwnedDescriptor &) = delete;

  [[nodiscard]] int get() const noexcept { return descriptor_; }
  [[nodiscard]] int release() noexcept;
  [[nodiscard]] explicit operator bool() const noexcept {
    return descriptor_ >= 0;
  }

private:
  int descriptor_ = -1;
};

struct ActivationRecord {
  std::string plugin_id;
  std::string revision_directory;
  std::string revision_sha256;
  std::string state_directory;
  std::uint64_t generation = 0;
};

struct VerifiedRevision {
  plugins::manifest::ManifestV2 manifest;
  std::string tree_sha256;
  std::string request_sha256;
};

struct FilesystemIdentity {
  std::uint64_t device = 0;
  std::uint64_t inode = 0;

  bool operator==(const FilesystemIdentity &) const = default;
};

// Every authority root and selected plugin directory must name a distinct
// filesystem object. This prevents writable state from aliasing trusted roots.
[[nodiscard]] bool distinct_authority_objects(
    std::span<const FilesystemIdentity> identities) noexcept;

// Discovery currently verifies by path. Activation instead hands this seam the
// exact already-open revision directory. Implementations must derive both
// returned values using descriptor-relative reads and must not reopen a path.
class RevisionVerifier {
public:
  virtual ~RevisionVerifier() = default;
  [[nodiscard]] virtual std::optional<VerifiedRevision>
  verify_open_revision(int revision_directory_fd) const = 0;
};

// The activation record never supplies grants or their fingerprint. The trusted
// authority resolves the persisted decision for the verified identity instead.
class GrantAuthority {
public:
  virtual ~GrantAuthority() = default;
  [[nodiscard]] virtual std::optional<policy::GrantSnapshot>
  resolve(std::string_view plugin_id, std::string_view revision_sha256,
          std::uint64_t generation) const = 0;
};

class LiveGenerationState {
public:
  explicit LiveGenerationState(permissions::ActivationBinding binding);

  [[nodiscard]] bool
  current(const permissions::ActivationBinding &binding) const noexcept;
  [[nodiscard]] std::uint64_t generation() const noexcept;
  void revoke() noexcept;

private:
  permissions::PluginId plugin_;
  permissions::Digest revision_;
  permissions::Digest policy_fingerprint_;
  std::atomic<std::uint64_t> generation_;
};

struct ActivationSnapshot {
  ActivationRecord record;
  plugins::manifest::ManifestV2 manifest;
  policy::GrantSnapshot grants;
  // Keep the trusted record and both selected directories pinned for the full
  // activation. A rename or path replacement cannot retarget a live session.
  OwnedDescriptor activation_record;
  OwnedDescriptor revision_directory;
  OwnedDescriptor state_directory;
  std::shared_ptr<LiveGenerationState> live;
};

enum class ActivationError {
  none,
  invalid_name,
  record_unavailable,
  record_untrusted,
  record_invalid,
  root_unavailable,
  root_untrusted,
  root_alias,
  revision_unavailable,
  state_unavailable,
  revision_state_alias,
  revision_unverified,
  grant_unavailable,
  grant_mismatch,
};

struct ActivationResult {
  std::optional<ActivationSnapshot> snapshot;
  ActivationError error = ActivationError::none;
};

class ActivationSource {
public:
  ActivationSource(int activation_root_fd, int revision_root_fd,
                   int state_root_fd, const RevisionVerifier &revision_verifier,
                   const GrantAuthority &grant_authority,
                   FilesystemIdentity grant_authority_root,
                   std::string expected_state_directory,
                   std::uint32_t trusted_uid);

  [[nodiscard]] ActivationResult load(std::string_view record_name) const;

private:
  OwnedDescriptor activation_root_;
  OwnedDescriptor revision_root_;
  OwnedDescriptor state_root_;
  const RevisionVerifier &revision_verifier_;
  const GrantAuthority &grant_authority_;
  FilesystemIdentity grant_authority_root_;
  std::string expected_state_directory_;
  std::uint32_t trusted_uid_;
};

} // namespace omarchy::plugin_runtime::host_session
