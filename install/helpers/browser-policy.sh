# Chromium-family machine policy is mandatory for every profile. Directories
# stay 0755 root:root; omarchy-theme-set-browser-policy is the privileged
# write for color.json.

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/as-root.sh"

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

browser_policy_purge_dir() {
  local dir=$1

  as_root find "$dir" -mindepth 1 -maxdepth 1 ! -user root -exec rm -rf -- {} +
}

browser_policy_parent_hardened() {
  local dir=$1

  [[ -d $dir && ! -L $dir ]] || return 1
  [[ $(stat -c '%a' "$dir") == "755" ]] || return 1
  [[ $(stat -c '%U' "$dir") == "root" ]] || return 1
}

browser_policy_dir_hardened() {
  browser_policy_parent_hardened "$1"
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
  browser_policy_setup_parent "$dir"
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

browser_policy_install_color() {
  local policy_dir=$1
  local hex=$2
  local dest=$policy_dir/color.json
  local tmp

  [[ -d $policy_dir && ! -L $policy_dir ]] || return 0
  [[ $hex =~ ^#[0-9a-f]{6}$ ]] || return 1

  tmp=$(mktemp) || return 1
  printf '{"BrowserThemeColor": "%s", "BrowserColorScheme": "device"}\n' "$hex" >"$tmp"

  if [[ -L $dest || -d $dest ]]; then
    if ! rm -rf -- "$dest" 2>/dev/null; then
      rm -f "$tmp"
      return 1
    fi
  fi

  if install -m 0644 -T "$tmp" "$dest" 2>/dev/null; then
    rm -f "$tmp"
    return 0
  fi

  rm -f "$tmp"
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

  [[ -d $dir && ! -L $dir ]] || return 1
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

  browser_policy_setup_parent "$distribution_dir"
  browser_policy_purge_dir "$distribution_dir"
  browser_policy_install_firefox_policies "$distribution_dir" "$policies"
}
