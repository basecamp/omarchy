#!/bin/bash
set -euo pipefail
# install hints
tmp_installer="$(mktemp)"
curl -fsSL https://raw.githubusercontent.com/AlfredoSequeida/hints/main/install.sh -o "$tmp_installer"
bash "$tmp_installer"
rm -f "$tmp_installer"

# setup hints
hints_cmd="$(command -v hints || true)"
if [[ -n "$hints_cmd" ]]; then
	sudo env XDG_SESSION_TYPE="${XDG_SESSION_TYPE-}" XDG_CURRENT_DESKTOP="${XDG_CURRENT_DESKTOP-}" "$hints_cmd" --setup
else
	echo "hints not found in PATH; skipping setup" >&2
fi

# Add Hyprland bindings (Omarchy uses Lua config modules under ~/.config/hypr/*.lua)
for bindings_file in "$HOME/.local/share/omarchy/config/hypr/bindings.lua" "$HOME/.config/hypr/bindings.lua"; do
  [[ -f $bindings_file ]] || continue

  if ! grep -qxF 'o.bind("SUPER + I", "Hints", { launch = "hints" })' "$bindings_file"; then
    cat >>"$bindings_file" <<'EOF'

-- Hints (vimium-style window navigation)
o.bind("SUPER + I", "Hints", { launch = "hints" })
o.bind("SUPER + Y", "Hints scroll", { launch = "hints --mode scroll" })
EOF
  fi
done

