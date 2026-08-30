#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
test_home="$test_tmp/home"
mkdir -p "$mock_bin" "$test_home"

export HOME="$test_home"
export OMARCHY_PATH="$ROOT"
export PATH="$mock_bin:$PATH"
export NEWSBOAT_TEST_LOG="$test_tmp/log"

write_mock() {
  local name="$1"
  shift
  printf '#!/bin/bash\n%s\n' "$*" >"$mock_bin/$name"
  chmod +x "$mock_bin/$name"
}

file_mode() {
  if stat -c '%a' "$1" >/dev/null 2>&1; then
    stat -c '%a' "$1"
  else
    stat -f '%Lp' "$1"
  fi
}

write_mock omarchy-pkg-add 'printf "pkg:%s\\n" "$*" >>"$NEWSBOAT_TEST_LOG"'
write_mock omarchy-tui-install '
printf "tui-attempt:%s\\n" "$*" >>"$NEWSBOAT_TEST_LOG"
mkdir -p "$HOME/.local/share/applications"
printf "new launcher\\n" >"$HOME/.local/share/applications/Feeds.desktop"
[[ ${NEWSBOAT_TEST_TUI_FAIL:-0} != 1 ]]
'
write_mock install '
destination=""
for argument in "$@"; do destination="$argument"; done
[[ ${NEWSBOAT_TEST_INSTALL_FAIL_TARGET:-} != "$destination" ]] || exit 41
exec /usr/bin/install "$@"
'
write_mock ln '
destination=""
for argument in "$@"; do destination="$argument"; done
if [[ ${NEWSBOAT_TEST_LN_RACE_TARGET:-} == "$destination" ]]; then
  printf "competitor\\n" >"$destination"
  exit 42
fi
[[ ${NEWSBOAT_TEST_LN_FAIL_TARGET:-} != "$destination" ]] || exit 43
exec /bin/ln "$@"
'
write_mock mv '
destination=""
for argument in "$@"; do destination="$argument"; done
[[ ${NEWSBOAT_TEST_MV_FAIL_TARGET:-} != "$destination" ]] || exit 44
exec /bin/mv "$@"
'

: >"$NEWSBOAT_TEST_LOG"
"$ROOT/bin/omarchy-install-newsboat" >/dev/null
grep -qx 'pkg:newsboat' "$NEWSBOAT_TEST_LOG" || fail "Newsboat installer uses the package helper"
grep -qx 'tui-attempt:Feeds omarchy-feeds tile newsboat' "$NEWSBOAT_TEST_LOG" || fail "Newsboat installer creates the first-class Feeds launcher"
cmp -s "$ROOT/default/newsboat/config" "$HOME/.config/newsboat/config" || fail "Newsboat installer seeds the Omarchy config"
cmp -s "$ROOT/default/newsboat/urls" "$HOME/.config/newsboat/urls" || fail "Newsboat installer seeds starter feeds"
[[ $(file_mode "$HOME/.config/newsboat/config") == 600 ]] || fail "Newsboat installer protects the user config"
[[ $(file_mode "$HOME/.config/newsboat/urls") == 600 ]] || fail "Newsboat installer protects subscription URLs"
[[ -L $HOME/.config/newsboat/omarchy.conf ]] || fail "Newsboat installer links the managed Omarchy config"
[[ $(readlink "$HOME/.config/newsboat/omarchy.conf") == "$ROOT/default/newsboat/omarchy.conf" ]] || fail "Newsboat managed config follows the active Omarchy source"
grep -Fq 'include "~/.config/newsboat/omarchy.conf"' "$HOME/.config/newsboat/config" || fail "Newsboat user config includes the managed layer"
pass "Newsboat installer creates an Omarchy first run"

printf 'my config\n' >"$HOME/.config/newsboat/config"
printf 'https://example.test/feed\n' >"$HOME/.config/newsboat/urls"
rm -f "$HOME/.config/newsboat/omarchy.conf"
printf 'my managed-name config\n' >"$HOME/.config/newsboat/omarchy.conf"
"$ROOT/bin/omarchy-install-newsboat" >/dev/null
[[ $(<"$HOME/.config/newsboat/config") == 'my config' ]] || fail "Newsboat installer preserves an existing config"
grep -Fxq 'https://example.test/feed' "$HOME/.config/newsboat/urls" || fail "Newsboat installer preserves existing subscriptions"
[[ $(grep -Fxc '"query:Inbox:unread = \"yes\""' "$HOME/.config/newsboat/urls") == 1 ]] || fail "Newsboat installer adds one finite Inbox to existing subscriptions"
[[ $(<"$HOME/.config/newsboat/omarchy.conf") == 'my managed-name config' ]] || fail "Newsboat installer preserves a regular omarchy.conf it does not own"
pass "Newsboat installer preserves user-owned files while adding the Inbox"

linked_subscription_target="$test_tmp/installer-linked-urls"
printf 'https://linked.example/feed\n' >"$linked_subscription_target"
rm -f "$HOME/.config/newsboat/urls"
/bin/ln -s "$linked_subscription_target" "$HOME/.config/newsboat/urls"
"$ROOT/bin/omarchy-install-newsboat" >/dev/null
[[ -L $HOME/.config/newsboat/urls ]] || fail "Newsboat installer preserves a user-managed subscriptions symlink"
[[ $(<"$linked_subscription_target") == 'https://linked.example/feed' ]] || fail "Newsboat installer leaves a user-managed subscriptions target untouched"
pass "Newsboat installer respects externally managed subscriptions"

rm -rf "$HOME/.config/newsboat" "$HOME/.local/share/applications"
write_mock omarchy-pkg-add 'exit 23'
if "$ROOT/bin/omarchy-install-newsboat" >/dev/null 2>&1; then
  fail "Newsboat installer stops when package installation fails"
fi
[[ ! -e $HOME/.config/newsboat ]] || fail "Newsboat installer avoids config mutations after package failure"
[[ ! -e $HOME/.local/share/applications ]] || fail "Newsboat installer avoids launcher mutations after package failure"
pass "Newsboat package failure leaves configuration untouched"

write_mock omarchy-pkg-add 'printf "pkg:%s\\n" "$*" >>"$NEWSBOAT_TEST_LOG"'

reset_empty_install_state() {
  rm -rf "$HOME/.config/newsboat" "$HOME/.local/share/applications"
  mkdir -p "$HOME/.config/newsboat"
  printf 'sentinel\n' >"$HOME/.config/newsboat/keep"
  : >"$NEWSBOAT_TEST_LOG"
  unset NEWSBOAT_TEST_INSTALL_FAIL_TARGET NEWSBOAT_TEST_LN_FAIL_TARGET NEWSBOAT_TEST_MV_FAIL_TARGET NEWSBOAT_TEST_TUI_FAIL
}

assert_empty_install_state_restored() {
  [[ $(<"$HOME/.config/newsboat/keep") == sentinel ]] || fail "$1 preserves unrelated config state"
  [[ ! -e $HOME/.config/newsboat/omarchy.conf && ! -L $HOME/.config/newsboat/omarchy.conf ]] || fail "$1 rolls back the managed config"
  [[ ! -e $HOME/.config/newsboat/config ]] || fail "$1 rolls back the user config"
  [[ ! -e $HOME/.config/newsboat/urls ]] || fail "$1 rolls back starter feeds"
  [[ ! -e $HOME/.local/share/applications/Feeds.desktop ]] || fail "$1 leaves no launcher"
}

reset_empty_install_state
export NEWSBOAT_TEST_LN_FAIL_TARGET="$HOME/.config/newsboat/omarchy.conf"
if "$ROOT/bin/omarchy-install-newsboat" >/dev/null 2>&1; then
  fail "Newsboat installer stops when managed-link creation fails"
fi
assert_empty_install_state_restored "managed-link failure"
! grep -q '^tui-attempt:' "$NEWSBOAT_TEST_LOG" || fail "managed-link failure does not invoke the launcher"
pass "Newsboat installer rolls back a managed-link failure"

reset_empty_install_state
export NEWSBOAT_TEST_INSTALL_FAIL_TARGET="$HOME/.config/newsboat/config"
if "$ROOT/bin/omarchy-install-newsboat" >/dev/null 2>&1; then
  fail "Newsboat installer stops when user-config creation fails"
fi
assert_empty_install_state_restored "user-config failure"
! grep -q '^tui-attempt:' "$NEWSBOAT_TEST_LOG" || fail "user-config failure does not invoke the launcher"
pass "Newsboat installer rolls back after creating the managed link"

reset_empty_install_state
export NEWSBOAT_TEST_INSTALL_FAIL_TARGET="$HOME/.config/newsboat/urls"
if "$ROOT/bin/omarchy-install-newsboat" >/dev/null 2>&1; then
  fail "Newsboat installer stops when starter-feed creation fails"
fi
assert_empty_install_state_restored "starter-feed failure"
! grep -q '^tui-attempt:' "$NEWSBOAT_TEST_LOG" || fail "starter-feed failure does not invoke the launcher"
pass "Newsboat installer rolls back after creating both config layers"

reset_empty_install_state
printf 'https://existing.example/feed\n' >"$HOME/.config/newsboat/urls"
export NEWSBOAT_TEST_MV_FAIL_TARGET="$HOME/.config/newsboat/urls"
if "$ROOT/bin/omarchy-install-newsboat" >/dev/null 2>&1; then
  fail "Newsboat installer stops when Inbox publication fails"
fi
[[ $(<"$HOME/.config/newsboat/urls") == 'https://existing.example/feed' ]] || fail "Inbox publication failure restores existing subscriptions"
[[ ! -e $HOME/.config/newsboat/omarchy.conf && ! -L $HOME/.config/newsboat/omarchy.conf ]] || fail "Inbox publication failure rolls back managed config"
[[ ! -e $HOME/.config/newsboat/config ]] || fail "Inbox publication failure rolls back user config"
! grep -q '^tui-attempt:' "$NEWSBOAT_TEST_LOG" || fail "Inbox publication failure does not invoke the launcher"
pass "Newsboat installer rolls back an Inbox publication failure"

reset_empty_install_state
export NEWSBOAT_TEST_TUI_FAIL=1
if "$ROOT/bin/omarchy-install-newsboat" >/dev/null 2>&1; then
  fail "Newsboat installer stops when launcher creation fails"
fi
assert_empty_install_state_restored "launcher failure"
grep -q '^tui-attempt:' "$NEWSBOAT_TEST_LOG" || fail "launcher failure reaches the downstream launcher"
pass "Newsboat installer rolls back a partial launcher failure"

reset_empty_install_state
mkdir -p "$HOME/.local/share/applications"
/bin/ln -s /old/omarchy.conf "$HOME/.config/newsboat/omarchy.conf"
printf 'https://old.example/feed\n' >"$HOME/.config/newsboat/urls"
printf 'old launcher\n' >"$HOME/.local/share/applications/Feeds.desktop"
export NEWSBOAT_TEST_TUI_FAIL=1
if "$ROOT/bin/omarchy-install-newsboat" >/dev/null 2>&1; then
  fail "Newsboat installer stops when replacing a launcher fails"
fi
[[ -L $HOME/.config/newsboat/omarchy.conf ]] || fail "launcher failure restores the previous managed link"
[[ $(readlink "$HOME/.config/newsboat/omarchy.conf") == /old/omarchy.conf ]] || fail "launcher failure restores the previous managed-link target"
[[ $(<"$HOME/.local/share/applications/Feeds.desktop") == 'old launcher' ]] || fail "launcher failure restores the previous launcher"
[[ ! -e $HOME/.config/newsboat/config ]] || fail "launcher failure removes the newly seeded user config"
[[ $(<"$HOME/.config/newsboat/urls") == 'https://old.example/feed' ]] || fail "launcher failure restores subscriptions changed while adding the Inbox"
pass "Newsboat installer restores replaced files after downstream failure"

unset NEWSBOAT_TEST_INSTALL_FAIL_TARGET NEWSBOAT_TEST_LN_FAIL_TARGET NEWSBOAT_TEST_MV_FAIL_TARGET NEWSBOAT_TEST_TUI_FAIL

notification_log="$test_tmp/notification"
agent_log="$test_tmp/agent"
agent_count_log="$test_tmp/agent-count"
export NEWSBOAT_NOTIFICATION_LOG="$notification_log"
export NEWSBOAT_AGENT_LOG="$agent_log"
export NEWSBOAT_AGENT_COUNT_LOG="$agent_count_log"

write_mock omarchy-default-agent 'printf "%s\\n" "${NEWSBOAT_TEST_AGENT:-}"'
write_mock omarchy-notification-send 'printf "%s\\n" "$@" >"$NEWSBOAT_NOTIFICATION_LOG"'
write_mock omarchy-agent-prompt 'printf "%s" "$1" >"$NEWSBOAT_AGENT_LOG"; printf "%s\\n" "$#" >"$NEWSBOAT_AGENT_COUNT_LOG"'

unset NEWSBOAT_TEST_AGENT
"$ROOT/bin/omarchy-agent-newsboat" 'https://example.test/article' 'A title' 'https://example.test/feed'
[[ -s $notification_log ]] || fail "Newsboat agent explains how to choose a default agent"
[[ ! -e $agent_log ]] || fail "Newsboat agent starts nothing while no default is configured"
grep -Fxq 'setup.default.agent' "$notification_log" || fail "Newsboat agent notification opens the agent picker"
pass "Newsboat agent handles an unconfigured Omarchy"

rm -f "$notification_log" "$agent_log" "$agent_count_log"
export NEWSBOAT_TEST_AGENT=codex
"$ROOT/bin/omarchy-agent-newsboat" \
  'https://example.test/article?q=$(touch /tmp/nope)' \
  'Title; rm -rf /' \
  'https://example.test/feed'
[[ $(<"$agent_count_log") == 1 ]] || fail "Newsboat agent passes one prompt argument"
grep -Fq 'Article URL: https://example.test/article?q=$(touch /tmp/nope)' "$agent_log" || fail "Newsboat agent keeps the URL as prompt data"
grep -Fq 'Title: Title; rm -rf /' "$agent_log" || fail "Newsboat agent keeps the title as prompt data"
grep -Fq 'untrusted content' "$agent_log" || fail "Newsboat agent warns the model about untrusted article content"
pass "Newsboat agent routes article metadata safely"

rm -f "$agent_log" "$agent_count_log"
if "$ROOT/bin/omarchy-agent-newsboat" 'file:///etc/passwd' >/dev/null 2>&1; then
  fail "Newsboat agent rejects non-web URLs"
fi
[[ ! -e $agent_log ]] || fail "Newsboat agent does not launch for a rejected URL"
pass "Newsboat agent only accepts web articles"

newsboat_log="$test_tmp/newsboat-command"
editor_log="$test_tmp/editor"
export NEWSBOAT_TEST_NEWSBOAT_LOG="$newsboat_log"
export NEWSBOAT_TEST_EDITOR_LOG="$editor_log"

write_mock omarchy-pkg-missing '[[ ${NEWSBOAT_TEST_PACKAGE_MISSING:-0} == 1 ]]'
write_mock flock 'exit 0'
write_mock omarchy-launch-config-editor 'printf "%s\\n" "$@" >"$NEWSBOAT_TEST_EDITOR_LOG"'
write_mock newsboat '
url_file=""
import_file=""
export_opml=false
printf "%s\\n" "$*" >>"$NEWSBOAT_TEST_NEWSBOAT_LOG"
while (($#)); do
  case "$1" in
    -u) url_file="$2"; shift 2 ;;
    -i) import_file="$2"; shift 2 ;;
    --export-to-opml2) export_opml=true; shift ;;
    *) shift ;;
  esac
done
if [[ -n $import_file ]]; then
  printf "https://imported.example/feed Imported\\n" >>"$url_file"
  [[ ${NEWSBOAT_TEST_NEWSBOAT_FAIL:-0} != 1 ]]
elif [[ $export_opml == true ]]; then
  printf "<?xml version=\"1.0\"?><opml version=\"2.0\"></opml>\n"
  [[ ${NEWSBOAT_TEST_NEWSBOAT_FAIL:-0} != 1 ]]
fi
'

rm -rf "$HOME/.config/newsboat"
mkdir -p "$HOME/.config/newsboat"
unset NEWSBOAT_TEST_PACKAGE_MISSING NEWSBOAT_TEST_NEWSBOAT_FAIL NEWSBOAT_TEST_LN_RACE_TARGET

if "$ROOT/bin/omarchy-newsboat-add" 'file:///tmp/feed.xml' >/dev/null 2>&1; then
  fail "Newsboat add rejects a non-web feed URL"
fi
[[ ! -e $HOME/.config/newsboat/urls ]] || fail "an invalid Newsboat feed does not create subscriptions"
pass "Newsboat add validates feed URLs before mutation"

export NEWSBOAT_TEST_PACKAGE_MISSING=1
if "$ROOT/bin/omarchy-newsboat-add" 'https://example.test/feed' >/dev/null 2>&1; then
  fail "Newsboat add refuses to run before Newsboat is installed"
fi
[[ ! -e $HOME/.config/newsboat/urls ]] || fail "a missing Newsboat package leaves subscriptions untouched"
pass "Newsboat commands explain their optional dependency"
unset NEWSBOAT_TEST_PACKAGE_MISSING

printf 'https://first.example/feed' >"$HOME/.config/newsboat/urls"
"$ROOT/bin/omarchy-newsboat-add" 'https://second.example/feed' >/dev/null
expected_feeds=$'https://first.example/feed\nhttps://second.example/feed'
[[ $(<"$HOME/.config/newsboat/urls") == "$expected_feeds" ]] || fail "Newsboat add preserves a final unterminated line"
"$ROOT/bin/omarchy-newsboat-add" 'https://second.example/feed' >/dev/null
[[ $(grep -c '^https://second.example/feed$' "$HOME/.config/newsboat/urls") == 1 ]] || fail "Newsboat add deduplicates an existing subscription"
injection_marker="$test_tmp/feed-command-ran"
"$ROOT/bin/omarchy-newsboat-add" 'https://example.test/$(touch${IFS}'"$injection_marker"')' >/dev/null
[[ ! -e $injection_marker ]] || fail "Newsboat add treats a feed URL as data"
pass "Newsboat add appends safely and idempotently"

if "$ROOT/bin/omarchy-newsboat-remove" 'file:///tmp/feed.xml' >/dev/null 2>&1; then
  fail "Newsboat remove rejects a non-web feed URL"
fi
[[ $(<"$HOME/.config/newsboat/urls") == *'https://second.example/feed'* ]] || fail "an invalid removal leaves subscriptions untouched"
pass "Newsboat remove validates feed URLs before mutation"

export NEWSBOAT_TEST_PACKAGE_MISSING=1
before_remove=$(<"$HOME/.config/newsboat/urls")
if "$ROOT/bin/omarchy-newsboat-remove" 'https://second.example/feed' >/dev/null 2>&1; then
  fail "Newsboat remove refuses to run before Newsboat is installed"
fi
[[ $(<"$HOME/.config/newsboat/urls") == "$before_remove" ]] || fail "a missing Newsboat package leaves removals untouched"
unset NEWSBOAT_TEST_PACKAGE_MISSING
pass "Newsboat remove checks its optional dependency"

printf '%s\n' \
  '# Keep this comment' \
  'https://first.example/feed "First"' \
  'https://first.example/feed-long "Similar"' \
  'https://second.example/feed tech news' >"$HOME/.config/newsboat/urls"
"$ROOT/bin/omarchy-newsboat-remove" 'https://first.example/feed' >/dev/null
expected_feeds=$'# Keep this comment\nhttps://first.example/feed-long "Similar"\nhttps://second.example/feed tech news'
[[ $(<"$HOME/.config/newsboat/urls") == "$expected_feeds" ]] || fail "Newsboat remove keeps comments, tags, and similar URLs"
before_remove=$(<"$HOME/.config/newsboat/urls")
"$ROOT/bin/omarchy-newsboat-remove" 'https://absent.example/feed' >/dev/null
[[ $(<"$HOME/.config/newsboat/urls") == "$before_remove" ]] || fail "Newsboat remove is idempotent for an absent subscription"
pass "Newsboat remove deletes only exact subscriptions"

linked_urls="$test_tmp/linked-urls"
printf 'https://linked.example/feed' >"$linked_urls"
rm -f "$HOME/.config/newsboat/urls"
/bin/ln -s "$linked_urls" "$HOME/.config/newsboat/urls"
"$ROOT/bin/omarchy-newsboat-remove" 'https://linked.example/feed' >/dev/null
[[ -L $HOME/.config/newsboat/urls ]] || fail "Newsboat remove preserves a user subscriptions symlink"
[[ ! -s $linked_urls ]] || fail "Newsboat remove updates the subscriptions symlink target"
pass "Newsboat remove preserves linked subscription files"

rm -f "$HOME/.config/newsboat/urls" "$editor_log"
"$ROOT/bin/omarchy-newsboat-edit"
[[ -f $HOME/.config/newsboat/urls ]] || fail "Newsboat edit creates a missing subscriptions file"
[[ $(<"$editor_log") == "$HOME/.config/newsboat/urls" ]] || fail "Newsboat edit opens the subscriptions file"
pass "Newsboat edit uses the configured Omarchy editor"

opml_file="$test_tmp/subscriptions.opml"
printf '<opml version="2.0"></opml>\n' >"$opml_file"
printf 'https://existing.example/feed\n' >"$HOME/.config/newsboat/urls"
export NEWSBOAT_TEST_NEWSBOAT_FAIL=1
if "$ROOT/bin/omarchy-newsboat-import" "$opml_file" >/dev/null 2>&1; then
  fail "Newsboat import reports a parser failure"
fi
[[ $(<"$HOME/.config/newsboat/urls") == 'https://existing.example/feed' ]] || fail "failed OPML import preserves subscriptions"
[[ -z $(find "$HOME/.config/newsboat" -name 'urls.import.*' -print -quit) ]] || fail "failed OPML import removes its staged file"
pass "Newsboat import is atomic when Newsboat rejects the OPML"

unset NEWSBOAT_TEST_NEWSBOAT_FAIL
"$ROOT/bin/omarchy-newsboat-import" "$opml_file" >/dev/null
grep -Fq 'https://existing.example/feed' "$HOME/.config/newsboat/urls" || fail "Newsboat import keeps existing subscriptions"
grep -Fq 'https://imported.example/feed Imported' "$HOME/.config/newsboat/urls" || fail "Newsboat import publishes imported subscriptions"
pass "Newsboat import merges OPML through a staged subscriptions file"

export_target="$test_tmp/export.opml"
export NEWSBOAT_TEST_NEWSBOAT_FAIL=1
if "$ROOT/bin/omarchy-newsboat-export" "$export_target" >/dev/null 2>&1; then
  fail "Newsboat export reports a generator failure"
fi
[[ ! -e $export_target ]] || fail "failed Newsboat export publishes no destination"
[[ -z $(find "$test_tmp" -name '.export.opml.tmp.*' -print -quit) ]] || fail "failed Newsboat export removes its staged file"
pass "Newsboat export is atomic when Newsboat fails"

unset NEWSBOAT_TEST_NEWSBOAT_FAIL
"$ROOT/bin/omarchy-newsboat-export" "$export_target" >/dev/null
grep -Fq '<opml version="2.0">' "$export_target" || fail "Newsboat export writes OPML 2.0"
pass "Newsboat export publishes a completed OPML file"

printf 'keep this export\n' >"$export_target"
: >"$newsboat_log"
if "$ROOT/bin/omarchy-newsboat-export" "$export_target" >/dev/null 2>&1; then
  fail "Newsboat export refuses an existing destination"
fi
[[ $(<"$export_target") == 'keep this export' ]] || fail "Newsboat export preserves an existing destination"
[[ ! -s $newsboat_log ]] || fail "Newsboat export checks the destination before invoking Newsboat"
pass "Newsboat export never overwrites a user file"

race_target="$test_tmp/race.opml"
export NEWSBOAT_TEST_LN_RACE_TARGET="$race_target"
if "$ROOT/bin/omarchy-newsboat-export" "$race_target" >/dev/null 2>&1; then
  fail "Newsboat export reports a destination race"
fi
[[ $(<"$race_target") == competitor ]] || fail "Newsboat export preserves a file that appears during export"
[[ -z $(find "$test_tmp" -name '.race.opml.tmp.*' -print -quit) ]] || fail "raced Newsboat export removes its staged file"
pass "Newsboat export publishes without a check-then-overwrite race"
unset NEWSBOAT_TEST_LN_RACE_TARGET

grep -Fq 'include "~/.config/newsboat/omarchy.conf"' "$ROOT/default/newsboat/config" || fail "Newsboat user config includes the managed layer"
grep -Fq 'browser "omarchy-launch-browser %u"' "$ROOT/default/newsboat/omarchy.conf" || fail "Newsboat opens normal links with the Omarchy browser"
grep -Fq 'bind r feedlist reload-urls; reload-all -- "Refresh subscriptions and feeds"' "$ROOT/default/newsboat/omarchy.conf" || fail "Newsboat refreshes subscriptions before collecting feeds"
grep -Fq 'macro a set browser "omarchy-agent-newsboat %u %T %F"' "$ROOT/default/newsboat/omarchy.conf" || fail "Newsboat exposes the explicit agent macro"
pass "Newsboat defaults integrate browser and agent actions"
