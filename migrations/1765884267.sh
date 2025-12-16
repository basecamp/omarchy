echo "Change to openai-codex instead of openai-codex-bin"

if omarchy-pkg-present openai-codex-bin; then
    omarchy-pkg-drop openai-codex-bin
    omarchy-pkg-add openai-codex
fi
