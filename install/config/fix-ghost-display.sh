#!/bin/bash
set -e

SCRIPT="$HOME/.config/hypr/fix-ghost-displays.sh"
AUTOSTART="$HOME/.config/hypr/autostart.conf"

mkdir -p "$(dirname "$SCRIPT")"

cat > "$SCRIPT" <<'EOF'
#!/bin/bash
# fix-ghost-displays.sh
# Disable phantom MST clones (e.g., Studio Display "ghost" head).
# Keep the monitor entry with MORE available modes; disable the rest.

set -euo pipefail

# Need hyprctl + jq
command -v hyprctl >/dev/null || exit 0
command -v jq >/dev/null || { echo "[ghost-fix] jq not found"; exit 0; }

# Retry a bit in case monitors aren't ready yet
MON_JSON=""
for i in {1..5}; do
  MON_JSON="$(hyprctl monitors -j 2>/dev/null || true)"
  [ -n "$MON_JSON" ] && [ "$MON_JSON" != "[]" ] && break
  sleep 1
done
[ -z "$MON_JSON" ] || [ "$MON_JSON" = "[]" ] && exit 0

# Some entries might have null serial; group by serial string key
SERIALS=$(echo "$MON_JSON" | jq -r '[.[].serial // "NULL"] | unique[]')

for SERIAL in $SERIALS; do
  MATCHING=$(echo "$MON_JSON" | jq -c --arg S "$SERIAL" '.[] | select((.serial // "NULL") == $S)')
  COUNT=$(echo "$MATCHING" | wc -l)
  if [ "$COUNT" -gt 1 ]; then
    KEEP=$(echo "$MATCHING" | jq -s 'max_by(.availableModes|length)')
    KEEPID=$(echo "$KEEP" | jq -r '.id')
    echo "[ghost-fix] keeping id=$KEEPID serial=$SERIAL"
    # Disable the rest
    for M in $(echo "$MATCHING" | jq -r '.id'); do
      if [ "$M" != "$KEEPID" ]; then
        echo "[ghost-fix] disabling phantom id=$M serial=$SERIAL"
        hyprctl keyword monitor "id:$M,disable" >/dev/null
      fi
    done
  fi
done
EOF

chmod +x "$SCRIPT"

# Ensure autostart exists
mkdir -p "$(dirname "$AUTOSTART")"
touch "$AUTOSTART"

# Append only if not already present (use ~ for portability)
if ! grep -q "fix-ghost-displays.sh" "$AUTOSTART"; then
  echo "exec-once = ~/.config/hypr/fix-ghost-displays.sh" >> "$AUTOSTART"
fi