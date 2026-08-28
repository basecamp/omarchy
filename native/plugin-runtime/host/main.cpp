#include <QCoreApplication>
#include <QDebug>
#include <QStringList>
#include <QTextStream>

#include "omarchy/plugin_runtime/Version.h"
#include "omarchy/plugin_runtime/launcher/launcher.h"

namespace {
int usage_error(const QString &argument) {
  qCritical().noquote() << "omarchy-plugin-host: unsupported argument:"
                        << argument;
  return 64;
}
} // namespace

int main(int argc, char *argv[]) {
  QCoreApplication application(argc, argv);
  application.setApplicationName(QStringLiteral("omarchy-plugin-host"));

  const QStringList arguments = application.arguments();
  if (arguments.size() == 2 && arguments.at(1) == QStringLiteral("--version")) {
    const auto version = omarchy::plugin_runtime::build_version();
    QTextStream(stdout) << "omarchy-plugin-host "
                        << QString::fromLatin1(version.data(), version.size())
                        << " envelope="
                        << omarchy::plugin_runtime::envelope_version() << '\n';
    return 0;
  }
  if (arguments.size() == 2 &&
      arguments.at(1) == QStringLiteral("--check-launch-prerequisites")) {
    auto supervisor =
        omarchy::plugin_runtime::launcher::Supervisor::production();
    std::string error;
    if (!supervisor.prerequisites(error)) {
      qCritical().noquote()
          << "omarchy-plugin-host: launcher prerequisites unavailable:"
          << QString::fromStdString(error);
      return 1;
    }
    qInfo() << "omarchy-plugin-host: launcher prerequisites available";
    return 0;
  }
  if (arguments.size() > 1) {
    return usage_error(arguments.at(1));
  }

  qInfo() << "omarchy-plugin-host: runtime skeleton active; plugin execution "
             "is unavailable";
  return application.exec();
}
