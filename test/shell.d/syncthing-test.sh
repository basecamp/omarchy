#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test "syncthing model and panel contract" <<'JS'
const fs = require('fs')
const syncthing = requireFromRoot('shell/plugins/panels/syncthing/Model.js')
const panelSource = fs.readFileSync(path.join(root, 'shell/plugins/panels/syncthing/Panel.qml'), 'utf8')
const serviceSource = fs.readFileSync(path.join(root, 'shell/plugins/panels/syncthing/Service.qml'), 'utf8')

assertEqual(syncthing.formatBytes(1_530_000), '1.53 MB', 'syncthing formats byte counts')
assertEqual(syncthing.formatPercent(7.25), '7.3%', 'syncthing formats small percentages')
assertEqual(syncthing.prettyPath('/home/amy/Sync/Photos', '/home/amy'), '~/Sync/Photos', 'syncthing shortens home paths')
assertEqual(syncthing.relativeTime('2026-08-23T09:00:00Z', Date.parse('2026-08-23T11:02:00Z')), '2h ago', 'syncthing formats last-seen time')

const snapshot = syncthing.parseSnapshot(JSON.stringify({
  installed: true,
  running: true,
  authenticated: true,
  overall: 'syncing',
  syncPercent: 82.4,
  folders: [{ id: 'docs', state: 'syncing', completion: 82.4 }]
}))
assert(snapshot.ok && snapshot.folders.length === 1, 'syncthing parses a healthy snapshot')
assertEqual(syncthing.statusText(snapshot), 'Syncing · 82%', 'syncthing summarizes sync progress')
assertEqual(syncthing.folderStatusText(snapshot.folders[0]), 'Syncing · 82%', 'syncthing summarizes folder progress')

const broken = {
  id: 'docs',
  state: 'error',
  errorCount: 1,
  errors: [{ path: 'report.pdf', error: 'permission denied' }]
}
assert(syncthing.folderHasProblem(broken), 'syncthing detects folder errors')
assertDeepEqual(
  syncthing.folderProblemKeys({ folders: [broken] }),
  ['docs\nreport.pdf\npermission denied'],
  'syncthing gives folder errors stable notification keys'
)
assertDeepEqual(
  syncthing.problemKeys({
    folders: [],
    systemErrors: [{ when: '2026-08-23T11:00:00Z', message: 'Disk full' }]
  }),
  ['system\n2026-08-23T11:00:00Z\nDisk full'],
  'syncthing includes daemon errors in actionable notification keys'
)
assertDeepEqual(syncthing.addedKeys(['old'], ['new', 'old']), ['new'], 'syncthing reports only new actionable conditions')
assertDeepEqual(
  syncthing.pendingKeys({
    pendingDevices: [{ id: 'DEVICE-A' }],
    pendingFolders: [{ id: 'photos', deviceId: 'DEVICE-A' }]
  }),
  ['device:DEVICE-A', 'folder:photos:DEVICE-A'],
  'syncthing gives incoming offers stable notification keys'
)
assert(!syncthing.parseSnapshot('{').ok, 'syncthing rejects invalid helper JSON')

assert(/function scanAll\(\): string/.test(panelSource), 'syncthing exposes rescan-all over IPC')
assert(/function toggleService\(\): string/.test(panelSource), 'syncthing exposes service control over IPC')
assert(/function openWebUi\(\): string/.test(panelSource), 'syncthing exposes its Web UI handoff over IPC')
assert(/--exec", "omarchy-shell shell summon omarchy\.syncthing"/.test(serviceSource), 'syncthing notifications open the native panel')
assert(/if \(_baselineReady\) notifyTransitions[\s\S]*if \(_desiredService !== -1/.test(serviceSource), 'syncthing recognizes an intentional stop before clearing optimistic state')
assert(/notifyHealth \? Model\.addedKeys/.test(serviceSource), 'syncthing establishes a health baseline before sending problem notifications')
assert(!/X-API-Key|apiKey|apikey/i.test(panelSource + serviceSource), 'syncthing never carries its API key through QML')
JS

python3 - "$ROOT" <<'PY'
import importlib.util
import pathlib
import sys
import tempfile
from unittest import mock

root = pathlib.Path(sys.argv[1])
helper_path = root / "shell/plugins/panels/syncthing/syncthing.py"
spec = importlib.util.spec_from_file_location("omarchy_syncthing", helper_path)
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)

assert helper.normalize_gui_url("127.0.0.1:8384") == "http://127.0.0.1:8384"
assert helper.normalize_gui_url("0.0.0.0:8384") == "http://127.0.0.1:8384"
assert helper.normalize_gui_url("[::]:8384") == "http://[::1]:8384"
assert helper.normalize_gui_url("localhost:9443", tls=True) == "https://127.0.0.1:9443"

for address in ("192.168.1.20:8384", "syncthing.example:8384"):
  try:
    helper.normalize_gui_url(address)
  except helper.SyncthingError as error:
    assert error.reason == "nonlocal-api"
  else:
    raise AssertionError(f"accepted non-loopback GUI address: {address}")

try:
  helper.normalize_gui_url("127.0.0.1:not-a-port")
except helper.SyncthingError as error:
  assert error.reason == "config-error"
else:
  raise AssertionError("accepted invalid GUI port")

with tempfile.TemporaryDirectory() as temp_dir:
  config = pathlib.Path(temp_dir) / "config.xml"
  config.write_text(
    '<configuration><gui enabled="true" tls="false">'
    '<address>127.0.0.1:8384</address><apikey>secret-value</apikey>'
    '</gui></configuration>',
    encoding="utf-8",
  )
  runtime = helper.read_runtime(config)
  assert runtime["baseUrl"] == "http://127.0.0.1:8384"
  assert runtime["apiKey"] == "secret-value"


class FakeResponse:
  def __enter__(self):
    return self

  def __exit__(self, *_args):
    return False

  def read(self):
    return b'{}'


class FakeOpener:
  def open(self, _request, timeout):
    assert timeout == helper.DEFAULT_TIMEOUT
    return FakeResponse()


with mock.patch.object(helper.urllib.request, "build_opener", return_value=FakeOpener()) as build_opener:
  assert helper.request_json({"baseUrl": "http://127.0.0.1:8384", "apiKey": "secret-value"}, "/rest/system/status") == {}
  handlers = build_opener.call_args.args
  proxy_handlers = [handler for handler in handlers if isinstance(handler, helper.urllib.request.ProxyHandler)]
  assert len(proxy_handlers) == 1 and proxy_handlers[0].proxies == {}
  assert any(isinstance(handler, helper.RejectRedirectHandler) for handler in handlers)

try:
  helper.RejectRedirectHandler().redirect_request(None, None, 302, "Found", {}, "https://example.com/")
except helper.SyncthingError as error:
  assert error.reason == "unsafe-redirect"
else:
  raise AssertionError("accepted a redirect away from the configured loopback endpoint")

folder = helper.summarize_folder(
  {"id": "docs", "label": "Documents", "path": "/home/amy/Sync", "paused": False},
  {"state": "syncing", "globalBytes": 1000, "needBytes": 250, "needTotalItems": 2},
  {"errors": []},
)
assert folder["completion"] == 75
assert folder["errorCount"] == 0
assert helper.classify([folder], [], [], []) == "syncing"

folder_errors = helper.summarize_folder(
  {"id": "docs", "paused": False},
  {"state": "error", "pullErrors": 7},
  {"errors": [
    {"path": "one", "error": "denied"},
    {"path": "two", "error": "denied"},
  ]},
)
assert folder_errors["errorCount"] == 7

page_exceeds_total = helper.summarize_folder(
  {"id": "docs", "paused": False},
  {"state": "error", "pullErrors": 1},
  {"errors": [
    {"path": "one", "error": "denied"},
    {"path": "two", "error": "denied"},
  ]},
)
assert page_exceeds_total["errorCount"] == 2

folder["errors"] = [{"path": "bad", "error": "denied"}]
folder["errorCount"] = 1
assert helper.classify([folder], [], [], []) == "error"
assert helper.classify([], [{"id": "DEVICE"}], [], []) == "attention"

pending = helper.pending_folder_rows({
  "photos": {"offeredBy": {"DEVICE": {"label": "Camera Roll"}}}
}, {"DEVICE": "Phone"})
assert pending == [{
  "id": "photos",
  "label": "Camera Roll",
  "deviceId": "DEVICE",
  "deviceName": "Phone",
}]
assert helper.pending_folder_rows({"photos": {"offeredBy": None}}) == []

unavailable = helper.unavailable_snapshot(True, "failed", "config-error", "bad config")
assert unavailable["ok"] is True
assert unavailable["overall"] == "error"

# Syncthing 2.x represents an empty recent-error list as JSON null. Keep this
# live response shape pinned so an idle daemon cannot crash status collection.
assert helper.system_error_rows({"errors": None}) == []
assert helper.system_error_rows({"errors": [{"when": None, "message": "Disk full"}]}) == [
  {"when": "", "message": "Disk full"}
]
PY
pass "syncthing helper accepts local APIs and normalizes runtime state"

if rg -n 'secret-value' "$ROOT/shell/plugins/panels/syncthing" >/dev/null; then
  fail "syncthing fixture secret never enters shipped panel files"
fi
pass "syncthing panel source contains no fixture secret"
