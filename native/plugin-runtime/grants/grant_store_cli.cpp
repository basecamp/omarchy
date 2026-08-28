#include "grant_store.hpp"

#include <charconv>
#include <chrono>
#include <cstdlib>
#include <iostream>
#include <limits>
#include <optional>
#include <stdexcept>
#include <string>
#include <string_view>
#include <unistd.h>
#include <vector>

namespace {

namespace grant = omarchy::plugins::grants;
namespace permission = omarchy::plugins::permissions;

struct Options {
  std::string command;
  std::filesystem::path store;
  std::uint16_t plugin_schema_version = 0;
  std::string plugin;
  std::string revision;
  std::string source_request_fingerprint;
  std::uint64_t generation = 0;
  std::vector<std::pair<bool, std::string>> requests;
  std::string capability;
  std::optional<std::string> scope;
  std::optional<std::string> filter_plugin;
};

[[noreturn]] void fail(std::string_view message) {
  throw std::runtime_error(std::string(message));
}

std::uint64_t unsigned_integer(
    std::string_view value, std::string_view label,
    std::uint64_t maximum = std::numeric_limits<std::uint64_t>::max()) {
  std::uint64_t result = 0;
  const auto [end, error] =
      std::from_chars(value.data(), value.data() + value.size(), result);
  if (error != std::errc{} || end != value.data() + value.size() ||
      result > maximum)
    fail(std::string(label) + " must be a bounded unsigned integer");
  return result;
}

std::filesystem::path default_store() {
  if (const auto *state = std::getenv("XDG_STATE_HOME");
      state != nullptr && *state != '\0')
    return std::filesystem::path(state) / "omarchy/plugin-security/grants";
  if (const auto *home = std::getenv("HOME"); home != nullptr && *home != '\0')
    return std::filesystem::path(home) /
           ".local/state/omarchy/plugin-security/grants";
  fail("HOME or XDG_STATE_HOME is required for the grant store");
}

std::vector<std::string_view> split(std::string_view value, char separator) {
  std::vector<std::string_view> result;
  std::size_t start = 0;
  while (true) {
    const auto position = value.find(separator, start);
    result.push_back(value.substr(start, position - start));
    if (position == std::string_view::npos)
      return result;
    start = position + 1;
  }
}

permission::CapabilityKey capability_key(std::string_view value) {
  const auto separator = value.rfind('@');
  if (separator == std::string_view::npos || separator == 0 ||
      separator + 1 == value.size())
    fail("capability must use canonical-id@version");
  return {
      .id = permission::CapabilityId(value.substr(0, separator)),
      .version = static_cast<std::uint16_t>(
          unsigned_integer(value.substr(separator + 1), "capability version",
                           std::numeric_limits<std::uint16_t>::max())),
  };
}

permission::Scope scope_value(const permission::CapabilityKey &capability,
                              std::string_view value) {
  const auto *definition = permission::find_capability(capability);
  if (definition == nullptr)
    fail("capability/version is not in the closed registry");
  permission::Scope result;
  if (value.starts_with("quota:")) {
    const auto values = split(value.substr(6), ':');
    if (values.size() != 2)
      fail("quota scope must be quota:total-bytes:item-bytes");
    result = permission::QuotaScope{
        .total_bytes = unsigned_integer(values[0], "quota total"),
        .item_bytes = unsigned_integer(values[1], "quota item"),
    };
  } else if (value.starts_with("tokens:")) {
    permission::TokenScope tokens;
    for (const auto token : split(value.substr(7), ',')) {
      if (!tokens.tokens.insert(permission::ScopeToken(token)))
        fail("token scope contains a duplicate");
    }
    result = std::move(tokens);
  } else if (value.starts_with("resources:")) {
    const auto sections = split(value.substr(10), ':');
    if (sections.size() != 2)
      fail("resource scope must be resources:id,id:operation,operation");
    permission::ResourceScope resources;
    for (const auto resource : split(sections[0], ',')) {
      if (!resources.resources.insert(static_cast<std::uint32_t>(
              unsigned_integer(resource, "resource id",
                               std::numeric_limits<std::uint32_t>::max()))))
        fail("resource scope contains a duplicate id");
    }
    for (const auto operation : split(sections[1], ',')) {
      if (!resources.operations.insert(static_cast<permission::OperationId>(
              unsigned_integer(operation, "operation id",
                               std::numeric_limits<std::uint16_t>::max()))))
        fail("resource scope contains a duplicate operation");
    }
    result = std::move(resources);
  } else if (value == "none") {
    result = permission::NoScope{};
  } else {
    fail("scope must use quota:, tokens:, resources:, or none");
  }
  if (!permission::valid_scope(*definition, result))
    fail("scope is invalid for the registered capability version");
  return result;
}

permission::CapabilityRequest request_value(bool required,
                                            std::string_view value) {
  const auto separator = value.find('=');
  if (separator == std::string_view::npos || separator == 0 ||
      separator + 1 == value.size())
    fail("request must use capability@version=scope");
  const auto capability = capability_key(value.substr(0, separator));
  return {.capability = capability,
          .scope = scope_value(capability, value.substr(separator + 1)),
          .required = required};
}

std::string take_value(int &index, int count, char **arguments,
                       std::string_view option) {
  if (index + 1 >= count)
    fail(std::string(option) + " requires a value");
  return arguments[++index];
}

void usage(std::ostream &output) {
  output << "Usage:\n"
         << "  omarchy-plugin-permission list [--store DIR] [--plugin ID]\n"
         << "  omarchy-plugin-permission diff BINDING REQUESTS --capability "
            "ID@VERSION\n"
         << "  omarchy-plugin-permission grant BINDING REQUESTS --capability "
            "ID@VERSION [--scope SCOPE]\n"
         << "  omarchy-plugin-permission deny BINDING REQUESTS --capability "
            "ID@VERSION\n"
         << "  omarchy-plugin-permission revoke BINDING REQUESTS --capability "
            "ID@VERSION\n\n"
         << "BINDING: --schema-version 2 --plugin ID --revision SHA256 "
            "--source-request SHA256 --generation N\n"
         << "REQUESTS: repeat --required CAPABILITY@VERSION=SCOPE or "
            "--optional ...\n"
         << "Scopes: quota:TOTAL:ITEM | tokens:NAME,NAME | "
            "resources:ID,ID:OP,OP\n";
}

Options parse(int count, char **arguments) {
  if (count < 2)
    fail("a command is required; use --help");
  if (std::string_view(arguments[1]) == "--help" ||
      std::string_view(arguments[1]) == "-h") {
    usage(std::cout);
    std::exit(0);
  }
  Options options;
  options.command = arguments[1];
  options.store = default_store();
  for (int index = 2; index < count; ++index) {
    const std::string_view argument(arguments[index]);
    if (argument == "--store")
      options.store = take_value(index, count, arguments, argument);
    else if (argument == "--schema-version")
      options.plugin_schema_version =
          static_cast<std::uint16_t>(unsigned_integer(
              take_value(index, count, arguments, argument), "schema version",
              std::numeric_limits<std::uint16_t>::max()));
    else if (argument == "--plugin") {
      const auto value = take_value(index, count, arguments, argument);
      if (options.command == "list")
        options.filter_plugin = value;
      else
        options.plugin = value;
    } else if (argument == "--revision")
      options.revision = take_value(index, count, arguments, argument);
    else if (argument == "--source-request")
      options.source_request_fingerprint =
          take_value(index, count, arguments, argument);
    else if (argument == "--generation")
      options.generation = unsigned_integer(
          take_value(index, count, arguments, argument), "generation");
    else if (argument == "--required")
      options.requests.emplace_back(
          true, take_value(index, count, arguments, argument));
    else if (argument == "--optional")
      options.requests.emplace_back(
          false, take_value(index, count, arguments, argument));
    else if (argument == "--capability")
      options.capability = take_value(index, count, arguments, argument);
    else if (argument == "--scope")
      options.scope = take_value(index, count, arguments, argument);
    else if (argument == "--yes" || argument == "-y")
      fail("--yes never grants or denies plugin permissions");
    else if (argument == "--actor")
      fail("permission actors are derived from the trusted caller, not an "
           "option");
    else if (argument == "--help" || argument == "-h") {
      usage(std::cout);
      std::exit(0);
    } else
      fail("unknown permission option: " + std::string(argument));
  }
  return options;
}

grant::RequestBundle bundle_from(const Options &options) {
  if (options.plugin.empty() || options.revision.empty() ||
      options.source_request_fingerprint.empty() || options.generation == 0 ||
      options.plugin_schema_version == 0)
    fail("complete schema-v2 plugin/revision/source/generation binding is "
         "required");
  permission::RequestSet requests;
  for (const auto &[required, value] : options.requests)
    requests.push_back(request_value(required, value));
  return grant::make_bundle(
      options.plugin_schema_version, permission::PluginId(options.plugin),
      permission::Digest(options.revision),
      permission::Digest(options.source_request_fingerprint),
      options.generation, std::move(requests));
}

bool feature_enabled() {
  const auto *value = std::getenv("OMARCHY_PLUGIN_SCHEMA_V2_ENABLED");
  return value != nullptr && std::string_view(value) == "1";
}

void require_feature(const Options &options) {
  if (options.plugin_schema_version == 1)
    fail("schema v1 is unsafe host code and cannot receive granular "
         "permissions");
  if (!feature_enabled())
    fail("schema-v2 plugin permissions are feature-gated; set "
         "OMARCHY_PLUGIN_SCHEMA_V2_ENABLED=1 in the trusted runtime rollout");
}

std::uint64_t wall_seconds() {
  const auto now = std::chrono::system_clock::now().time_since_epoch();
  const auto seconds =
      std::chrono::duration_cast<std::chrono::seconds>(now).count();
  if (seconds <= 0)
    fail("system wall clock is invalid");
  return static_cast<std::uint64_t>(seconds);
}

void confirm(std::string_view action, const grant::Preview &preview,
             const permission::CapabilityKey &capability) {
  std::cerr << "Permission preview: " << grant::preview_json(preview) << '\n';
  if (isatty(STDIN_FILENO) == 0 || isatty(STDERR_FILENO) == 0)
    fail("grant and deny require an interactive terminal; no unattended actor "
         "is available");
  std::cerr << "Type " << action << " to " << action << ' '
            << capability.id.view() << '@' << capability.version << ": ";
  std::string answer;
  if (!std::getline(std::cin, answer) || answer != action)
    fail("permission decision cancelled");
}

grant::StoreState filter_state(grant::StoreState state,
                               const std::optional<std::string> &filter) {
  if (!filter)
    return state;
  const permission::PluginId id(*filter);
  std::erase_if(state.plugins,
                [&](const auto &plugin) { return plugin.plugin != id; });
  std::erase_if(state.decisions,
                [&](const auto &decision) { return decision.plugin != id; });
  return state;
}

int run(const Options &options) {
  require_feature(options);
  grant::GrantStore store(options.store);
  if (options.command == "list") {
    std::cout << grant::state_json(
                     filter_state(store.read(), options.filter_plugin))
              << '\n';
    return 0;
  }
  if (options.command != "diff" && options.command != "grant" &&
      options.command != "deny" && options.command != "revoke")
    fail("command must be list, diff, grant, deny, or revoke");
  const auto bundle = bundle_from(options);
  if (options.capability.empty())
    fail("--capability ID@VERSION is required");
  const auto capability = capability_key(options.capability);
  if (options.command == "diff") {
    std::cout << grant::preview_json(store.preview(bundle, capability)) << '\n';
    return 0;
  }
  if (options.command == "revoke") {
    if (options.scope)
      fail("revoke does not accept --scope");
    std::cout << grant::revocation_json(store.revoke(bundle, capability))
              << '\n';
    return 0;
  }
  if (options.command == "deny" && options.scope)
    fail("deny records the exact requested scope and does not accept --scope");
  const auto preview = store.preview(bundle, capability);
  confirm(options.command, preview, capability);
  std::optional<permission::Scope> scope;
  if (options.scope)
    scope = scope_value(capability, *options.scope);
  const auto decision = options.command == "grant"
                            ? permission::UserDecision::grant
                            : permission::UserDecision::deny;
  const auto result =
      store.decide(bundle, capability, scope, decision,
                   permission::DecisionActor::interactive_cli, wall_seconds(),
                   preview.expected_mutation_sequence);
  std::cout << grant::mutation_json(result) << '\n';
  return 0;
}

} // namespace

int main(int count, char **arguments) {
  try {
    return run(parse(count, arguments));
  } catch (const std::exception &error) {
    std::cerr << "omarchy-plugin-permission-store: " << error.what() << '\n';
    return 2;
  }
}
