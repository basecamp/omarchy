#include "omarchy/plugin_runtime/providers/private_storage_backend.hpp"

#include <dirent.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

#include <array>
#include <cerrno>
#include <cstdio>
#include <limits>
#include <string>

namespace omarchy::plugin_runtime::providers {

PrivateStorageBackend::PrivateStorageBackend(
    int directory_fd, std::uint64_t maximum_total_bytes,
    std::uint64_t maximum_item_bytes) noexcept
    : maximum_total_bytes_(maximum_total_bytes),
      maximum_item_bytes_(maximum_item_bytes) {
  if (directory_fd < 0 || maximum_item_bytes == 0 ||
      maximum_item_bytes > maximum_total_bytes)
    return;
  directory_fd_ = fcntl(directory_fd, F_DUPFD_CLOEXEC, 3);
}

PrivateStorageBackend::~PrivateStorageBackend() {
  if (directory_fd_ >= 0)
    close(directory_fd_);
}

StorageBackend PrivateStorageBackend::configuration() noexcept {
  if (!valid())
    return {};
  return {.read = read,
          .write = write,
          .remove = remove,
          .context = this,
          .maximum_total_bytes = maximum_total_bytes_,
          .maximum_item_bytes = maximum_item_bytes_};
}

bool PrivateStorageBackend::read(std::string_view key,
                                 std::span<std::byte> output,
                                 std::size_t &written, bool &found,
                                 void *context) noexcept {
  auto &self = *static_cast<PrivateStorageBackend *>(context);
  written = 0;
  found = false;
  if (!valid_storage_key(key))
    return false;
  const std::string name(key);
  const int fd = openat(self.directory_fd_, name.c_str(),
                        O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
  if (fd < 0)
    return errno == ENOENT;
  struct stat info {};
  if (fstat(fd, &info) != 0 || !S_ISREG(info.st_mode) || info.st_nlink != 1 ||
      info.st_size < 0 || static_cast<std::uint64_t>(info.st_size) >
                              self.maximum_item_bytes_ ||
      static_cast<std::uint64_t>(info.st_size) > output.size()) {
    close(fd);
    return false;
  }
  const auto size = static_cast<std::size_t>(info.st_size);
  while (written < size) {
    const auto count = ::read(fd, output.data() + written, size - written);
    if (count <= 0) {
      close(fd);
      return false;
    }
    written += static_cast<std::size_t>(count);
  }
  const bool exact = close(fd) == 0;
  found = exact;
  return exact;
}

bool PrivateStorageBackend::within_total_limit(std::string_view replacing,
                                                std::size_t new_size) const noexcept {
  // openat(".") creates an independent directory stream offset. dup() would
  // share the offset and a second quota scan could incorrectly start at EOF.
  const int scan_fd =
      openat(directory_fd_, ".", O_RDONLY | O_DIRECTORY | O_CLOEXEC);
  if (scan_fd < 0)
    return false;
  DIR *directory = fdopendir(scan_fd);
  if (directory == nullptr) {
    close(scan_fd);
    return false;
  }
  std::uint64_t total = new_size;
  bool ok = true;
  while (const auto *entry = readdir(directory)) {
    const std::string_view name(entry->d_name);
    if (name == "." || name == ".." || name == replacing ||
        name.starts_with(".omarchy-tmp-"))
      continue;
    struct stat info {};
    if (fstatat(directory_fd_, entry->d_name, &info,
                AT_SYMLINK_NOFOLLOW) != 0 ||
        !S_ISREG(info.st_mode) || info.st_nlink != 1 || info.st_size < 0) {
      ok = false;
      break;
    }
    const auto size = static_cast<std::uint64_t>(info.st_size);
    if (size > maximum_total_bytes_ || total > maximum_total_bytes_ - size) {
      ok = false;
      break;
    }
    total += size;
  }
  closedir(directory);
  return ok && total <= maximum_total_bytes_;
}

bool PrivateStorageBackend::write(std::string_view key,
                                  std::span<const std::byte> value,
                                  void *context) noexcept {
  auto &self = *static_cast<PrivateStorageBackend *>(context);
  if (!valid_storage_key(key) || value.size() > self.maximum_item_bytes_ ||
      !self.within_total_limit(key, value.size()))
    return false;
  const std::string destination(key);
  std::array<char, 64> temporary{};
  const int length = std::snprintf(temporary.data(), temporary.size(),
                                   ".omarchy-tmp-%ld-%llu",
                                   static_cast<long>(getpid()),
                                   static_cast<unsigned long long>(
                                       ++self.temporary_sequence_));
  if (length <= 0 || static_cast<std::size_t>(length) >= temporary.size())
    return false;
  const int fd = openat(self.directory_fd_, temporary.data(),
                        O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
                        0600);
  if (fd < 0)
    return false;
  std::size_t offset = 0;
  bool ok = true;
  while (offset < value.size()) {
    const auto count = ::write(fd, value.data() + offset, value.size() - offset);
    if (count <= 0) {
      ok = false;
      break;
    }
    offset += static_cast<std::size_t>(count);
  }
  ok = ok && fsync(fd) == 0 && close(fd) == 0;
  if (ok)
    ok = renameat(self.directory_fd_, temporary.data(), self.directory_fd_,
                  destination.c_str()) == 0 &&
         fsync(self.directory_fd_) == 0;
  if (!ok)
    unlinkat(self.directory_fd_, temporary.data(), 0);
  return ok;
}

bool PrivateStorageBackend::remove(std::string_view key,
                                   void *context) noexcept {
  auto &self = *static_cast<PrivateStorageBackend *>(context);
  if (!valid_storage_key(key))
    return false;
  const std::string name(key);
  struct stat info {};
  if (fstatat(self.directory_fd_, name.c_str(), &info, AT_SYMLINK_NOFOLLOW) !=
          0 ||
      !S_ISREG(info.st_mode) || info.st_nlink != 1)
    return false;
  return unlinkat(self.directory_fd_, name.c_str(), 0) == 0 &&
         fsync(self.directory_fd_) == 0;
}

} // namespace omarchy::plugin_runtime::providers
