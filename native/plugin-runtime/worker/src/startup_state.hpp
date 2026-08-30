#pragma once

#include <cstdint>

namespace omarchy::plugin_runtime::worker {

// One-way authority state for the worker's startup snapshot and QML load.
// No transition permits a second snapshot or recovery from a terminal error.
class StartupState final {
public:
  [[nodiscard]] bool begin_loading() noexcept {
    if (phase_ != Phase::awaiting_snapshot)
      return false;
    phase_ = Phase::loading;
    return true;
  }

  [[nodiscard]] bool finish_loading() noexcept {
    if (phase_ != Phase::loading)
      return false;
    phase_ = Phase::loaded;
    return true;
  }

  // Returns true only for the first terminal transition, allowing fatal paths
  // to emit one diagnostic and request one event-loop exit.
  [[nodiscard]] bool terminate() noexcept {
    if (phase_ == Phase::terminal)
      return false;
    phase_ = Phase::terminal;
    return true;
  }

  [[nodiscard]] bool loading() const noexcept {
    return phase_ == Phase::loading;
  }
  [[nodiscard]] bool loaded() const noexcept {
    return phase_ == Phase::loaded;
  }
  [[nodiscard]] bool terminal() const noexcept {
    return phase_ == Phase::terminal;
  }

private:
  enum class Phase : std::uint8_t {
    awaiting_snapshot,
    loading,
    loaded,
    terminal,
  };
  Phase phase_ = Phase::awaiting_snapshot;
};

} // namespace omarchy::plugin_runtime::worker
