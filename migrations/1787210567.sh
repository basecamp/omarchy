echo "Let the Omarchy repository outrank Arch's so its packages can ship ahead of extra"

# Ordering is the whole mechanism. pacman stops at the first repository carrying
# a name and never compares versions across the rest, so with [omarchy] below
# [extra] an Omarchy build of a package Arch also ships is simply unreachable:
# -Syu reports nothing to do and -S installs Arch's.
#
# The section is moved in place rather than by copying the shipped template over
# the file, because omarchy-refresh-pacman does that and it also resets the
# channel and discards whatever the user added to /etc/pacman.conf.

conf="${OMARCHY_PACMAN_CONF:-/etc/pacman.conf}"
marker="${OMARCHY_PACMAN_ORDER_MARKER:-/var/lib/omarchy/migrations/1787210567}"

# Machine-wide work recorded per user, so a second account would run it again and
# undo an administrator who deliberately put the ordering back.
[[ -e $marker ]] && exit 0
[[ -f $conf ]] || exit 0

# awk rather than grep, which reports no match as a failure and would take the
# whole migration run down with it under the runner's errexit.
omarchy_line=$(awk '/^\[omarchy\]/ { print NR; exit }' "$conf")
extra_line=$(awk '/^\[extra\]/ { print NR; exit }' "$conf")

# Nothing to do for a config that predates the Omarchy repository, and nothing to
# do once the section already leads.
if [[ -z $omarchy_line || -z $extra_line ]] || ((omarchy_line < extra_line)); then
  sudo install -Dm644 /dev/null "$marker"
  exit 0
fi

# The section runs to the next header, a blank line, or the end of the file.
block=$(awk '
  /^\[omarchy\]/ { collecting = 1; print; next }
  collecting && (/^\[/ || /^[[:space:]]*$/) { collecting = 0 }
  collecting { print }
' "$conf")

reordered=$(awk -v block="$block" '
  /^\[omarchy\]/ { dropping = 1; next }
  dropping && /^\[/ { dropping = 0 }
  dropping && /^[[:space:]]*$/ { dropping = 0; next }
  dropping { next }
  /^\[extra\]/ && !inserted { print block; print ""; inserted = 1 }
  { print }
' "$conf")

# A reorder moves lines and changes nothing else, so the two files have to hold
# the same content. Anything else means the awk above misread this config, and a
# mangled pacman.conf is not worth the ordering.
if ! diff -q <(grep -v '^[[:space:]]*$' "$conf" | sort) \
             <(grep -v '^[[:space:]]*$' <<<"$reordered" | sort) >/dev/null; then
  echo "Leaving $conf alone: reordering it would have changed more than the order"
  exit 0
fi

sudo cp -f "$conf" "$conf.bak-repo-order"
printf '%s\n' "$reordered" | sudo tee "$conf" >/dev/null
sudo chmod 644 "$conf"
sudo install -Dm644 /dev/null "$marker"
