echo "Fix Obsidian -disable-gpu so CLI commands parse"

flags="$HOME/.config/obsidian/user-flags.conf"

# A symlink is left alone: it already tracks whatever the package ships.
[[ -f $flags && ! -L $flags ]] || exit 0
grep -qxF -- '-disable-gpu' "$flags" || exit 0

sed -i 's/^-disable-gpu$/--disable-gpu/' "$flags"
