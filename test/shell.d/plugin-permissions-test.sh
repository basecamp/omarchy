#!/bin/bash

set -euo pipefail

# shellcheck disable=SC1091
source "$(dirname "$0")/base-test.sh"

test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

mkdir -p "$test_dir/bin"
calls="$test_dir/calls"
touch "$calls"

cat >"$test_dir/bin/omarchy-shell" <<'STUB'
#!/bin/bash

printf '%s\t%s\t%s\t%s\t%s\t%s\n' "${1:-}" "${2:-}" "${3:-}" "${4:-}" "${5:-}" "${6:-}" >>"$PERMISSION_TEST_CALLS"

[[ ${1:-} == "plugin-permissions" ]] || exit 31
case ${2:-} in
  list)
    printf 'permission-00000000000000000000000000000000\n'
    ;;
  review)
    printf 'permission-11111111111111111111111111111111\n'
    ;;
  apply)
    [[ ${PERMISSION_TEST_MODE:-} != "apply-fail" ]] || exit 1
    printf 'permission-22222222222222222222222222222222\n'
    ;;
  revoke)
    printf 'permission-33333333333333333333333333333333\n'
    ;;
  poll)
    case ${3:-} in
      permission-00000000000000000000000000000000)
        list_result='{"operationId":"permission-00000000000000000000000000000000","kind":"list","state":"succeeded","result":{"plugin":"org.example.evil\nplugin","permissions":[{"rowId":"row-11111111111111111111111111111111","kind":"builtin","name":"notifications.send\u001b[31m\nforged","required":true,"available":true,"state":"granted","scope":"desktop","operations":["send"]},{"rowId":"row-22222222222222222222222222222222","kind":"dynamic","name":"cli.example","title":"Example CLI","required":false,"available":true,"state":"denied","scope":"repository","operations":["Read\nfiles","Write"]}]}}'
        case ${PERMISSION_TEST_MODE:-} in
          malformed-row)
            list_result=$(jq -c '.result.permissions[0].required = "yes"' <<<"$list_result")
            ;;
          extra-authority)
            list_result=$(jq -c '.result.authoritySequence = 17' <<<"$list_result")
            ;;
          oversized-result)
            list_result=$(jq -c '.result.permissions[0] as $row | .result.permissions = [range(0; 257) | $row]' <<<"$list_result")
            ;;
        esac
        printf '%s\n' "$list_result"
        ;;
      permission-11111111111111111111111111111111)
        printf '%s\n' '{"operationId":"permission-11111111111111111111111111111111","kind":"review","state":"succeeded","result":{"plugin":"org.example.review","permissions":[{"rowId":"row-11111111111111111111111111111111","kind":"builtin","name":"notifications.send","required":true,"available":true,"state":"undecided","scope":"desktop","operations":["send"],"delta":"added","reason":"Show status"},{"rowId":"row-22222222222222222222222222222222","kind":"dynamic","name":"cli.example","title":"Example CLI","required":false,"available":true,"state":"undecided","scope":"repository","operations":[{"operationId":"operation-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","name":"read","label":"Read"},{"operationId":"operation-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","name":"write","label":"Write"}],"delta":"added","reason":"Read only when selected"}]}}'
        ;;
      permission-22222222222222222222222222222222)
        [[ ${PERMISSION_TEST_MODE:-} != "poll-fail" ]] || exit 1
        printf '%s\n' '{"operationId":"permission-22222222222222222222222222222222","kind":"apply","state":"succeeded","result":{"applied":true}}'
        ;;
      permission-33333333333333333333333333333333)
        printf '%s\n' '{"operationId":"permission-33333333333333333333333333333333","kind":"revoke","state":"succeeded","result":{"applied":true}}'
        ;;
      *)
        exit 32
        ;;
    esac
    ;;
  *)
    exit 33
    ;;
esac
STUB
chmod +x "$test_dir/bin/omarchy-shell"

export PATH="$test_dir/bin:$PATH"
export PERMISSION_TEST_CALLS="$calls"

host_qml="$ROOT/native/plugin-runtime/shell/SecurePluginHost.qml"
rg -q 'target: "plugin-permissions"' "$host_qml" || fail "secure host owns a dedicated permission IPC target"
for method in list review apply revoke poll; do
  rg -q "function $method" "$host_qml" || fail "secure permission IPC exposes $method"
done
! rg -q 'function (beginList|beginReview|beginInteractiveCliReview|applyInteractiveCli)' "$host_qml" ||
  fail "permission IPC does not leak native method or provenance names"
rg -Uq 'function review[^{]*\{[[:space:]]*return PluginManager.permissions.beginInteractiveCliReview' "$host_qml" ||
  fail "review IPC stays paired to interactive CLI provenance"
rg -Uq '(?s)function apply[^{]*\{.*?return PluginManager.permissions.applyInteractiveCli' "$host_qml" ||
  fail "apply IPC stays paired to interactive CLI provenance"
rg -q 'maximumPermissionChoiceBytes: 262176' "$host_qml" || fail "permission IPC carries the native maximum choice document"
rg -q 'maximumPermissionChoiceChunkBytes: 90000' "$host_qml" || fail "permission IPC bounds each transport chunk"
rg -q 'choicesJson.length > root.maximumPermissionChoiceBytes' "$host_qml" || fail "permission IPC rejects one byte over the native maximum"
pass "secure host exposes only the paired permission IPC contract"

# shellcheck disable=SC1091
source "$ROOT/bin/omarchy-plugin-permissions"
printf -v maximum_choices '%*s' 262176 ''
split_permission_choices "$maximum_choices" || fail "maximum permission choice document was rejected"
# shellcheck disable=SC2154
[[ ${#choice_chunk_0} == 90000 && ${#choice_chunk_1} == 90000 && ${#choice_chunk_2} == 82176 ]] ||
  fail "maximum permission choice document did not use three bounded chunks"
if split_permission_choices "${maximum_choices}x"; then
  fail "one byte over the maximum permission choice document was accepted"
fi
pass "permission choice chunking accepts the exact maximum and rejects one byte over"

json_output=$("$ROOT/bin/omarchy-plugin-permissions" org.example.evil --json)
jq -e '
  .plugin == "org.example.evil\nplugin"
  and (.permissions | length == 2)
  and all(.permissions[]; has("rowId") | not)
  and all(.permissions[].operations[]?; type != "object" or (has("operationId") | not))
' <<<"$json_output" >/dev/null || fail "read-only JSON omits mutation handles" "$json_output"
pass "read-only JSON omits every mutation handle"

for malformed_mode in malformed-row extra-authority oversized-result; do
  if malformed_output=$(PERMISSION_TEST_MODE="$malformed_mode" \
    "$ROOT/bin/omarchy-plugin-permissions" org.example.evil --json 2>&1); then
    fail "invalid permission result reached JSON output: $malformed_mode" "$malformed_output"
  fi
  [[ $malformed_output == *"invalid permission result"* ]] ||
    fail "invalid permission result did not fail closed: $malformed_mode" "$malformed_output"
  [[ $malformed_output != *"authoritySequence"* ]] ||
    fail "rejected authority metadata leaked through the CLI" "$malformed_output"
done
pass "malformed rows, authority metadata, and oversized permission arrays fail closed"

human_output=$("$ROOT/bin/omarchy-plugin-permissions" org.example.evil)
[[ $human_output != *$'\e'* ]] || fail "human permission output emits an ANSI escape"
[[ $human_output == *"org.example.evil plugin"* ]] || fail "human permission output flattens control characters" "$human_output"
[[ $human_output == *"notifications.send forged"* ]] || fail "human permission output sanitizes names" "$human_output"
[[ $human_output == *"Read files"* ]] || fail "human permission output sanitizes operation labels" "$human_output"
pass "human permission output is terminal-safe"

calls_before=$(wc -l <"$calls")
if "$ROOT/bin/omarchy-plugin-permissions" review org.example.review >/dev/null 2>&1; then
  fail "non-TTY review was accepted"
fi
if "$ROOT/bin/omarchy-plugin-permissions" revoke org.example.evil >/dev/null 2>&1; then
  fail "non-TTY revoke was accepted"
fi
[[ $(wc -l <"$calls") == "$calls_before" ]] || fail "non-TTY mutation reached shell IPC"
pass "non-TTY mutations fail before shell IPC"

for forbidden in --yes -y --grant-all grant-all; do
  if "$ROOT/bin/omarchy-plugin-permissions" review org.example.review "$forbidden" >/dev/null 2>&1; then
    fail "forbidden bulk approval flag was accepted: $forbidden"
  fi
done
if "$ROOT/bin/omarchy-plugin-permissions" review org.example.review --json >/dev/null 2>&1; then
  fail "JSON mutation mode was accepted"
fi
pass "JSON and bulk approval mutation modes are rejected"

require_command script
review_output=$(printf 'y\ny\ny\nn\n' | script -qefc \
  "env PATH='$test_dir/bin:$PATH' PERMISSION_TEST_CALLS='$calls' '$ROOT/bin/omarchy-plugin-permissions' review org.example.review" /dev/null)
[[ $review_output == *"Permissions updated for org.example.review"* ]] || fail "interactive permission review did not complete" "$review_output"
apply_choices=$(awk -F '\t' '$2 == "apply" {print $4 $5 $6}' "$calls" | tail -n1)
jq -e '
  .choices == [
    {rowId:"row-11111111111111111111111111111111", decision:"grant"},
    {rowId:"row-22222222222222222222222222222222", decision:"grant", operations:["operation-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"]}
  ]
' <<<"$apply_choices" >/dev/null || fail "interactive review did not submit exact row and operation handles" "$apply_choices"
pass "interactive review prompts every row and narrows dynamic operations"

revoke_output=$(printf '1\ny\n' | script -qefc \
  "env PATH='$test_dir/bin:$PATH' PERMISSION_TEST_CALLS='$calls' '$ROOT/bin/omarchy-plugin-permissions' revoke org.example.evil" /dev/null)
[[ $revoke_output == *"Revoked permission 1 for org.example.evil"* ]] || fail "interactive one-row revoke did not complete" "$revoke_output"
[[ $revoke_output != *"Example CLI"* ]] || fail "revoke selector displayed a permission that was not granted" "$revoke_output"
[[ $revoke_output == *"revoking this required permission will disable the plugin"* ]] ||
  fail "required-permission revoke did not warn that the plugin will be disabled" "$revoke_output"
awk -F '\t' '$2 == "revoke" && $3 == "permission-00000000000000000000000000000000" && $4 == "row-11111111111111111111111111111111" {found=1} END {exit !found}' "$calls" ||
  fail "revoke did not submit the selected opaque row handle"
pass "interactive revoke changes exactly the selected row"

set +e
unknown_output=$(printf 'y\ny\ny\nn\n' | PERMISSION_TEST_MODE=apply-fail script -qefc \
  "env PATH='$test_dir/bin:$PATH' PERMISSION_TEST_CALLS='$calls' PERMISSION_TEST_MODE=apply-fail '$ROOT/bin/omarchy-plugin-permissions' review org.example.review" /dev/null 2>&1)
unknown_status=$?
set -e
(( unknown_status != 0 )) || fail "ambiguous mutation transport failure returned success"
[[ $unknown_output == *"outcome is unknown"* ]] || fail "ambiguous mutation failure did not warn against retry" "$unknown_output"
pass "mutation transport failure reports an unknown outcome without retrying"

apply_calls_before=$(awk -F '\t' '$2 == "apply" {count++} END {print count+0}' "$calls")
set +e
poll_unknown_output=$(printf 'y\ny\ny\nn\n' | PERMISSION_TEST_MODE=poll-fail script -qefc \
  "env PATH='$test_dir/bin:$PATH' PERMISSION_TEST_CALLS='$calls' PERMISSION_TEST_MODE=poll-fail '$ROOT/bin/omarchy-plugin-permissions' review org.example.review" /dev/null 2>&1)
poll_unknown_status=$?
set -e
(( poll_unknown_status != 0 )) || fail "failure after mutation submission returned success"
[[ $poll_unknown_output == *"outcome is unknown"* ]] || fail "post-submit poll failure did not report unknown outcome" "$poll_unknown_output"
apply_calls_after=$(awk -F '\t' '$2 == "apply" {count++} END {print count+0}' "$calls")
(( apply_calls_after == apply_calls_before + 1 )) || fail "post-submit poll failure retried the mutation"
pass "failure after mutation submission reports unknown outcome without retrying"
