#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

PERF_STATE_DIR=$(mktemp -d)
trap 'rm -rf -- "$PERF_STATE_DIR"' EXIT

python3 - "$ROOT/shell/plugins/panels/news/fetch_news.py" "$PERF_STATE_DIR" <<'PY'
import importlib.util
import io
import json
import os
import sys
import threading
import time
from contextlib import redirect_stdout

path, state_dir = sys.argv[1:]
os.environ["XDG_STATE_HOME"] = state_dir

spec = importlib.util.spec_from_file_location("fetch_news_perf", path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

custom_setting = "; ".join(
    f"Custom {index}|https://feed-{index}.example/rss" for index in range(10)
)
source_ids = ",".join(module.TECH_FEED_IDS)
sources = module.selected_sources(source_ids, custom_setting)
assert len(sources) == 21, len(sources)

network_calls = []
network_lock = threading.Lock()
article_body = "x" * module.MAX_ARTICLE_CHARS


def article_url(source, index):
    if source.get("allow_external_articles") is True:
        return f"https://articles.example/story-{source['id']}-{index}"
    host = source["article_hosts"][0]
    prefix = str(source["article_path_prefix"]).rstrip("/")
    return f"https://{host}{prefix}/story-{index}"


def feed_payload(source):
    items = []
    for index in range(module.MAX_ITEMS):
        link = article_url(source, index)
        items.append(
            "<item>"
            f"<title>Story {index}</title><link>{link}</link><guid>{link}</guid>"
            f"<description>Summary {index}</description>"
            f"<content:encoded><![CDATA[<p>{article_body}</p>]]></content:encoded>"
            "</item>"
        )
    return (
        '<rss xmlns:content="http://purl.org/rss/1.0/modules/content/" version="2.0">'
        f"<channel><title>{source['name']}</title>{''.join(items)}</channel></rss>"
    ).encode()


def cold_fetch(source):
    with network_lock:
        network_calls.append(source["id"])
    return feed_payload(source)


def run_main(*extra_args):
    output = io.StringIO()
    started = time.perf_counter()
    with redirect_stdout(output):
        code = module.main(
            [
                "--sources",
                source_ids,
                "--custom-feeds",
                custom_setting,
                "--item-limit",
                "10",
                *extra_args,
            ]
        )
    elapsed = time.perf_counter() - started
    assert code == 0
    raw = output.getvalue()
    return json.loads(raw), len(raw.encode()), elapsed


module.fetch = cold_fetch
cold, cold_bytes, cold_elapsed = run_main()
assert len(network_calls) == 21, network_calls
assert len(set(network_calls)) == 21, network_calls
assert len(cold["sources"]) == 21
assert len(cold["items"]) == 210
assert all(source["itemCount"] == 10 for source in cold["sources"])
assert cold_bytes < 6 * 1024 * 1024, cold_bytes
assert cold_elapsed < 10.0, cold_elapsed


def forbidden_fetch(source):
    raise AssertionError(f"warm cache attempted network access for {source['id']}")


module.fetch = forbidden_fetch
warm, warm_bytes, warm_elapsed = run_main("--max-cache-age", "900")
assert len(warm["sources"]) == 21
assert len(warm["items"]) == 210
assert all(source["cached"] is True for source in warm["sources"])
assert warm_bytes < 6 * 1024 * 1024, warm_bytes
assert warm_elapsed < 5.0, warm_elapsed

print(
    "rss-reader-perf "
    f"sources=21 items=210 cold_ms={cold_elapsed * 1000:.1f} "
    f"warm_ms={warm_elapsed * 1000:.1f} payload_kib={warm_bytes / 1024:.1f}"
)
PY

pass "RSS Reader cold and warm paths stay within bounded performance budgets"
pass "RSS Reader warm cache performs zero network fetches at the 21-source ceiling"

node - "$ROOT/shell/plugins/panels/news/Collections.js" <<'JS'
const collections = require(process.argv[2])

const sourceUrls = Array.from({ length: 21 }, (_, index) => `https://feed-${index}.example/rss`)
const groups = Array.from({ length: 8 }, (_, index) => ({
  id: `group-${index}`,
  name: `Group ${index}`,
  sourceUrls: sourceUrls.filter((_, sourceIndex) => (sourceIndex + index) % 3 === 0)
}))
const items = sourceUrls.flatMap((sourceUrl, sourceIndex) =>
  Array.from({ length: 10 }, (_, itemIndex) => ({
    id: `${sourceIndex}:${itemIndex}`,
    sourceId: `source-${sourceIndex}`,
    sourceUrl
  }))
)

const started = process.hrtime.bigint()
let index
for (let run = 0; run < 1000; run++) index = collections.buildItemIndex(items, groups, 10)
const elapsedMs = Number(process.hrtime.bigint() - started) / 1e6

if (index.all.length !== 10) throw new Error(`unexpected aggregate size: ${index.all.length}`)
if (index['collection:group-0'].length !== 10) throw new Error('collection index is incomplete')
if (elapsedMs >= 5000) throw new Error(`collection indexing exceeded budget: ${elapsedMs.toFixed(1)}ms`)
console.log(`rss-reader-collections sources=21 items=210 groups=8 rebuilds=1000 elapsed_ms=${elapsedMs.toFixed(1)}`)
JS

pass "RSS Reader collection indexing stays within its bounded performance budget"
