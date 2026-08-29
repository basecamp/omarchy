#include "provider_registration.hpp"

#include <algorithm>
#include <charconv>
#include <dirent.h>
#include <fcntl.h>
#include <sys/stat.h>
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
void collect(RegistrationChangeAssessment &result,
             const definitions::AdapterBinding &adapter,
             std::span<const ProviderDependency> dependencies) {
  for (const auto &dependency : dependencies)
    if (dependency.adapter == adapter)
      result.dependents.push_back(dependency);
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
} // namespace omarchy::plugins::external_provider
