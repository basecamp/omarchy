echo "Import WiFi networks from iwd into NetworkManager"

# The quattro upgrade retired iwd/systemd-networkd in favor of NetworkManager
# but did not carry over previously-saved WiFi networks, so they appear
# "forgotten". Their credentials still live in iwd's store; re-create them as
# NetworkManager profiles. Idempotent and best-effort: it never aborts the
# migration run and skips networks NetworkManager already knows.

as_root() {
  if (( EUID == 0 )); then
    "$@"
  else
    sudo "$@"
  fi
}

# Overridable so the test suite can point at a temp store.
IWD_DIR="${OMARCHY_IWD_DIR:-/var/lib/iwd}"
NM_DIR="${OMARCHY_NM_DIR:-/etc/NetworkManager/system-connections}"

# Nothing to do unless iwd left saved networks behind and NetworkManager is
# the active backend to import them into.
command -v nmcli >/dev/null 2>&1 || exit 0
command -v uuidgen >/dev/null 2>&1 || exit 0
systemctl is-active --quiet NetworkManager.service 2>/dev/null || exit 0
as_root test -d "$IWD_DIR" || exit 0

# iwd stores the SSID verbatim in the filename, or as '=' followed by the hex
# of the SSID when it contains unusual bytes. Decode both forms.
decode_ssid() {
  local name=$1
  if [[ $name == =* ]]; then
    printf '%b' "$(sed 's/../\\x&/g' <<<"${name#=}")"
  else
    printf '%s' "$name"
  fi
}

# True when NetworkManager already has a wifi profile for this SSID.
nm_has_ssid() {
  local want=$1 uuid ssid
  while read -r uuid; do
    [[ -n $uuid ]] || continue
    ssid=$(nmcli -t -g 802-11-wireless.ssid connection show "$uuid" 2>/dev/null || true)
    [[ $ssid == "$want" ]] && return 0
  done < <(nmcli -t -f UUID,TYPE connection show 2>/dev/null | awk -F: '$2=="802-11-wireless"{print $1}')
  return 1
}

# Write a keyfile profile straight to NetworkManager's store rather than
# shelling out to `nmcli connection add`. Secrets passed to nmcli would sit in
# argv and be readable from /proc by any local user for the life of the call;
# here the profile travels over stdin into a root-owned 0600 file instead.
write_profile() {
  local ssid=$1 hidden=$2 secret=$3 file=$4
  {
    printf '[connection]\nid=%s\nuuid=%s\ntype=wifi\n\n' "$ssid" "$(uuidgen)"
    printf '[wifi]\nmode=infrastructure\nssid=%s\n' "$ssid"
    [[ $hidden == yes ]] && printf 'hidden=true\n'
    printf '\n'
    if [[ -n $secret ]]; then
      printf '[wifi-security]\nkey-mgmt=wpa-psk\npsk=%s\n\n' "$secret"
    fi
    printf '[ipv4]\nmethod=auto\n\n[ipv6]\nmethod=auto\n'
  } | as_root install -m 600 /dev/stdin "$file"
}

imported=0

while IFS= read -r file; do
  [[ -n $file ]] || continue
  base=${file##*/}
  ext=${base##*.}
  ssid=$(decode_ssid "${base%.*}")

  # A newline in the id/ssid would forge extra keyfile lines; '/' would escape
  # the profile directory. Neither is a real SSID we can round-trip safely.
  [[ $ssid == *$'\n'* || $ssid == */* || -z $ssid ]] && continue
  nm_has_ssid "$ssid" && continue

  contents=$(as_root cat "$file" 2>/dev/null || true)
  hidden=no
  grep -qi '^Hidden=true' <<<"$contents" && hidden=yes

  secret=""
  case "$ext" in
    open)
      : # no secret; open network
      ;;
    psk)
      secret=$(sed -n 's/^Passphrase=//p' <<<"$contents" | head -n1)
      [[ -n $secret ]] || secret=$(sed -n 's/^PreSharedKey=//p' <<<"$contents" | head -n1)
      [[ -n $secret ]] || continue
      ;;
    *)
      continue # 8021x/enterprise carry certs/identities; leave for manual re-add
      ;;
  esac

  write_profile "$ssid" "$hidden" "$secret" "$NM_DIR/$ssid.nmconnection" \
    && ((imported++)) || true
done < <(as_root bash -c 'ls -1 "$0"/*.psk "$0"/*.open 2>/dev/null' "$IWD_DIR")

if (( imported > 0 )); then
  as_root nmcli connection reload >/dev/null 2>&1 || true
  echo "Imported $imported WiFi network(s) previously saved by iwd."
fi
exit 0
