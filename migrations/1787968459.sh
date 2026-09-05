echo "Order the hibernation resume hook before filesystems"

resume_config="${OMARCHY_RESUME_CONFIG:-/etc/mkinitcpio.conf.d/omarchy_resume.conf}"
rebuild_marker="${OMARCHY_RESUME_REBUILD_MARKER:-/var/lib/omarchy/migrations/1787968459}"

[[ -f $resume_config ]] || exit 0
[[ ! -e $rebuild_marker ]] || exit 0

if grep -q '^HOOKS+=(resume)$' "$resume_config"; then
  needs_config_update=true
elif grep -q '^# omarchy:resume-hook$' "$resume_config"; then
  needs_config_update=false
else
  exit 0
fi

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

cat >"$tmp" <<'EOF'
# omarchy:resume-hook
_omarchy_resume_hooks=()
_omarchy_resume_inserted=false

for _omarchy_hook in "${HOOKS[@]}"; do
  [[ $_omarchy_hook == "resume" ]] && continue

  if [[ $_omarchy_hook == "filesystems" && $_omarchy_resume_inserted == false ]]; then
    _omarchy_resume_hooks+=(resume)
    _omarchy_resume_inserted=true
  fi

  _omarchy_resume_hooks+=("$_omarchy_hook")
done

if [[ $_omarchy_resume_inserted == false ]]; then
  _omarchy_resume_hooks+=(resume)
fi

HOOKS=("${_omarchy_resume_hooks[@]}")
unset _omarchy_resume_hooks _omarchy_resume_inserted _omarchy_hook
EOF

if [[ $needs_config_update == true ]]; then
  sudo install -m 644 "$tmp" "$resume_config"
fi

sudo limine-mkinitcpio
sudo install -Dm644 /dev/null "$rebuild_marker"
