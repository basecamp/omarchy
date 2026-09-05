#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/base-test.sh"

python3 - "$ROOT/shell/plugins/panels/news/fetch_news.py" <<'PY'
import importlib.util
import io
import json
import sys
import threading
from contextlib import redirect_stdout
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("reader", sys.argv[1])
reader = importlib.util.module_from_spec(spec)
spec.loader.exec_module(reader)
slow = reader.SOURCE_CATALOG["omarchy"]
fast = reader.SOURCE_CATALOG["ars-technica"]
release = threading.Event()
snapshots = []

class Output(io.StringIO):
    def flush(self):
        snapshot = json.loads(self.getvalue().splitlines()[-1])
        snapshots.append(snapshot)
        if any(item["id"] == "fast" for item in snapshot["items"]):
            release.set()

def load(source, *args):
    if source is slow:
        assert release.wait(3), "fast feed was blocked behind the slow feed"
    item_id = "slow" if source is slow else "fast"
    return ([{"id": item_id}], {"id": source["id"], "stale": False}, "")

with patch.object(reader, "selected_sources", return_value=[slow, fast]), \
     patch.object(reader, "cached_result", return_value={"items": [{"id": "cached"}]}), \
     patch.object(reader, "load_source", side_effect=load), redirect_stdout(Output()):
    assert reader.main(["--stream"]) == 0
assert len(snapshots) == 3
assert all(item["id"] == "cached" for item in snapshots[0]["items"])
assert {item["id"] for item in snapshots[1]["items"]} == {"cached", "fast"}
assert {item["id"] for item in snapshots[2]["items"]} == {"slow", "fast"}

output = io.StringIO()
with patch.object(reader, "selected_sources", return_value=[slow]), \
     patch.object(reader, "fetch", side_effect=OSError("offline")), \
     patch.object(reader, "cached_result", return_value=None), redirect_stdout(output):
    assert reader.main([]) == 0
result = json.loads(output.getvalue())
assert result["items"] == [] and result["partial"]
assert result["sources"][0]["error"] == "offline"
PY
pass "cached articles emit before fetching and fast feeds bypass slow feeds"
pass "total feed failure retains structured source errors"
