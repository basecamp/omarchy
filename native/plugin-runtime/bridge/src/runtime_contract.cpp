#include "omarchy/plugin_runtime/runtime_paths.hpp"

#include <QtCore/qglobal.h>

extern "C" Q_DECL_EXPORT const char *
omarchy_plugin_host_worker_path_v1() noexcept {
  return omarchy::plugin_runtime::kPackagedWorkerPath.data();
}
