# cups-browsed manages queues through CUPS and does not need Unix root. Give
# only its locked service account passwordless CUPS administration; interactive
# users go through cups-pk-helper and Polkit instead.
cups_files_conf="${OMARCHY_CUPS_FILES_CONF:-/etc/cups/cups-files.conf}"
cups_browsed_sysusers_conf="${OMARCHY_CUPS_BROWSED_SYSUSERS_CONF:-/etc/sysusers.d/omarchy-cups-browsed.conf}"

if [[ -f $cups_browsed_sysusers_conf ]]; then
  systemd-sysusers "$cups_browsed_sysusers_conf"
fi

if [[ -L $cups_files_conf ]]; then
  echo "Refusing to rewrite symlinked CUPS authorization config: $cups_files_conf" >&2
  false
elif [[ -f $cups_files_conf ]]; then
  staged_conf=$(mktemp --tmpdir="${cups_files_conf%/*}" ".${cups_files_conf##*/}.XXXXXX")

  if ! awk '
    NR == FNR {
      if ($1 == "SystemGroup") {
        for (i = 2; i <= NF; i++) {
          if (substr($i, 1, 1) == "#")
            break
          if ($i != "wheel" && !seen_group[$i]) {
            system_groups[++system_group_count] = $i
            seen_group[$i] = 1
          }
        }
      }
      next
    }

    $1 == "SystemGroup" {
      comment_start = index($0, "#")
      if (!wrote_system_group) {
        printf "SystemGroup"
        for (i = 1; i <= system_group_count; i++)
          printf " %s", system_groups[i]
        if (!seen_group["cups-browsed"])
          printf " cups-browsed"
        if (comment_start)
          printf " %s", substr($0, comment_start)
        print ""
        wrote_system_group = 1
      } else if (comment_start) {
        print substr($0, comment_start)
      }
      next
    }

    $1 == "PeerCred" {
      comment_start = index($0, "#")
      if (!saw_peer_cred) {
        printf "PeerCred on"
        if (comment_start)
          printf " %s", substr($0, comment_start)
        print ""
      } else if (comment_start) {
        print substr($0, comment_start)
      }
      saw_peer_cred = 1
      next
    }

    { print }

    END {
      if (!wrote_system_group)
        print "SystemGroup sys root cups-browsed"
      if (!saw_peer_cred)
        print "PeerCred on"
    }
  ' "$cups_files_conf" "$cups_files_conf" >"$staged_conf"; then
    rm -f "$staged_conf"
    false
  fi

  if ! chmod --reference="$cups_files_conf" "$staged_conf" ||
    ! chown --reference="$cups_files_conf" "$staged_conf" ||
    ! mv -f "$staged_conf" "$cups_files_conf"; then
    rm -f "$staged_conf"
    false
  fi
fi
