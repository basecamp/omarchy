#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
stub_dir="$tmpdir/bin"
home_dir="$tmpdir/home"
mkdir -p "$stub_dir" "$home_dir/.local/share/applications"

cat >"$stub_dir/hyprctl" <<'EOF'
#!/bin/bash
if [[ $1 == '-j' && $2 == clients ]]; then
  printf '%s\n' '[{"address":"0x1","class":"Example","initialClass":"Example","title":"Document","pid":42,"workspace":{"id":3},"floating":true,"fullscreen":false,"at":[12,34],"size":[600,400]},{"address":"0x2","class":"org.quickshell","title":"bar"}]'
fi
EOF
chmod +x "$stub_dir/hyprctl"
cat >"$home_dir/.local/share/applications/example.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Example
StartupWMClass=Example
Exec=example
EOF

HOME="$home_dir" XDG_STATE_HOME="$home_dir/.local/state" PATH="$stub_dir:$PATH" "$ROOT/bin/omarchy-session" save
state="$home_dir/.local/state/omarchy/session/last.json"
[[ -f $state ]] || fail "session save creates a durable state file"
jq -e '.schema == 1 and (.clients | length == 1)' "$state" >/dev/null || fail "session save excludes Omarchy shell windows"
[[ $(jq -r '.clients[0].desktop_id' "$state") == example.desktop ]] || fail "session save resolves desktop launch identity"
[[ $(jq -r '.clients[0].address // empty' "$state") == '' ]] || fail "session save excludes ephemeral window addresses"
pass "session save writes restorable application state atomically"
