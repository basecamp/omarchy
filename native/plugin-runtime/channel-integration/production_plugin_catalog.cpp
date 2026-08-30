#include "production_plugin_catalog.hpp"

#include <dirent.h>
#include <fcntl.h>
#include <sys/stat.h>
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

ProductionPluginCatalogEntry::ProductionPluginCatalogEntry(
    std::string record_name,
    host_session::InspectedActivationRecord inspected) noexcept
    : record_name_(std::move(record_name)), inspected_(std::move(inspected)) {}

ProductionPluginCatalog::ProductionPluginCatalog(
    host_session::OwnedDescriptor activation_root,
    std::vector<ProductionPluginCatalogEntry> entries)
    : activation_root_(std::move(activation_root)),
      entries_(std::move(entries)) {}

std::unique_ptr<ProductionPluginCatalog>
ProductionPluginCatalog::load(int activation_root_fd, std::uint32_t trusted_uid,
                              ProductionPluginCatalogError &error) noexcept {
  error = ProductionPluginCatalogError::none;
  try {
    struct stat root_before{};
    if (activation_root_fd < 0 ||
        ::fstat(activation_root_fd, &root_before) < 0 ||
        !trusted_root(root_before, trusted_uid)) {
      error = ProductionPluginCatalogError::root_untrusted;
      return {};
    }

    host_session::OwnedDescriptor root(
        ::openat(activation_root_fd, ".",
                 O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW));
    struct stat pinned_root{};
    if (!root || ::fstat(root.get(), &pinned_root) < 0 ||
        !stable(root_before, pinned_root)) {
      error = ProductionPluginCatalogError::root_untrusted;
      return {};
    }

    const int scan_fd = ::openat(
        root.get(), ".", O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
    if (scan_fd < 0) {
      error = ProductionPluginCatalogError::enumeration_failed;
      return {};
    }
    std::unique_ptr<DIR, DirectoryCloser> directory(::fdopendir(scan_fd));
    if (!directory) {
      ::close(scan_fd);
      error = ProductionPluginCatalogError::enumeration_failed;
      return {};
    }

    std::vector<ProductionPluginCatalogEntry> entries;
    for (;;) {
      errno = 0;
      const auto *entry = ::readdir(directory.get());
      if (entry == nullptr) {
        if (errno != 0)
          error = ProductionPluginCatalogError::enumeration_failed;
        break;
      }
      const std::string_view name(entry->d_name);
      if (name == "." || name == "..")
        continue;
      if (entries.size() == kMaximumProductionPluginCatalogEntries) {
        error = ProductionPluginCatalogError::bound_exceeded;
        break;
      }
      if (!exact_plugin_id(name)) {
        error = ProductionPluginCatalogError::unexpected_entry;
        break;
      }
      struct stat entry_metadata{};
      if (::fstatat(root.get(), entry->d_name, &entry_metadata,
                    AT_SYMLINK_NOFOLLOW) < 0 ||
          !S_ISREG(entry_metadata.st_mode)) {
        error = ProductionPluginCatalogError::unexpected_entry;
        break;
      }
      auto inspected = host_session::inspect_activation_record(root.get(), name,
                                                               trusted_uid);
      if (!inspected) {
        error = ProductionPluginCatalogError::invalid_record;
        break;
      }
      if (std::ranges::any_of(entries, [&](const auto &candidate) {
            return candidate.record().plugin_id ==
                   inspected->record().plugin_id;
          })) {
        error = ProductionPluginCatalogError::duplicate_plugin;
        break;
      }
      if (inspected->record().plugin_id != name) {
        error = ProductionPluginCatalogError::invalid_record;
        break;
      }
      entries.push_back(ProductionPluginCatalogEntry(std::string(name),
                                                     std::move(*inspected)));
    }

    struct stat root_after{};
    if (error == ProductionPluginCatalogError::none &&
        (::fstat(root.get(), &root_after) < 0 ||
         !stable(root_before, root_after) ||
         std::ranges::any_of(entries, [](const auto &candidate) {
           return !candidate.unchanged();
         })))
      error = ProductionPluginCatalogError::mutated;

    if (::closedir(directory.release()) < 0 &&
        error == ProductionPluginCatalogError::none)
      error = ProductionPluginCatalogError::enumeration_failed;
    if (error != ProductionPluginCatalogError::none)
      return {};
    std::ranges::sort(entries, [](const auto &left, const auto &right) {
      return left.record_name() < right.record_name();
    });
    return std::unique_ptr<ProductionPluginCatalog>(
        new ProductionPluginCatalog(std::move(root), std::move(entries)));
  } catch (const std::bad_alloc &) {
    error = ProductionPluginCatalogError::resource_exhausted;
    return {};
  } catch (...) {
    error = ProductionPluginCatalogError::internal_failure;
    return {};
  }
}

} // namespace omarchy::plugin_runtime::channel
