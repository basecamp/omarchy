#!/usr/bin/env python3
import argparse
import json
import os
import sqlite3
import sys
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path


API_BASE = "https://api2.cursor.sh/aiserver.v1.DashboardService"
PERIOD_PATH = "GetCurrentPeriodUsage"
DEFAULT_STATE_DB = Path.home() / ".config" / "Cursor" / "User" / "globalStorage" / "state.vscdb"


def empty_result(**overrides):
  out = {
    "ready": True,
    # Meters-only: no local day/model history for chart sections.
    "hasLocalStats": False,
    "todayPrompts": 0,
    "todaySessions": 0,
    "todayTotalTokens": 0,
    "todayTokensByModel": {},
    "recentDays": [],
    "totalPrompts": 0,
    "totalSessions": 0,
    "activeDays": 0,
    "activeDates": [],
    "modelUsage": {},
    "rateLimitPercent": -1,
    "rateLimitLabel": "",
    "rateLimitResetAt": "",
    "secondaryRateLimitPercent": -1,
    "secondaryRateLimitLabel": "",
    "secondaryRateLimitResetAt": "",
    "tierLabel": "",
    "usageStatusText": "",
    "authHelpText": "",
  }
  out.update(overrides)
  return out


def expand_path(value):
  text = str(value or "").strip()
  if not text:
    return DEFAULT_STATE_DB
  return Path(os.path.expanduser(text)).expanduser()


def read_item(conn, key):
  row = conn.execute(
    "SELECT value FROM ItemTable WHERE key = ? LIMIT 1",
    (key,),
  ).fetchone()
  if not row or row[0] is None:
    return None
  value = row[0]
  if isinstance(value, bytes):
    value = value.decode("utf-8", errors="replace")
  text = str(value).strip()
  return text or None


def load_credentials(state_db):
  if not state_db.is_file():
    return None, empty_result(
      usageStatusText="Cursor unavailable",
      authHelpText="Cursor state database not found. Open Cursor and sign in.",
    )

  try:
    # Open read-only. mode=ro blocks writes through this connection; WAL/shm
    # sidecars may still exist from Cursor's writer. Avoid immutable=1 so a
    # live DB with an active WAL remains readable.
    uri = state_db.resolve().as_uri() + "?mode=ro"
    conn = sqlite3.connect(uri, uri=True, timeout=2)
  except sqlite3.Error as exc:
    return None, empty_result(
      usageStatusText="Cursor unavailable",
      authHelpText=f"Could not open Cursor database: {exc}",
    )

  try:
    conn.execute("PRAGMA query_only = ON")
    access_token = read_item(conn, "cursorAuth/accessToken")
    membership = read_item(conn, "cursorAuth/stripeMembershipType")
  except sqlite3.Error as exc:
    return None, empty_result(
      usageStatusText="Cursor unavailable",
      authHelpText=f"Could not read Cursor database: {exc}",
    )
  finally:
    conn.close()

  if not access_token:
    return None, empty_result(
      usageStatusText="Sign in to Cursor",
      authHelpText="Open Cursor and sign in.",
    )

  return {"accessToken": access_token, "membershipType": membership}, None


def to_epoch_ms(value):
  if value is None or value == "":
    return None
  if isinstance(value, (int, float)):
    number = float(value)
    # Values at/above ~1e11 are already milliseconds (ms since ~1973).
    # Smaller magnitudes are treated as seconds.
    if abs(number) >= 1e11:
      return int(number)
    return int(number * 1000.0)

  text = str(value).strip()
  if not text:
    return None
  if text.isdigit() or (text.startswith("-") and text[1:].isdigit()):
    return to_epoch_ms(float(text))

  try:
    if text.endswith("Z"):
      dt = datetime.fromisoformat(text[:-1] + "+00:00")
    else:
      dt = datetime.fromisoformat(text)
    if dt.tzinfo is None:
      dt = dt.replace(tzinfo=timezone.utc)
    return int(dt.timestamp() * 1000)
  except Exception:
    return None


def parse_billing_cycle_end(value):
  ms = to_epoch_ms(value)
  if ms is None:
    # Keep resetAt empty on unparseable input so QML date parsing stays valid.
    return ""
  try:
    return datetime.fromtimestamp(ms / 1000.0, timezone.utc).isoformat()
  except (OverflowError, OSError, ValueError):
    # Out-of-range numerics (e.g. unexpected microseconds) still clear resetAt.
    return ""


def format_tier(value):
  text = str(value or "").strip()
  if not text:
    return ""
  return " ".join(part.capitalize() for part in text.replace("_", " ").split())


def percent_to_fraction(value):
  if value is None:
    return -1
  try:
    return float(value) / 100.0
  except (TypeError, ValueError):
    return -1


def api_post(access_token, path, body, timeout=30):
  request = urllib.request.Request(
    f"{API_BASE}/{path}",
    data=json.dumps(body).encode("utf-8"),
    method="POST",
    headers={
      "Authorization": f"Bearer {access_token}",
      "Content-Type": "application/json",
      "Connect-Protocol-Version": "1",
    },
  )
  try:
    with urllib.request.urlopen(request, timeout=timeout) as response:
      raw = response.read().decode("utf-8", errors="replace")
      status = getattr(response, "status", 200)
  except urllib.error.HTTPError as exc:
    status = exc.code
    raw = exc.read().decode("utf-8", errors="replace")
    if status in (401, 403):
      return None, empty_result(
        usageStatusText="Sign in to Cursor",
        authHelpText="Cursor session expired. Open Cursor and sign in again.",
      )
    return None, empty_result(
      usageStatusText="Cursor limits unavailable",
      authHelpText=f"Usage API returned HTTP {status}",
    )
  except Exception as exc:
    return None, empty_result(
      usageStatusText="Cursor limits unavailable",
      authHelpText=str(exc),
    )

  if status < 200 or status >= 300:
    return None, empty_result(
      usageStatusText="Cursor limits unavailable",
      authHelpText=f"Usage API returned HTTP {status}",
    )

  try:
    return json.loads(raw), None
  except Exception:
    return None, empty_result(
      usageStatusText="Cursor limits unavailable",
      authHelpText="Could not parse usage response.",
    )


def fetch_period_usage(access_token):
  return api_post(access_token, PERIOD_PATH, {}, timeout=20)


def build_rate_limits(credentials, payload):
  if not isinstance(payload, dict):
    return empty_result(
      usageStatusText="Cursor limits unavailable",
      authHelpText="Usage response was not a JSON object.",
    )

  plan = payload.get("planUsage")
  if not isinstance(plan, dict):
    return empty_result(
      usageStatusText="Cursor limits unavailable",
      authHelpText="Usage response did not include plan usage.",
    )

  reset_at = parse_billing_cycle_end(payload.get("billingCycleEnd"))
  membership = credentials.get("membershipType") or payload.get("membershipType") or ""
  auto_percent = percent_to_fraction(plan.get("autoPercentUsed"))
  api_percent = percent_to_fraction(plan.get("apiPercentUsed"))
  # Treat a missing pool as 0% used when the plan object itself is present,
  # so a signed-in Cursor account still surfaces in the bar.
  if auto_percent < 0 and plan.get("autoPercentUsed") is None:
    auto_percent = 0.0
  if api_percent < 0 and plan.get("apiPercentUsed") is None:
    api_percent = 0.0

  return empty_result(
    rateLimitPercent=auto_percent,
    rateLimitLabel="Cursor Models",
    rateLimitResetAt=reset_at,
    secondaryRateLimitPercent=api_percent,
    secondaryRateLimitLabel="Other Models",
    secondaryRateLimitResetAt=reset_at,
    tierLabel=format_tier(membership),
  )


def main(argv=None):
  parser = argparse.ArgumentParser(description="Scan Cursor plan usage for omarchy model-usage")
  parser.add_argument(
    "--state-db",
    default=os.environ.get("CURSOR_STATE_DB", str(DEFAULT_STATE_DB)),
    help="Path to Cursor state.vscdb (read-only)",
  )
  args = parser.parse_args(argv)

  state_db = expand_path(args.state_db)
  credentials, error = load_credentials(state_db)
  if error is not None:
    print(json.dumps(error, separators=(",", ":")))
    return 0

  payload, error = fetch_period_usage(credentials["accessToken"])
  if error is not None:
    print(json.dumps(error, separators=(",", ":")))
    return 0

  print(json.dumps(build_rate_limits(credentials, payload), separators=(",", ":")))
  return 0


if __name__ == "__main__":
  sys.exit(main())
