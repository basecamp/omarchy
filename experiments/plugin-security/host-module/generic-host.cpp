#include <QGuiApplication>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QQuickItem>

#include <cstdio>
#include <memory>

namespace {

int fail(const QString &message) {
  std::fprintf(stderr, "host-module-smoke: %s\n", qPrintable(message));
  return 1;
}

} // namespace

int main(int argc, char *argv[]) {
  QGuiApplication application(argc, argv);

  if (application.arguments().size() != 2) {
    return fail(
        QStringLiteral("usage: omarchy-plugin-host-smoke QML_IMPORT_ROOT"));
  }

  QQmlEngine engine;
  engine.addImportPath(application.arguments().at(1));

  QQmlComponent component(&engine);
  component.setData(R"(
import QtQuick
import Omarchy.PluginHost

HostProbeItem {}
)",
                    QUrl());

  if (component.status() != QQmlComponent::Ready) {
    return fail(component.errorString());
  }

  std::unique_ptr<QObject> object(component.create());
  if (object == nullptr) {
    return fail(QStringLiteral("native module returned a null object: %1")
                    .arg(component.errorString()));
  }

  auto *item = qobject_cast<QQuickItem *>(object.get());
  if (item == nullptr) {
    return fail(
        QStringLiteral("native module created %1 instead of a QQuickItem")
            .arg(QString::fromLatin1(object->metaObject()->className())));
  }

  const QString marker = item->property("probeMarker").toString();
  if (marker != QStringLiteral("omarchy-plugin-host-loaded")) {
    return fail(QStringLiteral("unexpected marker: %1").arg(marker));
  }

  std::fprintf(stdout,
               "host-module-smoke: imported Omarchy.PluginHost; marker=%s\n",
               qPrintable(marker));
  return 0;
}
