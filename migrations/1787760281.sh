echo "Install the Hermes CLI wrapper for existing installs"

# Users who removed the preinstalls opted out of the mise wrappers, and Hermes
# is one of them.
[[ -f $HOME/.local/state/omarchy/preinstalls-removed ]] && exit 0

# Hermes Desktop provides its own Hermes. The installer stands aside for it,
# removing the mise copy and the Omarchy wrapper an earlier install may have
# left beside the app. It also reports when the app has not finished setting
# Hermes up, which is the app's to finish, not this migration's to fail on.
if omarchy-pkg-present hermes-desktop; then
  omarchy-install-hermes-cli || true
  exit 0
fi

# Anything already answering to hermes that this installer did not write --
# an official install, a hand-rolled wrapper, even a dangling link -- belongs to
# the user and stays exactly as it is. The installer is asked rather than
# matched against here, so there is one answer to who owns that wrapper.
wrapper="$HOME/.local/bin/hermes"
if [[ -e $wrapper || -L $wrapper ]] && ! omarchy-install-hermes-cli --owns; then
  exit 0
fi

omarchy-install-hermes-cli
