#pragma once

#include <QObject>
#include <QString>
#include <QtQml/qqmlregistration.h>

#include <chrono>
#include <cstdint>
#include <string>
#include <vector>

namespace omarchy::plugin_runtime::bridge {

class PluginManager;

// Owns the opaque public handle for one verified archive candidate. The exact
// revision never crosses into QML and can only be consumed by exact review.
class PluginInstallControl final : public QObject {
  Q_OBJECT
  QML_NAMED_ELEMENT(PluginInstallControl)
  QML_UNCREATABLE("PluginInstallControl is owned by PluginManager")

public:
  ~PluginInstallControl() override;

  Q_INVOKABLE QString begin(const QString &archive_path) noexcept;
  Q_INVOKABLE QString poll(const QString &operation_id) noexcept;
  Q_INVOKABLE QString beginReview(const QString &operation_id) noexcept;

private:
  enum class State : std::uint8_t { pending, succeeded, failed };
  struct Operation final {
    std::uint64_t serial = 0;
    std::string id;
    State state = State::pending;
    std::chrono::steady_clock::time_point touched;
    std::string plugin;
    std::string revision;
    std::string error;
    bool consumed = false;
  };

  explicit PluginInstallControl(PluginManager &manager);
  void complete(std::uint64_t serial, std::string plugin,
                std::string revision, std::string error) noexcept;
  void prune() noexcept;
  [[nodiscard]] Operation *find(const QString &operation_id) noexcept;

  PluginManager &manager_;
  std::vector<Operation> operations_;
  std::uint64_t next_serial_ = 1;

  friend class PluginManager;
};

} // namespace omarchy::plugin_runtime::bridge
