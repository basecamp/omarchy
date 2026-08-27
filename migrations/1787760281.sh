echo "Install the Hermes CLI wrapper for existing installs"

# Users who removed the preinstalls opted out of the mise wrappers, and Hermes
# is one of them.
[[ -f $HOME/.local/state/omarchy/preinstalls-removed ]] && exit 0

# Hermes Desktop provides its own Hermes; the installer would only stand aside.
omarchy-pkg-present hermes-desktop && exit 0

# Anything already answering to hermes that this installer did not write --
# an official install, a hand-rolled wrapper, even a dangling link -- belongs to
# the user and stays exactly as it is.
wrapper="$HOME/.local/bin/hermes"
if [[ -e $wrapper || -L $wrapper ]]; then
  if [[ -L $wrapper || ! -f $wrapper ]] || ! grep -qxF '# Written by omarchy-install-hermes-cli.' "$wrapper"; then
    exit 0
  fi
fi

omarchy-install-hermes-cli
