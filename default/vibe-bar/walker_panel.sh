#!/bin/bash
# Vibe Bar — Agent panel
# Two-column live fzf panel: agent list (left) + detail preview (right).
# Auto-refreshes when the state file changes.

STATE_FILE="/tmp/vibe-agents.state.json"
SCRIPT_DIR="$OMARCHY_PATH/default/vibe-bar"
APPROVE_CMD="python3 $SCRIPT_DIR/approve.py"
export VIBE_SRC_DIR="$SCRIPT_DIR"

# ── If called from Waybar, open a floating Alacritty ───────────────────────────
if [[ "$1" != "--inner" ]]; then
    hyprctl dispatch exec \
        "[float;center;size 1200x680] alacritty -e bash $OMARCHY_PATH/default/vibe-bar/walker_panel.sh --inner"
    exit 0
fi

# ── Inside Alacritty: setup temp scripts and watcher ───────────────────────────
PREVIEW_PY=$(mktemp /tmp/vibe-preview-XXXXXX.py)
FOCUS_PREVIEW_PY=$(mktemp /tmp/vibe-focus-preview-XXXXXX.py)
ITEMS_PY=$(mktemp /tmp/vibe-items-XXXXXX.py)
TOGGLE_PY=$(mktemp /tmp/vibe-toggle-XXXXXX.py)
GROUPS_FILE="/tmp/vibe-agents.groups.json"
WATCHER_PID=""

cleanup() {
    [[ -n "$WATCHER_PID" ]] && kill "$WATCHER_PID" 2>/dev/null
    rm -f "$PREVIEW_PY" "$FOCUS_PREVIEW_PY" "$ITEMS_PY" "$TOGGLE_PY"
}
trap cleanup EXIT

# Random port for fzf --listen
PORT=$((20000 + RANDOM % 10000))

# ── Preview script (right panel) ───────────────────────────────────────────────
cat > "$PREVIEW_PY" << 'PYEOF'
#!/usr/bin/env python3
import json, sys, os, time

sys.path.insert(0, os.environ.get("VIBE_SRC_DIR", ""))
from preview_helpers import (
    RESET, BOLD, DIM, YELLOW, GREEN, CYAN, RED, BLUE, MAGENTA,
    SPIN_WAIT as _SPIN_WAIT, SPIN_RUN as _SPIN_RUN, PULSE as _PULSE,
    _ANSI, frame, human_duration, _visible_slice, vpad, wrap_value, format_tool,
    render_diff_lines,
)

state_file = sys.argv[1]
target_id  = sys.argv[2]

# Box geometry — adapt to the live preview pane size fzf gives us.
COLS    = int(os.environ.get("FZF_PREVIEW_COLUMNS", "56"))
LINES   = int(os.environ.get("FZF_PREVIEW_LINES",   "24"))
INNER   = max(30, COLS - 2)
INDENT  = 2
LABEL_W = 8 if INNER < 40 else (10 if INNER < 60 else 12)
GAP     = 2
VALUE_W = INNER - INDENT * 2 - LABEL_W - GAP
bar     = "─" * INNER

# ── Line budget: prevent overflow (scroll resets on every refresh) ─────────────
_rows_left = [max(4, LINES - 2)]

def _p(line=""):
    if _rows_left[0] <= 0:
        return
    print(line)
    _rows_left[0] -= 1

def bline(content):
    fw = INNER - INDENT * 2
    return f"│{' ' * INDENT}{vpad(content, fw)}{' ' * INDENT}│"

def rline(label, value, lc=DIM, vc=""):
    lp = vpad(label, LABEL_W)
    vp = vpad(str(value), VALUE_W)
    lpart = f"{lc}{lp}{RESET}" if lc else lp
    vpart = f"{vc}{vp}{RESET}" if vc else vp
    return f"│  {lpart}  {vpart}  │"

def emit_value_rows(label, text, lc=DIM, vc="", max_lines=3):
    lines = wrap_value(text, VALUE_W)
    if not lines:
        lines = [""]
    if len(lines) > max_lines:
        lines = lines[: max_lines - 1] + [lines[max_lines - 1][: VALUE_W - 1] + "…"]
    _p(rline(label, lines[0], lc=lc, vc=vc))
    for cont in lines[1:]:
        _p(rline("", cont, lc=lc, vc=vc))

def emit_diff(old, new, budget):
    for label, content in render_diff_lines(old, new, budget, VALUE_W):
        _p(rline(label, content))


# ── Main ──────────────────────────────────────────────────────────────────────
try:
    with open(state_file) as f:
        state = json.load(f)
except Exception as e:
    _p(f"Error: {e}")
    sys.exit(1)

# GROUP: target — show project summary instead of session detail
if target_id.startswith("GROUP:"):
    project_name = target_id[6:]
    sessions_in_project = [
        s for s in state.get("sessions", [])
        if os.path.basename(s.get("cwd") or "") == project_name
        and s.get("status") != "done"
    ]
    _p(f"╭{bar}╮")
    _p(bline(f"{BOLD}{CYAN}{project_name}{RESET}"))
    _p(f"├{bar}┤")
    for s in sessions_in_project:
        st   = s.get("status", "?")
        sid  = s.get("id", "?")[:8]
        if st == "waiting":
            p    = s.get("pending") or {}
            tool = p.get("tool", "?")
            _p(bline(f"  {YELLOW}● waiting{RESET}  {DIM}[{tool}]{RESET}  {DIM}{sid}{RESET}"))
        elif st == "running":
            last = s.get("last_tool") or ""
            _p(bline(f"  {GREEN}● running{RESET}  {DIM}{last}{RESET}  {DIM}{sid}{RESET}"))
        else:
            _p(bline(f"  {DIM}○ {st}  {sid}{RESET}"))
    _p(f"╰{bar}╯")
    sys.exit(0)

session = next(
    (s for s in state.get("sessions", []) if s.get("id") == target_id),
    None,
)
if not session:
    _p(bline(f"{DIM}Session not found{RESET}"))
    sys.exit(0)

status     = session.get("status", "?")
agent      = session.get("agent", "?")
cwd        = session.get("cwd", "?")
project    = os.path.basename(cwd) if cwd and cwd != "?" else "?"
last_tool  = session.get("last_tool") or ""
sid        = session.get("id", "?")
sid_short  = sid[:8] if sid and sid != "?" else "?"
started_at = session.get("started_at") or 0
last_event = session.get("last_event") or 0
now        = time.time()
age        = human_duration(now - started_at) if started_at else "?"

_p(f"╭{bar}╮")
_p(bline(f"{BOLD}{agent}{RESET}"))
_p(f"├{bar}┤")

if status == "waiting":
    p    = session.get("pending") or {}
    tool = p.get("tool", "?")
    ti   = p.get("tool_input") or {}
    waiting_for = human_duration(now - last_event) if last_event else "?"
    spin = frame(_SPIN_WAIT)
    pulse = frame(_PULSE, rate=8)

    _p(bline(f"{YELLOW}{spin}{RESET}  {YELLOW}{BOLD}Waiting for approval{RESET}"))
    _p(bline(f"{DIM}{pulse}{RESET}"))
    _p(rline("Project", project, vc=CYAN))
    _p(rline("Folder",  cwd))
    _p(rline("Session", sid_short))
    _p(rline("Age",     age))
    _p(rline("Waiting", waiting_for, vc=YELLOW))
    _p(f"├{bar}┤")
    _p(rline("Tool", tool, vc=BOLD))
    _p(bline(""))
    for (label, value, vc) in format_tool(tool, ti):
        emit_value_rows(label, value, vc=vc)

    # Diff preview for edits & writes
    if tool in ("Edit", "Write", "MultiEdit"):
        budget = max(4, LINES - 21)
        _p(bline(""))
        if tool == "Edit":
            emit_diff(ti.get("old_string"), ti.get("new_string"), budget)
        elif tool == "Write":
            emit_diff("", ti.get("content") or "", budget)
        else:
            first = (ti.get("edits") or [{}])[0]
            emit_diff(first.get("old_string"), first.get("new_string"), budget)
            remaining = len(ti.get("edits") or []) - 1
            if remaining > 0:
                _p(rline("", f"{DIM}… +{remaining} more hunk(s){RESET}"))

    # Extra tool_input fields not covered by the formatter
    known = {
        "Bash": {"command", "description"},
        "Edit": {"file_path", "old_string", "new_string", "replace_all"},
        "MultiEdit": {"file_path", "edits"},
        "Write": {"file_path", "content"},
        "Read": {"file_path", "offset", "limit"},
        "Glob": {"pattern", "path"},
        "Grep": {"pattern", "path", "glob", "type", "output_mode", "-i", "-n", "-A", "-B", "-C"},
        "WebFetch": {"url", "prompt"},
        "WebSearch": {"query"},
        "TodoWrite": {"todos"},
        "SlashCommand": {"command"},
        "NotebookEdit": {"notebook_path", "cell_id"},
    }
    if isinstance(ti, dict):
        extras = [(k, v) for k, v in ti.items() if k not in known.get(tool, set())]
        if extras:
            _p(f"├{bar}┤")
            _p(bline(f"{DIM}Extra fields{RESET}"))
            for k, v in extras[:6]:
                emit_value_rows(str(k)[:LABEL_W], v, vc=DIM)

    _p(f"├{bar}┤")
    _p(bline(f"{GREEN}[a]{RESET} Allow   {CYAN}[A]{RESET} Allow session   {YELLOW}[d]{RESET} Deny"))

elif status == "running":
    spin = frame(_SPIN_RUN)
    _p(bline(f"{GREEN}{spin}{RESET}  {GREEN}{BOLD}Running{RESET}"))
    _p(bline(""))
    _p(rline("Project", project, vc=CYAN))
    _p(rline("Folder",  cwd))
    _p(rline("Session", sid_short))
    _p(rline("Age",     age))
    if last_tool:
        _p(rline("Last",    last_tool))
    _p(bline(""))
    _p(bline(f"{DIM}Active — no pending request.{RESET}"))
    _p(bline(f"{DIM}No keybinding applies.{RESET}"))

else:
    _p(rline("Status",  status))
    _p(rline("Project", project, vc=CYAN))
    _p(rline("Session", sid_short))
    _p(rline("Age",     age))

_p(f"╰{bar}╯")
PYEOF

# ── Items script (left list) ───────────────────────────────────────────────────
cat > "$ITEMS_PY" << 'PYEOF'
#!/usr/bin/env python3
import json, sys, os
from collections import defaultdict

state_file  = sys.argv[1]
groups_file = sys.argv[2] if len(sys.argv) > 2 else None

RESET  = "\033[0m"
BOLD   = "\033[1m"
YELLOW = "\033[33m"
GREEN  = "\033[32m"
DIM    = "\033[2m"
CYAN   = "\033[36m"

try:
    with open(state_file) as f:
        state = json.load(f)
except Exception:
    sys.exit(0)

collapsed = {}
if groups_file:
    try:
        with open(groups_file) as f:
            collapsed = json.load(f)
    except Exception:
        pass

order    = {"waiting": 0, "running": 1}
sessions = [s for s in state.get("sessions", []) if s.get("status") != "done"]
sessions.sort(key=lambda s: order.get(s.get("status"), 9))

by_project = defaultdict(list)
for s in sessions:
    cwd     = s.get("cwd") or "?"
    project = os.path.basename(cwd) if cwd != "?" else "?"
    by_project[project].append(s)

# Grouping mode only active when ≥1 project has 2+ agents
grouping = any(len(v) >= 2 for v in by_project.values())

for project, group in by_project.items():
    if grouping:
        is_collapsed = collapsed.get(project, False)
        arrow = "▶" if is_collapsed else "▼"
        count = len(group)
        any_waiting = any(s.get("status") == "waiting" for s in group)
        if any_waiting:
            header = f"{YELLOW}{arrow} {project}{RESET}  {DIM}({count}){RESET}"
        else:
            header = f"{DIM}{arrow}{RESET} {project}  {DIM}({count}){RESET}"
        print(f"{header}\tGROUP:{project}")
        if is_collapsed:
            continue

    for s in group:
        cwd    = s.get("cwd") or "?"
        agent  = s.get("agent", "agent")
        status = s.get("status", "unknown")
        sid    = s.get("id", "?")

        agent_display = agent
        if agent == "opencode":
            agent_display = "OpenCode"
        elif agent == "claude-code":
            agent_display = "Claude"

        if status == "waiting":
            p     = s.get("pending") or {}
            tool  = p.get("tool", "?")
            icon  = f"{YELLOW}●{RESET}"
            label = f"{icon}  {YELLOW}{BOLD}{agent_display}{RESET}  {DIM}·{RESET}  {CYAN}{project}{RESET}  {DIM}[{RESET}{tool}{DIM}]{RESET}"
        elif status == "running":
            last  = s.get("last_tool") or ""
            icon  = f"{GREEN}●{RESET}"
            label = f"{icon}  {agent_display}  {DIM}·{RESET}  {CYAN}{project}{RESET}"
            if last:
                label += f"  {DIM}·  {last}{RESET}"
        else:
            icon  = f"{DIM}○{RESET}"
            label = f"{icon}  {DIM}{agent_display}  ·  {project}{RESET}"

        if grouping:
            label = "  " + label
        print(f"{label}\t{sid}")
PYEOF

# ── Group toggle script (l key) ───────────────────────────────────────────────
cat > "$TOGGLE_PY" << 'PYEOF'
#!/usr/bin/env python3
"""Toggle collapsed state for a project group. No-op on non-GROUP items."""
import json, sys, os

groups_file = sys.argv[1]
value       = sys.argv[2] if len(sys.argv) > 2 else ""

if not value.startswith("GROUP:"):
    sys.exit(0)

project = value[6:]

collapsed = {}
try:
    with open(groups_file) as f:
        collapsed = json.load(f)
except Exception:
    pass

collapsed[project] = not collapsed.get(project, False)

with open(groups_file, "w") as f:
    json.dump(collapsed, f)
PYEOF

# ── Focus preview script (full-pane: agent timeline + pending details) ─────────
cat > "$FOCUS_PREVIEW_PY" << 'FPEOF'
#!/usr/bin/env python3
import json, sys, os, time

sys.path.insert(0, os.environ.get("VIBE_SRC_DIR", ""))
from preview_helpers import (
    RESET, BOLD, DIM, YELLOW, GREEN, CYAN, RED,
    SPIN_WAIT, SPIN_RUN,
    _ANSI, frame, human_duration, vpad, wrap_value, format_tool, render_diff_lines,
    _visible_slice,
)

state_file = sys.argv[1]
target_id  = sys.argv[2]

COLS  = int(os.environ.get("FZF_PREVIEW_COLUMNS", "120"))
LINES = int(os.environ.get("FZF_PREVIEW_LINES",   "40"))
W     = max(60, COLS - 4)

try:
    with open(state_file) as f:
        state = json.load(f)
except Exception:
    print(f"{RED}Cannot read state file.{RESET}")
    sys.exit(0)

sess = next((s for s in state.get("sessions", []) if s.get("id") == target_id), None)
if not sess:
    print(f"{DIM}Session not found.{RESET}")
    sys.exit(0)

status  = sess.get("status", "unknown")
agent   = sess.get("agent", "agent")
cwd     = sess.get("cwd") or "?"
project = os.path.basename(cwd) if cwd != "?" else "?"
started = sess.get("started_at", 0)
now     = time.time()
age     = human_duration(now - started)
history = sess.get("tool_history", [])
pending = sess.get("pending")

agent_display = agent
if agent == "opencode":
    agent_display = "OpenCode"
elif agent == "claude-code":
    agent_display = "Claude"

if status == "waiting":
    sp   = frame(SPIN_WAIT, 8)
    stxt = f"{YELLOW}{sp} waiting{RESET}"
elif status == "running":
    sp   = frame(SPIN_RUN, 10)
    stxt = f"{GREEN}{sp} running{RESET}"
else:
    stxt = f"{DIM}{status}{RESET}"

bar       = f"{DIM}{'─' * W}{RESET}"
rows_left = max(4, LINES - 2)

def out(line=""):
    global rows_left
    if rows_left <= 0:
        return
    print(line)
    rows_left -= 1

def trunc(text, width):
    text = str(text)
    vis  = len(_ANSI.sub("", text))
    if vis <= width:
        return text
    return _visible_slice(text, 0, width - 1) + "…"

out()
out(f"  {BOLD}{CYAN}{agent_display}{RESET}  {DIM}·{RESET}  {project}  {DIM}·{RESET}  {stxt}  {DIM}({age}){RESET}")
out(f"  {DIM}{cwd}{RESET}")
out(f"  {bar}")

if pending:
    tool       = pending.get("tool", "?")
    ti         = pending.get("tool_input", {})
    last_event = sess.get("last_event") or 0
    waiting_s  = human_duration(now - last_event) if last_event else "?"

    out()
    out(f"  {YELLOW}{BOLD}Waiting for approval{RESET}  {DIM}({waiting_s}){RESET}")
    out()
    out(f"  {DIM}Tool   {RESET}{BOLD}{tool}{RESET}")
    out()

    tool_rows = format_tool(tool, ti)
    for label, value, vc in tool_rows:
        first_line = str(value).split("\n")[0]
        first_line = trunc(first_line, W - 12)
        color = vc if vc else ""
        out(f"  {DIM}{label:<8}{RESET}  {color}{first_line}{RESET}")

    # Diff section for edit/write tools
    if tool in ("Edit", "Write", "MultiEdit"):
        diff_budget = max(4, rows_left - 6)
        if tool == "Edit":
            diff_pairs = render_diff_lines(
                ti.get("old_string"), ti.get("new_string"), diff_budget, W - 12)
        elif tool == "Write":
            diff_pairs = render_diff_lines(
                "", ti.get("content") or "", diff_budget, W - 12)
        else:
            first = (ti.get("edits") or [{}])[0]
            diff_pairs = render_diff_lines(
                first.get("old_string"), first.get("new_string"), diff_budget, W - 12)
            remaining = len(ti.get("edits") or []) - 1

        out()
        for label, content in diff_pairs:
            if label:
                out(f"  {DIM}{label:<6}{RESET}  {content}")
            else:
                out(f"          {content}")
        if tool == "MultiEdit" and remaining > 0:
            out(f"  {DIM}… +{remaining} more hunk(s){RESET}")

    out()
    out(f"  {bar}")
    out()
    out(f"  {GREEN}[a]{RESET} Allow   {CYAN}[A]{RESET} Allow session   {YELLOW}[d]{RESET} Deny")

elif history:
    out()
    out(f"  {BOLD}Recent activity{RESET}  {DIM}(last {len(history)}){RESET}")
    out()
    for entry in reversed(history):
        if rows_left <= 1:
            break
        t   = entry.get("tool", "?")
        ts  = entry.get("ts", 0)
        ago = human_duration(now - ts) + " ago"
        out(f"  {DIM}▸{RESET}  {t:<32}{DIM}{ago}{RESET}")
else:
    out()
    out(f"  {DIM}No tool history recorded yet.{RESET}")
FPEOF

ITEMS_CMD="python3 $ITEMS_PY $STATE_FILE $GROUPS_FILE"

# ── Bail out early if no state ─────────────────────────────────────────────────
if [[ ! -f "$STATE_FILE" ]]; then
    printf '\033[2mNo agent state file found.\033[0m\n'
    sleep 2
    exit 0
fi

# ── Background watcher: fast animation tick + state-change reload ─────────────
# - Every ~150 ms: refresh-preview (cheap; lets spinners animate).
# - Every ~600 ms: reload the items list (spinners in the left column tick too).
# - On state-file mtime change: immediate reload+refresh-preview.
(
    LAST=$(stat -c %Y "$STATE_FILE" 2>/dev/null)
    while sleep 0.15; do
        CUR=$(stat -c %Y "$STATE_FILE" 2>/dev/null)
        if [[ -n "$CUR" && "$CUR" != "$LAST" ]]; then
            LAST="$CUR"
            curl -s -XPOST "http://localhost:$PORT" \
                -d "reload($ITEMS_CMD)+refresh-preview" >/dev/null 2>&1
            continue
        fi
        # List is static; only the right-pane preview animates.
        curl -s -XPOST "http://localhost:$PORT" \
            -d "refresh-preview" >/dev/null 2>&1
    done
) &
WATCHER_PID=$!

# ── Jump to session: focus the Hyprland window running this session ────────────
jump_to_session() {
    local target_cwd="$1"
    local addr
    addr=$(hyprctl clients -j 2>/dev/null | python3 -c "
import json, sys, os

clients = json.load(sys.stdin)
target = sys.argv[1]

# Build pid→parent map from /proc
pid_to_parent = {}
for entry in os.listdir('/proc'):
    if not entry.isdigit():
        continue
    try:
        with open(f'/proc/{entry}/status') as f:
            for line in f:
                if line.startswith('PPid:'):
                    pid_to_parent[int(entry)] = int(line.split()[1])
                    break
    except OSError:
        pass

# Find all pids whose cwd matches the session
matching_pids = set()
for entry in os.listdir('/proc'):
    if not entry.isdigit():
        continue
    try:
        if os.readlink(f'/proc/{entry}/cwd') == target:
            matching_pids.add(int(entry))
    except OSError:
        pass

# Walk up from each matching pid to see if a client owns it
client_pids = {c['pid']: c for c in clients if c.get('pid', 0) > 0}
for mpid in matching_pids:
    pid = mpid
    visited = set()
    while pid and pid not in visited:
        if pid in client_pids:
            print(client_pids[pid]['address'])
            sys.exit(0)
        visited.add(pid)
        pid = pid_to_parent.get(pid, 0)
" "$target_cwd" 2>/dev/null)
    if [[ -z "$addr" ]]; then
        notify-send "Vibe Bar" "Session window not found"
        return 1
    fi
    hyprctl dispatch focuswindow "address:$addr"
}

# ── Status helper ──────────────────────────────────────────────────────────────
get_status() {
    python3 -c "
import json, sys
with open('$STATE_FILE') as f: s = json.load(f)
for x in s.get('sessions', []):
    if x['id'] == '$1':
        print(x.get('status', 'unknown')); break
"
}

# ── Focus view: full-pane preview for one session, ESC returns ────────────────
focus_view() {
    local sid="$1"
    local fport=$((PORT + 1))
    (
        while sleep 0.15; do
            curl -s -XPOST "http://localhost:$fport" \
                -d "refresh-preview" >/dev/null 2>&1
        done
    ) &
    local fwpid=$!
    printf '%s' "$sid" | fzf \
        --listen="$fport" \
        --ansi \
        --layout=reverse-list \
        --with-nth=1 \
        --preview="python3 \"$FOCUS_PREVIEW_PY\" \"$STATE_FILE\" \"$sid\"" \
        --preview-window='up:99%:border-none:wrap' \
        --no-sort \
        --no-info \
        --border=none \
        --no-input \
        --header='  ESC back' \
        --header-first \
        --color='bg:-1,bg+:-1,prompt:cyan,pointer:cyan,border:bright-black,preview-border:bright-black' \
        2>/dev/null >/dev/null
    kill "$fwpid" 2>/dev/null
}

# ── Main loop: stay open after each action; only ESC exits ─────────────────────
while true; do
    INITIAL=$($ITEMS_CMD)
    if [[ -z "$INITIAL" ]]; then
        printf '\033[2mNo active agents.\033[0m\n'
        sleep 1.5
        exit 0
    fi

    selected=$(printf '%s\n' "$INITIAL" | fzf \
        --listen="$PORT" \
        --ansi \
        --layout=reverse-list \
        --with-nth=1 \
        --delimiter=$'\t' \
        --preview="python3 \"$PREVIEW_PY\" \"$STATE_FILE\" {2}" \
        --preview-window='right:54%:border-left:wrap' \
        --no-sort \
        --no-info \
        --disabled \
        --no-input \
        --bind="j:down,k:up" \
        --border=rounded \
        --border-label=' Agents ' \
        --color='bg:-1,bg+:-1,hl:yellow,hl+:yellow,prompt:cyan,pointer:cyan,border:bright-black,preview-border:bright-black' \
        --header=$'  ↵ jump  ·  ctrl+o focus  ·  esc close' \
        --header-first \
        --bind="a:become(printf 'ALLOW:%s' {2})" \
        --bind="A:become(printf 'ALLOWSESSION:%s' {2})" \
        --bind="d:become(printf 'DENY:%s' {2})" \
        --bind="enter:become(printf 'JUMP:%s' {2})" \
        --bind="ctrl-o:become(printf 'FOCUS:%s' {2})" \
        --bind="l:execute(python3 \"$TOGGLE_PY\" \"$GROUPS_FILE\" {2})+reload($ITEMS_CMD)" \
        2>/dev/null)

    # ESC / empty selection → exit the panel entirely
    [[ -z "$selected" ]] && exit 0

    case "$selected" in
        ALLOW:*)
            sid="${selected#ALLOW:}"
            [[ "$(get_status "$sid")" == "waiting" ]] && \
                $APPROVE_CMD "$sid" allow
            ;;
        ALLOWSESSION:*)
            sid="${selected#ALLOWSESSION:}"
            [[ "$(get_status "$sid")" == "waiting" ]] && \
                $APPROVE_CMD "$sid" allow_session
            ;;
        DENY:*)
            sid="${selected#DENY:}"
            [[ "$(get_status "$sid")" == "waiting" ]] && \
                $APPROVE_CMD "$sid" deny
            ;;
        FOCUS:*)
            sid="${selected#FOCUS:}"
            focus_view "$sid"
            ;;
        JUMP:*)
            sid="${selected#JUMP:}"
            cwd=$(python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    state = json.load(f)
for x in state.get('sessions', []):
    if x['id'] == sys.argv[2]:
        print(x.get('cwd', ''))
        break
" "$STATE_FILE" "$sid" 2>/dev/null)
            if [[ -n "$cwd" ]]; then
                jump_to_session "$cwd" && exit 0
            fi
            ;;
        GROUP:*)
            ;;
    esac
done
