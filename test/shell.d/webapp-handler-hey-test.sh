#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT
mkdir -p "$tmp_dir/bin"

# The handler ends in an exec, so stand in for the launcher to see the URL it
# would have opened.
printf '#!/bin/bash\necho "$1"\n' >"$tmp_dir/bin/omarchy-launch-webapp"
chmod +x "$tmp_dir/bin/omarchy-launch-webapp"

open_url() {
  PATH="$tmp_dir/bin:$PATH" "$ROOT/bin/omarchy-webapp-handler-hey" "$@"
}

# A mailto: link carrying a subject used to fold the whole query into "to=",
# leaving a second "?" that HEY reads as part of the address. Assert on the
# separator: the address alone lands in the right place either way, so only
# the "&" shows the parameters survived as parameters.
url=$(open_url "mailto:someone@example.com?subject=Hello")
[[ $url == "https://app.hey.com/messages/new?to=someone@example.com&subject=Hello" ]] ||
  fail "a mailto subject reaches HEY as its own parameter" "$url"
pass "mailto with a subject keeps the address and subject apart"

url=$(open_url "mailto:a@example.com?subject=Hi&body=Text")
[[ $url == "https://app.hey.com/messages/new?to=a@example.com&subject=Hi&body=Text" ]] ||
  fail "every mailto parameter is carried over" "$url"
pass "mailto parameters past the first survive"

url=$(open_url "mailto:someone@example.com")
[[ $url == "https://app.hey.com/messages/new?to=someone@example.com" ]] ||
  fail "a bare mailto address still opens addressed" "$url"
pass "mailto without parameters is unchanged"

# "mailto:?to=someone@example.com" carries the address as a parameter, which
# must not become a second "to=".
url=$(open_url "mailto:?to=someone@example.com&subject=Hello")
[[ $url == "https://app.hey.com/messages/new?to=someone@example.com&subject=Hello" ]] ||
  fail "the mailto parameter form addresses the message once" "$url"
pass "mailto carrying the address as a parameter is not doubled"

url=$(open_url "")
[[ $url == "https://app.hey.com" ]] ||
  fail "a call with no mailto URL opens HEY itself" "$url"
pass "a non-mailto invocation opens HEY unchanged"
