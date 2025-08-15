#!/bin/bash

[ -z "$OMARCHY_USER_NAME" ] &&
  export OMARCHY_USER_NAME=$(gum input --placeholder "Enter full name" --prompt "Name> ")

[ -z "$OMARCHY_USER_EMAIL" ] &&
  export OMARCHY_USER_EMAIL=$(gum input --placeholder "Enter email address" --prompt "Email> ")
