#!/bin/bash

set -euo pipefail
source "$(dirname "$0")/base-test.sh"

python3 - "$ROOT/shell/plugins/panels/news/fetch_news.py" <<'PY'
import importlib.util
import sys
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("reader", sys.argv[1])
reader = importlib.util.module_from_spec(spec)
spec.loader.exec_module(reader)
source = reader.SOURCE_CATALOG["omarchy"]
now = "2026-09-04T12:00:00+00:00"

description = 'A long paragraph. ' * 60 + '<a href="https://example.com/article">Read more</a>'
entry = '<item><title>Article</title><link>https://omarchy.org/news/one</link><description><![CDATA[' + description + ']]></description></item>'
second = '<item><title>Second</title><link>https://omarchy.org/news/two</link></item>'
feed = ('<rss><channel><item><title>Invalid</title></item>' + entry + entry + second + '</channel></rss>').encode()
articles = reader.parse_feed(feed, source, 2)
assert len(articles) == 2 and articles[1]["title"] == "Second"
assert len(articles[0]["content"]) > 500
assert '<a href="https://example.com/article">' in articles[0]["contentHtml"]

for timestamp in ("2026-09-04T12:00:00", "broken", "2027-01-01T00:00:00+00:00"):
    with patch.object(reader, "cached_result", return_value={"fetchedAt": timestamp, "items": []}):
        assert reader.fresh_cached_items(source, now, 900, 10) is None

payload = b'<rss><channel><item><title>Fresh</title><link>https://omarchy.org/news/fresh</link></item></channel></rss>'
with patch.object(reader, "fetch", return_value=payload), patch.object(reader, "atomic_write", side_effect=OSError("disk full")):
    items, state, error = reader.load_source(source, now)
    assert len(items) == 1 and items[0]["title"] == "Fresh"
    assert not state["stale"]
    assert "Could not save feed cache" in error

cached = {"items": [{"id": "cached", "title": "Offline"}]}
with patch.object(reader, "fetch", side_effect=OSError("offline")), patch.object(reader, "cached_result", return_value=cached):
    items, state, error = reader.load_source(source, now)
    assert items[0]["title"] == "Offline"
    assert state["stale"] and error == "offline"

with patch.object(reader.Path, "read_text", side_effect=UnicodeDecodeError("utf8", b'\xff', 0, 1, "invalid")):
    assert reader.cached_result(source, "") is None

# Exercise the actual redirect handler, without making a network request.
request = reader.urllib.request.Request(source["url"])
handler = reader.SafeRedirectHandler(source)
for i in range(reader.MAX_REDIRECTS):
    redirected = handler.redirect_request(request, None, 302, "Found", {}, f"https://omarchy.org/news/feed-{i}")
    assert redirected.full_url.endswith(f"feed-{i}")
try:
    handler.redirect_request(request, None, 302, "Found", {}, source["url"])
    raise AssertionError("redirect ceiling was not enforced")
except ValueError:
    pass
for target in ("http://omarchy.org/rss", "https://127.0.0.1/rss", "https://evil.example/rss", "https://user:password@omarchy.org/rss"):
    try:
        reader.SafeRedirectHandler(source).redirect_request(request, None, 302, "Found", {}, target)
        raise AssertionError(f"unsafe redirect accepted: {target}")
    except ValueError:
        pass
PY

pass "invalid cache timestamps cannot abort refresh"
pass "cache write failures preserve freshly fetched articles"
pass "offline refresh preserves cached articles with a stale indicator"
pass "invalid cache encoding is treated as a cache miss"
pass "redirect handler rejects unsafe targets and excessive hops"

run_node_test <<'JS'
const fs = require('fs')
const panel = fs.readFileSync(path.join(root, 'shell/plugins/panels/news/Panel.qml'), 'utf8')
assert(/function close\(\)\s*\{\s*markReadTimer.stop\(\)/.test(panel), 'closing the reader cancels pending automatic read acknowledgement')
assert(/function openFeedManager\(\)\s*\{\s*markReadTimer.stop\(\)/.test(panel), 'managing subscriptions cancels pending read acknowledgement')
assert(panel.includes('root.opened && !root.managingFeeds && root.news'), 'read timer checks that the reader is actually visible')
JS
