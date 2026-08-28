#include "PluginHostInfo.h"

#include "omarchy/plugin_runtime/Version.h"

PluginHostInfo::PluginHostInfo(QObject *parent) : QObject(parent) {}

bool PluginHostInfo::available() const { return false; }

QString PluginHostInfo::runtimeVersion() const {
  const auto version = omarchy::plugin_runtime::build_version();
  return QString::fromLatin1(version.data(), version.size());
}
