echo "Remove Omarchy 3 power udev rules that run a command out of a user home"

rules_dir="${OMARCHY_UDEV_RULES_DIR:-/etc/udev/rules.d}"

as_root() {
  if (( EUID == 0 )); then
    "$@"
  else
    sudo "$@"
  fi
}

defer_privileged_repair() {
  echo "Cannot remove the legacy privileged udev rule; omarchy-migrate will retry it later." >&2
  if [[ -n ${OMARCHY_MIGRATION_DEFER_FILE:-} && -n ${OMARCHY_MIGRATION_DEFER_TOKEN:-} ]]; then
    printf '%s\n' "$OMARCHY_MIGRATION_DEFER_TOKEN" >"$OMARCHY_MIGRATION_DEFER_FILE"
  fi
  exit 75
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
# Pre-4 layout work normally belongs in bin/omarchy-upgrade-to-quattro, but that
# command only runs on a machine still making the crossing, so an install that
# crossed already would never see it. The upgrade command ends by running
# omarchy-migrate, so this covers the installs still to upgrade as well.
#
# Only remove a file that is actually one of those. A comment is inert to udev,
# so the match keys on an active RUN+= whose command really is the legacy path
# under a home directory for that filename's binary. A rule of the same name that
# a user wrote themselves survives, including one that merely mentions the legacy
# path in a comment, and so does a legacy file already repointed at /usr/bin.
rule_runs_from_home() {
  local file="$1" binary="$2"
  local pattern="^/.+/\\.local/share/omarchy/bin/$binary\$"
  local line logical="" rest command word
  local -a words

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

    while [[ $rest == *'RUN+="'* ]]; do
      rest=${rest#*'RUN+="'}
      command=${rest%%'"'*}
      rest=${rest#*'"'}

      # The legacy rules put the binary first (wifi power save) or last, after a
      # systemd-run invocation (power profile), and some variants passed it an
      # argument. Compare whole words so no substring stands in for the path.
      read -ra words <<<"$command"
      for word in "${words[@]}"; do
        if [[ $word =~ $pattern ]]; then
          return 0
        fi
      done
    done
  done <"$file"

  return 1
}

removed=0

for legacy_rule in "99-power-profile.rules:omarchy-powerprofiles-set" "99-wifi-powersave.rules:omarchy-wifi-powersave"; do
  rule_file="$rules_dir/${legacy_rule%%:*}"

  if [[ -f $rule_file ]] && rule_runs_from_home "$rule_file" "${legacy_rule##*:}"; then
    if ! as_root rm -f "$rule_file"; then
      defer_privileged_repair
    fi
    removed=1
  fi
done

if (( removed )); then
  # Drop the rule from the running udevd too; until it reloads, the rule that was
  # just deleted still fires on the next power_supply event. Best effort the way
  # install/post-install/udev.sh is: a machine with no udevd to talk to has
  # already had the file removed, and the next boot reads the directory fresh.
  as_root udevadm control --reload 2>/dev/null || true
fi
