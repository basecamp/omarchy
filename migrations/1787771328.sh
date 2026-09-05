echo "Rewrite the font override that captured every family named *mono*"

# `omarchy font set` wrote the chosen family as a prepend_first edit on any
# pattern carrying the monospace generic. /etc/fonts/conf.d/48-guessfamily.conf
# appends that generic to every pattern whose family name merely contains
# "mono", so the edit fired for a request naming Liberation Mono as readily as
# for one naming monospace, and put the chosen family at the head of the list,
# ahead of the family the application actually asked for. Every install that
# picked a font since then carries that file, and rewriting it only happens on
# the next pick. Restate it as the alias it should have been, which inserts the
# family at the generic instead of at the head.

fontconfig_file="$HOME/.config/fontconfig/fonts.conf"

[[ -f $fontconfig_file ]] || exit 0

font_name=$(sed -n '/mode="prepend_first"/{n;s#^ *<string>\(.*\)</string> *$#\1#p;}' "$fontconfig_file")

[[ -n $font_name ]] || exit 0

previous_override() {
  cat <<XML
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <match target="pattern">
    <test name="family" qual="any">
      <string>monospace</string>
    </test>
    <edit name="family" mode="prepend_first" binding="strong">
      <string>$font_name</string>
    </edit>
  </match>
</fontconfig>
XML
}

# The whole file has to be what that version wrote, so an override someone has
# edited by hand is left as it is rather than silently replaced.
[[ $(<"$fontconfig_file") == "$(previous_override)" ]] || exit 0

cat >"$fontconfig_file" <<XML
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <alias binding="strong">
    <family>monospace</family>
    <prefer>
      <family>$font_name</family>
    </prefer>
  </alias>
</fontconfig>
XML
