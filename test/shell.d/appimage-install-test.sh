#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

home="$tmpdir/home"
stubs="$tmpdir/stubs"
mkdir -p "$home" "$stubs"

for stub in omarchy-pkg-add gtk-update-icon-cache update-desktop-database; do
  printf '#!/bin/bash\nexit 0\n' >"$stubs/$stub"
done

# gum only runs when no path is given, and every case here names one. A stub
# that fails is how the run says so instead of blocking on a picker.
printf '#!/bin/bash\necho "gum must not run" >&2\nexit 1\n' >"$stubs/gum"
chmod +x "$stubs"/*

apps_dir="$home/Applications"
desktop_dir="$home/.local/share/applications"
icon_dir="$home/.local/share/icons/hicolor/256x256/apps"

# A stand-in for the real thing: --appimage-extract unpacks the embedded
# squashfs into ./squashfs-root, which is the only part of an AppImage the
# installer reads. Any other argument makes it behave like the app it stands
# for and record what it was handed.
new_appimage() {
  local file="$1" payload="$2"

  cat >"$file" <<SCRIPT
#!/bin/bash
if [[ \$1 == "--appimage-extract" ]]; then
  cp -r "$payload" squashfs-root
  exit 0
fi
printf '%s\n' "\$@" >>"\${OMARCHY_TEST_ARGV:-/dev/null}"
SCRIPT
  chmod +x "$file"
}

install_appimage() {
  HOME="$home" PATH="$stubs:$ROOT/bin:$PATH" "$ROOT/bin/omarchy-appimage-install" "$@"
}

desktop_value() {
  awk -v key="$2" 'index($0, key "=") == 1 { print substr($0, length(key) + 2); exit }' "$1"
}

# An image that ships a launcher of its own: the name, categories, MIME types
# and the %f the installer has to carry over all come from here.
payload="$tmpdir/payload-editor"
mkdir -p "$payload/usr/share/icons/hicolor/48x48/apps" "$payload/usr/share/icons/hicolor/512x512/apps"
cat >"$payload/photoeditor.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=Photo Editor
GenericName=Editor
Comment=Edits photos
Exec=AppRun %f
Icon=photoeditor
Categories=Graphics;GTK;
MimeType=image/png;image/jpeg;
Terminal=false
DESKTOP
printf 'small' >"$payload/usr/share/icons/hicolor/48x48/apps/photoeditor.png"
printf 'this is the 512px icon' >"$payload/usr/share/icons/hicolor/512x512/apps/photoeditor.png"

new_appimage "$tmpdir/PhotoEditor-1.2.3-x86_64.AppImage" "$payload"
install_appimage "$tmpdir/PhotoEditor-1.2.3-x86_64.AppImage" >"$tmpdir/out" 2>"$tmpdir/err" ||
  fail "appimage install succeeds" "$(cat "$tmpdir/out" "$tmpdir/err")"

desktop="$desktop_dir/appimage-photo-editor.desktop"
[[ -f $desktop ]] || fail "appimage install derives the launcher id from the embedded name" "$(ls -A "$desktop_dir")"
pass "appimage install derives the launcher id from the embedded name"

[[ -f $apps_dir/PhotoEditor-1.2.3-x86_64.AppImage && -x $apps_dir/PhotoEditor-1.2.3-x86_64.AppImage ]] ||
  fail "appimage install copies the image into ~/Applications as an executable"
pass "appimage install copies the image into ~/Applications as an executable"

[[ $(desktop_value "$desktop" Exec) == "\"$apps_dir/PhotoEditor-1.2.3-x86_64.AppImage\" %f" ]] ||
  fail "appimage install quotes the image path and keeps the field code" "$(desktop_value "$desktop" Exec)"
pass "appimage install quotes the image path and keeps the embedded field code"

[[ $(desktop_value "$desktop" X-AppImage-Source) == "$apps_dir/PhotoEditor-1.2.3-x86_64.AppImage" ]] ||
  fail "appimage install records the image it installed" "$(cat "$desktop")"
pass "appimage install records the image it installed"

[[ $(desktop_value "$desktop" Name) == "Photo Editor" ]] || fail "appimage install keeps the embedded name"
[[ $(desktop_value "$desktop" Comment) == "Edits photos" ]] || fail "appimage install keeps the embedded comment"
[[ $(desktop_value "$desktop" Categories) == "Graphics;GTK;" ]] || fail "appimage install keeps the embedded categories"
[[ $(desktop_value "$desktop" MimeType) == "image/png;image/jpeg;" ]] || fail "appimage install keeps the embedded MIME types"
pass "appimage install carries the embedded launcher fields over"

# AppImages ship the same icon at several resolutions and the paths do not say
# which is which, so the installer picks by byte size. A 48px icon in the
# launcher is a blurry row in the app search.
[[ $(desktop_value "$desktop" Icon) == "appimage-photo-editor" ]] ||
  fail "appimage install points the launcher at the installed icon" "$(desktop_value "$desktop" Icon)"
[[ $(<"$icon_dir/appimage-photo-editor.png") == "this is the 512px icon" ]] ||
  fail "appimage install installs the highest-resolution icon in the image"
pass "appimage install installs the highest-resolution icon in the image"

# No launcher inside the image at all: the file name is the only name there is,
# and its version and architecture are not part of it.
payload_bare="$tmpdir/payload-bare"
mkdir -p "$payload_bare"
new_appimage "$tmpdir/Weird_Tool-2.0-x86_64.AppImage" "$payload_bare"
install_appimage "$tmpdir/Weird_Tool-2.0-x86_64.AppImage" >/dev/null 2>&1 ||
  fail "appimage install handles an image with no embedded launcher"

bare="$desktop_dir/appimage-weird-tool.desktop"
[[ -f $bare ]] || fail "appimage install slugs a name out of the file name" "$(ls -A "$desktop_dir")"
[[ $(desktop_value "$bare" Name) == "Weird_Tool" ]] ||
  fail "appimage install strips the version and architecture off the file name" "$(desktop_value "$bare" Name)"
[[ $(desktop_value "$bare" Icon) == "application-x-executable" ]] ||
  fail "appimage install falls back to a generic icon" "$(desktop_value "$bare" Icon)"
[[ $(desktop_value "$bare" Exec) == "\"$apps_dir/Weird_Tool-2.0-x86_64.AppImage\"" ]] ||
  fail "appimage install writes no field code when the image declares none" "$(desktop_value "$bare" Exec)"
pass "appimage install names an image that ships no launcher after its file"

# The Exec value is quoted per the Exec spec and then escaped again by the file
# syntax, exactly as omarchy-webapp-install does it: left single, GLib reads \$
# as an invalid escape and refuses the whole entry, and a bare % is eaten as a
# field code.
odd_source="$tmpdir/odd"
mkdir -p "$odd_source"
new_appimage "$odd_source/Odd \$App \"quoted\" 50%.AppImage" "$payload_bare"
install_appimage "$odd_source/Odd \$App \"quoted\" 50%.AppImage" >/dev/null 2>&1 ||
  fail "appimage install accepts a path holding Exec metacharacters"

odd="$desktop_dir/appimage-odd-app-quoted-50.desktop"
[[ -f $odd ]] || fail "appimage install slugs metacharacters out of the id" "$(ls -A "$desktop_dir")"
[[ $(desktop_value "$odd" Exec) == "\"$apps_dir/Odd \\\\\$App \\\\\"quoted\\\\\" 50%%.AppImage\"" ]] ||
  fail "appimage install escapes Exec metacharacters in the image path" "$(desktop_value "$odd" Exec)"
pass "appimage install escapes Exec metacharacters in the image path"

# The property the escaping exists for: a value lifted out of a downloaded image
# must not be able to start a second key line.
payload_inject="$tmpdir/payload-inject"
mkdir -p "$payload_inject"
{
  printf '[Desktop Entry]\n'
  printf 'Type=Application\n'
  printf 'Name=Inject\\nExec=evil\n'
  printf 'Exec=AppRun\n'
} >"$payload_inject/inject.desktop"
new_appimage "$tmpdir/Inject-1.0-x86_64.AppImage" "$payload_inject"
install_appimage "$tmpdir/Inject-1.0-x86_64.AppImage" >/dev/null 2>&1 ||
  fail "appimage install survives an embedded name holding an escape"

inject=$(printf '%s\n' "$desktop_dir"/appimage-inject*.desktop | head -1)
(( $(grep -c '^Exec=' "$inject") == 1 )) ||
  fail "an escape in an embedded name cannot inject a second Exec" "$(cat "$inject")"
pass "an escape in an embedded name cannot inject a second Exec"

# Reinstalling the same app from a newer file: the launcher moves to the new
# image and the superseded one is deleted rather than left behind under its own
# versioned name.
new_appimage "$tmpdir/PhotoEditor-1.3.0-x86_64.AppImage" "$payload"
install_appimage "$tmpdir/PhotoEditor-1.3.0-x86_64.AppImage" >/dev/null 2>&1 ||
  fail "appimage install reinstalls over an existing launcher"

[[ $(desktop_value "$desktop" X-AppImage-Source) == "$apps_dir/PhotoEditor-1.3.0-x86_64.AppImage" ]] ||
  fail "appimage reinstall repoints the launcher at the new image" "$(desktop_value "$desktop" X-AppImage-Source)"
[[ ! -e $apps_dir/PhotoEditor-1.2.3-x86_64.AppImage ]] ||
  fail "appimage reinstall deletes the superseded image" "$(ls -A "$apps_dir")"
pass "appimage reinstall repoints the launcher and deletes the superseded image"

# Removal has to take all three: the launcher, the icon, and the image the
# launcher names.
remove_appimage() {
  HOME="$home" PATH="$stubs:$ROOT/bin:$PATH" OMARCHY_REMOVE_NOTIFY=false "$ROOT/bin/omarchy-appimage-remove" "$@"
}

remove_appimage "Photo Editor" >/dev/null 2>&1 || fail "appimage remove accepts a name"
[[ ! -e $desktop ]] || fail "appimage remove deletes the launcher"
[[ ! -e $icon_dir/appimage-photo-editor.png ]] || fail "appimage remove deletes the icon"
[[ ! -e $apps_dir/PhotoEditor-1.3.0-x86_64.AppImage ]] || fail "appimage remove deletes the image"
pass "appimage remove deletes the launcher, the icon, and the image"

remove_appimage "appimage-weird-tool" >/dev/null 2>&1 || fail "appimage remove accepts a launcher id"
[[ ! -e $bare ]] || fail "appimage remove addresses an app by its launcher id"
pass "appimage remove addresses an app by its launcher id"

if remove_appimage "Not Installed" >"$tmpdir/out" 2>&1; then
  fail "appimage remove refuses a name it never indexed" "$(cat "$tmpdir/out")"
fi
grep -Fq "No installed AppImage matches" "$tmpdir/out" ||
  fail "appimage remove says which name it could not find" "$(cat "$tmpdir/out")"
pass "appimage remove refuses a name it never indexed"
