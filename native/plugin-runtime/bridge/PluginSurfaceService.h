#pragma once

#include <QObject>
#include <QString>
#include <QVariantList>
#include <QtQml/qqmlregistration.h>

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

class PluginSurfaceService : public QObject {
  Q_OBJECT
  QML_ELEMENT
  Q_PROPERTY(bool available READ available NOTIFY availableChanged)
  Q_PROPERTY(QVariantList surfaces READ surfaces NOTIFY surfacesChanged)
  Q_PROPERTY(qulonglong revision READ revision NOTIFY surfacesChanged)

public:
  enum class Role {
    bar,
    panel,
    overlay,
  };
  Q_ENUM(Role)

  explicit PluginSurfaceService(QObject *parent = nullptr);

  [[nodiscard]] bool available() const;
  [[nodiscard]] QVariantList surfaces() const;
  [[nodiscard]] qulonglong revision() const;

  Q_INVOKABLE bool attach(const QString &surface_key, QObject *surface);
  Q_INVOKABLE bool dismiss(const QString &surface_key);

  bool bindBackend(PluginSurfaceBackend &backend);
  void unbindBackend(PluginSurfaceBackend &backend);
  bool publishSurfaces(const QVariantList &surfaces, qulonglong revision);
  bool publishIntent(host_session::AdmittedSurfaceIntent intent);

signals:
  void availableChanged();
  void surfacesChanged();
  void openRequested(QString sourceSurface, QString targetSurface,
                     qulonglong generation);
  void toggleRequested(QString sourceSurface, QString targetSurface,
                       qulonglong generation);
  void dismissRequested(QString sourceSurface, QString targetSurface,
                        qulonglong generation);

private:
  [[nodiscard]] bool declared(QStringView surface_key) const;

  PluginSurfaceBackend *backend_ = nullptr;
  QVariantList surfaces_;
  qulonglong revision_ = 0;
};

} // namespace omarchy::plugin_runtime::bridge
