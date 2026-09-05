#include "PermissionControl.h"

#include "PluginManager.h"
#include "omarchy/plugin/wire/permission_snapshot.hpp"
#include "plugin_permission_authority.hpp"

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonParseError>
#include <QRandomGenerator>

#include <algorithm>
#include <array>
#include <chrono>
#include <ranges>
#include <string_view>

namespace omarchy::plugin_runtime::bridge {
namespace {

constexpr std::size_t kMaximumOperations = 32;
// One 1 KiB choice lane covers the fixed JSON keys, a 128-bit opaque row ID,
// and sixteen 128-bit opaque operation IDs. The wire contract supplies the
// exact manifest row bound, so every valid review fits without unbounded input.
constexpr qsizetype kMaximumChoiceRowBytes = 1024;
constexpr qsizetype kMaximumChoicesBytes =
    32 +
    static_cast<qsizetype>(
        omarchy::plugin::wire::permission_snapshot::kMaximumManifestRequests) *
        kMaximumChoiceRowBytes;
constexpr auto kCompletedLifetime = std::chrono::minutes(1);
constexpr auto kReviewLifetime = std::chrono::minutes(15);
constexpr auto kPendingLifetime = std::chrono::minutes(5);

namespace definitions = omarchy::plugins::definitions;
namespace permissions = omarchy::plugins::permissions;

QString text(std::string_view value) {
  return QString::fromUtf8(value.data(), static_cast<qsizetype>(value.size()));
}

std::string opaque_id(std::string_view prefix) {
  const auto first = QRandomGenerator::system()->generate64();
  const auto second = QRandomGenerator::system()->generate64();
  return std::string(prefix) + '-' +
         QStringLiteral("%1%2")
             .arg(first, 16, 16, QLatin1Char('0'))
             .arg(second, 16, 16, QLatin1Char('0'))
             .toStdString();
}

QString kind_name(PermissionControl::Kind kind) {
  switch (kind) {
  case PermissionControl::Kind::list:
    return QStringLiteral("list");
  case PermissionControl::Kind::review:
    return QStringLiteral("review");
  case PermissionControl::Kind::apply:
    return QStringLiteral("apply");
  case PermissionControl::Kind::revoke:
    return QStringLiteral("revoke");
  }
  return QStringLiteral("invalid");
}

QString grant_state(permissions::GrantState state) {
  switch (state) {
  case permissions::GrantState::granted:
    return QStringLiteral("granted");
  case permissions::GrantState::denied:
    return QStringLiteral("denied");
  case permissions::GrantState::revoked:
    return QStringLiteral("revoked");
  }
  return QStringLiteral("denied");
}

QString delta_name(host_session::ConsentDeltaKind delta) {
  using Delta = host_session::ConsentDeltaKind;
  switch (delta) {
  case Delta::unchanged:
    return QStringLiteral("unchanged");
  case Delta::narrowed:
    return QStringLiteral("narrowed");
  case Delta::expanded:
    return QStringLiteral("expanded");
  case Delta::incomparable:
    return QStringLiteral("incomparable");
  case Delta::added:
    return QStringLiteral("added");
  case Delta::removed:
    return QStringLiteral("removed");
  case Delta::requirement_changed:
    return QStringLiteral("requirement-changed");
  case Delta::definition_changed:
    return QStringLiteral("definition-changed");
  case Delta::operations_changed:
    return QStringLiteral("operations-changed");
  }
  return QStringLiteral("invalid");
}

QJsonArray builtin_operations(const permissions::CapabilityKey &key) {
  QJsonArray result;
  const auto *definition = permissions::find_capability(key);
  if (!definition)
    return result;
  for (std::uint8_t index = 0; index < definition->operation_count; ++index)
    result.push_back(text(permissions::operation_name(
        definition->operations[static_cast<std::size_t>(index)])));
  return result;
}

template <typename Values> QJsonArray dynamic_operations(const Values &values) {
  QJsonArray result;
  for (const auto &operation : values.values())
    result.push_back(text(operation.view()));
  return result;
}

QJsonObject builtin_row(std::string_view row_id,
                        const permissions::CapabilityRequest &request,
                        const std::optional<permissions::GrantRecord> &grant,
                        bool available) {
  return {
      {QStringLiteral("rowId"), text(row_id)},
      {QStringLiteral("kind"), QStringLiteral("builtin")},
      {QStringLiteral("name"), text(request.capability.id.view())},
      {QStringLiteral("required"), request.required},
      {QStringLiteral("available"), available},
      {QStringLiteral("state"),
       grant ? grant_state(grant->state) : QStringLiteral("undecided")},
      {QStringLiteral("scope"),
       text(permissions::canonical_scope(request.scope))},
      {QStringLiteral("operations"), builtin_operations(request.capability)}};
}

QJsonObject dynamic_row(
    std::string_view row_id, const definitions::DynamicRequest &request,
    const std::optional<definitions::DynamicGrant> &grant,
    const std::optional<definitions::CapabilityDefinition> &trusted_definition,
    bool available) {
  QJsonObject result{
      {QStringLiteral("rowId"), text(row_id)},
      {QStringLiteral("kind"), QStringLiteral("dynamic")},
      {QStringLiteral("name"), text(request.definition.canonical_name.view())},
      {QStringLiteral("required"), request.required},
      {QStringLiteral("available"), available},
      {QStringLiteral("state"),
       grant ? grant_state(grant->state) : QStringLiteral("undecided")},
      {QStringLiteral("scope"), text(request.scope.view())},
      {QStringLiteral("operations"), dynamic_operations(request.operations)}};
  if (trusted_definition) {
    result.insert(QStringLiteral("title"),
                  text(trusted_definition->title.view()));
    result.insert(QStringLiteral("category"),
                  text(trusted_definition->display_category_label.view()));
  }
  return result;
}

QJsonObject builtin_list_row(
    std::string_view row_id, const permissions::CapabilityRequest &request,
    const std::optional<permissions::GrantRecord> &grant, bool available) {
  auto result = builtin_row(row_id, request, grant, available);
  if (grant)
    result.insert(QStringLiteral("scope"),
                  text(permissions::canonical_scope(grant->scope)));
  return result;
}

QJsonObject dynamic_list_row(
    std::string_view row_id, const definitions::DynamicRequest &request,
    const std::optional<definitions::DynamicGrant> &grant, bool available) {
  auto result = dynamic_row(row_id, request, grant, std::nullopt, available);
  if (grant) {
    result.insert(QStringLiteral("scope"), text(grant->scope.view()));
    result.insert(QStringLiteral("operations"),
                  dynamic_operations(grant->operations));
  }
  return result;
}

std::optional<permissions::GrantRecord>
grant_for(const host_session::AuthorityView &view,
          const permissions::CapabilityKey &capability) {
  if (!view.active)
    return std::nullopt;
  const auto found = std::ranges::find(view.active->grants.values(), capability,
                                       &permissions::GrantRecord::capability);
  return found == view.active->grants.values().end() ? std::nullopt
                                                     : std::optional(*found);
}

} // namespace

PermissionControl::PermissionControl(PluginManager &manager)
    : QObject(&manager), manager_(manager) {
  operations_.reserve(kMaximumOperations);
}

PermissionControl::~PermissionControl() = default;

QString PermissionControl::beginList(const QString &plugin_id) noexcept {
  return beginRead(plugin_id, Kind::list, Ingress::trusted_ui);
}

QString PermissionControl::beginReview(const QString &plugin_id) noexcept {
  return beginRead(plugin_id, Kind::review, Ingress::trusted_ui);
}

QString PermissionControl::beginInteractiveCliReview(
    const QString &plugin_id) noexcept {
  return beginRead(plugin_id, Kind::review, Ingress::interactive_cli);
}

QString PermissionControl::beginInteractiveCliReviewExact(
    std::string_view plugin, std::string_view revision) noexcept {
  try {
    const permissions::PluginId exact_plugin(plugin);
    const permissions::Digest exact_revision(revision);
    return beginRead(QString::fromUtf8(exact_plugin.view().data(),
                                      static_cast<qsizetype>(exact_plugin.view().size())),
                     Kind::review, Ingress::interactive_cli, exact_revision);
  } catch (...) {
    return {};
  }
}

QString
PermissionControl::applyInteractiveCli(const QString &review_operation_id,
                                       const QString &choices_json) noexcept {
  return applyForIngress(review_operation_id, choices_json,
                         Ingress::interactive_cli);
}

QString PermissionControl::beginRead(const QString &plugin_id, Kind kind,
                                     Ingress ingress,
                                     std::optional<permissions::Digest>
                                         expected_revision) noexcept {
  try {
    const auto encoded = plugin_id.toUtf8();
    const permissions::PluginId exact(std::string_view(
        encoded.constData(), static_cast<std::size_t>(encoded.size())));
    const auto id = reserve(kind, ingress);
    auto *operation = find(QString::fromStdString(id));
    if (!operation)
      return {};
    const auto serial = operation->serial;
    if (!manager_.beginPermissionRead(serial, std::string(exact.view()),
                                      kind == Kind::review,
                                      std::move(expected_revision))) {
      erase(serial);
      return {};
    }
    return QString::fromStdString(id);
  } catch (...) {
    return {};
  }
}

QString PermissionControl::apply(const QString &review_operation_id,
                                 const QString &choices_json) noexcept {
  return applyForIngress(review_operation_id, choices_json,
                         Ingress::trusted_ui);
}

QString PermissionControl::applyForIngress(const QString &review_operation_id,
                                           const QString &choices_json,
                                           Ingress ingress) noexcept {
  try {
    prune();
    auto *source = find(review_operation_id);
    if (!source || source->kind != Kind::review ||
        source->state != State::succeeded || source->consumed ||
        !source->context || !source->review || source->ingress != ingress ||
        choices_json.toUtf8().size() > kMaximumChoicesBytes)
      return {};

    QJsonParseError parse_error{};
    const auto document =
        QJsonDocument::fromJson(choices_json.toUtf8(), &parse_error);
    if (parse_error.error != QJsonParseError::NoError || !document.isObject())
      return {};
    const auto root = document.object();
    if (root.size() != 1 || !root.value(QStringLiteral("choices")).isArray())
      return {};
    const auto choices = root.value(QStringLiteral("choices")).toArray();
    if (choices.size() != static_cast<qsizetype>(source->rows.size()))
      return {};

    std::vector<host_session::BuiltinConsentDecision> builtin;
    std::vector<host_session::DynamicConsentDecision> dynamic;
    builtin.reserve(source->review->builtin_rows.size());
    dynamic.reserve(source->review->dynamic_rows.size());
    std::vector<bool> seen(source->rows.size(), false);
    for (const auto value : choices) {
      if (!value.isObject())
        return {};
      const auto choice = value.toObject();
      if (choice.size() < 2 || choice.size() > 3 ||
          !choice.value(QStringLiteral("rowId")).isString() ||
          !choice.value(QStringLiteral("decision")).isString())
        return {};
      const auto row_id = choice.value(QStringLiteral("rowId")).toString();
      const auto found =
          std::ranges::find(source->rows, row_id.toStdString(), &Row::id);
      if (found == source->rows.end())
        return {};
      const auto position =
          static_cast<std::size_t>(std::distance(source->rows.begin(), found));
      if (seen[position])
        return {};
      seen[position] = true;
      const auto decision_text =
          choice.value(QStringLiteral("decision")).toString();
      const bool grant = decision_text == QStringLiteral("grant");
      if (!grant && decision_text != QStringLiteral("deny"))
        return {};
      if ((grant && !found->available) || (!grant && found->required))
        return {};
      const auto decision = grant ? permissions::UserDecision::grant
                                  : permissions::UserDecision::deny;
      if (found->dynamic) {
        const auto &row = source->review->dynamic_rows[found->index];
        if (!row.requested)
          return {};
        auto operations = row.requested->operations;
        if (grant) {
          if (choice.size() != 3 ||
              !choice.value(QStringLiteral("operations")).isArray())
            return {};
          const auto selected =
              choice.value(QStringLiteral("operations")).toArray();
          const auto narrowed = selectDynamicOperations(*found, selected);
          if (!narrowed)
            return {};
          operations = *narrowed;
        } else if (choice.size() != 2) {
          return {};
        }
        dynamic.push_back({.definition = row.requested->definition,
                           .operations = std::move(operations),
                           .decided_scope = row.requested->scope,
                           .decision = decision});
      } else {
        if (choice.size() != 2)
          return {};
        const auto &row = source->review->builtin_rows[found->index];
        if (!row.requested)
          return {};
        builtin.push_back({.capability = row.requested->capability,
                           .decided_scope = row.requested->scope,
                           .decision = decision});
      }
    }
    if (!std::ranges::all_of(seen, [](bool value) { return value; }))
      return {};

    const auto context = *source->context;
    const auto review = source->review;
    const auto seconds =
        std::chrono::duration_cast<std::chrono::seconds>(
            std::chrono::system_clock::now().time_since_epoch())
            .count();
    host_session::ConsentConfirmation confirmation{
        .review_fingerprint = review->fingerprint,
        .decision_fingerprint = host_session::consent_decision_fingerprint(
            *review, builtin, dynamic),
        .actor = ingress == Ingress::trusted_ui
                     ? permissions::DecisionActor::trusted_ui
                     : permissions::DecisionActor::interactive_cli,
        .confirmed_wall_seconds =
            seconds > 0 ? static_cast<std::uint64_t>(seconds) : 1};
    const auto id = reserve(Kind::apply, ingress);
    auto *operation = find(QString::fromStdString(id));
    if (!operation)
      return {};
    const auto serial = operation->serial;
    if (!manager_.beginPermissionApply(serial, context, review, confirmation,
                                       builtin, dynamic)) {
      erase(serial);
      return {};
    }
    source = find(review_operation_id);
    if (source)
      source->consumed = true;
    return QString::fromStdString(id);
  } catch (...) {
    return {};
  }
}

QString PermissionControl::revoke(const QString &source_operation_id,
                                  const QString &row_id) noexcept {
  try {
    prune();
    auto *source = find(source_operation_id);
    if (!source ||
        (source->kind != Kind::list && source->kind != Kind::review) ||
        source->state != State::succeeded || source->consumed ||
        !source->context)
      return {};
    const auto found =
        std::ranges::find(source->rows, row_id.toStdString(), &Row::id);
    if (found == source->rows.end())
      return {};
    const auto exact_row = *found;
    const auto context = *source->context;
    const auto id = reserve(Kind::revoke, source->ingress);
    auto *operation = find(QString::fromStdString(id));
    if (!operation)
      return {};
    const auto serial = operation->serial;
    if (!manager_.beginPermissionRevoke(serial, context, exact_row)) {
      erase(serial);
      return {};
    }
    source = find(source_operation_id);
    if (source)
      source->consumed = true;
    return QString::fromStdString(id);
  } catch (...) {
    return {};
  }
}

QString PermissionControl::poll(const QString &operation_id) noexcept {
  try {
    prune();
    auto *operation = find(operation_id);
    if (!operation)
      return {};
    QJsonObject response{{QStringLiteral("operationId"), operation_id},
                         {QStringLiteral("kind"), kind_name(operation->kind)}};
    switch (operation->state) {
    case State::pending:
      response.insert(QStringLiteral("state"), QStringLiteral("pending"));
      break;
    case State::succeeded: {
      response.insert(QStringLiteral("state"), QStringLiteral("succeeded"));
      if (!operation->result_json.empty()) {
        const auto result = QJsonDocument::fromJson(
            QByteArray::fromStdString(operation->result_json));
        response.insert(QStringLiteral("result"), result.object());
      }
      break;
    }
    case State::failed:
      response.insert(QStringLiteral("state"), QStringLiteral("failed"));
      response.insert(QStringLiteral("error"), text(operation->error));
      break;
    }
    operation->touched = std::chrono::steady_clock::now();
    return QString::fromUtf8(
        QJsonDocument(response).toJson(QJsonDocument::Compact));
  } catch (...) {
    return {};
  }
}

PermissionControl::Operation *
PermissionControl::find(const QString &operation_id) noexcept {
  const auto id = operation_id.toStdString();
  const auto found = std::ranges::find(operations_, id, &Operation::id);
  return found == operations_.end() ? nullptr : &*found;
}

PermissionControl::Operation *
PermissionControl::find(std::uint64_t serial) noexcept {
  const auto found = std::ranges::find(operations_, serial, &Operation::serial);
  return found == operations_.end() ? nullptr : &*found;
}

void PermissionControl::erase(std::uint64_t serial) noexcept {
  std::erase_if(operations_, [serial](const Operation &candidate) {
    return candidate.serial == serial;
  });
}

std::optional<permissions::FixedSet<definitions::Name, 16>>
PermissionControl::selectDynamicOperations(
    const Row &row, const QJsonArray &selected) noexcept {
  try {
    if (selected.isEmpty() ||
        selected.size() > static_cast<qsizetype>(row.operations.size()))
      return std::nullopt;
    permissions::FixedSet<definitions::Name, 16> operations;
    for (const auto selected_value : selected) {
      if (!selected_value.isString())
        return std::nullopt;
      const auto selected_id = selected_value.toString().toStdString();
      const auto exact = std::ranges::find(row.operations, selected_id,
                                           &Row::DynamicOperation::id);
      if (exact == row.operations.end() || !operations.insert(exact->name))
        return std::nullopt;
    }
    return operations;
  } catch (...) {
    return std::nullopt;
  }
}

#ifdef OMARCHY_PLUGIN_MANAGER_TESTING
void PermissionControlTestAccess::ageOperation(PermissionControl &control,
                                               const QString &operation_id,
                                               std::chrono::minutes age) {
  if (auto *operation = control.find(operation_id))
    operation->touched = std::chrono::steady_clock::now() - age;
}
#endif

std::string PermissionControl::reserve(Kind kind, Ingress ingress) {
  prune();
  if (operations_.size() >= kMaximumOperations || next_serial_ == 0)
    return {};
  std::string id;
  do {
    id = opaque_id("permission");
  } while (std::ranges::any_of(
      operations_, [&](const auto &operation) { return operation.id == id; }));
  operations_.push_back({.serial = next_serial_++,
                         .id = id,
                         .kind = kind,
                         .ingress = ingress,
                         .state = State::pending,
                         .touched = std::chrono::steady_clock::now(),
                         .result_json = {},
                         .error = {},
                         .context = std::nullopt,
                         .view = std::nullopt,
                         .review = {},
                         .rows = {},
                         .consumed = false});
  return id;
}

void PermissionControl::prune() noexcept {
  const auto now = std::chrono::steady_clock::now();
  std::erase_if(operations_, [&](const Operation &operation) {
    const auto lifetime =
        operation.state == State::pending ? kPendingLifetime
        : operation.kind == Kind::review && !operation.consumed
            ? kReviewLifetime
            : kCompletedLifetime;
    return now - operation.touched > lifetime;
  });
}

void PermissionControl::fail(std::uint64_t serial, std::string error) noexcept {
  if (auto *operation = find(serial)) {
    operation->state = State::failed;
    operation->error = std::move(error);
    operation->touched = std::chrono::steady_clock::now();
  }
}

void PermissionControl::completeRead(
    std::uint64_t serial, std::string plugin, std::uint64_t slot_epoch,
    std::shared_ptr<channel::PluginPermissionAuthority> authority,
    std::optional<host_session::AuthorityView> view,
    std::shared_ptr<const host_session::ConsentReview> review) noexcept {
  try {
    auto *operation = find(serial);
    if (!operation || !authority || !view ||
        (operation->kind == Kind::review && !review)) {
      fail(serial, "read-failed");
      return;
    }
    operation->context =
        ExactContext{.plugin = std::move(plugin),
                     .slot_epoch = slot_epoch,
                     .authority_sequence = view->authority_slots.sequence,
                     .authority = std::move(authority)};
    operation->view = std::move(view);
    operation->review = std::move(review);
    QJsonArray rows;
    if (operation->kind == Kind::list) {
      if (operation->view->active) {
        const auto &active = *operation->view->active;
        for (std::size_t index = 0; index < active.requests.size(); ++index) {
          const auto &request = active.requests[index];
          const auto grant = grant_for(*operation->view, request.capability);
          const auto row_id = opaque_id("row");
          const bool available =
              operation->context->authority->provider_available(
                  request.capability);
          operation->rows.push_back({.id = row_id,
                                     .dynamic = false,
                                     .index = index,
                                     .required = request.required,
                                     .available = available,
                                     .builtin = request.capability,
                                     .definition = std::nullopt,
                                     .operations = {}});
          rows.push_back(
              builtin_list_row(row_id, request, grant, available));
        }
        for (std::size_t index = 0; index < active.dynamic_grants.size();
             ++index) {
          const auto &revision = active.dynamic_grants[index];
          const auto row_id = opaque_id("row");
          const bool available =
              operation->context->authority->provider_available(
                  revision.request.definition);
          operation->rows.push_back({.id = row_id,
                                     .dynamic = true,
                                     .index = index,
                                     .required = revision.request.required,
                                     .available = available,
                                     .builtin = std::nullopt,
                                     .definition = revision.request.definition,
                                     .operations = {}});
          rows.push_back(dynamic_list_row(row_id, revision.request,
                                          revision.grant, available));
        }
      }
    } else {
      for (std::size_t index = 0;
           index < operation->review->builtin_rows.size(); ++index) {
        const auto &review_row = operation->review->builtin_rows[index];
        if (!review_row.requested)
          continue;
        const auto row_id = opaque_id("row");
        const bool available =
            operation->context->authority->provider_available(
                review_row.requested->capability);
        operation->rows.push_back({.id = row_id,
                                   .dynamic = false,
                                   .index = index,
                                   .required = review_row.requested->required,
                                   .available = available,
                                   .builtin = review_row.requested->capability,
                                   .definition = std::nullopt,
                                   .operations = {}});
        auto presentation = builtin_row(row_id, *review_row.requested,
                                        review_row.previous_grant, available);
        presentation.insert(QStringLiteral("delta"),
                            delta_name(review_row.delta));
        presentation.insert(QStringLiteral("reason"),
                            text(review_row.publisher_reason));
        rows.push_back(std::move(presentation));
      }
      for (std::size_t index = 0;
           index < operation->review->dynamic_rows.size(); ++index) {
        const auto &review_row = operation->review->dynamic_rows[index];
        if (!review_row.requested)
          continue;
        const auto row_id = opaque_id("row");
        const bool available =
            operation->context->authority->provider_available(
                review_row.requested->definition);
        operation->rows.push_back(
            {.id = row_id,
             .dynamic = true,
             .index = index,
             .required = review_row.requested->required,
             .available = available,
             .builtin = std::nullopt,
             .definition = review_row.requested->definition,
             .operations = {}});
        auto &exact_row = operation->rows.back();
        QJsonArray selectable_operations;
        for (const auto &name : review_row.requested->operations.values()) {
          const auto operation_id = opaque_id("operation");
          exact_row.operations.push_back({.id = operation_id, .name = name});
          QString label = text(name.view());
          if (review_row.trusted_definition) {
            const auto definition_operation = std::ranges::find(
                review_row.trusted_definition->operations.values(), name,
                &definitions::OperationDefinition::name);
            if (definition_operation !=
                review_row.trusted_definition->operations.values().end())
              label = text(definition_operation->label.view());
          }
          selectable_operations.push_back(
              QJsonObject{{QStringLiteral("operationId"), text(operation_id)},
                          {QStringLiteral("name"), text(name.view())},
                          {QStringLiteral("label"), label}});
        }
        auto presentation = dynamic_row(
            row_id, *review_row.requested, review_row.previous_grant,
            review_row.trusted_definition, available);
        presentation.insert(QStringLiteral("operations"),
                            selectable_operations);
        presentation.insert(QStringLiteral("delta"),
                            delta_name(review_row.delta));
        presentation.insert(QStringLiteral("reason"),
                            text(review_row.publisher_reason));
        rows.push_back(std::move(presentation));
      }
    }
    QJsonObject result{
        {QStringLiteral("plugin"), text(operation->context->plugin)},
        {QStringLiteral("permissions"), rows}};
    operation->result_json =
        QJsonDocument(result).toJson(QJsonDocument::Compact).toStdString();
    operation->state = State::succeeded;
    operation->touched = std::chrono::steady_clock::now();
  } catch (...) {
    fail(serial, "read-failed");
  }
}

void PermissionControl::completeMutation(std::uint64_t serial, bool applied,
                                         std::string error) noexcept {
  auto *operation = find(serial);
  if (!operation)
    return;
  operation->state = applied ? State::succeeded : State::failed;
  operation->error = applied ? std::string{} : std::move(error);
  operation->result_json = applied ? "{\"applied\":true}" : std::string{};
  operation->touched = std::chrono::steady_clock::now();
}

void PermissionControl::invalidatePlugin(std::string_view plugin) noexcept {
  std::erase_if(operations_, [&](const Operation &operation) {
    return operation.context && operation.context->plugin == plugin;
  });
}

} // namespace omarchy::plugin_runtime::bridge
