#pragma once

#include "manifest_contract.hpp"

#include <sys/types.h>

#include <string>
#include <vector>

namespace omarchy::plugin_runtime::worker {

class SidecarSupervisor {
public:
  SidecarSupervisor() = default;
  SidecarSupervisor(const SidecarSupervisor &) = delete;
  SidecarSupervisor &operator=(const SidecarSupervisor &) = delete;
  ~SidecarSupervisor();

  [[nodiscard]] bool
  start(const std::vector<plugins::manifest::Runtime::Sidecar> &sidecars,
        std::string &error);
  [[nodiscard]] bool healthy(std::string &error);
  void terminate() noexcept;

private:
  struct Child {
    std::string name;
    pid_t pid = -1;
  };
  std::vector<Child> children_;
};

} // namespace omarchy::plugin_runtime::worker
