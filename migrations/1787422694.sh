echo "Set the lazygit editor to match the Omarchy default editor"

editor="nvim"
if [[ -f "$HOME/.local/state/omarchy/defaults/editor" ]]; then
  read -r editor <"$HOME/.local/state/omarchy/defaults/editor" || editor="nvim"
fi

config="$HOME/.config/lazygit/config.yml"

# Only keys directly inside the top-level os mapping may be touched; lazygit
# configs nest same-named keys elsewhere (e.g. keybinding.universal.edit) and
# whole-document matches would corrupt them. The os block's own indentation is
# discovered from the document instead of assumed, so four-space configs stay
# consistent.
os_present=0
os_child="  " # indentation used by the os block's children
preset_indent="" # set when the block already carries an editPreset child

scan_os_block() {
  local raw
  raw=$(awk '
    BEGIN { os_seen = 0; in_os = 0; child = ""; preset = "" }
    !os_seen && /^os:/ { os_seen = 1; in_os = 1; next }
    # Comments take no part in indentation: they neither end the block nor
    # establish its child indent.
    in_os && /^[[:space:]]*#/ { next }
    in_os && /^[^[:space:]]/ { exit }
    in_os && $0 ~ /^[[:space:]]*$/ { next }
    in_os {
      match($0, /^[[:space:]]*/)
      indent = substr($0, 1, RLENGTH)
      if (child == "") child = indent
      if (preset == "" && indent == child && substr($0, RLENGTH + 1) ~ /^editPreset:/) preset = indent
    }
    END { print (os_seen ? "y" : "n") "|" child "|" preset }
  ' "$config")
  os_present=${raw%%|*}
  raw=${raw#*|}
  os_child=${raw%%|*}
  preset_indent=${raw#*|}
  [[ -n $os_child ]] || os_child="  "
}

# Rewrite a one-line flow-style os mapping (os: {a: b, c: d}) into block style
# so an indented child can be inserted beneath it. Mappings with nested braces
# or quotes are left untouched rather than rewritten incorrectly; their
# editPreset simply keeps whatever value it already had.
# Swap a single known os: line for its rewritten form, preserving mode.
replace_os_line() {
  local old="$1" new="$2"

  if awk -v flow="$old" -v block="$new"$'\n' '
    $0 == flow { printf "%s", block; next }
    { print }
  ' "$config" >"$config.tmp"; then
    # The redirect creates the temp file from the umask, so restoring the
    # original mode keeps e.g. a private 0600 config private after the swap.
    chmod --reference="$config" "$config.tmp"
    mv "$config.tmp" "$config"
  else
    rm -f "$config.tmp"
  fi
}

normalize_os_mapping() {
  local line inner pair block="" comment="" parts

  line=$(grep -m1 "^os:[[:space:]]*{" "$config" 2> /dev/null) || return 0
  # Capture the members AND the trailing YAML comment separately: the comment
  # is user-authored content and must ride onto the rebuilt os: header. Each
  # segment is wrapped in brackets so a matched-but-empty piece differs from a
  # failed match.
  parts=$(sed -n "s/^os:[[:space:]]*{\(.*\)}[[:space:]]*\(#.*\)\?\$/[\\1]\\n[\\2]/p" <<<"$line")
  inner=$(sed -n "1p" <<<"$parts")
  comment=$(sed -n "2p" <<<"$parts")
  if [[ $inner != "["*"]" || $comment != "["*"]" ]]; then
    return 0
  fi
  inner=${inner#"["}; inner=${inner%"]"}
  comment=${comment#"["}; comment=${comment%"]"}
  [[ $inner != *[\{\}\[\]\"\']* ]] || return 0

  local IFS=,
  for pair in $inner; do
    pair="${pair#"${pair%%[![:space:]]*}"}"
    pair="${pair%"${pair##*[![:space:]]}"}"
    [[ -n $pair ]] && block+="  $pair"$'\n'
  done

  local os_header="os:"
  if [[ -n $comment ]]; then
    os_header="os: $comment"
  fi

  replace_os_line "$line" "$os_header"$'\n'"${block%$'\n'}"
}

# A null value carries no settings of its own, so it can become an empty
# mapping with any trailing comment moved onto the header. Other scalars and
# sequences are not mappings and are left untouched.
normalize_null_os_mapping() {
  local line payload token comment=""

  line=$(grep -m1 -E "^os:[[:space:]]*([nN][uU][lL][lL]|~)([[:space:]]+#.*)?$" "$config") || return 0
  payload=$(sed -n "s/^os:[[:space:]]*//p" <<<"$line")
  token=${payload%%[[:space:]]*}
  case $token in
  null | Null | NULL | "~") ;;
  *) return 0 ;;
  esac
  if [[ $payload == *"#"* ]]; then
    comment="#${payload#*#}"
  fi

  local os_header="os:"
  if [[ -n $comment ]]; then
    os_header="os: $comment"
  fi

  replace_os_line "$line" "$os_header"
}

write_preset() {
  local value="$1" payload=""

  # Only a bare block header (optionally commented) may take an appended
  # child. Unnormalizable flow mappings, scalars, and sequences stay exactly
  # as the user wrote them.
  payload=$(grep -m1 "^os:" "$config" 2> /dev/null) || payload=""
  payload=$(sed -n "s/^os:[[:space:]]*//p" <<<"$payload")
  case $payload in
  "" | "#"*) ;;
  *) return 0 ;;
  esac

  mkdir -p "$(dirname "$config")"
  if [[ $os_present == "y" ]]; then
    sed -i "/^os:/a\\${os_child}editPreset: $value" "$config"
  else
    printf "\nos:\n%seditPreset: %s\n" "$os_child" "$value" >>"$config"
  fi
}

if [[ -f $config ]] && grep -q "^os:" "$config"; then
  normalize_os_mapping
  normalize_null_os_mapping
  scan_os_block
fi

case "$editor" in
helix) preset="helix" ;;
code) preset="vscode" ;;
zed | zeditor) preset="zed" ;;
sublime_text) preset="sublime" ;;
nvim | vim | emacs) preset="$editor" ;;
*)
  # No lazygit preset exists for this editor (Cursor). Leave an explicit
  # choice alone; otherwise seed nvim so lazygit stops falling back to vim.
  preset=""
  ;;
esac

# Replace the direct os-child editPreset with a new value, scoped strictly to
# the top-level os mapping. The old line's trailing comment is carried over as
# data: it never passes through sed replacement syntax, so &, |, and backslash
# in user comments are preserved verbatim.
swap_os_preset() {
  local indent="$1" value="$2"

  if awk -v ind="$indent" -v val="$value" '
    BEGIN { in_os = 0; done = 0 }
    !in_os && /^os:/ { in_os = 1; print; next }
    in_os && /^[[:space:]]*#/ { print; next }
    in_os && /^[^[:space:]]/ { done = 1 }
    in_os && !done && index($0, ind "editPreset:") == 1 {
      hash = index($0, "#")
      if (hash > 0) {
        print ind "editPreset: " val " " substr($0, hash)
      } else {
        print ind "editPreset: " val
      }
      done = 1
      next
    }
    { print }
  ' "$config" >"$config.tmp"; then
    # The redirect creates the temp file from the umask, so restoring the
    # original mode keeps e.g. a private 0600 config private after the swap.
    chmod --reference="$config" "$config.tmp"
    mv "$config.tmp" "$config"
  else
    rm -f "$config.tmp"
  fi
}

if [[ -n $preset ]]; then
  if [[ -n $preset_indent ]]; then
    swap_os_preset "$preset_indent" "$preset"
  else
    write_preset "$preset"
  fi
elif [[ -z $preset_indent ]]; then
  write_preset nvim
fi
