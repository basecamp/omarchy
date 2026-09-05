#pragma once

#include <poll.h>

namespace omarchy::plugin_runtime::launcher {

[[nodiscard]] constexpr bool pidfd_has_exited(short revents) noexcept {
  return revents == POLLIN || revents == (POLLIN | POLLHUP);
}

class TerminationState {
public:
  [[nodiscard]] bool begin() noexcept {
    if (attempted_)
      return false;
    attempted_ = true;
    return true;
  }

  void complete(bool succeeded) noexcept {
    if (attempted_ && !completed_) {
      completed_ = true;
      succeeded_ = succeeded;
    }
  }

  [[nodiscard]] bool attempted() const noexcept { return attempted_; }
  [[nodiscard]] bool completed() const noexcept { return completed_; }
  [[nodiscard]] bool succeeded() const noexcept {
    return completed_ && succeeded_;
  }

private:
  bool attempted_ = false;
  bool completed_ = false;
  bool succeeded_ = false;
};

} // namespace omarchy::plugin_runtime::launcher
