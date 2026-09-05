#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

stubs="$tmpdir/stubs"
mkdir -p "$stubs"

# gh is optional, so the helpers have two ways to reach the API. Both are stubbed
# and both keep a log, which is how each case says which one answered.
cat >"$stubs/gh" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$GH_LOG"
case "$1" in
auth) exit "${GH_AUTHENTICATED:-1}" ;;
api) cat "$RELEASE_JSON" ;;
esac
STUB

cat >"$stubs/curl" <<'STUB'
#!/bin/bash
for arg; do url="$arg"; done
printf '%s\n' "$url" >>"$CURL_LOG"
cat "$RELEASE_JSON"
STUB

cat >"$stubs/omarchy-cmd-present" <<'STUB'
#!/bin/bash
command -v "$1" >/dev/null
STUB

cat >"$stubs/omarchy-appimage-install" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$INSTALL_LOG"
STUB

cat >"$stubs/omarchy-notification-send" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$NOTIFY_LOG"
STUB

cat >"$stubs/systemctl" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$SYSTEMCTL_LOG"
case "$*" in
*"is-enabled"*) exit "${TIMER_ENABLED:-1}" ;;
esac
STUB

chmod +x "$stubs"/*

export GH_LOG="$tmpdir/gh.log"
export CURL_LOG="$tmpdir/curl.log"
export RELEASE_JSON="$tmpdir/release.json"
# The stubs shadow the commands under test's control; $ROOT/bin is what makes
# `source omarchy-appimage-release` resolve the way it does in a real session,
# where the bins are on PATH.
export PATH="$stubs:$ROOT/bin:$PATH"

: >"$GH_LOG"
: >"$CURL_LOG"
printf '{}\n' >"$RELEASE_JSON"

source "$ROOT/bin/omarchy-appimage-release"

# A version-agnostic pattern for the asset name, so the next release's file is
# still recognizable. Only dotted digit runs go: that is what a version looks
# like, and 64 in x86_64 is exactly what must survive.
[[ $(appimage_asset_glob "Cursor-1.2.3-x86_64.AppImage") == "Cursor-*-x86_64.AppImage" ]] ||
  fail "asset glob replaces the version" "$(appimage_asset_glob "Cursor-1.2.3-x86_64.AppImage")"
[[ $(appimage_asset_glob "nextcloud-3.16.4-x86_64.AppImage") == "nextcloud-*-x86_64.AppImage" ]] ||
  fail "asset glob replaces a three-part version" "$(appimage_asset_glob "nextcloud-3.16.4-x86_64.AppImage")"
[[ $(appimage_asset_glob "appimagetool-x86_64.AppImage") == "appimagetool-x86_64.AppImage" ]] ||
  fail "asset glob leaves an unversioned asset name alone" "$(appimage_asset_glob "appimagetool-x86_64.AppImage")"
pass "asset glob replaces the version and keeps the architecture"

assets=$(
  printf '%s\t%s\n' \
    "Cursor-1.4.0-x86_64.AppImage" "https://example.test/x86" \
    "Cursor-1.4.0-aarch64.AppImage" "https://example.test/arm"
)

selected=$(printf '%s' "$assets" | appimage_match_asset "Cursor-*-x86_64.AppImage")
[[ ${selected%%$'\t'*} == "Cursor-1.4.0-x86_64.AppImage" ]] ||
  fail "the glob matches the next version of the same asset" "$selected"
pass "the glob matches the next version of the same asset"

selected=$(printf '%s' "$assets" | appimage_match_asset "Cursor-*-aarch64.AppImage")
[[ ${selected%%$'\t'*} == "Cursor-1.4.0-aarch64.AppImage" ]] ||
  fail "the glob picks the architecture it was built from" "$selected"
pass "the glob picks the architecture it was built from"

# Installing an x86_64 image and being handed an arm64 one on the next release
# is the failure this pattern exists to prevent.
if printf '%s' "$assets" | appimage_match_asset "Krita-*-x86_64.AppImage" >/dev/null; then
  fail "a glob for another app matches nothing in this release"
fi
pass "a glob that names no asset in the release matches nothing"

# Except when there is nothing else it could mean: a project that renamed its
# only AppImage still gets updated.
renamed=$(printf '%s\t%s\n' "cursor_1.4.0_amd64.AppImage" "https://example.test/renamed")
selected=$(printf '%s' "$renamed" | appimage_match_asset "Cursor-*-x86_64.AppImage")
[[ ${selected%%$'\t'*} == "cursor_1.4.0_amd64.AppImage" ]] ||
  fail "a renamed sole asset is still the one meant" "$selected"
pass "a renamed sole asset is still the one meant"

# Publish time, not just the tag: a project on a rolling tag such as
# "continuous" or "nightly" publishes every build under the same tag, and
# comparing tags alone would call it up to date forever.
if appimage_release_moved "1.2.3" "2026-01-01T00:00:00Z" "1.2.3" "2026-01-01T00:00:00Z"; then
  fail "an unchanged release is not an update"
fi
pass "an unchanged release is not an update"

appimage_release_moved "1.2.3" "2026-01-01T00:00:00Z" "1.4.0" "2026-02-01T00:00:00Z" ||
  fail "a new tag is an update"
pass "a new tag is an update"

appimage_release_moved "continuous" "2026-01-01T00:00:00Z" "continuous" "2026-02-01T00:00:00Z" ||
  fail "a rolling tag republished is an update"
pass "a rolling tag republished is an update"

[[ $(appimage_normalize_repo "AppImage/appimagetool") == "AppImage/appimagetool" ]] ||
  fail "owner/repo is left alone"
[[ $(appimage_normalize_repo "https://github.com/AppImage/appimagetool/releases/tag/continuous") == "AppImage/appimagetool" ]] ||
  fail "a releases URL reduces to owner/repo" "$(appimage_normalize_repo "https://github.com/AppImage/appimagetool/releases/tag/continuous")"
[[ $(appimage_normalize_repo "github.com/AppImage/appimagetool.git") == "AppImage/appimagetool" ]] ||
  fail "a clone URL reduces to owner/repo"
[[ $(appimage_normalize_repo "appimagetool") == "" ]] ||
  fail "a bare word is not a repo" "$(appimage_normalize_repo "appimagetool")"
pass "a repo is recognized as owner/repo, a URL, or a clone URL"

# /releases/latest is empty for a project where every release is flagged a
# prerelease, which is how continuous and nightly AppImages ship. The newest
# non-draft is the answer there.
cat >"$RELEASE_JSON" <<'JSON'
[
  {"tag_name": "continuous", "published_at": "2026-02-01T00:00:00Z", "draft": false,
   "assets": [{"name": "Tool-x86_64.AppImage", "browser_download_url": "https://example.test/tool"}]}
]
JSON
release=$(GH_AUTHENTICATED=1 appimage_latest_release "acme/tool")
[[ $(jq -r '.tag_name' <<<"$release") == "continuous" ]] ||
  fail "the newest non-draft release answers when there is no published latest" "$release"
pass "the newest non-draft release answers when there is no published latest"

[[ -s $CURL_LOG ]] || fail "an unauthenticated gh falls back to curl" "$(cat "$GH_LOG")"
pass "an unauthenticated gh falls back to anonymous curl"

: >"$CURL_LOG"
release=$(GH_AUTHENTICATED=0 appimage_latest_release "acme/tool")
[[ $(jq -r '.tag_name' <<<"$release") == "continuous" ]] || fail "gh answers the release lookup" "$release"
[[ ! -s $CURL_LOG ]] || fail "an authenticated gh is used instead of curl" "$(cat "$CURL_LOG")"
pass "an authenticated gh carries the release lookup instead of curl"

# The command as a whole: what it decides for a tracked launcher, and what it
# hands the installer when a release moved.
home="$tmpdir/home"
mkdir -p "$home/.local/share/applications"

write_tracked_launcher() {
  cat >"$home/.local/share/applications/appimage-tool.desktop" <<DESKTOP
[Desktop Entry]
Name=Tool
Exec="$home/Applications/Tool-x86_64.AppImage"
Type=Application
X-AppImage-Source=$home/Applications/Tool-x86_64.AppImage
X-AppImage-Repo=acme/tool
X-AppImage-Release=$1
X-AppImage-Asset=Tool-x86_64.AppImage
X-AppImage-Asset-Glob=Tool-x86_64.AppImage
X-AppImage-Published=$2
DESKTOP
}

export INSTALL_LOG="$tmpdir/install.log"
export NOTIFY_LOG="$tmpdir/notify.log"

run_update() {
  : >"$INSTALL_LOG"
  : >"$NOTIFY_LOG"
  HOME="$home" GH_AUTHENTICATED=1 "$ROOT/bin/omarchy-appimage-update" "$@"
}

# Same tag, same publish time: nothing to do.
write_tracked_launcher "continuous" "2026-02-01T00:00:00Z"
run_update >"$tmpdir/out" 2>&1 || fail "update succeeds when everything is current" "$(cat "$tmpdir/out")"
grep -Fq "All tracked AppImages are current" "$tmpdir/out" ||
  fail "update reports a current install as current" "$(cat "$tmpdir/out")"
[[ ! -s $INSTALL_LOG ]] || fail "update installs nothing when nothing moved" "$(cat "$INSTALL_LOG")"
pass "update leaves a current AppImage alone"

# Same rolling tag, newer publish time: this is the case tag comparison misses.
write_tracked_launcher "continuous" "2026-01-01T00:00:00Z"
run_update --notify >"$tmpdir/out" 2>&1 || fail "update succeeds on a rolling tag" "$(cat "$tmpdir/out")"
grep -Fq "Updating Tool" "$tmpdir/out" ||
  fail "update reinstalls when a rolling tag was republished" "$(cat "$tmpdir/out")"
grep -Fxq -- "--github acme/tool --asset Tool-x86_64.AppImage --quiet" "$INSTALL_LOG" ||
  fail "update hands the installer the repo and the asset pattern" "$(cat "$INSTALL_LOG")"
grep -Fq "AppImages updated" "$NOTIFY_LOG" ||
  fail "update notifies about what it updated" "$(cat "$NOTIFY_LOG")"
pass "update reinstalls a republished rolling tag and says what changed"

# --check reports the same decision without installing anything.
write_tracked_launcher "continuous" "2026-01-01T00:00:00Z"
run_update --check >"$tmpdir/out" 2>&1 || fail "update --check succeeds" "$(cat "$tmpdir/out")"
grep -Fq "Tool: continuous -> continuous" "$tmpdir/out" ||
  fail "update --check names the release it would install" "$(cat "$tmpdir/out")"
[[ ! -s $INSTALL_LOG ]] || fail "update --check installs nothing" "$(cat "$INSTALL_LOG")"
pass "update --check reports without installing"

# A launcher with no provenance is not tracked, and an untracked machine is not
# a failure.
rm -f "$home/.local/share/applications/appimage-tool.desktop"
cat >"$home/.local/share/applications/appimage-local.desktop" <<DESKTOP
[Desktop Entry]
Name=Local
Type=Application
X-AppImage-Source=$home/Applications/Local-x86_64.AppImage
DESKTOP
run_update >"$tmpdir/out" 2>&1 || fail "update succeeds with nothing tracked" "$(cat "$tmpdir/out")"
grep -Fq "No AppImages are tracked" "$tmpdir/out" ||
  fail "update says when nothing is tracked" "$(cat "$tmpdir/out")"
pass "update ignores an AppImage installed from a local file"

# The timer is what makes tracking worth recording. Its own units are checked
# here rather than against the live user manager.
export SYSTEMCTL_LOG="$tmpdir/systemctl.log"
: >"$SYSTEMCTL_LOG"

unit_dir="$tmpdir/config/systemd/user"
XDG_CONFIG_HOME="$tmpdir/config" HOME="$home" OMARCHY_PATH="$ROOT" TIMER_ENABLED=1 \
  "$ROOT/bin/omarchy-appimage-watch" enable >"$tmpdir/out" 2>&1 ||
  fail "watch enable succeeds" "$(cat "$tmpdir/out")"

[[ -f $unit_dir/omarchy-appimage-update.service && -f $unit_dir/omarchy-appimage-update.timer ]] ||
  fail "watch enable installs both units" "$(cat "$tmpdir/out")"
grep -Fxq -e "--user enable --now omarchy-appimage-update.timer" "$SYSTEMCTL_LOG" ||
  fail "watch enable enables the timer" "$(cat "$SYSTEMCTL_LOG")"
pass "watch enable installs the shipped units and enables the timer"

timer="$ROOT/default/systemd/user/omarchy-appimage-update.timer"
grep -Fxq "OnCalendar=daily" "$timer" || fail "the timer runs daily"
grep -Fxq "Persistent=true" "$timer" || fail "the timer catches up a missed run"
grep -Fxq "RandomizedDelaySec=30m" "$timer" || fail "the timer spreads the check out"
pass "the timer runs daily, catches up a missed run, and spreads the load"

: >"$SYSTEMCTL_LOG"
XDG_CONFIG_HOME="$tmpdir/config" HOME="$home" OMARCHY_PATH="$ROOT" TIMER_ENABLED=0 \
  "$ROOT/bin/omarchy-appimage-watch" toggle >"$tmpdir/out" 2>&1 ||
  fail "watch toggle succeeds" "$(cat "$tmpdir/out")"
grep -Fxq -e "--user disable --now omarchy-appimage-update.timer" "$SYSTEMCTL_LOG" ||
  fail "watch toggle turns an enabled timer off" "$(cat "$SYSTEMCTL_LOG")"
pass "watch toggle turns an enabled timer off"
