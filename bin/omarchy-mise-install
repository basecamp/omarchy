#!/bin/bash

# omarchy:summary=Install a small mise-backed wrapper for a given tool.
# omarchy:args=<package> [command-name [bin-name]]

if [[ -z $1 ]]; then
  echo "Usage: omarchy-mise-install <package> [command-name [bin-name]]"
  exit 1
fi

package=$1
command=${2:-$1}
bin=${3:-$command}

mkdir -p "$HOME/.local/bin"

# These tools install and upgrade on first run, so mise's release cooldown would
# hold a new version back for days after it ships. Exported rather than set on
# the install line alone, so resolving the version to execute agrees with the
# one just installed.
rm -f "$HOME/.local/bin/$command"
cat >"$HOME/.local/bin/$command" <<EOF
#!/bin/bash
export MISE_MINIMUM_RELEASE_AGE=0
mise use -g --quiet "$package" || exit 1
exec mise x "$package" -- "$bin" "\$@"
EOF

chmod +x "$HOME/.local/bin/$command"
