echo "Align Qt with packaged quickshell 0.3.1 so the shell can load"

# 1787399318 switches quickshell-git to extra/quickshell 0.3.1. That
# package was built against Qt 6.11.2's public Qt_6 ABI for
# QUntypedPropertyBinding(QPropertyBindingPrivate*). qt6-base 6.11.1 only
# exports that constructor as Qt_6_PRIVATE_API. A migrate-only run (no
# pacman -Syu) then leaves Hyprland up with no layers: black desktop,
# mouse only.
#
# Do not undo 1787399318. Do not reinstall quickshell-git.

if ! command -v nm >/dev/null || [[ ! -e /usr/lib/libQt6Core.so.6 ]]; then
  exit 0
fi

if ! pacman -Q quickshell >/dev/null 2>&1; then
  exit 0
fi

# omarchy-migrate runs this under pipefail. nm | grep -q closes the pipe
# on the first match; nm then SIGPIPEs and the pipeline fails even when
# the public Qt_6 ctor exists, so the toast asked for sudo on an aligned box.
if [[ $(nm -D /usr/lib/libQt6Core.so.6) == *QUntypedPropertyBindingC1EP23QPropertyBindingPrivate@@Qt_6* ]]; then
  exit 0
fi

sudo pacman -S --noconfirm --needed qt6-base qt6-declarative qt6-svg qt6-5compat
