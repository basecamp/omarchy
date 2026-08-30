echo "Remove privileged files left behind by retired Omarchy installers"

sudoers_dir="${OMARCHY_SUDOERS_DIR:-/etc/sudoers.d}"
systemd_dir="${OMARCHY_SYSTEMD_SYSTEM_DIR:-/etc/systemd/system}"
machine_marker="${OMARCHY_RETIRED_INSTALLER_ARTIFACTS_MARKER:-/var/lib/omarchy/migrations/1788025225}"
reload_needed_marker="$machine_marker.daemon-reload"

[[ ! -e $machine_marker ]] || exit 0

as_root() {
  if (( EUID == 0 )); then
    "$@"
  else
    sudo "$@"
  fi
}

# Three installers that no longer exist each left a root-owned file behind, and
# nothing in Omarchy has ever removed any of them. Each is judged against what
# the installer that wrote it actually produced, so a file of the same name that
# an administrator wrote themselves is left alone.
#
# Emit the lines a parser would act on: comments and blanks dropped, backslash
# continuations joined, and runs of whitespace collapsed so a reformatted copy
# still compares equal. Reads the body on stdin, because /etc/sudoers.d is 0750
# root:root and the caller has to hand us an elevated read.
#
# Comments are tested before continuations are joined, which is the order every
# consumer here uses: udev's parse_file discards a '#' line without looking at a
# trailing backslash (`udevadm verify` on "# disabled \" plus a bogus key reports
# the error on line 2), sudo's toke.l comment rule consumes to the newline and
# clears its continuation flag, and systemd's config_parse tests the comment
# characters before appending to a continuation. Joining first would let a
# comment ending in a backslash swallow the live line beneath it.
#
# FORMAT is sudoers or systemd. systemd takes ';' as well as '#'. sudo does not
# treat every '#' as a comment: toke.l has INITIAL rules for ^#include and
# ^#includedir, and its comment pattern excludes '#' followed by a digit or
# -digit so those reach the ID token as a numeric uid user spec. Those lines are
# active directives, and a file carrying one must not read as though it held only
# generated lines.
active_lines() {
  local format="$1"
  local comments='#'
  local line logical=""

  [[ $format == "systemd" ]] && comments='#;'

  while IFS= read -r line || [[ -n $line ]]; do
    if [[ $line =~ ^[[:space:]]*[$comments] ]] &&
      ! { [[ $format == "sudoers" ]] && sudoers_hash_is_active "$line"; }; then
      # The two consumers part company here. sudo ends the logical line at a
      # comment and keeps what came before it, so `visudo -cf` reads a spec
      # ending in a backslash, then a comment, then a second spec as two live
      # specs; dropping the pending half would hide an administrator's grant and
      # let this file read as though the installer had written all of it. systemd
      # resumes the continuation instead: `systemd-analyze verify` on "ExecStop=\"
      # + "; c" + a path resolves that path, so the pending half has to stay.
      if [[ $format == "sudoers" ]]; then
        emit_logical "$logical"
        logical=""
      fi
      continue
    fi

    if [[ $line == *\\ ]]; then
      logical+="${line%\\} "
      continue
    fi

    emit_logical "$logical$line"
    logical=""
  done

  # A file whose last line ends in a backslash still carries a live directive for
  # systemd: `systemd-analyze verify` resolves an ExecStop= written that way.
  # udev ignores the dangling line and sudo rejects the file outright, so emitting
  # it costs those two nothing.
  emit_logical "$logical"
}

# One logical line, whitespace collapsed so a reformatted copy still compares
# equal, and nothing at all for a line that held only whitespace.
emit_logical() {
  local -a parts

  read -ra parts <<<"$1"
  if (( ${#parts[@]} )); then
    printf '%s\n' "${parts[*]}"
  fi
}

sudoers_hash_is_active() {
  local line="$1"

  [[ $line =~ ^[[:space:]]*#include[[:blank:]] ]] && return 0
  [[ $line =~ ^[[:space:]]*#includedir[[:blank:]] ]] && return 0
  [[ $line =~ ^[[:space:]]*#-?[0-9] ]] && return 0

  return 1
}

# install/preflight/first-run-mode.sh (2025-08-25 to 2026-05-25) granted the
# installing account passwordless sudo for the rest of the first boot, including
# an unrestricted /usr/bin/systemctl from 2025-10-14 on -- enough to link and
# start a unit of the user's own, which is root. bin/omarchy-first-run was meant
# to delete the grant, but it clears its first-run.mode guard as the very first
# statement and only reaches the removal after eight set -e steps, two of which
# touch the network. Any failure in between leaves the grant on the machine with
# nothing left to retry it.
#
# The installer rewrote this file nine times across two locations -- the last two
# bodies came from install/post-install/first-run-mode.sh, whose cleanup alias
# names /usr/bin/rm as well as /bin/rm -- and only the later ones carry both
# Cmnd_Alias lines, so keying on those would walk past the earlier ones. Instead
# require every active line to be one the installer itself emitted, plus at least
# one line that is unmistakably this grant: its own self-cleanup. One
# hand-written line anywhere in the file and it is not ours to delete.
first_run_sudoers_is_generated() {
  local spec_pattern='^([^[:space:]]+) ALL=\(ALL\) NOPASSWD: (.+)$'
  local marker_pattern='^/bin/rm -f /home/([^/]+)/\.local/state/omarchy/first-run\.mode$'
  local line user command marker_user generated_user=""
  local seen_any=0 seen_marker=0 seen_spec=0

  while IFS= read -r line; do
    seen_any=1

    case "$line" in
      "Cmnd_Alias SYMLINK_RESOLVED = /usr/bin/ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf")
        continue
        ;;
      "Cmnd_Alias FIRST_RUN_CLEANUP = /bin/rm -f /etc/sudoers.d/first-run" | \
        "Cmnd_Alias FIRST_RUN_CLEANUP = /bin/rm -f /etc/sudoers.d/first-run, /bin/rm -f /etc/sudoers.d/99-omarchy-installer-reboot" | \
        "Cmnd_Alias FIRST_RUN_CLEANUP = /usr/bin/rm -f /etc/sudoers.d/first-run, /bin/rm -f /etc/sudoers.d/first-run")
        seen_marker=1
        continue
        ;;
    esac

    # Everything else the installer wrote is a user spec naming the installing
    # account, whose name cannot be assumed here: it may since have been renamed
    # or removed, and a second account runs this migration too.
    if [[ ! $line =~ $spec_pattern ]]; then
      return 1
    fi
    user=${BASH_REMATCH[1]}
    command=${BASH_REMATCH[2]}
    if [[ -n $generated_user && $user != "$generated_user" ]]; then
      return 1
    fi
    generated_user=$user
    seen_spec=1

    case "$command" in
      "/usr/bin/systemctl" | "/usr/bin/ufw" | "/usr/bin/ufw-docker" | \
        "/usr/bin/gtk-update-icon-cache" | "/usr/bin/udevadm" | \
        "/usr/bin/tee /etc/udev/rules.d/*" | "SYMLINK_RESOLVED")
        continue
        ;;
      "FIRST_RUN_CLEANUP" | "/bin/rm -f /etc/sudoers.d/first-run")
        seen_marker=1
        continue
        ;;
    esac

    if [[ $command =~ $marker_pattern ]]; then
      marker_user=${BASH_REMATCH[1]}
      [[ $marker_user == "$generated_user" ]] || return 1
      seen_marker=1
      continue
    fi

    return 1
  done < <(active_lines sudoers)

  (( seen_any && seen_marker && seen_spec ))
}

# bin/omarchy-install-tailscale (2025-08-22 to 2026-02-02) ran
# "echo \"\$USER ALL=(ALL) NOPASSWD: \$(which tsui)\" | sudo tee
# /etc/sudoers.d/tsui" one line after installing tsui by piping a vendor script
# to bash with no sudo at all, so the path it resolved was usually the user's own
# ~/.local/bin. Overwrite that file, run sudo tsui, and you are root. The grant
# goes whatever the path turned out to be: the feature was dropped from Omarchy,
# and unrestricted NOPASSWD on a TUI that can shell out is an escalation from a
# root-owned path too.
tsui_sudoers_is_generated() {
  local spec_pattern='^[^[:space:]]+ ALL=\(ALL\) NOPASSWD: ([^[:space:]]+)$'
  local line command="" count=0

  while IFS= read -r line; do
    count=$(( count + 1 ))
    if (( count > 1 )); then
      return 1
    fi
    if [[ ! $line =~ $spec_pattern ]]; then
      return 1
    fi
    command=${BASH_REMATCH[1]}
  done < <(active_lines sudoers)

  if (( count == 1 )) && [[ ${command##*/} == "tsui" ]]; then
    return 0
  fi

  return 1
}

# install/plymouth.sh wrote this unit for two days (2025-07-05 to 2025-07-07)
# with an unquoted heredoc, so ExecStop names the installing user's home. The
# unit is enabled WantedBy=multi-user.target, so systemd runs that path as uid 0
# on every shutdown, with no hardware event needed to reach it.
plymouth_unit_runs_from_home() {
  local binary="omarchy-plymouth-shutdown-sync"
  local exec_stop_pattern='^ExecStop[[:space:]]*=[[:space:]]*(.*)$'
  local home_pattern="^/.+/\\.local/share/omarchy/bin/$binary\$"
  local line word
  local -a words
  local matched=1

  while IFS= read -r line; do
    if [[ ! $line =~ $exec_stop_pattern ]]; then
      continue
    fi

    read -ra words <<<"${BASH_REMATCH[1]}"
    if (( ! ${#words[@]} )); then
      # An empty assignment resets the list, so nothing named before it still
      # runs. `systemd-analyze verify` reports the missing command for a unit
      # with one ExecStop=, and reports nothing once a bare ExecStop= follows it.
      # An administrator who neutralised the unit this way is left alone.
      matched=1
      continue
    fi

    # systemd reads -, @, +, ! and : ahead of the command as flags, not as part
    # of the path it runs.
    word=${words[0]}
    while [[ $word == [-@+!:]* ]]; do
      word=${word:1}
    done

    if [[ $word =~ $home_pattern ]]; then
      # Non-empty ExecStop= assignments append to the command list. Once a
      # vulnerable command is present it stays live until an empty assignment
      # explicitly resets the list; a later packaged command does not replace it.
      matched=0
    fi
  done < <(active_lines systemd)

  return $matched
}

# /etc/sudoers.d is 0750 root:root as shipped, and omarchy-migrate runs as the
# logged-in user, so an unelevated [[ -f ]] on a file in there is false whether or
# not the file exists and an unelevated read returns nothing. Both tests and both
# reads have to be elevated or this migration reports success having done nothing.
first_run_sudoers="$sudoers_dir/first-run"
tsui_sudoers="$sudoers_dir/tsui"

fail_privileged_repair() {
  echo "Cannot complete the privileged installer-artifact repair. An administrator must run omarchy-migrate to repair this machine." >&2
  exit 1
}

# This is a machine-wide repair with per-user migration markers. A root-owned,
# readable marker lets later non-sudo users finish their own migration run after
# one privileged account has inspected and repaired the machine. Until then,
# the migration fails loudly and remains pending. After an administrator repairs
# the machine, this marker lets every other account complete without using sudo.
if ! as_root true 2>/dev/null; then
  fail_privileged_repair
fi

# Removing a unit and reloading systemd are one repair. Persist the second half
# before removing the file so a failed daemon-reload cannot be forgotten on a
# retry that now sees no unit on disk.
if [[ -e $reload_needed_marker ]]; then
  if ! as_root systemctl daemon-reload >/dev/null 2>&1; then
    fail_privileged_repair
  fi
  if ! as_root rm -f "$reload_needed_marker"; then
    fail_privileged_repair
  fi
fi

inspect_sudoers_file() {
  local file="$1" predicate="$2" kind content

  # Emit an explicit state from the elevated process. A bare `sudo test -f` in
  # an if-condition makes "file missing" indistinguishable from "sudo failed",
  # which could mark a live grant repaired without ever reading it.
  if ! kind=$(as_root bash -c 'if [[ -f $1 ]]; then printf file; elif [[ -e $1 ]]; then printf other; else printf missing; fi' bash "$file"); then
    fail_privileged_repair
  fi

  [[ $kind == "file" ]] || return 0
  if ! content=$(as_root cat "$file"); then
    fail_privileged_repair
  fi

  if "$predicate" <<<"$content"; then
    if ! as_root rm -f "$file"; then
      fail_privileged_repair
    fi
  fi
}

inspect_sudoers_file "$first_run_sudoers" first_run_sudoers_is_generated
inspect_sudoers_file "$tsui_sudoers" tsui_sudoers_is_generated

# /etc/systemd/system is 0755, so this one needs no elevation to look at.
plymouth_unit="$systemd_dir/omarchy-plymouth-shutdown.service"
if [[ -f $plymouth_unit ]] && plymouth_unit_runs_from_home <"$plymouth_unit"; then
  # Disable, never stop. Stopping the unit is precisely what runs ExecStop, and
  # ExecStop is the path this migration exists to keep root away from; disabling
  # only drops the multi-user.target symlink.
  if ! as_root install -Dm644 /dev/null "$reload_needed_marker"; then
    fail_privileged_repair
  fi
  if ! as_root systemctl disable omarchy-plymouth-shutdown.service >/dev/null 2>&1; then
    fail_privileged_repair
  fi
  if ! as_root rm -f "$plymouth_unit"; then
    fail_privileged_repair
  fi
  # systemd keeps serving the copy it already loaded until it rereads the
  # directory, so without this the unit is still there to run at shutdown.
  if ! as_root systemctl daemon-reload >/dev/null 2>&1; then
    fail_privileged_repair
  fi
  if ! as_root rm -f "$reload_needed_marker"; then
    fail_privileged_repair
  fi
fi

if ! as_root install -Dm644 /dev/null "$machine_marker"; then
  fail_privileged_repair
fi
