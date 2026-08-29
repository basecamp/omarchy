#include "provider_registration.hpp"

#include <algorithm>
#include <charconv>
#include <dirent.h>
#include <fcntl.h>
#include <fstream>
#include <sys/stat.h>
#include <tuple>
#include <unistd.h>

namespace omarchy::plugins::external_provider {
namespace {
constexpr std::size_t kMaximumDocumentBytes = 4096;
bool line(std::string_view input, std::size_t &offset, std::string_view key,
          std::string_view &value) {
  const auto end = input.find('\n', offset);
  if (end == std::string_view::npos)
    return false;
  const std::string prefix = std::string(key) + "=";
  const auto current = input.substr(offset, end - offset);
  offset = end + 1;
  if (!current.starts_with(prefix) || current.size() == prefix.size())
    return false;
  value = current.substr(prefix.size());
  return value.find_first_of("\r\0") == std::string_view::npos;
}
template <typename T> bool number(std::string_view input, T &output) {
  const auto [end, error] =
      std::from_chars(input.data(), input.data() + input.size(), output);
  return error == std::errc{} && end == input.data() + input.size();
}
bool trusted(const struct stat &status, std::uint32_t uid, bool directory) {
  return status.st_uid == uid && (status.st_mode & (S_IWGRP | S_IWOTH)) == 0 &&
         (directory ? S_ISDIR(status.st_mode) : S_ISREG(status.st_mode));
}
bool same(const Registration &left, const Registration &right) {
  return left.service_id == right.service_id && left.adapter == right.adapter &&
         left.executable == right.executable &&
         left.executable_digest == right.executable_digest &&
         left.expected_uid == right.expected_uid &&
         left.protocol_version == right.protocol_version;
}
bool verify_revision(const std::filesystem::path &path,
                     const grants::RevisionGrants &revision) {
  try {
    std::ifstream input(path / "manifest.json", std::ios::binary);
    if (!input)
      return false;
    const std::string bytes((std::istreambuf_iterator<char>(input)), {});
    const auto parsed = manifest::parse_manifest_v2(bytes);
    const auto identity = manifest::identify_tree(path, parsed);
    return parsed.id == revision.binding.plugin.view() &&
           identity.tree_sha256 == revision.binding.revision.view() &&
           identity.request_sha256 ==
               revision.source_request_fingerprint.view();
  } catch (...) {
    return false;
  }
}
std::string dependency_document(const DependencyIndex &index) {
  std::string output = "OMARCHY-PROVIDER-DEPENDENCIES-V1\nmutation=" +
                       std::to_string(index.grant_mutation_sequence) + "\n";
  for (const auto &dependency : index.dependencies) {
    output.append("dependency=")
        .append(dependency.plugin.view())
        .append("|")
        .append(dependency.revision.view())
        .append("|")
        .append(dependency.adapter.adapter_class.view())
        .append("|")
        .append(dependency.adapter.implementation_digest.view())
        .append("|")
        .append(std::to_string(dependency.adapter.abi_version))
        .append("\n");
  }
  return output;
}
void collect(RegistrationChangeAssessment &result,
             const definitions::AdapterBinding &adapter,
             std::span<const ProviderDependency> dependencies) {
  for (const auto &dependency : dependencies)
    if (dependency.adapter == adapter)
      result.dependents.push_back(dependency);
}
bool dispatch_external(const definitions::AuthorizedDynamicRequest &request,
                       std::span<std::byte> response, std::size_t &written,
                       void *context) noexcept {
  written = 0;
  if (context == nullptr)
    return false;
  try {
    auto &registration = *static_cast<Registration *>(context);
    return invoke(registration, request, response, written,
                  std::chrono::seconds(30),
                  request.authorization.grant_epoch) == Result::completed;
  } catch (...) {
    written = 0;
    return false;
  }
}
} // namespace

std::string canonical_registration_document(const Registration &registration) {
  if (!valid_registration(registration))
    return {};
  std::string output;
  const auto append = [&](std::string_view key, std::string_view value) {
    output.append(key).append("=").append(value).append("\n");
  };
  append("format", "omarchy-provider-v1");
  append("service-id", registration.service_id.view());
  append("adapter-class", registration.adapter.adapter_class.view());
  append("adapter-digest", registration.adapter.implementation_digest.view());
  append("adapter-abi", std::to_string(registration.adapter.abi_version));
  append("executable", registration.executable.string());
  append("executable-digest", registration.executable_digest.view());
  append("expected-uid", std::to_string(registration.expected_uid));
  append("protocol", std::to_string(registration.protocol_version));
  return output.size() <= kMaximumDocumentBytes ? output : std::string{};
}

RegistrationLoadResult parse_registration_document(
    std::string_view document, std::uint32_t expected_uid,
    Registration &registration) {
  registration = {};
  if (document.empty() || document.size() > kMaximumDocumentBytes)
    return RegistrationLoadResult::invalid_document;
  std::size_t offset = 0;
  std::string_view value;
  std::uint32_t uid = 0;
  try {
    if (!line(document, offset, "format", value) ||
        value != "omarchy-provider-v1" ||
        !line(document, offset, "service-id", value))
      return RegistrationLoadResult::invalid_document;
    registration.service_id = definitions::Name(value);
    if (!line(document, offset, "adapter-class", value))
      return RegistrationLoadResult::invalid_document;
    registration.adapter.adapter_class = definitions::Name(value);
    if (!line(document, offset, "adapter-digest", value))
      return RegistrationLoadResult::invalid_document;
    registration.adapter.implementation_digest = Digest(value);
    if (!line(document, offset, "adapter-abi", value) ||
        !number(value, registration.adapter.abi_version) ||
        !line(document, offset, "executable", value))
      return RegistrationLoadResult::invalid_document;
    registration.executable = std::filesystem::path(value);
    if (!line(document, offset, "executable-digest", value))
      return RegistrationLoadResult::invalid_document;
    registration.executable_digest = Digest(value);
    if (!line(document, offset, "expected-uid", value) ||
        !number(value, uid) || uid != expected_uid ||
        !line(document, offset, "protocol", value) ||
        !number(value, registration.protocol_version) ||
        offset != document.size())
      return RegistrationLoadResult::invalid_document;
    registration.expected_uid = uid;
  } catch (const std::runtime_error &) {
    return RegistrationLoadResult::invalid_document;
  }
  return valid_registration(registration)
             ? RegistrationLoadResult::loaded
             : RegistrationLoadResult::invalid_provider;
}

RegistrationLoadResult load_registration_directory(
    std::string_view path, std::uint32_t expected_uid,
    std::vector<Registration> &registrations) {
  registrations.clear();
  const std::string owned(path);
  const int root = open(owned.c_str(), O_RDONLY | O_DIRECTORY | O_CLOEXEC |
                                           O_NOFOLLOW);
  struct stat root_status {};
  if (root < 0 || fstat(root, &root_status) < 0 ||
      !trusted(root_status, expected_uid, true)) {
    if (root >= 0)
      close(root);
    return RegistrationLoadResult::untrusted_path;
  }
  DIR *directory = fdopendir(dup(root));
  if (directory == nullptr) {
    close(root);
    return RegistrationLoadResult::untrusted_path;
  }
  RegistrationLoadResult result = RegistrationLoadResult::loaded;
  while (const dirent *entry = readdir(directory)) {
    const std::string_view name(entry->d_name);
    if (name == "." || name == "..")
      continue;
    if (!name.ends_with(".provider") || registrations.size() == 64) {
      result = RegistrationLoadResult::bound_exceeded;
      break;
    }
    const int fd = openat(root, entry->d_name,
                          O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK);
    struct stat status {};
    if (fd < 0 || fstat(fd, &status) < 0 ||
        !trusted(status, expected_uid, false) || status.st_size <= 0 ||
        static_cast<std::size_t>(status.st_size) > kMaximumDocumentBytes) {
      if (fd >= 0)
        close(fd);
      result = RegistrationLoadResult::untrusted_path;
      break;
    }
    std::string document(static_cast<std::size_t>(status.st_size), '\0');
    std::size_t read_bytes = 0;
    while (read_bytes < document.size()) {
      const ssize_t count =
          read(fd, document.data() + read_bytes, document.size() - read_bytes);
      if (count < 0 && errno == EINTR)
        continue;
      if (count <= 0)
        break;
      read_bytes += static_cast<std::size_t>(count);
    }
    close(fd);
    if (read_bytes != document.size()) {
      result = RegistrationLoadResult::invalid_document;
      break;
    }
    Registration registration;
    result = parse_registration_document(document, expected_uid, registration);
    if (result != RegistrationLoadResult::loaded)
      break;
    if (name != std::string(registration.service_id.view()) + ".provider") {
      result = RegistrationLoadResult::invalid_document;
      break;
    }
    if (std::ranges::any_of(registrations, [&](const auto &installed) {
          return installed.service_id == registration.service_id ||
                 installed.adapter == registration.adapter;
        })) {
      result = RegistrationLoadResult::duplicate_identity;
      break;
    }
    registrations.push_back(std::move(registration));
  }
  closedir(directory);
  close(root);
  if (result != RegistrationLoadResult::loaded)
    registrations.clear();
  return result;
}

RegistrationChangeAssessment assess_registration_install(
    std::span<const Registration> installed, const Registration &candidate,
    std::span<const ProviderDependency> dependencies) {
  RegistrationChangeAssessment result;
  if (!valid_registration(candidate))
    return result;
  const auto found = std::ranges::find_if(installed, [&](const auto &item) {
    return item.service_id == candidate.service_id;
  });
  if (found == installed.end()) {
    result.decision = std::ranges::any_of(installed, [&](const auto &item) {
                        return item.adapter == candidate.adapter;
                      })
                          ? RegistrationChangeDecision::identity_conflict
                          : RegistrationChangeDecision::installable;
    return result;
  }
  if (same(*found, candidate)) {
    result.decision = RegistrationChangeDecision::unchanged;
    return result;
  }
  collect(result, found->adapter, dependencies);
  result.decision = result.dependents.empty()
                        ? RegistrationChangeDecision::requires_plugin_review
                        : RegistrationChangeDecision::blocked_by_dependents;
  return result;
}

RegistrationChangeAssessment assess_registration_removal(
    std::span<const Registration> installed, std::string_view service_id,
    std::span<const ProviderDependency> dependencies) {
  RegistrationChangeAssessment result;
  const auto found = std::ranges::find_if(installed, [&](const auto &item) {
    return item.service_id.view() == service_id;
  });
  if (found == installed.end()) {
    result.decision = RegistrationChangeDecision::unchanged;
    return result;
  }
  collect(result, found->adapter, dependencies);
  result.decision = result.dependents.empty()
                        ? RegistrationChangeDecision::installable
                        : RegistrationChangeDecision::blocked_by_dependents;
  return result;
}

definitions::DynamicAdapter compose_dynamic_adapter(
    Registration &registration) {
  if (!valid_registration(registration))
    return {};
  return {.binding = registration.adapter,
          .dispatch = dispatch_external,
          .context = &registration};
}

DependencyIndexResult rebuild_dependency_index(
    grants::GrantStore &grant_store,
    const std::filesystem::path &revision_stores_root,
    const definitions::TrustedDefinitionRegistry &definitions,
    const std::filesystem::path &index_root, std::uint32_t expected_uid,
    DependencyIndex &output) {
  output = {};
  grants::StoreState state;
  try {
    state = grant_store.read_as_owner(expected_uid);
  } catch (...) {
    return DependencyIndexResult::untrusted_store;
  }
  output.grant_mutation_sequence = state.mutation_sequence;
  for (const auto &plugin : state.plugins) {
    store::RevisionStore revisions(
        revision_stores_root / std::string(plugin.plugin.view()),
        {.schema_v2_enabled = true});
    store::Result revision_status;
    const auto activation =
        revisions.verified_current_as_owner(expected_uid, &revision_status);
    if ((plugin.active || plugin.rollback) &&
        (!revision_status.ok() || !activation))
      return DependencyIndexResult::revision_mismatch;
    const auto check_slot = [&](const std::optional<grants::RevisionGrants> &slot,
                                const std::optional<store::PolicyBinding> &bound) {
      if (!slot)
        return true;
      if (!verify_revision(revisions.revision_path(
                               slot->binding.revision.view()),
                           *slot))
        return false;
      if (bound &&
          (bound->plugin_id != slot->binding.plugin.view() ||
           bound->revision_sha256 != slot->binding.revision.view() ||
           bound->source_request_sha256 !=
               slot->source_request_fingerprint.view() ||
           bound->generation != slot->binding.generation))
        return false;
      for (const auto &dynamic : slot->dynamic_grants) {
        const auto resolved = definitions.resolve(dynamic.request.definition);
        if (!resolved)
          return false;
        output.dependencies.push_back(
            {.plugin = slot->binding.plugin,
             .revision = slot->binding.revision,
             .adapter = resolved->definition->adapter});
      }
      return true;
    };
    if (!check_slot(plugin.active,
                    activation ? std::optional(activation->active)
                               : std::nullopt) ||
        !check_slot(plugin.rollback,
                    activation ? activation->rollback : std::nullopt) ||
        !check_slot(plugin.candidate, std::nullopt))
      return DependencyIndexResult::revision_mismatch;
  }
  std::ranges::sort(output.dependencies, {}, [](const auto &item) {
    return std::tuple(item.adapter.adapter_class.view(),
                      item.adapter.implementation_digest.view(),
                      item.adapter.abi_version, item.plugin.view(),
                      item.revision.view());
  });
  output.dependencies.erase(
      std::unique(output.dependencies.begin(), output.dependencies.end(),
                  [](const auto &left, const auto &right) {
                    return left.plugin == right.plugin &&
                           left.revision == right.revision &&
                           left.adapter == right.adapter;
                  }),
      output.dependencies.end());
  auto document = dependency_document(output);
  output.content_digest = Digest(manifest::sha256_hex(document));
  document.append("digest=").append(output.content_digest.view()).append("\n");
  const int directory = open(index_root.c_str(),
                             O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
  struct stat status {};
  if (directory < 0 || fstat(directory, &status) < 0 ||
      status.st_uid != geteuid() || (status.st_mode & 0077) != 0) {
    if (directory >= 0)
      close(directory);
    return DependencyIndexResult::unsafe_index;
  }
  const std::string temporary =
      ".provider-dependencies-" + std::to_string(getpid());
  const int record = openat(directory, temporary.c_str(),
                            O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC |
                                O_NOFOLLOW,
                            0600);
  if (record < 0) {
    close(directory);
    return DependencyIndexResult::unsafe_index;
  }
  std::size_t offset = 0;
  while (offset < document.size()) {
    const ssize_t count =
        write(record, document.data() + offset, document.size() - offset);
    if (count < 0 && errno == EINTR)
      continue;
    if (count <= 0)
      break;
    offset += static_cast<std::size_t>(count);
  }
  const bool published = offset == document.size() && fsync(record) == 0 &&
                         renameat(directory, temporary.c_str(), directory,
                                  "provider-dependencies-v1") == 0 &&
                         fsync(directory) == 0;
  close(record);
  if (!published)
    unlinkat(directory, temporary.c_str(), 0);
  close(directory);
  if (!published)
    return DependencyIndexResult::unsafe_index;
  DependencyIndex verified;
  if (!verify_dependency_index(index_root, state.mutation_sequence, geteuid(),
                               verified) ||
      verified.content_digest != output.content_digest ||
      verified.dependencies.size() != output.dependencies.size())
    return DependencyIndexResult::unsafe_index;
  output = std::move(verified);
  return DependencyIndexResult::rebuilt;
}

bool verify_dependency_index(
    const std::filesystem::path &index_root,
    std::uint64_t expected_grant_mutation_sequence,
    std::uint32_t expected_owner, DependencyIndex &output) {
  output = {};
  const int directory = open(index_root.c_str(),
                             O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
  struct stat directory_status {};
  if (directory < 0 || fstat(directory, &directory_status) < 0 ||
      directory_status.st_uid != expected_owner ||
      (directory_status.st_mode & 0077) != 0) {
    if (directory >= 0)
      close(directory);
    return false;
  }
  const int record = openat(directory, "provider-dependencies-v1",
                            O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
  struct stat record_status {};
  if (record < 0 || fstat(record, &record_status) < 0 ||
      !S_ISREG(record_status.st_mode) ||
      record_status.st_uid != expected_owner ||
      (record_status.st_mode & 0077) != 0 || record_status.st_size <= 0 ||
      record_status.st_size > 4 * 1024 * 1024) {
    if (record >= 0)
      close(record);
    close(directory);
    return false;
  }
  std::string document(static_cast<std::size_t>(record_status.st_size), '\0');
  std::size_t read_bytes = 0;
  while (read_bytes < document.size()) {
    const ssize_t count =
        read(record, document.data() + read_bytes, document.size() - read_bytes);
    if (count < 0 && errno == EINTR)
      continue;
    if (count <= 0)
      break;
    read_bytes += static_cast<std::size_t>(count);
  }
  close(record);
  close(directory);
  if (read_bytes != document.size() ||
      !document.starts_with("OMARCHY-PROVIDER-DEPENDENCIES-V1\nmutation=") ||
      !document.ends_with("\n"))
    return false;
  const auto digest_line = document.rfind("digest=");
  if (digest_line == std::string::npos || digest_line == 0 ||
      document.find('\n', digest_line) != document.size() - 1)
    return false;
  const auto canonical = std::string_view(document).substr(0, digest_line);
  const auto digest_value = std::string_view(document).substr(
      digest_line + 7, document.size() - digest_line - 8);
  try {
    output.content_digest = Digest(digest_value);
  } catch (...) {
    return false;
  }
  if (manifest::sha256_hex(canonical) != output.content_digest.view())
    return false;
  std::size_t offset = std::string_view(
      "OMARCHY-PROVIDER-DEPENDENCIES-V1\nmutation=").size();
  const auto mutation_end = document.find('\n', offset);
  if (mutation_end == std::string::npos ||
      !number(std::string_view(document).substr(offset, mutation_end - offset),
              output.grant_mutation_sequence) ||
      output.grant_mutation_sequence != expected_grant_mutation_sequence)
    return false;
  offset = mutation_end + 1;
  while (offset < digest_line) {
    const auto end = document.find('\n', offset);
    if (end == std::string::npos || end > digest_line ||
        output.dependencies.size() == 4096)
      return false;
    const std::string_view row(document.data() + offset, end - offset);
    if (!row.starts_with("dependency="))
      return false;
    const auto fields = [&] {
      std::array<std::string_view, 5> result{};
      auto value = row.substr(11);
      for (std::size_t index = 0; index < result.size(); ++index) {
        const auto separator = value.find('|');
        if (index + 1 == result.size()) {
          if (separator != std::string_view::npos)
            return std::array<std::string_view, 5>{};
          result[index] = value;
        } else {
          if (separator == std::string_view::npos)
            return std::array<std::string_view, 5>{};
          result[index] = value.substr(0, separator);
          value.remove_prefix(separator + 1);
        }
      }
      return result;
    }();
    std::uint32_t abi = 0;
    if (std::ranges::any_of(fields, [](auto value) { return value.empty(); }) ||
        !number(fields[4], abi) || abi == 0)
      return false;
    try {
      output.dependencies.push_back(
          {.plugin = permissions::PluginId(fields[0]),
           .revision = Digest(fields[1]),
           .adapter = {.adapter_class = definitions::Name(fields[2]),
                       .implementation_digest = Digest(fields[3]),
                       .abi_version = abi}});
    } catch (...) {
      return false;
    }
    offset = end + 1;
  }
  return dependency_document(output) == canonical;
}
} // namespace omarchy::plugins::external_provider
