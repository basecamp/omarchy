echo "Migrate Brave Origin Beta profile data to stable"

beta=~/.config/BraveSoftware/Brave-Origin-Beta
stable=~/.config/BraveSoftware/Brave-Origin

# A running Chromium-family browser holds a SingletonLock (and socket) inside
# its user-data-dir; -L also catches a lock left as a dangling symlink.
profile_open() {
  [[ -L $1/SingletonLock || -e $1/SingletonLock || -S $1/SingletonSocket ]]
}

if [[ -d $beta ]]; then
  if profile_open "$beta" || { [[ -d $stable ]] && profile_open "$stable"; }; then
    echo "Brave is running — skipping profile migration." >&2
    echo "Quit Brave completely, then run: omarchy-update" >&2
  else
    if [[ -d $stable ]]; then
      backup="$stable.bak.$(date +%Y%m%d%H%M%S)"
      mv "$stable" "$backup"
      echo "Existing stable profile preserved at $backup"
    fi

    mv "$beta" "$stable"
    rm -f "$stable"/Singleton*
    rm -rf ~/.cache/BraveSoftware/Brave-Origin-Beta

    echo "Beta profile migrated. Previous stable data (if any) kept as a .bak directory."
  fi
fi
