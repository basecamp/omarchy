#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

feeds_class='^org\.omarchy\.acceptance\.feeds$'
agent_class='^org\.omarchy\.acceptance\.newsboat-agent$'
confirmation_namespace='omarchy-newsboat-confirmation'
original_workspace=$(hyprctl -j activeworkspace | jq -r '.id')
test_workspace=${OMARCHY_FEEDS_ACCEPTANCE_WORKSPACE:-9}

if ! command -v newsboat >/dev/null 2>&1; then
  if [[ ${OMARCHY_FEEDS_ACCEPTANCE_REQUIRE_FEEDS:-0} == 1 ]]; then
    fail "Feeds UI acceptance requires Newsboat" "install Newsboat or unset OMARCHY_FEEDS_ACCEPTANCE_REQUIRE_FEEDS"
  fi
  pass "Feeds UI acceptance skipped because optional Newsboat is not installed"
  exit 0
fi

if pgrep -u "$UID" -x newsboat >/dev/null 2>&1; then
  fail "Feeds acceptance starts with no running Newsboat" "close Feeds before running this test"
fi

test_root=$(mktemp -d /tmp/omarchy-feeds-acceptance.XXXXXXXX)
test_home="$test_root/home"
mock_bin="$test_root/bin"
server_log="$test_root/feed-server.log"
agent_log="$test_root/agent-prompt.log"
brief_dir="$test_root/briefs"
triage_output="$test_root/triage-output"
triage_error="$test_root/triage-error"
feed_port=18741
server_pid=""
triage_pid=""
newsboat_pid=""
unrelated_newsboat_pid=""
confirmation_owned=false

cleanup() {
  set +e

  if [[ $confirmation_owned == "true" ]] && layer_present "$confirmation_namespace" >/dev/null 2>&1; then
    wtype -k Escape >/dev/null 2>&1 || true
  fi
  [[ -z $triage_pid ]] || kill "$triage_pid" >/dev/null 2>&1 || true
  close_windows "$agent_class"
  close_windows "$feeds_class"
  [[ -z $newsboat_pid ]] || kill "$newsboat_pid" >/dev/null 2>&1 || true
  [[ -z $unrelated_newsboat_pid ]] || kill "$unrelated_newsboat_pid" >/dev/null 2>&1 || true
  [[ -z $server_pid ]] || kill "$server_pid" >/dev/null 2>&1 || true
  hyprctl dispatch "hl.dsp.focus({ workspace = \"$original_workspace\" })" >/dev/null 2>&1 || true
  if [[ ${OMARCHY_FEEDS_ACCEPTANCE_KEEP_STATE:-0} == 1 ]]; then
    printf 'Feeds acceptance state kept at %s\n' "$test_root" >&2
  else
    rm -rf -- "$test_root"
  fi
}
trap cleanup EXIT

hyprctl dispatch "hl.dsp.focus({ workspace = \"$test_workspace\" })" >/dev/null
wait_until "Feeds acceptance focuses its isolated workspace" 15 bash -c \
  '[[ $(hyprctl -j activeworkspace | jq -r .id) == "$1" ]]' _ "$test_workspace"
# The graphical suite can run unattended long enough for the decorative
# screensaver terminal to appear. Remove it before asserting that the isolated
# workspace is empty; a real lock surface is not a normal client and remains
# outside this test's authority.
close_windows '^org\.omarchy\.screensaver$'
wait_until "Feeds acceptance clears the idle screensaver" 15 \
  window_absent '^org\.omarchy\.screensaver$'
if layer_present "$confirmation_namespace" >/dev/null 2>&1; then
  fail "Feeds acceptance starts without another confirmation" "finish or cancel the existing Newsboat confirmation before running this test"
fi
workspace_windows=$(hyprctl -j clients | jq --argjson workspace "$test_workspace" \
  '[.[] | select(.workspace.id == $workspace)] | length')
(( workspace_windows == 0 )) || \
  fail "Feeds acceptance workspace starts empty" "workspace $test_workspace has $workspace_windows windows"

# Layer-shell surfaces receive keyboard input before normal windows. Start from
# a known state so a launcher left open by an earlier test cannot consume the
# Newsboat keystrokes and create a convincing false failure (or false pass).
omarchy-shell shell hide omarchy.menu >/dev/null 2>&1 || true
wtype -k Escape >/dev/null 2>&1 || true
wait_until "Feeds acceptance has no open launcher" 15 layer_absent "omarchy-menu"

mkdir -p \
  "$mock_bin" \
  "$test_home/.config/newsboat" \
  "$test_home/.local/share/newsboat" \
  "$brief_dir"

cp -- "$ROOT/default/newsboat/config" "$test_home/.config/newsboat/config"
cp -- "$ROOT/default/newsboat/omarchy.conf" "$test_home/.config/newsboat/omarchy.conf"
printf '%s\n' \
  '"query:Inbox:unread = \"yes\""' \
  "http://127.0.0.1:$feed_port/alpha.xml" \
  >"$test_home/.config/newsboat/urls"

cat >"$mock_bin/omarchy-default-agent" <<'SH'
#!/bin/bash
printf 'acceptance-agent\n'
SH

cat >"$mock_bin/omarchy-agent-prompt" <<'SH'
#!/bin/bash
set -euo pipefail

if [[ ${1:-} == "--conversation" && $# == 2 ]]; then
  prompt=$2
elif (($# == 1)); then
  prompt=$1
else
  exit 64
fi

case $prompt in
  "Help me understand this RSS article."*) kind=article ;;
  "Give me a sharp daily briefing"*) kind=brief ;;
  "Act as my Feed Scout."*) kind=scout ;;
  *) kind=unknown ;;
esac

printf '%s' "$prompt" >>"$FEEDS_ACCEPTANCE_AGENT_LOG"
printf '\n--- %s invocation ---\n' "$kind" >>"$FEEDS_ACCEPTANCE_AGENT_LOG"

exec foot --app-id=org.omarchy.acceptance.newsboat-agent sh -c '
  printf "\n  Feeds %s opened\n\n  Deterministic acceptance agent\n" "$1"
  exec sleep 300
' sh "$kind"
SH
chmod +x "$mock_bin/omarchy-default-agent" "$mock_bin/omarchy-agent-prompt"

export HOME="$test_home"
export XDG_CONFIG_HOME="$test_home/.config"
export XDG_DATA_HOME="$test_home/.local/share"
export PATH="$mock_bin:$ROOT/bin:$PATH"
export NEWSBOAT_CACHE_FILE="$test_home/.local/share/newsboat/cache.db"
export NEWSBOAT_URLS_FILE="$test_home/.config/newsboat/urls"
export NEWSBOAT_BRIEF_STATE_DIR="$brief_dir"
export NEWSBOAT_CONFIRM_STATE_DIR="$test_root/confirmations"
export NEWSBOAT_READER_STATE_DIR="$test_root/readers"
export FEEDS_ACCEPTANCE_AGENT_LOG="$agent_log"

if curl --connect-timeout 1 --silent --fail \
  "http://127.0.0.1:$feed_port/alpha.xml" >/dev/null 2>&1; then
  fail "Feeds acceptance fixture port is available" "127.0.0.1:$feed_port is already serving HTTP"
fi

python3 -m http.server "$feed_port" \
  --bind 127.0.0.1 \
  --directory "$ROOT/test/fixtures/newsboat" \
  >"$server_log" 2>&1 &
server_pid=$!

wait_until "local Feeds fixture server starts" 15 \
  bash -c 'curl --silent --fail "$1" | grep -Fq "Alpha Engineering"' _ \
  "http://127.0.0.1:$feed_port/alpha.xml"
kill -0 "$server_pid" 2>/dev/null || \
  fail "local Feeds fixture server remains running" "$(tail -20 "$server_log")"

launch_app "foot --app-id=org.omarchy.acceptance.feeds -e omarchy-feeds"
wait_until "Feeds opens in a terminal" 45 window_present "$feeds_class"
wait_until "Feeds renders the first local subscription" 30 screen_contains "Alpha Engineering"
newsboat_pid=$(pgrep -n -u "$UID" -x newsboat)
[[ -n $newsboat_pid ]] || fail "Feeds starts a Newsboat process"
screenshot "success-feeds-01-initial-edition"

focus_feeds() {
  local address
  address=$(hyprctl -j clients | jq -r --arg class "$feeds_class" \
    '.[] | select(.class | test($class)) | .address' | head -1)
  [[ -n $address ]] || return 1
  hyprctl dispatch "hl.dsp.focus({ window = \"address:$address\" })" >/dev/null 2>&1 ||
    hyprctl dispatch focuswindow "address:$address" >/dev/null
}

# Add a feed while the reader is already open, then use its visible refresh
# action. This covers the otherwise easy-to-miss reload-urls interaction.
omarchy-newsboat-subscribe "http://127.0.0.1:$feed_port/beta.html" >/dev/null
grep -Fq "http://127.0.0.1:$feed_port/beta.xml" "$NEWSBOAT_URLS_FILE" || \
  fail "browser subscription stores the resolved feed URL"
omarchy-shell notifications dismissAll >/dev/null 2>&1 || true
wait_until "subscription notification clears before visual verification" 15 \
  layer_absent "omarchy-notifications"
focus_feeds
wtype -k r
cache_contains_beta() {
  python3 - "$NEWSBOAT_CACHE_FILE" <<'PY'
import sqlite3
import sys

with sqlite3.connect(f"file:{sys.argv[1]}?mode=ro", uri=True) as database:
    count = database.execute(
        "SELECT COUNT(*) FROM rss_item WHERE guid = 'omarchy-acceptance-beta' AND deleted = 0"
    ).fetchone()[0]
raise SystemExit(0 if count == 1 else 1)
PY
}
wait_until "running Feeds collects the newly subscribed article" 30 cache_contains_beta
# Match the distinctive stem because terminal OCR can confuse the final m at
# this font size (for example, "Systems" becomes "Systens"). The notification
# is already gone and the cache assertion above proves the exact feed identity.
wait_until "running Feeds displays a newly subscribed feed" 30 screen_contains "Beta Syst"
[[ $(pgrep -n -u "$UID" -x newsboat) == "$newsboat_pid" ]] || \
  fail "subscription refresh keeps the running reader"
screenshot "success-feeds-02-live-subscription-refresh"

client_is_tiled() {
  hyprctl -j clients | jq -e --arg class "$feeds_class" '
    .[] | select(.class | test($class))
    | select(.floating == false and (.fullscreenClient // 0) == 0)
  ' >/dev/null
}

client_is_floating() {
  hyprctl -j clients | jq -e --arg class "$feeds_class" '
    .[] | select(.class | test($class)) | select(.floating == true)
  ' >/dev/null
}

newsboat_columns() {
  local tty
  tty=$(ps -o tty= -p "$newsboat_pid" | tr -d '[:space:]')
  [[ -n $tty && $tty != "?" ]] || return 1
  stty -F "/dev/$tty" size | awk '{print $2}'
}

wait_for_column_growth() {
  local previous=$1 current
  current=$(newsboat_columns) || return 1
  (( current >= previous + 20 ))
}

# The host acceptance harness proves compositor key chords with hardware input;
# wtype is intentionally limited to focused controls. Exercise the exact
# Super+T dispatcher here and verify Newsboat responds to both PTY resizes.
toggle_feeds_float() {
  local address
  address=$(hyprctl -j clients | jq -r --arg class "$feeds_class" \
    '.[] | select(.class | test($class)) | .address' | head -1)
  [[ -n $address ]] || return 1
  hyprctl dispatch "hl.dsp.window.float({ window = \"address:$address\", action = \"toggle\" })" >/dev/null 2>&1 ||
    hyprctl dispatch togglefloating "address:$address" >/dev/null
}

toggle_feeds_float
wait_until "Super+T dispatcher floats Feeds" 15 client_is_floating
screenshot "success-feeds-03-floating"
toggle_feeds_float
wait_until "Super+T dispatcher returns Feeds to its tile" 15 client_is_tiled
wide_columns=$(newsboat_columns)
(( wide_columns >= 100 )) || fail "tiled Feeds terminal uses the available width" "only $wide_columns columns"
screenshot "success-feeds-04-retiled"

# Ask about one real article from the Inbox. This crosses the feed list,
# article list, browser-operation handoff, and configured-agent boundary.
focus_feeds
wtype -k Return
wait_until "Inbox opens its article list" 15 screen_contains "Beta reliability"
wtype -k comma
wtype -k a
wait_until "comma-a opens the configured agent beside Feeds" 45 window_present "$agent_class"
wait_until "article prompt contains the selected RSS context" 15 \
  grep -Fq "Help me understand this RSS article." "$agent_log"
window_present "$feeds_class" >/dev/null || fail "article handoff keeps Feeds open"
screenshot "success-feeds-05-article-agent-handoff"
close_windows "$agent_class"
wait_until "article agent window closes" 15 window_absent "$agent_class"
focus_feeds
wtype -k h
wait_until "article list returns to the feed list" 15 screen_contains "finite edition"

# Invoke the briefing from the synthetic Inbox on the very first attempt. The
# agent stand-in makes the graphical handoff deterministic while the real
# Newsboat macro, snapshot builder, Foot window, and Hyprland tiling still run.
focus_feeds
wtype -k comma
wtype -k b
wait_until "first comma-b opens the configured agent" 45 window_present "$agent_class"
wait_until "first comma-b creates a briefing snapshot" 30 bash -c 'compgen -G "$1/brief.*" >/dev/null' _ "$brief_dir"
wait_until "briefing prompt includes both unread articles" 30 grep -Fq "There are 2 unread entries" "$agent_log"
client_is_tiled || fail "Feeds remains tiled beside the briefing"
if screen_contains "Cannot open query feeds"; then
  fail "briefing works from the Inbox query"
fi
split_columns=$(newsboat_columns)
(( split_columns < wide_columns )) || \
  fail "briefing creates a spare tile beside Feeds" "wide=$wide_columns split=$split_columns"
screenshot "success-feeds-06-first-brief-tiled"

# Closing the agent must immediately let the still-running reader consume the
# larger PTY. This is the regression for the half-width content after resize.
close_windows "$agent_class"
wait_until "briefing window closes" 15 window_absent "$agent_class"
wait_until "Feeds redraws to the reclaimed width" 15 wait_for_column_growth "$split_columns"
[[ $(pgrep -n -u "$UID" -x newsboat) == "$newsboat_pid" ]] || \
  fail "closing the briefing keeps Feeds running"
screenshot "success-feeds-07-reader-redraw-after-agent-close"

# A second invocation catches lifecycle bugs hidden by warm state or stale
# detached browser commands.
focus_feeds
wtype -k comma
wtype -k b
wait_until "repeated comma-b opens the configured agent" 45 window_present "$agent_class"
invocations=$(grep -c '^--- brief invocation ---$' "$agent_log")
(( invocations == 2 )) || fail "repeated comma-b reaches the agent exactly twice" "$invocations invocations"
screenshot "success-feeds-08-repeated-brief"

brief_file=$(find "$brief_dir" -maxdepth 1 -type f -name 'brief.*' -printf '%T@ %p\n' | sort -nr | head -1 | cut -d' ' -f2-)
brief_id=${brief_file##*/brief.}
[[ $brief_id =~ ^[A-Za-z0-9_-]{8,64}$ ]] || fail "briefing exposes a valid protected ID"

# Keep an unrelated same-user process with Newsboat's process name alive for
# the mutation journey. Confirmed triage must close only the registered Feeds
# child for this cache, never every process named newsboat.
python3 - <<'PY' &
import ctypes
import time

libc = ctypes.CDLL(None)
libc.prctl(15, b"newsboat", 0, 0, 0)
time.sleep(300)
PY
unrelated_newsboat_pid=$!
wait_until "unrelated Newsboat-named process starts" 15 bash -c \
  '[[ $(ps -o comm= -p "$1" | tr -d "[:space:]") == newsboat ]]' _ "$unrelated_newsboat_pid"

unread_count() {
  python3 - "$NEWSBOAT_CACHE_FILE" <<'PY'
import sqlite3
import sys

with sqlite3.connect(f"file:{sys.argv[1]}?mode=ro", uri=True) as database:
    count = database.execute(
        "SELECT COUNT(*) FROM rss_item WHERE unread = 1 AND deleted = 0"
    ).fetchone()[0]
print(count)
PY
}

wait_for_process_exit() {
  ! kill -0 "$1" >/dev/null 2>&1
}

# Default focus is deliberately Cancel. Prove that an accidental Enter leaves
# both the edition and the briefing intact.
omarchy-newsboat-triage "$brief_id" 1 1 A001 >"$triage_output" 2>"$triage_error" &
triage_pid=$!
wait_until "triage opens the native confirmation" 15 layer_on_screen "$confirmation_namespace"
kill -0 "$triage_pid" 2>/dev/null || fail "triage owns the visible native confirmation" "the triage helper exited before its confirmation was answered"
confirmation_owned=true
wait_until "confirmation explains the exact read count" 15 screen_contains "1 article will be marked read"
screenshot "success-feeds-09-confirmation-default-cancel"
wtype -k Return
wait_until "default confirmation choice closes safely" 15 layer_absent "$confirmation_namespace"
confirmation_owned=false
wait_until "cancelled triage returns" 15 wait_for_process_exit "$triage_pid"
triage_status=0
wait "$triage_pid" || triage_status=$?
triage_pid=""
(( triage_status == 0 )) || fail "cancelled triage reports a safe result" "$(<"$triage_error")"
[[ $(unread_count) == 2 ]] || fail "cancelled triage preserves the unread edition"
[[ -f $brief_file ]] || fail "cancelled triage preserves the briefing"
window_present "$feeds_class" >/dev/null || fail "cancelled triage leaves Feeds open"

# Repeat the same protected command, explicitly select Apply, and verify the
# real Newsboat import—not just the helper's exit code or notification.
omarchy-newsboat-triage "$brief_id" 1 1 A001 >"$triage_output" 2>"$triage_error" &
triage_pid=$!
wait_until "confirmed triage reopens the native confirmation" 15 layer_on_screen "$confirmation_namespace"
kill -0 "$triage_pid" 2>/dev/null || fail "confirmed triage owns the visible native confirmation" "the triage helper exited before its confirmation was answered"
confirmation_owned=true
sleep 0.3
wtype -k Right
sleep 0.1
wtype -k Return
wait_until "approved confirmation closes" 15 layer_absent "$confirmation_namespace"
confirmation_owned=false
wait_until "approved triage returns" 30 wait_for_process_exit "$triage_pid"
triage_status=0
wait "$triage_pid" || triage_status=$?
triage_pid=""
(( triage_status == 0 )) || fail "approved triage applies successfully" "$(<"$triage_error")"
wait_until "approved triage closes Feeds before import" 15 window_absent "$feeds_class"
kill -0 "$unrelated_newsboat_pid" 2>/dev/null || fail "approved triage leaves unrelated Newsboat processes running"
pass "approved triage leaves unrelated Newsboat processes running"
[[ $(unread_count) == 1 ]] || fail "approved triage marks exactly one article read" "$(unread_count) remain unread"
[[ ! -e $brief_file ]] || fail "approved triage consumes its protected briefing"
grep -Fq '1 marked read; 1 left unread.' "$triage_output" || fail "approved triage reports its exact result"
close_windows "$agent_class"
wait_until "completed briefing agent closes before Feed Scout" 15 window_absent "$agent_class"

# Finish on the third agent entry point. Feed Scout should receive selected-
# article context and intentionally close Newsboat while its research session
# takes over the workspace.
launch_app "foot --app-id=org.omarchy.acceptance.feeds -e omarchy-feeds"
wait_until "Feeds reopens after confirmed triage" 45 window_present "$feeds_class"
wait_until "reopened Feeds shows the retained feed" 30 screen_contains "Beta Syst"
screenshot "success-feeds-10-confirmed-triage-result"
newsboat_pid=$(pgrep -n -u "$UID" -x newsboat)
focus_feeds
wtype -k Return
wait_until "retained article opens for Feed Scout" 15 screen_contains "Beta reliability"
wtype -k comma
wtype -k d
wait_until "comma-d opens Feed Scout in the configured agent" 45 window_present "$agent_class"
wait_until "Feed Scout prompt contains selected-article context" 15 \
  grep -Fq "Find high-signal feeds related to the selected article" "$agent_log"
wait_until "Feed Scout releases the Feeds tile" 15 window_absent "$feeds_class"
screenshot "success-feeds-11-feed-scout-handoff"

pass "Feeds completes its graphical subscribe, read, agent, resize, brief, triage, and scout journeys"
