#include "capability_definition.hpp"

#include <array>
#include <stdexcept>
#include <string>

namespace {
using namespace omarchy::plugins::definitions;
namespace permissions = omarchy::plugins::permissions;

void require(bool condition, std::string_view message) {
  if (!condition)
    throw std::runtime_error(std::string(message));
}

Digest digest(char value) { return Digest(std::string(64, value)); }

CapabilityDefinition github() {
  CapabilityDefinition definition{
      .canonical_name = Name("network.fetch.github"),
      .authority_identity = Name("network.fetch.github-api-v1"),
      .category = AuthorityCategory::network_fetch,
      .scope_schema = ScopeSchema::https_origins_and_methods,
      .title = Label("Read or update selected GitHub resources"),
      .risk_text = Label("Sends bounded requests to explicitly selected GitHub API origins"),
      .risk = RiskLevel::high,
      .revocation = RevocationPolicy::cancel_inflight,
      .audit = {},
      .adapter = {.adapter_class = Name("github-api"),
                  .implementation_digest = digest('a'),
                  .abi_version = 1},
      .operations = {},
  };
  definition.operations.insert({.name = Name("notifications.list"),
                                .label = Label("List notifications")});
  definition.operations.insert({.name = Name("notifications.mark-read"),
                                .label = Label("Mark a notification read"),
                                .mutating = true});
  return definition;
}

CapabilityDefinition open_uri() {
  CapabilityDefinition definition{
      .canonical_name = Name("external.open-uri.https"),
      .authority_identity = Name("external.open-uri.https-v1"),
      .category = AuthorityCategory::external_open_uri,
      .scope_schema = ScopeSchema::https_origins_after_gesture,
      .title = Label("Open selected HTTPS sites"),
      .risk_text = Label("Opens a user-visible HTTPS address after one fresh gesture"),
      .risk = RiskLevel::moderate,
      .revocation = RevocationPolicy::deny_new,
      .audit = {},
      .adapter = {.adapter_class = Name("desktop-open-uri"),
                  .implementation_digest = digest('b'),
                  .abi_version = 1},
      .operations = {},
  };
  definition.operations.insert({.name = Name("open"),
                                .label = Label("Open link"),
                                .mutating = true,
                                .requires_fresh_gesture = true});
  return definition;
}

CliHarnessProfile github_cli() {
  CliHarnessProfile profile{
      .profile_name = Name("github-notifications-read"),
      .executable = permissions::BoundedString<256>("/usr/bin/gh"),
      .executable_digest = digest('c'),
      .working_directory = permissions::BoundedString<256>("/var/empty"),
      .fixed_environment = {},
      .subcommands = {},
      .maximum_stdin_bytes = 0,
      .maximum_stdout_bytes = 65536,
      .maximum_stderr_bytes = 4096,
      .timeout_milliseconds = 5000,
  };
  profile.fixed_environment.insert(Token("NO_COLOR=1"));
  CliSubcommand command{.name = Name("api"), .arguments = {}};
  command.arguments.push_back({.kind = ArgumentKind::literal,
                               .value = Token("notifications")});
  command.arguments.push_back({.kind = ArgumentKind::bounded_unsigned,
                               .value = Token("limit"),
                               .maximum = 100});
  profile.subcommands.push_back(command);
  return profile;
}
} // namespace

int main() {
  TrustedDefinitionRegistry registry;
  const auto github_definition = github();
  require(registry.install(github_definition, DefinitionSource::omarchy_package, 4),
          "trusted GitHub adapter definition was rejected");
  require(registry.install(open_uri(), DefinitionSource::local_admin, 2),
          "trusted open-URI definition was rejected");
  require(registry.size() == 2, "registry count changed");

  const auto installed = registry.find("network.fetch.github");
  require(installed && installed->generation == 4 &&
              installed->definition->adapter.adapter_class.view() == "github-api",
          "installed adapter definition did not resolve");
  require(registry.resolve({.canonical_name = Name("network.fetch.github"),
                            .definition_generation = 4,
                            .definition_digest = installed->digest}).has_value(),
          "exact plugin capability reference did not resolve");
  require(!registry.resolve({.canonical_name = Name("network.fetch.github"),
                             .definition_generation = 3,
                             .definition_digest = installed->digest}).has_value(),
          "stale definition generation resolved");
  require(!registry.resolve({.canonical_name = Name("network.fetch.github"),
                             .definition_generation = 4,
                             .definition_digest = digest('f')}).has_value(),
          "wrong adapter-definition digest resolved");
  require(!registry.find("plugin.proposed-capability"),
          "unknown publisher-defined capability resolved");

  auto alias = github_definition;
  alias.canonical_name = Name("network.fetch.github-friendly-name");
  require(!registry.install(alias, DefinitionSource::local_admin, 1),
          "alias laundered an existing authority identity");
  alias.authority_identity = Name("network.fetch.github-alias-v1");
  require(!registry.install(alias, DefinitionSource::local_admin, 1),
          "duplicate adapter operation binding was laundered under an alias");

  auto dishonest_open = open_uri();
  dishonest_open.canonical_name = Name("external.open-uri.no-gesture");
  dishonest_open.authority_identity = Name("external.open-uri.no-gesture-v1");
  auto operation = *dishonest_open.operations.values().begin();
  dishonest_open.operations = {};
  operation.requires_fresh_gesture = false;
  dishonest_open.operations.insert(operation);
  require(!valid_definition(dishonest_open),
          "external URI definition removed the gesture rule");

  auto profile = github_cli();
  require(valid_cli_profile(profile), "exact CLI profile was rejected");
  CliInvocation invocation{};
  const std::array<std::string_view, 3> accepted{"api", "notifications", "25"};
  require(authorize_cli_invocation(profile, digest('c'), accepted, invocation) &&
              invocation.argc == 3,
          "bounded CLI invocation was denied");
  const std::array<std::string_view, 3> injected{"api", "notifications", "25;sh"};
  require(!authorize_cli_invocation(profile, digest('c'), injected, invocation),
          "CLI grammar accepted shell-like injection");
  const std::array<std::string_view, 3> expanded{"api", "notifications", "101"};
  require(!authorize_cli_invocation(profile, digest('c'), expanded, invocation),
          "CLI grammar accepted out-of-range argument");
  require(!authorize_cli_invocation(profile, digest('d'), accepted, invocation),
          "wrong executable identity was accepted");
  const std::array<std::string_view, 2> unknown{"repo", "list"};
  require(!authorize_cli_invocation(profile, digest('c'), unknown, invocation),
          "unregistered CLI subcommand was accepted");

  profile.executable = permissions::BoundedString<256>("/usr/bin/bash");
  require(!valid_cli_profile(profile), "shell executable became a harness profile");
  return 0;
}
