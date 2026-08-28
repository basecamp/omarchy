#pragma once

#include "omarchy/plugin_runtime/surface/frame_transport.hpp"
#include "omarchy/plugin_runtime/surface/input.hpp"
#include "omarchy/plugin_runtime/surface/surface_state.hpp"

#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <memory>
#include <optional>
#include <string>
#include <string_view>

namespace omarchy::plugin_runtime::worker {

namespace surface = omarchy::plugin_runtime::surface;

inline constexpr std::size_t kMaximumManifestBytes = 1024 * 1024;
inline constexpr std::size_t kMaximumQmlObjects = 4096;
inline constexpr std::size_t kMaximumEntryPathBytes = 512;

enum class RuntimeFailure {
  none,
  invalid_source_root,
  manifest_missing,
  manifest_oversized,
  manifest_invalid,
  entry_path_invalid,
  entry_missing,
  qml_load_failed,
  root_not_item,
  object_limit,
  profile_not_selected,
  surface_already_allocated,
  allocation_invalid,
  mapping_invalid,
  render_failed,
  stale_surface,
  invalid_transition,
  invalid_input,
};

struct RuntimeResult {
  RuntimeFailure failure = RuntimeFailure::none;
  std::string detail;

  [[nodiscard]] explicit operator bool() const {
    return failure == RuntimeFailure::none;
  }
};

struct PublishedFrame {
  surface::FrameReady ready{};
  std::uint64_t rendered_objects = 0;
};

class WorkerRuntime {
public:
  explicit WorkerRuntime(std::filesystem::path source_root);
  ~WorkerRuntime();
  WorkerRuntime(const WorkerRuntime &) = delete;
  WorkerRuntime &operator=(const WorkerRuntime &) = delete;

  [[nodiscard]] RuntimeResult load_manifest_entry();
  [[nodiscard]] RuntimeResult load_entry(std::string entry_path);
  [[nodiscard]] RuntimeResult
  select_software_profile(const surface::ProfileOffer &offer);
  [[nodiscard]] RuntimeResult
  allocate(const surface::TrustedAllocation &allocation,
           int mapping_descriptor);
  [[nodiscard]] RuntimeResult suspend(surface::SurfaceKey surface);
  [[nodiscard]] RuntimeResult resume(surface::SurfaceKey surface);
  [[nodiscard]] RuntimeResult release(surface::SurfaceKey surface);
  [[nodiscard]] RuntimeResult focus(const surface::FocusEvent &event);
  [[nodiscard]] RuntimeResult input(const surface::InputEvent &event);
  [[nodiscard]] std::optional<PublishedFrame> render();

  [[nodiscard]] bool loaded() const;
  [[nodiscard]] bool allocated() const;
  [[nodiscard]] bool active() const;
  [[nodiscard]] bool focused() const;
  [[nodiscard]] bool render_requested() const;
  [[nodiscard]] std::size_t object_count() const;
  [[nodiscard]] const std::string &last_error() const;

private:
  struct Impl;
  std::unique_ptr<Impl> implementation_;
};

[[nodiscard]] bool safe_relative_qml_path(std::string_view path);
[[nodiscard]] bool install_steady_state_seccomp(std::string &error);

} // namespace omarchy::plugin_runtime::worker
