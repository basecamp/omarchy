-- Let Hyprland upscale X11 (XWayland) apps to match the monitor scale.
--
-- By default Omarchy sets xwayland:force_zero_scaling, which hands X11 clients
-- an unscaled surface. Toolkit-aware apps (GTK/Qt/Electron) then scale
-- themselves via GDK_SCALE/QT_* and stay crisp. Apps that ignore those hints
-- render at 1x instead, so on a 2x monitor their text and controls come out
-- half size (RealVNC Viewer, older Java/Motif/Tk apps, some installers).
--
-- Turning this flag on drops force_zero_scaling so the compositor upscales
-- those windows to the monitor scale: correct apparent size, at the cost of
-- slightly softer text on X11 apps that were already scaling themselves.
hl.config({
  xwayland = {
    force_zero_scaling = false,
  },
})
