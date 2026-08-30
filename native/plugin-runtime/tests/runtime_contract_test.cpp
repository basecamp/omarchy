#include <QCoreApplication>
#include <QProcess>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QStringList>
#include <QtQml/qqml.h>

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
    return omarchy::plugin_runtime::envelope_version() == 2 ? 0 : 1;
  }
  if (mode == QStringLiteral("version") && arguments.size() == 3) {
    return verify_version(arguments.at(2));
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
    const auto version = omarchy::plugin_runtime::build_version();
    int remote_surface_type = -1;
    int plugin_manager_type = -1;
    bool first_engine_valid = false;
    bool same_engine_identity = false;
    bool competing_engine_excluded = false;
    {
      QQmlEngine engine;
      engine.addImportPath(arguments.at(2));
      QQmlComponent component(&engine);
      component.setData(
          "import QtQml\nimport Omarchy.PluginHost 1.0\n"
          "QtObject { property bool available: PluginManager.available; "
          "property string runtimeVersion: PluginManager.runtimeVersion; "
          "property int surfaceCount: PluginManager.count }\n",
          QUrl());
      std::unique_ptr<QObject> object(component.create());
      if (!object) {
        for (const QQmlError &error : component.errors())
          std::cerr << error.toString().toStdString() << '\n';
        return 1;
      }
      remote_surface_type =
          qmlTypeId("Omarchy.PluginHost", 1, 0, "RemotePluginSurface");
      plugin_manager_type =
          qmlTypeId("Omarchy.PluginHost", 1, 0, "PluginManager");
      auto *first_manager =
          engine.singletonInstance<QObject *>(plugin_manager_type);
      auto *second_manager =
          engine.singletonInstance<QObject *>(plugin_manager_type);
      same_engine_identity =
          first_manager != nullptr && first_manager == second_manager;
      QQmlComponent forbidden(&engine);
      forbidden.setData("import Omarchy.PluginHost 1.0\nPluginManager {}\n",
                        QUrl());
      std::unique_ptr<QObject> forbidden_object(forbidden.create());
      QQmlComponent internal_model(&engine);
      internal_model.setData(
          "import Omarchy.PluginHost 1.0\nSurfaceProjectionModel {}\n", QUrl());
      std::unique_ptr<QObject> internal_model_object(internal_model.create());
      first_engine_valid =
          !forbidden_object && !internal_model_object &&
          !object->property("available").toBool() &&
          object->property("surfaceCount").toInt() == 0 &&
          object->property("runtimeVersion").toString() ==
              QString::fromLatin1(version.data(), version.size());

      QQmlEngine competing_engine;
      competing_engine.addImportPath(arguments.at(2));
      competing_engine_excluded = competing_engine.singletonInstance<QObject *>(
                                      plugin_manager_type) == nullptr;
    }

    QQmlEngine replacement_engine;
    replacement_engine.addImportPath(arguments.at(2));
    QQmlComponent replacement(&replacement_engine);
    replacement.setData("import QtQml\nimport Omarchy.PluginHost 1.0\n"
                        "QtObject { property string runtimeVersion: "
                        "PluginManager.runtimeVersion }\n",
                        QUrl());
    std::unique_ptr<QObject> replacement_object(replacement.create());
    const bool replacement_valid =
        replacement_object &&
        replacement_object->property("runtimeVersion").toString() ==
            QString::fromLatin1(version.data(), version.size());
    if (remote_surface_type < 0 || plugin_manager_type < 0 ||
        !first_engine_valid || !same_engine_identity ||
        !competing_engine_excluded || !replacement_valid) {
      std::cerr << "bridge singleton contract failed: remote="
                << remote_surface_type << " manager=" << plugin_manager_type
                << " first=" << first_engine_valid
                << " same=" << same_engine_identity
                << " excluded=" << competing_engine_excluded
                << " replacement=" << replacement_valid << '\n';
      for (const QQmlError &error : replacement.errors())
        std::cerr << error.toString().toStdString() << '\n';
      return 1;
    }
    return 0;
  }

  return 64;
}
