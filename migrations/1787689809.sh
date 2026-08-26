echo "Update first-run hooks to safe notification click arguments"

hooks_dir="$HOME/.config/omarchy/hooks/post-update.d"

agent_hook="$hooks_dir/setup-agent.hook"
if [[ -f $agent_hook && ! -L $agent_hook ]] &&
  grep -Fq -- '--exec "omarchy menu summon setup.default.agent"' "$agent_hook"; then
  sed -i 's|--exec "omarchy menu summon setup\.default\.agent"|--exec omarchy menu summon setup.default.agent|' "$agent_hook"
fi

fingerprint_hook="$hooks_dir/setup-fingerprint.hook"
if [[ -f $fingerprint_hook && ! -L $fingerprint_hook ]] &&
  grep -Fq -- '--exec "omarchy-launch-floating-terminal-with-presentation omarchy-setup-security-fingerprint"' "$fingerprint_hook"; then
  sed -i 's|--exec "omarchy-launch-floating-terminal-with-presentation omarchy-setup-security-fingerprint"|--exec omarchy-launch-floating-terminal-with-presentation omarchy-setup-security-fingerprint|' "$fingerprint_hook"
fi

voxtype_hook="$hooks_dir/install-voxtype.hook"
if [[ -f $voxtype_hook && ! -L $voxtype_hook ]] &&
  grep -Fq -- '--exec "omarchy-launch-floating-terminal-with-presentation omarchy-voxtype-install"' "$voxtype_hook"; then
  sed -i 's|--exec "omarchy-launch-floating-terminal-with-presentation omarchy-voxtype-install"|--exec omarchy-launch-floating-terminal-with-presentation omarchy-voxtype-install|' "$voxtype_hook"
fi
