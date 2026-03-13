echo "Use mise shims in ~/.config/uwsm/env"

UWSM_ENV="$HOME/.config/uwsm/env"

if [[ -f $UWSM_ENV ]] && grep -q 'mise activate bash)' "$UWSM_ENV"; then
  sed -i 's/mise activate bash)/mise activate bash --shims)/g' "$UWSM_ENV"
fi
