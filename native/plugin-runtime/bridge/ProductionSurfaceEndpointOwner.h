#pragma once

#include "permission_contract.hpp"

#include <QString>
#include <QStringView>

#include <cstdint>
#include <memory>
#include <optional>
#include <string>
#include <thread>
#include <utility>
#include <vector>

namespace omarchy::plugin_runtime::channel {
class ProductionSurfaceSessionPort;
}

namespace omarchy::plugin_runtime::surface_host {
class InspectionAuthority;
class MonotonicClock;
} // namespace omarchy::plugin_runtime::surface_host

namespace omarchy::plugin_runtime::bridge {

class PluginManager;
class ProductionSurfaceEndpoint;
class RemotePluginSurface;

enum class ProductionEndpointAttachResult : std::uint8_t {
  attached,
  not_ready,
  rejected,
};

// One exact row selected from PluginManager's private published model. QML can
// return only its opaque key; it cannot construct or alter this context.
class PublishedSurfaceAttachment final {
public:
  PublishedSurfaceAttachment(PublishedSurfaceAttachment &&) noexcept = default;
  PublishedSurfaceAttachment &
  operator=(PublishedSurfaceAttachment &&) noexcept = default;
  PublishedSurfaceAttachment(const PublishedSurfaceAttachment &) = delete;
  PublishedSurfaceAttachment &
  operator=(const PublishedSurfaceAttachment &) = delete;

private:
  PublishedSurfaceAttachment(QString surface_key,
                             plugins::permissions::ActivationBinding binding,
                             std::string declared_surface,
                             qulonglong publication_revision) noexcept;

  QString surface_key_;
  plugins::permissions::ActivationBinding binding_;
  std::string declared_surface_;
  qulonglong publication_revision_ = 0;

  friend class PluginManager;
  friend class ProductionSurfaceEndpointOwner;
#ifdef OMARCHY_PRODUCTION_SURFACE_ENDPOINT_OWNER_TESTING
  friend class ProductionSurfaceEndpointOwnerTestAccess;
#endif
};

// Event-loop-confined owner of every live endpoint. A not-ready attachment is
// not retained: PluginManager may retry after the trusted QQuickItem acquires a
// window and settled geometry. Exact binding teardown must run before its
// ProductionPluginRuntimeRoot is destroyed or replaced.
class ProductionSurfaceEndpointOwner final {
public:
  ~ProductionSurfaceEndpointOwner() noexcept;
  ProductionSurfaceEndpointOwner(const ProductionSurfaceEndpointOwner &) =
      delete;
  ProductionSurfaceEndpointOwner &
  operator=(const ProductionSurfaceEndpointOwner &) = delete;

private:
  ProductionSurfaceEndpointOwner(
      surface_host::InspectionAuthority &inspection,
      surface_host::MonotonicClock &clock,
      plugins::permissions::ActivationBinding binding,
      qulonglong publication_revision,
      channel::ProductionSurfaceSessionPort &session) noexcept;

  [[nodiscard]] ProductionEndpointAttachResult
  attach(const PublishedSurfaceAttachment &published, QStringView qml_key,
         RemotePluginSurface &surface) noexcept;
  void close_all() noexcept;

  struct Record;
  void prune_closed() noexcept;
  [[nodiscard]] bool on_owner_thread() const noexcept;

  surface_host::InspectionAuthority &inspection_;
  surface_host::MonotonicClock &clock_;
  const plugins::permissions::ActivationBinding binding_;
  const qulonglong publication_revision_;
  channel::ProductionSurfaceSessionPort &session_;
  const std::thread::id owner_thread_;
  std::vector<Record> records_;

  friend class PluginManager;
#ifdef OMARCHY_PRODUCTION_SURFACE_ENDPOINT_OWNER_TESTING
  friend class ProductionSurfaceEndpointOwnerTestAccess;
#endif
};

#ifdef OMARCHY_PRODUCTION_SURFACE_ENDPOINT_OWNER_TESTING
class ProductionSurfaceEndpointOwnerTestAccess final {
public:
  struct Geometry final {
    std::uint32_t logical_width = 0;
    std::uint32_t logical_height = 0;
    std::uint32_t dpr_numerator = 0;
    std::uint32_t dpr_denominator = 0;
  };

  [[nodiscard]] static PublishedSurfaceAttachment
  published(QString surface_key,
            plugins::permissions::ActivationBinding binding,
            std::string declared_surface, qulonglong publication_revision) {
    return PublishedSurfaceAttachment(
        std::move(surface_key), std::move(binding), std::move(declared_surface),
        publication_revision);
  }
  [[nodiscard]] static std::unique_ptr<ProductionSurfaceEndpointOwner>
  create(surface_host::InspectionAuthority &inspection,
         surface_host::MonotonicClock &clock,
         plugins::permissions::ActivationBinding binding,
         qulonglong publication_revision,
         channel::ProductionSurfaceSessionPort &session) {
    return std::unique_ptr<ProductionSurfaceEndpointOwner>(
        new ProductionSurfaceEndpointOwner(inspection, clock,
                                           std::move(binding),
                                           publication_revision, session));
  }
  [[nodiscard]] static ProductionEndpointAttachResult
  attach(ProductionSurfaceEndpointOwner &owner,
         const PublishedSurfaceAttachment &published, QStringView qml_key,
         RemotePluginSurface &surface) noexcept {
    return owner.attach(published, qml_key, surface);
  }
  static void close_all(ProductionSurfaceEndpointOwner &owner) noexcept {
    owner.close_all();
  }
  [[nodiscard]] static std::size_t
  count(const ProductionSurfaceEndpointOwner &owner) noexcept;
  [[nodiscard]] static std::optional<Geometry>
  geometry(const RemotePluginSurface &surface) noexcept;
  [[nodiscard]] static std::optional<Geometry>
  geometry(qreal width, qreal height, qreal device_pixel_ratio) noexcept;
};
#endif

} // namespace omarchy::plugin_runtime::bridge
