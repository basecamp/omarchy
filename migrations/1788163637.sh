echo "Upgrade Omarchy-managed SSH hardening to a universally key-only policy"

legacy_config=/etc/ssh/sshd_config.d/10-omarchy-hardening.conf
key_only_config=/etc/ssh/sshd_config.d/00-omarchy-key-only.conf
main_config=/etc/ssh/sshd_config
dropin_dir=/etc/ssh/sshd_config.d
target_uid=""
target_name=""
target_home=""
authorized_keys=""

as_root() { if ((EUID == 0)); then "$@"; else sudo "$@"; fi; }

service_affected() {
  systemctl is-active --quiet sshd.service 2>/dev/null || systemctl is-enabled --quiet sshd.service 2>/dev/null
}

disable_affected() {
  service_affected || return 0
  as_root systemctl disable --now sshd.service || {
    echo "Could not disable SSH after key-only policy verification failed; rerun omarchy-migrate with administrator privileges." >&2
    exit 1
  }
  echo "Disabled sshd because a universally usable key-only policy could not be proven. Run omarchy-setup-security-sshd to repair it."
}

legacy_is_omarchy_managed() {
  [[ -f $legacy_config && ! -L $legacy_config ]] || return 1
  [[ $(awk '!/^[[:space:]]*(#|$)/ { print }' "$legacy_config") == $'PasswordAuthentication no\nKbdInteractiveAuthentication no' ]]
}

has_usable_key() {
  local line home_mode ssh_mode key_mode home_owner ssh_owner key_owner canonical
  target_uid=$(/usr/bin/id -u) || return 1
  [[ $target_uid =~ ^[0-9]+$ ]] || return 1
  local entry entry_uid
  entry=$(/usr/bin/getent passwd "$target_uid") || return 1
  IFS=: read -r target_name _ entry_uid _ _ target_home _ <<<"$entry"
  [[ $entry_uid == "$target_uid" && $target_name =~ ^[a-z_][a-z0-9_-]{0,31}$ && $target_home == /* ]] || return 1
  canonical=$(/usr/bin/realpath -e -- "$target_home" 2>/dev/null) || return 1
  [[ $canonical == "$target_home" && ! -L $target_home ]] || return 1
  authorized_keys="$target_home/.ssh/authorized_keys"
  [[ -d $target_home/.ssh && ! -L $target_home/.ssh && -f $authorized_keys && ! -L $authorized_keys && -r $authorized_keys ]] || return 1
  [[ $(/usr/bin/realpath -e -- "$target_home/.ssh") == "$target_home/.ssh" &&
    $(/usr/bin/realpath -e -- "$authorized_keys") == "$authorized_keys" ]] || return 1
  home_mode=$(/usr/bin/stat -c '%a' "$target_home") || return 1
  ssh_mode=$(/usr/bin/stat -c '%a' "$target_home/.ssh") || return 1
  key_mode=$(/usr/bin/stat -c '%a' "$authorized_keys") || return 1
  home_owner=$(/usr/bin/stat -c '%u' "$target_home") || return 1
  ssh_owner=$(/usr/bin/stat -c '%u' "$target_home/.ssh") || return 1
  key_owner=$(/usr/bin/stat -c '%u' "$authorized_keys") || return 1
  [[ $home_owner == 0 || $home_owner == "$target_uid" ]] &&
    [[ $ssh_owner == 0 || $ssh_owner == "$target_uid" ]] &&
    [[ $key_owner == 0 || $key_owner == "$target_uid" ]] || return 1
  ! ((8#$home_mode & 022)) && ! ((8#$ssh_mode & 022)) && ! ((8#$key_mode & 022)) || return 1
  while IFS= read -r line || [[ -n $line ]]; do
    [[ $line =~ ^[[:space:]]*(#|$) ]] && continue
    ssh-keygen -lf /dev/stdin <<<"$line" >/dev/null 2>&1 && return 0
  done <"$authorized_keys"
  return 1
}

precedence_is_provable() {
  as_root awk '
    { line=$0; sub(/[[:space:]]*#.*/, "", line); sub(/^[[:space:]]+/, "", line) }
    line !~ /^[[:space:]]*$/ {
      split(line,f,/[[:space:]]+/); key=tolower(f[1])
      if (!included) {
        if (key=="include" && line ~ /^[Ii][Nn][Cc][Ll][Uu][Dd][Ee][[:space:]]+\/etc\/ssh\/sshd_config\.d\/\*\.conf[[:space:]]*$/) included=1
        else if (key=="include" || key=="match" || key=="passwordauthentication" || key=="kbdinteractiveauthentication" || key=="authenticationmethods" || key=="pubkeyauthentication" || key=="authorizedkeysfile") exit 1
      }
    }
    END { if (!included) exit 1 }
  ' "$main_config" || return 1
  local entry
  while IFS= read -r entry; do
    [[ $entry == "${key_only_config##*/}" ]] && continue
    [[ $entry > "${key_only_config##*/}" ]] || return 1
  done < <(as_root find "$dropin_dir" -mindepth 1 -maxdepth 1 -name '*.conf' -printf '%f\n' | LC_ALL=C sort)
}

effective_is_key_only() {
  local dump matched
  dump=$(as_root sshd -T) || return 1
  matched=$(as_root sshd -T -C "user=$target_name,host=localhost,addr=127.0.0.1,laddr=127.0.0.1,lport=22") || return 1
  for dump in "$dump" "$matched"; do
    grep -qixF 'passwordauthentication no' <<<"$dump" &&
    grep -qixF 'kbdinteractiveauthentication no' <<<"$dump" &&
    grep -qixF 'authenticationmethods publickey' <<<"$dump" &&
    grep -qixF 'pubkeyauthentication yes' <<<"$dump" &&
      grep -qixF 'authorizedkeysfile .ssh/authorized_keys' <<<"$dump" || return 1
  done
}

# Only repair the exact two-directive file emitted by old Omarchy. Preserve an
# administrator-authored file at either name byte-for-byte.
if [[ -e $legacy_config || -L $legacy_config ]]; then
  legacy_is_omarchy_managed || exit 0
elif [[ ! -e $key_only_config && ! -L $key_only_config ]]; then
  exit 0
fi
if [[ -e $key_only_config || -L $key_only_config ]] && [[ ! -f $key_only_config || -L $key_only_config ]]; then
  disable_affected
  exit 0
fi

has_usable_key && precedence_is_provable || {
  disable_affected
  exit 0
}

created=0
if [[ ! -e $key_only_config ]]; then
  # Root consumes an inherited descriptor instead of reopening a mutable
  # caller-owned staging path.
  as_root install -DTm644 /dev/stdin "$key_only_config" <<'CONF' || exit 1
# Written by Omarchy once an SSH key was already authorized.
PasswordAuthentication no
KbdInteractiveAuthentication no
AuthenticationMethods publickey
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
Match all
  PasswordAuthentication no
  KbdInteractiveAuthentication no
  AuthenticationMethods publickey
  PubkeyAuthentication yes
  AuthorizedKeysFile .ssh/authorized_keys
CONF
  created=1
fi
as_root ssh-keygen -A || { ((created)) && as_root rm -f "$key_only_config"; exit 1; }
if ! as_root sshd -t || ! effective_is_key_only; then
  ((created)) && as_root rm -f "$key_only_config"
  disable_affected
  exit 0
fi

if systemctl is-active --quiet sshd.service 2>/dev/null && ! as_root systemctl reload sshd.service; then
  disable_affected
  exit 0
fi

legacy_is_omarchy_managed && as_root rm -f -- "$legacy_config"
