#pragma once

#include <filesystem>
#include <string>

namespace omarchy::plugins::migration {

enum class Format { json, markdown };

struct Result {
  bool ok = false;
  std::string output;
  std::string error;
};

[[nodiscard]] Result generate(const std::filesystem::path &legacy_plugin,
                              const std::filesystem::path &secure_target,
                              const std::filesystem::path &scanner,
                              Format format);

} // namespace omarchy::plugins::migration
