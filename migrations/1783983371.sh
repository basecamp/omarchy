echo "Repair foot text-bindings broken by an earlier migration"

# The 1783833508 migration meant to append a blank line and a [text-bindings]
# section header to foot.ini, but an extra backslash made sed append the
# literal line '\n[text-bindings]' instead. foot then reports a syntax error
# on every startup, and the follow-up inserts anchored on '[text-bindings]'
# never matched, so the CSI-u bindings were never added.
foot_config="$HOME/.config/foot/foot.ini"
if [[ -f $foot_config ]]; then
  sed -i '/^\\n\[text-bindings\]$/d' "$foot_config"

  if ! grep -q '^\[text-bindings\]$' "$foot_config"; then
    sed -i '$a\\n[text-bindings]' "$foot_config"
  fi

  if ! grep -Fq '\x1b[13;4u=Mod1+Shift+Return' "$foot_config"; then
    sed -i '/^\[text-bindings\]$/a\# Send Alt+Shift+Return as CSI-u so tmux can match M-S-Enter.\n\\x1b[13;4u=Mod1+Shift+Return' "$foot_config"
  fi

  if ! grep -Fq '\x1b[13;2u=Shift+Return' "$foot_config"; then
    sed -i '/^\[text-bindings\]$/a\# Send Shift+Return as CSI-u so TUIs can distinguish it from Return.\n\\x1b[13;2u=Shift+Return' "$foot_config"
  fi
fi
