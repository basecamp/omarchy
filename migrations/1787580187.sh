echo "Move this install to the opt-in docker group default (the group is root-equivalent)"

# The docker group grants passwordless root (a container can bind-mount / and
# rewrite the host), so Omarchy no longer puts users in it by default. Bring
# existing installs in line: remove this user from the group if present. The
# change applies after a reboot, so it stays reachable until then. Anyone who
# wants passwordless docker back can opt in, behind a warning, with
# Setup > Security > Sudoless Docker. Reuses the removal command so there is one
# source of truth for the privileged change and its notice; DEFER_REBOOT keeps
# it from prompting mid-update — omarchy-update-restart handles the reboot once
# the whole update has finished.
if id -nG "$USER" | grep -qw docker; then
  OMARCHY_DEFER_REBOOT=1 omarchy-remove-security-sudoless-docker
fi

# The Docker app entry copied into ~/.local/share/applications used to run
# lazydocker directly; it now needs the wrapper that prompts for daemon access
# (or runs directly under sudoless Docker). Refresh just that file.
dest="$HOME/.local/share/applications/Docker.desktop"
if [[ -f $dest ]]; then
  cp "$OMARCHY_PATH/applications/Docker.desktop" "$dest"
fi
