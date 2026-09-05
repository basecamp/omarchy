#pragma once

#include "SurfaceEndpointOwner.h"
#include "permission_contract.hpp"

#include <QAbstractListModel>
#include <QString>

#include <cstdint>
#include <memory>
#include <optional>
#include <string>
#include <vector>

namespace omarchy::plugin_runtime::host_session {
class AdmittedSurfaceIntent;
}

namespace omarchy::plugin_runtime::bridge {

class PluginManager;
namespace detail {
class PluginRuntimeController;
}
#ifdef OMARCHY_PLUGIN_MANAGER_TESTING
class SurfaceProjectionModelTestAccess;
#endif

// Internal projection model. Host publication and attachment are owned
// by the singleton PluginManager; this type is deliberately not a QML type.
class SurfaceProjectionModel : public QAbstractListModel {
  Q_OBJECT

public:
  enum class Role : std::uint8_t { Bar, Panel, Overlay };
  Q_ENUM(Role)

  enum class BarSection : std::uint8_t {
    Unspecified,
    Left,
    Center,
    Right,
  };
  Q_ENUM(BarSection)

  // Manifest policy has already been parsed and bounded before this trusted
  // value reaches the shell adapter. Identity is deliberately absent: the
  // service derives it from the exact activation binding and surface name.
  struct SurfaceDeclaration {
    std::string surface_name;
    Role role = Role::Panel;
    bool initially_visible = false;
    std::uint32_t maximum_width = 0;
    std::uint32_t maximum_height = 0;
    bool dynamic_input_regions = false;
    BarSection default_bar_section = BarSection::Unspecified;

    bool operator==(const SurfaceDeclaration &) const = default;
  };

  enum ModelRole {
    SurfaceKeyRole = Qt::UserRole + 1,
    PluginIdRole,
    SurfaceNameRole,
    SurfaceRoleRole,
    GenerationRole,
    PublicationRevisionRole,
    InitiallyVisibleRole,
    MaximumWidthRole,
    MaximumHeightRole,
    DynamicInputRegionsRole,
    DefaultSectionRole,
  };

  ~SurfaceProjectionModel() override;

  [[nodiscard]] QAbstractItemModel *barSurfaces();
  [[nodiscard]] QAbstractItemModel *panelSurfaces();
  [[nodiscard]] QAbstractItemModel *overlaySurfaces();
  [[nodiscard]] int count() const;

  [[nodiscard]] int
  rowCount(const QModelIndex &parent = QModelIndex()) const override;
  [[nodiscard]] QVariant data(const QModelIndex &index,
                              int role = Qt::DisplayRole) const override;
  [[nodiscard]] QHash<int, QByteArray> roleNames() const override;

signals:
  void surfacesChanged();
  void openRequested(QString sourceSurface, QString targetSurface,
                     QString generation, QString inputSequence,
                     QString requestedOutput);
  void toggleRequested(QString sourceSurface, QString targetSurface,
                       QString generation, QString inputSequence,
                       QString requestedOutput);
  void dismissRequested(QString sourceSurface, QString targetSurface,
                        QString generation, QString inputSequence);

private:
  explicit SurfaceProjectionModel(QObject *parent = nullptr);
  bool publishSurfaces(
      const plugins::permissions::ActivationBinding &binding,
      std::vector<SurfaceDeclaration> declarations, qulonglong revision);
  bool withdrawSurfaces(
      const plugins::permissions::ActivationBinding &binding);
  bool publishIntent(host_session::AdmittedSurfaceIntent intent);
  [[nodiscard]] std::optional<PublishedSurfaceAttachment>
  resolve(QStringView surface_key) const;

  class RoleFilterModel;
  struct Publication;
  struct SurfaceRow;

  [[nodiscard]] const SurfaceRow *declared(QStringView surface_key) const;
  [[nodiscard]] bool onOwnerThread() const;
  [[nodiscard]] qsizetype firstRow(std::size_t publication_index) const;
  [[nodiscard]] std::vector<SurfaceRow>
  rowsFor(const Publication &publication) const;

  std::vector<Publication> publications_;
  std::vector<SurfaceRow> surfaces_;
  std::unique_ptr<RoleFilterModel> bar_surfaces_;
  std::unique_ptr<RoleFilterModel> panel_surfaces_;
  std::unique_ptr<RoleFilterModel> overlay_surfaces_;

  friend class PluginManager;
  friend class detail::PluginRuntimeController;
#ifdef OMARCHY_PLUGIN_MANAGER_TESTING
  friend class SurfaceProjectionModelTestAccess;
#endif
};

#ifdef OMARCHY_PLUGIN_MANAGER_TESTING
class SurfaceProjectionModelTestAccess final {
public:
  struct Resolved final {
    QString key;
    plugins::permissions::ActivationBinding binding;
    std::string surface_name;
    qulonglong revision = 0;
  };
  [[nodiscard]] static bool publish(
      PluginManager &manager,
      const plugins::permissions::ActivationBinding &binding,
      std::vector<SurfaceProjectionModel::SurfaceDeclaration> declarations,
      qulonglong revision);
  [[nodiscard]] static bool
  withdraw(PluginManager &manager,
           const plugins::permissions::ActivationBinding &binding);
  [[nodiscard]] static std::optional<Resolved>
  resolve(const SurfaceProjectionModel &model, QStringView key) {
    auto value = model.resolve(key);
    if (!value)
      return std::nullopt;
    return Resolved{.key = value->surface_key_,
                    .binding = value->binding_,
                    .surface_name = value->declared_surface_,
                    .revision = value->publication_revision_};
  }
};
#endif

} // namespace omarchy::plugin_runtime::bridge
