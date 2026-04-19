#!/bin/bash
# Vibe Bar — Waybar status module script
# Returns JSON for Waybar custom module: {"text":"...","tooltip":"...","class":"..."}
#
# Env override (for testing): VIBE_STATE_FILE

STATE_FILE="${VIBE_STATE_FILE:-/tmp/vibe-agents.state.json}"

if [[ ! -f "$STATE_FILE" ]]; then
  echo '{"text": "", "class": "agents-offline"}'
  exit 0
fi

python3 - "$STATE_FILE" << 'EOF'
import json, sys, os, time
from collections import defaultdict

FRAMES_RUNNING = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
FRAMES_WAITING = ["⣾", "⣽", "⣻", "⢿", "⡿", "⣟", "⣯", "⣷"]
FPS = 12

frame = int(time.time() * FPS)

with open(sys.argv[1]) as f:
    state = json.load(f)

sessions = [s for s in state.get("sessions", []) if s.get("status") not in ("done",)]

# No live sessions at all → Waybar shows nothing (empty text hides the module).
if not sessions:
    print('{"text": "", "class": "agents-offline"}')
    sys.exit(0)

groups = defaultdict(list)
for s in sessions:
    groups[s.get("cwd") or "?"].append(s)

has_waiting = any(s["status"] == "waiting" for g in groups.values() for s in g)
has_running = any(s["status"] == "running" for g in groups.values() for s in g)
total_projects = len(groups)

if has_waiting:
    cwd, group = next((c, g) for c, g in groups.items() if any(s["status"] == "waiting" for s in g))
    ws = next(s for s in group if s["status"] == "waiting")
    project = os.path.basename(cwd) if cwd and cwd != "?" else "?"
    pending = ws.get("pending") or {}
    tool = pending.get("tool", "?")
    tooltip = f"{ws['agent']}: {tool} — {project}"
    f = FRAMES_WAITING[frame % len(FRAMES_WAITING)]
    print(json.dumps({"text": f, "tooltip": tooltip, "class": "agents-waiting"}))
elif has_running:
    tooltip = f"{total_projects} project{'s' if total_projects > 1 else ''} active"
    f = FRAMES_RUNNING[frame % len(FRAMES_RUNNING)]
    print(json.dumps({"text": f, "tooltip": tooltip, "class": "agents-active"}))
else:
    # All sessions are idle → static robot icon, no animation.
    tooltip = f"{total_projects} project{'s' if total_projects > 1 else ''} idle"
    print(json.dumps({"text": "󱚤", "tooltip": tooltip, "class": "agents-idle"}))
EOF
