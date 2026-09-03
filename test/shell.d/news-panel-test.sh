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
assert '<a href="https://example.com">inline link</a>' in items[0]["contentHtml"]
assert items[0]["contentHtml"].count("<br>") == 3
assert "<br><br>" not in items[0]["contentHtml"]
assert "<" not in items[0]["content"]
assert "https://example.com" not in items[0]["content"]
assert module.external_url("javascript:alert(1)") == ""
assert module.external_url("https://example.com/path") == "https://example.com/path"
unsafe_markup = module.article_markup('<img src="https://bad.example/pixel"><script>bad()</script><a href="javascript:alert(1)">plain label</a>')
assert "img" not in unsafe_markup
assert "bad()" not in unsafe_markup
assert "javascript" not in unsafe_markup
assert unsafe_markup == "plain label"
assert len(module.article_text("x" * (module.MAX_ARTICLE_CHARS + 1))) == module.MAX_ARTICLE_CHARS
assert module.canonical_news_url("http://omarchy.org/news/no") == ""
assert module.canonical_news_url("https://omarchy.org/not-news/no") == ""
print(json.dumps(items[0], sort_keys=True))
PY

[[ -f $ROOT/shell/plugins/panels/news/manifest.json ]] || fail "news panel manifest exists"
jq -e '
  .schemaVersion == 1 and
  .id == "omarchy.news" and
  .kinds == ["panel", "service", "bar-widget"] and
  .keepLoaded == true and
  .entryPoints.panel == "Panel.qml" and
  .entryPoints.service == "Service.qml" and
  .entryPoints.barWidget == "BarWidget.qml" and
  .barWidget.defaultSection == "right"
' "$ROOT/shell/plugins/panels/news/manifest.json" >/dev/null || fail "news plugin manifest pairs the bar widget with a desktop reader"

grep -qF 'implicitWidth: 1040' "$ROOT/shell/plugins/panels/news/Panel.qml" ||
  fail "news reader uses a desktop-sized window"
grep -qF 'omarchy-shell shell toggle omarchy.news' "$ROOT/shell/plugins/panels/news/BarWidget.qml" ||
  fail "news bar widget summons the desktop reader"
grep -qF '"↑↓ SELECT  ·  → READ"' "$ROOT/shell/plugins/panels/news/Panel.qml" ||
  fail "news feed pane explains headline navigation"
grep -qF '"↑↓ SCROLL  ·  ← FEED"' "$ROOT/shell/plugins/panels/news/Panel.qml" ||
  fail "news story pane explains article scrolling"
grep -qF 'onLinkActivated: function(link) { Qt.openUrlExternally(link) }' "$ROOT/shell/plugins/panels/news/Panel.qml" ||
  fail "news story opens deliberately activated links"
grep -qF 'tooltipText: "Close (Esc)"' "$ROOT/shell/plugins/panels/news/Panel.qml" ||
  fail "news reader exposes its right-side window actions"

grep -qF 'FEED_URL = "https://omarchy.org/news/rss.xml"' "$ROOT/shell/plugins/panels/news/fetch_news.py" ||
  fail "news fetcher pins the official RSS URL"
grep -qF 'MAX_RESPONSE_BYTES = 1024 * 1024' "$ROOT/shell/plugins/panels/news/fetch_news.py" ||
  fail "news fetcher bounds the response"
grep -qF 'urllib.request.ProxyHandler({})' "$ROOT/shell/plugins/panels/news/fetch_news.py" ||
  fail "news fetcher ignores inherited proxy redirection"
grep -qF 'SYSTEM_CA_BUNDLE = "/etc/ssl/certs/ca-certificates.crt"' "$ROOT/shell/plugins/panels/news/fetch_news.py" ||
  fail "news fetcher pins the system CA bundle"

pass "news feed parser accepts only canonical Omarchy news items"
pass "news plugin manifest pairs the bar widget with a desktop reader"
pass "news fetcher pins and bounds the official feed and ignores environment redirection"
