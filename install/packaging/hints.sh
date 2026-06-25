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

# ensure hypr config dir and append bindings if missing
hypr_dir="$HOME/.config/hypr"
bindings_file="$hypr_dir/bindings.conf"
mkdir -p "$hypr_dir"
if [[ -f "$bindings_file" && ! -f "${bindings_file}.bak" ]]; then
	cp -a "$bindings_file" "${bindings_file}.bak"
fi
grep -qxF 'bind = SUPER, I, exec, hints' "$bindings_file" 2>/dev/null || cat >>"$bindings_file" <<'EOF'
bind = SUPER, I, exec, hints
bind = SUPER, Y, exec, hints --mode scroll
EOF

