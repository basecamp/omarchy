#!/usr/bin/python3

import argparse
import concurrent.futures
import ipaddress
import json
import os
import shutil
import ssl
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path


DEFAULT_TIMEOUT = 5
REFRESH_EVENTS = ",".join([
  "ConfigSaved",
  "DeviceConnected",
  "DeviceDisconnected",
  "FolderCompletion",
  "FolderErrors",
  "FolderPaused",
  "FolderResumed",
  "FolderSummary",
  "PendingDevicesChanged",
  "PendingFoldersChanged",
  "StateChanged",
])


class SyncthingError(RuntimeError):
  def __init__(self, message, reason="api-error"):
    super().__init__(message)
    self.reason = reason


class RejectRedirectHandler(urllib.request.HTTPRedirectHandler):
  def redirect_request(self, request, fp, code, message, headers, new_url):
    raise SyncthingError("Syncthing API redirected away from its configured endpoint", "unsafe-redirect")


def run(command, timeout=4):
  try:
    result = subprocess.run(command, check=False, capture_output=True, text=True, timeout=timeout)
  except (OSError, subprocess.TimeoutExpired):
    return 1, ""
  return result.returncode, result.stdout.strip()


def service_state():
  code, output = run(["systemctl", "--user", "is-active", "syncthing.service"])
  if code == 0:
    return "active"
  return output if output in {"inactive", "failed", "activating", "deactivating"} else "inactive"


def config_candidates():
  explicit = os.environ.get("SYNCTHING_CONFIG_FILE", "").strip()
  if explicit:
    yield Path(explicit).expanduser()

  if shutil.which("syncthing"):
    code, output = run(["syncthing", "paths"])
    if code == 0:
      lines = output.splitlines()
      for index, line in enumerate(lines[:-1]):
        if line.strip() == "Configuration file:":
          yield Path(lines[index + 1].strip()).expanduser()
          break

  state_home = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state"))
  config_home = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
  yield state_home / "syncthing/config.xml"
  yield config_home / "syncthing/config.xml"


def find_config():
  seen = set()
  for candidate in config_candidates():
    path = candidate.resolve() if candidate.exists() else candidate
    if str(path) in seen:
      continue
    seen.add(str(path))
    if path.is_file():
      return path
  return None


def local_host(host):
  value = str(host or "").strip().strip("[]").lower()
  if value in {"localhost", "0.0.0.0", "::", ""}:
    return "127.0.0.1" if value != "::" else "::1"
  try:
    address = ipaddress.ip_address(value)
  except ValueError:
    raise SyncthingError("Syncthing GUI must listen on a local address", "nonlocal-api")
  if not address.is_loopback:
    raise SyncthingError("Syncthing GUI must listen on a local address", "nonlocal-api")
  return str(address)


def normalize_gui_url(address, tls=False):
  raw = str(address or "").strip()
  if raw.startswith("unix://"):
    raise SyncthingError("Unix-socket Syncthing APIs are not supported", "unsupported-api")
  if "://" not in raw:
    raw = ("https://" if tls else "http://") + raw
  parsed = urllib.parse.urlsplit(raw)
  if parsed.scheme not in {"http", "https"}:
    raise SyncthingError("Syncthing GUI must use HTTP or HTTPS", "unsupported-api")
  host = local_host(parsed.hostname)
  try:
    port = parsed.port or 8384
  except ValueError as error:
    raise SyncthingError("Syncthing GUI has an invalid port", "config-error") from error
  rendered_host = f"[{host}]" if ":" in host else host
  scheme = "https" if tls or parsed.scheme == "https" else "http"
  return f"{scheme}://{rendered_host}:{port}"


def read_runtime(config_path):
  try:
    root = ET.parse(config_path).getroot()
  except (OSError, ET.ParseError) as error:
    raise SyncthingError(f"Could not read Syncthing configuration: {error}", "config-error") from error

  gui = root.find("./gui")
  if gui is None or gui.attrib.get("enabled", "true").lower() == "false":
    raise SyncthingError("Syncthing GUI/API is disabled", "api-disabled")
  address = (gui.findtext("address") or "127.0.0.1:8384").strip()
  api_key = (gui.findtext("apikey") or "").strip()
  if not api_key:
    raise SyncthingError("Syncthing API key is missing", "missing-key")
  return {
    "configPath": str(config_path),
    "baseUrl": normalize_gui_url(address, gui.attrib.get("tls", "false").lower() == "true"),
    "apiKey": api_key,
  }


def request_json(runtime, path, method="GET", query=None, body=None, timeout=DEFAULT_TIMEOUT):
  url = runtime["baseUrl"] + path
  if query:
    url += "?" + urllib.parse.urlencode(query)
  payload = None if body is None else json.dumps(body).encode("utf-8")
  headers = {"Accept": "application/json", "X-API-Key": runtime["apiKey"]}
  if payload is not None:
    headers["Content-Type"] = "application/json"
  request = urllib.request.Request(url, data=payload, headers=headers, method=method)
  context = None
  if url.startswith("https://"):
    context = ssl.create_default_context()
    context.check_hostname = False
    context.verify_mode = ssl.CERT_NONE
  handlers = [urllib.request.ProxyHandler({}), RejectRedirectHandler()]
  if context is not None:
    handlers.append(urllib.request.HTTPSHandler(context=context))
  opener = urllib.request.build_opener(*handlers)
  try:
    with opener.open(request, timeout=timeout) as response:
      data = response.read().decode("utf-8").strip()
  except urllib.error.HTTPError as error:
    reason = "unauthorized" if error.code in {401, 403} else "api-error"
    raise SyncthingError(f"Syncthing API returned HTTP {error.code}", reason) from error
  except (urllib.error.URLError, TimeoutError, OSError) as error:
    raise SyncthingError(f"Could not reach Syncthing: {error}", "offline") from error
  if not data:
    return {}
  try:
    return json.loads(data)
  except json.JSONDecodeError as error:
    raise SyncthingError("Syncthing API returned invalid JSON", "invalid-response") from error


def safe_request(runtime, path, fallback, **kwargs):
  try:
    return request_json(runtime, path, **kwargs)
  except SyncthingError:
    return fallback


def pending_device_rows(value):
  rows = []
  source = value if isinstance(value, dict) else {}
  for device_id, entry in source.items():
    item = entry if isinstance(entry, dict) else {}
    rows.append({
      "id": device_id,
      "name": item.get("name") or item.get("deviceName") or "Unknown device",
      "address": item.get("address") or "",
    })
  return sorted(rows, key=lambda row: (row["name"].lower(), row["id"]))


def pending_folder_rows(value, device_names=None):
  rows = []
  source = value if isinstance(value, dict) else {}
  names = device_names or {}
  for folder_id, entry in source.items():
    offered_by = entry.get("offeredBy", {}) if isinstance(entry, dict) else {}
    offered_by = offered_by if isinstance(offered_by, dict) else {}
    for device_id, offer in offered_by.items():
      item = offer if isinstance(offer, dict) else {}
      rows.append({
        "id": folder_id,
        "label": item.get("label") or folder_id,
        "deviceId": device_id,
        "deviceName": names.get(device_id) or device_id,
      })
  return sorted(rows, key=lambda row: (row["label"].lower(), row["deviceName"].lower()))


def system_error_rows(value):
  source = value.get("errors", []) if isinstance(value, dict) else []
  source = source if isinstance(source, list) else []
  return [
    {"when": str(row.get("when") or ""), "message": str(row.get("message") or "")}
    for row in source if isinstance(row, dict)
  ]


def summarize_folder(folder, status, errors):
  error_rows = errors.get("errors", []) if isinstance(errors, dict) else []
  error_rows = error_rows if isinstance(error_rows, list) else []
  global_bytes = int(status.get("globalBytes") or 0)
  need_bytes = int(status.get("needBytes") or 0)
  completion = 100 if global_bytes <= 0 else max(0, min(100, (global_bytes - need_bytes) / global_bytes * 100))
  paused = folder.get("paused") is True
  raw_state = str(status.get("state") or "unknown")
  state = "paused" if paused else raw_state
  return {
    "id": str(folder.get("id") or ""),
    "label": str(folder.get("label") or folder.get("id") or "Folder"),
    "path": str(folder.get("path") or ""),
    "paused": paused,
    "state": state,
    "stateChanged": str(status.get("stateChanged") or ""),
    "globalBytes": global_bytes,
    "needBytes": need_bytes,
    "needItems": int(status.get("needTotalItems") or 0),
    "errorCount": max(len(error_rows), int(status.get("pullErrors") or 0)),
    "error": str(status.get("error") or ""),
    "watchError": str(status.get("watchError") or ""),
    "completion": completion,
    "errors": [
      {"path": str(item.get("path") or ""), "error": str(item.get("error") or "")}
      for item in error_rows if isinstance(item, dict)
    ],
  }


def classify(folders, pending_devices, pending_folders, system_errors):
  if system_errors or any(row["errorCount"] > 0 or row["error"] or row["watchError"] or row["state"] == "error" for row in folders):
    return "error"
  if pending_devices or pending_folders:
    return "attention"
  active = [row for row in folders if not row["paused"]]
  if any(row["state"] in {"syncing", "sync-preparing"} or row["needItems"] > 0 for row in active):
    return "syncing"
  if any(row["state"] in {"scanning", "scan-waiting", "cleaning"} for row in active):
    return "scanning"
  if folders and not active:
    return "paused"
  return "idle"


def unavailable_snapshot(installed, state, reason, message=""):
  return {
    # A health problem is still a valid status snapshot. `ok` is reserved for
    # bridge/protocol failures so the panel can replace stale state here.
    "ok": True,
    "installed": installed,
    "running": state in {"active", "activating"},
    "authenticated": False,
    "reason": reason,
    "message": message,
    "serviceState": state,
    "overall": "error" if state == "failed" else ("stopped" if installed else "unavailable"),
    "folders": [],
    "devices": [],
    "pendingDevices": [],
    "pendingFolders": [],
    "systemErrors": [],
  }


def snapshot():
  installed = shutil.which("syncthing") is not None
  state = service_state()
  config_path = find_config()
  if not config_path:
    return unavailable_snapshot(installed, state, "no-config", "Syncthing has not created its configuration yet")
  try:
    runtime = read_runtime(config_path)
  except SyncthingError as error:
    return unavailable_snapshot(installed, state, error.reason, str(error))

  try:
    system = request_json(runtime, "/rest/system/status")
    config = request_json(runtime, "/rest/config")
  except SyncthingError as error:
    return unavailable_snapshot(installed, state, error.reason, str(error)) | {
      "guiUrl": runtime["baseUrl"],
    }

  connections = safe_request(runtime, "/rest/system/connections", {"connections": {}})
  stats = safe_request(runtime, "/rest/stats/device", {})
  pending_devices_raw = safe_request(runtime, "/rest/cluster/pending/devices", {})
  pending_folders_raw = safe_request(runtime, "/rest/cluster/pending/folders", {})
  system_errors_raw = safe_request(runtime, "/rest/system/error", {"errors": []})
  folders_config = config.get("folders", []) if isinstance(config, dict) else []
  devices_config = config.get("devices", []) if isinstance(config, dict) else []
  folders_config = folders_config if isinstance(folders_config, list) else []
  devices_config = devices_config if isinstance(devices_config, list) else []

  def folder_runtime(folder):
    folder_id = str(folder.get("id") or "")
    status = safe_request(runtime, "/rest/db/status", {}, query={"folder": folder_id})
    errors = safe_request(runtime, "/rest/folder/errors", {"errors": []}, query={"folder": folder_id, "page": 1, "perpage": 25})
    return summarize_folder(folder, status, errors)

  with concurrent.futures.ThreadPoolExecutor(max_workers=min(6, max(1, len(folders_config)))) as executor:
    folders = list(executor.map(folder_runtime, folders_config))

  local_id = str(system.get("myID") or "")
  device_names = {str(row.get("deviceID") or ""): str(row.get("name") or "") for row in devices_config}
  connection_rows = connections.get("connections", {}) if isinstance(connections, dict) else {}
  devices = []
  for device in devices_config:
    device_id = str(device.get("deviceID") or "")
    if not device_id or device_id == local_id:
      continue
    connection = connection_rows.get(device_id, {}) if isinstance(connection_rows, dict) else {}
    statistic = stats.get(device_id, {}) if isinstance(stats, dict) else {}
    devices.append({
      "id": device_id,
      "name": str(device.get("name") or device_id),
      "paused": device.get("paused") is True,
      "connected": connection.get("connected") is True,
      "address": str(connection.get("address") or ""),
      "lastSeen": str(statistic.get("lastSeen") or ""),
    })
  devices.sort(key=lambda row: (not row["connected"], row["name"].lower()))

  pending_devices = pending_device_rows(pending_devices_raw)
  pending_folders = pending_folder_rows(pending_folders_raw, device_names)
  system_errors = system_error_rows(system_errors_raw)
  active = [row for row in folders if not row["paused"]]
  total_global = sum(row["globalBytes"] for row in active)
  total_need = sum(row["needBytes"] for row in active)
  percent = 100 if total_global <= 0 else max(0, min(100, (total_global - total_need) / total_global * 100))

  return {
    "ok": True,
    "installed": True,
    "running": True,
    "authenticated": True,
    "reason": "",
    "message": "",
    "serviceState": "active",
    "overall": classify(folders, pending_devices, pending_folders, system_errors),
    "guiUrl": runtime["baseUrl"],
    "myID": local_id,
    "myName": device_names.get(local_id) or "Syncthing",
    "syncPercent": percent,
    "totalNeedBytes": total_need,
    "totalNeedItems": sum(row["needItems"] for row in active),
    "folders": folders,
    "devices": devices,
    "pendingDevices": pending_devices,
    "pendingFolders": pending_folders,
    "systemErrors": system_errors,
  }


def runtime_or_die():
  config_path = find_config()
  if not config_path:
    raise SyncthingError("Syncthing configuration was not found", "no-config")
  return read_runtime(config_path)


def events(since, timeout):
  runtime = runtime_or_die()
  query = {"events": REFRESH_EVENTS, "timeout": max(0, min(60, timeout))}
  if since >= 0:
    query["since"] = since
  else:
    query["limit"] = 1
    query["timeout"] = 0
  rows = request_json(runtime, "/rest/events", query=query, timeout=max(DEFAULT_TIMEOUT, timeout + 2))
  rows = rows if isinstance(rows, list) else []
  last_id = int(rows[-1].get("id") or 0) if rows else max(0, since)
  return {"ok": True, "lastId": last_id, "baseline": since < 0, "events": [] if since < 0 else rows}


def action_scan(folder_id):
  runtime = runtime_or_die()
  query = {"folder": folder_id} if folder_id else None
  request_json(runtime, "/rest/db/scan", method="POST", query=query)


def action_pause(folder_id, paused):
  runtime = runtime_or_die()
  encoded = urllib.parse.quote(folder_id, safe="")
  request_json(runtime, f"/rest/config/folders/{encoded}", method="PATCH", body={"paused": paused})


def parse_args():
  parser = argparse.ArgumentParser(description="Local Syncthing bridge for the Omarchy shell")
  subparsers = parser.add_subparsers(dest="command", required=True)
  subparsers.add_parser("status")
  event_parser = subparsers.add_parser("events")
  event_parser.add_argument("--since", type=int, default=-1)
  event_parser.add_argument("--timeout", type=int, default=55)
  scan_parser = subparsers.add_parser("scan")
  scan_parser.add_argument("folder", nargs="?", default="")
  pause_parser = subparsers.add_parser("set-paused")
  pause_parser.add_argument("folder")
  pause_parser.add_argument("paused", choices=["true", "false"])
  return parser.parse_args()


def main():
  args = parse_args()
  try:
    if args.command == "status":
      result = snapshot()
    elif args.command == "events":
      result = events(args.since, args.timeout)
    elif args.command == "scan":
      action_scan(args.folder)
      result = {"ok": True}
    else:
      action_pause(args.folder, args.paused == "true")
      result = {"ok": True}
    print(json.dumps(result, separators=(",", ":")))
  except SyncthingError as error:
    print(json.dumps({"ok": False, "reason": error.reason, "message": str(error)}, separators=(",", ":")))
    if args.command not in {"status", "events"}:
      return 1
  return 0


if __name__ == "__main__":
  sys.exit(main())
