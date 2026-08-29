#!/bin/bash
set -euo pipefail

admin="$1"
root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
mkdir -m 700 "$root/providers" "$root/package-definitions" \
  "$root/definitions" "$root/index"

digest=$(sha256sum "$admin" | cut -d' ' -f1)
cat >"$root/candidate.provider" <<EOF
format=omarchy-provider-v1
service-id=local.admin-test
adapter-class=admin-test-adapter
adapter-digest=dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
adapter-abi=1
executable=$admin
executable-digest=$digest
expected-uid=$(id -u)
protocol=2
EOF

common=(--providers "$root/providers" \
  --package-definitions "$root/package-definitions" \
  --definitions "$root/definitions" \
  --grants "$root/grants" --revisions "$root/revisions" \
  --index "$root/index" --owner "$(id -u)")

"$admin" inspect "${common[@]}"
"$admin" install "$root/candidate.provider" --dry-run "${common[@]}" |
  grep -q '^decision=installable$'
[[ ! -e "$root/providers/local.admin-test.provider" ]]
"$admin" install "$root/candidate.provider" "${common[@]}"
[[ -f "$root/providers/local.admin-test.provider" ]]
"$admin" inspect "${common[@]}" | grep -q '^service=local.admin-test '

cp "$admin" "$root/provider-v2"
printf '\0' >>"$root/provider-v2"
chmod 700 "$root/provider-v2"
digest_v2=$(sha256sum "$root/provider-v2" | cut -d' ' -f1)
sed -e "s|^executable=.*|executable=$root/provider-v2|" \
  -e "s|^executable-digest=.*|executable-digest=$digest_v2|" \
  "$root/candidate.provider" >"$root/candidate-v2.provider"
if "$admin" upgrade "$root/candidate-v2.provider" --dry-run \
    "${common[@]}"; then
  echo "unreviewed provider upgrade unexpectedly succeeded" >&2
  exit 1
else
  [[ $? == 4 ]]
fi
"$admin" upgrade "$root/candidate-v2.provider" --reviewed --dry-run \
  "${common[@]}" | grep -q '^decision=requires-plugin-review$'
grep -q "^executable=$admin$" \
  "$root/providers/local.admin-test.provider"
"$admin" upgrade "$root/candidate-v2.provider" --reviewed \
  "${common[@]}"
grep -q "^executable=$root/provider-v2$" \
  "$root/providers/local.admin-test.provider"

"$admin" remove local.admin-test --dry-run "${common[@]}"
[[ -f "$root/providers/local.admin-test.provider" ]]
"$admin" remove local.admin-test "${common[@]}"
[[ ! -e "$root/providers/local.admin-test.provider" ]]
echo "external provider admin cli: PASS"
