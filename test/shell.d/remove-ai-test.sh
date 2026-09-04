#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

mkdir -p "$tmp_dir/bin"

cat >"$tmp_dir/bin/omarchy-pkg-drop" <<'SCRIPT'
#!/bin/bash
printf 'drop:%s\n' "$*" >>"$TEST_LOG"
SCRIPT
chmod +x "$tmp_dir/bin/omarchy-pkg-drop"

export TEST_LOG="$tmp_dir/log"
export PATH="$tmp_dir/bin:$PATH"

fresh_home() {
  rm -rf "$tmp_dir/home"
  mkdir -p "$tmp_dir/home"
  export HOME="$tmp_dir/home"
}

# The Codex CLI ships in its own package and resolves its runtime out of
# ~/.cache/codex-runtimes, so removing the desktop app must not take it.
fresh_home
mkdir -p "$HOME/.config/Codex" "$HOME/.cache/Codex" "$HOME/.cache/codex-runtimes/codex-primary-runtime" "$HOME/.codex"
"$ROOT/bin/omarchy-remove-ai-chatgpt" >/dev/null

[[ ! -e $HOME/.config/Codex ]] || fail "ChatGPT removal deletes the desktop app's config"
pass "ChatGPT removal deletes the desktop app's config"

[[ -d $HOME/.cache/codex-runtimes/codex-primary-runtime ]] || fail "ChatGPT removal keeps the Codex CLI's runtime cache"
pass "ChatGPT removal keeps the Codex CLI's runtime cache"

[[ -d $HOME/.codex ]] || fail "ChatGPT removal keeps the Codex CLI's config"
pass "ChatGPT removal keeps the Codex CLI's config"

# LM Studio's models follow a relocatable home, named only by the pointer file.
fresh_home
mkdir -p "$tmp_dir/relocated-models/models"
printf '%s' "$tmp_dir/relocated-models" >"$HOME/.lmstudio-home-pointer"
mkdir -p "$HOME/.config/LM Studio"
"$ROOT/bin/omarchy-remove-ai-lm-studio" >/dev/null

[[ ! -e $tmp_dir/relocated-models ]] || fail "LM Studio removal follows a relocated home pointer"
pass "LM Studio removal follows a relocated home pointer"

[[ ! -e "$HOME/.config/LM Studio" ]] || fail "LM Studio removal deletes its config"
pass "LM Studio removal deletes its config"

# A pointer that resolves to the home directory itself would take everything.
fresh_home
printf '%s' "$HOME" >"$HOME/.lmstudio-home-pointer"
mkdir -p "$HOME/Documents"
"$ROOT/bin/omarchy-remove-ai-lm-studio" >/dev/null

[[ -d $HOME/Documents ]] || fail "LM Studio removal refuses a pointer aimed at the home directory"
pass "LM Studio removal refuses a pointer aimed at the home directory"

# T3 Code bootstraps the agents it drives; their state outlives it.
fresh_home
mkdir -p "$HOME/.config/t3code" "$HOME/.t3" "$HOME/.grok" "$HOME/.local/share/opencode" "$HOME/.npm"
touch "$HOME/.claude.json"
"$ROOT/bin/omarchy-remove-ai-t3-code" >/dev/null

[[ ! -e $HOME/.t3 ]] || fail "T3 Code removal deletes its own data"
pass "T3 Code removal deletes its own data"

for kept in .grok .claude.json .npm .local/share/opencode; do
  [[ -e $HOME/$kept ]] || fail "T3 Code removal keeps the agent state it bootstrapped" "$kept"
done
pass "T3 Code removal keeps the agent state it bootstrapped"

# ~/.grok belongs to the Grok CLI that omarchy-default-agent installs.
fresh_home
mkdir -p "$HOME/.config/Grok Bot" "$HOME/.grokbot" "$HOME/.grok"
"$ROOT/bin/omarchy-remove-ai-grok-bot" >/dev/null

[[ ! -e $HOME/.grokbot ]] || fail "Grok Bot removal deletes its own data"
pass "Grok Bot removal deletes its own data"

[[ -d $HOME/.grok ]] || fail "Grok Bot removal keeps the Grok CLI's state"
pass "Grok Bot removal keeps the Grok CLI's state"

# Every acceleration variant depends on the base package, so package presence is
# the test the remover can actually act on; the command alone is also provided by
# builds omarchy-pkg-drop will not touch.
ollama_row=$(grep '^  "remove.ai.ollama":' "$ROOT/default/omarchy/omarchy-menu.jsonc")
[[ $ollama_row == *'"when":"omarchy-pkg-present ollama"'* ]] ||
  fail "Ollama removal is offered only where the package is installed" "$ollama_row"
pass "Ollama removal is offered only where the package is installed"

# OpenClaw's gateway unit and web app launcher are the app's own; the agent
# state in ~/.openclaw is the user's. systemctl and openclaw are stubbed so the
# sandbox never reaches the real user manager or a real gateway.
cat >"$tmp_dir/bin/systemctl" <<'SCRIPT'
#!/bin/bash
printf 'systemctl:%s\n' "$*" >>"$TEST_LOG"
SCRIPT
chmod +x "$tmp_dir/bin/systemctl"

# Default openclaw stub: the packaged CLI predates `gateway uninstall`, so the
# remover has to fall back to its manual systemd path.
cat >"$tmp_dir/bin/openclaw" <<'SCRIPT'
#!/bin/bash
printf 'openclaw:%s\n' "$*" >>"$TEST_LOG"
exit 1
SCRIPT
chmod +x "$tmp_dir/bin/openclaw"

fresh_openclaw_home() {
  fresh_home
  mkdir -p "$HOME/.config/systemd/user/default.target.wants" "$HOME/.openclaw" \
    "$HOME/.local/share/applications" "$HOME/.local/share/icons/hicolor/256x256/apps"
  touch "$HOME/.config/systemd/user/openclaw-gateway.service" \
    "$HOME/.config/systemd/user/openclaw-gateway.service.bak" \
    "$HOME/.config/systemd/user/openclaw-node.service" \
    "$HOME/.openclaw/openclaw.json" \
    "$HOME/.local/share/applications/OpenClaw.desktop" \
    "$HOME/.local/share/icons/hicolor/256x256/apps/openclaw.png"
  ln -s ../openclaw-gateway.service \
    "$HOME/.config/systemd/user/default.target.wants/openclaw-gateway.service"
  ln -s ../openclaw-node.service \
    "$HOME/.config/systemd/user/default.target.wants/openclaw-node.service"
}

# gum would ask about ~/.openclaw; the tests never run on a terminal, so it
# must not even be reached. Logging it proves that.
cat >"$tmp_dir/bin/gum" <<'SCRIPT'
#!/bin/bash
printf 'gum:%s\n' "$*" >>"$TEST_LOG"
exit 0
SCRIPT
chmod +x "$tmp_dir/bin/gum"

fresh_openclaw_home
"$ROOT/bin/omarchy-remove-ai-openclaw" >/dev/null

for gone in .config/systemd/user/openclaw-gateway.service \
  .config/systemd/user/openclaw-gateway.service.bak \
  .config/systemd/user/default.target.wants/openclaw-gateway.service \
  .config/systemd/user/openclaw-node.service \
  .config/systemd/user/default.target.wants/openclaw-node.service \
  .local/share/applications/OpenClaw.desktop \
  .local/share/icons/hicolor/256x256/apps/openclaw.png; do
  [[ ! -e $HOME/$gone && ! -L $HOME/$gone ]] || fail "OpenClaw removal deletes the service and launcher it installed" "$gone"
done
pass "OpenClaw removal deletes the service and launcher it installed"

grep -q '^systemctl:--user disable --now openclaw-gateway.service$' "$TEST_LOG" ||
  fail "OpenClaw removal stops the gateway service"
grep -q '^systemctl:--user disable --now openclaw-node.service$' "$TEST_LOG" ||
  fail "OpenClaw removal stops the gateway service" "node host service left running"
for unit in openclaw-gateway.service openclaw-node.service; do
  grep -q "^systemctl:--user reset-failed $unit\$" "$TEST_LOG" ||
    fail "OpenClaw removal stops the gateway service" "$unit left in systemd's failed list"
done
pass "OpenClaw removal stops the gateway service"

# Without a terminal there is nobody to ask, so the state stays and gum is
# never invoked (a gum that answered "yes" on its own would be a data loss).
[[ -f $HOME/.openclaw/openclaw.json ]] || fail "OpenClaw removal keeps the user's agent state"
! grep -q '^gum:' "$TEST_LOG" ||
  fail "OpenClaw removal keeps the user's agent state" "asked about ~/.openclaw without a terminal"
pass "OpenClaw removal keeps the user's agent state"

# A CLI that knows `gateway uninstall` owns the teardown; the manual systemd
# fallback must not run.
cat >"$tmp_dir/bin/openclaw" <<'SCRIPT'
#!/bin/bash
printf 'openclaw:%s\n' "$*" >>"$TEST_LOG"
rm -f "$HOME/.config/systemd/user/openclaw-$1.service" \
  "$HOME/.config/systemd/user/default.target.wants/openclaw-$1.service"
SCRIPT
chmod +x "$tmp_dir/bin/openclaw"

: >"$TEST_LOG"
fresh_openclaw_home
"$ROOT/bin/omarchy-remove-ai-openclaw" >/dev/null

grep -q '^openclaw:gateway uninstall$' "$TEST_LOG" ||
  fail "OpenClaw removal prefers upstream's own gateway teardown"
grep -q '^openclaw:node uninstall$' "$TEST_LOG" ||
  fail "OpenClaw removal prefers upstream's own gateway teardown" "node host not handed to upstream"
! grep -q '^systemctl:--user disable' "$TEST_LOG" ||
  fail "OpenClaw removal prefers upstream's own gateway teardown" "manual disable ran too"
pass "OpenClaw removal prefers upstream's own gateway teardown"

# Without the unit file there is nothing of ours registered, so systemd stays untouched.
systemctl_calls_before=$(grep -c '^systemctl:' "$TEST_LOG" || true)
fresh_home
"$ROOT/bin/omarchy-remove-ai-openclaw" >/dev/null
systemctl_calls_after=$(grep -c '^systemctl:' "$TEST_LOG" || true)

[[ $systemctl_calls_before == "$systemctl_calls_after" ]] ||
  fail "OpenClaw removal leaves systemd alone when onboarding never ran"
pass "OpenClaw removal leaves systemd alone when onboarding never ran"

# A gateway that will not stop aborts the removal before the package drop:
# pacman would otherwise strand the live process on deleted code.
cat >"$tmp_dir/bin/openclaw" <<'SCRIPT'
#!/bin/bash
printf 'openclaw:%s\n' "$*" >>"$TEST_LOG"
exit 1
SCRIPT
chmod +x "$tmp_dir/bin/openclaw"
cat >"$tmp_dir/bin/systemctl" <<'SCRIPT'
#!/bin/bash
printf 'systemctl:%s\n' "$*" >>"$TEST_LOG"
[[ $2 == disable ]] && exit 1
[[ $2 == is-active ]] && exit 0
exit 0
SCRIPT
chmod +x "$tmp_dir/bin/systemctl"

drop_calls_before=$(grep -c '^drop:openclaw$' "$TEST_LOG" || true)
fresh_openclaw_home
rc=0
"$ROOT/bin/omarchy-remove-ai-openclaw" >/dev/null 2>&1 || rc=$?
drop_calls_after=$(grep -c '^drop:openclaw$' "$TEST_LOG" || true)

[[ $rc != 0 ]] || fail "OpenClaw removal aborts when the gateway cannot be stopped"
[[ -f $HOME/.config/systemd/user/openclaw-gateway.service ]] ||
  fail "OpenClaw removal aborts when the gateway cannot be stopped" "unit file deleted"
[[ $drop_calls_before == "$drop_calls_after" ]] ||
  fail "OpenClaw removal aborts when the gateway cannot be stopped" "package dropped anyway"
pass "OpenClaw removal aborts when the gateway cannot be stopped"

# An unreachable user manager is not a stopped gateway: every probe failing
# with no answer must still abort, not read as "confirmed inactive".
cat >"$tmp_dir/bin/systemctl" <<'SCRIPT'
#!/bin/bash
printf 'systemctl:%s\n' "$*" >>"$TEST_LOG"
echo "Failed to connect to user scope bus" >&2
exit 1
SCRIPT
chmod +x "$tmp_dir/bin/systemctl"

: >"$TEST_LOG"
fresh_openclaw_home
rc=0
"$ROOT/bin/omarchy-remove-ai-openclaw" >/dev/null 2>&1 || rc=$?

[[ $rc != 0 ]] || fail "OpenClaw removal aborts when systemd cannot be reached"
[[ -f $HOME/.config/systemd/user/openclaw-gateway.service ]] ||
  fail "OpenClaw removal aborts when systemd cannot be reached" "unit file deleted"
! grep -q '^drop:openclaw$' "$TEST_LOG" ||
  fail "OpenClaw removal aborts when systemd cannot be reached" "package dropped anyway"
pass "OpenClaw removal aborts when systemd cannot be reached"
