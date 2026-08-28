#pragma once

#include <QQmlEngine>
#include <QQuickItem>

class HostProbeItem : public QQuickItem {
  Q_OBJECT
  QML_ELEMENT
  Q_PROPERTY(QString probeMarker READ probeMarker CONSTANT FINAL)

public:
  explicit HostProbeItem(QQuickItem *parent = nullptr);

  [[nodiscard]] QString probeMarker() const;
};
