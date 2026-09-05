#pragma once

#include <QQmlAbstractUrlInterceptor>

#include <filesystem>
#include <string>
#include <string_view>

class QQmlEngine;

namespace omarchy::plugin_runtime::worker {

struct RuntimeResult;

// Owns the deny-by-default boundary between plugin-packaged sources and Qt's
// trusted QML modules. The policy must outlive every engine it configures.
class PluginSourcePolicy final : private QQmlAbstractUrlInterceptor {
public:
  explicit PluginSourcePolicy(std::filesystem::path source_root,
                              std::filesystem::path qt_import_root = {});

  void configure(QQmlEngine &engine);
  [[nodiscard]] RuntimeResult validate_tree() const;
  [[nodiscard]] RuntimeResult preload_trusted_modules(QQmlEngine &engine) const;
  [[nodiscard]] const std::filesystem::path &root() const;

  [[nodiscard]] static bool valid_entry_path(std::string_view path);

private:
  [[nodiscard]] QUrl intercept(const QUrl &url, DataType type) override;
  [[nodiscard]] static QUrl denied_url();
  [[nodiscard]] RuntimeResult inspect_tree() const;

  std::filesystem::path source_root_;
  std::filesystem::path qt_import_root_;
};

} // namespace omarchy::plugin_runtime::worker
