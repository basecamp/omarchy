#pragma once

#include <QObject>
#include <QString>
#include <QtQml/qqmlregistration.h>

class PluginHostInfo : public QObject {
  Q_OBJECT
  QML_ELEMENT
  Q_PROPERTY(bool available READ available CONSTANT)
  Q_PROPERTY(QString runtimeVersion READ runtimeVersion CONSTANT)

public:
  explicit PluginHostInfo(QObject *parent = nullptr);

  [[nodiscard]] bool available() const;
  [[nodiscard]] QString runtimeVersion() const;
};
