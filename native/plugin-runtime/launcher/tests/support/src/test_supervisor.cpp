#include "omarchy/plugin_runtime/launcher/test_supervisor.h"

#include "omarchy/plugin_runtime/sandbox/test_plan.h"
#include "bus_connection.hpp"
#include "supervisor_recipe.hpp"

#include <sys/stat.h>
#include <systemd/sd-bus.h>

#include <memory>
#include <stdexcept>
#include <utility>

namespace omarchy::plugin_runtime::launcher::test_support {
namespace {

std::shared_ptr<detail::ProcessScopeReaper> test_process_reaper() {
  static const auto reaper =
      std::make_shared<detail::ProcessScopeReaper>(false);
  return reaper;
}

uid_t exact_owner(const std::string &path) {
  struct stat metadata {};
  if (lstat(path.c_str(), &metadata) < 0) {
    throw std::runtime_error("test executable metadata is unavailable");
  }
  return metadata.st_uid;
}

Supervisor assemble(std::string bwrap_path, uid_t bwrap_owner,
                    std::string worker_path, uid_t worker_owner,
                    std::shared_ptr<ResourceScopeController> resource_scope,
                    bool force_reaper_start_failure) {
  detail::SupervisorRecipe recipe{
      .bwrap = {.path = std::move(bwrap_path), .owner = bwrap_owner},
      .worker = {.path = worker_path, .owner = worker_owner},
      .plan = sandbox::test_support::build_plan_for_worker(
          std::move(worker_path)),
      .resource_scope = std::move(resource_scope),
      .reaper = force_reaper_start_failure
                    ? std::make_shared<detail::ProcessScopeReaper>(true)
                    : test_process_reaper()};
  return detail::SupervisorAssembler::assemble(std::move(recipe));
}

} // namespace

Supervisor make_supervisor(
    std::string bwrap_path, std::string worker_path,
    std::shared_ptr<ResourceScopeController> resource_scope,
    bool force_reaper_start_failure) {
  const uid_t bwrap_owner = exact_owner(bwrap_path);
  const uid_t worker_owner = exact_owner(worker_path);
  return assemble(std::move(bwrap_path), bwrap_owner, std::move(worker_path),
                  worker_owner, std::move(resource_scope),
                  force_reaper_start_failure);
}

bool connect_bus(std::string_view address, Deadline deadline,
                 std::string &error) noexcept {
  sd_bus *bus = detail::connect_bus(address, deadline, error);
  if (!bus)
    return false;
  sd_bus_close_unref(bus);
  return true;
}

} // namespace omarchy::plugin_runtime::launcher::test_support
