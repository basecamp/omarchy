#!/bin/bash

desktop_names=${1:-}

declare -A seen_ids

desktop_matches() {
  local list=$1
  local desktop_name
  local entry

  IFS=":" read -ra desktop_parts <<< "$desktop_names"
  IFS=";" read -ra entries <<< "$list"

  for desktop_name in "${desktop_parts[@]}"; do
    [[ -z $desktop_name ]] && continue

    for entry in "${entries[@]}"; do
      [[ -z $entry ]] && continue
      [[ $entry == "$desktop_name" ]] && return 0
    done
  done

  return 1
}

desktop_id_for_file() {
  local dir=$1
  local file=$2
  local rel=${file#"$dir"/}

  rel=${rel%.desktop}
  printf '%s\n' "${rel//\//-}"
}

is_hidden_desktop_file() {
  local file=$1
  local in_desktop_entry=0
  local hidden=false
  local only_show_in=
  local not_show_in=
  local line key value

  while IFS= read -r line || [[ -n $line ]]; do
    line=${line%$'\r'}

    if [[ $line =~ ^\[(.*)\]$ ]]; then
      [[ ${BASH_REMATCH[1]} == "Desktop Entry" ]] && in_desktop_entry=1 || in_desktop_entry=0
      continue
    fi

    (( in_desktop_entry )) || continue
    [[ $line == *=* ]] || continue

    key=${line%%=*}
    value=${line#*=}

    case $key in
      Hidden|NoDisplay)
        [[ $value == "true" ]] && hidden=true
        ;;
      OnlyShowIn)
        only_show_in=$value
        ;;
      NotShowIn)
        not_show_in=$value
        ;;
    esac
  done < "$file"

  [[ $hidden == "true" ]] && return 0
  [[ -n $only_show_in ]] && ! desktop_matches "$only_show_in" && return 0
  [[ -n $not_show_in ]] && desktop_matches "$not_show_in" && return 0

  return 1
}

scan_dir() {
  local dir=$1
  local file id

  [[ -d $dir ]] || return

  while IFS= read -r -d '' file; do
    id=$(desktop_id_for_file "$dir" "$file")
    [[ -n ${seen_ids[$id]+set} ]] && continue
    seen_ids[$id]=1

    if is_hidden_desktop_file "$file"; then
      printf '%s\n' "$id"
    fi
  done < <(find "$dir" -type f -name '*.desktop' -print0 2>/dev/null | sort -z)
}

scan_dir "$HOME/.local/share/applications"

IFS=":" read -ra data_dirs <<< "${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
for data_dir in "${data_dirs[@]}"; do
  scan_dir "$data_dir/applications"
done

scan_dir "$HOME/.nix-profile/share/applications"
