#pragma once

#include <QImage>
#include <QQmlEngine>
#include <QQuickItem>

class HostFrameItem : public QQuickItem {
  Q_OBJECT
  QML_ELEMENT
  Q_PROPERTY(QImage frame READ frame NOTIFY frameChanged FINAL)
  Q_PROPERTY(QString frameDigest READ frameDigest NOTIFY frameChanged FINAL)
  Q_PROPERTY(QString lastError READ lastError NOTIFY lastErrorChanged FINAL)
  Q_PROPERTY(quint64 surfaceGeneration READ surfaceGeneration NOTIFY
                 surfaceGenerationChanged FINAL)

public:
  explicit HostFrameItem(QQuickItem *parent = nullptr);

  [[nodiscard]] QImage frame() const;
  [[nodiscard]] QString frameDigest() const;
  [[nodiscard]] QString lastError() const;
  [[nodiscard]] quint64 surfaceGeneration() const;

  Q_INVOKABLE bool configureSurface(int width, int height, qint64 offset);
  Q_INVOKABLE bool importFrameForTest(int fd, qint64 declaredLength,
                                      int declaredWidth, int declaredHeight);

signals:
  void frameChanged();
  void lastErrorChanged();
  void surfaceGenerationChanged();

private:
  bool reject(const QString &message);

  QSize m_surfaceSize;
  qint64 m_offset = 0;
  quint64 m_surfaceGeneration = 0;
  QImage m_frame;
  QString m_lastError;
};
