#include "discovery.hpp"

#include <algorithm>
#include <cctype>
#include <fstream>
#include <iterator>
#include <map>
#include <set>
#include <stdexcept>
#include <string_view>

namespace omarchy::plugins::discovery {
namespace {

constexpr std::size_t kMaximumManifestBytes = 1024 * 1024;

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
  std::error_code error;
  const auto status = std::filesystem::symlink_status(path, error);
  if (error || status.type() != std::filesystem::file_type::regular) {
    return std::nullopt;
  }
  const auto size = std::filesystem::file_size(path, error);
  if (error || size > kMaximumManifestBytes) {
    return std::nullopt;
  }
  std::ifstream input(path, std::ios::binary);
  if (!input) {
    return std::nullopt;
  }
  std::string bytes;
  bytes.reserve(static_cast<std::size_t>(size));
  bytes.assign(std::istreambuf_iterator<char>(input),
               std::istreambuf_iterator<char>());
  if (input.bad() || bytes.size() != size) {
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
