#include <QCoreApplication>
#include <QProcess>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QStringList>

#include <iostream>
#include <memory>

#include "omarchy/plugin_runtime/Version.h"

namespace {
bool finishes(QProcess &process) {
  return process.waitForStarted(3000) && process.waitForFinished(3000);
}

int verify_version(const QString &program) {
  QProcess process;
  process.start(program, {QStringLiteral("--version")});
  if (!finishes(process) || process.exitStatus() != QProcess::NormalExit ||
      process.exitCode() != 0) {
    return 1;
  }
  const QByteArray output =
      process.readAllStandardOutput() + process.readAllStandardError();
  return output.contains(omarchy::plugin_runtime::build_version()) &&
                 output.contains("envelope=")
             ? 0
             : 1;
}
} // namespace

int main(int argc, char *argv[]) {
  QCoreApplication application(argc, argv);
  const QStringList arguments = application.arguments();
  if (arguments.size() < 2) {
    return 64;
  }

  const QString mode = arguments.at(1);
  if (mode == QStringLiteral("protocol")) {
    return omarchy::plugin_runtime::envelope_version() == 1 ? 0 : 1;
  }
  if (mode == QStringLiteral("versions") && arguments.size() == 4) {
    return verify_version(arguments.at(2)) == 0 &&
                   verify_version(arguments.at(3)) == 0
               ? 0
               : 1;
  }
  if (mode == QStringLiteral("worker-denial") && arguments.size() == 3) {
    QProcess process;
    process.start(arguments.at(2));
    if (!finishes(process)) {
      return 1;
    }
    return process.exitStatus() == QProcess::NormalExit &&
                   process.exitCode() == 78
               ? 0
               : 1;
  }
  if (mode == QStringLiteral("bridge") && arguments.size() == 3) {
    QQmlEngine engine;
    engine.addImportPath(arguments.at(2));
    QQmlComponent component(&engine);
    component.setData("import Omarchy.PluginHost 1.0\nPluginHostInfo {}\n",
                      QUrl());
    std::unique_ptr<QObject> object(component.create());
    if (!object) {
      for (const QQmlError &error : component.errors()) {
        std::cerr << error.toString().toStdString() << '\n';
      }
      return 1;
    }
    const auto version = omarchy::plugin_runtime::build_version();
    return !object->property("available").toBool() &&
                   object->property("runtimeVersion").toString() ==
                       QString::fromLatin1(version.data(), version.size())
               ? 0
               : 1;
  }

  return 64;
}
