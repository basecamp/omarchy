#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

require_command xdg-user-dir

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
mkdir -p "$mock_bin"

for command in xdg-user-dirs-update xdg-settings xdg-mime; do
  printf '#!/bin/bash\nexit 0\n' >"$mock_bin/$command"
done
chmod +x "$mock_bin"/*

# Provisioning prepends $OMARCHY_PATH/bin, which shadows a mock for anything
# Omarchy ships, so the install suite is stubbed out at its path instead. The
# real one rethemes the session it runs in: hyprctl reload against the live
# compositor, gsettings against the live desktop, and a global Node install.
mkdir -p "$test_tmp/install/user"
: >"$test_tmp/install/user/all.sh"

# XDG_CONFIG_HOME is cleared so xdg-user-dir reads the fixture's own
# user-dirs.dirs rather than whatever the developer running the suite has.
provision() {
  env -u XDG_CONFIG_HOME HOME="$1" PATH="$mock_bin:$ROOT/bin:$PATH" \
    OMARCHY_PATH="$ROOT" OMARCHY_INSTALL="$test_tmp/install" \
    bash "$ROOT/bin/omarchy-provision-user" >/dev/null
}

bookmarked() {
  grep -qxF "file://$2 $3" "$1/.config/gtk-3.0/bookmarks"
}

default_home="$test_tmp/home"
mkdir -p "$default_home"
provision "$default_home" || fail "omarchy-provision-user finishes"

for skill in omarchy diagnose-crash; do
  link="$default_home/.gemini/config/skills/$skill"
  [[ -L $link && $(readlink "$link") == "$ROOT/default/agents/skills/$skill" ]] ||
    fail "omarchy-provision-user provisions the $skill skill for Antigravity"
done

pass "omarchy-provision-user provisions Antigravity skills"

# With nothing configured, xdg-user-dir reports $HOME for every directory, and
# the default names are what provisioning has to fall back to.
for dir in Downloads Pictures Videos; do
  [[ -d "$default_home/$dir" ]] ||
    fail "omarchy-provision-user creates ~/$dir when nothing is configured"
  bookmarked "$default_home" "$default_home/$dir" "$dir" ||
    fail "omarchy-provision-user bookmarks ~/$dir when nothing is configured"
done

bookmarked "$default_home" "$default_home/Projects" Projects ||
  fail "omarchy-provision-user bookmarks ~/Projects"

pass "omarchy-provision-user uses the default directories when none are configured"

# A user who moved their XDG directories keeps them: provisioning must not
# create an empty duplicate under the default name and bookmark that instead.
custom_home="$test_tmp/custom"
mkdir -p "$custom_home/.config" "$custom_home/inbox" "$custom_home/media/fotos" "$custom_home/media/clips"
cat >"$custom_home/.config/user-dirs.dirs" <<'DIRS'
XDG_DOWNLOAD_DIR="$HOME/inbox"
XDG_PICTURES_DIR="$HOME/media/fotos"
XDG_VIDEOS_DIR="$HOME/media/clips"
DIRS

provision "$custom_home" || fail "omarchy-provision-user finishes with customized XDG directories"

for dir in Downloads Pictures Videos; do
  [[ -e "$custom_home/$dir" ]] &&
    fail "omarchy-provision-user leaves a duplicate ~/$dir beside the configured directory"
done

pass "omarchy-provision-user creates no duplicates beside customized XDG directories"

bookmarked "$custom_home" "$custom_home/inbox" Downloads ||
  fail "omarchy-provision-user bookmarks the configured download directory"
bookmarked "$custom_home" "$custom_home/media/fotos" Pictures ||
  fail "omarchy-provision-user bookmarks the configured picture directory"
bookmarked "$custom_home" "$custom_home/media/clips" Videos ||
  fail "omarchy-provision-user bookmarks the configured video directory"

pass "omarchy-provision-user bookmarks the configured XDG directories"
