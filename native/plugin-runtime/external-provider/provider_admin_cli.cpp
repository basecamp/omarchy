#include "capability_definition_loader.hpp"
#include "provider_registration.hpp"

#include <fcntl.h>
#include <pwd.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <unistd.h>

#include <charconv>
#include <cstdlib>
#include <fstream>
#include <iostream>
#include <ranges>
#include <stdexcept>

namespace external = omarchy::plugins::external_provider;
namespace definitions = omarchy::plugins::definitions;
namespace grants = omarchy::plugins::grants;

namespace {
struct Options {
  std::string command;
  std::string argument;
  bool dry_run = false;
  bool reviewed = false;
  std::filesystem::path providers = "/etc/omarchy/plugin-providers.d";
  std::filesystem::path package_definitions =
      "/usr/lib/omarchy/plugin-capabilities.d";
  std::filesystem::path definitions = "/etc/omarchy/plugin-capabilities.d";
  std::filesystem::path grants;
  std::filesystem::path revisions;
  std::filesystem::path index = "/var/lib/omarchy/plugin-security";
  std::uint32_t owner = 0;
};
[[noreturn]] void fail(std::string_view message) {
  throw std::runtime_error(std::string(message));
}
std::uint32_t number(std::string_view value) {
  std::uint32_t output = 0;
  const auto [end, error] =
      std::from_chars(value.data(), value.data() + value.size(), output);
  if (error != std::errc{} || end != value.data() + value.size())
    fail("invalid owner uid");
  return output;
}
void defaults(Options &options) {
  const char *sudo_uid = std::getenv("SUDO_UID");
  options.owner = sudo_uid == nullptr ? getuid() : number(sudo_uid);
  const passwd *account = getpwuid(options.owner);
  if (account == nullptr || account->pw_dir == nullptr)
    fail("cannot resolve invoking user's trusted state roots");
  const std::filesystem::path state =
      std::filesystem::path(account->pw_dir) /
      ".local/state/omarchy/plugin-security";
  options.grants = state / "grants";
  options.revisions = state / "revisions";
}
Options parse(int argc, char **argv) {
  if (argc < 2)
    fail("expected inspect, install, upgrade, or remove");
  Options options;
  defaults(options);
  options.command = argv[1];
  for (int index = 2; index < argc; ++index) {
    const std::string_view value(argv[index]);
    if (value == "--dry-run")
      options.dry_run = true;
    else if (value == "--reviewed")
      options.reviewed = true;
#ifdef OMARCHY_PROVIDER_ADMIN_TESTING
    else if (value == "--providers" && index + 1 < argc)
      options.providers = argv[++index];
    else if (value == "--definitions" && index + 1 < argc)
      options.definitions = argv[++index];
    else if (value == "--package-definitions" && index + 1 < argc)
      options.package_definitions = argv[++index];
    else if (value == "--grants" && index + 1 < argc)
      options.grants = argv[++index];
    else if (value == "--revisions" && index + 1 < argc)
      options.revisions = argv[++index];
    else if (value == "--index" && index + 1 < argc)
      options.index = argv[++index];
    else if (value == "--owner" && index + 1 < argc)
      options.owner = number(argv[++index]);
#endif
    else if (value.starts_with("--"))
      fail("unknown option");
    else if (options.argument.empty())
      options.argument = value;
    else
      fail("too many positional arguments");
  }
  if (options.command != "inspect" && options.command != "install" &&
      options.command != "upgrade" && options.command != "remove")
    fail("unknown command");
  if (options.command != "inspect" && options.argument.empty())
    fail("mutation requires a registration document or service id");
  return options;
}
bool any_adapter(std::string_view, const definitions::Digest &, std::uint32_t,
                 void *) noexcept {
  return true;
}
std::string decision(external::RegistrationChangeDecision value) {
  switch (value) {
  case external::RegistrationChangeDecision::installable: return "installable";
  case external::RegistrationChangeDecision::unchanged: return "unchanged";
  case external::RegistrationChangeDecision::requires_plugin_review:
    return "requires-plugin-review";
  case external::RegistrationChangeDecision::blocked_by_dependents:
    return "blocked-by-dependents";
  case external::RegistrationChangeDecision::identity_conflict:
    return "identity-conflict";
  }
  return "identity-conflict";
}
void print_dependents(
    const external::RegistrationChangeAssessment &assessment) {
  for (const auto &dependent : assessment.dependents)
    std::cout << "dependent=" << dependent.plugin.view() << '@'
              << dependent.revision.view() << '\n';
}
struct Directory {
  int fd = -1;
  explicit Directory(const std::filesystem::path &path) {
    fd = open(path.c_str(), O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
    struct stat status {};
    if (fd < 0 || fstat(fd, &status) < 0 || status.st_uid != geteuid() ||
        (status.st_mode & (S_IWGRP | S_IWOTH)) != 0 || flock(fd, LOCK_EX) < 0)
      fail("provider registration root is not trusted and lockable");
  }
  ~Directory() {
    if (fd >= 0)
      close(fd);
  }
};
void publish(Directory &root, std::string_view name, std::string_view document) {
  const std::string temporary = ".provider-admin-" + std::to_string(getpid());
  const int fd = openat(root.fd, temporary.c_str(),
                        O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
                        0644);
  if (fd < 0)
    fail("cannot stage provider registration");
  std::size_t offset = 0;
  while (offset < document.size()) {
    const ssize_t count =
        write(fd, document.data() + offset, document.size() - offset);
    if (count < 0 && errno == EINTR)
      continue;
    if (count <= 0)
      break;
    offset += static_cast<std::size_t>(count);
  }
  const bool ok = offset == document.size() && fsync(fd) == 0;
  close(fd);
  if (!ok || renameat(root.fd, temporary.c_str(), root.fd,
                      std::string(name).c_str()) < 0 ||
      fsync(root.fd) < 0) {
    unlinkat(root.fd, temporary.c_str(), 0);
    fail("provider registration transaction failed");
  }
}
} // namespace

int main(int argc, char **argv) try {
  auto options = parse(argc, argv);
#ifndef OMARCHY_PROVIDER_ADMIN_TESTING
  if (geteuid() != 0)
    fail("provider administration requires a root-owned trust transaction");
#endif
  std::vector<external::Registration> installed;
  if (external::load_registration_directory(options.providers.string(),
                                             geteuid(), installed) !=
      external::RegistrationLoadResult::loaded)
    fail("installed provider registration root is invalid");
  definitions::TrustedDefinitionRegistry registry;
  std::size_t loaded = 0;
  if (!std::filesystem::exists(options.package_definitions) ||
      definitions::load_definition_directory(
          options.package_definitions.string(),
          definitions::DefinitionSource::omarchy_package, geteuid(),
          {.available = any_adapter}, registry, loaded) !=
          definitions::LoadResult::loaded)
    fail("packaged capability definitions are invalid or unavailable");
  if (std::filesystem::exists(options.definitions) &&
      definitions::load_definition_directory(
          options.definitions.string(), definitions::DefinitionSource::local_admin,
          geteuid(), {.available = any_adapter}, registry, loaded) !=
          definitions::LoadResult::loaded)
    fail("administrator capability definitions are invalid");
  grants::GrantStore grant_store(options.grants);
  external::DependencyIndex dependency_index;
  if (external::rebuild_dependency_index(
          grant_store, options.revisions, registry, options.index,
          options.owner, dependency_index) !=
      external::DependencyIndexResult::rebuilt)
    fail("cannot reconstruct authoritative provider dependencies");
  if (options.command == "inspect") {
    for (const auto &registration : installed) {
      const auto assessment = external::assess_registration_removal(
          installed, registration.service_id.view(),
          dependency_index.dependencies);
      std::cout << "service=" << registration.service_id.view()
                << " adapter=" << registration.adapter.adapter_class.view()
                << " digest=" << registration.executable_digest.view()
                << " decision=" << decision(assessment.decision) << '\n';
      print_dependents(assessment);
    }
    return 0;
  }
  Directory registration_root(options.providers);
  if (options.command == "remove") {
    const auto assessment = external::assess_registration_removal(
        installed, options.argument, dependency_index.dependencies);
    std::cout << "decision=" << decision(assessment.decision) << '\n';
    print_dependents(assessment);
    if (assessment.decision ==
        external::RegistrationChangeDecision::blocked_by_dependents)
      return 3;
    if (assessment.decision ==
        external::RegistrationChangeDecision::unchanged)
      return 0;
    if (!options.dry_run) {
      const std::string name = options.argument + ".provider";
      if (unlinkat(registration_root.fd, name.c_str(), 0) < 0 ||
          fsync(registration_root.fd) < 0)
        fail("provider removal transaction failed");
    }
    return 0;
  }
  std::ifstream input(options.argument, std::ios::binary);
  const std::string bytes((std::istreambuf_iterator<char>(input)), {});
  external::Registration candidate;
  if (external::parse_registration_document(bytes, geteuid(), candidate) !=
      external::RegistrationLoadResult::loaded)
    fail("candidate provider registration is invalid");
  const auto assessment = external::assess_registration_install(
      installed, candidate, dependency_index.dependencies);
  std::cout << "decision=" << decision(assessment.decision) << '\n';
  print_dependents(assessment);
  if (assessment.decision ==
      external::RegistrationChangeDecision::blocked_by_dependents)
    return 3;
  if (assessment.decision ==
          external::RegistrationChangeDecision::requires_plugin_review &&
      (!options.reviewed || options.command != "upgrade"))
    return 4;
  if (assessment.decision ==
      external::RegistrationChangeDecision::identity_conflict)
    return 5;
  if (!options.dry_run &&
      assessment.decision != external::RegistrationChangeDecision::unchanged) {
    const std::string name =
        std::string(candidate.service_id.view()) + ".provider";
    publish(registration_root, name,
            external::canonical_registration_document(candidate));
  }
  return 0;
} catch (const std::exception &error) {
  std::cerr << "omarchy-plugin-provider-admin: " << error.what() << '\n';
  return 2;
}
