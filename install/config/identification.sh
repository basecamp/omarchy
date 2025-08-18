#!/bin/bash

[ -z "$OMARCHY_USER_NAME" ] &&
  OMARCHY_USER_NAME=$(gum input --placeholder "Enter full name" --prompt "Name> ") &&
  export OMARCHY_USER_NAME

[ -z "$OMARCHY_USER_EMAIL" ] &&
  OMARCHY_USER_EMAIL=$(gum input --placeholder "Enter email address" --prompt "Email> ") &&
  export OMARCHY_USER_NAME
