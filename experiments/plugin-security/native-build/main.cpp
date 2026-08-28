#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQuickRenderControl>
#include <QtGlobal>

#include <cstdio>

int main(int argc, char *argv[]) {
  QGuiApplication application(argc, argv);
  QQuickRenderControl renderControl;
  QQmlApplicationEngine engine;

  QObject::connect(
      &engine, &QQmlApplicationEngine::objectCreationFailed, &application,
      []() { QCoreApplication::exit(1); }, Qt::QueuedConnection);

  engine.loadFromModule("Omarchy.PluginSecurity.NativeBuild", "Main");

  if (engine.rootObjects().isEmpty()) {
    std::fprintf(
        stderr,
        "native-build-probe: QML module did not create a root object\n");
    return 1;
  }

  std::fprintf(stdout,
               "native-build-probe: Qt %s; QQuickRenderControl linked; QML "
               "module loaded\n",
               qVersion());

  return application.exec();
}
