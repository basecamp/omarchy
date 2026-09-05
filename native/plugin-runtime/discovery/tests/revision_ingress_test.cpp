#include "revision_ingress.hpp"

#include <fcntl.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

#include <array>
#include <atomic>
#include <barrier>
#include <cerrno>
#include <cstdio>
#include <cstring>
#include <filesystem>
#include <iostream>
#include <stdexcept>
#include <string>
#include <string_view>
#include <thread>
#include <utility>
#include <vector>

namespace discovery = omarchy::plugins::discovery;

namespace {

struct Entry {
  std::string path;
  char type = '0';
  unsigned mode = 0644;
  std::string bytes;
  std::string link;
  std::uint64_t declared_size = 0;
};

class Fd final {
public:
  explicit Fd(int fd = -1) : fd_(fd) {}
  ~Fd() {
    if (fd_ >= 0)
      ::close(fd_);
  }
  Fd(Fd &&other) noexcept : fd_(std::exchange(other.fd_, -1)) {}
  Fd &operator=(Fd &&other) noexcept {
    if (this != &other) {
      if (fd_ >= 0)
        ::close(fd_);
      fd_ = std::exchange(other.fd_, -1);
    }
    return *this;
  }
  Fd(const Fd &) = delete;
  Fd &operator=(const Fd &) = delete;
  [[nodiscard]] int get() const { return fd_; }

private:
  int fd_;
};

class TempDirectory final {
public:
  TempDirectory() {
    std::array<char, 80> pattern{};
    std::snprintf(pattern.data(), pattern.size(), "/tmp/omarchy-ingress-test-XXXXXX");
    const char *created = ::mkdtemp(pattern.data());
    if (created == nullptr)
      throw std::runtime_error("mkdtemp failed");
    path_ = created;
    root_ = Fd(::open(path_.c_str(), O_RDONLY | O_DIRECTORY | O_CLOEXEC));
    if (root_.get() < 0)
      throw std::runtime_error("open temp root failed");
  }
  ~TempDirectory() {
    std::error_code error;
    for (std::filesystem::recursive_directory_iterator it(path_, error), end;
         !error && it != end; it.increment(error)) {
      if (it->is_directory(error))
        std::filesystem::permissions(
            it->path(), std::filesystem::perms::owner_write,
            std::filesystem::perm_options::add, error);
    }
    std::filesystem::permissions(path_, std::filesystem::perms::owner_write,
                                 std::filesystem::perm_options::add, error);
    std::filesystem::remove_all(path_, error);
    if (error)
      std::terminate();
  }
  [[nodiscard]] int fd() const { return root_.get(); }
  [[nodiscard]] const std::string &path() const { return path_; }

private:
  std::string path_;
  Fd root_;
};

void check(bool condition, std::string_view message) {
  if (!condition)
    throw std::runtime_error(std::string(message));
}

void put_octal(char *output, std::size_t size, std::uint64_t value) {
  std::memset(output, '0', size);
  output[size - 1] = '\0';
  for (std::size_t index = size - 1; index-- > 0 && value != 0;) {
    output[index] = static_cast<char>('0' + (value & 7));
    value >>= 3;
  }
  check(value == 0, "test tar octal field overflow");
}

void write_all(int fd, const void *bytes, std::size_t size) {
  const auto *cursor = static_cast<const char *>(bytes);
  while (size != 0) {
    const auto count = ::write(fd, cursor, size);
    if (count < 0 && errno == EINTR)
      continue;
    check(count > 0, "test archive write failed");
    cursor += count;
    size -= static_cast<std::size_t>(count);
  }
}

Fd archive(const std::vector<Entry> &entries) {
  char path[] = "/tmp/omarchy-ingress-archive-XXXXXX";
  Fd fd(::mkstemp(path));
  check(fd.get() >= 0, "mkstemp archive failed");
  ::unlink(path);
  for (const auto &entry : entries) {
    std::array<char, 512> header{};
    std::string name = entry.path;
    std::string prefix;
    if (name.size() > 100) {
      const auto split = name.rfind('/');
      check(split != std::string::npos && split <= 155 &&
                name.size() - split - 1 <= 100,
            "test archive path cannot fit ustar");
      prefix = name.substr(0, split);
      name.erase(0, split + 1);
    }
    check(name.size() <= 100 && prefix.size() <= 155, "test path too long");
    std::memcpy(header.data(), name.data(), name.size());
    put_octal(header.data() + 100, 8, entry.mode);
    put_octal(header.data() + 108, 8, 12345);
    put_octal(header.data() + 116, 8, 54321);
    const auto size = entry.declared_size == 0 ? entry.bytes.size()
                                                : entry.declared_size;
    put_octal(header.data() + 124, 12, size);
    put_octal(header.data() + 136, 12, 1);
    std::memset(header.data() + 148, ' ', 8);
    header[156] = entry.type;
    std::memcpy(header.data() + 157, entry.link.data(), entry.link.size());
    std::memcpy(header.data() + 257, "ustar\0", 6);
    std::memcpy(header.data() + 263, "00", 2);
    std::memcpy(header.data() + 345, prefix.data(), prefix.size());
    unsigned checksum = 0;
    for (const unsigned char byte : header)
      checksum += byte;
    std::snprintf(header.data() + 148, 8, "%06o", checksum);
    header[154] = '\0';
    header[155] = ' ';
    write_all(fd.get(), header.data(), header.size());
    if (!entry.bytes.empty())
      write_all(fd.get(), entry.bytes.data(), entry.bytes.size());
    const std::array<char, 512> zero{};
    const auto padding = (512 - (entry.bytes.size() % 512)) % 512;
    if (padding != 0)
      write_all(fd.get(), zero.data(), padding);
  }
  const std::array<char, 1024> end{};
  write_all(fd.get(), end.data(), end.size());
  check(::lseek(fd.get(), 0, SEEK_SET) == 0, "seek archive failed");
  return fd;
}

constexpr std::string_view manifest = R"({
  "schemaVersion": 2,
  "id": "org.example.ingress",
  "name": "Ingress",
  "version": "1.0.0",
  "runtime": {"apiVersion": 1, "qml": "ui/Main.qml"},
  "surfaces": {"overlay": {"role": "overlay"}},
  "permissions": {"required": [], "optional": []}
})";

std::vector<Entry> valid_entries() {
  Entry directory;
  directory.path = "ui/";
  directory.type = '5';
  directory.mode = 0755;
  Entry manifest_entry;
  manifest_entry.path = "manifest.json";
  manifest_entry.bytes = manifest;
  Entry qml;
  qml.path = "ui/Main.qml";
  qml.bytes = "import QtQuick\nItem {}\n";
  return {std::move(directory), std::move(manifest_entry), std::move(qml)};
}

void expect_rejected(std::vector<Entry> entries, std::string_view label) {
  TempDirectory root;
  auto input = archive(entries);
  bool rejected = false;
  try {
    auto ignored = discovery::publish_revision_archive(
        input.get(), root.fd(), static_cast<std::uint32_t>(::geteuid()));
  } catch (const std::exception &) {
    rejected = true;
  }
  check(rejected, label);
  check(std::filesystem::is_empty(root.path()), "failed ingress left staging data");
}

void expect_descriptor_rejected(int descriptor, std::string_view label) {
  TempDirectory root;
  bool rejected = false;
  try {
    auto ignored = discovery::publish_revision_archive(
        descriptor, root.fd(), static_cast<std::uint32_t>(::geteuid()));
  } catch (const std::exception &) {
    rejected = true;
  }
  check(rejected, label);
}

void rewrite_header_checksum(int fd, std::array<char, 512> &header) {
  std::memset(header.data() + 148, ' ', 8);
  unsigned checksum = 0;
  for (const unsigned char byte : header)
    checksum += byte;
  std::snprintf(header.data() + 148, 8, "%06o", checksum);
  header[154] = '\0';
  header[155] = ' ';
  check(::pwrite(fd, header.data(), header.size(), 0) ==
            static_cast<ssize_t>(header.size()),
        "test header rewrite failed");
  check(::lseek(fd, 0, SEEK_SET) == 0, "test header rewind failed");
}

void positive_and_same_digest_race() {
  TempDirectory root;
  auto first_archive = archive(valid_entries());
  auto first = discovery::publish_revision_archive(
      first_archive.get(), root.fd(), static_cast<std::uint32_t>(::geteuid()));
  check(first.verified().manifest.id == "org.example.ingress",
        "published manifest changed");
  check(first.verified().identity.tree_sha256.size() == 64,
        "published digest is malformed");

  struct stat root_metadata{};
  check(::fstat(first.descriptor(), &root_metadata) == 0 &&
            (root_metadata.st_mode & 07777) == 0555,
        "published root is mutable");
  const int file = ::openat(first.descriptor(), "manifest.json",
                            O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
  struct stat file_metadata{};
  check(file >= 0 && ::fstat(file, &file_metadata) == 0 &&
            (file_metadata.st_mode & 07777) == 0444 &&
            file_metadata.st_nlink == 1,
        "published file metadata is unsafe");
  ::close(file);

  auto second_archive = archive(valid_entries());
  auto second = discovery::publish_revision_archive(
      second_archive.get(), root.fd(), static_cast<std::uint32_t>(::geteuid()));
  check(second.verified().identity == first.verified().identity,
        "same digest publication did not deduplicate");

  TempDirectory concurrent_root;
  auto left_archive = archive(valid_entries());
  auto right_archive = archive(valid_entries());
  std::barrier start(3);
  std::atomic<int> completed{0};
  std::atomic<int> failures{0};
  auto run = [&](int fd) {
    start.arrive_and_wait();
    try {
      auto result = discovery::publish_revision_archive(
          fd, concurrent_root.fd(), static_cast<std::uint32_t>(::geteuid()));
      (void)result;
      ++completed;
    } catch (...) {
      ++failures;
    }
  };
  std::thread left(run, left_archive.get());
  std::thread right(run, right_archive.get());
  start.arrive_and_wait();
  left.join();
  right.join();
  check(failures == 0 && completed == 2 &&
            std::ranges::distance(std::filesystem::directory_iterator(
                                      concurrent_root.path()),
                                  std::filesystem::directory_iterator{}) == 1,
        "concurrent same-digest publication was not deduplicated");
}

void unsafe_archives() {
  auto replace_qml = [](std::string path, char type = '0', unsigned mode = 0644,
                        std::string link = {}) {
    auto entries = valid_entries();
    entries.back().path = std::move(path);
    entries.back().type = type;
    entries.back().mode = mode;
    entries.back().link = std::move(link);
    return entries;
  };
  expect_rejected(replace_qml("/ui/Main.qml"), "absolute path accepted");
  expect_rejected(replace_qml("ui/../Main.qml"), "parent traversal accepted");
  expect_rejected(replace_qml("ui//Main.qml"), "empty path component accepted");
  expect_rejected(replace_qml("ui/./Main.qml"), "dot path component accepted");
  expect_rejected(replace_qml("ui/Main.qml", '2', 0777, "elsewhere"),
                  "symlink accepted");
  expect_rejected(replace_qml("ui/Main.qml", '1', 0644, "manifest.json"),
                  "hardlink accepted");
  expect_rejected(replace_qml("ui/Main.qml", '6'), "special file accepted");
  expect_rejected(replace_qml("ui/Main.qml", '0', 04755), "set-id mode accepted");
  expect_rejected(replace_qml("ui/Main.qml", '0', 0664),
                  "group-writable mode accepted");

  auto duplicate = valid_entries();
  duplicate.push_back(duplicate.back());
  expect_rejected(std::move(duplicate), "duplicate path accepted");
  auto prefix_collision = valid_entries();
  Entry blocked;
  blocked.path = "blocked";
  blocked.bytes = "file";
  prefix_collision.insert(prefix_collision.begin(), blocked);
  Entry child;
  child.path = "blocked/child";
  child.bytes = "file";
  prefix_collision.push_back(child);
  expect_rejected(std::move(prefix_collision), "file/directory alias accepted");

  std::string deep;
  for (int index = 0; index < 65; ++index)
    deep += (index == 0 ? "a" : "/a");
  expect_rejected(replace_qml(deep), "depth bound was not enforced");
  auto oversized = valid_entries();
  oversized.back().declared_size = 64ULL * 1024ULL * 1024ULL + 1;
  expect_rejected(std::move(oversized), "byte bound was not enforced");

  TempDirectory directory_archive;
  expect_descriptor_rejected(directory_archive.fd(),
                             "directory archive descriptor accepted");
  int pipe_fds[2]{};
  check(::pipe2(pipe_fds, O_CLOEXEC) == 0, "test pipe failed");
  expect_descriptor_rejected(pipe_fds[0], "nonseekable archive accepted");
  ::close(pipe_fds[0]);
  ::close(pipe_fds[1]);

  {
    auto malformed = archive(valid_entries());
    std::array<char, 512> header{};
    check(::pread(malformed.get(), header.data(), header.size(), 0) == 512,
          "test header read failed");
    header[0] ^= 1;
    check(::pwrite(malformed.get(), header.data(), header.size(), 0) == 512,
          "test checksum corruption failed");
    expect_descriptor_rejected(malformed.get(), "bad archive checksum accepted");
  }
  {
    auto malformed = archive(valid_entries());
    std::array<char, 512> header{};
    check(::pread(malformed.get(), header.data(), header.size(), 0) == 512,
          "test header read failed");
    header[124] = '9';
    rewrite_header_checksum(malformed.get(), header);
    expect_descriptor_rejected(malformed.get(), "bad numeric field accepted");
  }
  {
    auto malformed = archive(valid_entries());
    std::array<char, 512> header{};
    check(::pread(malformed.get(), header.data(), header.size(), 0) == 512,
          "test header read failed");
    header[263] = '9';
    rewrite_header_checksum(malformed.get(), header);
    expect_descriptor_rejected(malformed.get(), "bad ustar version accepted");
  }
  {
    auto malformed = archive(valid_entries());
    check(::lseek(malformed.get(), 0, SEEK_END) >= 0 &&
              ::write(malformed.get(), "x", 1) == 1 &&
              ::lseek(malformed.get(), 0, SEEK_SET) == 0,
          "test trailer corruption failed");
    expect_descriptor_rejected(malformed.get(),
                               "nonzero trailing archive data accepted");
  }
  {
    TempDirectory unsafe_root;
    check(::fchmod(unsafe_root.fd(), 0755) == 0,
          "test root mode mutation failed");
    auto input = archive(valid_entries());
    bool rejected = false;
    try {
      auto ignored = discovery::publish_revision_archive(
          input.get(), unsafe_root.fd(),
          static_cast<std::uint32_t>(::geteuid()));
    } catch (...) {
      rejected = true;
    }
    check(rejected, "nonprivate revisions root accepted");
  }
}

void existing_digest_cannot_be_substituted() {
  TempDirectory root;
  auto input = archive(valid_entries());
  auto first = discovery::publish_revision_archive(
      input.get(), root.fd(), static_cast<std::uint32_t>(::geteuid()));
  check(::fchmod(first.descriptor(), 0755) == 0,
        "test could not mutate published directory");
  check(::fchmodat(first.descriptor(), "manifest.json", 0644, 0) == 0,
        "test could not mutate published file mode");
  check(::fchmod(first.descriptor(), 0555) == 0,
        "test could not restore published root mode");
  auto retry = archive(valid_entries());
  bool rejected = false;
  try {
    auto ignored = discovery::publish_revision_archive(
        retry.get(), root.fd(), static_cast<std::uint32_t>(::geteuid()));
  } catch (const std::exception &) {
    rejected = true;
  }
  check(rejected, "unsafe preexisting digest tree was trusted");

  TempDirectory hardlink_root;
  auto hardlink_input = archive(valid_entries());
  auto hardlinked = discovery::publish_revision_archive(
      hardlink_input.get(), hardlink_root.fd(),
      static_cast<std::uint32_t>(::geteuid()));
  check(::linkat(hardlinked.descriptor(), "manifest.json", hardlink_root.fd(),
                 "outside-hardlink", 0) == 0,
        "test could not create published-file hardlink");
  auto hardlink_retry = archive(valid_entries());
  rejected = false;
  try {
    auto ignored = discovery::publish_revision_archive(
        hardlink_retry.get(), hardlink_root.fd(),
        static_cast<std::uint32_t>(::geteuid()));
  } catch (const std::exception &) {
    rejected = true;
  }
  check(rejected, "hardlinked preexisting digest tree was trusted");
}

void crash_points_never_publish_torn_tree() {
  for (const auto point : {discovery::RevisionIngressCrashPoint::extracted,
                           discovery::RevisionIngressCrashPoint::verified,
                           discovery::RevisionIngressCrashPoint::durable,
                           discovery::RevisionIngressCrashPoint::renamed,
                           discovery::RevisionIngressCrashPoint::published}) {
    TempDirectory root;
    auto input = archive(valid_entries());
    const pid_t child = ::fork();
    check(child >= 0, "fork failed");
    if (child == 0) {
      discovery::set_revision_ingress_crash_point_for_testing(point);
      try {
        auto ignored = discovery::publish_revision_archive(
            input.get(), root.fd(), static_cast<std::uint32_t>(::geteuid()));
      } catch (...) {
        ::_exit(120);
      }
      ::_exit(121);
    }
    int status = 0;
    check(::waitpid(child, &status, 0) == child && WIFEXITED(status) &&
              WEXITSTATUS(status) == 80 + static_cast<int>(point),
          "crash injection did not stop at requested point");
    for (const auto &entry : std::filesystem::directory_iterator(root.path())) {
      const auto name = entry.path().filename().string();
      if (name.starts_with(".incoming-"))
        continue;
      check(name.size() == 64, "crash exposed a non-digest revision");
      Fd revision(::openat(root.fd(), name.c_str(),
                           O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW));
      check(revision.get() >= 0, "crash publication cannot be reopened");
      const auto verified = discovery::discover_open_revision(revision.get());
      check(verified.identity.tree_sha256 == name,
            "crash publication is torn or mislabeled");
    }
    auto recovery_archive = archive(valid_entries());
    auto recovered = discovery::publish_revision_archive(
        recovery_archive.get(), root.fd(),
        static_cast<std::uint32_t>(::geteuid()));
    (void)recovered;
    for (const auto &entry : std::filesystem::directory_iterator(root.path()))
      check(!entry.path().filename().string().starts_with(".incoming-"),
            "next ingress did not recover abandoned staging");
  }
}

} // namespace

int main() {
  try {
    positive_and_same_digest_race();
    unsafe_archives();
    existing_digest_cannot_be_substituted();
    crash_points_never_publish_torn_tree();
    std::cout << "revision ingress tests passed\n";
    return 0;
  } catch (const std::exception &error) {
    std::cerr << "revision ingress test failed: " << error.what() << '\n';
    return 1;
  }
}
