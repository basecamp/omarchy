#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

cat >"$tmp_dir/setsid" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "$*" >"$TEST_LOG"
SCRIPT
chmod +x "$tmp_dir/setsid"

export TEST_LOG="$tmp_dir/log"
export PATH="$tmp_dir:$ROOT/bin:$PATH"

"$ROOT/bin/omarchy-launch-floating-terminal-with-presentation" "echo hello"

launch=$(<"$TEST_LOG")
[[ $launch == *"xdg-terminal-exec --app-id=org.omarchy.terminal"* ]] || fail "floating terminal launches Omarchy terminal" "$launch"
pass "floating terminal launches Omarchy terminal"

# The launcher ends by taking over the process, so source it short of its
# --render branch and the fit can be exercised here, without a terminal to draw on.
presentation="$ROOT/bin/omarchy-launch-floating-terminal-with-presentation"
anchor_line=$(grep -Fxn 'if [[ ${1:-} == "--render" ]]; then' "$presentation" | cut -d: -f1)
[[ -n $anchor_line ]] || fail "presentation launcher can be sourced short of its render branch"
head -n $(( anchor_line - 1 )) "$presentation" >"$tmp_dir/presentation.bash"

export OMARCHY_PATH="$tmp_dir/omarchy-path"
mkdir -p "$OMARCHY_PATH"
printf '%s\n' 'XXXXXXXXXX' >"$OMARCHY_PATH/logo.txt"

source "$tmp_dir/presentation.bash"

[[ $(type -t settle_grid) == "function" && $(type -t hypr_dispatch) == "function" ]] ||
  fail "the launcher finds the shared resize helpers it sources"
pass "the launcher finds the shared resize helpers it sources"

# The window-rule cache (presize_window/apply_size_rule/remember_fit) was
# confirmed to have no effect on the size a window opens at and was dropped
# rather than kept as dead weight alongside the live nudge.
for removed in presize_window apply_size_rule remember_fit; do
  [[ $(type -t "$removed" 2>/dev/null) != "function" ]] || fail "$removed was dropped as dead code"
done
pass "the non-functional size-rule cache was dropped as dead code"

clients_json='[]'
hyprctl() {
  if [[ $1 == clients ]]; then
    printf '%s' "$clients_json"
  elif [[ $1 == dispatch ]]; then
    return 0
  fi
}
stty() { printf '%s\n' "50 80"; }

# own_client's ancestry walk matches this process's own pid directly, and does
# so even when another window shares the class -- the fallback below is only
# for when no pid in the ancestry matches at all.
clients_json=$(jq -n --arg pid "$$" \
  '[{class:"org.omarchy.terminal", pid: ($pid | tonumber), address:"0xmine", size:[321,222]},
    {class:"org.omarchy.terminal", pid: 999999999, address:"0xother", size:[1,1]}]')
result=$(own_client)
[[ $result == "0xmine 321 222" ]] || fail "own_client matches its own pid over an unrelated window of the same class" "$result"
pass "own_client matches its own pid over an unrelated window of the same class"

# A terminal running as a persistent server (e.g. `foot --server`) maps the
# window from a process that isn't this script's ancestor, so the ancestry
# walk never matches. $APP_ID is exclusive to this launcher, so when exactly
# one client carries it, that one is unambiguously ours.
clients_json=$(jq -n \
  '[{class:"org.omarchy.terminal", pid: 999999999, address:"0xsolo", size:[444,333]}]')
result=$(own_client)
[[ $result == "0xsolo 444 333" ]] || fail "own_client falls back to the sole client of its class" "$result"
pass "own_client falls back to the sole client of its class"

# Ambiguous is not a guess: two clients of the class and no pid match leaves
# nothing safe to fall back to, so own_client reports nothing rather than
# picking one of them.
clients_json=$(jq -n \
  '[{class:"org.omarchy.terminal", pid: 999999999, address:"0xa", size:[1,1]},
    {class:"org.omarchy.terminal", pid: 999999998, address:"0xb", size:[2,2]}]')
if result=$(own_client); then
  fail "own_client refuses to guess between two unmatched clients of its class" "$result"
else
  pass "own_client refuses to guess between two unmatched clients of its class"
fi

# A window whose reported height is momentarily 0 -- read before the compositor
# has finished populating a just-mapped client's geometry -- must not be divided
# into, which is what silently drove a bad resize before this guard existed.
clients_json=$(jq -n --arg pid "$$" \
  '[{class:"org.omarchy.terminal", pid: ($pid | tonumber), address:"0xzero", size:[500,0]}]')
if fit_window; then
  fail "fit_window refuses a client whose height reads as 0"
else
  pass "fit_window refuses a client whose height reads as 0"
fi

# own_client walks this script's own process ancestry, which costs a real
# ps/hyprctl round trip per ancestor -- worth paying once per fit, not once per
# nudge. Spy on it to confirm fit_window only calls it the once, reading
# updated geometry through the cheaper client_geometry lookup thereafter.
# own_client is invoked as $(own_client), which forks a subshell -- a counter
# incremented inside it would never be seen back here, so the spy counts calls
# through a file instead.
eval "$(declare -f own_client | sed '1s/own_client/_real_own_client/')"
own_client_call_log="$tmp_dir/own_client_calls"
: >"$own_client_call_log"
own_client() {
  printf 'x' >>"$own_client_call_log"
  _real_own_client
}

clients_json=$(jq -n --arg pid "$$" \
  '[{class:"org.omarchy.terminal", pid: ($pid | tonumber), address:"0xstuck", size:[100,50]}]')
fit_window && fail "fit_window should exhaust its nudge budget against a window stuck off-target" ||
  pass "fit_window exhausts its nudge budget rather than nudging forever"

own_client_calls=$(wc -c <"$own_client_call_log")
(( own_client_calls == 1 )) || fail "fit_window resolves the client once and reuses it across nudges" "own_client called $own_client_calls times"
pass "fit_window resolves the client once and reuses it across nudges"
