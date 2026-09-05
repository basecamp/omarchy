#!/bin/bash

source "$(dirname "$0")/base-test.sh"

script="$ROOT/shell/services/hidden-entries.sh"

test_home=$(mktemp -d)
system_dir=$(mktemp -d)
local_dir=$(mktemp -d)

cleanup() {
  rm -rf "$test_home" "$system_dir" "$local_dir"
}
trap cleanup EXIT

user_apps="$test_home/.local/share/applications"
mkdir -p "$user_apps" "$system_dir/applications" "$local_dir/applications"

write_entry() {
  local path="$1"
  mkdir -p "$(dirname "$path")"
  cat >"$path"
}

hidden_entries() {
  HOME="$test_home" XDG_DATA_DIRS="$local_dir:$system_dir" bash "$script" "${1:-}"
}

lists_entry() {
  local output
  # Capture first: piping straight into grep would discard the script's exit
  # status, so a crash would read the same as an entry that is simply absent.
  if ! output=$(hidden_entries "${2:-}"); then
    fail "hidden-entries.sh exited non-zero"
  fi

  grep -Fqx -- "$1" <<<"$output"
}

write_entry "$user_apps/plain.desktop" <<'EOF'
[Desktop Entry]
Name=Plain
Exec=plain
EOF

write_entry "$user_apps/hidden.desktop" <<'EOF'
[Desktop Entry]
Name=Hidden
Hidden=true
EOF

write_entry "$user_apps/nodisplay.desktop" <<'EOF'
[Desktop Entry]
Name=NoDisplay
NoDisplay=true
EOF

lists_entry hidden || fail "Hidden=true is hidden"
lists_entry nodisplay || fail "NoDisplay=true is hidden"
lists_entry plain && fail "an entry with neither key stays visible"
pass "hidden-entries reports Hidden and NoDisplay entries"

# The value is compared literally: only "true" hides an entry, so "True" and
# "1" leave it visible rather than silently disappearing from the launcher.
write_entry "$user_apps/capitalized.desktop" <<'EOF'
[Desktop Entry]
Name=Capitalized
Hidden=True
EOF

lists_entry capitalized && fail "Hidden=True (capitalized) does not hide"
pass "hidden-entries only treats a literal true as hidden"

write_entry "$user_apps/only-hyprland.desktop" <<'EOF'
[Desktop Entry]
Name=Only Hyprland
OnlyShowIn=Hyprland;
EOF

write_entry "$user_apps/not-hyprland.desktop" <<'EOF'
[Desktop Entry]
Name=Not Hyprland
NotShowIn=Hyprland;
EOF

lists_entry only-hyprland Hyprland && fail "OnlyShowIn match stays visible"
lists_entry only-hyprland GNOME || fail "OnlyShowIn mismatch is hidden"
lists_entry not-hyprland Hyprland || fail "NotShowIn match is hidden"
lists_entry not-hyprland GNOME && fail "NotShowIn mismatch stays visible"
pass "hidden-entries honours OnlyShowIn and NotShowIn"

# Quickshell passes XDG_CURRENT_DESKTOP, XDG_SESSION_DESKTOP and
# DESKTOP_SESSION joined by ":", so any one of them matching is a match.
lists_entry only-hyprland "GNOME:Hyprland" && fail "a later desktop name still matches OnlyShowIn"
lists_entry not-hyprland "GNOME:Hyprland" || fail "a later desktop name still matches NotShowIn"
pass "hidden-entries matches any of the colon-separated desktop names"

# Keys belong to [Desktop Entry]. An action group carrying Hidden=true must not
# hide the application the actions belong to.
write_entry "$user_apps/action-group.desktop" <<'EOF'
[Desktop Entry]
Name=Action Group
Actions=extra;

[Desktop Action extra]
Name=Extra
Hidden=true
EOF

lists_entry action-group && fail "Hidden in a non-Desktop Entry group is ignored"
pass "hidden-entries only reads the Desktop Entry group"

# Desktop files written on Windows keep their CRLF endings; the trailing \r must
# not turn "true" into something that no longer compares equal.
printf '[Desktop Entry]\r\nName=Crlf\r\nHidden=true\r\n' >"$user_apps/crlf.desktop"

lists_entry crlf || fail "CRLF line endings are handled"
pass "hidden-entries handles CRLF desktop files"

# A user entry shadows a system entry of the same id, so the user's visible copy
# must win over a system copy marked hidden.
write_entry "$user_apps/shadowed.desktop" <<'EOF'
[Desktop Entry]
Name=Shadowed
EOF

write_entry "$system_dir/applications/shadowed.desktop" <<'EOF'
[Desktop Entry]
Name=Shadowed
Hidden=true
EOF

lists_entry shadowed && fail "the first directory scanned wins"
pass "hidden-entries keeps the first entry found for an id"

# Nested entries get their separators folded into the id, matching the desktop
# id Quickshell reports for them.
write_entry "$system_dir/applications/nested/deep.desktop" <<'EOF'
[Desktop Entry]
Name=Deep
Hidden=true
EOF

lists_entry nested-deep || fail "a nested entry uses a dashed id"
pass "hidden-entries derives dashed ids for nested entries"

# Paths are streamed NUL separated, so a directory with a space must survive.
spaced_dir="$system_dir/applications/with space"
write_entry "$spaced_dir/spaced.desktop" <<'EOF'
[Desktop Entry]
Name=Spaced
Hidden=true
EOF

lists_entry "with space-spaced" || fail "a path containing a space is scanned"
pass "hidden-entries scans paths containing spaces"

# Desktop names reach awk through the environment, so a backslash has to arrive
# intact. Passing them via -v would let gawk eat the escape and hide the entry.
write_entry "$system_dir/applications/backslash.desktop" <<'ENTRY'
[Desktop Entry]
Name=Backslash
OnlyShowIn=Foo\Bar;
ENTRY

lists_entry backslash 'Foo\Bar' && fail "a backslash in a desktop name survives transport"
pass "hidden-entries passes desktop names to awk without escape processing"
