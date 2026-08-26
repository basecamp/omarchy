echo "Pin Cursor password store to gnome-libsecret so GitHub login can use the OS keyring"

# Cursor is a VS Code fork. On Hyprland, Electron cannot identify GNOME Keyring
# from XDG_CURRENT_DESKTOP, so GitHub login offers "weaker encryption" instead.
# Existing installs went through the generic package launcher and never got the
# argv.json pin VS Code writes at install time. Leave an explicit password-store
# alone so a user who chose "basic" is not silently moved.

if [[ -d $HOME/.cursor ]] || omarchy-cmd-present cursor; then
  argv="$HOME/.cursor/argv.json"
  mkdir -p "$HOME/.cursor"

  if [[ ! -f $argv ]]; then
    cat > "$argv" << 'EOF'
{
  "password-store": "gnome-libsecret"
}
EOF
  elif ! grep -q '"password-store"' "$argv"; then
    python3 - "$argv" << 'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
idx = text.rfind("}")
if idx < 0:
    path.write_text(text.rstrip() + '\n{\n  "password-store": "gnome-libsecret"\n}\n')
    raise SystemExit(0)
head = text[:idx].rstrip()
if head.endswith("{") or head.endswith(","):
    insert = '\n  "password-store": "gnome-libsecret"\n'
else:
    insert = ',\n  "password-store": "gnome-libsecret"\n'
path.write_text(head + insert + text[idx:])
PY
  fi
fi
