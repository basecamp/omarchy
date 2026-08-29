echo "Order the hibernation resume hook before filesystems"

resume_config="/etc/mkinitcpio.conf.d/omarchy_resume.conf"
[[ -f $resume_config ]] && grep -q '^HOOKS+=(resume)$' "$resume_config" || exit 0

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

sudo install -m 644 "$tmp" "$resume_config"
sudo limine-mkinitcpio
