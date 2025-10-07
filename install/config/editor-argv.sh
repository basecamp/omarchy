#!/bin/bash
# Configure VSCode-based editors to use gnome-libsecret as the password store
# Usage: editor-argv.sh <editor-name>
# Example: editor-argv.sh vscode

set -e

EDITOR_NAME="${1:-vscode}"
EDITOR_DIR="${EDITOR_NAME,,}"  # Convert to lowercase
ARGV_FILE="$HOME/.${EDITOR_DIR}/argv.json"

# Create the editor directory if it doesn't exist
mkdir -p "$HOME/.${EDITOR_DIR}"

# Check if file exists and already has password-store configured
if [[ -f "$ARGV_FILE" ]] && grep -q '"password-store"[[:space:]]*:[[:space:]]*"gnome-libsecret"' "$ARGV_FILE"; then
  echo "${EDITOR_NAME} password-store already configured correctly"
  exit 0
fi

# If file exists but doesn't have password-store, add it using sed
if [[ -f "$ARGV_FILE" ]]; then
  # Add comma to the last property before closing brace (if it doesn't already have one)
  sed -i '/^[[:space:]]*}[[:space:]]*$/!{/[^,]$/s/$/,/}' "$ARGV_FILE"

  # Add the password-store setting before the closing brace
  sed -i '/^[[:space:]]*}[[:space:]]*$/i\
\
	// Omarchy default password store\
	"password-store": "gnome-libsecret"' "$ARGV_FILE"

  echo "Added password-store setting to existing ${EDITOR_NAME} argv.json"
  exit 0
fi

# Create new argv.json with password-store setting
cat >"$ARGV_FILE" <<'EOF'
{
	// Omarchy default password store
	"password-store": "gnome-libsecret"
}
EOF

echo "Configured ${EDITOR_NAME} to use gnome-libsecret password store"
