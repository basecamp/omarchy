#include "audit_store.hpp"

#include <cstdlib>
#include <iostream>
#include <stdexcept>
#include <string>
#include <string_view>

namespace {

namespace audit = omarchy::plugins::audit;
namespace permissions = omarchy::plugins::permissions;

struct Options {
  std::filesystem::path store;
  std::string format = "human";
  std::optional<permissions::PluginId> plugin;
};

[[noreturn]] void fail(std::string_view message) {
  throw std::runtime_error(std::string(message));
}

std::filesystem::path default_store() {
  if (const auto *state = std::getenv("XDG_STATE_HOME");
      state != nullptr && *state != '\0')
    return std::filesystem::path(state) / "omarchy/plugin-security/audit";
  if (const auto *home = std::getenv("HOME"); home != nullptr && *home != '\0')
    return std::filesystem::path(home) /
           ".local/state/omarchy/plugin-security/audit";
  fail("HOME or XDG_STATE_HOME is required for the audit store");
}

void usage() {
  std::cout << "Usage: omarchy-plugin-audit-store [--plugin ID] "
               "[--format human|tsv] [--store DIR]\n"
               "\nShows trusted, redacted plugin security events. Plugin ID "
               "and revision are never abbreviated.\n";
}

Options parse(int count, char **arguments) {
  Options result{.store = default_store(), .format = "human", .plugin = {}};
  for (int index = 1; index < count; ++index) {
    const std::string_view argument(arguments[index]);
    const auto value = [&]() -> std::string_view {
      if (++index >= count)
        fail(std::string(argument) + " requires a value");
      return arguments[index];
    };
    if (argument == "--help" || argument == "-h") {
      usage();
      std::exit(0);
    }
    if (argument == "--store")
      result.store = value();
    else if (argument == "--plugin")
      result.plugin = permissions::PluginId(value());
    else if (argument == "--format") {
      result.format = value();
      if (result.format != "human" && result.format != "tsv")
        fail("--format must be human or tsv");
    } else
      fail("unknown audit option: " + std::string(argument));
  }
  return result;
}

int run(const Options &options) {
  audit::AuditStore store(options.store, {});
  audit::Query query;
  query.plugin = options.plugin;
  std::string output;
  const auto result = options.format == "human"
                          ? store.export_human(query, output)
                          : store.export_tsv(query, output);
  if (!result.ok())
    fail(result.detail);
  std::cout << output;
  return 0;
}

} // namespace

int main(int count, char **arguments) {
  try {
    return run(parse(count, arguments));
  } catch (const std::exception &error) {
    std::cerr << "omarchy-plugin-audit-store: " << error.what() << '\n';
    return 2;
  }
}
