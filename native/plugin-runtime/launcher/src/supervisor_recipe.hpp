#pragma once

#include "omarchy/plugin_runtime/launcher/launcher.h"
#include "process_cleanup.hpp"

#include <memory>
#include <string>
#include <utility>

namespace omarchy::plugin_runtime::launcher::detail {

struct ExecutableRequirement final {
  std::string path;
  uid_t owner = 0;
};

struct SupervisorRecipe final {
  ExecutableRequirement bwrap;
  ExecutableRequirement worker;
  sandbox::SandboxPlan plan;
  std::shared_ptr<ResourceScopeController> resource_scope;
  std::shared_ptr<ProcessScopeReaper> reaper;
};

} // namespace omarchy::plugin_runtime::launcher::detail

namespace omarchy::plugin_runtime::launcher {

struct Supervisor::Impl final {
  explicit Impl(detail::SupervisorRecipe recipe_value)
      : recipe(std::move(recipe_value)) {}

  detail::SupervisorRecipe recipe;
};

namespace detail {

class SupervisorAssembler final {
public:
  [[nodiscard]] static Supervisor assemble(SupervisorRecipe recipe) {
    return Supervisor(std::make_unique<Supervisor::Impl>(std::move(recipe)));
  }
};

} // namespace detail
} // namespace omarchy::plugin_runtime::launcher
