echo "Switch to the herdr-git package that follows upstream Herdr"

# herdr was built from an Omarchy fork whose only divergence was replaying an
# agent's CLI options on resume, work upstream declined twice. herdr-git drops
# the fork and follows upstream master, which renames the package.

if omarchy-pkg-present herdr-git; then
  exit 0
fi

# One transaction rather than a drop and an add: the session is usually running
# inside herdr, and an install that failed between the two would leave it with
# no terminal. --noconfirm answers "no" to the conflict herdr-git raises against
# the installed herdr, so --ask 4 preselects removing it.
sudo pacman -S --noconfirm --ask 4 --needed herdr-git

# pacman does not always exit non-zero when a package fails to install, and a
# migration that marked itself done would leave this machine on the fork for good.
omarchy-pkg-present herdr-git
