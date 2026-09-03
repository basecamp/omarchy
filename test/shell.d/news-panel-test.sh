#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

python3 - "$ROOT/shell/plugins/panels/news/fetch_news.py" <<'PY'
import importlib.util
import io
import json
import sys
from contextlib import redirect_stdout

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
assert items[0]["id"] == "omarchy:https://omarchy.org/news/2026/09/a-new-thing"
assert items[0]["url"] == "https://omarchy.org/news/2026/09/a-new-thing"
assert items[0]["sourceId"] == "omarchy"
assert items[0]["sourceName"] == "Omarchy"
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

bbc_xml = b'''<?xml version="1.0"?><rss version="2.0"><channel><item>
  <title>BBC headline</title>
  <link>https://www.bbc.com/news/articles/example</link>
  <guid>https://www.bbc.com/news/articles/example?at_medium=RSS</guid>
  <description>A publisher-provided summary.</description>
</item><item><title>Wrong publisher</title><link>https://example.com/news/no</link></item></channel></rss>'''
bbc_items = module.parse_feed(bbc_xml, module.SOURCE_CATALOG["bbc-news"])
assert len(bbc_items) == 1, bbc_items
assert bbc_items[0]["sourceId"] == "bbc-news"
assert bbc_items[0]["sourceName"] == "BBC News"
assert bbc_items[0]["id"] == "bbc-news:https://www.bbc.com/news/articles/example"
assert module.source_article_url("https://news.bbc.co.uk/story", module.SOURCE_CATALOG["bbc-news"])
assert module.source_article_url("https://notbbc.co.uk/story", module.SOURCE_CATALOG["bbc-news"]) == ""
assert module.source_article_url("https://attacker@bbc.com/story", module.SOURCE_CATALOG["bbc-news"]) == ""
assert module.source_article_url("https://bbc.com:444/story", module.SOURCE_CATALOG["bbc-news"]) == ""
assert [source["id"] for source in module.selected_sources("bbc-news,unknown,bbc-news")] == ["omarchy", "bbc-news"]
assert module.published_key({"published": "not a date"}) == 0.0

original_fetch = module.fetch
original_atomic_write = module.atomic_write
original_cached_result = module.cached_result
module.fetch = lambda source: xml if source["id"] == "omarchy" else (_ for _ in ()).throw(OSError("offline"))
module.atomic_write = lambda path, data: None
module.cached_result = lambda source, error: None
output = io.StringIO()
with redirect_stdout(output):
    assert module.main(["--sources", "bbc-news"]) == 0
partial_result = json.loads(output.getvalue())
assert partial_result["partial"] is True
assert len(partial_result["items"]) == 1
assert partial_result["sources"][0]["id"] == "omarchy"
assert partial_result["sources"][0]["error"] == ""
assert partial_result["sources"][1]["id"] == "bbc-news"
assert partial_result["sources"][1]["error"] == "offline"
module.fetch = original_fetch
module.atomic_write = original_atomic_write
module.cached_result = original_cached_result
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
  .barWidget.defaultSection == "right" and
  (.barWidget.schema | map(select(.key == "publisherFeeds" and .type == "enum")) | length) == 1
' "$ROOT/shell/plugins/panels/news/manifest.json" >/dev/null || fail "news plugin manifest pairs the bar widget with a desktop reader"

grep -qF 'implicitWidth: 1040' "$ROOT/shell/plugins/panels/news/Panel.qml" ||
  fail "news reader uses a desktop-sized window"
grep -qF 'omarchy-shell shell toggle omarchy.news' "$ROOT/shell/plugins/panels/news/BarWidget.qml" ||
  fail "news bar widget summons the desktop reader"
grep -qF '"↑↓ SELECT  ·  → READ"' "$ROOT/shell/plugins/panels/news/Panel.qml" ||
  fail "news feed pane explains headline navigation"
grep -qF '"↑↓ SCROLL  ·  ← FEED"' "$ROOT/shell/plugins/panels/news/Panel.qml" ||
  fail "news story pane explains article scrolling"
grep -qF 'id: sourceRail' "$ROOT/shell/plugins/panels/news/Panel.qml" ||
  fail "news reader exposes a compact source rail"
grep -qF 'Qt.Key_BracketLeft' "$ROOT/shell/plugins/panels/news/Panel.qml" ||
  fail "news source rail supports keyboard switching"
grep -qF 'onLinkActivated: function(link) { Qt.openUrlExternally(link) }' "$ROOT/shell/plugins/panels/news/Panel.qml" ||
  fail "news story opens deliberately activated links"
grep -qF 'tooltipText: "Close (Esc)"' "$ROOT/shell/plugins/panels/news/Panel.qml" ||
  fail "news reader exposes its right-side window actions"
grep -qF 'o.bind("SUPER + ALT + N", "Omarchy News", "omarchy-shell shell toggle omarchy.news")' "$ROOT/default/hypr/bindings/utilities.lua" ||
  fail "news reader has a default Hyprland shortcut"

grep -qF 'FEED_URL = "https://omarchy.org/news/rss.xml"' "$ROOT/shell/plugins/panels/news/fetch_news.py" ||
  fail "news fetcher pins the official RSS URL"
grep -qF 'MAX_RESPONSE_BYTES = 1024 * 1024' "$ROOT/shell/plugins/panels/news/fetch_news.py" ||
  fail "news fetcher bounds the response"
grep -qF 'urllib.request.ProxyHandler({})' "$ROOT/shell/plugins/panels/news/fetch_news.py" ||
  fail "news fetcher ignores inherited proxy redirection"
grep -qF 'SYSTEM_CA_BUNDLE = "/etc/ssl/certs/ca-certificates.crt"' "$ROOT/shell/plugins/panels/news/fetch_news.py" ||
  fail "news fetcher pins the system CA bundle"
grep -qF '"https://feeds.bbci.co.uk/news/rss.xml"' "$ROOT/shell/plugins/panels/news/fetch_news.py" ||
  fail "news fetcher includes the curated BBC News source"

pass "news feed parser accepts canonical items from curated sources"
pass "news plugin manifest pairs the bar widget with a multi-source desktop reader"
pass "news fetcher pins and bounds curated feeds and ignores environment redirection"
