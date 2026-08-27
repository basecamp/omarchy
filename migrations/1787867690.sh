echo "Guard rustup cargo env lines so a missing ~/.cargo/env cannot login-loop UWSM"

# rustup's default install appends an unguarded `. "$HOME/.cargo/env"` to shell
# profiles. UWSM sources ~/.profile on graphical login; if that file is missing,
# session start fails and SDDM loops. PATH for cargo is owned by env-bootstrap
# after the companion change; keep a guarded source so leftover rustup env still
# loads when present, and never aborts when absent.
unguarded_dot='. "$HOME/.cargo/env"'
unguarded_source='source "$HOME/.cargo/env"'
guarded='[[ -r "$HOME/.cargo/env" ]] && . "$HOME/.cargo/env"'

guard_cargo_env_line() {
  local file="$1"
  local tmp

  [[ -f $file ]] || return 0
  grep -qxF -- "$unguarded_dot" "$file" ||
    grep -qxF -- "$unguarded_source" "$file" ||
    return 0

  tmp=$(mktemp)
  awk -v guarded="$guarded" -v dot="$unguarded_dot" -v src="$unguarded_source" '
    $0 == dot || $0 == src { print guarded; next }
    { print }
  ' "$file" >"$tmp"
  cp -- "$tmp" "$file"
  rm -f "$tmp"
}

guard_cargo_env_line "$HOME/.profile"
guard_cargo_env_line "$HOME/.bash_profile"
guard_cargo_env_line "$HOME/.bashrc"
guard_cargo_env_line "$HOME/.zprofile"
guard_cargo_env_line "$HOME/.zshrc"
