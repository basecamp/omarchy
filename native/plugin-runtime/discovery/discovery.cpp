#include "discovery.hpp"

#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

#include <dirent.h>

#include <algorithm>
#include <array>
#include <cctype>
#include <cerrno>
#include <map>
#include <set>
#include <stdexcept>
#include <string_view>
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
                         std::size_t &entry_count, std::size_t depth) {
  require(depth <= kMaximumTraversalDepth, "plugin tree traversal is too deep");
  Descriptor pinned(::openat(directory_fd, ".",
                             O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW));
  require(pinned.get() >= 0, "cannot pin plugin directory");
  struct stat directory_metadata{};
  require(::fstat(pinned.get(), &directory_metadata) == 0 &&
              S_ISDIR(directory_metadata.st_mode),
          "cannot inspect plugin directory");
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
                          entry_count, depth + 1);
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
    contents.add(
        {.relative = relative,
         .bytes =
             read_open_file(file.get(), contents.remaining_bytes(), opened),
         .executable = (opened.st_mode & (S_IXUSR | S_IXGRP | S_IXOTH)) != 0});
    files.push_back({.descriptor = std::move(file), .metadata = opened});
  }
  require(errno == 0, "cannot enumerate plugin directory");
}

bool valid_digest(std::string_view value) {
  return value.size() == 64 &&
         std::ranges::all_of(value, [](unsigned char byte) {
           return (byte >= '0' && byte <= '9') || (byte >= 'a' && byte <= 'f');
         });
}

bool valid_directory_name(std::string_view value) {
  return !value.empty() && value != "." && value != ".." &&
         value.find('/') == std::string_view::npos &&
         value.find('\\') == std::string_view::npos &&
         value.find('\0') == std::string_view::npos;
}

std::optional<std::string> read_manifest(const std::filesystem::path &path) {
  const int descriptor =
      ::open(path.c_str(), O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK);
  if (descriptor < 0) {
    return std::nullopt;
  }
  struct Descriptor {
    int value;
    ~Descriptor() { ::close(value); }
  } owned{descriptor};
  struct stat metadata{};
  if (::fstat(owned.value, &metadata) < 0 || !S_ISREG(metadata.st_mode) ||
      metadata.st_size < 0 ||
      static_cast<std::uint64_t>(metadata.st_size) > kMaximumManifestBytes) {
    return std::nullopt;
  }

  std::string bytes;
  bytes.reserve(static_cast<std::size_t>(metadata.st_size));
  std::array<char, 8192> chunk{};
  for (;;) {
    const ssize_t count = ::read(owned.value, chunk.data(), chunk.size());
    if (count < 0 && errno == EINTR) {
      continue;
    }
    if (count < 0) {
      return std::nullopt;
    }
    if (count == 0) {
      break;
    }
    const auto amount = static_cast<std::size_t>(count);
    if (amount > kMaximumManifestBytes - bytes.size()) {
      return std::nullopt;
    }
    bytes.append(chunk.data(), amount);
  }
  if (bytes.size() != static_cast<std::size_t>(metadata.st_size)) {
    return std::nullopt;
  }
  return bytes;
}

bool legacy_v1_marker(std::string_view bytes) {
  constexpr std::string_view key = "\"schemaVersion\"";
  const auto first = bytes.find(key);
  if (first == std::string_view::npos ||
      bytes.find(key, first + key.size()) != std::string_view::npos) {
    return false;
  }
  auto position = first + key.size();
  while (position < bytes.size() &&
         std::isspace(static_cast<unsigned char>(bytes[position])) != 0) {
    ++position;
  }
  if (position == bytes.size() || bytes[position++] != ':') {
    return false;
  }
  while (position < bytes.size() &&
         std::isspace(static_cast<unsigned char>(bytes[position])) != 0) {
    ++position;
  }
  if (position == bytes.size() || bytes[position++] != '1') {
    return false;
  }
  return position == bytes.size() || bytes[position] == ',' ||
         bytes[position] == '}' ||
         std::isspace(static_cast<unsigned char>(bytes[position])) != 0;
}

void add(DiscoveryReport &report, DiagnosticCode code, std::string directory,
         std::string detail) {
  report.diagnostics.push_back({.code = code,
                                .directory = std::move(directory),
                                .detail = std::move(detail)});
}

} // namespace

DescriptorVerifiedPlugin discover_open_revision(int revision_directory_fd) {
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
                      entry_count, 0);
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

DiscoveryReport discover(const std::filesystem::path &root,
                         std::span<const IdentityPin> pins,
                         DiscoveryOptions options) {
  DiscoveryReport report;
  if (pins.size() > kMaximumDiscoveredPlugins) {
    add(report, DiagnosticCode::traversal_limit, "",
        "identity pin limit exceeded");
    return report;
  }
  std::error_code error;
  const auto root_status = std::filesystem::symlink_status(root, error);
  if (error || root_status.type() == std::filesystem::file_type::not_found) {
    add(report, DiagnosticCode::root_unavailable, "", "root unavailable");
    return report;
  }
  if (root_status.type() != std::filesystem::file_type::directory) {
    add(report,
        root_status.type() == std::filesystem::file_type::symlink
            ? DiagnosticCode::symlink_rejected
            : DiagnosticCode::root_not_directory,
        "", "root must be a real directory");
    return report;
  }

  std::map<std::string, std::vector<const IdentityPin *>> pins_by_directory;
  std::map<std::string, std::size_t> pin_name_counts;
  for (const auto &pin : pins) {
    ++pin_name_counts[pin.directory];
  }
  for (const auto &pin : pins) {
    if (!valid_directory_name(pin.directory) ||
        !valid_digest(pin.tree_sha256)) {
      add(report, DiagnosticCode::identity_pin_invalid, pin.directory,
          "pin must contain one directory component and lowercase sha256");
      continue;
    }
    pins_by_directory[pin.directory].push_back(&pin);
  }

  std::vector<std::filesystem::directory_entry> entries;
  std::filesystem::directory_iterator iterator(root, error);
  const std::filesystem::directory_iterator end;
  while (!error && iterator != end) {
    if (entries.size() == kMaximumDiscoveredPlugins) {
      add(report, DiagnosticCode::traversal_limit, "",
          "plugin directory entry limit exceeded");
      return report;
    }
    entries.push_back(*iterator);
    iterator.increment(error);
  }
  if (error) {
    add(report, DiagnosticCode::root_unavailable, "",
        "plugin root enumeration failed");
    return report;
  }
  std::ranges::sort(entries, [](const auto &left, const auto &right) {
    return left.path().filename().string() < right.path().filename().string();
  });

  std::set<std::string> entry_names;
  for (const auto &entry : entries) {
    entry_names.insert(entry.path().filename().string());
  }
  for (const auto &[directory, pin_list] : pins_by_directory) {
    if (pin_list.size() == 1 && !entry_names.contains(directory)) {
      add(report, DiagnosticCode::registered_directory_missing, directory,
          "identity pin names a missing plugin directory");
    }
  }

  for (const auto &entry : entries) {
    const auto directory = entry.path().filename().string();
    const auto pin_match = pins_by_directory.find(directory);
    if (pin_name_counts[directory] > 1) {
      add(report, DiagnosticCode::duplicate_registration, directory,
          "multiple identity pins name this directory");
      continue;
    }
    const auto status = entry.symlink_status(error);
    if (error || status.type() == std::filesystem::file_type::symlink) {
      error.clear();
      add(report, DiagnosticCode::symlink_rejected, directory,
          "plugin entry must not be a symlink");
      continue;
    }
    if (status.type() != std::filesystem::file_type::directory) {
      add(report, DiagnosticCode::unexpected_entry, directory,
          "plugin entry must be a directory");
      continue;
    }
    const auto manifest_path = entry.path() / "manifest.json";
    const auto manifest_status =
        std::filesystem::symlink_status(manifest_path, error);
    if (!error &&
        manifest_status.type() == std::filesystem::file_type::regular) {
      const auto manifest_size =
          std::filesystem::file_size(manifest_path, error);
      if (!error && manifest_size > kMaximumManifestBytes) {
        add(report, DiagnosticCode::manifest_too_large, directory,
            "manifest.json exceeds the one MiB limit");
        continue;
      }
    }
    error.clear();
    const auto bytes = read_manifest(manifest_path);
    if (!bytes) {
      add(report, DiagnosticCode::manifest_missing, directory,
          "bounded regular manifest.json required");
      continue;
    }

    manifest::ManifestV2 parsed;
    try {
      parsed = manifest::parse_manifest_v2(*bytes);
    } catch (const std::exception &exception) {
      if (legacy_v1_marker(*bytes)) {
        add(report, DiagnosticCode::legacy_v1_unsafe, directory,
            "schema v1 is arbitrary in-process code and is never secure");
      } else {
        add(report, DiagnosticCode::invalid_manifest, directory,
            exception.what());
      }
      continue;
    }
    if (!options.schema_v2_enabled) {
      add(report, DiagnosticCode::schema_v2_feature_disabled, directory,
          "schema v2 discovery feature is disabled");
      continue;
    }
    if (pin_match == pins_by_directory.end()) {
      add(report, DiagnosticCode::identity_pin_missing, directory,
          "schema v2 plugin has no trusted immutable identity pin");
      continue;
    }

    manifest::ContentIdentity identity;
    try {
      identity = manifest::identify_tree(entry.path(), parsed);
    } catch (const std::exception &exception) {
      add(report, DiagnosticCode::tree_verification_failed, directory,
          exception.what());
      continue;
    }
    if (identity.tree_sha256 != pin_match->second.front()->tree_sha256) {
      add(report, DiagnosticCode::identity_mismatch, directory,
          "tree sha256 does not match trusted pin");
      continue;
    }
    report.plugins.push_back({.root = entry.path(),
                              .manifest = std::move(parsed),
                              .identity = std::move(identity)});
  }

  std::map<std::string, std::size_t> id_counts;
  for (const auto &plugin : report.plugins) {
    ++id_counts[plugin.manifest.id];
  }
  for (const auto &plugin : report.plugins) {
    if (id_counts[plugin.manifest.id] > 1) {
      add(report, DiagnosticCode::duplicate_plugin_id,
          plugin.root.filename().string(),
          "multiple verified trees claim the same plugin id");
    }
  }
  std::erase_if(report.plugins, [&](const VerifiedPlugin &plugin) {
    return id_counts[plugin.manifest.id] > 1;
  });
  std::ranges::sort(report.diagnostics,
                    [](const Diagnostic &left, const Diagnostic &right) {
                      if (left.directory != right.directory) {
                        return left.directory < right.directory;
                      }
                      return left.code < right.code;
                    });
  return report;
}

} // namespace omarchy::plugins::discovery
