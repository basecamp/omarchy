.pragma library

// SDDM's SessionModel.data() only handles its own SessionRoles enum (FileRole =
// Qt.UserRole + 2); it has no Qt.DisplayRole case and returns an invalid
// QVariant for it, so DisplayRole must not be used here. Match on the .desktop
// path rather than the display name: "uwsm" also appears in the name of
// hyprland-uwsm.desktop, which sorts ahead of omarchy.desktop.
function resolveSessionIndex(sessionModel, fileRole) {
  for (var i = 0; i < sessionModel.rowCount(); i++) {
    var file = (sessionModel.data(sessionModel.index(i, 0), fileRole) || "").toString()
    if (file.indexOf("/omarchy.desktop") !== -1)
      return i
  }
  return sessionModel.lastIndex
}
