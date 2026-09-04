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
#include <vector>

#include <QVariantMap>

class QObject;
class QQmlComponent;
class QQuickItem;

namespace omarchy::plugin_runtime::worker {

namespace surface = omarchy::plugin_runtime::surface;

inline constexpr std::size_t kMaximumManifestBytes = 1024 * 1024;
inline constexpr std::size_t kMaximumQmlObjects = 4096;
inline constexpr std::size_t kMaximumEntryPathBytes = 512;
inline constexpr int kMaximumDecodedImageMiB = 64;

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
  invalid_runtime_api,
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
  explicit WorkerRuntime(std::filesystem::path source_root,
                         std::filesystem::path qt_import_root = {});
  ~WorkerRuntime();
  WorkerRuntime(const WorkerRuntime &) = delete;
  WorkerRuntime &operator=(const WorkerRuntime &) = delete;

  [[nodiscard]] RuntimeResult load_manifest_entry();
  // Scans plugin imports, then loads only exact registry-owned Qt probes before
  // the steady-state filter. Plugin QML is never instantiated here.
  [[nodiscard]] RuntimeResult prepare_trusted_qt_types();
  [[nodiscard]] RuntimeResult load_entry(std::string entry_path);
  [[nodiscard]] RuntimeResult load_surface_entry(std::string surface_name,
                                                 std::string entry_path);
  [[nodiscard]] RuntimeResult bind_surface(std::string_view surface_name,
                                           surface::SurfaceKey surface);
  [[nodiscard]] std::optional<surface::SurfaceKey>
  surface_key(std::string_view surface_name) const;
  [[nodiscard]] RuntimeResult bind_runtime_api(QObject &runtime_api);
  // Installs the already-validated, authority-free host presentation snapshot
  // exactly once before plugin QML is instantiated.
  [[nodiscard]] bool apply_presentation(const QVariantMap &presentation);
  [[nodiscard]] RuntimeResult
  select_software_profile(const surface::ProfileOffer &offer);
  [[nodiscard]] RuntimeResult
  allocate(const surface::TrustedAllocation &allocation,
           int mapping_descriptor);
  [[nodiscard]] RuntimeResult suspend(surface::SurfaceKey surface);
  [[nodiscard]] RuntimeResult resume(surface::SurfaceKey surface);
  [[nodiscard]] RuntimeResult release(surface::SurfaceKey surface);
  [[nodiscard]] RuntimeResult input(const surface::InputEvent &event);
  [[nodiscard]] bool can_deliver_surface_intent(
      std::string_view surface_name) const;
  [[nodiscard]] bool deliver_surface_intent(std::string_view surface_name,
                                            const QVariantMap &data);
  void request_render();
  [[nodiscard]] std::optional<PublishedFrame> render();
  [[nodiscard]] std::optional<surface::InputRegionUpdate>
  input_region_update(surface::SurfaceKey surface,
                      std::uint64_t generation) const;

  [[nodiscard]] bool loaded() const;
  [[nodiscard]] bool allocated() const;
  [[nodiscard]] bool active() const;
  [[nodiscard]] bool focused() const;
  [[nodiscard]] bool render_requested() const;
  [[nodiscard]] std::size_t object_count() const;
  [[nodiscard]] std::string root_object_name() const;
  [[nodiscard]] const std::string &last_error() const;

private:
  [[nodiscard]] RuntimeResult
  instantiate_entry(std::string entry_path,
                    std::unique_ptr<QQmlComponent> &component,
                    QQuickItem *&root_item);
  struct Impl;
  std::unique_ptr<Impl> implementation_;
};

[[nodiscard]] bool safe_relative_qml_path(std::string_view path);
[[nodiscard]] bool install_steady_state_seccomp(std::string &error);

} // namespace omarchy::plugin_runtime::worker
