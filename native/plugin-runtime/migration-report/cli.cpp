#include "migration_report.hpp"

#include <QCoreApplication>

#include <cstdlib>
#include <filesystem>
#include <iostream>
#include <string_view>

int main(int argc, char **argv) {
  QCoreApplication application(argc, argv);
  if (argc != 4 || (std::string_view(argv[3]) != "json" &&
                    std::string_view(argv[3]) != "markdown")) {
    std::cerr << "usage: omarchy-plugin-migration-report-cli "
                 "<legacy-plugin> <secure-target> <json|markdown>\n";
    return 64;
  }
  const char *omarchy_path = std::getenv("OMARCHY_PATH");
  if (omarchy_path == nullptr || *omarchy_path == '\0') {
    std::cerr << "OMARCHY_PATH is required\n";
    return 78;
  }
  const auto format = std::string_view(argv[3]) == "json"
                          ? omarchy::plugins::migration::Format::json
                          : omarchy::plugins::migration::Format::markdown;
  const auto result = omarchy::plugins::migration::generate(
      argv[1], argv[2],
      std::filesystem::path(omarchy_path) /
          "bin/omarchy-plugin-security-scan",
      format);
  if (!result.ok) {
    std::cerr << "omarchy-plugin-migration-report: " << result.error << '\n';
    return 2;
  }
  std::cout << result.output;
  return 0;
}
