#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

python3 - "$ROOT/shell/plugins/panels/news/fetch_news.py" <<'PY'
import importlib.util
import json
import sys

path = sys.argv[1]
spec = importlib.util.spec_from_file_location("fetch_news", path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

xml = b'''<?xml version="1.0"?>
<rss xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:content="http://purl.org/rss/1.0/modules/content/" version="2.0"><channel>
  <item>
    <title>  A new   Omarchy thing  </title>
    <link>https://omarchy.org/news/2026/09/a-new-thing?tracking=bad</link>
    <guid>https://omarchy.org/news/2026/09/a-new-thing</guid>
    <pubDate>Thu, 03 Sep 2026 00:00:00 GMT</pubDate>
    <dc:creator>DHH</dc:creator>
    <description>One <strong>useful</strong> sentence.</description>
    <content:encoded><![CDATA[<p>First paragraph with an <a href="https://example.com">inline link</a>.</p><p>Second paragraph.</p><ul><li>First point</li><li>Second point</li></ul>]]></content:encoded>
  </item>
  <item>
    <title>Wrong host</title>
    <link>https://example.com/news/trap</link>
  </item>
</channel></rss>'''

items = module.parse_feed(xml)
assert len(items) == 1, items
assert items[0]["title"] == "A new Omarchy thing"
assert items[0]["url"] == "https://omarchy.org/news/2026/09/a-new-thing"
assert items[0]["author"] == "DHH"
assert items[0]["summary"] == "One useful sentence."
assert items[0]["content"] == "First paragraph with an inline link.\n\nSecond paragraph.\n\n• First point\n\n• Second point"
assert "<" not in items[0]["content"]
assert "https://example.com" not in items[0]["content"]
assert len(module.article_text("x" * (module.MAX_ARTICLE_CHARS + 1))) == module.MAX_ARTICLE_CHARS
assert module.canonical_news_url("http://omarchy.org/news/no") == ""
assert module.canonical_news_url("https://omarchy.org/not-news/no") == ""
print(json.dumps(items[0], sort_keys=True))
PY

[[ -f $ROOT/shell/plugins/panels/news/manifest.json ]] || fail "news panel manifest exists"
jq -e '
  .schemaVersion == 1 and
  .id == "omarchy.news" and
  .kinds == ["bar-widget"] and
  .entryPoints.barWidget == "Panel.qml" and
  .barWidget.defaultSection == "right"
' "$ROOT/shell/plugins/panels/news/manifest.json" >/dev/null || fail "news panel manifest follows the bar-widget contract"

grep -qF 'FEED_URL = "https://omarchy.org/news/rss.xml"' "$ROOT/shell/plugins/panels/news/fetch_news.py" ||
  fail "news fetcher pins the official RSS URL"
grep -qF 'MAX_RESPONSE_BYTES = 1024 * 1024' "$ROOT/shell/plugins/panels/news/fetch_news.py" ||
  fail "news fetcher bounds the response"
grep -qF 'urllib.request.ProxyHandler({})' "$ROOT/shell/plugins/panels/news/fetch_news.py" ||
  fail "news fetcher ignores inherited proxy redirection"
grep -qF 'SYSTEM_CA_BUNDLE = "/etc/ssl/certs/ca-certificates.crt"' "$ROOT/shell/plugins/panels/news/fetch_news.py" ||
  fail "news fetcher pins the system CA bundle"

pass "news feed parser accepts only canonical Omarchy news items"
pass "news panel manifest follows the bar-widget contract"
pass "news fetcher pins and bounds the official feed and ignores environment redirection"
