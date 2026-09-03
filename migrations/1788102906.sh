echo "Repair legacy XCompose and remove vulnerable Omarchy 3 power udev rules"

xcompose="$HOME/.XCompose"
packaged_xcompose="$OMARCHY_PATH/default/xcompose"
legacy_xcompose_pattern='^[[:space:]]*include[[:space:]]+"[^"]*/\.local/share/omarchy/default/xcompose"[[:space:]]*$'

# Omarchy 3 pointed the user's compose file through the checkout compatibility
# link. Preserve their own sequences while moving that include to the packaged
# tree. A failed live restart is harmless: the next graphical login reads the
# repaired file.
if [[ -f $xcompose ]] && grep -Eq "$legacy_xcompose_pattern" "$xcompose"; then
  xcompose_replacement=${packaged_xcompose//\\/\\\\}
  xcompose_replacement=${xcompose_replacement//&/\\&}
  xcompose_replacement=${xcompose_replacement//|/\\|}
  sed -i -E "s|^([[:space:]]*include[[:space:]]+\")[^\"]*/\\.local/share/omarchy/default/xcompose\"[[:space:]]*$|\\1$xcompose_replacement\"|" "$xcompose"
  omarchy-restart-xcompose >/dev/null 2>&1 || true
fi

rules_dir=/etc/udev/rules.d
reload_marker_prefix=/var/lib/omarchy/migrations/1788102906-udev-reload-needed
udev_control=/run/udev/control
install_command=/usr/bin/install
mv_command=/usr/bin/mv
rm_command=/usr/bin/rm
udevadm_command=/usr/bin/udevadm

as_root() {
  if (( EUID == 0 )); then
    "$@"
  else
    sudo "$@"
  fi
}

# Omarchy 3 generated these two rules with an unquoted heredoc, so the installing
# user's $HOME was expanded and the file on disk names that absolute home path.
# udev runs RUN+= as root, and
# ~/.local/share/omarchy is a symlink that same unprivileged user owns: replacing
# it with a tree of their own and provoking a power_supply event runs their code
# as root. Quattro ships the rules as 99-omarchy-*.rules under /usr/bin, but the
# one-shot migration that swept the old filenames was itself dropped, so an
# install that came up through the 3.x line keeps the old file until this
# migration removes it.
#
# Pre-4 layout work normally belongs in the Omarchy 4 upgrade command, but that
# command only runs on a machine still making the crossing, so an install that
# crossed already would never see it. The upgrade command ends by running
# omarchy-migrate, so this covers the installs still to upgrade as well.
#
# Only remove an exact two-line body that one of the retired installers wrote.
# A same-named file with no active vulnerable RUN survives; one that still has
# the vulnerable command but also contains administrator changes is quarantined
# under a non-.rules suffix for review.
rule_runs_from_home() {
  local file="$1" binary="$2"
  local run_pattern='RUN([[:space:]]*\{[^}]*\})?[[:space:]]*(\+|:)?=[[:space:]]*(e)?"([^"]*)"'
  local line logical="" rest command

  while IFS= read -r line || [[ -n $line ]]; do
    # udev tests for a comment before it joins continuations, and skipping one
    # does not end a continuation already under way. Both halves verified with
    # `udevadm verify`: "# disabled \" followed by a bogus key reports the error
    # on line 2, so a comment's own trailing backslash swallows nothing, while
    # 'SUBSYSTEM=="power_supply" \' + "# c" + ', RUN+="..."' reports its style
    # warning on line 1, so the rule spans the comment. Testing the comment after
    # the join would hide a live rule; clearing the pending line here would hide
    # one just as well.
    if [[ $line =~ ^[[:space:]]*# ]]; then
      continue
    fi

    # A trailing backslash continues the rule on the next line.
    if [[ $line == *\\ ]]; then
      logical+=${line%\\}
      continue
    fi

    rest=$logical$line
    logical=""

    while [[ $rest =~ $run_pattern ]]; do
      command=${BASH_REMATCH[4]}
      rest=${rest#*"${BASH_REMATCH[0]}"}

      # This is only the fail-closed detector; wholesale deletion still requires
      # an exact historical body below. Match spacing edits and wrapper arguments
      # conservatively so a modified active rule is never mistaken for a safe one.
      if [[ $command == *"/.local/share/omarchy/bin/$binary"* ]]; then
        return 0
      fi
    done
  done <"$file"

  return 1
}

mark_reload_needed() {
  if ! as_root "$install_command" -Dm644 /dev/null "$reload_needed_marker"; then
    echo "Administrator privileges are required to repair the vulnerable legacy udev rule. Ask an administrator to run omarchy-migrate." >&2
    exit 1
  fi
}

# The retired installers overwrote each file with one of five known two-line
# bodies. Only those exact bodies are safe to delete wholesale. If a vulnerable
# rule has since been edited or extended, preserve it under an inactive name
# rather than taking unrelated rules with it.
rule_is_exact_generated() {
  local file="$1" binary="$2"
  local prefix suffix home expected
  local -a lines

  mapfile -t lines <"$file"
  (( ${#lines[@]} == 2 )) || return 1

  case "$binary" in
    omarchy-powerprofiles-set)
      # Initial userland helper: separate AC/battery units and arguments.
      prefix='SUBSYSTEM=="power_supply", ATTR{type}=="Mains", ATTR{online}=="0", RUN+="/usr/bin/systemd-run --no-block --collect --unit=omarchy-power-profile-battery --property=After=power-profiles-daemon.service '
      suffix='/.local/share/omarchy/bin/omarchy-powerprofiles-set battery"'
      if [[ ${lines[0]} == "$prefix"*"$suffix" ]]; then
        home=${lines[0]#"$prefix"}
        home=${home%"$suffix"}
        expected='SUBSYSTEM=="power_supply", ATTR{type}=="Mains", ATTR{online}=="1", RUN+="/usr/bin/systemd-run --no-block --collect --unit=omarchy-power-profile-ac --property=After=power-profiles-daemon.service '"$home"'/.local/share/omarchy/bin/omarchy-powerprofiles-set ac"'
        [[ $home == /* && $home != *'"'* && ${lines[1]} == "$expected" ]] && return 0
      fi

      # USB-C support: one fixed transient-unit name and no profile argument.
      prefix='SUBSYSTEM=="power_supply", ATTR{type}=="Mains", RUN+="/usr/bin/systemd-run --no-block --collect --unit=omarchy-power-profile --property=After=power-profiles-daemon.service '
      suffix='/.local/share/omarchy/bin/omarchy-powerprofiles-set"'
      if [[ ${lines[0]} == "$prefix"*"$suffix" ]]; then
        home=${lines[0]#"$prefix"}
        home=${home%"$suffix"}
        expected='SUBSYSTEM=="power_supply", ATTR{type}=="USB", RUN+="/usr/bin/systemd-run --no-block --collect --unit=omarchy-power-profile --property=After=power-profiles-daemon.service '"$home"'/.local/share/omarchy/bin/omarchy-powerprofiles-set"'
        [[ $home == /* && $home != *'"'* && ${lines[1]} == "$expected" ]] && return 0
      fi

      # The final Omarchy 3 revision dropped the fixed transient-unit name.
      prefix='SUBSYSTEM=="power_supply", ATTR{type}=="Mains", RUN+="/usr/bin/systemd-run --no-block --collect --property=After=power-profiles-daemon.service '
      suffix='/.local/share/omarchy/bin/omarchy-powerprofiles-set"'
      if [[ ${lines[0]} == "$prefix"*"$suffix" ]]; then
        home=${lines[0]#"$prefix"}
        home=${home%"$suffix"}
        expected='SUBSYSTEM=="power_supply", ATTR{type}=="USB", RUN+="/usr/bin/systemd-run --no-block --collect --property=After=power-profiles-daemon.service '"$home"'/.local/share/omarchy/bin/omarchy-powerprofiles-set"'
        [[ $home == /* && $home != *'"'* && ${lines[1]} == "$expected" ]] && return 0
      fi
      ;;
    omarchy-wifi-powersave)
      # Initial Wi-Fi helper: invoke the userland command directly.
      prefix='SUBSYSTEM=="power_supply", ATTR{type}=="Mains", ATTR{online}=="0", RUN+="'
      suffix='/.local/share/omarchy/bin/omarchy-wifi-powersave on"'
      if [[ ${lines[0]} == "$prefix"*"$suffix" ]]; then
        home=${lines[0]#"$prefix"}
        home=${home%"$suffix"}
        expected='SUBSYSTEM=="power_supply", ATTR{type}=="Mains", ATTR{online}=="1", RUN+="'"$home"'/.local/share/omarchy/bin/omarchy-wifi-powersave off"'
        [[ $home == /* && $home != *'"'* && ${lines[1]} == "$expected" ]] && return 0
      fi

      # Later revision deferred each change through its own transient unit.
      prefix='SUBSYSTEM=="power_supply", ATTR{type}=="Mains", ATTR{online}=="0", RUN+="/usr/bin/systemd-run --no-block --collect --unit=omarchy-wifi-powersave-on '
      suffix='/.local/share/omarchy/bin/omarchy-wifi-powersave on"'
      if [[ ${lines[0]} == "$prefix"*"$suffix" ]]; then
        home=${lines[0]#"$prefix"}
        home=${home%"$suffix"}
        expected='SUBSYSTEM=="power_supply", ATTR{type}=="Mains", ATTR{online}=="1", RUN+="/usr/bin/systemd-run --no-block --collect --unit=omarchy-wifi-powersave-off '"$home"'/.local/share/omarchy/bin/omarchy-wifi-powersave off"'
        [[ $home == /* && $home != *'"'* && ${lines[1]} == "$expected" ]] && return 0
      fi
      ;;
  esac

  return 1
}

finish_pending_reload() {
  # With no control socket there is no running udevd holding the deleted rule;
  # the next daemon start reads the directory from disk. If a daemon is running,
  # a failed reload must keep this migration pending so the in-memory root rule
  # cannot outlive the per-user completion marker.
  if [[ -e $udev_control ]] && ! as_root "$udevadm_command" control --reload 2>/dev/null; then
    echo "Could not reload udev after removing a vulnerable legacy rule. Ask an administrator to run omarchy-migrate." >&2
    exit 1
  fi

  if ! as_root "$rm_command" -f "$reload_needed_marker"; then
    echo "Could not finish the legacy udev-rule repair. Ask an administrator to run omarchy-migrate." >&2
    exit 1
  fi
}

quarantine_rule() {
  local rule_file="$1"
  local backup="$rule_file.omarchy-disabled"
  local suffix=0

  # udev only loads files ending in .rules. Preserve an administrator-modified
  # file byte-for-byte under a suffix udev ignores instead of either deleting
  # their additions or leaving its user-controlled command active as root.
  while [[ -e $backup || -L $backup ]]; do
    ((++suffix))
    backup="$rule_file.omarchy-disabled.$suffix"
  done

  mark_reload_needed
  if ! as_root "$mv_command" --no-clobber -- "$rule_file" "$backup"; then
    echo "Administrator privileges are required to quarantine the vulnerable legacy udev rule. Ask an administrator to run omarchy-migrate." >&2
    exit 1
  fi
  if [[ -e $rule_file || -L $rule_file ]]; then
    echo "Could not quarantine the vulnerable legacy udev rule at $rule_file. Ask an administrator to run omarchy-migrate." >&2
    exit 1
  fi

  finish_pending_reload
  echo "Quarantined the modified legacy rule as $backup so udev cannot execute it. Review the preserved file before restoring any safe custom actions." >&2
}

if [[ -d $rules_dir && ! -x $rules_dir ]]; then
  echo "Could not inspect legacy udev rules under $rules_dir. Ask an administrator to run omarchy-migrate." >&2
  exit 1
fi

for legacy_rule in "99-power-profile.rules:omarchy-powerprofiles-set" "99-wifi-powersave.rules:omarchy-wifi-powersave"; do
  rule_name="${legacy_rule%%:*}"
  rule_file="$rules_dir/$rule_name"
  binary="${legacy_rule##*:}"
  reload_needed_marker="$reload_marker_prefix-$rule_name"

  # The marker is written before removal so a crash cannot lose the need to
  # reload. Only consume it early when the corresponding active file is already
  # gone; another user's concurrent run may still be between those two steps.
  if [[ -e $reload_needed_marker && ! -e $rule_file && ! -L $rule_file ]]; then
    finish_pending_reload
  fi

  if [[ -f $rule_file && ! -r $rule_file ]]; then
    echo "Could not inspect the legacy udev rule at $rule_file. Ask an administrator to run omarchy-migrate." >&2
    exit 1
  fi

  if [[ -f $rule_file ]] && rule_is_exact_generated "$rule_file" "$binary"; then
    mark_reload_needed
    if ! as_root "$rm_command" -f "$rule_file"; then
      echo "Administrator privileges are required to remove the vulnerable legacy udev rule. Ask an administrator to run omarchy-migrate." >&2
      exit 1
    fi

    finish_pending_reload
  elif [[ -f $rule_file ]] && rule_runs_from_home "$rule_file" "$binary"; then
    quarantine_rule "$rule_file"
  fi

  # If an interrupted removal was followed by an administrator installing a
  # safe replacement, reload that replacement before clearing the old marker.
  if [[ -e $reload_needed_marker ]]; then
    finish_pending_reload
  fi
done
