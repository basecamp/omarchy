#include "omarchy/plugin_runtime/providers/github_cli_backend.hpp"

#include <QProcess>
#include <QProcessEnvironment>

#include <sys/stat.h>
#include <unistd.h>

#include <cstring>
#include <utility>

namespace omarchy::plugin_runtime::providers {

GitHubCliBackend::GitHubCliBackend(std::filesystem::path program,
                                   std::filesystem::path state_root,
                                   std::uint32_t expected_owner)
    : program_(std::move(program)), state_root_(std::move(state_root)) {
  struct stat metadata {};
  available_ = program_.is_absolute() && state_root_.is_absolute() &&
               lstat(program_.c_str(), &metadata) == 0 &&
               S_ISREG(metadata.st_mode) && metadata.st_uid == expected_owner &&
               (metadata.st_mode & 0022) == 0 && access(program_.c_str(), X_OK) == 0;
}

bool GitHubCliBackend::available() const noexcept { return available_; }

GitHubBackend GitHubCliBackend::configuration() noexcept {
  return available_ ? GitHubBackend{.invoke = invoke, .context = this}
                    : GitHubBackend{};
}

bool GitHubCliBackend::invoke(std::string_view operation,
                              std::string_view argument,
                              std::span<std::byte> response,
                              std::size_t &written, void *opaque) noexcept {
  written = 0;
  try {
    auto &self = *static_cast<GitHubCliBackend *>(opaque);
    if (!self.available_ || response.empty()) return false;
    QProcess process;
    auto environment = QProcessEnvironment::systemEnvironment();
    environment.insert(QStringLiteral("OMARCHY_GITHUB_PROVIDER_STATE"),
                       QString::fromStdString(self.state_root_.string()));
    environment.remove(QStringLiteral("OMARCHY_GITHUB_ALLOW_LIVE_MUTATION"));
    process.setProcessEnvironment(environment);
    process.setProgram(QString::fromStdString(self.program_.string()));
    process.setArguments({QString::fromUtf8(operation),
                          QString::fromUtf8(argument)});
    process.start(QIODevice::ReadOnly);
    if (!process.waitForStarted(2000) || !process.waitForFinished(30000) ||
        process.exitStatus() != QProcess::NormalExit || process.exitCode() != 0)
      return false;
    const auto output = process.readAllStandardOutput().trimmed();
    if (output.isEmpty() || static_cast<std::size_t>(output.size()) > response.size())
      return false;
    std::memcpy(response.data(), output.constData(),
                static_cast<std::size_t>(output.size()));
    written = static_cast<std::size_t>(output.size());
    return true;
  } catch (...) {
    return false;
  }
}

} // namespace omarchy::plugin_runtime::providers
