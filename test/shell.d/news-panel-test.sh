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
assert items[0]["sourceCategory"] == "official"
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
assert module.external_url("https://attacker@example.com/path") == ""
unsafe_markup = module.article_markup('<img src="https://bad.example/pixel"><script>bad()</script><a href="javascript:alert(1)">plain label</a>')
assert "img" not in unsafe_markup
assert "bad()" not in unsafe_markup
assert "javascript" not in unsafe_markup
assert unsafe_markup == "plain label"
assert len(module.article_text("x" * (module.MAX_ARTICLE_CHARS + 1))) == module.MAX_ARTICLE_CHARS
assert module.canonical_news_url("http://omarchy.org/news/no") == ""
assert module.canonical_news_url("https://omarchy.org/not-news/no") == ""

ars_xml = b'''<?xml version="1.0"?><rss version="2.0"><channel><item>
  <title>Ars headline</title>
  <link>https://arstechnica.com/gadgets/2026/09/example/</link>
  <guid>https://arstechnica.com/gadgets/2026/09/example/?utm_source=rss</guid>
  <description>A publisher-provided summary.</description>
</item><item><title>Wrong publisher</title><link>https://example.com/news/no</link></item></channel></rss>'''
ars_items = module.parse_feed(ars_xml, module.SOURCE_CATALOG["ars-technica"])
assert len(ars_items) == 1, ars_items
assert ars_items[0]["sourceId"] == "ars-technica"
assert ars_items[0]["sourceName"] == "Ars Technica"
assert ars_items[0]["sourceCategory"] == "technology"
assert ars_items[0]["id"] == "ars-technica:https://arstechnica.com/gadgets/2026/09/example/"
assert module.source_article_url("https://www.arstechnica.com/story", module.SOURCE_CATALOG["ars-technica"])
assert module.source_article_url("https://notarstechnica.com/story", module.SOURCE_CATALOG["ars-technica"]) == ""
assert module.source_article_url("https://attacker@arstechnica.com/story", module.SOURCE_CATALOG["ars-technica"]) == ""
assert module.source_article_url("https://arstechnica.com:444/story", module.SOURCE_CATALOG["ars-technica"]) == ""

hn_source = module.SOURCE_CATALOG["hacker-news"]
assert module.source_article_url("https://example.com/story?id=42#section", hn_source) == "https://example.com/story?id=42"
assert module.source_article_url("http://example.com:80/story", hn_source) == "http://example.com/story"
assert module.source_article_url("https://attacker@example.com/story", hn_source) == ""
assert module.source_article_url("file:///tmp/story", hn_source) == ""
assert module.canonical_feed_url("https://Example.com/feed?a=1#latest") == "https://example.com/feed?a=1"
assert module.canonical_feed_url("http://example.com/feed") == ""
assert module.canonical_feed_url("https://attacker@example.com/feed") == ""
assert module.canonical_feed_url("https://127.0.0.1/feed") == ""
assert module.canonical_feed_url("https://router.local/feed") == ""
custom = module.custom_sources("LWN|https://lwn.net/headlines/rss; https://lobste.rs/rss; duplicate|https://lwn.net/headlines/rss")
assert len(custom) == 2, custom
assert custom[0]["name"] == "LWN"
assert custom[0]["category"] == "custom"
assert custom[1]["name"] == "lobste.rs"
assert custom[0]["id"].startswith("custom-")
parsed_custom, custom_errors = module.parse_custom_sources("Good|https://example.com/rss;http://localhost/rss")
assert len(parsed_custom) == 1
assert custom_errors == ["Custom feed 2 must be a public HTTPS URL"]
custom_items = module.parse_feed(
    b'''<rss version="2.0"><channel><item><title>Custom story</title><link>http://elsewhere.example/story?id=4</link></item></channel></rss>''',
    custom[0],
)
assert len(custom_items) == 1
assert custom_items[0]["url"] == "http://elsewhere.example/story?id=4"
assert [source["name"] for source in module.selected_sources("ars-technica", "LWN|https://lwn.net/headlines/rss")] == ["Omarchy", "Ars Technica", "LWN"]
original_getaddrinfo = module.socket.getaddrinfo
module.socket.getaddrinfo = lambda *args, **kwargs: [(module.socket.AF_INET, module.socket.SOCK_STREAM, 6, "", ("127.0.0.1", 443))]
try:
    module.fetch(custom[0])
    raise AssertionError("private custom feed target was accepted")
except ValueError as error:
    assert "public address" in str(error)
finally:
    module.socket.getaddrinfo = original_getaddrinfo
assert [source["id"] for source in module.selected_sources("ars-technica,unknown,ars-technica")] == ["omarchy", "ars-technica"]
assert tuple(source_id for source_id in module.TECH_FEED_IDS) == (
    "hacker-news", "ars-technica", "techcrunch", "the-verge", "wired",
    "phoronix", "its-foss", "openai-news", "hugging-face", "mit-ai",
)
assert [module.SOURCE_CATALOG[source_id]["url"] for source_id in module.TECH_FEED_IDS] == [
    "https://news.ycombinator.com/rss",
    "https://feeds.arstechnica.com/arstechnica/index",
    "https://techcrunch.com/feed/",
    "https://www.theverge.com/rss/index.xml",
    "https://www.wired.com/feed/rss",
    "https://www.phoronix.com/rss.php",
    "https://itsfoss.com/rss/",
    "https://openai.com/news/rss.xml",
    "https://huggingface.co/blog/feed.xml",
    "https://news.mit.edu/rss/topic/artificial-intelligence2",
]
assert module.published_key({"published": "not a date"}) == 0.0

original_fetch = module.fetch
original_atomic_write = module.atomic_write
original_cached_result = module.cached_result
module.fetch = lambda source: xml if source["id"] == "omarchy" else (_ for _ in ()).throw(OSError("offline"))
module.atomic_write = lambda path, data: None
module.cached_result = lambda source, error: None
output = io.StringIO()
with redirect_stdout(output):
    assert module.main(["--sources", "ars-technica", "--custom-feeds", "LWN|https://lwn.net/headlines/rss;http://localhost/rss"]) == 0
partial_result = json.loads(output.getvalue())
assert partial_result["partial"] is True
assert partial_result["configurationError"] == "Custom feed 2 must be a public HTTPS URL"
assert len(partial_result["items"]) == 1
assert partial_result["sources"][0]["id"] == "omarchy"
assert partial_result["sources"][0]["error"] == ""
assert partial_result["sources"][1]["id"] == "ars-technica"
assert partial_result["sources"][1]["error"] == "offline"
assert partial_result["sources"][2]["name"] == "LWN"
assert partial_result["sources"][2]["category"] == "custom"
assert partial_result["sources"][2]["error"] == "offline"
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
  (.barWidget.schema | map(select(.key == "enabledFeeds" and .type == "multiselect")) | length) == 1 and
  (.barWidget.schema | map(select(.key == "customFeeds" and .type == "string")) | length) == 1
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
grep -qF 'return Color.green' "$ROOT/shell/plugins/panels/news/Panel.qml" ||
  fail "news source rail maps feed categories onto theme colours"
grep -qF 'property color green:' "$ROOT/shell/Commons/Color.qml" ||
  fail "shell colour service exposes the active theme category palette"
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
grep -qF '"https://news.ycombinator.com/rss"' "$ROOT/shell/plugins/panels/news/fetch_news.py" ||
  fail "news fetcher includes the ranked tech feed pack"
! grep -qF 'bbc' "$ROOT/shell/plugins/panels/news/fetch_news.py" ||
  fail "news fetcher does not promote BBC into the initial tech feed pack"
grep -qF 'custom feed host does not resolve to a public address' "$ROOT/shell/plugins/panels/news/fetch_news.py" ||
  fail "custom feeds cannot resolve to private network addresses"

pass "news feed parser accepts canonical items from curated sources"
pass "news plugin manifest pairs the bar widget with a multi-source desktop reader"
pass "news fetcher pins and bounds curated feeds and ignores environment redirection"
