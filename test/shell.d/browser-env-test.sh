#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

envs="$ROOT/default/bash/envs"
uwsm_default="$ROOT/default/uwsm/default"
uwsm_env="$ROOT/default/uwsm/env.d/10-omarchy"

browser=$(env -u BROWSER bash -c 'source "$1"; printf "%s" "$BROWSER"' bash "$envs")
[[ $browser == "omarchy-launch-browser" ]] || fail "bash env provides a default browser" "actual: $browser"
pass "bash env provides a default browser"

browser=$(BROWSER=firefox bash -c 'source "$1"; printf "%s" "$BROWSER"' bash "$envs")
[[ $browser == "firefox" ]] || fail "bash env preserves the inherited browser" "actual: $browser"
pass "bash env preserves the inherited browser"

# A session-wide BROWSER makes xdg-settings refuse "set default-web-browser",
# breaking the browsers' own "Set as default" buttons.
browser=$(env -u BROWSER bash -c 'source "$1"; printf "%s" "${BROWSER:-}"' bash "$uwsm_default")
[[ -z $browser ]] || fail "uwsm session env leaves BROWSER unset" "actual: $browser"
pass "uwsm session env leaves BROWSER unset"

! grep -q "export BROWSER" "$uwsm_env" || fail "uwsm env.d fallback leaves BROWSER unset"
pass "uwsm env.d fallback leaves BROWSER unset"

# Global mise shims must not be activated session-wide in UWSM env, which would
# place user-installed toolchains (e.g. Python) before system binaries and crash
# native apps (like Blender) that link against system runtimes.
! grep -q "mise activate" "$uwsm_env" || fail "uwsm session env leaves mise shims un-activated"
pass "uwsm session env leaves mise shims un-activated"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

mock_bin="$tmpdir/bin"
mkdir -p "$mock_bin"
cat >"$mock_bin/mise" <<'EOF'
#!/bin/bash
if [[ "$*" == *"activate"*"--shims"* ]]; then
  echo 'export PATH="/fake/mise/shims:$PATH"'
fi
EOF
chmod +x "$mock_bin/mise"

cat >"$mock_bin/omarchy-cmd-present" <<'EOF'
#!/bin/bash
command -v "$1" >/dev/null 2>&1
EOF
chmod +x "$mock_bin/omarchy-cmd-present"

uwsm_path=$(PATH="$mock_bin:/usr/bin" HOME="$tmpdir" bash -c '
  export OMARCHY_PATH="'"$ROOT"'"
  . "$1"
  printf "%s" "$PATH"
' bash "$uwsm_env")

[[ $uwsm_path != *"/fake/mise/shims"* ]] || fail "uwsm env does not prepend mise shims" "actual: $uwsm_path"
pass "uwsm env does not prepend mise shims"
