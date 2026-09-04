#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/base-test.sh"

run_node_test <<'JS'
const read = require(path.join(root, 'shell/plugins/panels/news/ReadState.js'))
const fs = require('fs')
const panel = fs.readFileSync(path.join(root, 'shell/plugins/panels/news/Panel.qml'), 'utf8')
const articleChange = panel.match(/onArticlesChanged: \{([\s\S]*?)\n  \}/)[1]
const updateArticles = new Function('articles', 'currentArticle', 'selectedIndex',
  '(function() {' + articleChange + '})(); return {currentArticle, selectedIndex};')
const snapshot = {id:'one', content:'Reading this'}
const updated = updateArticles([{id:'new'}, {id:'one', content:'Publisher correction'}], snapshot, 0)
assert(updated.currentArticle === snapshot && updated.selectedIndex === 1, 'refresh preserves the reading snapshot while tracking its new list position')
assert(updateArticles([{id:'other'}], snapshot, 0).currentArticle.id === 'other', 'removed article falls back to an available entry')
assert(updateArticles([], snapshot, 0).currentArticle === null, 'empty source clears the article')
const manager = fs.readFileSync(path.join(root, 'shell/plugins/panels/news/FeedManager.qml'), 'utf8')
const persistBody = manager.match(/function persistSettings\(values\) \{([\s\S]*?)\n  \}/)[1]
const writes = []
const news = {settings: {id:'omarchy.news', enabledFeeds:[], customFeeds:'existing'}}
const shell = {updateEntryInline: (id, settings) => writes.push({id, settings})}
const persist = new Function('news', 'shell', 'values', persistBody)
persist(news, shell, {enabledFeeds:['wired']})
persist(news, shell, {feedCollections:'[]'})
assert(writes.length === 2, 'each accepted edit is submitted for persistence before returning')
assert(writes[1].settings.enabledFeeds[0] === 'wired' && writes[1].settings.customFeeds === 'existing', 'successive edits preserve other settings')
assert(writes[0].settings.feedCollections === undefined, 'later edits do not mutate earlier snapshots')
const items = [{id:'a:3', sourceId:'a'}, {id:'b:1', sourceId:'b'}, {id:'a:2', sourceId:'a'}, {id:'a:1', sourceId:'a'}]
const ids = read.mark([], 'a:3')
assert(read.isRead(items[0], items, ids, {}), 'selected article is read')
assert(!read.isRead(items[1], items, ids, {}), 'other sources remain unread')
assert(!read.isRead(items[2], items, ids, {}), 'other articles remain unread')
assert(read.mark(ids, 'a:3') === ids, 'revisiting avoids another write')
assert(read.isRead(items[3], items, [], {a:'a:2'}), 'legacy older articles remain read')
assert(!read.isRead(items[0], items, [], {a:'a:2'}), 'legacy newer articles remain unread')
assert(read.mark(Array.from({length:4096}, (_,i)=>String(i)), 'new').length === 4096, 'read history is bounded')
const restored = JSON.parse(JSON.stringify(ids))
assert(read.isRead(items[0], items, restored, {}), 'read IDs survive restart')
JS

python3 - "$ROOT/shell/plugins/panels/news/fetch_news.py" <<'PY'
import importlib.util
import sys
spec = importlib.util.spec_from_file_location('reader', sys.argv[1])
r = importlib.util.module_from_spec(spec)
spec.loader.exec_module(r)
source = r.custom_source('https://example.com/feed')
feed = b'''<feed xmlns="http://www.w3.org/2005/Atom" xml:base="https://example.com/posts/">
<entry xml:base="2026/"><title>Plain</title><id>plain</id><link href="one"/>
<content type="text">Use &lt;tag&gt; &amp; keep it literal.</content></entry>
<entry><title>XHTML</title><id>xhtml</id><link href="two"/>
<content type="xhtml"><div xmlns="http://www.w3.org/1999/xhtml" xml:base="more/">
<p>First</p><p>Second <a href="detail">link</a></p></div></content></entry>
</feed>'''
items = r.parse_feed(feed, source)
assert items[0]['url'] == 'https://example.com/posts/2026/one'
assert '<tag>' in items[0]['content'] and '&lt;tag&gt;' in items[0]['contentHtml']
assert 'First<br>Second' in items[1]['contentHtml']
assert 'href="https://example.com/posts/more/detail"' in items[1]['contentHtml']
assert 'href="https://example.com/detail"' in r.article_markup('<a href="/detail">Link</a>', base_url='https://example.com/post')
assert '<a ' not in r.article_markup('<a href="javascript:alert(1)">Bad</a>', base_url='https://example.com/')
PY
pass "Atom text, XHTML, inherited bases and safe relative links"
