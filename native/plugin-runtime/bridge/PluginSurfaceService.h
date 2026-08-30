#pragma once

#include "permission_contract.hpp"

#include <QAbstractListModel>
#include <QString>
#include <QtQml/qqmlregistration.h>

#include <cstdint>
#include <memory>
#include <string>
#include <vector>

namespace omarchy::plugin_runtime::bridge {

class RemotePluginSurface;

} // namespace omarchy::plugin_runtime::bridge

namespace omarchy::plugin_runtime::host_session {
class AdmittedSurfaceIntent;
}

namespace omarchy::plugin_runtime::bridge {

class PluginSurfaceBackend {
public:
  virtual ~PluginSurfaceBackend() = default;
  virtual bool attach(QStringView surface_key,
                      RemotePluginSurface &surface) = 0;
  virtual bool dismiss(QStringView surface_key) = 0;
};

class PluginSurfaceService : public QAbstractListModel {
  Q_OBJECT
  QML_ELEMENT
  Q_PROPERTY(bool available READ available NOTIFY availableChanged)
  Q_PROPERTY(QAbstractItemModel *barSurfaces READ barSurfaces CONSTANT)
  Q_PROPERTY(QAbstractItemModel *panelSurfaces READ panelSurfaces CONSTANT)
  Q_PROPERTY(QAbstractItemModel *overlaySurfaces READ overlaySurfaces CONSTANT)
  Q_PROPERTY(int count READ count NOTIFY surfacesChanged)

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
    QString screen_name;
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
    ScreenNameRole,
    InitiallyVisibleRole,
    MaximumWidthRole,
    MaximumHeightRole,
    DynamicInputRegionsRole,
    DefaultSectionRole,
  };

  explicit PluginSurfaceService(QObject *parent = nullptr);
  ~PluginSurfaceService() override;

  [[nodiscard]] bool available() const;
  [[nodiscard]] QAbstractItemModel *barSurfaces();
  [[nodiscard]] QAbstractItemModel *panelSurfaces();
  [[nodiscard]] QAbstractItemModel *overlaySurfaces();
  [[nodiscard]] int count() const;

  [[nodiscard]] int
  rowCount(const QModelIndex &parent = QModelIndex()) const override;
  [[nodiscard]] QVariant data(const QModelIndex &index,
                              int role = Qt::DisplayRole) const override;
  [[nodiscard]] QHash<int, QByteArray> roleNames() const override;

  Q_INVOKABLE bool attach(const QString &surface_key, QObject *surface);
  Q_INVOKABLE bool dismiss(const QString &surface_key);

  bool bindBackend(PluginSurfaceBackend &backend);
  void unbindBackend(PluginSurfaceBackend &backend);
  bool publishSurfaces(
      const plugins::permissions::ActivationBinding &binding,
      std::vector<SurfaceDeclaration> declarations, qulonglong revision);
  bool withdrawSurfaces(
      const plugins::permissions::ActivationBinding &binding);
  bool publishIntent(host_session::AdmittedSurfaceIntent intent);

signals:
  void availableChanged();
  void surfacesChanged();
  void openRequested(QString sourceSurface, QString targetSurface,
                     QString generation);
  void toggleRequested(QString sourceSurface, QString targetSurface,
                       QString generation);
  void dismissRequested(QString sourceSurface, QString targetSurface,
                        QString generation);

private:
  class RoleFilterModel;
  struct Publication;
  struct SurfaceRow;

  [[nodiscard]] const SurfaceRow *declared(QStringView surface_key) const;
  [[nodiscard]] bool onOwnerThread() const;
  [[nodiscard]] qsizetype firstRow(std::size_t publication_index) const;
  [[nodiscard]] std::vector<SurfaceRow>
  rowsFor(const Publication &publication) const;
  void clearSurfaces();

  PluginSurfaceBackend *backend_ = nullptr;
  std::vector<Publication> publications_;
  std::vector<SurfaceRow> surfaces_;
  std::unique_ptr<RoleFilterModel> bar_surfaces_;
  std::unique_ptr<RoleFilterModel> panel_surfaces_;
  std::unique_ptr<RoleFilterModel> overlay_surfaces_;
};

} // namespace omarchy::plugin_runtime::bridge
