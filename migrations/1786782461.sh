echo "Remove the literal \\n[text-bindings] line an earlier migration wrote into foot.ini"

# A 3.8.3 migration appended the section header with `sed -i '$a\\\n[text-bindings]'`,
# one backslash too many, so GNU sed wrote a backslash and an "n" as two ordinary
# characters ahead of the section name, leaving the single line \n[text-bindings]
# where a blank line and a [text-bindings] header belong. foot rejects it with
# "syntax error: key/value pair has no value" and stops reading the rest of the file.
#
# The later text-binding migration looks for the header with `grep -qxF`, which the
# literal line doesn't match, so it appends a second real [text-bindings] section and
# leaves the broken line in place. Removing the line is what actually repairs the
# config; the duplicate section that migration added is valid and harmless.

foot_config="$HOME/.config/foot/foot.ini"

if [[ -f $foot_config ]] && grep -qxF '\n[text-bindings]' "$foot_config"; then
  sed -i '/^\\n\[text-bindings\]$/d' "$foot_config"
fi
