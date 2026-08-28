#include "migration_report.hpp"

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>

#include <filesystem>
#include <iostream>
#include <string>
#include <string_view>
#include <vector>

namespace {

struct Case {
  std::string legacy;
  std::string target;
  std::string plugin;
  std::vector<std::string> findings;
  std::vector<std::string> capabilities;
  std::string surface;
};

int failures = 0;

void check(bool condition, std::string_view message) {
  if (!condition) {
    std::cerr << "FAIL: " << message << '\n';
    ++failures;
  }
}

bool sha256(const QString &value) {
  if (value.size() != 64) {
    return false;
  }
  for (const QChar character : value) {
    if (!((character.unicode() >= '0' && character.unicode() <= '9') ||
          (character.unicode() >= 'a' && character.unicode() <= 'f'))) {
      return false;
    }
  }
  return true;
}

bool contains_id(const QJsonArray &array, std::string_view id) {
  for (const QJsonValue &value : array) {
    if (value.toObject().value("id").toString().toStdString() == id) {
      return true;
    }
  }
  return false;
}

bool contains_capability(const QJsonArray &array, std::string_view capability) {
  for (const QJsonValue &value : array) {
    if (value.toObject().value("capability").toString().toStdString() ==
        capability) {
      return true;
    }
  }
  return false;
}

void run_case(const Case &item) {
  const std::filesystem::path legacy_root =
      std::filesystem::path(MIGRATION_FIXTURE_ROOT) / item.legacy;
  const std::filesystem::path target_root =
      std::filesystem::path(PRODUCT_FIXTURE_ROOT) / item.target;
  const std::filesystem::path scanner =
      std::filesystem::path(OMARCHY_SOURCE_ROOT) /
      "bin/omarchy-plugin-security-scan";

  const auto first = omarchy::plugins::migration::generate(
      legacy_root, target_root, scanner,
      omarchy::plugins::migration::Format::json);
  const auto second = omarchy::plugins::migration::generate(
      legacy_root, target_root, scanner,
      omarchy::plugins::migration::Format::json);
  check(first.ok, item.legacy + " JSON report succeeds: " + first.error);
  check(second.ok && second.output == first.output,
        item.legacy + " report is deterministic");
  if (!first.ok) {
    return;
  }

  const QJsonDocument document =
      QJsonDocument::fromJson(QByteArray::fromStdString(first.output));
  check(document.isObject(), item.legacy + " output is JSON object");
  const QJsonObject report = document.object();
  check(report.value("reportType") == "secure-plugin-migration-map",
        item.legacy + " has report type");
  check(report.value("advisoryOnly").toBool(),
        item.legacy + " remains advisory-only");
  const QJsonObject source = report.value("source").toObject();
  const QJsonArray findings = source.value("findings").toArray();
  check(report.value("mapping").toArray().size() == findings.size(),
        item.legacy + " directly maps every detected behavior");
  for (const std::string &finding : item.findings) {
    check(contains_id(findings, finding),
          item.legacy + " maps finding " + finding);
  }

  const QJsonObject target = report.value("target").toObject();
  check(target.value("plugin").toString().toStdString() == item.plugin,
        item.legacy + " selects exact secure target");
  check(target.value("surfaces").toObject().contains(
            QString::fromStdString(item.surface)),
        item.legacy + " exposes declared target surface");
  const QJsonObject identity = target.value("candidateIdentity").toObject();
  check(sha256(identity.value("treeSha256").toString()) &&
            sha256(identity.value("manifestSha256").toString()) &&
            sha256(identity.value("requestSha256").toString()),
        item.legacy + " has exact candidate content identity");
  const QJsonArray requests = target.value("requestedCapabilities").toArray();
  check(requests.size() == static_cast<qsizetype>(item.capabilities.size()),
        item.legacy + " has no implicit capability requests");
  for (const std::string &capability : item.capabilities) {
    check(contains_capability(requests, capability),
          item.legacy + " declares " + capability);
  }

  const auto markdown = omarchy::plugins::migration::generate(
      legacy_root, target_root, scanner,
      omarchy::plugins::migration::Format::markdown);
  check(markdown.ok, item.legacy + " markdown report succeeds");
  check(markdown.output.find("| Existing behavior |") != std::string::npos &&
            markdown.output.find("neither grants permissions nor activates") !=
                std::string::npos &&
            markdown.output.find("Today:") != std::string::npos &&
            markdown.output.find("Tomorrow:") != std::string::npos,
        item.legacy + " markdown explains the direct map and trust boundary");
}

} // namespace

int main() {
  const std::vector<Case> cases{
      {"pomodoro",
       "pomodoro",
       "org.omarchy.fixture.pomodoro",
       {"filesystem.fileview", "process.qml", "media.audio",
        "notification.access"},
       {"storage.private", "notifications.send", "audio.play-cue"},
       "timer"},
      {"pet",
       "pet",
       "org.omarchy.fixture.pet",
       {"wayland.import", "shell.object"},
       {},
       "pet"},
      {"fake-status",
       "fake-status",
       "org.omarchy.fixture.fake-status",
       {"process.qml", "url.open", "url.computed"},
       {"service.fake-status"},
       "statusPanel"},
  };
  for (const Case &item : cases) {
    run_case(item);
  }

  const auto rejected = omarchy::plugins::migration::generate(
      std::filesystem::path(MIGRATION_FIXTURE_ROOT) / "pomodoro",
      std::filesystem::path(PRODUCT_FIXTURE_ROOT) / "pomodoro",
      std::filesystem::path(MIGRATION_FIXTURE_ROOT) / "pomodoro" /
          "manifest.json",
      omarchy::plugins::migration::Format::json);
  check(!rejected.ok, "non-executable scanner is rejected before invocation");

  if (failures == 0) {
    std::cout << "plugin migration report: PASS\n";
  }
  return failures == 0 ? 0 : 1;
}
