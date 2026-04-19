#!/bin/bash

# ── Systemd user service for the Vibe Bar daemon ──────────────────────────────
mkdir -p ~/.config/systemd/user

cat > ~/.config/systemd/user/omarchy-vibe-bar.service << SERVICE
[Unit]
Description=Omarchy Vibe Bar — AI agents activity daemon

[Service]
ExecStart=$OMARCHY_PATH/bin/omarchy-vibe-bar start --foreground
Restart=on-failure
RestartSec=2

[Install]
WantedBy=default.target
SERVICE

systemctl --user daemon-reload
systemctl --user enable --now omarchy-vibe-bar

# ── Claude Code hooks ─────────────────────────────────────────────────────────
if omarchy-cmd-present claude; then
  SETTINGS="$HOME/.claude/settings.json"
  HOOK_CMD="$OMARCHY_PATH/default/vibe-bar/hook.py"
  mkdir -p "$(dirname "$SETTINGS")"

  python3 - "$SETTINGS" "$HOOK_CMD" << 'EOF'
import json, sys, os

settings_path = sys.argv[1]
hook_cmd = sys.argv[2]

if os.path.exists(settings_path):
    with open(settings_path) as f:
        settings = json.load(f)
else:
    settings = {}

hook_entry = {"type": "command", "command": hook_cmd}
hook_block = {"hooks": [hook_entry]}

events = [
    "PreToolUse", "PermissionRequest", "PostToolUse", "Stop",
    "UserPromptSubmit", "SessionStart", "SessionEnd", "Notification",
]

existing_hooks = settings.get("hooks", {})
for event in events:
    matchers = existing_hooks.get(event, [])
    if not isinstance(matchers, list):
        matchers = [matchers]
    if hook_block not in matchers:
        matchers.append(hook_block)
    existing_hooks[event] = matchers
settings["hooks"] = existing_hooks

with open(settings_path, "w") as f:
    json.dump(settings, f, indent=2)
EOF
fi

# ── OpenCode plugin ───────────────────────────────────────────────────────────
if [[ -d "$HOME/.config/opencode" ]]; then
  mkdir -p "$HOME/.config/opencode/plugins"
  cp "$OMARCHY_PATH/default/vibe-bar/opencode_plugin.js" \
     "$HOME/.config/opencode/plugins/vibe-bar.js"
fi