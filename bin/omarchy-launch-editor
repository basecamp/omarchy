#!/bin/bash

case "${EDITOR:-nvim}" in
nvim | vim | nano | micro | hx | helix)
  exec setsid uwsm-app -- "$TERMINAL" -e "$EDITOR" "$@"
  ;;
*)
  exec setsid uwsm-app -- "$EDITOR" "$@"
  ;;
esac
