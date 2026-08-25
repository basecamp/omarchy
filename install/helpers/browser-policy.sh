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

# Ancestors of the managed dirs, shortest first. A writable or attacker-owned
# parent can rename the leaf aside; install -d follows a planted symlink.
BROWSER_POLICY_PARENT_DIRS=(
  /etc/chromium
  /etc/chromium/policies
  /etc/opt/chrome
  /etc/opt/chrome/policies
  /etc/opt/edge
  /etc/opt/edge/policies
  /etc/brave
  /etc/brave/policies
)

BROWSER_POLICY_FIREFOX_DIRS=(
  /usr/lib/firefox/distribution
  /opt/zen-browser/distribution
)

BROWSER_POLICY_DEFAULT_COLOR="#1c2027"

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

browser_policy_parent_hardened() {
  local dir=$1

  [[ -d $dir && ! -L $dir ]] || return 1
  [[ $(stat -c '%a' "$dir") == "755" ]] || return 1
  [[ $(stat -c '%U' "$dir") == "root" ]] || return 1
}

browser_policy_parents_hardened() {
  local dir=$1
  local parent

  for parent in "${BROWSER_POLICY_PARENT_DIRS[@]}"; do
    [[ $dir == "$parent"/* ]] || continue
    [[ -e $parent || -L $parent ]] || continue
    browser_policy_parent_hardened "$parent" || return 1
  done
}

browser_policy_setup_parent() {
  local dir=$1

  if [[ -L $dir || ( -e $dir && ! -d $dir ) ]]; then
    as_root rm -rf -- "$dir"
  fi
  as_root install -d -m 0755 -o root -g root "$dir"
}

browser_policy_setup_parents_for() {
  local dir=$1
  local parent

  for parent in "${BROWSER_POLICY_PARENT_DIRS[@]}"; do
    [[ $dir == "$parent"/* ]] || continue
    browser_policy_setup_parent "$parent"
  done
}

browser_policy_setup_dir() {
  local dir=$1

  browser_policy_setup_parents_for "$dir"
  as_root install -d -m 2775 -o root -g "$BROWSER_POLICY_GROUP" "$dir"
  browser_policy_purge_dir "$dir"
}

# Themes are user-installed. Accept only three 0-255 components.
browser_policy_theme_hex() {
  local theme_rgb=$1

  if [[ $theme_rgb =~ ^[[:space:]]*([0-9]{1,3})[[:space:]]*,[[:space:]]*([0-9]{1,3})[[:space:]]*,[[:space:]]*([0-9]{1,3})[[:space:]]*$ ]] &&
    (( 10#${BASH_REMATCH[1]} < 256 && 10#${BASH_REMATCH[2]} < 256 && 10#${BASH_REMATCH[3]} < 256 )); then
    printf '#%02x%02x%02x' "$((10#${BASH_REMATCH[1]}))" "$((10#${BASH_REMATCH[2]}))" "$((10#${BASH_REMATCH[3]}))"
    return
  fi

  printf '%s' "$BROWSER_POLICY_DEFAULT_COLOR"
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

browser_policy_firefox_policy_file_ok() {
  local file=$1
  local mode
  local group_write
  local other_write

  [[ -f $file && ! -L $file ]] || return 1
  [[ $(stat -c '%U' "$file") == "root" ]] || return 1
  mode=$(stat -c '%a' "$file")
  group_write=$((8#${mode: -2:1}))
  other_write=$((8#${mode: -1}))
  (( (group_write & 2) == 0 && (other_write & 2) == 0 ))
}

browser_policy_firefox_hardened() {
  local dir=$1

  [[ -d $dir ]] || return 1
  [[ $(stat -c '%a' "$dir") == "755" ]] || return 1
  [[ $(stat -c '%U' "$dir") == "root" ]] || return 1
  browser_policy_firefox_policy_file_ok "$dir/policies.json"
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
