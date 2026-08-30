#include "PluginSurfaceService.h"

#include "gesture_intent.hpp"
#include "omarchy/plugin/wire/surface_name.hpp"
#include "remote_surface.hpp"

#include <QSortFilterProxyModel>
#include <QThread>

#include <algorithm>
#include <iterator>
#include <string>
#include <utility>

namespace omarchy::plugin_runtime::bridge {
namespace {

namespace wire = omarchy::plugin::wire;

QString text(std::string_view bytes) {
  return QString::fromUtf8(bytes.data(), static_cast<qsizetype>(bytes.size()));
}

QString canonical_surface_key(
    const plugins::permissions::ActivationBinding &binding,
    std::string_view surface_name) {
  const auto plugin = binding.plugin.view();
  return QStringLiteral("v2.") + QString::number(plugin.size()) + u'.' +
         text(plugin) + u'.' + QString::number(binding.generation) + u'.' +
         text(surface_name);
}

QString bar_section_name(PluginSurfaceService::BarSection section) {
  switch (section) {
  case PluginSurfaceService::BarSection::Left:
    return QStringLiteral("left");
  case PluginSurfaceService::BarSection::Right:
    return QStringLiteral("right");
  case PluginSurfaceService::BarSection::Unspecified:
  case PluginSurfaceService::BarSection::Center:
    return QStringLiteral("center");
  }
  return QStringLiteral("center");
}

} // namespace

struct PluginSurfaceService::Publication {
  plugins::permissions::ActivationBinding binding;
  qulonglong revision = 0;
  std::vector<SurfaceDeclaration> declarations;
};

struct PluginSurfaceService::SurfaceRow {
  QString surface_key;
  QString plugin_id;
  QString surface_name;
  qulonglong generation = 0;
  qulonglong publication_revision = 0;
  SurfaceDeclaration declaration;
};

class PluginSurfaceService::RoleFilterModel final
    : public QSortFilterProxyModel {
public:
  RoleFilterModel(Role role, PluginSurfaceService &source)
      : QSortFilterProxyModel(&source), role_(role) {
    setSourceModel(&source);
  }

protected:
  bool filterAcceptsRow(int source_row,
                        const QModelIndex &source_parent) const override {
    const auto source_index = sourceModel()->index(source_row, 0, source_parent);
    return sourceModel()->data(source_index, SurfaceRoleRole).toInt() ==
           static_cast<int>(role_);
  }

private:
  Role role_;
};

PluginSurfaceService::PluginSurfaceService(QObject *parent)
    : QAbstractListModel(parent),
      bar_surfaces_(std::make_unique<RoleFilterModel>(Role::Bar, *this)),
      panel_surfaces_(std::make_unique<RoleFilterModel>(Role::Panel, *this)),
      overlay_surfaces_(
          std::make_unique<RoleFilterModel>(Role::Overlay, *this)) {}

PluginSurfaceService::~PluginSurfaceService() = default;

bool PluginSurfaceService::available() const { return backend_ != nullptr; }

QAbstractItemModel *PluginSurfaceService::barSurfaces() {
  return bar_surfaces_.get();
}

QAbstractItemModel *PluginSurfaceService::panelSurfaces() {
  return panel_surfaces_.get();
}

QAbstractItemModel *PluginSurfaceService::overlaySurfaces() {
  return overlay_surfaces_.get();
}

int PluginSurfaceService::count() const { return rowCount(); }

int PluginSurfaceService::rowCount(const QModelIndex &parent) const {
  return parent.isValid() ? 0 : static_cast<int>(surfaces_.size());
}

QVariant PluginSurfaceService::data(const QModelIndex &index, int role) const {
  if (!index.isValid() || index.column() != 0 || index.row() < 0 ||
      index.row() >= rowCount())
    return {};
  const auto &row = surfaces_[static_cast<std::size_t>(index.row())];
  switch (role) {
  case SurfaceKeyRole:
    return row.surface_key;
  case PluginIdRole:
    return row.plugin_id;
  case SurfaceNameRole:
    return row.surface_name;
  case SurfaceRoleRole:
    return static_cast<int>(row.declaration.role);
  case GenerationRole:
    return QString::number(row.generation);
  case PublicationRevisionRole:
    return QString::number(row.publication_revision);
  case ScreenNameRole:
    return row.declaration.screen_name;
  case InitiallyVisibleRole:
    return row.declaration.initially_visible;
  case MaximumWidthRole:
    return row.declaration.maximum_width;
  case MaximumHeightRole:
    return row.declaration.maximum_height;
  case DynamicInputRegionsRole:
    return row.declaration.dynamic_input_regions;
  case DefaultSectionRole:
    return bar_section_name(row.declaration.default_bar_section);
  default:
    return {};
  }
}

QHash<int, QByteArray> PluginSurfaceService::roleNames() const {
  return {{SurfaceKeyRole, "surfaceKey"},
          {PluginIdRole, "pluginId"},
          {SurfaceNameRole, "surfaceName"},
          {SurfaceRoleRole, "surfaceRole"},
          {GenerationRole, "generation"},
          {PublicationRevisionRole, "publicationRevision"},
          {ScreenNameRole, "screenName"},
          {InitiallyVisibleRole, "initiallyVisible"},
          {MaximumWidthRole, "maximumWidth"},
          {MaximumHeightRole, "maximumHeight"},
          {DynamicInputRegionsRole, "dynamicInputRegions"},
          {DefaultSectionRole, "defaultSection"}};
}

bool PluginSurfaceService::attach(const QString &surface_key,
                                  QObject *surface) {
  auto *remote = qobject_cast<RemotePluginSurface *>(surface);
  return onOwnerThread() && backend_ != nullptr && remote != nullptr &&
         declared(surface_key) && backend_->attach(surface_key, *remote);
}

bool PluginSurfaceService::dismiss(const QString &surface_key) {
  return onOwnerThread() && backend_ != nullptr &&
         declared(surface_key) != nullptr && backend_->dismiss(surface_key);
}

bool PluginSurfaceService::bindBackend(PluginSurfaceBackend &backend) {
  if (!onOwnerThread() || backend_ != nullptr)
    return false;
  backend_ = &backend;
  emit availableChanged();
  return true;
}

void PluginSurfaceService::unbindBackend(PluginSurfaceBackend &backend) {
  if (!onOwnerThread() || backend_ != &backend)
    return;
  backend_ = nullptr;
  clearSurfaces();
  emit availableChanged();
}

bool PluginSurfaceService::publishSurfaces(
    const plugins::permissions::ActivationBinding &binding,
    std::vector<SurfaceDeclaration> declarations, qulonglong revision) {
  if (!onOwnerThread() || backend_ == nullptr || revision == 0 ||
      declarations.size() > wire::kMaximumPluginSurfaces)
    return false;

  const auto publication = std::ranges::find_if(
      publications_, [&binding](const Publication &candidate) {
        return candidate.binding.plugin == binding.plugin;
      });
  if (publication != publications_.end()) {
    if (revision <= publication->revision ||
        binding.generation < publication->binding.generation ||
        (binding.generation == publication->binding.generation &&
         binding != publication->binding))
      return false;
    Publication replacement{.binding = binding,
                            .revision = revision,
                            .declarations = std::move(declarations)};
    auto replacement_rows = rowsFor(replacement);
    const auto publication_index = static_cast<std::size_t>(
        std::distance(publications_.begin(), publication));
    const qsizetype first = firstRow(publication_index);
    const qsizetype old_count =
        static_cast<qsizetype>(publication->declarations.size());
    surfaces_.reserve(surfaces_.size() - static_cast<std::size_t>(old_count) +
                      replacement_rows.size());
    if (old_count > 0) {
      beginRemoveRows({}, first, first + old_count - 1);
      surfaces_.erase(surfaces_.begin() + first,
                      surfaces_.begin() + first + old_count);
      endRemoveRows();
    }
    *publication = std::move(replacement);
    if (!replacement_rows.empty()) {
      beginInsertRows({}, first,
                      first + static_cast<qsizetype>(replacement_rows.size()) -
                          1);
      surfaces_.insert(surfaces_.begin() + first,
                       std::make_move_iterator(replacement_rows.begin()),
                       std::make_move_iterator(replacement_rows.end()));
      endInsertRows();
    }
    emit surfacesChanged();
    return true;
  }

  Publication addition{.binding = binding,
                       .revision = revision,
                       .declarations = std::move(declarations)};
  auto addition_rows = rowsFor(addition);
  const qsizetype first = rowCount();
  publications_.reserve(publications_.size() + 1);
  surfaces_.reserve(surfaces_.size() + addition_rows.size());
  publications_.push_back(std::move(addition));
  if (!addition_rows.empty()) {
    beginInsertRows({}, first,
                    first + static_cast<qsizetype>(addition_rows.size()) - 1);
    surfaces_.insert(surfaces_.end(),
                     std::make_move_iterator(addition_rows.begin()),
                     std::make_move_iterator(addition_rows.end()));
    endInsertRows();
  }
  emit surfacesChanged();
  return true;
}

bool PluginSurfaceService::withdrawSurfaces(
    const plugins::permissions::ActivationBinding &binding) {
  if (!onOwnerThread() || backend_ == nullptr)
    return false;
  const auto publication = std::ranges::find_if(
      publications_, [&binding](const Publication &candidate) {
        return candidate.binding.plugin == binding.plugin;
      });
  if (publication == publications_.end() || publication->binding != binding)
    return false;
  const auto publication_index = static_cast<std::size_t>(
      std::distance(publications_.begin(), publication));
  const qsizetype first = firstRow(publication_index);
  const qsizetype count =
      static_cast<qsizetype>(publication->declarations.size());
  if (count > 0) {
    beginRemoveRows({}, first, first + count - 1);
    surfaces_.erase(surfaces_.begin() + first,
                    surfaces_.begin() + first + count);
    endRemoveRows();
  }
  publications_.erase(publication);
  emit surfacesChanged();
  return true;
}

bool PluginSurfaceService::publishIntent(
    host_session::AdmittedSurfaceIntent intent) {
  // The product adapter must queue this move-owned value to this object's
  // thread. Freshness is intentionally consumed only at the UI publication
  // boundary, never on the channel worker.
  if (!onOwnerThread() || backend_ == nullptr)
    return false;
  auto publication = intent.take_if_fresh();
  if (!publication)
    return false;
  const auto source =
      canonical_surface_key(publication->binding(), publication->source_name());
  const auto target =
      canonical_surface_key(publication->binding(), publication->target_name());
  const auto *source_declaration = declared(source);
  const auto *target_declaration = declared(target);
  const qulonglong generation = publication->binding().generation;
  if (generation == 0 || source_declaration == nullptr ||
      target_declaration == nullptr ||
      source_declaration->generation != generation ||
      target_declaration->generation != generation)
    return false;
  switch (publication->action()) {
  case surface::SurfaceIntentAction::open:
    emit openRequested(source, target, QString::number(generation));
    return true;
  case surface::SurfaceIntentAction::toggle:
    emit toggleRequested(source, target, QString::number(generation));
    return true;
  case surface::SurfaceIntentAction::dismiss:
    emit dismissRequested(source, target, QString::number(generation));
    return true;
  }
  return false;
}

const PluginSurfaceService::SurfaceRow *
PluginSurfaceService::declared(QStringView surface_key) const {
  const auto found = std::ranges::find_if(
      surfaces_, [surface_key](const SurfaceRow &row) {
        return row.surface_key == surface_key;
      });
  return found == surfaces_.end() ? nullptr : &*found;
}

bool PluginSurfaceService::onOwnerThread() const {
  return QThread::currentThread() == thread();
}

qsizetype PluginSurfaceService::firstRow(
    std::size_t publication_index) const {
  qsizetype first = 0;
  for (std::size_t index = 0; index < publication_index; ++index)
    first += static_cast<qsizetype>(publications_[index].declarations.size());
  return first;
}

std::vector<PluginSurfaceService::SurfaceRow> PluginSurfaceService::rowsFor(
    const Publication &publication) const {
  std::vector<SurfaceRow> rows;
  rows.reserve(publication.declarations.size());
  for (const auto &declaration : publication.declarations) {
    rows.push_back(
        {.surface_key =
             canonical_surface_key(publication.binding, declaration.surface_name),
         .plugin_id = text(publication.binding.plugin.view()),
         .surface_name = text(declaration.surface_name),
         .generation = publication.binding.generation,
         .publication_revision = publication.revision,
         .declaration = declaration});
  }
  return rows;
}

void PluginSurfaceService::clearSurfaces() {
  beginResetModel();
  publications_.clear();
  surfaces_.clear();
  endResetModel();
  emit surfacesChanged();
}

} // namespace omarchy::plugin_runtime::bridge
