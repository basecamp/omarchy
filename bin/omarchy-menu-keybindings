#!/bin/bash

# A script to display Hyprland keybindings defined in your configuration
# using walker for an interactive search menu.

declare -A KEYCODE_SYM_MAP

build_keymap_cache() {
  local keymap
  keymap="$(xkbcli compile-keymap)" || {
    echo "Failed to compile keymap" >&2
    return 1
  }

  while IFS=, read -r code sym; do
    [[ -z "$code" || -z "$sym" ]] && continue
    KEYCODE_SYM_MAP["$code"]="$sym"
  done < <(
    awk '
      BEGIN { sec = "" }
      /xkb_keycodes/ { sec = "codes"; next }
      /xkb_symbols/  { sec = "syms";  next }
      sec == "codes" {
        if (match($0, /<([A-Za-z0-9_]+)>\s*=\s*([0-9]+)\s*;/, m)) code_by_name[m[1]] = m[2]
      }
      sec == "syms" {
        if (match($0, /key\s*<([A-Za-z0-9_]+)>\s*\{\s*\[\s*([^, \]]+)/, m)) sym_by_name[m[1]] = m[2]
      }
      END {
        for (k in code_by_name) {
          c = code_by_name[k]
          s = sym_by_name[k]
          if (c != "" && s != "" && s != "NoSymbol") print c "," s
        }
      }
    ' <<<"$keymap"
  )
}

lookup_keycode_cached() {
  printf '%s\n' "${KEYCODE_SYM_MAP[$1]}"
}

parse_keycodes() {
  local start end elapsed
  [[ "${DEBUG:-0}" == "1" ]] && start=$(date +%s.%N)
  while IFS= read -r line; do
    if [[ "$line" =~ code:([0-9]+) ]]; then
      code="${BASH_REMATCH[1]}"
      symbol=$(lookup_keycode_cached "$code" "$XKB_KEYMAP_CACHE")
      echo "${line/code:${code}/$symbol}"
    else
      echo "$line"
    fi
  done

  if [[ "$DEBUG" == "1" ]]; then
    end=$(date +%s.%N)
    # fall back to awk if bc is missing
    if command -v bc >/dev/null 2>&1; then
      elapsed=$(echo "$end - $start" | bc)
    else
      elapsed=$(awk -v s="$start" -v e="$end" 'BEGIN{printf "%.6f", (e - s)}')
    fi
    echo "[DEBUG] parse_keycodes elapsed: ${elapsed}s" >&2
  fi
}

# Fetch dynamic keybindings from Hyprland
#
# Also do some pre-processing:
# - Remove standard Omarchy bin path prefix
# - Remove uwsm prefix
# - Map numeric modifier key mask to a textual rendition
# - Output comma-separated values that the parser can understand
dynamic_bindings() {
  hyprctl -j binds |
    jq -r '.[] | {modmask, key, keycode, description, dispatcher, arg} | "\(.modmask),\(.key)@\(.keycode),\(.description),\(.dispatcher),\(.arg)"' |
    sed -r \
      -e 's/null//' \
      -e 's,~/.local/share/omarchy/bin/,,' \
      -e 's,uwsm app -- ,,' \
      -e 's,uwsm-app -- ,,' \
      -e 's/@0//' \
      -e 's/,@/,code:/' \
      -e 's/^0,/,/' \
      -e 's/^1,/SHIFT,/' \
      -e 's/^4,/CTRL,/' \
      -e 's/^5,/SHIFT CTRL,/' \
      -e 's/^8,/ALT,/' \
      -e 's/^9,/SHIFT ALT,/' \
      -e 's/^12,/CTRL ALT,/' \
      -e 's/^13,/SHIFT CTRL ALT,/' \
      -e 's/^64,/SUPER,/' \
      -e 's/^65,/SUPER SHIFT,/' \
      -e 's/^68,/SUPER CTRL,/' \
      -e 's/^69,/SUPER SHIFT CTRL,/' \
      -e 's/^72,/SUPER ALT,/' \
      -e 's/^73,/SUPER SHIFT ALT,/' \
      -e 's/^76,/SUPER CTRL ALT,/' \
      -e 's/^77,/SUPER SHIFT CTRL ALT,/'
}

# Parse and format keybindings
#
# `awk` does the heavy lifting:
# - Set the field separator to a comma ','.
# - Joins the key combination (e.g., "SUPER + Q").
# - Joins the command that the key executes.
# - Prints everything in a nicely aligned format.
parse_bindings() {
  awk -F, '
{
    # Combine the modifier and key (first two fields)
    key_combo = $1 " + " $2;

    # Clean up: strip leading "+" if present, trim spaces
    gsub(/^[ \t]*\+?[ \t]*/, "", key_combo);
    gsub(/[ \t]+$/, "", key_combo);

    # Use description, if set
    action = $3;

    if (action == "") {
        # Reconstruct the command from the remaining fields
        for (i = 4; i <= NF; i++) {
            action = action $i (i < NF ? "," : "");
        }

        # Clean up trailing commas, remove leading "exec, ", and trim
        sub(/,$/, "", action);
        gsub(/(^|,)[[:space:]]*exec[[:space:]]*,?/, "", action);
        gsub(/^[ \t]+|[ \t]+$/, "", action);
        gsub(/[ \t]+/, " ", key_combo);  # Collapse multiple spaces to one

        # Escape XML entities
        gsub(/&/, "\\&amp;", action);
        gsub(/</, "\\&lt;", action);
        gsub(/>/, "\\&gt;", action);
        gsub(/"/, "\\&quot;", action);
        gsub(/'"'"'/, "\\&apos;", action);
    }

    if (action != "") {
        printf "%-35s → %s\n", key_combo, action;
    }
}'
}

monitor_height=$(hyprctl monitors -j | jq -r '.[] | select(.focused == true) | .height')
menu_height=$((monitor_height * 40 / 100))

build_keymap_cache

dynamic_bindings |
  sort -u |
  parse_keycodes |
  parse_bindings |
  walker --dmenu -p 'Keybindings' --width 800 --height "$menu_height"
