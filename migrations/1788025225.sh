echo "Remove privileged files left behind by retired Omarchy installers"

sudoers_dir="${OMARCHY_SUDOERS_DIR:-/etc/sudoers.d}"
systemd_dir="${OMARCHY_SYSTEMD_SYSTEM_DIR:-/etc/systemd/system}"

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
# The installer rewrote this file eight times, and only the last four carry both
# Cmnd_Alias lines, so keying on those would walk past the earlier ones. Instead
# require every active line to be one the installer itself emitted, plus at least
# one line that is unmistakably this grant: its own self-cleanup. One
# hand-written line anywhere in the file and it is not ours to delete.
first_run_sudoers_is_generated() {
  local spec_pattern='^[^[:space:]]+ ALL=\(ALL\) NOPASSWD: (.+)$'
  local marker_pattern='^/bin/rm -f /home/[^/]+/\.local/state/omarchy/first-run\.mode$'
  local line command
  local seen_any=0 seen_marker=0

  while IFS= read -r line; do
    seen_any=1

    case "$line" in
      "Cmnd_Alias SYMLINK_RESOLVED = /usr/bin/ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf")
        continue
        ;;
      "Cmnd_Alias FIRST_RUN_CLEANUP = /bin/rm -f /etc/sudoers.d/first-run" | \
        "Cmnd_Alias FIRST_RUN_CLEANUP = /bin/rm -f /etc/sudoers.d/first-run, /bin/rm -f /etc/sudoers.d/99-omarchy-installer-reboot")
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
    command=${BASH_REMATCH[1]}

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
      seen_marker=1
      continue
    fi

    return 1
  done < <(active_lines sudoers)

  (( seen_any && seen_marker ))
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
  local home_pattern="^(/home/[^/]+|/root)/\\.local/share/omarchy/bin/$binary\$"
  local line word
  local -a words

  while IFS= read -r line; do
    if [[ ! $line =~ $exec_stop_pattern ]]; then
      continue
    fi

    read -ra words <<<"${BASH_REMATCH[1]}"
    if (( ! ${#words[@]} )); then
      continue
    fi

    # systemd reads -, @, +, ! and : ahead of the command as flags, not as part
    # of the path it runs.
    word=${words[0]}
    while [[ $word == [-@+!:]* ]]; do
      word=${word:1}
    done

    if [[ $word =~ $home_pattern || $word == "$HOME/.local/share/omarchy/bin/$binary" ]]; then
      return 0
    fi
  done < <(active_lines systemd)

  return 1
}

# /etc/sudoers.d is 0750 root:root as shipped, and omarchy-migrate runs as the
# logged-in user, so an unelevated [[ -f ]] on a file in there is false whether or
# not the file exists and an unelevated read returns nothing. Both tests and both
# reads have to be elevated or this migration reports success having done nothing.
# One combined probe first, so the common case of neither file being present costs
# a single sudo call rather than one per file.
first_run_sudoers="$sudoers_dir/first-run"
tsui_sudoers="$sudoers_dir/tsui"

if as_root test -e "$first_run_sudoers" -o -e "$tsui_sudoers"; then
  if as_root test -f "$first_run_sudoers" &&
    as_root cat "$first_run_sudoers" | first_run_sudoers_is_generated; then
    as_root rm -f "$first_run_sudoers"
  fi

  if as_root test -f "$tsui_sudoers" &&
    as_root cat "$tsui_sudoers" | tsui_sudoers_is_generated; then
    as_root rm -f "$tsui_sudoers"
  fi
fi

# /etc/systemd/system is 0755, so this one needs no elevation to look at.
plymouth_unit="$systemd_dir/omarchy-plymouth-shutdown.service"
if [[ -f $plymouth_unit ]] && plymouth_unit_runs_from_home <"$plymouth_unit"; then
  # Disable, never stop. Stopping the unit is precisely what runs ExecStop, and
  # ExecStop is the path this migration exists to keep root away from; disabling
  # only drops the multi-user.target symlink.
  as_root systemctl disable omarchy-plymouth-shutdown.service >/dev/null 2>&1 || true
  as_root rm -f "$plymouth_unit"
  # systemd keeps serving the copy it already loaded until it rereads the
  # directory, so without this the unit is still there to run at shutdown.
  as_root systemctl daemon-reload >/dev/null 2>&1 || true
fi
