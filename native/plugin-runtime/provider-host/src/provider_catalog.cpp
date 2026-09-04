#include "provider_profile.hpp"

#include "manifest_contract.hpp"

#include <dirent.h>
#include <fcntl.h>
#include <sys/stat.h>

#include <algorithm>
#include <array>
#include <cerrno>
#include <charconv>
#include <map>
#include <optional>
#include <string>
#include <utility>

namespace omarchy::plugin_runtime::provider_host {
namespace {

using detail::Descriptor;

constexpr std::size_t kMaximumProfileBytes = 16 * 1024;
constexpr std::size_t kMaximumExecutableBytes = 128 * 1024 * 1024;
constexpr std::size_t kMaximumArguments = 16;
constexpr std::size_t kMaximumArgumentBytes = 512;
constexpr std::size_t kMaximumInheritedEnvironment = 4;
constexpr std::size_t kMaximumProfiles = 128;

bool secure_directory(const struct stat &metadata,
                      std::uint32_t trusted_uid) noexcept {
  return S_ISDIR(metadata.st_mode) && metadata.st_uid == trusted_uid &&
         (metadata.st_mode & 0022) == 0;
}

enum class RootResult { opened, absent, rejected };

RootResult open_root(int filesystem_root_fd,
                     std::span<const std::string_view> components,
                     std::uint32_t trusted_uid, Descriptor &output) {
  Descriptor current(::openat(filesystem_root_fd, ".",
                              O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW));
  struct stat metadata {};
  if (!current || ::fstat(current.get(), &metadata) < 0 ||
      !secure_directory(metadata, trusted_uid))
    return RootResult::rejected;
  for (const auto component : components) {
    if (component.empty() || component == "." || component == ".." ||
        component.find('/') != std::string_view::npos)
      return RootResult::rejected;
    const std::string name(component);
    Descriptor next(::openat(current.get(), name.c_str(),
                             O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW));
    if (!next)
      return errno == ENOENT ? RootResult::absent : RootResult::rejected;
    if (::fstat(next.get(), &metadata) < 0 ||
        !secure_directory(metadata, trusted_uid))
      return RootResult::rejected;
    current = std::move(next);
  }
  output = std::move(current);
  return RootResult::opened;
}

std::optional<std::string> read_bounded(int fd, std::size_t maximum) {
  std::string result;
  std::array<char, 16 * 1024> buffer{};
  if (::lseek(fd, 0, SEEK_SET) < 0)
    return std::nullopt;
  while (true) {
    const auto count = ::read(fd, buffer.data(), buffer.size());
    if (count < 0) {
      if (errno == EINTR)
        continue;
      return std::nullopt;
    }
    if (count == 0)
      break;
    if (result.size() + static_cast<std::size_t>(count) > maximum)
      return std::nullopt;
    result.append(buffer.data(), static_cast<std::size_t>(count));
  }
  if (::lseek(fd, 0, SEEK_SET) < 0)
    return std::nullopt;
  return result;
}

bool canonical_absolute_path(std::string_view path) {
  if (path.size() < 2 || path.size() > 4096 || path.front() != '/' ||
      path.back() == '/' || path.find('\0') != std::string_view::npos)
    return false;
  std::size_t begin = 1;
  while (begin < path.size()) {
    const auto end = path.find('/', begin);
    const auto component = path.substr(
        begin, end == std::string_view::npos ? path.size() - begin : end - begin);
    if (component.empty() || component == "." || component == "..")
      return false;
    begin = end == std::string_view::npos ? path.size() : end + 1;
  }
  return true;
}

Descriptor open_executable(int filesystem_root_fd, std::string_view path,
                           std::uint32_t trusted_uid) {
  if (!canonical_absolute_path(path))
    return {};
  Descriptor current(::openat(filesystem_root_fd, ".",
                              O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW));
  struct stat metadata {};
  if (!current || ::fstat(current.get(), &metadata) < 0 ||
      !secure_directory(metadata, trusted_uid))
    return {};
  std::size_t begin = 1;
  while (begin < path.size()) {
    const auto end = path.find('/', begin);
    const auto component = path.substr(
        begin, end == std::string_view::npos ? path.size() - begin : end - begin);
    const std::string name(component);
    const bool leaf = end == std::string_view::npos;
    Descriptor next(::openat(
        current.get(), name.c_str(),
        (leaf ? O_RDONLY | O_NONBLOCK : O_RDONLY | O_DIRECTORY) | O_CLOEXEC |
            O_NOFOLLOW));
    if (!next || ::fstat(next.get(), &metadata) < 0)
      return {};
    if (leaf) {
      if (!S_ISREG(metadata.st_mode) || metadata.st_uid != trusted_uid ||
          (metadata.st_mode & 0022) != 0 || (metadata.st_mode & 0100) == 0 ||
          (metadata.st_mode & (S_ISUID | S_ISGID)) != 0 ||
          metadata.st_size < 0 ||
          static_cast<std::uint64_t>(metadata.st_size) > kMaximumExecutableBytes)
        return {};
      return next;
    }
    if (!secure_directory(metadata, trusted_uid))
      return {};
    current = std::move(next);
    begin = end + 1;
  }
  return {};
}

std::map<std::string, std::vector<std::string>>
parse_document(std::string_view document) {
  std::map<std::string, std::vector<std::string>> fields;
  std::size_t begin = 0;
  while (begin < document.size()) {
    const auto end = document.find('\n', begin);
    auto line = document.substr(
        begin, end == std::string_view::npos ? document.size() - begin : end - begin);
    if (!line.empty() && line.back() == '\r')
      line.remove_suffix(1);
    if (!line.empty() && line.front() != '#') {
      const auto separator = line.find('=');
      if (separator == std::string_view::npos || separator == 0 ||
          separator + 1 >= line.size())
        return {};
      fields[std::string(line.substr(0, separator))].emplace_back(
          line.substr(separator + 1));
    }
    begin = end == std::string_view::npos ? document.size() : end + 1;
  }
  return fields;
}

bool single(const std::map<std::string, std::vector<std::string>> &fields,
            std::string_view key, std::string &output) {
  const auto found = fields.find(std::string(key));
  if (found == fields.end() || found->second.size() != 1)
    return false;
  output = found->second.front();
  return true;
}

std::uint32_t parse_u32(std::string_view value) {
  std::uint32_t result = 0;
  const auto [end, error] =
      std::from_chars(value.data(), value.data() + value.size(), result);
  return error == std::errc{} && end == value.data() + value.size() ? result : 0;
}

bool same_process(const ProviderCatalog::Profile &left,
                  const ProviderCatalog::Profile &right) {
  return left.executable_path == right.executable_path &&
         left.executable_digest == right.executable_digest &&
         left.arguments == right.arguments &&
         left.inherited_environment == right.inherited_environment;
}

std::optional<std::optional<std::chrono::milliseconds>>
parse_timeout(const std::map<std::string, std::vector<std::string>> &fields) {
  const auto found = fields.find("invocation-timeout-ms");
  if (found == fields.end())
    return std::optional<std::chrono::milliseconds>{};
  if (found->second.size() != 1)
    return std::nullopt;
  const auto value = parse_u32(found->second.front());
  const auto timeout = std::chrono::milliseconds(value);
  if (value == 0 || timeout > kMaximumProviderInvocationTimeout)
    return std::nullopt;
  return timeout;
}

std::optional<ProviderCatalog::Profile>
load_profile(int root_fd, std::string_view name, int filesystem_root_fd,
             std::uint32_t trusted_uid, CatalogError &error) {
  if (name.size() < 9 || !name.ends_with(".profile"))
    return std::nullopt;
  const std::string filename(name);
  Descriptor profile(::openat(root_fd, filename.c_str(),
                              O_RDONLY | O_NONBLOCK | O_CLOEXEC | O_NOFOLLOW));
  struct stat metadata {};
  if (!profile || ::fstat(profile.get(), &metadata) < 0 ||
      !S_ISREG(metadata.st_mode) || metadata.st_uid != trusted_uid ||
      (metadata.st_mode & 0022) != 0 || metadata.st_size < 0 ||
      static_cast<std::size_t>(metadata.st_size) > kMaximumProfileBytes) {
    error = CatalogError::profile_rejected;
    return std::nullopt;
  }
  const auto document = read_bounded(profile.get(), kMaximumProfileBytes);
  if (!document) {
    error = CatalogError::profile_rejected;
    return std::nullopt;
  }
  const auto fields = parse_document(*document);
  std::string schema, adapter_class, contract_digest, abi, group, executable_path,
      executable_digest;
  const auto invocation_timeout = parse_timeout(fields);
  if (fields.empty() || !single(fields, "schema", schema) || schema != "1" ||
      !single(fields, "adapter-class", adapter_class) ||
      !single(fields, "contract-digest", contract_digest) ||
      !single(fields, "abi-version", abi) || !single(fields, "group", group) ||
      !single(fields, "executable", executable_path) ||
      !single(fields, "executable-sha256", executable_digest) ||
      !definitions::canonical_identifier(adapter_class) ||
      !definitions::canonical_identifier(group) ||
      !definitions::valid_digest(contract_digest) ||
      !definitions::valid_digest(executable_digest) || parse_u32(abi) == 0 ||
      !invocation_timeout) {
    error = CatalogError::profile_rejected;
    return std::nullopt;
  }
  for (const auto &[key, values] : fields) {
    if (key != "schema" && key != "adapter-class" &&
        key != "contract-digest" && key != "abi-version" && key != "group" &&
        key != "executable" && key != "executable-sha256" && key != "arg" &&
        key != "inherit-environment" && key != "invocation-timeout-ms") {
      error = CatalogError::profile_rejected;
      return std::nullopt;
    }
    if (key != "arg" && key != "inherit-environment" && values.size() != 1) {
      error = CatalogError::profile_rejected;
      return std::nullopt;
    }
  }
  std::vector<std::string> inherited_environment;
  if (const auto found = fields.find("inherit-environment");
      found != fields.end()) {
    static constexpr std::array<std::string_view, 2> allowed{
        "HYPRLAND_INSTANCE_SIGNATURE", "XDG_RUNTIME_DIR"};
    if (found->second.empty() ||
        found->second.size() > kMaximumInheritedEnvironment ||
        std::ranges::any_of(found->second, [&](const auto &name) {
          return std::ranges::find(allowed, name) == allowed.end();
        })) {
      error = CatalogError::profile_rejected;
      return std::nullopt;
    }
    inherited_environment = found->second;
    std::ranges::sort(inherited_environment);
    if (std::ranges::adjacent_find(inherited_environment) !=
        inherited_environment.end()) {
      error = CatalogError::profile_rejected;
      return std::nullopt;
    }
  }
  std::vector<std::string> arguments;
  if (const auto found = fields.find("arg"); found != fields.end()) {
    if (found->second.size() > kMaximumArguments ||
        std::ranges::any_of(found->second, [](const auto &argument) {
          return argument.empty() || argument.size() > kMaximumArgumentBytes ||
                 argument.find('\0') != std::string::npos;
        })) {
      error = CatalogError::profile_rejected;
      return std::nullopt;
    }
    arguments = found->second;
  }
  auto executable =
      open_executable(filesystem_root_fd, executable_path, trusted_uid);
  const auto executable_bytes =
      executable ? read_bounded(executable.get(), kMaximumExecutableBytes)
                 : std::nullopt;
  if (!executable_bytes ||
      plugins::manifest::sha256_hex(*executable_bytes) != executable_digest) {
    error = CatalogError::executable_rejected;
    return std::nullopt;
  }
  try {
    return ProviderCatalog::Profile{
        .binding = {.adapter_class = definitions::Name(adapter_class),
                    .contract_digest = definitions::Digest(contract_digest),
                    .abi_version = parse_u32(abi)},
        .group = std::move(group),
        .executable_path = std::move(executable_path),
        .executable_digest = definitions::Digest(executable_digest),
        .arguments = std::move(arguments),
        .inherited_environment = std::move(inherited_environment),
        .invocation_timeout = *invocation_timeout,
        .executable = std::move(executable)};
  } catch (...) {
    error = CatalogError::profile_rejected;
    return std::nullopt;
  }
}

bool load_directory(int directory_fd, int filesystem_root_fd,
                    std::uint32_t trusted_uid,
                    std::vector<ProviderCatalog::Profile> &profiles,
                    CatalogError &error) {
  Descriptor duplicate(::fcntl(directory_fd, F_DUPFD_CLOEXEC, 3));
  DIR *directory = duplicate ? ::fdopendir(duplicate.release()) : nullptr;
  if (!directory) {
    error = CatalogError::root_rejected;
    return false;
  }
  std::vector<std::string> names;
  errno = 0;
  while (const auto *entry = ::readdir(directory)) {
    const std::string_view name(entry->d_name);
    if (name != "." && name != ".." && name.ends_with(".profile"))
      names.emplace_back(name);
    if (names.size() > kMaximumProfiles) {
      error = CatalogError::profile_rejected;
      ::closedir(directory);
      return false;
    }
  }
  const int read_error = errno;
  ::closedir(directory);
  if (read_error != 0) {
    error = CatalogError::root_rejected;
    return false;
  }
  std::ranges::sort(names);
  for (const auto &name : names) {
    auto profile = load_profile(directory_fd, name, filesystem_root_fd,
                                trusted_uid, error);
    if (!profile)
      return false;
    if (std::ranges::any_of(profiles, [&](const auto &existing) {
          return existing.binding == profile->binding;
        })) {
      error = CatalogError::duplicate_binding;
      return false;
    }
    if (std::ranges::any_of(profiles, [&](const auto &existing) {
          return existing.group == profile->group &&
                 !same_process(existing, *profile);
        })) {
      error = CatalogError::profile_rejected;
      return false;
    }
    profiles.push_back(std::move(*profile));
  }
  return true;
}

} // namespace

ProviderCatalog::ProviderCatalog(std::vector<Profile> profiles)
    : profiles_(std::move(profiles)) {}
ProviderCatalog::~ProviderCatalog() = default;

std::shared_ptr<const ProviderCatalog> ProviderCatalog::load(
    int filesystem_root_fd,
    std::span<const std::string_view> package_components,
    std::span<const std::string_view> admin_components,
    std::uint32_t trusted_uid, CatalogError &error) noexcept {
  error = CatalogError::none;
  try {
    if (::fcntl(filesystem_root_fd, F_GETFD) < 0) {
      error = CatalogError::root_rejected;
      return {};
    }
    std::vector<Profile> profiles;
    for (const auto components : {package_components, admin_components}) {
      Descriptor root;
      const auto result =
          open_root(filesystem_root_fd, components, trusted_uid, root);
      if (result == RootResult::rejected) {
        error = CatalogError::root_rejected;
        return {};
      }
      if (result == RootResult::opened &&
          !load_directory(root.get(), filesystem_root_fd, trusted_uid,
                          profiles, error))
        return {};
    }
    return std::shared_ptr<const ProviderCatalog>(
        new ProviderCatalog(std::move(profiles)));
  } catch (const std::bad_alloc &) {
    error = CatalogError::resource_exhausted;
    return {};
  } catch (...) {
    error = CatalogError::profile_rejected;
    return {};
  }
}

const ProviderCatalog::Profile *ProviderCatalog::find(
    const definitions::AdapterBinding &binding) const noexcept {
  const auto found =
      std::ranges::find(profiles_, binding, &Profile::binding);
  return found == profiles_.end() ? nullptr : &*found;
}

bool ProviderCatalog::available(
    const definitions::AdapterBinding &binding) const noexcept {
  return find(binding) != nullptr;
}

std::size_t ProviderCatalog::size() const noexcept { return profiles_.size(); }

} // namespace omarchy::plugin_runtime::provider_host
