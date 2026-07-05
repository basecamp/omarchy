echo "Remove stale 99-omarchy-nofile.conf systemd drop-ins"

# Earlier Omarchy shipped 99-omarchy-nofile.conf using the key
# 'DefaultLimitNOFILESoft', which is not a valid systemd manager setting.
# systemd rejects it at manager load on every boot:
#   /etc/systemd/system.conf.d/99-omarchy-nofile.conf: Unknown key
#   'DefaultLimitNOFILESoft' in section [Manager], ignoring.
# It was replaced by 20-omarchy-nofile.conf (DefaultLimitNOFILE=soft:hard),
# but the orphaned 99- files are unowned by any package and linger on
# upgraded systems, spamming the journal on every boot. Remove them; the
# 20-omarchy-nofile.conf drop-in already sets the limit correctly.

as_root() {
  if (( EUID == 0 )); then
    "$@"
  else
    sudo "$@"
  fi
}

removed=0
for f in \
  /etc/systemd/system.conf.d/99-omarchy-nofile.conf \
  /etc/systemd/user.conf.d/99-omarchy-nofile.conf; do
  if [[ -f $f ]]; then
    as_root rm -f "$f" && removed=1
  fi
done

if (( removed )); then
  as_root systemctl daemon-reload >/dev/null 2>&1 || true
fi
