echo "Use Omarchy Shell for the Voxtype dictation OSD"

config="$HOME/.config/voxtype/config.toml"

[[ -f $config ]] || exit 0

changed=$(python3 - "$config" <<'PY'
import re
import sys
import tomllib
from pathlib import Path

path = Path(sys.argv[1])
try:
    text = path.read_text(encoding="utf-8")
    data = tomllib.loads(text)
except (OSError, tomllib.TOMLDecodeError):
    sys.exit(0)

osd = data.get("osd")
if isinstance(osd, dict) and "enabled" in osd:
    sys.exit(0)
if osd is not None and not isinstance(osd, dict):
    sys.exit(0)


def disables_osd(candidate):
    try:
        migrated_osd = tomllib.loads(candidate).get("osd")
        return isinstance(migrated_osd, dict) and migrated_osd.get("enabled") is False
    except tomllib.TOMLDecodeError:
        return False


header = re.search(r'''(?m)^[ \t]*\[[ \t]*(?:osd|"osd"|'osd')[ \t]*\][ \t]*(?:#.*)?$''', text)
if header:
    candidate = text[:header.end()] + "\nenabled = false" + text[header.end():]
elif "osd" not in data:
    candidate = text.rstrip("\n") + "\n\n[osd]\nenabled = false\n"
else:
    first_table = re.search(r'''(?m)^[ \t]*\[''', text)
    root_end = first_table.start() if first_table else len(text)
    inline = re.search(r'''(?m)^[ \t]*(?:osd|"osd"|'osd')[ \t]*=[ \t]*\{''', text[:root_end])

    if inline:
        value_start = inline.end() + len(re.match(r'''[ \t]*''', text[inline.end():]).group())
        separator = "" if text[value_start:value_start + 1] == "}" else ", "
        candidate = text[:value_start] + "enabled = false" + separator + text[value_start:]
    elif first_table:
        candidate = text[:root_end] + "osd.enabled = false\n" + text[root_end:]
    else:
        candidate = text.rstrip("\n") + "\nosd.enabled = false\n"

if not disables_osd(candidate):
    sys.exit(0)

path.write_text(candidate, encoding="utf-8")
print("yes")
PY
)

[[ $changed == "yes" ]] || exit 0

systemctl --user try-restart voxtype.service 2>/dev/null || true
