#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command python3

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

helper="$ROOT/bin/omarchy-newsboat-internal.py"
urls_file="$test_tmp/urls"

cat >"$urls_file" <<'URLS'
# Newsboat comments and query feeds are not subscriptions.
"query:Inbox:unread = \"yes\""
https://one.example/feed "First feed" tech
https://one.example/feed duplicate
https://two.example/feed
URLS

subscriptions=$(python3 "$helper" subscriptions "$urls_file")
python3 - "$subscriptions" <<'PY'
import json
import sys

subscriptions = json.loads(sys.argv[1])
assert subscriptions == [
    {"url": "https://one.example/feed", "labels": ["First feed", "tech"]},
    {"url": "https://two.example/feed", "labels": []},
]
PY
pass "Newsboat uses one subscription parser for labels, comments, queries, and duplicates"

cat >"$urls_file" <<'URLS'
https://one.example/feed "unfinished label
URLS
if python3 "$helper" subscriptions "$urls_file" >"$test_tmp/malformed-output" 2>"$test_tmp/malformed-error"; then
  fail "Newsboat accepts a malformed subscriptions file"
fi
grep -Fq "$urls_file:1:" "$test_tmp/malformed-error" || fail "subscription parse errors omit their source line"
grep -Fq 'No closing quotation' "$test_tmp/malformed-error" || fail "subscription parse errors hide the original problem"
pass "Newsboat fails closed on malformed subscription syntax"

cat >"$test_tmp/feed.xml" <<'XML'
<?xml version="1.0"?>
<rss version="2.0"><channel><title>Safe Dispatch</title><item><title>One useful thing</title></item></channel></rss>
XML
feed=$(python3 "$helper" validate-feed \
  https://safe.example/ \
  https://safe.example/feed.xml \
  'Safe page' \
  "$test_tmp/feed.xml")
python3 - "$feed" <<'PY'
import json
import sys

feed = json.loads(sys.argv[1])
assert feed["name"] == "Safe Dispatch"
assert feed["recent_titles"] == ["One useful thing"]
PY
pass "Newsboat accepts a bounded ordinary RSS document"

python3 - "$test_tmp/feed.xml" "$test_tmp/feed-utf16.xml" <<'PY'
import pathlib
import sys

source = pathlib.Path(sys.argv[1]).read_text()
pathlib.Path(sys.argv[2]).write_bytes(source.encode("utf-16"))
PY
feed=$(python3 "$helper" validate-feed \
  https://safe.example/ \
  https://safe.example/feed.xml \
  'Safe page' \
  "$test_tmp/feed-utf16.xml")
[[ $(python3 -c 'import json, sys; print(json.loads(sys.argv[1])["name"])' "$feed") == "Safe Dispatch" ]] || fail "Newsboat corrupts a safe UTF-16 feed"
pass "Newsboat accepts safe XML encodings structurally"

cat >"$test_tmp/hostile.xml" <<'XML'
<?xml version="1.0"?>
<!DOCTYPE rss [<!ENTITY injected "This must never expand">]>
<rss><channel><title>&injected;</title></channel></rss>
XML
if python3 "$helper" validate-feed \
  https://hostile.example/ \
  https://hostile.example/feed.xml \
  'Hostile page' \
  "$test_tmp/hostile.xml" >"$test_tmp/hostile-output" 2>"$test_tmp/hostile-error"; then
  fail "Newsboat accepts a feed with a DTD or entity declaration"
fi
grep -Fq 'may not declare a DTD or entity' "$test_tmp/hostile-error" || fail "unsafe XML does not explain why it was rejected"
pass "Newsboat rejects DTD and entity declarations before XML parsing"

python3 - "$test_tmp/hostile.xml" "$test_tmp/hostile-utf16.xml" <<'PY'
import pathlib
import sys

source = pathlib.Path(sys.argv[1]).read_text()
pathlib.Path(sys.argv[2]).write_bytes(source.encode("utf-16"))
PY
if python3 "$helper" validate-feed \
  https://hostile.example/ \
  https://hostile.example/feed.xml \
  'Hostile page' \
  "$test_tmp/hostile-utf16.xml" >"$test_tmp/hostile-utf16-output" 2>"$test_tmp/hostile-utf16-error"; then
  fail "Newsboat accepts an encoded DTD or expands its entity"
fi
grep -Fq 'may not declare a DTD or entity' "$test_tmp/hostile-utf16-error" || fail "encoded unsafe XML does not explain why it was rejected"
[[ ! -s $test_tmp/hostile-utf16-output ]] || fail "Newsboat exposes an entity-expanded value before rejecting encoded unsafe XML"
pass "Newsboat rejects DTDs structurally across XML encodings"

cat >"$test_tmp/not-a-feed.xml" <<'XML'
<?xml version="1.0"?><html><title>Not a feed</title></html>
XML
if python3 "$helper" validate-feed \
  https://invalid.example/ \
  https://invalid.example/document.xml \
  'Invalid page' \
  "$test_tmp/not-a-feed.xml" >/dev/null 2>&1; then
  fail "Newsboat accepts arbitrary XML as a feed"
fi
pass "Newsboat limits validated XML to RSS and Atom roots"

python3 - "$helper" "$test_tmp" <<'PY'
import json
import pathlib
import sqlite3
import subprocess
import sys

helper, directory = sys.argv[1], pathlib.Path(sys.argv[2])
cache, urls, snapshot = directory / 'cache.db', directory / 'brief-urls', directory / 'brief.json'
urls.write_text('https://articles.example/feed\n')
with sqlite3.connect(cache) as db:
    db.execute('CREATE TABLE rss_item (id INTEGER PRIMARY KEY, guid TEXT, title TEXT, url TEXT, feedurl TEXT, pubDate INTEGER, content TEXT, unread INTEGER, deleted INTEGER)')
    for index, body in enumerate([
        '<p>A useful &amp; concrete finding.</p><script>do evil</script><style>hidden</style><p>Second paragraph.</p>',
        '', '<script>only hidden text</script>',
        *['<p>' + 'long article ' * 2000 + '</p>'] * 25,
    ]):
        db.execute('INSERT INTO rss_item VALUES (?, ?, ?, ?, ?, ?, ?, 1, 0)',
                   (index, f'guid-{index}', 'A title', f'https://articles.example/{index}', 'https://articles.example/feed', 100-index, body))
result = json.loads(subprocess.check_output([sys.executable, helper, 'brief-snapshot', str(cache), str(urls), str(snapshot)]))
articles = result['articles']
assert articles[0]['excerpt'] == 'A useful & concrete finding. Second paragraph.'
assert articles[0]['content_status'] == 'cached excerpt'
print('ok - Brief extracts cached visible text without script or style content')
for article in articles[1:3]:
    assert article['excerpt'] == '' and article['content_status'] == 'unavailable'
    assert not article['markable']
print('ok - Brief keeps articles without usable cached content unread')
assert all(len(article['excerpt']) <= 1500 for article in articles)
assert sum(len(article['excerpt']) for article in articles) <= 24000
assert not articles[-1]['markable']
print('ok - Brief bounds per-article and total excerpt size and retains omitted content')
expected_read = sum(article['count'] for article in articles if article['markable'])
assert result['baseline_leave'] == result['total'] - expected_read
imports = directory / 'read-list'
subprocess.check_call([sys.executable, helper, 'triage-prepare', str(snapshot), str(cache), str(urls), str(expected_read), str(result['baseline_leave']), '[]', str(imports)], stdout=subprocess.DEVNULL)
written = imports.read_text().splitlines()
assert 'guid-1' not in written and 'guid-2' not in written and articles[-1]['guid'] not in written
assert len(written) == expected_read
print('ok - Triage cannot mark unavailable or over-budget article content read')
PY

[[ ! -x $helper ]] || fail "the internal data helper is exposed as a user command"
for wrapper in \
  omarchy-newsboat-resolve \
  omarchy-newsboat-brief \
  omarchy-newsboat-triage \
  omarchy-newsboat-scout \
  omarchy-newsboat-scout-propose \
  omarchy-newsboat-scout-apply; do
  grep -Fq 'omarchy-newsboat-internal.py' "$ROOT/bin/$wrapper" || fail "$wrapper bypasses the shared Newsboat data boundary"
done
pass "Newsboat wrappers share one non-command Python data boundary"
