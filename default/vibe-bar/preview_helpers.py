"""Shared rendering helpers for Vibe Bar preview scripts."""
import re
import time

# ── ANSI colors ────────────────────────────────────────────────────────────────
RESET   = "\033[0m"
BOLD    = "\033[1m"
DIM     = "\033[2m"
YELLOW  = "\033[33m"
GREEN   = "\033[32m"
CYAN    = "\033[36m"
RED     = "\033[31m"
BLUE    = "\033[34m"
MAGENTA = "\033[35m"

# ── Animation frames ───────────────────────────────────────────────────────────
SPIN_WAIT = ["⣾","⣽","⣻","⢿","⡿","⣟","⣯","⣷"]
SPIN_RUN  = ["⠋","⠙","⠹","⠸","⠼","⠴","⠦","⠧","⠇","⠏"]
PULSE     = ["▱▱▱▱▱","▰▱▱▱▱","▰▰▱▱▱","▰▰▰▱▱","▰▰▰▰▱",
             "▰▰▰▰▰","▱▰▰▰▰","▱▱▰▰▰","▱▱▱▰▰","▱▱▱▱▰"]

_ANSI = re.compile(r"\033\[[0-9;]*m")


def frame(frames, rate=10):
    return frames[int(time.time() * rate) % len(frames)]


def human_duration(delta):
    delta = max(0, int(delta))
    if delta < 60:
        return f"{delta}s"
    if delta < 3600:
        return f"{delta // 60}m {delta % 60}s"
    h, rem = divmod(delta, 3600)
    return f"{h}h {rem // 60}m"


def _visible_slice(s, start, end):
    out = []
    vis = 0
    i = 0
    while i < len(s) and vis < end:
        m = _ANSI.match(s, i)
        if m:
            out.append(m.group(0))
            i = m.end()
            continue
        if vis >= start:
            out.append(s[i])
        vis += 1
        i += 1
    return "".join(out) + RESET


def vpad(s, w):
    s = str(s)
    vis = len(_ANSI.sub("", s))
    if vis > w:
        return _visible_slice(s, 0, w)
    return s + " " * (w - vis)


def wrap_value(text, width):
    text = str(text).replace("\r", "")
    out = []
    for paragraph in text.split("\n"):
        if not paragraph:
            out.append("")
            continue
        visible_len = len(_ANSI.sub("", paragraph))
        if visible_len <= width:
            out.append(paragraph)
            continue
        pos = 0
        while pos < visible_len:
            out.append(_visible_slice(paragraph, pos, pos + width))
            pos += width
    return out


def format_tool(tool, ti):
    """Return list of (label, value, value_color) tuples for a tool call."""
    if not isinstance(ti, dict):
        return [("Input", str(ti), "")]

    if tool == "Bash":
        rows = []
        cmd  = (ti.get("command") or "").strip()
        desc = (ti.get("description") or "").strip()
        if desc:
            rows.append(("Action", desc, ""))
        if cmd:
            rows.append(("$", cmd, BOLD))
        return rows

    if tool == "Edit":
        old   = ti.get("old_string") or ""
        new   = ti.get("new_string") or ""
        old_n = old.count("\n") + (1 if old else 0)
        new_n = new.count("\n") + (1 if new else 0)
        delta = f"{RED}−{old_n}{RESET}  {GREEN}+{new_n}{RESET}  {DIM}lines{RESET}"
        return [
            ("File",   ti.get("file_path", "?"), CYAN),
            ("Change", delta, ""),
        ]

    if tool == "MultiEdit":
        edits     = ti.get("edits") or []
        total_old = sum((e.get("old_string") or "").count("\n") + 1 for e in edits)
        total_new = sum((e.get("new_string") or "").count("\n") + 1 for e in edits)
        delta = f"{RED}−{total_old}{RESET}  {GREEN}+{total_new}{RESET}  {DIM}lines{RESET}"
        return [
            ("File",   ti.get("file_path", "?"), CYAN),
            ("Hunks",  str(len(edits)), ""),
            ("Change", delta, ""),
        ]

    if tool == "Write":
        content  = ti.get("content") or ""
        lines_n  = content.count("\n") + (1 if content else 0)
        size_str = f"{GREEN}+{lines_n}{RESET}  {DIM}lines · {len(content)} chars{RESET}"
        return [
            ("File", ti.get("file_path", "?"), CYAN),
            ("Size", size_str, ""),
        ]

    if tool == "Read":
        rows = [("File", ti.get("file_path", "?"), CYAN)]
        if ti.get("offset") or ti.get("limit"):
            rows.append(("Range", f"offset={ti.get('offset', 0)} limit={ti.get('limit', '?')}", ""))
        return rows

    if tool in ("Glob", "Grep"):
        rows = [("Pattern", ti.get("pattern", "?"), BOLD)]
        if ti.get("path"):  rows.append(("Path",  ti["path"], CYAN))
        if ti.get("glob"):  rows.append(("Glob",  ti["glob"], ""))
        if ti.get("type"):  rows.append(("Type",  ti["type"], ""))
        return rows

    if tool == "WebFetch":
        return [
            ("URL",    ti.get("url", "?"), CYAN),
            ("Prompt", ti.get("prompt", ""), ""),
        ]

    if tool == "WebSearch":
        return [("Query", ti.get("query", "?"), BOLD)]

    if tool == "TodoWrite":
        todos = ti.get("todos") or []
        return [("Todos", f"{len(todos)} item(s)", "")]

    if tool == "SlashCommand":
        return [("Command", ti.get("command", "?"), BOLD)]

    if tool == "NotebookEdit":
        return [
            ("Notebook", ti.get("notebook_path", "?"), CYAN),
            ("Cell",     ti.get("cell_id", "?"), ""),
        ]

    rows = []
    for k, v in list(ti.items())[:5]:
        rows.append((str(k)[:8], str(v), ""))
    return rows or [("Input", "(empty)", DIM)]


def render_diff_lines(old, new, budget, value_w):
    """Return list of (label, content) pairs for a colorised diff.

    Does NOT print — callers render using their own layout helpers.
    budget caps the total number of pairs returned.
    """
    old    = (old or "").rstrip("\n")
    new    = (new or "").rstrip("\n")
    budget = max(4, budget)
    half   = max(2, budget // 2)
    pairs  = []

    def side(text, marker, color, label, max_lines):
        raw = text.split("\n") if text else []
        if not raw:
            pairs.append((label, f"{DIM}(empty){RESET}"))
            return
        shown = raw[:max_lines]
        extra = len(raw) - len(shown)
        avail = value_w - 2
        for i, ln in enumerate(shown):
            ln = ln.replace("\t", "  ")
            if len(ln) > avail:
                ln = ln[: avail - 1] + "…"
            pairs.append((label if i == 0 else "", f"{color}{marker}{RESET} {ln}"))
        if extra > 0:
            s = "" if extra == 1 else "s"
            pairs.append(("", f"{DIM}… {extra} more line{s}{RESET}"))

    side(old, "−", RED,   "Old", half)
    side(new, "+", GREEN, "New", half)
    return pairs
