#include <QDir>
#include <QElapsedTimer>
#include <QEventLoop>
#include <QGuiApplication>
#include <QImage>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QQuickItem>
#include <QQuickRenderControl>
#include <QQuickRenderTarget>
#include <QQuickWindow>
#include <QSGRendererInterface>
#include <QTimer>

#include <cstdio>
#include <memory>

namespace {

void waitForAnimationFrame() {
  QEventLoop loop;
  QTimer::singleShot(40, &loop, &QEventLoop::quit);
  loop.exec();
}

int fail(const QString &message) {
  std::fprintf(stderr, "%s\n", qPrintable(message));
  return 1;
}

} // namespace

int main(int argc, char *argv[]) {
  qputenv("QT_QPA_PLATFORM", "offscreen");
  qputenv("QT_QPA_PLATFORMTHEME", "none");
  qputenv("QSG_RHI_BACKEND", "software");
  qputenv("QSG_SOFTWARE_RENDERER_FORCE_PARTIAL_UPDATES", "0");
  QQuickWindow::setGraphicsApi(QSGRendererInterface::Software);

  QGuiApplication app(argc, argv);

  if (app.arguments().size() != 3) {
    return fail(QStringLiteral(
        "usage: omarchy-plugin-render-spike SCENE.qml OUTPUT_DIRECTORY"));
  }

  constexpr int logicalWidth = 320;
  constexpr int logicalHeight = 96;
  constexpr int frameCount = 6;

  const QString scenePath = QFileInfo(app.arguments().at(1)).absoluteFilePath();
  QDir outputDirectory(app.arguments().at(2));
  if (!outputDirectory.mkpath(QStringLiteral("."))) {
    return fail(QStringLiteral("cannot create output directory: %1")
                    .arg(outputDirectory.absolutePath()));
  }

  QImage frame(logicalWidth, logicalHeight,
               QImage::Format_RGBA8888_Premultiplied);
  frame.fill(Qt::transparent);

  QQuickRenderControl renderControl;
  QQuickWindow window(&renderControl);
  window.setColor(Qt::transparent);
  window.setGeometry(0, 0, logicalWidth, logicalHeight);

  QQmlEngine engine;
  QQmlComponent component(&engine, QUrl::fromLocalFile(scenePath));
  if (component.isError()) {
    return fail(component.errorString());
  }

  std::unique_ptr<QObject> rootObject(component.create());
  auto *rootItem = qobject_cast<QQuickItem *>(rootObject.get());
  if (rootItem == nullptr) {
    return fail(QStringLiteral("scene root must be a QQuickItem"));
  }

  rootItem->setParentItem(window.contentItem());
  rootItem->setSize(QSizeF(logicalWidth, logicalHeight));

  window.setRenderTarget(QQuickRenderTarget::fromPaintDevice(&frame));

  qint64 renderNanoseconds = 0;

  for (int frameNumber = 0; frameNumber < frameCount; ++frameNumber) {
    waitForAnimationFrame();
    app.processEvents();
    frame.fill(Qt::transparent);
    QElapsedTimer renderTimer;
    renderTimer.start();
    renderControl.polishItems();
    renderControl.sync();
    renderControl.render();
    renderNanoseconds += renderTimer.nsecsElapsed();

    if (qAlpha(frame.pixel(0, 0)) != 0 ||
        qAlpha(frame.pixel(logicalWidth / 2, logicalHeight / 2)) != 255) {
      return fail(QStringLiteral(
          "rendered frame lost expected transparent or opaque regions"));
    }

    const QString outputPath = outputDirectory.filePath(
        QStringLiteral("frame-%1.png")
            .arg(frameNumber, 3, 10, QLatin1Char('0')));
    if (!frame.save(outputPath)) {
      return fail(
          QStringLiteral("cannot save rendered frame: %1").arg(outputPath));
    }
  }

  const qsizetype bytesPerFrame = frame.sizeInBytes();
  std::fprintf(stdout,
               "frames=%d distinct_check=external size=%dx%d "
               "format=rgba8888-premultiplied bytes_per_frame=%lld "
               "average_render_ms=%.3f\n",
               frameCount, logicalWidth, logicalHeight,
               static_cast<long long>(bytesPerFrame),
               static_cast<double>(renderNanoseconds) /
                   static_cast<double>(frameCount) / 1000000.0);

  return 0;
}
