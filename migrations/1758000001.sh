echo "Reload mako to apply updated DND rules (allow critical)."
command -v makoctl >/dev/null 2>&1 && makoctl reload || true
