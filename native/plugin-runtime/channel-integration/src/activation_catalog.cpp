#include "activation_catalog.hpp"

#include <dirent.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/file.h>
#include <unistd.h>

#include <algorithm>
#include <cerrno>
#include <new>
#include <ranges>
#include <utility>

namespace omarchy::plugin_runtime::channel {
namespace {

struct DirectoryCloser {
  void operator()(DIR *directory) const noexcept {
    if (directory != nullptr)
      ::closedir(directory);
  }
};

bool trusted_root(const struct stat &metadata, std::uint32_t trusted_uid) {
  return S_ISDIR(metadata.st_mode) && metadata.st_uid == trusted_uid &&
         (metadata.st_mode & 07777) == 0700;
}

bool stable(const struct stat &before, const struct stat &after) {
  return before.st_dev == after.st_dev && before.st_ino == after.st_ino &&
         before.st_mode == after.st_mode && before.st_uid == after.st_uid &&
         before.st_gid == after.st_gid && before.st_nlink == after.st_nlink &&
         before.st_size == after.st_size &&
         before.st_mtim.tv_sec == after.st_mtim.tv_sec &&
         before.st_mtim.tv_nsec == after.st_mtim.tv_nsec &&
         before.st_ctim.tv_sec == after.st_ctim.tv_sec &&
         before.st_ctim.tv_nsec == after.st_ctim.tv_nsec;
}

bool exact_plugin_id(std::string_view value) noexcept {
  if (value.empty() || value.size() > 128)
    return false;
  bool previous_separator = true;
  for (const unsigned char character : value) {
    const bool alphanumeric = (character >= 'a' && character <= 'z') ||
                              (character >= '0' && character <= '9');
    const bool separator =
        character == '.' || character == '-' || character == '_';
    if ((!alphanumeric && !separator) ||
        (separator && previous_separator))
      return false;
    previous_separator = separator;
  }
  return !previous_separator && value.front() >= 'a' && value.front() <= 'z';
}

} // namespace

ActivationCatalogEntry::ActivationCatalogEntry(
    std::string record_name,
    host_session::InspectedActivationRecord inspected, Epoch epoch) noexcept
    : record_name_(std::move(record_name)), inspected_(std::move(inspected)),
      epoch_(epoch) {}

bool ActivationCatalogEntry::same_epoch(
    const ActivationCatalogEntry &other) const noexcept {
  const auto &left = inspected_.record();
  const auto &right = other.inspected_.record();
  return record_name_ == other.record_name_ && epoch_ == other.epoch_ &&
         left.plugin_id == right.plugin_id &&
         left.revision_directory == right.revision_directory &&
         left.revision_sha256 == right.revision_sha256 &&
         left.state_directory == right.state_directory;
}

ActivationCatalog::ActivationCatalog(
    host_session::OwnedDescriptor activation_root,
    ActivationCatalogEntry::Epoch root_epoch,
    std::vector<ActivationCatalogEntry> entries)
    : activation_root_(std::move(activation_root)),
      root_epoch_(root_epoch),
      entries_(std::move(entries)) {}

bool ActivationCatalog::capture_epoch(
    int descriptor, ActivationCatalogEntry::Epoch &epoch) noexcept {
  struct stat metadata{};
  if (descriptor < 0 || ::fstat(descriptor, &metadata) < 0 ||
      metadata.st_size < 0)
    return false;
  epoch = epoch_from_metadata(metadata);
  return true;
}

ActivationCatalogEntry::Epoch
ActivationCatalog::epoch_from_metadata(
    const struct stat &metadata) noexcept {
  return {
      .device = static_cast<std::uint64_t>(metadata.st_dev),
      .inode = static_cast<std::uint64_t>(metadata.st_ino),
      .size = static_cast<std::uint64_t>(metadata.st_size),
      .modified_seconds = metadata.st_mtim.tv_sec,
      .modified_nanoseconds = metadata.st_mtim.tv_nsec,
      .changed_seconds = metadata.st_ctim.tv_sec,
      .changed_nanoseconds = metadata.st_ctim.tv_nsec,
      .mode = static_cast<std::uint32_t>(metadata.st_mode),
      .uid = static_cast<std::uint32_t>(metadata.st_uid),
      .gid = static_cast<std::uint32_t>(metadata.st_gid),
      .links = static_cast<std::uint64_t>(metadata.st_nlink),
  };
}

bool ActivationCatalog::unchanged() const noexcept {
  ActivationCatalogEntry::Epoch current{};
  return capture_epoch(activation_root_.get(), current) &&
         current == root_epoch_ &&
         std::ranges::all_of(entries_, [](const auto &entry) {
           return entry.currently_unchanged();
         });
}

bool ActivationCatalog::same_epoch(
    const ActivationCatalog &other) const noexcept {
  if (root_epoch_ != other.root_epoch_ ||
      entries_.size() != other.entries_.size())
    return false;
  for (std::size_t index = 0; index < entries_.size(); ++index) {
    if (!entries_[index].same_epoch(other.entries_[index]))
      return false;
  }
  return true;
}

std::unique_ptr<ActivationCatalog>
ActivationCatalog::load(int activation_root_fd, std::uint32_t trusted_uid,
                              ActivationCatalogError &error) noexcept {
  error = ActivationCatalogError::none;
  try {
    struct stat root_before{};
    if (activation_root_fd < 0 ||
        ::fstat(activation_root_fd, &root_before) < 0 ||
        !trusted_root(root_before, trusted_uid)) {
      error = ActivationCatalogError::root_untrusted;
      return {};
    }

    host_session::OwnedDescriptor root(
        ::openat(activation_root_fd, ".",
                 O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW));
    struct stat pinned_root{};
    if (!root || ::fstat(root.get(), &pinned_root) < 0 ||
        pinned_root.st_dev != root_before.st_dev ||
        pinned_root.st_ino != root_before.st_ino ||
        !trusted_root(pinned_root, trusted_uid) ||
        ::flock(root.get(), LOCK_SH) < 0) {
      error = ActivationCatalogError::root_untrusted;
      return {};
    }
    struct stat locked_root_before{};
    if (::fstat(root.get(), &locked_root_before) < 0 ||
        !trusted_root(locked_root_before, trusted_uid)) {
      error = ActivationCatalogError::root_untrusted;
      return {};
    }

    const int scan_fd = ::openat(
        root.get(), ".", O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
    if (scan_fd < 0) {
      error = ActivationCatalogError::enumeration_failed;
      return {};
    }
    std::unique_ptr<DIR, DirectoryCloser> directory(::fdopendir(scan_fd));
    if (!directory) {
      ::close(scan_fd);
      error = ActivationCatalogError::enumeration_failed;
      return {};
    }

    std::vector<ActivationCatalogEntry> entries;
    for (;;) {
      errno = 0;
      const auto *entry = ::readdir(directory.get());
      if (entry == nullptr) {
        if (errno != 0)
          error = ActivationCatalogError::enumeration_failed;
        break;
      }
      const std::string_view name(entry->d_name);
      if (name == "." || name == "..")
        continue;
      if (entries.size() == kMaximumActivationCatalogEntries) {
        error = ActivationCatalogError::bound_exceeded;
        break;
      }
      if (!exact_plugin_id(name)) {
        error = ActivationCatalogError::unexpected_entry;
        break;
      }
      struct stat entry_metadata{};
      if (::fstatat(root.get(), entry->d_name, &entry_metadata,
                    AT_SYMLINK_NOFOLLOW) < 0 ||
          !S_ISREG(entry_metadata.st_mode)) {
        error = ActivationCatalogError::unexpected_entry;
        break;
      }
      auto inspected = host_session::inspect_activation_record(root.get(), name,
                                                               trusted_uid);
      if (!inspected) {
        error = ActivationCatalogError::invalid_record;
        break;
      }
      if (std::ranges::any_of(entries, [&](const auto &candidate) {
            return candidate.plugin_id() ==
                   inspected->record().plugin_id;
          })) {
        error = ActivationCatalogError::duplicate_plugin;
        break;
      }
      if (inspected->record().plugin_id != name) {
        error = ActivationCatalogError::invalid_record;
        break;
      }
      ActivationCatalogEntry::Epoch record_epoch{};
      if (!capture_epoch(inspected->descriptor(), record_epoch)) {
        error = ActivationCatalogError::mutated;
        break;
      }
      entries.push_back(ActivationCatalogEntry(
          std::string(name), std::move(*inspected), record_epoch));
    }

    struct stat root_after{};
    if (error == ActivationCatalogError::none &&
        (::fstat(root.get(), &root_after) < 0 ||
         !stable(locked_root_before, root_after) ||
         std::ranges::any_of(entries, [](const auto &candidate) {
           return !candidate.currently_unchanged();
         })))
      error = ActivationCatalogError::mutated;

    if (::closedir(directory.release()) < 0 &&
        error == ActivationCatalogError::none)
      error = ActivationCatalogError::enumeration_failed;
    if (::flock(root.get(), LOCK_UN) < 0 &&
        error == ActivationCatalogError::none)
      error = ActivationCatalogError::enumeration_failed;
    if (error != ActivationCatalogError::none)
      return {};
    std::ranges::sort(entries, [](const auto &left, const auto &right) {
      return left.plugin_id() < right.plugin_id();
    });
    const auto root_epoch = epoch_from_metadata(locked_root_before);
    return std::unique_ptr<ActivationCatalog>(
        new ActivationCatalog(std::move(root), root_epoch,
                                    std::move(entries)));
  } catch (const std::bad_alloc &) {
    error = ActivationCatalogError::resource_exhausted;
    return {};
  } catch (...) {
    error = ActivationCatalogError::internal_failure;
    return {};
  }
}

} // namespace omarchy::plugin_runtime::channel
