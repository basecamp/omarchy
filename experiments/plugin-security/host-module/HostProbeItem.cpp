#include "HostProbeItem.h"

HostProbeItem::HostProbeItem(QQuickItem *parent) : QQuickItem(parent) {
  setFlag(ItemHasContents, false);
}

QString HostProbeItem::probeMarker() const {
  return QStringLiteral("omarchy-plugin-host-loaded");
}
