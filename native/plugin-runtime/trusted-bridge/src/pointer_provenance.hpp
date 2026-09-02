#pragma once

#include <QInputDevice>
#include <Qt>

namespace omarchy::plugin_runtime::bridge::detail {

enum class PointerProvenanceFailure {
  none,
  not_spontaneous,
  synthesized,
  missing_device,
  unsupported_device,
};

struct PointerProvenance {
  PointerProvenanceFailure failure = PointerProvenanceFailure::none;

  [[nodiscard]] bool trusted() const noexcept {
    return failure == PointerProvenanceFailure::none;
  }
};

[[nodiscard]] inline PointerProvenance classify_pointer_provenance(
    bool spontaneous, Qt::MouseEventSource source,
    const QInputDevice *device) noexcept {
  if (!spontaneous)
    return {.failure = PointerProvenanceFailure::not_spontaneous};
  if (source != Qt::MouseEventNotSynthesized)
    return {.failure = PointerProvenanceFailure::synthesized};
  if (device == nullptr)
    return {.failure = PointerProvenanceFailure::missing_device};
  if (device->type() != QInputDevice::DeviceType::Mouse &&
      device->type() != QInputDevice::DeviceType::TouchPad)
    return {.failure = PointerProvenanceFailure::unsupported_device};
  return {};
}

} // namespace omarchy::plugin_runtime::bridge::detail
