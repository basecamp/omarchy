#include "SurfaceProjectionModel.h"

#include "gesture_intent.hpp"
#include "omarchy/plugin/wire/surface_name.hpp"
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

QString bar_section_name(SurfaceProjectionModel::BarSection section) {
  switch (section) {
  case SurfaceProjectionModel::BarSection::Left:
    return QStringLiteral("left");
  case SurfaceProjectionModel::BarSection::Right:
    return QStringLiteral("right");
  case SurfaceProjectionModel::BarSection::Unspecified:
  case SurfaceProjectionModel::BarSection::Center:
    return QStringLiteral("center");
  }
  return QStringLiteral("center");
}

} // namespace

struct SurfaceProjectionModel::Publication {
  plugins::permissions::ActivationBinding binding;
  qulonglong revision = 0;
  std::vector<SurfaceDeclaration> declarations;
};

struct SurfaceProjectionModel::SurfaceRow {
  QString surface_key;
  plugins::permissions::ActivationBinding binding;
  qulonglong publication_revision = 0;
  SurfaceDeclaration declaration;
};

class SurfaceProjectionModel::RoleFilterModel final
    : public QSortFilterProxyModel {
public:
  RoleFilterModel(Role role, SurfaceProjectionModel &source)
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

SurfaceProjectionModel::SurfaceProjectionModel(QObject *parent)
    : QAbstractListModel(parent),
      bar_surfaces_(std::make_unique<RoleFilterModel>(Role::Bar, *this)),
      panel_surfaces_(std::make_unique<RoleFilterModel>(Role::Panel, *this)),
      overlay_surfaces_(
          std::make_unique<RoleFilterModel>(Role::Overlay, *this)) {}

SurfaceProjectionModel::~SurfaceProjectionModel() = default;

QAbstractItemModel *SurfaceProjectionModel::barSurfaces() {
  return bar_surfaces_.get();
}

QAbstractItemModel *SurfaceProjectionModel::panelSurfaces() {
  return panel_surfaces_.get();
}

QAbstractItemModel *SurfaceProjectionModel::overlaySurfaces() {
  return overlay_surfaces_.get();
}

int SurfaceProjectionModel::count() const { return rowCount(); }

int SurfaceProjectionModel::rowCount(const QModelIndex &parent) const {
  return parent.isValid() ? 0 : static_cast<int>(surfaces_.size());
}

QVariant SurfaceProjectionModel::data(const QModelIndex &index, int role) const {
  if (!index.isValid() || index.column() != 0 || index.row() < 0 ||
      index.row() >= rowCount())
    return {};
  const auto &row = surfaces_[static_cast<std::size_t>(index.row())];
  switch (role) {
  case SurfaceKeyRole:
    return row.surface_key;
  case PluginIdRole:
    return text(row.binding.plugin.view());
  case SurfaceNameRole:
    return text(row.declaration.surface_name);
  case SurfaceRoleRole:
    return static_cast<int>(row.declaration.role);
  case GenerationRole:
    return QString::number(row.binding.generation);
  case PublicationRevisionRole:
    return QString::number(row.publication_revision);
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

QHash<int, QByteArray> SurfaceProjectionModel::roleNames() const {
  return {{SurfaceKeyRole, "surfaceKey"},
          {PluginIdRole, "pluginId"},
          {SurfaceNameRole, "surfaceName"},
          {SurfaceRoleRole, "surfaceRole"},
          {GenerationRole, "generation"},
          {PublicationRevisionRole, "publicationRevision"},
          {InitiallyVisibleRole, "initiallyVisible"},
          {MaximumWidthRole, "maximumWidth"},
          {MaximumHeightRole, "maximumHeight"},
          {DynamicInputRegionsRole, "dynamicInputRegions"},
          {DefaultSectionRole, "defaultSection"}};
}

bool SurfaceProjectionModel::publishSurfaces(
    const plugins::permissions::ActivationBinding &binding,
    std::vector<SurfaceDeclaration> declarations, qulonglong revision) {
  if (!onOwnerThread() || revision == 0 || binding.generation == 0 ||
      binding.plugin.view().empty() || binding.revision.view().empty() ||
      binding.policy_fingerprint.view().empty() ||
      declarations.empty() ||
      declarations.size() > wire::kMaximumPluginSurfaces)
    return false;
  for (std::size_t index = 0; index < declarations.size(); ++index) {
    const auto &declaration = declarations[index];
    if (!wire::valid_surface_name(declaration.surface_name) ||
        std::ranges::any_of(
            declarations | std::views::take(index),
            [&](const SurfaceDeclaration &prior) {
              return prior.surface_name == declaration.surface_name;
            }) ||
        declaration.maximum_width == 0 || declaration.maximum_height == 0)
      return false;
    switch (declaration.role) {
    case Role::Bar:
      if (declaration.maximum_width > 2048 ||
          declaration.maximum_height > 256)
        return false;
      switch (declaration.default_bar_section) {
      case BarSection::Unspecified:
      case BarSection::Left:
      case BarSection::Center:
      case BarSection::Right:
        break;
      default:
        return false;
      }
      break;
    case Role::Panel:
      if (declaration.maximum_width > 1024 ||
          declaration.maximum_height > 2048 ||
          declaration.default_bar_section != BarSection::Unspecified)
        return false;
      break;
    case Role::Overlay:
      if (declaration.maximum_width > 2048 ||
          declaration.maximum_height > 2048 ||
          declaration.default_bar_section != BarSection::Unspecified)
        return false;
      break;
    default:
      return false;
    }
  }

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

bool SurfaceProjectionModel::withdrawSurfaces(
    const plugins::permissions::ActivationBinding &binding) {
  if (!onOwnerThread())
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

bool SurfaceProjectionModel::publishIntent(
    host_session::AdmittedSurfaceIntent intent) {
  // The product adapter must queue this move-owned value to this object's
  // thread. Freshness is intentionally consumed only at the UI publication
  // boundary, never on the channel worker.
  if (!onOwnerThread())
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
  const auto &binding = publication->binding();
  const qulonglong generation = binding.generation;
  const auto input_sequence = QString::number(publication->input_sequence());
  const auto requested_output =
      QString::fromUtf8(publication->requested_output());
  if (generation == 0 || source_declaration == nullptr ||
      target_declaration == nullptr || source_declaration->binding != binding ||
      target_declaration->binding != binding)
    return false;
  switch (publication->action()) {
  case surface::SurfaceIntentAction::open:
    emit openRequested(source, target, QString::number(generation),
                       input_sequence, requested_output);
    return true;
  case surface::SurfaceIntentAction::toggle:
    emit toggleRequested(source, target, QString::number(generation),
                         input_sequence, requested_output);
    return true;
  case surface::SurfaceIntentAction::dismiss:
    emit dismissRequested(source, target, QString::number(generation),
                          input_sequence);
    return true;
  }
  return false;
}

const SurfaceProjectionModel::SurfaceRow *
SurfaceProjectionModel::declared(QStringView surface_key) const {
  const auto found = std::ranges::find_if(
      surfaces_, [surface_key](const SurfaceRow &row) {
        return row.surface_key == surface_key;
      });
  return found == surfaces_.end() ? nullptr : &*found;
}

std::optional<PublishedSurfaceAttachment>
SurfaceProjectionModel::resolve(QStringView surface_key) const {
  if (!onOwnerThread() || surface_key.isEmpty())
    return std::nullopt;
  const auto *row = declared(surface_key);
  if (row == nullptr)
    return std::nullopt;
  return PublishedSurfaceAttachment(row->surface_key, row->binding,
                                    row->declaration.surface_name,
                                    row->publication_revision);
}

bool SurfaceProjectionModel::onOwnerThread() const {
  return QThread::currentThread() == thread();
}

qsizetype SurfaceProjectionModel::firstRow(
    std::size_t publication_index) const {
  qsizetype first = 0;
  for (std::size_t index = 0; index < publication_index; ++index)
    first += static_cast<qsizetype>(publications_[index].declarations.size());
  return first;
}

std::vector<SurfaceProjectionModel::SurfaceRow> SurfaceProjectionModel::rowsFor(
    const Publication &publication) const {
  std::vector<SurfaceRow> rows;
  rows.reserve(publication.declarations.size());
  for (const auto &declaration : publication.declarations) {
    rows.push_back(
        {.surface_key =
             canonical_surface_key(publication.binding, declaration.surface_name),
         .binding = publication.binding,
         .publication_revision = publication.revision,
         .declaration = declaration});
  }
  return rows;
}

} // namespace omarchy::plugin_runtime::bridge
