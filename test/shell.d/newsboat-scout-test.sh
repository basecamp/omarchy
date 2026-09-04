#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command python3

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
test_home="$test_tmp/home"
urls_file="$test_home/.config/newsboat/urls"
agent_log="$test_tmp/agent"
notification_log="$test_tmp/notifications"
curl_log="$test_tmp/curl"
confirm_log="$test_tmp/confirm"
mkdir -p "$mock_bin" "$(dirname "$urls_file")"

export HOME="$test_home"
export OMARCHY_PATH="$ROOT"
export PATH="$mock_bin:$ROOT/bin:$PATH"
export NEWSBOAT_URLS_FILE="$urls_file"
export NEWSBOAT_SCOUT_STATE_DIR="$test_tmp/scouts"
export NEWSBOAT_SCOUT_RUNTIME_DIR="$test_tmp"
export SCOUT_TEST_AGENT_LOG="$agent_log"
export SCOUT_TEST_NOTIFICATION_LOG="$notification_log"
export SCOUT_TEST_CURL_LOG="$curl_log"
export SCOUT_TEST_CONFIRM_LOG="$confirm_log"
export NEWSBOAT_CONFIRM_STATE_DIR="$test_tmp/confirmations"

write_mock() {
  local name=$1
  shift
  printf '#!/bin/bash\n%s\n' "$*" >"$mock_bin/$name"
  chmod +x "$mock_bin/$name"
}

write_urls() {
  cat >"$urls_file" <<'URLS'
"query:Inbox:unread = \"yes\""
https://existing.example/feed "Existing"
URLS
}

write_mock omarchy-pkg-missing '[[ ${SCOUT_TEST_PACKAGE_MISSING:-0} == 1 ]]'
write_mock omarchy-default-agent 'printf "%s\n" "${SCOUT_TEST_AGENT:-}"'
write_mock omarchy-notification-send 'printf "%s\n" "$*" >>"$SCOUT_TEST_NOTIFICATION_LOG"; exit "${SCOUT_TEST_NOTIFICATION_STATUS:-0}"'
write_mock omarchy-agent-prompt '
[[ ${1:-} == "--conversation" ]] || exit 64
[[ ${OMARCHY_AGENT_NETWORK_ACCESS:-false} == "true" ]] || exit 65
printf "%s" "$2" >"$SCOUT_TEST_AGENT_LOG"
'
write_mock flock 'exit 0'
write_mock omarchy-shell '
case ${1:-}:${2:-} in
  shell:launchNewsboatConfirmation)
    "$OMARCHY_PATH/bin/omarchy-newsboat-confirm" --respond "$4" </dev/null &
    echo ok
    ;;
  shell:newsboatConfirmationStatus) echo active ;;
  shell:cancelNewsboatConfirmation) echo ok ;;
  *) exit 64 ;;
esac
'
write_mock gum '
printf "%s\n" "$*" >>"$SCOUT_TEST_CONFIRM_LOG"
if [[ -n ${SCOUT_TEST_CONFIRM_HOOK:-} ]]; then "$SCOUT_TEST_CONFIRM_HOOK"; fi
exit "${SCOUT_TEST_CONFIRM_STATUS:-0}"
'
write_mock mv '
destination=""
for argument in "$@"; do destination="$argument"; done
[[ ${SCOUT_TEST_MV_FAIL_TARGET:-} != "$destination" ]] || exit 71
exec /bin/mv "$@"
'
write_mock rm '
target=""
for argument in "$@"; do target="$argument"; done
[[ ${SCOUT_TEST_RM_FAIL_TARGET:-} != "$target" ]] || exit 72
exec /bin/rm "$@"
'
write_mock curl '
output=""
url=""
while (($#)); do
  case "$1" in
    --proto|--proto-redir|--connect-timeout|--max-time|--max-redirs|--max-filesize|--user-agent|--output|--write-out)
      [[ $1 == --output ]] && output="$2"
      shift 2
      ;;
    --silent|--show-error|--fail|--location|--compressed) shift ;;
    *) url="$1"; shift ;;
  esac
done
printf "%s\n" "$url" >>"$SCOUT_TEST_CURL_LOG"
case "$url" in
  https://scout-one.test|https://scout-three.test)
    host=${url#https://}
    cat >"$output" <<HTML
<html><head><title>$host</title><link rel="alternate" type="application/rss+xml" href="/feed.xml"></head></html>
HTML
    printf "%s\ntext/html" "$url"
    ;;
  https://scout-one.test/feed.xml)
    cat >"$output" <<RSS
<?xml version="1.0"?><rss><channel><title>Scout One</title><item><title>Deep systems notes</title></item><item><title>Tools that last</title></item></channel></rss>
RSS
    printf "%s\napplication/rss+xml" "$url"
    ;;
  https://scout-three.test/feed.xml)
    cat >"$output" <<RSS
<?xml version="1.0"?><rss><channel><title>Scout Three</title><item><title>Independent dispatch</title></item></channel></rss>
RSS
    printf "%s\napplication/rss+xml" "$url"
    ;;
  https://scout-two.test/feed.atom)
    cat >"$output" <<ATOM
<?xml version="1.0"?><feed xmlns="http://www.w3.org/2005/Atom"><title>Scout Two</title><entry><title>Careful weekly analysis</title></entry></feed>
ATOM
    printf "%s\napplication/atom+xml" "$url"
    ;;
  https://existing.example/feed)
    printf "<?xml version=\"1.0\"?><rss><channel><title>Existing</title></channel></rss>\n" >"$output"
    printf "%s\napplication/rss+xml" "$url"
    ;;
  https://invalid.test)
    printf "<html><head><title>No feed</title></head></html>\n" >"$output"
    printf "%s\ntext/html" "$url"
    ;;
  *) exit 22 ;;
esac
'

write_urls
export SCOUT_TEST_AGENT=codex
rm -f "$agent_log"
"$ROOT/bin/omarchy-newsboat-scout" "independent Ruby writing"
grep -Fq 'The user specifically wants: independent Ruby writing' "$agent_log" || fail "Feed Scout preserves the requested subject"
grep -Fq 'https://existing.example/feed' "$agent_log" || fail "Feed Scout gives the agent current subscriptions"
grep -Fq 'Recommend at most five' "$agent_log" || fail "Feed Scout keeps discovery intentionally small"
grep -Fq 'omarchy-newsboat-scout-propose URL' "$agent_log" || fail "Feed Scout routes candidates through read-only validation"
grep -Fq 'Do not run omarchy-newsboat-add' "$agent_log" || fail "Feed Scout forbids direct subscription mutations"
grep -Fq 'Add <COUNT> feeds? (yes/no)' "$agent_log" || fail "Feed Scout requires an exact confirmation"
[[ $(grep -c '^https://' "$urls_file") == 1 ]] || fail "Feed Scout changes subscriptions before confirmation"
grep -Fq 'normal per-command permission approval' "$agent_log" || fail "Feed Scout omits the desktop permission boundary"
pass "Feed Scout gives the configured agent a bounded network-research task with confirmation-only writes"

rm -f "$agent_log"
"$ROOT/bin/omarchy-newsboat-scout" --from-newsboat https://articles.example/story "A useful story" https://existing.example/feed
grep -Fq 'Selected article: A useful story' "$agent_log" || fail "article discovery includes the selected title"
grep -Fq 'Article URL: https://articles.example/story' "$agent_log" || fail "article discovery includes the selected URL"
pass "Feed Scout can look for feeds complementary to a selected article"

export SCOUT_TEST_AGENT=crush
rm -f "$agent_log"
"$ROOT/bin/omarchy-newsboat-scout" "systems engineering"
grep -Fq 'do not browse, research, or run any command in your first response' "$agent_log" || fail "Crush Feed Scout avoids tools in its headless seeded turn"
grep -Fq 'Start Feed Scout research? (yes/no)' "$agent_log" || fail "Crush Feed Scout opens its interactive research turn explicitly"
grep -Fq 'Only after I explicitly confirm that first question' "$agent_log" || fail "Crush Feed Scout defers validation until its interactive session"
pass "Feed Scout adapts research to Crush's seeded conversation lifecycle"

if SCOUT_TEST_AGENT= "$ROOT/bin/omarchy-newsboat-scout" >/dev/null 2>&1; then
  :
fi
grep -Fq 'Choose a default agent first' "$notification_log" || fail "Feed Scout explains an unconfigured agent"
pass "Feed Scout handles an unconfigured Omarchy"

scout_symlink_target="$test_tmp/scout-symlink-target"
mkdir -p "$scout_symlink_target"
rm -rf "$NEWSBOAT_SCOUT_STATE_DIR"
/bin/ln -s "$scout_symlink_target" "$NEWSBOAT_SCOUT_STATE_DIR"
write_urls
: >"$curl_log"
if "$ROOT/bin/omarchy-newsboat-scout-propose" https://scout-one.test >/dev/null 2>"$test_tmp/scout-symlink-error"; then
  fail "Feed Scout writes proposal state through a symlinked directory"
fi
[[ ! -s $curl_log ]] || fail "symlinked Feed Scout state reaches network validation"
[[ -z $(find "$scout_symlink_target" -type f -print -quit) ]] || fail "symlinked Feed Scout state receives a proposal"
rm -f "$NEWSBOAT_SCOUT_STATE_DIR"
mkdir -p "$NEWSBOAT_SCOUT_STATE_DIR"
pass "Feed Scout rejects symlinked proposal state before validation"

write_urls
: >"$curl_log"
proposal_output="$test_tmp/proposal-output"
"$ROOT/bin/omarchy-newsboat-scout-propose" \
  https://scout-one.test \
  https://scout-two.test/feed.atom \
  https://existing.example/feed \
  https://invalid.test >"$proposal_output" 2>"$test_tmp/proposal-errors" ||
  fail "Feed Scout creates a proposal from valid candidates" "$(<"$test_tmp/proposal-errors")"
grep -Fq 'F001 — Scout One' "$proposal_output" || fail "Feed Scout validates an advertised RSS document"
grep -Fq 'F002 — Scout Two' "$proposal_output" || fail "Feed Scout validates a direct Atom document"
grep -Fq 'Recent: Deep systems notes · Tools that last' "$proposal_output" || fail "Feed Scout exposes recent examples from the validated feed"
grep -Fq 'Ask: Add 2 feeds? (yes/no)' "$proposal_output" || fail "Feed Scout proposal reports its exact count"
grep -Eq 'After explicit confirmation: omarchy-newsboat-scout-apply [A-Za-z0-9_-]+ 2 F001 F002$' "$proposal_output" || fail "Feed Scout returns one exact confirmation command"
grep -Fq 'Skipped existing subscription' "$test_tmp/proposal-errors" || fail "Feed Scout removes existing subscriptions from a proposal"
grep -Fq 'Skipped unvalidated candidate' "$test_tmp/proposal-errors" || fail "Feed Scout rejects pages without a valid feed"
[[ $(grep -c '^https://' "$urls_file") == 1 ]] || fail "validating a Feed Scout proposal mutates subscriptions"
proposal_id=$(sed -n 's/^Validated Feed Scout proposal \([A-Za-z0-9_-]*\):$/\1/p' "$proposal_output")
[[ -n $proposal_id && -f $NEWSBOAT_SCOUT_STATE_DIR/scout.$proposal_id ]] || fail "Feed Scout protects the validated proposal in a snapshot"
pass "Feed Scout validates candidates without subscribing"

real_scout_state="$test_tmp/scout-state-real"
/bin/mv "$NEWSBOAT_SCOUT_STATE_DIR" "$real_scout_state"
/bin/ln -s "$real_scout_state" "$NEWSBOAT_SCOUT_STATE_DIR"
if "$ROOT/bin/omarchy-newsboat-scout-apply" "$proposal_id" 2 F001 F002 >/dev/null 2>&1; then
  fail "Feed Scout consumes a proposal through symlinked state"
fi
[[ $(grep -c '^https://' "$urls_file") == 1 ]] || fail "symlinked Feed Scout state mutates subscriptions"
rm -f "$NEWSBOAT_SCOUT_STATE_DIR"
/bin/mv "$real_scout_state" "$NEWSBOAT_SCOUT_STATE_DIR"
pass "Feed Scout rejects symlinked proposal state before confirmation"

write_urls
printf 'https://broken.example/feed "unfinished label\n' >>"$urls_file"
urls_before=$(<"$urls_file")
: >"$curl_log"
if "$ROOT/bin/omarchy-newsboat-scout-propose" https://scout-one.test >"$test_tmp/malformed-proposal-output" 2>"$test_tmp/malformed-proposal-error"; then
  fail "Feed Scout proposes feeds from malformed subscriptions"
fi
[[ $(<"$urls_file") == "$urls_before" ]] || fail "malformed subscriptions are changed during Feed Scout validation"
[[ ! -s $curl_log ]] || fail "Feed Scout fetches candidates before validating current subscriptions"
grep -Fq 'No closing quotation' "$test_tmp/malformed-proposal-error" || fail "Feed Scout hides a malformed subscriptions error"
pass "Feed Scout fails closed before researching malformed subscriptions"

write_urls

export SCOUT_TEST_CONFIRM_STATUS=1
urls_before=$(<"$urls_file")
"$ROOT/bin/omarchy-newsboat-scout-apply" "$proposal_id" 2 F001 F002 >"$test_tmp/declined-apply-output"
unset SCOUT_TEST_CONFIRM_STATUS
[[ $(<"$urls_file") == "$urls_before" ]] || fail "declining the separate Feed Scout confirmation changes subscriptions"
[[ -f $NEWSBOAT_SCOUT_STATE_DIR/scout.$proposal_id ]] || fail "declining the separate Feed Scout confirmation consumes its proposal"
grep -Fq 'No feeds were added; the Feed Scout proposal remains available.' "$test_tmp/declined-apply-output" || fail "declined Feed Scout has no clear result for the agent"
grep -Fq 'Add 2 validated feeds to Newsboat?' "$confirm_log" || fail "Feed Scout does not repeat the exact effect outside the agent terminal"
pass "Feed Scout requires separate human approval after the agent conversation"

"$ROOT/bin/omarchy-newsboat-scout-apply" "$proposal_id" 2 F001 F002 >"$test_tmp/apply-output"
grep -Fxq 'https://scout-one.test/feed.xml' "$urls_file" || fail "confirmed Feed Scout adds the selected RSS feed"
grep -Fxq 'https://scout-two.test/feed.atom' "$urls_file" || fail "confirmed Feed Scout adds the selected Atom feed"
[[ $(grep -c '^https://scout-' "$urls_file") == 2 ]] || fail "confirmed Feed Scout adds each selected feed once"
grep -Fq '2 feeds added to Newsboat.' "$test_tmp/apply-output" || fail "Feed Scout reports the confirmed result to the agent"
[[ ! -e $NEWSBOAT_SCOUT_STATE_DIR/scout.$proposal_id ]] || fail "Feed Scout consumes a successful proposal"
if "$ROOT/bin/omarchy-newsboat-scout-apply" "$proposal_id" 2 F001 F002 >/dev/null 2>&1; then
  fail "Feed Scout applies the same proposal twice"
fi
pass "Feed Scout atomically applies only an explicitly confirmed proposal"

write_urls
"$ROOT/bin/omarchy-newsboat-scout-propose" https://scout-three.test >"$proposal_output"
proposal_id=$(sed -n 's/^Validated Feed Scout proposal \([A-Za-z0-9_-]*\):$/\1/p' "$proposal_output")
write_mock scout-test-change-urls 'printf "https://manual.example/feed\n" >>"$NEWSBOAT_URLS_FILE"'
export SCOUT_TEST_CONFIRM_HOOK=scout-test-change-urls
if "$ROOT/bin/omarchy-newsboat-scout-apply" "$proposal_id" 1 F001 >/dev/null 2>&1; then
  fail "Feed Scout applies a stale proposal after subscriptions change"
fi
unset SCOUT_TEST_CONFIRM_HOOK
! grep -Fq 'https://scout-three.test/feed.xml' "$urls_file" || fail "stale Feed Scout proposal changes subscriptions"
[[ -f $NEWSBOAT_SCOUT_STATE_DIR/scout.$proposal_id ]] || fail "stale Feed Scout proposal remains inspectable"
pass "Feed Scout revalidates subscriptions after separate confirmation"

write_urls
"$ROOT/bin/omarchy-newsboat-scout-propose" https://scout-one.test https://scout-two.test/feed.atom >"$proposal_output"
proposal_id=$(sed -n 's/^Validated Feed Scout proposal \([A-Za-z0-9_-]*\):$/\1/p' "$proposal_output")
if "$ROOT/bin/omarchy-newsboat-scout-apply" "$proposal_id" 1 F001 F002 >/dev/null 2>&1; then
  fail "Feed Scout accepts a confirmation count that does not match its IDs"
fi
[[ $(grep -c '^https://' "$urls_file") == 1 ]] || fail "mismatched Feed Scout confirmation mutates subscriptions"
pass "Feed Scout verifies the exact confirmed feed count"

urls_before=$(<"$urls_file")
export SCOUT_TEST_MV_FAIL_TARGET="$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$urls_file")"
if "$ROOT/bin/omarchy-newsboat-scout-apply" "$proposal_id" 2 F001 F002 >/dev/null 2>&1; then
  fail "Feed Scout reports success when subscription publication fails"
fi
unset SCOUT_TEST_MV_FAIL_TARGET
[[ $(<"$urls_file") == "$urls_before" ]] || fail "failed Feed Scout publication changes the original subscriptions"
[[ -f $NEWSBOAT_SCOUT_STATE_DIR/scout.$proposal_id ]] || fail "failed Feed Scout publication consumes its proposal"
pass "Feed Scout restores its proposal when atomic publication fails"

export SCOUT_TEST_NOTIFICATION_STATUS=1
"$ROOT/bin/omarchy-newsboat-scout-apply" "$proposal_id" 2 F001 F002 >"$test_tmp/notification-failure-output"
unset SCOUT_TEST_NOTIFICATION_STATUS
grep -Fq '2 feeds added to Newsboat.' "$test_tmp/notification-failure-output" || fail "a notification failure hides a completed Feed Scout update"
[[ ! -e $NEWSBOAT_SCOUT_STATE_DIR/scout.$proposal_id ]] || fail "a completed Feed Scout proposal remains reusable after notification failure"
pass "Feed Scout reports success even if its desktop notification fails"

write_urls
"$ROOT/bin/omarchy-newsboat-scout-propose" https://scout-three.test >"$proposal_output"
proposal_id=$(sed -n 's/^Validated Feed Scout proposal \([A-Za-z0-9_-]*\):$/\1/p' "$proposal_output")
proposal_file="$NEWSBOAT_SCOUT_STATE_DIR/scout.$proposal_id"
export SCOUT_TEST_RM_FAIL_TARGET="$proposal_file"
if "$ROOT/bin/omarchy-newsboat-scout-apply" "$proposal_id" 1 F001 >"$test_tmp/cleanup-failure-output" 2>"$test_tmp/cleanup-failure-error"; then
  fail "Feed Scout reports a fully completed transaction when proposal cleanup fails"
fi
unset SCOUT_TEST_RM_FAIL_TARGET
grep -Fxq 'https://scout-three.test/feed.xml' "$urls_file" || fail "proposal cleanup failure loses the committed subscription"
[[ -f $proposal_file ]] || fail "proposal cleanup failure hides the unremoved state"
if "$ROOT/bin/omarchy-newsboat-scout-apply" "$proposal_id" 1 F001 >/dev/null 2>&1; then
  fail "Feed Scout reapplies a proposal left after cleanup failure"
fi
[[ $(grep -Fxc 'https://scout-three.test/feed.xml' "$urls_file") == 1 ]] || fail "a retained consumed proposal duplicates a subscription"
grep -Fq 'Subscriptions were updated' "$test_tmp/cleanup-failure-error" || fail "proposal cleanup failure does not report the committed subscription change"
/bin/rm -f -- "$proposal_file"
pass "Feed Scout fails safely if consumed proposal cleanup cannot finish"

linked_urls="$test_tmp/linked-urls"
cat >"$linked_urls" <<'URLS'
"query:Inbox:unread = \"yes\""
https://existing.example/feed "Existing"
URLS
rm -f "$urls_file"
/bin/ln -s "$linked_urls" "$urls_file"
"$ROOT/bin/omarchy-newsboat-scout-propose" https://scout-three.test >"$proposal_output"
proposal_id=$(sed -n 's/^Validated Feed Scout proposal \([A-Za-z0-9_-]*\):$/\1/p' "$proposal_output")
"$ROOT/bin/omarchy-newsboat-scout-apply" "$proposal_id" 1 F001 >/dev/null
[[ -L $urls_file ]] || fail "Feed Scout replaces an externally managed subscriptions symlink"
grep -Fxq 'https://scout-three.test/feed.xml' "$linked_urls" || fail "Feed Scout updates the externally managed subscriptions target"
pass "Feed Scout preserves externally managed subscriptions"

grep -Fq 'macro d set browser "omarchy-newsboat-handoff scout %u %T %F"' "$ROOT/default/newsboat/omarchy.conf" || fail "Newsboat exposes non-blocking article-driven Feed Scout"
grep -F 'macro d ' "$ROOT/default/newsboat/omarchy.conf" | grep -Fq '; quit; quit --' || fail "Newsboat closes both its article and feed lists before Feed Scout changes subscriptions"
grep -Fq 'state_dir="${NEWSBOAT_SCOUT_STATE_DIR:-/tmp/omarchy-newsboat-$UID/scouts}"' "$ROOT/bin/omarchy-newsboat-scout-propose" || fail "Feed Scout keeps proposal state in the agent-writable private temp area"
grep -Fq 'omarchy-newsboat-confirm" scout' "$ROOT/bin/omarchy-newsboat-scout-apply" || fail "Feed Scout trusts the agent prompt as its only mutation confirmation"
pass "Newsboat exposes the agent-independent Feed Scout experience"
