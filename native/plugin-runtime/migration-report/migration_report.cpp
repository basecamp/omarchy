#include "migration_report.hpp"

#include "manifest_contract.hpp"

#include <QElapsedTimer>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonParseError>
#include <QProcess>

#include <algorithm>
#include <cctype>
#include <fstream>
#include <stdexcept>
#include <string_view>

namespace omarchy::plugins::migration {
namespace {

using omarchy::plugins::manifest::ManifestV2;

constexpr qsizetype kMaximumProcessOutput = 4 * 1024 * 1024;
constexpr qint64 kScannerTimeoutMilliseconds = 20'000;
constexpr std::size_t kMaximumManifestBytes = 1024 * 1024;
constexpr qsizetype kMaximumFindings = 4096;
constexpr qsizetype kMaximumFieldBytes = 16 * 1024;

[[noreturn]] void fail(std::string_view message) {
  throw std::runtime_error(std::string(message));
}

void require(bool condition, std::string_view message) {
  if (!condition) {
    fail(message);
  }
}

bool bounded_string(const QJsonValue &value, bool allow_empty = false) {
  if (!value.isString()) {
    return false;
  }
  const QByteArray encoded = value.toString().toUtf8();
  return encoded.size() <= kMaximumFieldBytes &&
         (allow_empty || !encoded.isEmpty());
}

bool is_sha256(const QString &value) {
  return value.size() == 64 &&
         std::all_of(value.cbegin(), value.cend(), [](QChar character) {
           const ushort code = character.unicode();
           return (code >= '0' && code <= '9') ||
                  (code >= 'a' && code <= 'f');
         });
}

std::string read_manifest(const std::filesystem::path &root) {
  const auto path = root / "manifest.json";
  const QFileInfo info(QString::fromStdString(path.string()));
  require(info.exists() && info.isFile() && !info.isSymLink(),
          "secure target manifest must be a regular non-symlink file");
  require(info.size() >= 0 &&
              static_cast<std::uint64_t>(info.size()) <= kMaximumManifestBytes,
          "secure target manifest is too large");
  std::ifstream input(path, std::ios::binary);
  require(input.good(), "cannot open secure target manifest");
  return {std::istreambuf_iterator<char>(input),
          std::istreambuf_iterator<char>()};
}

QByteArray run_scanner(const std::filesystem::path &scanner,
                       const std::filesystem::path &legacy_plugin) {
  const QFileInfo info(QString::fromStdString(scanner.string()));
  require(scanner.is_absolute() && info.exists() && info.isFile() &&
              !info.isSymLink() && info.isExecutable(),
          "scanner must be an absolute executable regular file");

  QProcess process;
  process.setProgram(info.absoluteFilePath());
  process.setArguments({QString::fromStdString(legacy_plugin.string()),
                        QStringLiteral("--format"), QStringLiteral("json")});
  process.setProcessChannelMode(QProcess::SeparateChannels);
  process.start();
  require(process.waitForStarted(5'000), "failed to start migration scanner");

  QByteArray output;
  QByteArray errors;
  QElapsedTimer timer;
  timer.start();
  while (process.state() != QProcess::NotRunning) {
    const qint64 remaining =
        kScannerTimeoutMilliseconds - timer.elapsed();
    if (remaining <= 0) {
      process.kill();
      process.waitForFinished(1'000);
      fail("migration scanner timed out");
    }
    process.waitForReadyRead(std::min<qint64>(remaining, 100));
    output += process.readAllStandardOutput();
    errors += process.readAllStandardError();
    if (output.size() > kMaximumProcessOutput ||
        errors.size() > kMaximumProcessOutput) {
      process.kill();
      process.waitForFinished(1'000);
      fail("migration scanner output exceeded its bound");
    }
  }
  output += process.readAllStandardOutput();
  errors += process.readAllStandardError();
  require(output.size() <= kMaximumProcessOutput &&
              errors.size() <= kMaximumProcessOutput,
          "migration scanner output exceeded its bound");
  require(process.exitStatus() == QProcess::NormalExit &&
              process.exitCode() == 0,
          "migration scanner failed");
  return output;
}

QJsonObject validate_scan(const QByteArray &bytes) {
  QJsonParseError error;
  const QJsonDocument document = QJsonDocument::fromJson(bytes, &error);
  require(error.error == QJsonParseError::NoError && document.isObject(),
          "migration scanner returned invalid JSON");
  const QJsonObject report = document.object();
  require(report.value("schemaVersion").toInt(-1) == 1,
          "unsupported scanner report schema");
  require(report.value("advisoryOnly").isBool() &&
              report.value("advisoryOnly").toBool(),
          "scanner report must remain advisory-only");
  require(report.value("legacySchemaV1Safe").isBool() &&
              !report.value("legacySchemaV1Safe").toBool(),
          "scanner report must not claim schema-v1 safety");
  require(bounded_string(report.value("plugin")),
          "scanner report has an invalid plugin id");

  const QJsonObject identity = report.value("identity").toObject();
  require(identity.value("kind").toString() ==
              QStringLiteral("advisory-content-snapshot-v1") &&
              is_sha256(identity.value("sha256").toString()),
          "scanner report has an invalid advisory identity");

  const QJsonValue findings_value = report.value("findings");
  require(findings_value.isArray(), "scanner findings must be an array");
  const QJsonArray findings = findings_value.toArray();
  require(findings.size() <= kMaximumFindings,
          "scanner report has too many findings");
  for (const QJsonValue &value : findings) {
    require(value.isObject(), "scanner finding must be an object");
    const QJsonObject finding = value.toObject();
    for (const char *field : {"id", "path", "severity", "confidence",
                              "behavior", "mapping", "authorDecision"}) {
      require(bounded_string(finding.value(field)),
              "scanner finding has an invalid field");
    }
    require(finding.value("line").isDouble() &&
                finding.value("line").toInteger(-1) >= 1,
            "scanner finding has an invalid line");
    const QString severity = finding.value("severity").toString();
    require(severity == "critical" || severity == "high" ||
                severity == "medium" || severity == "review" ||
                severity == "info",
            "scanner finding has an invalid severity");
    const QString confidence = finding.value("confidence").toString();
    require(confidence == "exact" || confidence == "heuristic",
            "scanner finding has invalid confidence");
  }
  return report;
}

QJsonValue parse_canonical_json(const std::string &value,
                                std::string_view field) {
  QJsonParseError error;
  const QJsonDocument wrapped = QJsonDocument::fromJson(
      QByteArray("[") + QByteArray::fromStdString(value) + ']', &error);
  require(error.error == QJsonParseError::NoError && wrapped.isArray() &&
              wrapped.array().size() == 1,
          std::string("manifest has invalid canonical ") + std::string(field));
  return wrapped.array().at(0);
}

QJsonObject target_json(const ManifestV2 &manifest,
                        const manifest::ContentIdentity &identity) {
  QJsonArray requests;
  for (const auto &request : manifest.requests) {
    requests.append(QJsonObject{
        {"capability", QString::fromStdString(request.capability)},
        {"required", request.required},
        {"canonicalScope",
         parse_canonical_json(request.canonical_scope, "request scope")},
        {"reason", QString::fromStdString(request.reason)},
    });
  }
  return QJsonObject{
      {"plugin", QString::fromStdString(manifest.id)},
      {"version", QString::fromStdString(manifest.version)},
      {"candidateIdentity",
       QJsonObject{{"treeSha256", QString::fromStdString(identity.tree_sha256)},
                   {"manifestSha256",
                    QString::fromStdString(identity.manifest_sha256)},
                   {"requestSha256",
                    QString::fromStdString(identity.request_sha256)}}},
      {"surfaces", parse_canonical_json(manifest.canonical_surfaces,
                                         "surfaces")},
      {"requestedCapabilities", requests},
  };
}

QJsonArray mapping_json(const QJsonArray &findings) {
  QJsonArray mappings;
  for (const QJsonValue &value : findings) {
    const QJsonObject finding = value.toObject();
    mappings.append(QJsonObject{
        {"findingId", finding.value("id")},
        {"detectedBehavior", finding.value("behavior")},
        {"proposedMapping", finding.value("mapping")},
        {"authorDecision", finding.value("authorDecision")},
    });
  }
  return mappings;
}

QString markdown_escape(QString value) {
  value.replace('&', QStringLiteral("&amp;"));
  value.replace('<', QStringLiteral("&lt;"));
  value.replace('>', QStringLiteral("&gt;"));
  value.replace('|', QStringLiteral("&#124;"));
  value.replace('`', QStringLiteral("&#96;"));
  value.replace('\r', ' ');
  value.replace('\n', QStringLiteral("<br>"));
  return value;
}

QString compact_json(const QJsonValue &value) {
  QJsonArray wrapper;
  wrapper.append(value);
  QByteArray bytes = QJsonDocument(wrapper).toJson(QJsonDocument::Compact);
  return QString::fromUtf8(bytes.mid(1, bytes.size() - 2));
}

std::string markdown_report(const QJsonObject &source,
                            const QJsonObject &target) {
  QString output;
  output += QStringLiteral("# Secure plugin migration map\n\n");
  output += QStringLiteral(
      "> Advisory only. This report neither grants permissions nor activates "
      "the candidate revision. The target hashes identify reviewed candidate "
      "content only.\n\n");
  output += QStringLiteral("Today: `%1` (schema v1, unsafe)\n\n")
                .arg(markdown_escape(source.value("plugin").toString()));
  output += QStringLiteral("Tomorrow: `%1` version `%2`\n\n")
                .arg(markdown_escape(target.value("plugin").toString()),
                     markdown_escape(target.value("version").toString()));
  output += QStringLiteral(
      "| Existing behavior | Location | Proposed secure mapping | Author "
      "decision |\n|---|---|---|---|\n");
  for (const QJsonValue &value : source.value("findings").toArray()) {
    const QJsonObject finding = value.toObject();
    output += QStringLiteral("| %1 | `%2:%3` | %4 | %5 |\n")
                  .arg(markdown_escape(finding.value("behavior").toString()),
                       markdown_escape(finding.value("path").toString()),
                       QString::number(finding.value("line").toInteger()),
                       markdown_escape(finding.value("mapping").toString()),
                       markdown_escape(
                           finding.value("authorDecision").toString()));
  }
  output += QStringLiteral("\n## Target surface declarations\n\n```json\n%1\n```\n\n")
                .arg(compact_json(target.value("surfaces")));
  output += QStringLiteral(
      "## Target capability requests\n\n| Capability | Required | Exact scope | "
      "Reason |\n|---|---|---|---|\n");
  for (const QJsonValue &value :
       target.value("requestedCapabilities").toArray()) {
    const QJsonObject request = value.toObject();
    output += QStringLiteral("| `%1` | %2 | `%3` | %4 |\n")
                  .arg(markdown_escape(request.value("capability").toString()),
                       request.value("required").toBool() ? "yes" : "no",
                       markdown_escape(
                           compact_json(request.value("canonicalScope"))),
                       markdown_escape(request.value("reason").toString()));
  }
  output += QStringLiteral(
      "\nThe candidate identity must still pass install validation, explicit "
      "grant selection, activation, and runtime policy checks.\n");
  return output.toStdString();
}

} // namespace

Result generate(const std::filesystem::path &legacy_plugin,
                const std::filesystem::path &secure_target,
                const std::filesystem::path &scanner, Format format) {
  try {
    const QJsonObject scan = validate_scan(run_scanner(scanner, legacy_plugin));
    const ManifestV2 manifest = manifest::parse_manifest_v2(
        read_manifest(secure_target));
    const auto identity = manifest::identify_tree(secure_target, manifest);
    const QJsonObject target = target_json(manifest, identity);
    const QJsonObject report{
        {"schemaVersion", 1},
        {"reportType", QStringLiteral("secure-plugin-migration-map")},
        {"advisoryOnly", true},
        {"source",
         QJsonObject{{"plugin", scan.value("plugin")},
                     {"advisoryIdentity", scan.value("identity")},
                     {"findings", scan.value("findings")}}},
        {"mapping", mapping_json(scan.value("findings").toArray())},
        {"target", target},
    };
    if (format == Format::json) {
      return {true,
              QJsonDocument(report).toJson(QJsonDocument::Indented).toStdString(),
              {}};
    }
    return {true, markdown_report(scan, target), {}};
  } catch (const std::exception &error) {
    return {false, {}, error.what()};
  }
}

} // namespace omarchy::plugins::migration
