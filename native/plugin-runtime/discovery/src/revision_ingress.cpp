#include "revision_ingress.hpp"

#include <fcntl.h>
#include <linux/fs.h>
#include <sys/random.h>
#include <sys/stat.h>
#include <sys/file.h>
#include <sys/syscall.h>
#include <unistd.h>

#include <dirent.h>

#include <algorithm>
#include <array>
#include <cerrno>
#include <charconv>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <limits>
#include <memory>
#include <stdexcept>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace omarchy::plugins::discovery {
namespace {

constexpr std::size_t kBlockBytes = 512;
constexpr std::size_t kMaximumFiles = 4096;
constexpr std::size_t kMaximumEntries = 8192;
constexpr std::size_t kMaximumDepth = 64;
constexpr std::size_t kMaximumPathBytes = 1024;
constexpr std::size_t kMaximumComponentBytes = 255;
constexpr std::uint64_t kMaximumTreeBytes = 64ULL * 1024ULL * 1024ULL;
constexpr std::uint64_t kMaximumArchiveBytes = 72ULL * 1024ULL * 1024ULL;

[[noreturn]] void fail(std::string_view message) {
  throw std::runtime_error(std::string(message));
}

void require(bool condition, std::string_view message) {
  if (!condition)
    fail(message);
}

class Descriptor final {
public:
  explicit Descriptor(int value = -1) noexcept : value_(value) {}
  ~Descriptor() {
    if (value_ >= 0)
      ::close(value_);
  }
  Descriptor(Descriptor &&other) noexcept
      : value_(std::exchange(other.value_, -1)) {}
  Descriptor &operator=(Descriptor &&other) noexcept {
    if (this != &other) {
      if (value_ >= 0)
        ::close(value_);
      value_ = std::exchange(other.value_, -1);
    }
    return *this;
  }
  Descriptor(const Descriptor &) = delete;
  Descriptor &operator=(const Descriptor &) = delete;
  [[nodiscard]] int get() const noexcept { return value_; }
  [[nodiscard]] int release() noexcept { return std::exchange(value_, -1); }

private:
  int value_;
};

struct DirectoryCloser {
  void operator()(DIR *directory) const noexcept {
    if (directory != nullptr)
      ::closedir(directory);
  }
};

#ifdef OMARCHY_REVISION_INGRESS_TESTING
RevisionIngressCrashPoint crash_point = RevisionIngressCrashPoint::none;

void crash_if_requested(RevisionIngressCrashPoint point) noexcept {
  if (crash_point == point)
    ::_exit(80 + static_cast<int>(point));
}
#endif

bool stable_identity(const struct stat &left, const struct stat &right) {
  return left.st_dev == right.st_dev && left.st_ino == right.st_ino &&
         left.st_mode == right.st_mode && left.st_uid == right.st_uid &&
         left.st_gid == right.st_gid && left.st_nlink == right.st_nlink &&
         left.st_size == right.st_size &&
         left.st_mtim.tv_sec == right.st_mtim.tv_sec &&
         left.st_mtim.tv_nsec == right.st_mtim.tv_nsec &&
         left.st_ctim.tv_sec == right.st_ctim.tv_sec &&
         left.st_ctim.tv_nsec == right.st_ctim.tv_nsec;
}

void read_exact(int fd, void *output, std::size_t size) {
  auto *cursor = static_cast<std::byte *>(output);
  while (size != 0) {
    const auto count = ::read(fd, cursor, size);
    if (count < 0 && errno == EINTR)
      continue;
    require(count > 0, "truncated plugin archive");
    cursor += count;
    size -= static_cast<std::size_t>(count);
  }
}

bool zero_block(const std::array<char, kBlockBytes> &block) {
  return std::ranges::all_of(block, [](char byte) { return byte == '\0'; });
}

std::string field(const char *bytes, std::size_t size) {
  const auto *end = static_cast<const char *>(std::memchr(bytes, '\0', size));
  if (end == nullptr)
    end = bytes + size;
  return std::string(bytes, end);
}

std::uint64_t octal(const char *bytes, std::size_t size,
                    std::string_view message) {
  require(size != 0 && (static_cast<unsigned char>(bytes[0]) & 0x80U) == 0,
          message);
  std::size_t begin = 0;
  while (begin < size && (bytes[begin] == ' ' || bytes[begin] == '\0'))
    ++begin;
  std::size_t end = begin;
  while (end < size && bytes[end] >= '0' && bytes[end] <= '7')
    ++end;
  for (std::size_t index = end; index < size; ++index)
    require(bytes[index] == ' ' || bytes[index] == '\0', message);
  require(end != begin, message);
  std::uint64_t result = 0;
  for (std::size_t index = begin; index < end; ++index) {
    require(result <= (std::numeric_limits<std::uint64_t>::max() >> 3),
            message);
    result = (result << 3) + static_cast<unsigned>(bytes[index] - '0');
  }
  return result;
}

void validate_checksum(std::array<char, kBlockBytes> block) {
  const auto expected = octal(block.data() + 148, 8, "invalid archive checksum");
  std::fill_n(block.data() + 148, 8, ' ');
  std::uint64_t actual = 0;
  for (const unsigned char byte : block)
    actual += byte;
  require(actual == expected, "invalid archive checksum");
}

std::vector<std::string> validate_path(std::string_view path, bool directory) {
  require(!path.empty() && path.front() != '/' && path.size() <= kMaximumPathBytes,
          "unsafe archive path");
  if (directory) {
    require(path.back() == '/', "directory archive path has no trailing slash");
    path.remove_suffix(1);
  } else {
    require(path.back() != '/', "file archive path has a trailing slash");
  }
  require(!path.empty(), "unsafe archive path");
  std::vector<std::string> result;
  std::size_t begin = 0;
  while (begin <= path.size()) {
    const auto slash = path.find('/', begin);
    const auto end = slash == std::string_view::npos ? path.size() : slash;
    const auto component = path.substr(begin, end - begin);
    require(!component.empty() && component != "." && component != ".." &&
                component.size() <= kMaximumComponentBytes,
            "unsafe archive path");
    result.emplace_back(component);
    require(result.size() <= kMaximumDepth, "archive path is too deep");
    if (slash == std::string_view::npos)
      break;
    begin = slash + 1;
  }
  return result;
}

Descriptor open_directory_component(int parent, std::string_view component) {
  const std::string name(component);
  Descriptor child(::openat(parent, name.c_str(),
                            O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW));
  require(child.get() >= 0, "archive parent directory is missing or unsafe");
  return child;
}

void normalize_new_directory(int parent, const std::string &name,
                             std::uint32_t expected_uid) {
  // A named directory has a nonzero link count. Do not assume traditional
  // parent-link accounting: Btrfs validly reports one for directories.
  Descriptor path(::openat(parent, name.c_str(),
                           O_PATH | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW));
  struct stat named{};
  struct stat pinned{};
  require(path.get() >= 0 &&
              ::fstatat(parent, name.c_str(), &named, AT_SYMLINK_NOFOLLOW) == 0 &&
              ::fstat(path.get(), &pinned) == 0 && S_ISDIR(pinned.st_mode) &&
              pinned.st_uid == expected_uid && pinned.st_dev == named.st_dev &&
              pinned.st_ino == named.st_ino && pinned.st_nlink != 0,
          "new directory identity is unsafe");
  require(::syscall(SYS_fchmodat2, path.get(), "", 0700, AT_EMPTY_PATH) == 0 &&
              ::fstat(path.get(), &pinned) == 0 &&
              (pinned.st_mode & 07777) == 0700,
          "cannot normalize new directory mode");
}

Descriptor open_parent(int root, const std::vector<std::string> &components) {
  Descriptor current(::openat(root, ".",
                              O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW));
  require(current.get() >= 0, "cannot pin archive staging directory");
  for (std::size_t index = 0; index + 1 < components.size(); ++index)
    current = open_directory_component(current.get(), components[index]);
  return current;
}

void verify_named_identity(int parent, const char *name, int opened,
                           mode_t type) {
  struct stat named{};
  struct stat pinned{};
  require(::fstatat(parent, name, &named, AT_SYMLINK_NOFOLLOW) == 0 &&
              ::fstat(opened, &pinned) == 0 && named.st_dev == pinned.st_dev &&
              named.st_ino == pinned.st_ino && (pinned.st_mode & S_IFMT) == type &&
              (type == S_IFDIR ? pinned.st_nlink != 0 : pinned.st_nlink == 1),
          "archive entry identity is unsafe");
}

void create_directory(int root, const std::vector<std::string> &components,
                      std::uint32_t expected_uid) {
  auto parent = open_parent(root, components);
  const auto &name = components.back();
  require(::mkdirat(parent.get(), name.c_str(), 0700) == 0,
          "duplicate or conflicting archive path");
  normalize_new_directory(parent.get(), name, expected_uid);
  Descriptor directory(::openat(parent.get(), name.c_str(),
                                O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW));
  require(directory.get() >= 0, "cannot open extracted directory");
  verify_named_identity(parent.get(), name.c_str(), directory.get(), S_IFDIR);
  struct stat metadata{};
  require(::fstat(directory.get(), &metadata) == 0 &&
              metadata.st_uid == expected_uid,
          "extracted directory has unexpected ownership");
}

void copy_file(int archive_fd, int root,
               const std::vector<std::string> &components, std::uint64_t size,
               bool executable, std::uint32_t expected_uid) {
  auto parent = open_parent(root, components);
  const auto &name = components.back();
  Descriptor output(::openat(parent.get(), name.c_str(),
                             O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
                             0600));
  require(output.get() >= 0, "duplicate or conflicting archive path");
  verify_named_identity(parent.get(), name.c_str(), output.get(), S_IFREG);
  struct stat metadata{};
  require(::fstat(output.get(), &metadata) == 0 &&
              metadata.st_uid == expected_uid,
          "extracted file has unexpected ownership");
  std::array<std::byte, 16384> buffer{};
  std::uint64_t remaining = size;
  while (remaining != 0) {
    const auto amount = static_cast<std::size_t>(
        std::min<std::uint64_t>(remaining, buffer.size()));
    read_exact(archive_fd, buffer.data(), amount);
    std::size_t written = 0;
    while (written != amount) {
      const auto count = ::write(output.get(), buffer.data() + written,
                                 amount - written);
      if (count < 0 && errno == EINTR)
        continue;
      require(count > 0, "cannot write extracted plugin file");
      written += static_cast<std::size_t>(count);
    }
    remaining -= amount;
  }
  const auto padding = (kBlockBytes - (size % kBlockBytes)) % kBlockBytes;
  std::array<std::byte, kBlockBytes> ignored{};
  if (padding != 0) {
    read_exact(archive_fd, ignored.data(), static_cast<std::size_t>(padding));
    require(std::all_of(ignored.begin(), ignored.begin() + padding,
                        [](std::byte byte) { return byte == std::byte{0}; }),
            "archive file padding is nonzero");
  }
  require(::fchmod(output.get(), executable ? 0555 : 0444) == 0 &&
              ::fsync(output.get()) == 0,
          "cannot make extracted plugin file durable");
}

void make_tree_immutable_and_durable(int directory_fd,
                                     std::uint32_t expected_uid) {
  Descriptor scan(::openat(directory_fd, ".",
                           O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW));
  require(scan.get() >= 0, "cannot scan extracted directory");
  DIR *raw = ::fdopendir(scan.release());
  require(raw != nullptr, "cannot enumerate extracted directory");
  std::unique_ptr<DIR, DirectoryCloser> directory(raw);
  std::vector<std::string> names;
  for (;;) {
    errno = 0;
    const auto *entry = ::readdir(directory.get());
    if (entry == nullptr) {
      require(errno == 0, "cannot enumerate extracted directory");
      break;
    }
    const std::string_view name(entry->d_name);
    if (name != "." && name != "..")
      names.emplace_back(name);
  }
  directory.reset();
  for (const auto &name : names) {
    struct stat metadata{};
    require(::fstatat(directory_fd, name.c_str(), &metadata,
                      AT_SYMLINK_NOFOLLOW) == 0 &&
                metadata.st_uid == expected_uid &&
                (S_ISDIR(metadata.st_mode) ? metadata.st_nlink != 0
                                           : metadata.st_nlink == 1),
            "extracted entry metadata is unsafe");
    if (S_ISDIR(metadata.st_mode)) {
      auto child = open_directory_component(directory_fd, name);
      make_tree_immutable_and_durable(child.get(), expected_uid);
    } else {
      require(S_ISREG(metadata.st_mode) &&
                  (metadata.st_mode & (S_ISUID | S_ISGID | S_IWUSR | S_IWGRP |
                                       S_IWOTH)) == 0,
              "extracted entry metadata is unsafe");
    }
  }
  require(::fchmod(directory_fd, 0555) == 0 && ::fsync(directory_fd) == 0,
          "cannot make extracted directory durable");
}

bool remove_tree(int directory_fd) noexcept {
  if (::fchmod(directory_fd, 0700) != 0)
    return false;
  const int scan_fd = ::openat(directory_fd, ".",
                               O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
  if (scan_fd < 0)
    return false;
  DIR *directory = ::fdopendir(scan_fd);
  if (directory == nullptr) {
    ::close(scan_fd);
    return false;
  }
  bool okay = true;
  for (;;) {
    errno = 0;
    const auto *entry = ::readdir(directory);
    if (entry == nullptr) {
      if (errno != 0)
        okay = false;
      break;
    }
    const std::string_view name(entry->d_name);
    if (name == "." || name == "..")
      continue;
    struct stat metadata{};
    if (::fstatat(directory_fd, entry->d_name, &metadata,
                  AT_SYMLINK_NOFOLLOW) != 0) {
      okay = false;
      continue;
    }
    if (S_ISDIR(metadata.st_mode)) {
      const int child = ::openat(directory_fd, entry->d_name,
                                 O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
      struct stat pinned{};
      if (child < 0 || ::fstat(child, &pinned) != 0 ||
          pinned.st_dev != metadata.st_dev || pinned.st_ino != metadata.st_ino ||
          !S_ISDIR(pinned.st_mode)) {
        if (child >= 0)
          ::close(child);
        okay = false;
        continue;
      }
      const bool child_removed = remove_tree(child);
      ::close(child);
      if (!child_removed ||
          ::unlinkat(directory_fd, entry->d_name, AT_REMOVEDIR) != 0)
        okay = false;
    } else {
      if (!S_ISREG(metadata.st_mode) || metadata.st_nlink != 1 ||
          ::unlinkat(directory_fd, entry->d_name, 0) != 0)
        okay = false;
    }
  }
  ::closedir(directory);
  return okay;
}

bool staging_name_is_canonical(std::string_view name) {
  constexpr std::string_view prefix = ".incoming-";
  if (!name.starts_with(prefix) || name.size() != prefix.size() + 24)
    return false;
  return std::ranges::all_of(name.substr(prefix.size()), [](char byte) {
    return (byte >= '0' && byte <= '9') || (byte >= 'a' && byte <= 'f');
  });
}

void recover_abandoned_staging(int root, std::uint32_t expected_uid) {
  constexpr std::size_t maximum_abandoned = 1024;
  Descriptor scan(::openat(root, ".",
                           O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW));
  require(scan.get() >= 0, "cannot scan revision root");
  const int scan_fd = scan.release();
  DIR *raw = ::fdopendir(scan_fd);
  if (raw == nullptr) {
    ::close(scan_fd);
    fail("cannot enumerate revision root");
  }
  std::unique_ptr<DIR, DirectoryCloser> directory(raw);
  std::vector<std::string> abandoned;
  for (;;) {
    errno = 0;
    const auto *entry = ::readdir(directory.get());
    if (entry == nullptr) {
      require(errno == 0, "cannot enumerate revision root");
      break;
    }
    const std::string_view name(entry->d_name);
    if (name.starts_with(".incoming-")) {
      require(staging_name_is_canonical(name),
              "revision root has malformed staging state");
      struct stat named{};
      require(::fstatat(root, entry->d_name, &named, AT_SYMLINK_NOFOLLOW) == 0 &&
                  S_ISDIR(named.st_mode) && named.st_uid == expected_uid,
              "abandoned staging entry is unsafe");
      require(abandoned.size() < maximum_abandoned,
              "too many abandoned revision staging directories");
      abandoned.emplace_back(name);
    }
  }
  directory.reset();
  for (const auto &name : abandoned) {
    struct stat named{};
    require(::fstatat(root, name.c_str(), &named, AT_SYMLINK_NOFOLLOW) == 0 &&
                S_ISDIR(named.st_mode) && named.st_uid == expected_uid,
            "abandoned staging entry changed");
    Descriptor staging(::openat(root, name.c_str(),
                                O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW));
    struct stat pinned{};
    require(staging.get() >= 0 && ::fstat(staging.get(), &pinned) == 0 &&
                pinned.st_dev == named.st_dev && pinned.st_ino == named.st_ino,
            "abandoned staging identity changed");
    require(remove_tree(staging.get()) &&
                ::unlinkat(root, name.c_str(), AT_REMOVEDIR) == 0,
            "cannot recover abandoned revision staging");
  }
  require(::fsync(root) == 0,
          "cannot sync revision staging recovery");
}

std::string staging_name() {
  std::array<unsigned char, 12> random{};
  require(::getrandom(random.data(), random.size(), 0) ==
              static_cast<ssize_t>(random.size()),
          "cannot generate private staging name");
  constexpr char hex[] = "0123456789abcdef";
  std::string name = ".incoming-";
  for (const auto byte : random) {
    name.push_back(hex[byte >> 4]);
    name.push_back(hex[byte & 15]);
  }
  return name;
}

void validate_root(int fd, std::uint32_t expected_uid) {
  struct stat metadata{};
  require(fd >= 0 && ::fstat(fd, &metadata) == 0 && S_ISDIR(metadata.st_mode) &&
              metadata.st_uid == expected_uid &&
              metadata.st_nlink != 0 &&
              (metadata.st_mode & 07777) == 0700 &&
              (metadata.st_mode & (S_IWGRP | S_IWOTH)) == 0,
          "revision root is not private and trusted");
}

Descriptor open_published(int root, const std::string &digest) {
  Descriptor result(::openat(root, digest.c_str(),
                             O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW));
  require(result.get() >= 0, "cannot open published revision");
  return result;
}

} // namespace

PublishedRevision::PublishedRevision(int descriptor,
                                     DescriptorVerifiedPlugin verified) noexcept
    : descriptor_(descriptor), verified_(std::move(verified)) {}

PublishedRevision::PublishedRevision(PublishedRevision &&other) noexcept
    : descriptor_(std::exchange(other.descriptor_, -1)),
      verified_(std::move(other.verified_)) {}

PublishedRevision &PublishedRevision::operator=(PublishedRevision &&other) noexcept {
  if (this != &other) {
    if (descriptor_ >= 0)
      ::close(descriptor_);
    descriptor_ = std::exchange(other.descriptor_, -1);
    verified_ = std::move(other.verified_);
  }
  return *this;
}

PublishedRevision::~PublishedRevision() {
  if (descriptor_ >= 0)
    ::close(descriptor_);
}

PublishedRevision publish_revision_archive(int archive_fd, int revisions_root_fd,
                                           std::uint32_t expected_uid) {
  validate_root(revisions_root_fd, expected_uid);
  Descriptor locked_root(::openat(revisions_root_fd, ".",
                                  O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW));
  require(locked_root.get() >= 0 && ::flock(locked_root.get(), LOCK_EX) == 0,
          "cannot lock revision root");
  validate_root(locked_root.get(), expected_uid);
  revisions_root_fd = locked_root.get();
  recover_abandoned_staging(revisions_root_fd, expected_uid);
  struct stat archive_before{};
  require(archive_fd >= 0 && ::fstat(archive_fd, &archive_before) == 0 &&
              S_ISREG(archive_before.st_mode) && archive_before.st_size >= 0 &&
              static_cast<std::uint64_t>(archive_before.st_size) <=
                  kMaximumArchiveBytes &&
              ::lseek(archive_fd, 0, SEEK_SET) == 0,
          "plugin archive descriptor is not a seekable regular file");

  const std::string stage_name = staging_name();
  require(::mkdirat(revisions_root_fd, stage_name.c_str(), 0700) == 0,
          "cannot create private revision staging directory");
  normalize_new_directory(revisions_root_fd, stage_name, expected_uid);
  Descriptor stage(::openat(revisions_root_fd, stage_name.c_str(),
                            O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW));
  if (stage.get() < 0) {
    ::unlinkat(revisions_root_fd, stage_name.c_str(), AT_REMOVEDIR);
    fail("cannot open private revision staging directory");
  }

  bool stage_named = true;
  try {
    std::size_t entries = 0;
    std::size_t files = 0;
    std::uint64_t total_bytes = 0;
    bool saw_end = false;
    for (;;) {
      std::array<char, kBlockBytes> header{};
      read_exact(archive_fd, header.data(), header.size());
      if (zero_block(header)) {
        std::array<char, kBlockBytes> second{};
        read_exact(archive_fd, second.data(), second.size());
        require(zero_block(second), "archive has an invalid end marker");
        saw_end = true;
        break;
      }
      require(++entries <= kMaximumEntries, "plugin archive has too many entries");
      validate_checksum(header);
      require(std::memcmp(header.data() + 257, "ustar\0", 6) == 0 &&
                  std::memcmp(header.data() + 263, "00", 2) == 0,
              "plugin archive is not strict ustar");
      const char type = header[156] == '\0' ? '0' : header[156];
      require(type == '0' || type == '5', "archive links and special files are forbidden");
      require(std::all_of(header.begin() + 157, header.begin() + 257,
                          [](char byte) { return byte == '\0'; }),
              "archive link target is forbidden");
      const auto mode = octal(header.data() + 100, 8, "invalid archive mode");
      (void)octal(header.data() + 108, 8, "invalid archive owner");
      (void)octal(header.data() + 116, 8, "invalid archive group");
      (void)octal(header.data() + 136, 12, "invalid archive timestamp");
      require((mode & (S_ISUID | S_ISGID | S_ISVTX | S_IWGRP | S_IWOTH)) == 0 &&
                  (mode & ~0777ULL) == 0,
              "unsafe archive mode");
      const auto size = octal(header.data() + 124, 12, "invalid archive size");
      require(type == '0' || size == 0, "archive directory has file data");
      std::string path = field(header.data(), 100);
      const auto prefix = field(header.data() + 345, 155);
      if (!prefix.empty())
        path = prefix + "/" + path;
      auto components = validate_path(path, type == '5');
      if (type == '5') {
        create_directory(stage.get(), components, expected_uid);
      } else {
        require(++files <= kMaximumFiles && size <= kMaximumTreeBytes - total_bytes,
                "plugin archive exceeds file or byte limits");
        total_bytes += size;
        copy_file(archive_fd, stage.get(), components, size,
                  (mode & 0111) != 0, expected_uid);
      }
    }
    require(saw_end, "plugin archive has no end marker");
    std::array<char, 8192> trailing{};
    for (;;) {
      const auto count = ::read(archive_fd, trailing.data(), trailing.size());
      if (count < 0 && errno == EINTR)
        continue;
      require(count >= 0, "cannot read plugin archive trailer");
      if (count == 0)
        break;
      require(std::all_of(trailing.begin(), trailing.begin() + count,
                          [](char byte) { return byte == '\0'; }),
              "plugin archive has nonzero trailing data");
    }
    struct stat archive_after{};
    require(::fstat(archive_fd, &archive_after) == 0 &&
                stable_identity(archive_before, archive_after),
            "plugin archive changed during extraction");
#ifdef OMARCHY_REVISION_INGRESS_TESTING
    crash_if_requested(RevisionIngressCrashPoint::extracted);
#endif

    make_tree_immutable_and_durable(stage.get(), expected_uid);
    auto verified = discover_open_published_revision(stage.get(), expected_uid);
#ifdef OMARCHY_REVISION_INGRESS_TESTING
    crash_if_requested(RevisionIngressCrashPoint::verified);
#endif
    require(::fsync(stage.get()) == 0, "cannot sync verified revision");
#ifdef OMARCHY_REVISION_INGRESS_TESTING
    crash_if_requested(RevisionIngressCrashPoint::durable);
#endif

    const auto &digest = verified.identity.tree_sha256;
    const long renamed = ::syscall(SYS_renameat2, revisions_root_fd,
                                   stage_name.c_str(), revisions_root_fd,
                                   digest.c_str(), RENAME_NOREPLACE);
    bool created = false;
    if (renamed == 0) {
      stage_named = false;
      created = true;
#ifdef OMARCHY_REVISION_INGRESS_TESTING
      crash_if_requested(RevisionIngressCrashPoint::renamed);
#endif
      require(::fsync(revisions_root_fd) == 0,
              "cannot sync published revision directory");
    } else {
      require(errno == EEXIST, "cannot publish immutable revision");
    }

    auto published = open_published(revisions_root_fd, digest);
    auto published_verified =
        discover_open_published_revision(published.get(), expected_uid);
    require(published_verified.identity == verified.identity &&
                published_verified.manifest == verified.manifest,
            "published digest names a different revision");
    if (!created) {
      require(remove_tree(stage.get()) &&
                  ::unlinkat(revisions_root_fd, stage_name.c_str(), AT_REMOVEDIR) == 0,
              "cannot remove redundant revision staging directory");
      stage_named = false;
    }
#ifdef OMARCHY_REVISION_INGRESS_TESTING
    crash_if_requested(RevisionIngressCrashPoint::published);
#endif
    return PublishedRevision(published.release(), std::move(published_verified));
  } catch (...) {
    if (stage_named) {
      remove_tree(stage.get());
      ::unlinkat(revisions_root_fd, stage_name.c_str(), AT_REMOVEDIR);
    }
    throw;
  }
}

#ifdef OMARCHY_REVISION_INGRESS_TESTING
void set_revision_ingress_crash_point_for_testing(
    RevisionIngressCrashPoint point) noexcept {
  crash_point = point;
}
#endif

} // namespace omarchy::plugins::discovery
