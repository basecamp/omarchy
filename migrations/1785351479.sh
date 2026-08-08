echo "Drop Kvantum now that Qt apps follow the theme through the GTK platform theme"

# QT_STYLE_OVERRIDE is gone, so Kvantum is no longer painting anything -- Qt
# falls back to built-in Fusion and takes its palette from
# QT_QPA_PLATFORMTHEME=gtk3, which actually tracks the Omarchy theme. Kvantum
# never did; we have never shipped a .kvconfig for it to read.
#
# kvantum-qt5 has to go in the same transaction: it is the only thing that
# requires kvantum, so removing kvantum alone fails the dependency check. It has
# been dead weight since VLC was retired anyway, and it takes qt5-svg and
# qt5-x11extras with it.
#
# What this deliberately does NOT touch is qt5-wayland and qt5-declarative. On a
# machine whose sddm theme metadata predates QtVersion=6, those are what keep
# the Qt5 greeter able to start, and removing them is how you end up with no
# login screen. qt5-wayland is explicitly installed, so the -s cascade leaves it
# and the qt5-base beneath it alone.
targets=()
for pkg in kvantum-qt5 kvantum; do
  pacman -Q "$pkg" &>/dev/null && targets+=("$pkg")
done

if ((${#targets[@]})); then
  # Preflight so a surprise reverse dependency prints our sentence rather than a
  # wall of pacman errors, and so neither outcome exits non-zero -- a failing
  # migration aborts every migration queued behind it.
  if pacman -Rs --print "${targets[@]}" >/dev/null 2>&1; then
    sudo pacman -Rns --noconfirm "${targets[@]}" ||
      echo "Could not remove Kvantum; leaving it installed." >&2
  else
    echo "Something still depends on Kvantum; leaving it installed." >&2
  fi
fi
