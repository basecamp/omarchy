#include "grant_store.hpp"

#include <algorithm>
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
  std::string format = "json";
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
         << "  omarchy-plugin-permission review BINDING REQUESTS\n"
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
            "resources:ID,ID:OP,OP\n"
         << "Read-only list/diff accept --format json|human. Review requires "
            "an interactive terminal only when authority changed.\n";
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
    else if (argument == "--format") {
      options.format = take_value(index, count, arguments, argument);
      if (options.format != "json" && options.format != "human")
        fail("--format must be json or human");
    } else if (argument == "--yes" || argument == "-y")
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

std::string capability_title(const permission::CapabilityKey &capability) {
  const auto id = capability.id.view();
  if (id == "storage.private")
    return "Private plugin storage";
  if (id == "notifications.send")
    return "Desktop notifications";
  if (id == "audio.play-cue")
    return "Named audio cues";
  if (id == "service.fake-status")
    return "Test status service";
  return std::string(id);
}

std::string scope_text(const permission::Scope &scope) {
  if (const auto *quota = std::get_if<permission::QuotaScope>(&scope))
    return "up to " + std::to_string(quota->total_bytes) + " bytes total and " +
           std::to_string(quota->item_bytes) + " bytes per item";
  if (const auto *tokens = std::get_if<permission::TokenScope>(&scope)) {
    std::string result = "only: ";
    for (std::size_t index = 0; index < tokens->tokens.size(); ++index) {
      if (index > 0)
        result += ", ";
      result += tokens->tokens.values()[index].view();
    }
    return result;
  }
  if (const auto *resources = std::get_if<permission::ResourceScope>(&scope)) {
    return std::to_string(resources->resources.size()) +
           " named resource(s), " +
           std::to_string(resources->operations.size()) +
           " allowed operation(s)";
  }
  return "no additional scope";
}

std::string change_text(permission::DeltaKind kind) {
  switch (kind) {
  case permission::DeltaKind::added:
    return "NEW";
  case permission::DeltaKind::expanded:
    return "EXPANDED";
  case permission::DeltaKind::narrowed:
    return "NARROWED";
  case permission::DeltaKind::removed:
    return "REMOVED";
  case permission::DeltaKind::requirement_changed:
    return "REQUIRED/OPTIONAL CHANGED";
  case permission::DeltaKind::incomparable:
    return "CHANGED";
  case permission::DeltaKind::unchanged:
    return "UNCHANGED";
  }
  return "UNKNOWN";
}

const permission::CapabilityRequest *
request_for(const grant::RequestBundle &bundle,
            const permission::CapabilityKey &capability) {
  const auto found = std::find_if(
      bundle.requests.values().begin(), bundle.requests.values().end(),
      [&](const auto &request) { return request.capability == capability; });
  return found == bundle.requests.values().end() ? nullptr : &*found;
}

bool requires_decision(permission::DeltaKind kind) {
  return kind == permission::DeltaKind::added ||
         kind == permission::DeltaKind::expanded ||
         kind == permission::DeltaKind::incomparable ||
         kind == permission::DeltaKind::requirement_changed;
}

void print_review(std::ostream &output, const grant::Preview &preview,
                  const grant::RequestBundle &bundle) {
  output << "Plugin permission review\n"
         << "  Plugin ID: " << preview.binding.plugin.view() << '\n'
         << "  Revision: " << preview.binding.revision.view() << '\n'
         << "  Policy: " << preview.binding.policy_fingerprint.view() << '\n'
         << "  Generation: " << preview.binding.generation << '\n'
         << "  Target: "
         << (preview.target == grant::TargetRevision::active ? "active"
                                                             : "candidate")
         << "\n\n";
  const auto deltas = preview.request_delta;
  for (const auto &delta : deltas.values()) {
    const auto *request = request_for(bundle, delta.capability);
    output << "  [" << change_text(delta.kind) << "] "
           << capability_title(delta.capability) << " ("
           << delta.capability.id.view() << '@' << delta.capability.version
           << ")\n"
           << "    Choice: "
           << (request == nullptr  ? "removed"
               : request->required ? "required"
                                   : "optional")
           << '\n';
    if (request != nullptr)
      output << "    Scope: " << scope_text(request->scope) << '\n';
    output << "    Prior grant inherited: "
           << (delta.inherited_grant ? "yes" : "no") << '\n';
  }
}

void review(grant::GrantStore &store, const grant::RequestBundle &bundle) {
  if (bundle.requests.empty())
    fail("review requires at least one declared permission request");
  auto preview = store.preview(bundle, bundle.requests[0].capability);
  print_review(std::cerr, preview, bundle);
  const bool changed = std::ranges::any_of(
      preview.request_delta.values(),
      [](const auto &delta) { return requires_decision(delta.kind); });
  if (!changed) {
    std::cout << "No new or expanded authority requires a decision.\n";
    return;
  }
  if (isatty(STDIN_FILENO) == 0 || isatty(STDERR_FILENO) == 0)
    fail("permission review requires an interactive terminal; unattended "
         "installs and updates cannot choose grants");
  const auto deltas = preview.request_delta;
  std::vector<std::pair<permission::CapabilityKey,
                        permission::UserDecision>>
      decisions;
  for (const auto &delta : deltas.values()) {
    if (!requires_decision(delta.kind))
      continue;
    const auto *request = request_for(bundle, delta.capability);
    if (request == nullptr)
      fail("decision-bearing permission is absent from the candidate");
    std::cerr << "Type grant or deny for " << delta.capability.id.view() << '@'
              << delta.capability.version << " ("
              << (request->required ? "required" : "optional") << "): ";
    std::string answer;
    if (!std::getline(std::cin, answer) ||
        (answer != "grant" && answer != "deny"))
      fail("permission review cancelled; type exactly grant or deny");
    decisions.emplace_back(
        delta.capability, answer == "grant" ? permission::UserDecision::grant
                                             : permission::UserDecision::deny);
  }
  for (const auto &[capability, decision] : decisions) {
    preview = store.preview(bundle, capability);
    (void)store.decide(bundle, capability, std::nullopt, decision,
                       permission::DecisionActor::interactive_cli,
                       wall_seconds(), preview.expected_mutation_sequence);
  }
  std::cout << "Permission review recorded for exact plugin revision and "
               "policy.\n";
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
    const auto state = filter_state(store.read(), options.filter_plugin);
    if (options.format == "json")
      std::cout << grant::state_json(state) << '\n';
    else
      std::cout << "Permission state: " << state.plugins.size()
                << " plugin(s), " << state.decisions.size()
                << " explicit decision(s). Use --format json for exact "
                   "bindings.\n";
    return 0;
  }
  if (options.command != "diff" && options.command != "grant" &&
      options.command != "deny" && options.command != "revoke" &&
      options.command != "review")
    fail("command must be list, diff, review, grant, deny, or revoke");
  const auto bundle = bundle_from(options);
  if (options.command == "review") {
    if (!options.capability.empty() || options.scope)
      fail("review covers the complete request set and does not accept "
           "--capability or --scope");
    review(store, bundle);
    return 0;
  }
  if (options.capability.empty())
    fail("--capability ID@VERSION is required");
  const auto capability = capability_key(options.capability);
  if (options.command == "diff") {
    const auto preview = store.preview(bundle, capability);
    if (options.format == "json")
      std::cout << grant::preview_json(preview) << '\n';
    else
      print_review(std::cout, preview, bundle);
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
