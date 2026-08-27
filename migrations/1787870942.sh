echo "Retire the Super + Shift + S screenshot example now that it is a default binding"

# The bindings.lua template used to offer this line, commented out, as the
# Logitech MX Keys example. Super + Shift + S is now bound to the same command
# by default, and Hyprland stacks duplicate binds, so an uncommented copy runs
# two screenshot instances that race each other's picker. Comment the copy back
# out; the chord rebound to any other command is the user's own and stays.
bindings_file="$HOME/.config/hypr/bindings.lua"

if [[ -f $bindings_file ]] && grep -Eq '^[[:space:]]*o\.bind\("SUPER \+ SHIFT \+ S",[^)]*"omarchy-capture-screenshot"\)' "$bindings_file"; then
  sed -i -E 's|^([[:space:]]*)(o\.bind\("SUPER \+ SHIFT \+ S",[^)]*"omarchy-capture-screenshot"\))|\1-- Super + Shift + S takes a screenshot by default now, so this duplicate is retired:\n\1-- \2|' "$bindings_file"
fi
