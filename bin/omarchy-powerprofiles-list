#!/bin/bash

powerprofilesctl list |
  awk '/^\s*[* ]\s*[a-zA-Z0-9\-]+:$/ { gsub(/^[*[:space:]]+|:$/,""); print }' |
  tac
