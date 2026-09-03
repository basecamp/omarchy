echo "Re-stage Tokyo Night with packaged boot intro videos"

theme_name_path="$HOME/.local/state/omarchy/current/theme.name"

[[ -s $theme_name_path ]] || exit 0

theme_name=$(<"$theme_name_path")
[[ $theme_name == "tokyo-night" ]] || exit 0

omarchy-theme-refresh

state_dir="$HOME/.local/state/omarchy"
marker="$state_dir/background-intro.boot-id"
boot_id=${OMARCHY_BOOT_ID:-$(< /proc/sys/kernel/random/boot_id)}
mkdir -p "$state_dir"
marker_staged=$(mktemp "$state_dir/.background-intro.boot-id.XXXXXX")
trap 'rm -f "$marker_staged"' EXIT
printf '%s\n' "$boot_id" >"$marker_staged"
mv -f "$marker_staged" "$marker"
trap - EXIT
