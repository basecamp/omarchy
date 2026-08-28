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
