echo "Enable the Ollama stats watcher"

if omarchy-cmd-present ollama; then
  systemctl --user daemon-reload >/dev/null 2>&1 || true

  if ! error=$(systemctl --user enable --now omarchy-ollama-context-watch.service 2>&1); then
    echo "Could not enable omarchy-ollama-context-watch.service: $error"
  fi
fi
