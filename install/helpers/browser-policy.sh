# Chromium-family machine policy is mandatory for every profile. A dedicated
# group at 2775 lets every Omarchy user write color.json and every other uid
# read; other-write stays off. Setgid so new files inherit the group.

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/as-root.sh"

BROWSER_POLICY_GROUP=omarchy-browser-policy

BROWSER_POLICY_MANAGED_DIRS=(
  /etc/chromium/policies/managed
  /etc/opt/chrome/policies/managed
  /etc/opt/edge/policies/managed
  /etc/brave/policies/managed
)

BROWSER_POLICY_FIREFOX_DIRS=(
  /usr/lib/firefox/distribution
  /opt/zen-browser/distribution
)

browser_policy_setup_group() {
  local provisioning_dir="${OMARCHY_PROVISIONING_DIR:-/var/lib/omarchy/provisioning}"

  as_root groupadd --system --force "$BROWSER_POLICY_GROUP"
  as_root mkdir -p "$provisioning_dir"
  if ! grep -qxF "$BROWSER_POLICY_GROUP" "$provisioning_dir/groups" 2>/dev/null; then
    printf '%s\n' "$BROWSER_POLICY_GROUP" | as_root tee -a "$provisioning_dir/groups" >/dev/null
  fi

  if [[ -n ${OMARCHY_INSTALL_USER:-} ]] && getent passwd "$OMARCHY_INSTALL_USER" >/dev/null; then
    as_root usermod -aG "$BROWSER_POLICY_GROUP" "$OMARCHY_INSTALL_USER"
  fi
}

browser_policy_grant_user() {
  local user=${1:-}

  if [[ -z $user || $user == "root" ]]; then
    user=${SUDO_USER:-}
  fi

  [[ -n $user && $user != "root" ]] || return 0
  getent passwd "$user" >/dev/null || return 0
  as_root usermod -aG "$BROWSER_POLICY_GROUP" "$user"
}

browser_policy_purge_dir() {
  local dir=$1

  as_root find "$dir" -mindepth 1 -maxdepth 1 ! -user root -exec rm -rf -- {} +
}

browser_policy_dir_hardened() {
  local dir=$1

  [[ -d $dir ]] || return 1
  [[ $(stat -c '%a' "$dir") == "2775" ]] || return 1
  [[ $(stat -c '%U' "$dir") == "root" ]] || return 1
  [[ $(stat -c '%G' "$dir") == $BROWSER_POLICY_GROUP ]] || return 1
}

browser_policy_setup_dir() {
  local dir=$1

  as_root install -d -m 2775 -o root -g "$BROWSER_POLICY_GROUP" "$dir"
  browser_policy_purge_dir "$dir"
}

browser_policy_file_owner() {
  local user

  if [[ -n ${OMARCHY_INSTALL_USER:-} && $OMARCHY_INSTALL_USER != "root" ]]; then
    printf '%s\n' "$OMARCHY_INSTALL_USER"
    return
  fi
  if [[ -n ${SUDO_USER:-} && $SUDO_USER != "root" ]]; then
    printf '%s\n' "$SUDO_USER"
    return
  fi
  if [[ -n ${PKEXEC_UID:-} ]]; then
    user=$(getent passwd "$PKEXEC_UID" | cut -d: -f1)
    if [[ -n $user && $user != "root" ]]; then
      printf '%s\n' "$user"
      return
    fi
  fi
  user=${USER:-$(id -un)}
  if [[ $user != "root" ]]; then
    printf '%s\n' "$user"
  fi
}

# sudo when this process has a controlling terminal (fd 0 is /dev/null under
# `bash -lc cmd &`, but /dev/tty still works). pkexec when it does not.
browser_policy_elevate() {
  if (( EUID == 0 )); then
    "$@"
  elif { exec 3</dev/tty; } 2>/dev/null; then
    exec 3<&-
    sudo "$@"
  else
    pkexec "$@"
  fi
}

browser_policy_write_color() {
  local policy_dir=$1
  local hex=$2
  local dest=$policy_dir/color.json
  local payload
  local tmp
  local owner

  [[ -d $policy_dir ]] || return 0

  payload=$(printf '{"BrowserThemeColor": "%s", "BrowserColorScheme": "device"}\n' "$hex")
  tmp=$(mktemp) || return 1
  printf '%s' "$payload" >"$tmp"

  # A planted symlink or directory must not be written through or into.
  if [[ -L $dest || -d $dest ]]; then
    if ! rm -rf -- "$dest" 2>/dev/null; then
      if ! browser_policy_elevate rm -rf -- "$dest"; then
        rm -f "$tmp"
        echo "omarchy-theme-set-browser: cannot replace $dest (need group $BROWSER_POLICY_GROUP)" >&2
        return 1
      fi
    fi
  fi

  if install -m 664 -T "$tmp" "$dest" 2>/dev/null; then
    rm -f "$tmp"
    return 0
  fi

  owner=$(browser_policy_file_owner)
  [[ -n $owner ]] || owner=root
  if browser_policy_elevate install -m 664 -o "$owner" -g "$BROWSER_POLICY_GROUP" -T "$tmp" "$dest"; then
    rm -f "$tmp"
    return 0
  fi

  rm -f "$tmp"
  echo "omarchy-theme-set-browser: cannot write $dest (need group $BROWSER_POLICY_GROUP)" >&2
  return 1
}

browser_policy_firefox_hardened() {
  local dir=$1

  [[ -d $dir ]] || return 1
  [[ $(stat -c '%a' "$dir") == "755" ]] || return 1
  [[ $(stat -c '%U' "$dir") == "root" ]] || return 1
  [[ -f $dir/policies.json && ! -L $dir/policies.json ]] || return 1
}

browser_policy_install_firefox_policies() {
  local distribution_dir=$1
  local policies=${2:-$OMARCHY_PATH/default/firefox/policies.json}

  as_root install -m 644 -o root -g root -T "$policies" "$distribution_dir/policies.json"
}

browser_policy_setup_firefox_distribution() {
  local distribution_dir=$1
  local policies=${2:-$OMARCHY_PATH/default/firefox/policies.json}

  as_root install -d -m 0755 -o root -g root "$distribution_dir"
  browser_policy_purge_dir "$distribution_dir"
  browser_policy_install_firefox_policies "$distribution_dir" "$policies"
}
