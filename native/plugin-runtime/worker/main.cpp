#include <QCoreApplication>
#include <QDebug>
#include <QStringList>
#include <QTextStream>

#include "omarchy/plugin_runtime/Version.h"

int main(int argc, char *argv[]) {
  QCoreApplication application(argc, argv);
  application.setApplicationName(QStringLiteral("omarchy-plugin-qml-worker"));

  const QStringList arguments = application.arguments();
  if (arguments.size() == 2 && arguments.at(1) == QStringLiteral("--version")) {
    const auto version = omarchy::plugin_runtime::build_version();
    QTextStream(stdout) << "omarchy-plugin-qml-worker "
                        << QString::fromLatin1(version.data(), version.size())
                        << " envelope="
                        << omarchy::plugin_runtime::envelope_version() << '\n';
    return 0;
  }

  qCritical() << "omarchy-plugin-qml-worker: direct execution denied; no "
                 "trusted launcher is available";
  return 78;
}
