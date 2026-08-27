#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

command="$ROOT/bin/omarchy-windows-key"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

rg -q '/sys/firmware/acpi/tables/MSDM' "$command" ||
  fail "windows key helper reads the ACPI MSDM table"
pass "windows key helper reads the ACPI MSDM table"

rg -q 'read_msdm strings' "$command" ||
  fail "windows key helper tries strings first"
pass "windows key helper tries strings first"

rg -q 'read_msdm cat' "$command" ||
  fail "windows key helper falls back to cat"
pass "windows key helper falls back to cat"

write_msdm() {
  local path=$1
  local payload=$2

  python3 -c 'import pathlib, sys
pathlib.Path(sys.argv[1]).write_bytes(b"MSDM" + b"\x00" * 52 + sys.argv[2].encode())
' "$path" "$payload"
}

run_helper() {
  OMARCHY_MSDM_PATH=$1 PATH="$ROOT/bin:$PATH" "$command"
}

key="XXXXX-XXXXX-XXXXX-XXXXX-XXXXX"
write_msdm "$tmp/msdm" "$key"
output=$(run_helper "$tmp/msdm")
[[ $output == "$key" ]] || fail "windows key helper prints the firmware key" "actual: $output"
pass "windows key helper prints the firmware key"

mkdir -p "$tmp/bin"
cat >"$tmp/bin/strings" <<'EOF'
#!/bin/bash
exit 0
EOF
chmod +x "$tmp/bin/strings"
output=$(PATH="$tmp/bin:$ROOT/bin:$PATH" OMARCHY_MSDM_PATH="$tmp/msdm" "$command")
[[ $output == "$key" ]] || fail "windows key helper falls back to cat when strings finds nothing" "actual: $output"
pass "windows key helper falls back to cat when strings finds nothing"

write_msdm "$tmp/empty" "no-product-key-here"
if OMARCHY_MSDM_PATH="$tmp/empty" PATH="$ROOT/bin:$PATH" "$command" >"$tmp/out" 2>"$tmp/err"; then
  fail "windows key helper fails when the table has no key"
fi
[[ $(<"$tmp/err") == "Firmware license table found, but no Windows product key could be extracted." ]] ||
  fail "windows key helper reports a missing key" "actual: $(<"$tmp/err")"
pass "windows key helper reports a missing key"

if OMARCHY_MSDM_PATH="$tmp/missing" PATH="$ROOT/bin:$PATH" "$command" >"$tmp/out" 2>"$tmp/err"; then
  fail "windows key helper fails when firmware has no MSDM table"
fi
[[ $(<"$tmp/err") == "No Windows license key found in firmware." ]] ||
  fail "windows key helper reports missing firmware table" "actual: $(<"$tmp/err")"
pass "windows key helper reports missing firmware table"
