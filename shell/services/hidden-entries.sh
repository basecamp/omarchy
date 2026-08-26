#!/bin/bash

desktop_names=${1:-}

scan_dirs=("$HOME/.local/share/applications")

IFS=":" read -ra data_dirs <<< "${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
for data_dir in "${data_dirs[@]}"; do
  scan_dirs+=("$data_dir/applications")
done

scan_dirs+=("$HOME/.nix-profile/share/applications")

# One awk pass over every entry, rather than a bash read loop per line. A
# desktop file is mostly localization -- on a stock install 19,507 of 24,064
# lines are Name[xx]/Comment[xx] -- and bash reads each of those one line at a
# time only to discard it, which cost ~800ms and pinned a core every time the
# desktop-entry watcher fired.
#
# Directories are streamed as D: records ahead of their F: entries so a single
# awk keeps the first-hit-wins dedup across all of them, and both stay NUL
# separated to survive whitespace in paths.
{
  for dir in "${scan_dirs[@]}"; do
    [[ -d $dir ]] || continue
    printf 'D:%s\0' "$dir"
    find "$dir" -type f -name '*.desktop' -printf 'F:%p\0' 2>/dev/null | sort -z
  done
} | desktop_names="$desktop_names" awk -v RS='\0' '
# Read the names from the environment rather than -v: gawk runs escape processing
# over a -v assignment, so a name containing a backslash would arrive mangled and
# silently stop matching.
function desktop_matches(list,   i, j, name_count, entry_count, parts, entries) {
  name_count = split(ENVIRON["desktop_names"], parts, ":")
  entry_count = split(list, entries, ";")

  for (i = 1; i <= name_count; i++) {
    if (parts[i] == "") continue

    for (j = 1; j <= entry_count; j++) {
      if (entries[j] == "") continue
      if (entries[j] == parts[i]) return 1
    }
  }

  return 0
}

/^D:/ { dir = substr($0, 3); next }

{
  file = substr($0, 3)

  id = substr(file, length(dir) + 2)
  sub(/\.desktop$/, "", id)
  gsub("/", "-", id)

  if (id in seen) next
  seen[id] = 1

  # RS is NUL for the file list, and getline honours it here too, so a desktop
  # file arrives as a single record. Split it rather than fighting RS: one read
  # per file beats one per line either way.
  contents = ""
  while ((status = (getline chunk < file)) > 0) contents = contents chunk
  # Read ERRNO before close(), which overwrites it when the file never opened.
  if (status < 0) reason = ERRNO
  close(file)

  if (status < 0) {
    print file ": " reason > "/dev/stderr"
    next
  }

  in_desktop_entry = 0
  hidden = 0
  only_show_in = ""
  not_show_in = ""

  line_count = split(contents, lines, "\n")
  for (i = 1; i <= line_count; i++) {
    line = lines[i]
    sub(/\r$/, "", line)

    if (line ~ /^\[.*\]$/) {
      in_desktop_entry = (line == "[Desktop Entry]")
      continue
    }

    if (!in_desktop_entry) continue

    separator = index(line, "=")
    if (separator == 0) continue

    key = substr(line, 1, separator - 1)
    value = substr(line, separator + 1)

    if (key == "Hidden" || key == "NoDisplay") {
      if (value == "true") hidden = 1
    } else if (key == "OnlyShowIn") {
      only_show_in = value
    } else if (key == "NotShowIn") {
      not_show_in = value
    }
  }

  if (hidden) { print id; next }
  if (only_show_in != "" && !desktop_matches(only_show_in)) { print id; next }
  if (not_show_in != "" && desktop_matches(not_show_in)) { print id; next }
}
'
