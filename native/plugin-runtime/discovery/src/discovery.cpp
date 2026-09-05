#include "discovery.hpp"

#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

#include <dirent.h>

#include <algorithm>
#include <array>
#include <cerrno>
#include <stdexcept>
#include <string_view>
#include <optional>
#include <utility>

namespace omarchy::plugins::discovery {
namespace {

constexpr std::size_t kMaximumManifestBytes = 1024 * 1024;
constexpr std::size_t kMaximumTraversalEntries = 8192;
constexpr std::size_t kMaximumTraversalDepth = 64;

[[noreturn]] void fail(std::string_view message) {
  throw std::runtime_error(std::string(message));
}

void require(bool condition, std::string_view message) {
  if (!condition)
    fail(message);
}

class Descriptor {
public:
  explicit Descriptor(int value) : value_(value) {}
  ~Descriptor() {
    if (value_ >= 0)
      ::close(value_);
  }
  Descriptor(Descriptor &&other) noexcept
      : value_(std::exchange(other.value_, -1)) {}
  Descriptor(const Descriptor &) = delete;
  Descriptor &operator=(const Descriptor &) = delete;
  Descriptor &operator=(Descriptor &&) = delete;
  [[nodiscard]] int get() const { return value_; }

private:
  int value_ = -1;
};

class DirectoryStream {
public:
  explicit DirectoryStream(int descriptor) : value_(::fdopendir(descriptor)) {
    if (value_ == nullptr)
      ::close(descriptor);
  }
  ~DirectoryStream() {
    if (value_ != nullptr)
      ::closedir(value_);
  }
  DirectoryStream(const DirectoryStream &) = delete;
  DirectoryStream &operator=(const DirectoryStream &) = delete;
  [[nodiscard]] DIR *get() const { return value_; }

private:
  DIR *value_ = nullptr;
};

struct OpenFile {
  Descriptor descriptor;
  struct stat metadata{};
};

struct OpenDirectory {
  Descriptor descriptor;
  struct stat metadata{};
};

struct PublishedOwner {
  std::uint32_t uid;
};

bool same_stable_metadata(const struct stat &before, const struct stat &after) {
  return before.st_dev == after.st_dev && before.st_ino == after.st_ino &&
         before.st_mode == after.st_mode && before.st_nlink == after.st_nlink &&
         before.st_size == after.st_size &&
         before.st_mtim.tv_sec == after.st_mtim.tv_sec &&
         before.st_mtim.tv_nsec == after.st_mtim.tv_nsec &&
         before.st_ctim.tv_sec == after.st_ctim.tv_sec &&
         before.st_ctim.tv_nsec == after.st_ctim.tv_nsec;
}

std::string read_open_file(int descriptor, std::uint64_t limit,
                           const struct stat &before) {
  require(::lseek(descriptor, 0, SEEK_SET) == 0, "cannot seek plugin file");
  std::string bytes;
  bytes.reserve(static_cast<std::size_t>(before.st_size));
  std::array<char, 8192> chunk{};
  for (;;) {
    const auto count = ::read(descriptor, chunk.data(), chunk.size());
    if (count < 0 && errno == EINTR)
      continue;
    require(count >= 0, "cannot read plugin file");
    if (count == 0)
      break;
    require(static_cast<std::uint64_t>(count) <= limit - bytes.size(),
            "plugin tree is too large");
    bytes.append(chunk.data(), static_cast<std::size_t>(count));
  }
  struct stat after{};
  require(::fstat(descriptor, &after) == 0, "cannot re-inspect plugin file");
  require(same_stable_metadata(before, after) &&
              bytes.size() == static_cast<std::size_t>(after.st_size),
          "plugin file changed while hashing");
  return bytes;
}

void enumerate_open_tree(int directory_fd, std::string_view prefix,
                         std::vector<OpenFile> &files,
                         std::vector<OpenDirectory> &directories,
                         manifest::TreeContents &contents,
                         std::size_t &entry_count, std::size_t depth,
                         std::optional<PublishedOwner> published_owner) {
  require(depth <= kMaximumTraversalDepth, "plugin tree traversal is too deep");
  Descriptor pinned(::openat(directory_fd, ".",
                             O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW));
  require(pinned.get() >= 0, "cannot pin plugin directory");
  struct stat directory_metadata{};
  require(::fstat(pinned.get(), &directory_metadata) == 0 &&
              S_ISDIR(directory_metadata.st_mode),
          "cannot inspect plugin directory");
  if (published_owner) {
    // Btrfs reports one link for a named directory, unlike filesystems that
    // include dot and parent links. Zero still identifies an unlinked inode.
    require(directory_metadata.st_uid == published_owner->uid &&
                directory_metadata.st_nlink != 0 &&
                (directory_metadata.st_mode & 07777) == 0555,
            "published plugin directory metadata is unsafe");
  }
  directories.push_back(
      {.descriptor = std::move(pinned), .metadata = directory_metadata});
  const int scan_fd = ::openat(directory_fd, ".",
                               O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
  require(scan_fd >= 0, "cannot open plugin directory for enumeration");
  DirectoryStream directory(scan_fd);
  require(directory.get() != nullptr, "cannot enumerate plugin directory");
  errno = 0;
  while (const auto *entry = ::readdir(directory.get())) {
    const std::string_view name(entry->d_name);
    if (name == "." || name == "..")
      continue;
    require(++entry_count <= kMaximumTraversalEntries,
            "plugin tree traversal has too many entries");
    require(!prefix.empty() || name != ".git", ".git entry in plugin tree");
    const std::string relative =
        prefix.empty() ? std::string(name)
                       : std::string(prefix) + "/" + std::string(name);
    struct stat metadata{};
    require(::fstatat(directory_fd, entry->d_name, &metadata,
                      AT_SYMLINK_NOFOLLOW) == 0,
            "cannot inspect plugin tree entry");
    require(!S_ISLNK(metadata.st_mode), "symlink in plugin tree");
    if (S_ISDIR(metadata.st_mode)) {
      Descriptor child(
          ::openat(directory_fd, entry->d_name,
                   O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW));
      require(child.get() >= 0, "cannot open plugin directory");
      enumerate_open_tree(child.get(), relative, files, directories, contents,
                          entry_count, depth + 1, published_owner);
      continue;
    }
    require(S_ISREG(metadata.st_mode), "special file in plugin tree");
    require(metadata.st_size >= 0, "plugin file has invalid size");
    Descriptor file(::openat(directory_fd, entry->d_name,
                             O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK));
    require(file.get() >= 0, "cannot open plugin file");
    struct stat opened{};
    require(::fstat(file.get(), &opened) == 0 && S_ISREG(opened.st_mode),
            "plugin file changed during traversal");
    if (published_owner) {
      require(opened.st_uid == published_owner->uid && opened.st_nlink == 1 &&
                  ((opened.st_mode & 07777) == 0444 ||
                   (opened.st_mode & 07777) == 0555),
              "published plugin file metadata is unsafe");
    }
    contents.add(
        {.relative = relative,
         .bytes =
             read_open_file(file.get(), contents.remaining_bytes(), opened),
         .executable = (opened.st_mode & (S_IXUSR | S_IXGRP | S_IXOTH)) != 0});
    files.push_back({.descriptor = std::move(file), .metadata = opened});
  }
  require(errno == 0, "cannot enumerate plugin directory");
}

} // namespace

DescriptorVerifiedPlugin discover(int revision_directory_fd,
                                  std::optional<PublishedOwner> published_owner) {
  struct stat root_metadata{};
  require(revision_directory_fd >= 0 &&
              ::fstat(revision_directory_fd, &root_metadata) == 0 &&
              S_ISDIR(root_metadata.st_mode),
          "plugin root descriptor is not a directory");

  std::vector<OpenFile> files;
  std::vector<OpenDirectory> directories;
  manifest::TreeContents contents;
  std::size_t entry_count = 0;
  enumerate_open_tree(revision_directory_fd, "", files, directories, contents,
                      entry_count, 0, published_owner);
  const auto *manifest_file = contents.find("manifest.json");
  require(manifest_file != nullptr, "plugin tree has no manifest.json");
  require(manifest_file->bytes.size() <= kMaximumManifestBytes,
          "manifest.json exceeds the one MiB limit");
  auto parsed = manifest::parse_manifest_v2(manifest_file->bytes);

  // The identity is only meaningful for one stable verification epoch. Check
  // every object again after all reads so an add/remove/replace cannot produce
  // a hybrid digest assembled from different directory states.
  for (const auto &file : files) {
    struct stat after{};
    require(::fstat(file.descriptor.get(), &after) == 0 &&
                same_stable_metadata(file.metadata, after),
            "plugin file changed during verification");
  }
  for (const auto &directory : directories) {
    struct stat after{};
    require(::fstat(directory.descriptor.get(), &after) == 0 &&
                same_stable_metadata(directory.metadata, after),
            "plugin directory changed during verification");
  }

  auto identity = manifest::identify_tree_contents(std::move(contents), parsed);
  return {.manifest = std::move(parsed), .identity = std::move(identity)};
}

DescriptorVerifiedPlugin discover_open_revision(int revision_directory_fd) {
  return discover(revision_directory_fd, std::nullopt);
}

DescriptorVerifiedPlugin discover_open_published_revision(
    int revision_directory_fd, std::uint32_t expected_uid) {
  return discover(revision_directory_fd,
                  PublishedOwner{.uid = expected_uid});
}

} // namespace omarchy::plugins::discovery
