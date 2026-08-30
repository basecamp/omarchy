#include "activation_snapshot.hpp"

#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

#include <array>
#include <filesystem>
#include <functional>
#include <iostream>
#include <stdexcept>
#include <string>
#include <utility>

namespace host = omarchy::plugin_runtime::host_session;
namespace manifest = omarchy::plugins::manifest;
namespace permissions = omarchy::plugins::permissions;
namespace policy = omarchy::plugin_runtime::policy;

namespace {

constexpr std::string_view kPlugin = "org.example.secure";
const std::string kRevision(64, 'a');
const std::string kRequest(64, 'b');

void require(bool condition, std::string_view message) {
  if (!condition)
    throw std::runtime_error(std::string(message));
}

class TemporaryTree {
public:
  TemporaryTree() {
    std::string pattern = "/tmp/omarchy-activation-test.XXXXXX";
    char *created = ::mkdtemp(pattern.data());
    if (created == nullptr)
      throw std::runtime_error("mkdtemp failed");
    root_ = created;
    activation_ = root_ / "activation";
    revisions_ = root_ / "revisions";
    state_ = root_ / "state";
    authority_ = root_ / "authority";
    std::filesystem::create_directory(activation_);
    std::filesystem::create_directory(revisions_);
    std::filesystem::create_directory(state_);
    std::filesystem::create_directory(authority_);
    std::filesystem::create_directory(revisions_ / "active");
    std::filesystem::create_directory(state_ / "plugin-state");
    require(::chmod((state_ / "plugin-state").c_str(), 0700) == 0,
            "state permissions failed");
    write(revisions_ / "active" / "identity",
          std::string(kPlugin) + "\n" + kRevision + "\n");
    write(activation_ / "current", record());
  }

  ~TemporaryTree() { std::filesystem::remove_all(root_); }
  TemporaryTree(const TemporaryTree &) = delete;
  TemporaryTree &operator=(const TemporaryTree &) = delete;

  [[nodiscard]] static std::string
  record(std::string_view revision = "active",
         std::string_view state = "plugin-state") {
    return "format=omarchy-plugin-activation-v2\nplugin=" +
           std::string(kPlugin) +
           "\nrevision-directory=" + std::string(revision) +
           "\nrevision-sha256=" + kRevision +
           "\nstate-directory=" + std::string(state) + "\n";
  }

  static void write(const std::filesystem::path &path, std::string_view bytes) {
    const int fd =
        ::open(path.c_str(), O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0600);
    if (fd < 0)
      throw std::runtime_error("open for write failed");
    std::size_t offset = 0;
    while (offset != bytes.size()) {
      const ssize_t count =
          ::write(fd, bytes.data() + offset, bytes.size() - offset);
      if (count <= 0) {
        ::close(fd);
        throw std::runtime_error("write failed");
      }
      offset += static_cast<std::size_t>(count);
    }
    ::close(fd);
  }

  [[nodiscard]] int open_directory(const std::filesystem::path &path) const {
    const int fd = ::open(path.c_str(), O_RDONLY | O_DIRECTORY | O_CLOEXEC);
    if (fd < 0)
      throw std::runtime_error("directory open failed");
    return fd;
  }

  [[nodiscard]] const std::filesystem::path &activation() const {
    return activation_;
  }
  [[nodiscard]] const std::filesystem::path &revisions() const {
    return revisions_;
  }
  [[nodiscard]] const std::filesystem::path &state() const { return state_; }
  [[nodiscard]] const std::filesystem::path &authority() const {
    return authority_;
  }

private:
  std::filesystem::path root_;
  std::filesystem::path activation_;
  std::filesystem::path revisions_;
  std::filesystem::path state_;
  std::filesystem::path authority_;
};

std::string read_relative(int directory_fd, std::string_view name) {
  const std::string owned(name);
  const int fd =
      ::openat(directory_fd, owned.c_str(), O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
  if (fd < 0)
    return {};
  std::string result;
  char bytes[256];
  for (;;) {
    const ssize_t count = ::read(fd, bytes, sizeof(bytes));
    if (count <= 0)
      break;
    result.append(bytes, static_cast<std::size_t>(count));
  }
  ::close(fd);
  return result;
}

class DescriptorVerifier final : public host::RevisionVerifier {
public:
  std::function<void()> before_read;
  mutable int calls = 0;

  std::optional<host::VerifiedRevision>
  verify_open_revision(int revision_directory_fd) const override {
    ++calls;
    if (before_read)
      before_read();
    const std::string identity =
        read_relative(revision_directory_fd, "identity");
    const auto split = identity.find('\n');
    const auto end = identity.find('\n', split + 1);
    if (split == std::string::npos || end == std::string::npos ||
        end + 1 != identity.size())
      return std::nullopt;
    manifest::ManifestV2 verified_manifest;
    verified_manifest.id = identity.substr(0, split);
    return host::VerifiedRevision{
        .manifest = std::move(verified_manifest),
        .tree_sha256 = identity.substr(split + 1, end - split - 1),
        .request_sha256 = kRequest};
  }
};

policy::GrantSnapshot grants(std::uint64_t generation = 7) {
  policy::GrantSnapshot result;
  result.binding = {
      .plugin = permissions::PluginId(kPlugin),
      .revision = permissions::Digest(kRevision),
      .policy_fingerprint = permissions::Digest(
          permissions::policy_request_fingerprint(result.requests)),
      .generation = generation};
  result.source_request_fingerprint = permissions::Digest(kRequest);
  return result;
}

class Authority final : public host::GrantAuthority {
public:
  policy::GrantSnapshot snapshot = grants();
  std::function<void()> before_return;
  mutable int calls = 0;

  std::optional<policy::GrantSnapshot>
  resolve(std::string_view plugin_id,
          std::string_view revision_sha256) const override {
    ++calls;
    if (before_return)
      before_return();
    if (plugin_id != kPlugin || revision_sha256 != kRevision)
      return std::nullopt;
    return snapshot;
  }
};

struct OpenRoots {
  int activation = -1;
  int revisions = -1;
  int state = -1;
  int authority = -1;

  explicit OpenRoots(const TemporaryTree &tree)
      : activation(tree.open_directory(tree.activation())),
        revisions(tree.open_directory(tree.revisions())),
        state(tree.open_directory(tree.state())),
        authority(tree.open_directory(tree.authority())) {}
  ~OpenRoots() {
    if (activation >= 0)
      ::close(activation);
    if (revisions >= 0)
      ::close(revisions);
    if (state >= 0)
      ::close(state);
    if (authority >= 0)
      ::close(authority);
  }
};

host::FilesystemIdentity identity(int descriptor) {
  struct stat metadata {};
  require(::fstat(descriptor, &metadata) == 0, "identity fstat failed");
  return {.device = static_cast<std::uint64_t>(metadata.st_dev),
          .inode = static_cast<std::uint64_t>(metadata.st_ino)};
}

host::ActivationResult load(const TemporaryTree &tree,
                            DescriptorVerifier &verifier,
                            Authority &authority,
                            std::optional<host::FilesystemIdentity>
                                authority_root = std::nullopt,
                            std::string expected_state = "plugin-state") {
  OpenRoots roots(tree);
  host::ActivationSource source(roots.activation, roots.revisions, roots.state,
                                verifier, authority,
                                authority_root.value_or(identity(roots.authority)),
                                std::move(expected_state), ::getuid());
  // ActivationSource owns duplicates rather than borrowing caller descriptors.
  ::close(std::exchange(roots.activation, -1));
  ::close(std::exchange(roots.revisions, -1));
  ::close(std::exchange(roots.state, -1));
  return source.load("current");
}

void happy_path_and_revocation() {
  TemporaryTree tree;
  DescriptorVerifier verifier;
  Authority authority;
  auto result = load(tree, verifier, authority);
  require(result.snapshot.has_value() &&
              result.error == host::ActivationError::none,
          "valid activation failed");
  require(verifier.calls == 1 && authority.calls == 1,
          "activation authority was consulted more than once");
  require(result.snapshot->manifest.id == kPlugin,
          "activation discarded its descriptor-verified manifest");
  auto binding = result.snapshot->grants.binding;
  require(binding.generation == 7,
          "activation record rather than durable authority selected generation");
  require(result.snapshot->live->current(binding),
          "fresh generation is not live");
  auto stale = binding;
  ++stale.generation;
  require(!result.snapshot->live->current(stale), "stale generation is live");
  result.snapshot->live->revoke();
  require(result.snapshot->live->generation() == 0 &&
              !result.snapshot->live->current(binding),
          "revoked generation remained usable");
  require(::fcntl(result.snapshot->activation_record.get(), F_GETFD) >= 0 &&
              ::fcntl(result.snapshot->revision_directory.get(), F_GETFD) >=
                  0 &&
              ::fcntl(result.snapshot->state_directory.get(), F_GETFD) >= 0,
          "activation did not retain its authority descriptors");
  require((::fcntl(result.snapshot->activation_record.get(), F_GETFD) &
           FD_CLOEXEC) != 0 &&
              (::fcntl(result.snapshot->revision_directory.get(), F_GETFD) &
               FD_CLOEXEC) != 0 &&
              (::fcntl(result.snapshot->state_directory.get(), F_GETFD) &
               FD_CLOEXEC) != 0,
          "authority descriptors can leak across exec");
}

void path_swaps_do_not_retarget_descriptors() {
  TemporaryTree tree;
  std::filesystem::create_directory(tree.revisions() / "replacement");
  TemporaryTree::write(tree.revisions() / "replacement" / "identity",
                       "org.attacker\n" + std::string(64, 'f') + "\n");
  std::filesystem::create_directory(tree.state() / "replacement");
  TemporaryTree::write(tree.state() / "plugin-state" / "marker", "original");
  TemporaryTree::write(tree.state() / "replacement" / "marker", "replacement");

  DescriptorVerifier verifier;
  verifier.before_read = [&] {
    std::filesystem::rename(tree.revisions() / "active",
                            tree.revisions() / "original-moved");
    std::filesystem::rename(tree.revisions() / "replacement",
                            tree.revisions() / "active");
  };
  Authority authority;
  authority.before_return = [&] {
    std::filesystem::rename(tree.state() / "plugin-state",
                            tree.state() / "original-moved");
    std::filesystem::rename(tree.state() / "replacement",
                            tree.state() / "plugin-state");
  };
  auto result = load(tree, verifier, authority);
  require(result.snapshot.has_value(),
          "path replacement retargeted revision fd");
  require(
      read_relative(result.snapshot->revision_directory.get(), "identity") ==
          std::string(kPlugin) + "\n" + kRevision + "\n",
      "snapshot revision descriptor followed replacement path");
  require(read_relative(result.snapshot->state_directory.get(), "marker") ==
              "original",
          "snapshot state descriptor followed replacement path");

  const struct stat before = [&] {
    struct stat value{};
    require(::fstat(result.snapshot->activation_record.get(), &value) == 0,
            "record fstat failed");
    return value;
  }();
  std::filesystem::rename(tree.activation() / "current",
                          tree.activation() / "original-record");
  TemporaryTree::write(tree.activation() / "current", TemporaryTree::record());
  struct stat after{};
  require(::fstat(result.snapshot->activation_record.get(), &after) == 0 &&
              before.st_dev == after.st_dev && before.st_ino == after.st_ino,
          "snapshot record descriptor followed replacement path");
}

void symlinks_and_aliases_are_rejected() {
  {
    TemporaryTree tree;
    std::filesystem::rename(tree.activation() / "current",
                            tree.activation() / "real");
    std::filesystem::create_symlink("real", tree.activation() / "current");
    DescriptorVerifier verifier;
    Authority authority;
    require(load(tree, verifier, authority).error ==
                host::ActivationError::record_unavailable,
            "activation-record symlink was followed");
  }
  {
    TemporaryTree tree;
    std::filesystem::rename(tree.revisions() / "active",
                            tree.revisions() / "real");
    std::filesystem::create_directory_symlink("real",
                                              tree.revisions() / "active");
    DescriptorVerifier verifier;
    Authority authority;
    require(load(tree, verifier, authority).error ==
                host::ActivationError::revision_unavailable,
            "revision symlink was followed");
  }
  {
    TemporaryTree tree;
    std::filesystem::rename(tree.state() / "plugin-state",
                            tree.state() / "real");
    std::filesystem::create_directory_symlink("real",
                                              tree.state() / "plugin-state");
    DescriptorVerifier verifier;
    Authority authority;
    require(load(tree, verifier, authority).error ==
                host::ActivationError::state_unavailable,
            "state symlink was followed");
  }
  {
    TemporaryTree tree;
    OpenRoots roots(tree);
    DescriptorVerifier verifier;
    Authority authority;
    host::ActivationSource source(roots.activation, roots.revisions,
                                  roots.revisions, verifier, authority,
                                  identity(roots.authority), "plugin-state",
                                  ::getuid());
    require(source.load("current").error == host::ActivationError::root_alias,
            "aliased revision/state roots were accepted");
  }
}

void grant_authority_aliases_are_rejected() {
  {
    TemporaryTree tree;
    OpenRoots roots(tree);
    DescriptorVerifier verifier;
    Authority authority;
    require(load(tree, verifier, authority, identity(roots.activation)).error ==
                host::ActivationError::root_alias,
            "grant authority aliased activation root");
    require(load(tree, verifier, authority, identity(roots.revisions)).error ==
                host::ActivationError::root_alias,
            "grant authority aliased revision root");
    require(load(tree, verifier, authority, identity(roots.state)).error ==
                host::ActivationError::root_alias,
            "grant authority aliased state root");
  }
  {
    TemporaryTree tree;
    const int selected = tree.open_directory(tree.revisions() / "active");
    DescriptorVerifier verifier;
    Authority authority;
    const auto result = load(tree, verifier, authority, identity(selected));
    ::close(selected);
    require(result.error == host::ActivationError::revision_state_alias,
            "grant authority aliased selected revision");
  }
  {
    TemporaryTree tree;
    const int selected = tree.open_directory(tree.state() / "plugin-state");
    DescriptorVerifier verifier;
    Authority authority;
    const auto result = load(tree, verifier, authority, identity(selected));
    ::close(selected);
    require(result.error == host::ActivationError::revision_state_alias,
            "grant authority aliased selected state");
  }
}

void every_authority_inode_must_be_distinct() {
  std::array<host::FilesystemIdentity, 5> identities{};
  for (std::size_t index = 0; index < identities.size(); ++index) {
    identities[index] = {.device = 1, .inode = index + 1};
  }
  require(host::distinct_authority_objects(identities),
          "distinct authority objects were rejected");
  for (std::size_t left = 0; left < identities.size(); ++left) {
    for (std::size_t right = left + 1; right < identities.size(); ++right) {
      const auto original = identities[right];
      identities[right] = identities[left];
      require(!host::distinct_authority_objects(identities),
              "cross-set authority alias was accepted");
      identities[right] = original;
    }
  }
}

void identity_policy_and_mode_mismatches_are_rejected() {
  {
    TemporaryTree tree;
    TemporaryTree::write(
        tree.activation() / "current",
        "format=omarchy-plugin-activation-v1\nplugin=" + std::string(kPlugin) +
            "\nrevision-directory=active\nrevision-sha256=" + kRevision +
            "\nstate-directory=plugin-state\ngeneration=7\n");
    DescriptorVerifier verifier;
    Authority authority;
    require(load(tree, verifier, authority).error ==
                host::ActivationError::record_invalid &&
                verifier.calls == 0 && authority.calls == 0,
            "legacy generation-bearing activation record was accepted");
  }
  {
    TemporaryTree tree;
    std::filesystem::create_directory(tree.state() / "other-state");
    require(::chmod((tree.state() / "other-state").c_str(), 0700) == 0,
            "alternate state permissions failed");
    TemporaryTree::write(tree.activation() / "current",
                         TemporaryTree::record("active", "other-state"));
    DescriptorVerifier verifier;
    Authority authority;
    require(load(tree, verifier, authority).error ==
                host::ActivationError::record_invalid &&
                verifier.calls == 0 && authority.calls == 0,
            "activation record selected an unexpected state component");
    DescriptorVerifier expected_verifier;
    Authority expected_authority;
    require(load(tree, expected_verifier, expected_authority, std::nullopt,
                 "other-state")
                .snapshot.has_value(),
            "activation rejected its explicitly bound state component");
  }
  {
    TemporaryTree tree;
    TemporaryTree::write(tree.revisions() / "active" / "identity",
                         "org.wrong\n" + kRevision + "\n");
    DescriptorVerifier verifier;
    Authority authority;
    require(load(tree, verifier, authority).error ==
                host::ActivationError::revision_unverified,
            "mismatched verified plugin identity was accepted");
  }
  {
    TemporaryTree tree;
    DescriptorVerifier verifier;
    Authority authority;
    authority.snapshot.binding.policy_fingerprint =
        permissions::Digest(std::string(64, 'f'));
    require(load(tree, verifier, authority).error ==
                host::ActivationError::grant_mismatch,
            "authority policy fingerprint was not recomputed");
  }
  {
    TemporaryTree tree;
    DescriptorVerifier verifier;
    Authority authority;
    authority.snapshot.source_request_fingerprint =
        permissions::Digest(std::string(64, 'c'));
    require(load(tree, verifier, authority).error ==
                host::ActivationError::grant_mismatch,
            "grant requests were not bound to the verified manifest");
  }
  {
    TemporaryTree tree;
    DescriptorVerifier verifier;
    Authority authority;
    authority.snapshot.binding.generation = 8;
    const auto result = load(tree, verifier, authority);
    require(result.snapshot && result.snapshot->grants.binding.generation == 8,
            "durable authority did not supply the active generation");
  }
  {
    TemporaryTree tree;
    ::chmod((tree.activation() / "current").c_str(), 0660);
    DescriptorVerifier verifier;
    Authority authority;
    require(load(tree, verifier, authority).error ==
                host::ActivationError::record_untrusted,
            "group-writable authority record was accepted");
  }
  {
    TemporaryTree tree;
    ::chmod(tree.state().c_str(), 0770);
    DescriptorVerifier verifier;
    Authority authority;
    require(load(tree, verifier, authority).error ==
                host::ActivationError::root_untrusted,
            "group-writable state root was accepted");
  }
  for (const mode_t mode : {mode_t{0755}, mode_t{0750}, mode_t{04700},
                            mode_t{02700}, mode_t{01700}}) {
    TemporaryTree tree;
    require(::chmod((tree.state() / "plugin-state").c_str(), mode) == 0,
            "selected state mode mutation failed");
    DescriptorVerifier verifier;
    Authority authority;
    require(load(tree, verifier, authority).error ==
                host::ActivationError::state_unavailable,
            "selected state with non-0700 mode was accepted");
  }
  {
    TemporaryTree tree;
    struct stat metadata {};
    require(::stat((tree.state() / "plugin-state").c_str(), &metadata) == 0 &&
                metadata.st_uid == ::getuid() &&
                (metadata.st_mode & 0777) == 0700,
            "valid selected state does not have the exact trusted uid/mode");
    DescriptorVerifier verifier;
    Authority authority;
    require(load(tree, verifier, authority).snapshot.has_value(),
            "exact trusted uid and 0700 selected state were rejected");
  }
}

} // namespace

int main() {
  try {
    happy_path_and_revocation();
    path_swaps_do_not_retarget_descriptors();
    symlinks_and_aliases_are_rejected();
    grant_authority_aliases_are_rejected();
    every_authority_inode_must_be_distinct();
    identity_policy_and_mode_mismatches_are_rejected();
    std::cout << "activation snapshot tests passed\n";
    return 0;
  } catch (const std::exception &error) {
    std::cerr << "activation snapshot test failed: " << error.what() << '\n';
    return 1;
  }
}
