#pragma once

#include "omarchy/plugin_runtime/runtime_paths.hpp"
#include "omarchy/plugin_runtime/sandbox/policy.h"

#include <cstddef>
#include <filesystem>
#include <stdexcept>
#include <string>
#include <utility>

namespace omarchy::plugin_runtime::sandbox::test_support {

inline SandboxPlan build_plan_for_worker(std::string worker_path) {
  const std::filesystem::path worker(worker_path);
  if (worker_path.empty() || !worker.is_absolute() ||
      worker.lexically_normal() != worker) {
    throw std::invalid_argument(
        "test worker path must be absolute and normalized");
  }

  SandboxPlan plan = build_plan();
  if (plan.argv.empty() || plan.argv.back() != "/runtime/worker") {
    throw std::logic_error("canonical worker executable changed");
  }

  std::size_t bind_source = plan.argv.size();
  std::size_t bind_count = 0;
  for (std::size_t index = 0; index + 2 < plan.argv.size(); ++index) {
    if (plan.argv.at(index) != "--ro-bind" ||
        plan.argv.at(index + 2) != "/runtime/worker") {
      continue;
    }
    if (plan.argv.at(index + 1) != kPackagedWorkerPath) {
      throw std::logic_error("canonical packaged-worker bind changed");
    }
    bind_source = index + 1;
    ++bind_count;
  }
  if (bind_count != 1) {
    throw std::logic_error("canonical packaged-worker bind is not unique");
  }

  plan.argv.at(bind_source) = std::move(worker_path);
  return plan;
}

} // namespace omarchy::plugin_runtime::sandbox::test_support
