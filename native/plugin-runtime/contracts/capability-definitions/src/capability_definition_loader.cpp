#include "capability_definition_loader.hpp"

#include <algorithm>
#include <cerrno>
#include <charconv>
#include <dirent.h>
#include <fcntl.h>
#include <string>
#include <sys/stat.h>
#include <unistd.h>

namespace omarchy::plugins::definitions {
namespace {

constexpr std::size_t kMaximumDocumentBytes = 16384;

std::string_view enum_name(EnforcementFamily value) {
  switch (value) {
  case EnforcementFamily::network_fetch: return "network-fetch";
  case EnforcementFamily::external_open_uri: return "external-open-uri";
  case EnforcementFamily::system_observe: return "system-observe";
  case EnforcementFamily::device_observe: return "device-observe";
  case EnforcementFamily::device_control: return "device-control";
  case EnforcementFamily::media_play_stream: return "media-play-stream";
  case EnforcementFamily::remote_account_read: return "remote-account-read";
  case EnforcementFamily::remote_account_write: return "remote-account-write";
  case EnforcementFamily::cli_harness: return "cli-harness";
  }
  return {};
}

std::string_view enum_name(ScopeSchema value) {
  switch (value) {
  case ScopeSchema::https_origins_and_methods: return "https-origins-methods";
  case ScopeSchema::https_origins_after_gesture: return "https-origins-gesture";
  case ScopeSchema::named_sanitized_datasets: return "named-sanitized-datasets";
  case ScopeSchema::selected_device_fields: return "selected-device-fields";
  case ScopeSchema::selected_device_controls: return "selected-device-controls";
  case ScopeSchema::selected_remote_account: return "selected-remote-account";
  case ScopeSchema::activation_source_handles_and_controls:
    return "activation-source-handles-controls";
  case ScopeSchema::exact_cli_profile: return "exact-cli-profile";
  }
  return {};
}

template <typename Enum, std::size_t Size>
bool parse_enum(std::string_view input,
                const std::array<std::pair<std::string_view, Enum>, Size> &map,
                Enum &output) {
  const auto found = std::find_if(map.begin(), map.end(), [input](const auto &item) {
    return item.first == input;
  });
  if (found == map.end())
    return false;
  output = found->second;
  return true;
}

bool next_line(std::string_view document, std::size_t &offset,
               std::string_view expected, std::string_view &value) {
  if (offset >= document.size())
    return false;
  const auto end = document.find('\n', offset);
  if (end == std::string_view::npos)
    return false;
  const auto line = document.substr(offset, end - offset);
  offset = end + 1;
  const auto prefix = std::string(expected) + "=";
  if (!line.starts_with(prefix) || line.size() == prefix.size())
    return false;
  value = line.substr(prefix.size());
  return value.find('\r') == std::string_view::npos;
}

template <typename Integer>
bool number(std::string_view input, Integer &output) {
  const auto [end, error] =
      std::from_chars(input.data(), input.data() + input.size(), output);
  return error == std::errc{} && end == input.data() + input.size();
}

bool trusted_stat(const struct stat &status, std::uint32_t expected_uid,
                  bool directory) {
  return static_cast<std::uint32_t>(status.st_uid) == expected_uid &&
         (status.st_mode & 07777) == (directory ? 0755 : 0644) &&
         (directory ? S_ISDIR(status.st_mode)
                    : S_ISREG(status.st_mode) && status.st_nlink == 1);
}

bool stable_stat(const struct stat &before, const struct stat &after) {
  return before.st_dev == after.st_dev && before.st_ino == after.st_ino &&
         before.st_mode == after.st_mode && before.st_uid == after.st_uid &&
         before.st_gid == after.st_gid && before.st_nlink == after.st_nlink &&
         before.st_size == after.st_size &&
         before.st_mtim.tv_sec == after.st_mtim.tv_sec &&
         before.st_mtim.tv_nsec == after.st_mtim.tv_nsec &&
         before.st_ctim.tv_sec == after.st_ctim.tv_sec &&
         before.st_ctim.tv_nsec == after.st_ctim.tv_nsec;
}

} // namespace

std::string canonical_definition_document(const CapabilityDefinition &definition,
                                          std::uint32_t generation) {
  if (!valid_definition(definition) || generation == 0)
    return {};
  std::string output;
  const auto line = [&output](std::string_view key, std::string_view value) {
    output.append(key).push_back('=');
    output.append(value).push_back('\n');
  };
  line("format", "omarchy-capability-v1");
  line("generation", std::to_string(generation));
  line("canonical-name", definition.canonical_name.view());
  line("authority-identity", definition.authority_identity.view());
  line("enforcement-family", enum_name(definition.enforcement_family));
  line("display-category-id", definition.display_category_id.view());
  line("display-category-label", definition.display_category_label.view());
  line("scope-schema", enum_name(definition.scope_schema));
  line("title", definition.title.view());
  line("risk-text", definition.risk_text.view());
  line("risk", std::to_string(static_cast<unsigned>(definition.risk)));
  line("revocation", std::to_string(static_cast<unsigned>(definition.revocation)));
  line("audit", "decision,duration,bytes,redact-payload,redact-uri,redact-tokens");
  line("adapter-class", definition.adapter.adapter_class.view());
  line("contract-digest", definition.adapter.contract_digest.view());
  line("adapter-abi", std::to_string(definition.adapter.abi_version));
  for (const auto &operation : definition.operations.values()) {
    std::string value(operation.name.view());
    value.push_back('|');
    value.append(operation.label.view());
    value.push_back('|');
    value.push_back(operation.mutating ? '1' : '0');
    value.push_back('|');
    value.push_back(operation.requires_fresh_gesture ? '1' : '0');
    line("operation", value);
  }
  line("definition-digest", definition_digest(definition).view());
  return output.size() <= kMaximumDocumentBytes ? output : std::string{};
}

LoadResult parse_definition_document(std::string_view document,
                                     DefinitionSource source,
                                     LoadedDefinition &output) {
  output = {};
  if (document.empty() || document.size() > kMaximumDocumentBytes)
    return LoadResult::invalid_document;
  std::size_t offset = 0;
  std::string_view value;
  CapabilityDefinition definition;
  std::uint32_t generation = 0;
  unsigned enumeration = 0;
  try {
    if (!next_line(document, offset, "format", value) ||
        value != "omarchy-capability-v1" ||
        !next_line(document, offset, "generation", value) ||
        !number(value, generation) || generation == 0 ||
        !next_line(document, offset, "canonical-name", value))
      return LoadResult::invalid_document;
    definition.canonical_name = Name(value);
    if (!next_line(document, offset, "authority-identity", value))
      return LoadResult::invalid_document;
    definition.authority_identity = Name(value);
    static constexpr std::array categories{
        std::pair{std::string_view("network-fetch"), EnforcementFamily::network_fetch},
        std::pair{std::string_view("external-open-uri"), EnforcementFamily::external_open_uri},
        std::pair{std::string_view("system-observe"), EnforcementFamily::system_observe},
        std::pair{std::string_view("device-observe"), EnforcementFamily::device_observe},
        std::pair{std::string_view("device-control"), EnforcementFamily::device_control},
        std::pair{std::string_view("media-play-stream"), EnforcementFamily::media_play_stream},
        std::pair{std::string_view("remote-account-read"), EnforcementFamily::remote_account_read},
        std::pair{std::string_view("remote-account-write"), EnforcementFamily::remote_account_write},
        std::pair{std::string_view("cli-harness"), EnforcementFamily::cli_harness}};
    if (!next_line(document, offset, "enforcement-family", value) ||
        !parse_enum(value, categories, definition.enforcement_family) ||
        !next_line(document, offset, "display-category-id", value))
      return LoadResult::invalid_document;
    definition.display_category_id = Name(value);
    if (!next_line(document, offset, "display-category-label", value))
      return LoadResult::invalid_document;
    definition.display_category_label = Label(value);
    static constexpr std::array scopes{
        std::pair{std::string_view("https-origins-methods"), ScopeSchema::https_origins_and_methods},
        std::pair{std::string_view("https-origins-gesture"), ScopeSchema::https_origins_after_gesture},
        std::pair{std::string_view("named-sanitized-datasets"), ScopeSchema::named_sanitized_datasets},
        std::pair{std::string_view("selected-device-fields"), ScopeSchema::selected_device_fields},
        std::pair{std::string_view("selected-device-controls"), ScopeSchema::selected_device_controls},
        std::pair{std::string_view("selected-remote-account"), ScopeSchema::selected_remote_account},
        std::pair{std::string_view("activation-source-handles-controls"),
                  ScopeSchema::activation_source_handles_and_controls},
        std::pair{std::string_view("exact-cli-profile"), ScopeSchema::exact_cli_profile}};
    if (!next_line(document, offset, "scope-schema", value) ||
        !parse_enum(value, scopes, definition.scope_schema) ||
        !next_line(document, offset, "title", value))
      return LoadResult::invalid_document;
    definition.title = Label(value);
    if (!next_line(document, offset, "risk-text", value))
      return LoadResult::invalid_document;
    definition.risk_text = Label(value);
    if (!next_line(document, offset, "risk", value) || !number(value, enumeration) ||
        enumeration > static_cast<unsigned>(RiskLevel::critical))
      return LoadResult::invalid_document;
    definition.risk = static_cast<RiskLevel>(enumeration);
    if (!next_line(document, offset, "revocation", value) ||
        !number(value, enumeration) ||
        enumeration > static_cast<unsigned>(RevocationPolicy::restart_worker))
      return LoadResult::invalid_document;
    definition.revocation = static_cast<RevocationPolicy>(enumeration);
    if (!next_line(document, offset, "audit", value) ||
        value != "decision,duration,bytes,redact-payload,redact-uri,redact-tokens" ||
        !next_line(document, offset, "adapter-class", value))
      return LoadResult::invalid_document;
    definition.adapter.adapter_class = Name(value);
    if (!next_line(document, offset, "contract-digest", value))
      return LoadResult::invalid_document;
    definition.adapter.contract_digest = Digest(value);
    if (!next_line(document, offset, "adapter-abi", value) ||
        !number(value, definition.adapter.abi_version))
      return LoadResult::invalid_document;
    while (document.substr(offset).starts_with("operation=")) {
      if (!next_line(document, offset, "operation", value))
        return LoadResult::invalid_document;
      const auto first = value.find('|');
      const auto second = value.find('|', first + 1);
      const auto third = value.find('|', second + 1);
      if (first == std::string_view::npos || second == std::string_view::npos ||
          third == std::string_view::npos || value.substr(second + 1, third - second - 1).size() != 1 ||
          value.substr(third + 1).size() != 1)
        return LoadResult::invalid_document;
      OperationDefinition operation{.name = Name(value.substr(0, first)),
                                    .label = Label(value.substr(first + 1, second - first - 1)),
                                    .mutating = value[second + 1] == '1',
                                    .requires_fresh_gesture = value[third + 1] == '1'};
      if ((value[second + 1] != '0' && value[second + 1] != '1') ||
          (value[third + 1] != '0' && value[third + 1] != '1') ||
          !definition.operations.insert(operation))
        return LoadResult::invalid_document;
    }
    if (!next_line(document, offset, "definition-digest", value) ||
        offset != document.size() || !valid_definition(definition) ||
        Digest(value) != definition_digest(definition))
      return LoadResult::invalid_document;
  } catch (const std::runtime_error &) {
    return LoadResult::invalid_document;
  }
  output = {.definition = definition,
            .source = source,
            .generation = generation,
            .digest = definition_digest(definition)};
  return LoadResult::loaded;
}

LoadResult load_definition_directory_fd(
    int directory_fd, DefinitionSource source, std::uint32_t expected_uid,
    TrustedDefinitionRegistry &registry, std::size_t &loaded_count) {
  loaded_count = 0;
  struct stat directory_before {};
  if (directory_fd < 0 || fstat(directory_fd, &directory_before) != 0 ||
      !trusted_stat(directory_before, expected_uid, true))
    return LoadResult::untrusted_path;

  const int scan_fd = openat(directory_fd, ".",
                             O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
  if (scan_fd < 0)
    return LoadResult::untrusted_path;
  struct stat scan_status {};
  if (fstat(scan_fd, &scan_status) != 0 ||
      !stable_stat(directory_before, scan_status)) {
    close(scan_fd);
    return LoadResult::untrusted_path;
  }
  DIR *directory = fdopendir(scan_fd);
  if (directory == nullptr) {
    close(scan_fd);
    return LoadResult::untrusted_path;
  }
  const int pinned_directory_fd = dirfd(directory);
  LoadResult result = LoadResult::loaded;
  auto candidate_registry = registry;
  for (;;) {
    errno = 0;
    const auto *entry = readdir(directory);
    if (entry == nullptr) {
      if (errno != 0)
        result = LoadResult::untrusted_path;
      break;
    }
    const std::string_view name(entry->d_name);
    if (name == "." || name == "..")
      continue;
    if (!name.ends_with(".capability") || ++loaded_count > 128) {
      result = LoadResult::bound_exceeded;
      break;
    }
    const int file_fd = openat(pinned_directory_fd, entry->d_name,
                               O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK);
    struct stat before {};
    if (file_fd < 0 || fstat(file_fd, &before) != 0 ||
        !trusted_stat(before, expected_uid, false) || before.st_size <= 0 ||
        before.st_size > static_cast<off_t>(kMaximumDocumentBytes)) {
      if (file_fd >= 0) close(file_fd);
      result = LoadResult::untrusted_path;
      break;
    }
    std::string document(static_cast<std::size_t>(before.st_size), '\0');
    std::size_t offset = 0;
    while (offset < document.size()) {
      const auto bytes = read(file_fd, document.data() + offset,
                              document.size() - offset);
      if (bytes < 0 && errno == EINTR)
        continue;
      if (bytes <= 0)
        break;
      offset += static_cast<std::size_t>(bytes);
    }
    struct stat after {};
    const bool stable = offset == document.size() &&
                        fstat(file_fd, &after) == 0 &&
                        stable_stat(before, after);
    close(file_fd);
    if (!stable) {
      result = LoadResult::untrusted_path;
      break;
    }
    LoadedDefinition loaded;
    result = parse_definition_document(document, source, loaded);
    if (result != LoadResult::loaded)
      break;
    if (!candidate_registry.install(loaded.definition, loaded.source,
                                    loaded.generation)) {
      result = LoadResult::registry_rejected;
      break;
    }
  }
  struct stat directory_after {};
  if (result == LoadResult::loaded &&
      (fstat(pinned_directory_fd, &directory_after) != 0 ||
       !stable_stat(directory_before, directory_after)))
    result = LoadResult::untrusted_path;
  closedir(directory);
  if (result != LoadResult::loaded)
    loaded_count = 0;
  else
    registry = candidate_registry;
  return result;
}

} // namespace omarchy::plugins::definitions
