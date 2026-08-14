#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
log_file="$test_tmp/android.log"
mkdir -p "$stub_bin"

export OMARCHY_ANDROID_TEST_LOG="$log_file"

write_stub() {
  local name="$1"
  local body="$2"

  cat >"$stub_bin/$name" <<<"$body"
  chmod +x "$stub_bin/$name"
}

log_call() {
  cat <<'STUB'
log() {
  printf "%s" "$1" >>"$OMARCHY_ANDROID_TEST_LOG"
  shift
  for arg in "$@"; do printf "\t%s" "$arg" >>"$OMARCHY_ANDROID_TEST_LOG"; done
  printf "\n" >>"$OMARCHY_ANDROID_TEST_LOG"
}
STUB
}

# The fixture reproduces real `sdkmanager --list` output: a piped table whose
# platform names carry minor versions (android-37.0), plus the decoys that must
# never be chosen -- beta platforms, -ext variants, and -rc build-tools. An
# earlier fixture used bare names like android-36 and hid a prefix-matching bug
# that picked the nonexistent "platforms;android-37". System images stop at
# android-37.0 while the newest platform is 37.1, which is how Google actually
# publishes them -- the emulator must still find an image. The bare
# "system-images;android-37;..." entry (no minor version) reproduces a second
# bug class: sorting the full path instead of just the numeric level makes
# "...android-37;..." sort above "...android-37.0;..." because the version is
# followed by ";google_apis;$abi" rather than ending the string.
write_stub mise "#!/bin/bash
$(log_call)
if [[ \$1 == \"latest\" && \$2 == \"android-sdk\" ]]; then
  # Real cmdline-tools version current on this fixture; unrelated to the
  # sdkmanager package versions below.
  echo \"22.0\"
  exit 0
fi
if [[ \$1 == \"x\" ]]; then
  # Drop 'x <tool> <tool> --' to reach the real command.
  while [[ \$# -gt 0 && \$1 != \"--\" ]]; do shift; done
  shift
  log \"\$@\"
  if [[ \$1 == \"avdmanager\" ]]; then
    # Real avdmanager probes for an optional devices.xml and prints these two
    # lines just before reporting success.
    sysimg_dir=\"/tmp/android-sdk/system-images/android-37.0/google_apis/x86_64\"
    echo \"Error: Could not load devices from \$sysimg_dir/devices.xml\" >&2
    echo \"Error: \$sysimg_dir/devices.xml\" >&2
    echo \"AVDMANAGER_REAL_STDERR_MARKER\" >&2
  fi
  if [[ \$1 == \"sdkmanager\" ]]; then
    # Real sdkmanager prints this three-line banner on stderr every run.
    echo \"WARNING: The SDK Manager CLI tool (sdkmanager) is deprecated. Use Android CLI instead.\" >&2
    echo \"The 'android' binary can also be found in the cmdline-tools directory, and 'android sdk' is the replacement for 'sdkmanager'.\" >&2
    echo \"To learn more about the Android CLI and how to use it, see the documentation (https://d.android.com/tools/agents/android-cli)\" >&2
    echo \"SDKMANAGER_REAL_STDERR_MARKER\" >&2
  fi
  if [[ \$1 == \"sdkmanager\" && \$2 == \"--list\" ]]; then
    if [[ -n \${OMARCHY_TEST_LIST_FAIL:-} ]]; then
      # Simulate a real failure (network drop, unaccepted license): no table,
      # just a genuine error the caller must not lose.
      echo \"FAKE_LIST_ERROR_MARKER: could not connect\" >&2
    else
      cat <<'PACKAGES'
Available Packages:
  Path                                             | Version      | Description
  -------                                          | -------      | -------
  build-tools;35.0.1                               | 35.0.1       | Android SDK Build-Tools 35.0.1
  build-tools;36.1.0                               | 36.1.0       | Android SDK Build-Tools 36.1
  build-tools;37.0.0                               | 37.0.0       | Android SDK Build-Tools 37
  build-tools;37.0.0-rc2                           | 37.0.0 rc2   | Android SDK Build-Tools 37-rc2
  platform-tools                                   | 36.0.1       | Android SDK Platform-Tools
  platforms;android-35                             | 2            | Android SDK Platform 35
  platforms;android-35-ext14                       | 1            | Android SDK Platform 35-ext14
  platforms;android-36.1                           | 1            | Android SDK Platform 36.1
  platforms;android-37.0                           | 2            | Android SDK Platform 37.0
  platforms;android-37.1                           | 1            | Android SDK Platform 37.1
  platforms;android-37.2-beta1                     | 1            | Android SDK Platform 37.2-beta1
  system-images;android-36;google_apis;x86_64      | 1            | Google APIs Intel x86_64 Atom System Image
  system-images;android-37;google_apis;x86_64      | 1            | Google APIs Intel x86_64 Atom System Image (bare level, no minor)
  system-images;android-37.0;google_apis;x86_64    | 1            | Google APIs Intel x86_64 Atom System Image
  system-images;android-37.0;google_apis;arm64-v8a | 1            | Google APIs ARM 64 v8a System Image
PACKAGES
    fi
  fi
  if [[ \$1 == \"sdkmanager\" && \$2 == \"--install\" && \$3 == \"platform-tools\" && -n \${OMARCHY_TEST_SDKMANAGER_INSTALL_FAIL:-} ]]; then
    echo \"FAKE_SDKMANAGER_INSTALL_FAILURE\" >&2
    exit 1
  fi
  exit 0
fi
if [[ \$1 == \"ls\" && \$2 == \"--global\" ]]; then
  # Real \`mise ls --global\` columns: Plugin, Version, Config Source, Requested.
  # The install/remove scripts key off the fourth (Requested) column.
  if [[ \$3 == \"java\" && -n \${OMARCHY_TEST_GLOBAL_JAVA:-} ]]; then
    echo \"java  \${OMARCHY_TEST_GLOBAL_JAVA}.0  ~/.config/mise/config.toml  \$OMARCHY_TEST_GLOBAL_JAVA\"
  fi
  exit 0
fi
log mise \"\$@\"
"

write_stub omarchy-pkg-add "#!/bin/bash
$(log_call)
log omarchy-pkg-add \"\$@\"
[[ -n \${OMARCHY_TEST_PKG_ADD_FAIL:-} ]] && exit 1
exit 0
"

write_stub sudo "#!/bin/bash
$(log_call)
log sudo \"\$@\"
"

write_stub uname "#!/bin/bash
echo \${OMARCHY_TEST_UNAME_ARCH:-x86_64}
"

# Two confirms now, so answer them independently.
write_stub gum "#!/bin/bash
$(log_call)
log gum \"\$@\"
case \"\$*\" in
*emulator*) exit \${OMARCHY_TEST_GUM_EMULATOR:-\${OMARCHY_TEST_GUM_EXIT:-0}} ;;
*eas*) exit \${OMARCHY_TEST_GUM_EAS:-\${OMARCHY_TEST_GUM_EXIT:-0}} ;;
esac
exit \${OMARCHY_TEST_GUM_EXIT:-0}
"

write_stub omarchy-mise-install "#!/bin/bash
$(log_call)
log omarchy-mise-install \"\$@\"
"

# A throwaway HOME keeps the run hermetic: the installer checks $HOME for an
# existing AVD, and the result must not depend on whether the developer happens
# to have one.
install_home="$test_tmp/install-home"
mkdir -p "$install_home"

# Sets $install_status instead of letting the exit code propagate: several
# scenarios below now legitimately exit non-zero (a failed download, Ctrl-C at
# a prompt), and this file runs under `set -e`, so a bare call would abort the
# whole test suite instead of letting the scenario assert on the failure.
#
# XDG_CONFIG_HOME and ANDROID_USER_HOME default empty so android_user_home
# resolves to $HOME/.android under the test's throwaway HOME, regardless of
# what is actually set in the environment running this suite. Scenarios that
# need to prove XDG_CONFIG_HOME/ANDROID_USER_HOME precedence set
# test_xdg_config_home / test_android_user_home before calling run_install,
# then clear them again afterward.
test_xdg_config_home=
test_android_user_home=

run_install() {
  : >"$log_file"
  install_status=0
  # `script` allocates a pty so the `[[ -t 0 ]]` emulator prompt is reachable.
  PATH="$stub_bin:$PATH" HOME="$install_home" \
    XDG_CONFIG_HOME="$test_xdg_config_home" ANDROID_USER_HOME="$test_android_user_home" \
    script -qec "bash '$ROOT/bin/omarchy-install-dev-env' android" /dev/null >"$test_tmp/out" 2>&1 ||
    install_status=$?
}

assert_log_line() {
  local expected="$1"
  local description="$2"

  grep -Fx -- "$expected" "$log_file" >/dev/null || fail "$description" "$(cat "$log_file")"
  pass "$description"
}

refute_log_line() {
  local unexpected="$1"
  local description="$2"

  if grep -Fx -- "$unexpected" "$log_file" >/dev/null; then
    fail "$description" "$(cat "$log_file")"
  fi
  pass "$description"
}

# One usermod call carries a comma-joined group list; the username is whatever
# runs the suite, so match on the group field only.
assert_groups_joined() {
  local groups="$1"
  local description="$2"

  grep -q "^sudo"$'\t'"usermod"$'\t'"-aG"$'\t'"$groups"$'\t' "$log_file" ||
    fail "$description" "$(cat "$log_file")"
  pass "$description"
}

# --- No global Java configured, emulator accepted -----------------------------

OMARCHY_TEST_GUM_EXIT=0 run_install

(( install_status == 0 )) || fail "install succeeds" "$(cat "$test_tmp/out")"
pass "install succeeds"

assert_log_line $'mise\tinstall\tjava@temurin-17' "installs the JDK 17 the Android Gradle Plugin needs"
assert_log_line $'mise\tuse\t--global\tjava@temurin-17' "pins global Java to 17 when nothing else is pinned"
# Pinned to the resolved current version (22.0 in this fixture), not "latest":
# tracking latest would silently repoint ANDROID_HOME at an empty SDK root the
# next time cmdline-tools cuts a release (see I1).
assert_log_line $'mise\tuse\t--global\tandroid-sdk@22.0' "pins the Android SDK command-line tools to the resolved current version"
assert_log_line $'sdkmanager\t--licenses' "accepts the SDK licenses before installing packages"
assert_log_line $'sdkmanager\t--install\tplatform-tools\tplatforms;android-37.1\tbuild-tools;37.0.0' \
  "selects the highest stable platform and build-tools, skipping beta, ext and rc variants"
assert_log_line $'omarchy-pkg-add\tandroid-udev' "installs the udev rules that let adb see USB devices"
assert_groups_joined adbusers,kvm "takes one password up front for both groups the install needs"

# The point of asking and escalating first: a multi-GB download must never sit
# between the user and a sudo prompt, where the sudo timestamp can also expire.
privileged_at=$(grep -n "^sudo"$'\t'"usermod" "$log_file" | head -1 | cut -d: -f1)
prompt_at=$(grep -n "^gum"$'\t'"confirm" "$log_file" | head -1 | cut -d: -f1)
download_at=$(grep -n "^sdkmanager"$'\t'"--install" "$log_file" | head -1 | cut -d: -f1)
[[ -n $privileged_at && -n $prompt_at && -n $download_at ]] ||
  fail "prompts and escalates before downloading" "$(cat "$log_file")"
if (( prompt_at < privileged_at && privileged_at < download_at )); then
  pass "asks about the emulator and takes sudo before any download starts"
else
  fail "asks about the emulator and takes sudo before any download starts" "$(cat "$log_file")"
fi

assert_log_line $'sdkmanager\t--install\temulator\tsystem-images;android-37.0;google_apis;x86_64' \
  "installs the newest published system image for this architecture, even when the platform is newer"
assert_log_line $'avdmanager\tcreate\tavd\t-n\tomarchy\t-k\tsystem-images;android-37.0;google_apis;x86_64\t-d\tpixel_7' \
  "creates a ready-to-run AVD"

# --force overwrites an existing AVD, destroying whatever the user installed and
# configured inside the emulator. Re-running the installer must never do that.
refute_log_line $'avdmanager\tcreate\tavd\t-n\tomarchy\t-k\tsystem-images;android-37.0;google_apis;x86_64\t-d\tpixel_7\t--force' \
  "does not pass --force when creating the AVD"


# eas-cli must go through the lazy mise wrapper. `npm install -g` would land in
# the current Node version's global root and disappear on the next Node upgrade.
assert_log_line $'omarchy-mise-install\tnpm:eas-cli\teas' \
  "adds eas through the mise wrapper rather than npm install -g"

# Nothing should download while the screen is blank or the size is a surprise.
grep -q "Fetching Google's package index" "$test_tmp/out" ||
  fail "announces the silent package-index fetch" "$(cat "$test_tmp/out")"
pass "announces the silent package-index fetch"

grep -q "Downloading about 3 GB" "$test_tmp/out" ||
  fail "warns that accepting the emulator means a ~3 GB download" "$(cat "$test_tmp/out")"
pass "warns that accepting the emulator means a ~3 GB download"

notice_at=$(grep -n "Downloading about" "$test_tmp/out" | head -1 | cut -d: -f1)
fetching_at=$(grep -n "Fetching Google's package index" "$test_tmp/out" | head -1 | cut -d: -f1)
installing_at=$(grep -n "^Installing platforms" "$test_tmp/out" | head -1 | cut -d: -f1)
if (( notice_at < fetching_at && fetching_at < installing_at )); then
  pass "states the download size, then narrates the quiet phase, before installing"
else
  fail "states the download size, then narrates the quiet phase, before installing" "$(cat "$test_tmp/out")"
fi

grep -q "npx create-expo-app" "$test_tmp/out" ||
  fail "points at the Expo local build flow on success" "$(cat "$test_tmp/out")"
pass "points at the Expo local build flow on success"

# The banner is noise on every sdkmanager call, but the filter must be surgical:
# real stderr has to survive, or a failure like "Failed to find package" is lost.
if grep -q "sdkmanager) is deprecated" "$test_tmp/out"; then
  fail "hides the sdkmanager deprecation banner" "$(cat "$test_tmp/out")"
fi
pass "hides the sdkmanager deprecation banner"

grep -q "SDKMANAGER_REAL_STDERR_MARKER" "$test_tmp/out" ||
  fail "still lets genuine sdkmanager stderr through" "$(cat "$test_tmp/out")"
pass "still lets genuine sdkmanager stderr through"

# A maintainer will object to auto-accepting a third-party EULA with no
# disclosure, so this must be visible, not just silently piped.
grep -q "Accepting Google's Android SDK license agreements" "$test_tmp/out" ||
  fail "discloses that it is auto-accepting the SDK licenses" "$(cat "$test_tmp/out")"
pass "discloses that it is auto-accepting the SDK licenses"

# avdmanager reports success right after two alarming Error: lines about a
# devices.xml it only probes for. The AVD is correct; the noise is not.
if grep -q "Could not load devices from" "$test_tmp/out"; then
  fail "hides the avdmanager devices.xml probe error" "$(cat "$test_tmp/out")"
fi
pass "hides the avdmanager devices.xml probe error"

grep -q "AVDMANAGER_REAL_STDERR_MARKER" "$test_tmp/out" ||
  fail "still lets genuine avdmanager stderr through" "$(cat "$test_tmp/out")"
pass "still lets genuine avdmanager stderr through"

# --- Re-running with an AVD already present ------------------------------------

mkdir -p "$install_home/.android/avd/omarchy.avd"
: >"$install_home/.android/avd/omarchy.ini"

OMARCHY_TEST_GUM_EXIT=0 run_install

(( install_status == 0 )) || fail "install succeeds when the AVD already exists" "$(cat "$test_tmp/out")"
pass "install succeeds when the AVD already exists"

if grep -q $'^avdmanager' "$log_file"; then
  fail "keeps an existing AVD instead of recreating it" "$(cat "$log_file")"
fi
pass "keeps an existing AVD instead of recreating it"

grep -q "already exists" "$test_tmp/out" ||
  fail "says the existing AVD was kept" "$(cat "$test_tmp/out")"
pass "says the existing AVD was kept"

assert_log_line $'sdkmanager\t--install\tplatform-tools\tplatforms;android-37.1\tbuild-tools;37.0.0' \
  "re-running is otherwise idempotent and still installs the SDK packages"

rm -f "$install_home/.android/avd/omarchy.ini"

# --- Emulator declined --------------------------------------------------------

OMARCHY_TEST_GUM_EXIT=1 run_install

(( install_status == 0 )) || fail "install succeeds when the emulator is declined" "$(cat "$test_tmp/out")"
pass "install succeeds when the emulator is declined"

assert_log_line $'sdkmanager\t--install\tplatform-tools\tplatforms;android-37.1\tbuild-tools;37.0.0' \
  "still installs the base SDK when the emulator is declined"
assert_groups_joined adbusers "does not add the user to kvm when the emulator is declined"
grep -q "Downloading about 600 MB" "$test_tmp/out" ||
  fail "quotes the smaller download when the emulator is declined" "$(cat "$test_tmp/out")"
pass "quotes the smaller download when the emulator is declined"
refute_log_line $'sdkmanager\t--install\temulator\tsystem-images;android-37.0;google_apis;x86_64' \
  "skips the emulator download when declined"
if grep -q $'^avdmanager' "$log_file"; then
  fail "skips AVD creation when the emulator is declined" "$(cat "$log_file")"
fi
pass "skips AVD creation when the emulator is declined"

# --- Emulator accepted, eas declined ------------------------------------------

OMARCHY_TEST_GUM_EMULATOR=0 OMARCHY_TEST_GUM_EAS=1 run_install

(( install_status == 0 )) || fail "install succeeds when eas is declined" "$(cat "$test_tmp/out")"
pass "install succeeds when eas is declined"

refute_log_line $'omarchy-mise-install\tnpm:eas-cli\teas' \
  "does not add the eas command when it is declined"
assert_log_line $'sdkmanager\t--install\temulator\tsystem-images;android-37.0;google_apis;x86_64' \
  "declining eas still installs the emulator"

# --- Existing global Java is preserved ----------------------------------------

OMARCHY_TEST_GLOBAL_JAVA=26.0.2 OMARCHY_TEST_GUM_EXIT=1 run_install

(( install_status == 0 )) || fail "install succeeds alongside an existing global Java pin" "$(cat "$test_tmp/out")"
pass "install succeeds alongside an existing global Java pin"

refute_log_line $'mise\tuse\t--global\tjava@temurin-17' \
  "does not downgrade a Java version the user already pinned globally"
grep -q "mise use java@temurin-17" "$test_tmp/out" ||
  fail "explains how to pin JDK 17 per project" "$(cat "$test_tmp/out")"
pass "explains how to pin JDK 17 per project"
assert_log_line $'mise\tuse\t--global\tandroid-sdk@22.0' "still installs the Android SDK alongside the existing Java"

# --- Removal ------------------------------------------------------------------

write_stub omarchy-pkg-drop "#!/bin/bash
$(log_call)
log omarchy-pkg-drop \"\$@\"
"

# Route the Android user home through XDG_CONFIG_HOME, exactly like a real XDG
# system and like the installer's own android_user_home resolution, so removal
# is proven to target the same directory the tools actually use -- not a
# hardcoded $HOME/.android that would miss the real data entirely.
fake_home="$test_tmp/home"
fake_xdg_config="$test_tmp/xdg-config"
mkdir -p "$fake_xdg_config/.android/avd/omarchy.avd"
: >"$fake_xdg_config/.android/avd/omarchy.ini"

# A hand-made AVD and adb's per-machine keypair must both survive removal:
# wiping them would destroy a user-configured emulator or revoke adb
# authorization on every device the user has ever paired. Only what this
# feature created (the 'omarchy' AVD) may be removed.
mkdir -p "$fake_xdg_config/.android/avd/my-own-avd.avd"
: >"$fake_xdg_config/.android/avd/my-own-avd.ini"
: >"$fake_xdg_config/.android/adbkey"
: >"$fake_xdg_config/.android/adbkey.pub"

# The lazy eas wrapper the installer can create must not linger either (I7).
mkdir -p "$fake_home/.local/bin"
: >"$fake_home/.local/bin/eas"
chmod +x "$fake_home/.local/bin/eas"

: >"$log_file"
OMARCHY_TEST_GLOBAL_JAVA=temurin-17 \
  PATH="$stub_bin:$PATH" HOME="$fake_home" XDG_CONFIG_HOME="$fake_xdg_config" \
  bash "$ROOT/bin/omarchy-remove-dev-env" android >"$test_tmp/remove.out" 2>&1 ||
  fail "removing the Android environment succeeds" "$(cat "$test_tmp/remove.out")"
pass "removing the Android environment succeeds"

assert_log_line $'mise\tuninstall\tandroid-sdk\t--all' \
  "uninstalls every Android SDK version, which also clears the packages sdkmanager put inside it"
assert_log_line $'mise\trm\t-g\tandroid-sdk' "unpins the Android SDK from the global mise config"
assert_log_line $'omarchy-pkg-drop\tandroid-udev' "drops the udev rules package"

if [[ -e $fake_xdg_config/.android/avd/omarchy.avd || -e $fake_xdg_config/.android/avd/omarchy.ini ]]; then
  fail "deletes the 'omarchy' AVD this feature created" "$(ls -laR "$fake_xdg_config/.android")"
fi
pass "deletes the 'omarchy' AVD this feature created"

if [[ ! -e $fake_xdg_config/.android/avd/my-own-avd.avd ]]; then
  fail "leaves a hand-made AVD alone" "$(ls -laR "$fake_xdg_config/.android")"
fi
pass "leaves a hand-made AVD alone"

if [[ ! -e $fake_xdg_config/.android/adbkey || ! -e $fake_xdg_config/.android/adbkey.pub ]]; then
  fail "leaves adbkey/adbkey.pub alone so adb stays authorized on paired devices" \
    "$(ls -laR "$fake_xdg_config/.android")"
fi
pass "leaves adbkey/adbkey.pub alone so adb stays authorized on paired devices"

if [[ -e $fake_home/.android ]]; then
  fail 'does not touch $HOME/.android when XDG_CONFIG_HOME points elsewhere' "$(ls -la "$fake_home")"
fi
pass 'does not touch $HOME/.android when XDG_CONFIG_HOME points elsewhere'

if [[ -e $fake_home/.local/bin/eas ]]; then
  fail "removes the eas wrapper the installer may have left behind" "$(ls -la "$fake_home/.local/bin")"
fi
pass "removes the eas wrapper the installer may have left behind"

assert_log_line $'mise\tuninstall\tnpm:eas-cli\t--all' "uninstalls the eas-cli mise install"
assert_log_line $'mise\trm\t-g\tnpm:eas-cli' "unpins eas-cli from the global mise config"

assert_log_line $'mise\trm\t-g\tjava' \
  "unpins global Java when it is still exactly what this installer pinned (temurin-17)"

refute_log_line $'mise\tuninstall\tjava\t--all' "leaves Java installed, since it is its own menu entry"

# --- Removal leaves a Java pin alone when it is not what the installer set ----

fake_home2="$test_tmp/home2"
fake_xdg_config2="$test_tmp/xdg-config2"
mkdir -p "$fake_xdg_config2/.android/avd/omarchy.avd"
: >"$fake_xdg_config2/.android/avd/omarchy.ini"

: >"$log_file"
OMARCHY_TEST_GLOBAL_JAVA=21.0.5 \
  PATH="$stub_bin:$PATH" HOME="$fake_home2" XDG_CONFIG_HOME="$fake_xdg_config2" \
  bash "$ROOT/bin/omarchy-remove-dev-env" android >"$test_tmp/remove2.out" 2>&1 ||
  fail "removal still succeeds when global Java is pinned to something else" "$(cat "$test_tmp/remove2.out")"
pass "removal still succeeds when global Java is pinned to something else"

refute_log_line $'mise\trm\t-g\tjava' \
  "does not unpin a Java version the user pinned themselves after installing Android"

# --- Global Java already pinned to exactly temurin-17 --------------------------

# I4: comparing "is anything pinned" instead of the resolved version wrongly
# told a user with the correct Java already pinned that theirs was being kept
# in favor of some other version. Nothing should be said, and no re-pin issued.
OMARCHY_TEST_GLOBAL_JAVA=temurin-17 OMARCHY_TEST_GUM_EXIT=1 run_install

(( install_status == 0 )) || fail "install succeeds when Java is already pinned to temurin-17" "$(cat "$test_tmp/out")"
pass "install succeeds when Java is already pinned to temurin-17"

if grep -q "Keeping your existing global Java" "$test_tmp/out"; then
  fail "says nothing about Java when the existing pin already matches temurin-17" "$(cat "$test_tmp/out")"
fi
pass "says nothing about Java when the existing pin already matches temurin-17"

refute_log_line $'mise\tuse\t--global\tjava@temurin-17' \
  "does not re-pin Java when it is already exactly temurin-17"

# --- Ctrl-C at the first prompt aborts before any side effects -----------------

# I6: gum confirm exits 130 on Ctrl-C. A bare `&&` treats that the same as a
# "no" answer and falls straight through into a multi-GB download.
OMARCHY_TEST_GUM_EXIT=130 run_install

(( install_status != 0 )) || fail "aborts instead of exiting 0 on Ctrl-C" "$(cat "$test_tmp/out")"
pass "aborts instead of exiting 0 on Ctrl-C"

grep -q "Aborted" "$test_tmp/out" ||
  fail "tells the user it aborted on Ctrl-C" "$(cat "$test_tmp/out")"
pass "tells the user it aborted on Ctrl-C"

refute_log_line $'omarchy-pkg-add\tandroid-udev' \
  "does not touch device permissions after a Ctrl-C abort"
refute_log_line $'mise\tinstall\tjava@temurin-17' \
  "does not install anything after a Ctrl-C abort"

# --- A failing sdkmanager --install is reported, not swallowed -----------------

# C2: nothing used to check this exit status, so a dropped connection or a
# withdrawn package left the script printing success anyway.
OMARCHY_TEST_GUM_EXIT=1 OMARCHY_TEST_SDKMANAGER_INSTALL_FAIL=1 run_install

(( install_status != 0 )) || fail "reports failure when sdkmanager --install fails" "$(cat "$test_tmp/out")"
pass "reports failure when sdkmanager --install fails"

grep -q "FAKE_SDKMANAGER_INSTALL_FAILURE" "$test_tmp/out" ||
  fail "surfaces the real sdkmanager --install error" "$(cat "$test_tmp/out")"
pass "surfaces the real sdkmanager --install error"

if grep -q "adb --version" "$test_tmp/out"; then
  fail "does not print the success message after a failed sdkmanager --install" "$(cat "$test_tmp/out")"
fi
pass "does not print the success message after a failed sdkmanager --install"

# --- An empty --list is reported with the real stderr, not silenced -----------

# I2: 2>/dev/null on the whole `sdk sdkmanager --list` call discarded the
# already-filtered real stderr from the sdk() wrapper, so a network failure or
# an unaccepted license produced no diagnostic at all.
OMARCHY_TEST_GUM_EXIT=1 OMARCHY_TEST_LIST_FAIL=1 run_install

(( install_status != 0 )) || fail "reports failure when the package list comes back empty" "$(cat "$test_tmp/out")"
pass "reports failure when the package list comes back empty"

grep -q "Could not read the available Android packages" "$test_tmp/out" ||
  fail "explains that the package list could not be read" "$(cat "$test_tmp/out")"
pass "explains that the package list could not be read"

grep -q "FAKE_LIST_ERROR_MARKER" "$test_tmp/out" ||
  fail "surfaces the real stderr behind an empty package list" "$(cat "$test_tmp/out")"
pass "surfaces the real stderr behind an empty package list"

# --- A failing omarchy-pkg-add is reported but does not abort the install -----

# Device-group setup is best-effort (fixable later from a terminal where sudo
# can prompt); it must not block getting a working SDK and adb.
OMARCHY_TEST_GUM_EXIT=1 OMARCHY_TEST_PKG_ADD_FAIL=1 run_install

(( install_status == 0 )) || fail "still completes the SDK install when device-group setup fails" "$(cat "$test_tmp/out")"
pass "still completes the SDK install when device-group setup fails"

grep -q "Could not configure device access" "$test_tmp/out" ||
  fail "reports that device-group setup failed" "$(cat "$test_tmp/out")"
pass "reports that device-group setup failed"

assert_log_line $'sdkmanager\t--install\tplatform-tools\tplatforms;android-37.1\tbuild-tools;37.0.0' \
  "still installs the SDK packages after a failed device-group setup"

# The first warning is printed before the multi-GB download and is long
# off-screen by the time the install finishes; it must be re-stated in the
# closing block or the last thing the user sees is unqualified success.
grep -q "Could not configure device access earlier" "$test_tmp/out" ||
  fail "restates the device-access warning in the closing block" "$(cat "$test_tmp/out")"
pass "restates the device-access warning in the closing block"

first_warning_at=$(grep -n "Could not configure device access\." "$test_tmp/out" | head -1 | cut -d: -f1)
success_at=$(grep -n "adb --version" "$test_tmp/out" | head -1 | cut -d: -f1)
restated_at=$(grep -n "Could not configure device access earlier" "$test_tmp/out" | head -1 | cut -d: -f1)
if (( first_warning_at < success_at && success_at < restated_at )); then
  pass "the restated warning comes after the success message, not just a duplicate of the first"
else
  fail "the restated warning comes after the success message, not just a duplicate of the first" \
    "$(cat "$test_tmp/out")"
fi

# --- Unsupported architecture skips the emulator instead of guessing ----------

OMARCHY_TEST_GUM_EXIT=0 OMARCHY_TEST_UNAME_ARCH=riscv64 run_install

(( install_status == 0 )) || fail "install still succeeds on an unsupported architecture" "$(cat "$test_tmp/out")"
pass "install still succeeds on an unsupported architecture"

grep -q "No system image found for" "$test_tmp/out" ||
  fail "explains that no system image is available for this architecture" "$(cat "$test_tmp/out")"
pass "explains that no system image is available for this architecture"

if grep -q $'^avdmanager' "$log_file"; then
  fail "does not attempt AVD creation on an unsupported architecture" "$(cat "$log_file")"
fi
pass "does not attempt AVD creation on an unsupported architecture"

# --- The installer's AVD guard honours XDG_CONFIG_HOME, not just $HOME -------

# C1 regression guard for the INSTALL side specifically: every scenario above
# runs with XDG_CONFIG_HOME cleared, so a hardcoded $HOME/.android guard would
# pass every one of them. The marker here lives ONLY under
# $XDG_CONFIG_HOME/.android; a script that still hardcoded $HOME/.android (or
# lost the resolution block entirely) would never see it, try to recreate the
# AVD, and never say "already exists".
xdg_fixture="$test_tmp/xdg-fixture"
mkdir -p "$xdg_fixture/.android/avd/omarchy.avd"
: >"$xdg_fixture/.android/avd/omarchy.ini"

test_xdg_config_home="$xdg_fixture"
OMARCHY_TEST_GUM_EXIT=0 run_install
test_xdg_config_home=

(( install_status == 0 )) || fail "install succeeds when the AVD already exists under XDG_CONFIG_HOME" "$(cat "$test_tmp/out")"
pass "install succeeds when the AVD already exists under XDG_CONFIG_HOME"

if grep -q $'^avdmanager' "$log_file"; then
  fail "honours XDG_CONFIG_HOME for the AVD guard instead of hardcoding \$HOME/.android" "$(cat "$log_file")"
fi
pass "honours XDG_CONFIG_HOME for the AVD guard instead of hardcoding \$HOME/.android"

grep -q "already exists" "$test_tmp/out" ||
  fail "reports the AVD under XDG_CONFIG_HOME as already present" "$(cat "$test_tmp/out")"
pass "reports the AVD under XDG_CONFIG_HOME as already present"

grep -qF "$xdg_fixture/.android/avd/omarchy.avd" "$test_tmp/out" ||
  fail "names the XDG_CONFIG_HOME-resolved path in the already-exists message" "$(cat "$test_tmp/out")"
pass "names the XDG_CONFIG_HOME-resolved path in the already-exists message"

# --- ANDROID_USER_HOME takes precedence over XDG_CONFIG_HOME -----------------

# Both env vars are set here; the real tools (and this script) resolve
# ANDROID_USER_HOME first. The marker sits only under ANDROID_USER_HOME; a
# decoy $XDG_CONFIG_HOME/.android exists but deliberately has no omarchy.ini,
# so a resolution that checked XDG first (or ignored ANDROID_USER_HOME
# entirely) would miss the AVD and try to recreate it.
android_user_home_fixture="$test_tmp/android-user-home-fixture"
mkdir -p "$android_user_home_fixture/avd/omarchy.avd"
: >"$android_user_home_fixture/avd/omarchy.ini"

decoy_xdg="$test_tmp/decoy-xdg"
mkdir -p "$decoy_xdg/.android"

test_xdg_config_home="$decoy_xdg"
test_android_user_home="$android_user_home_fixture"
OMARCHY_TEST_GUM_EXIT=0 run_install
test_xdg_config_home=
test_android_user_home=

(( install_status == 0 )) || fail "install succeeds when the AVD already exists under ANDROID_USER_HOME" "$(cat "$test_tmp/out")"
pass "install succeeds when the AVD already exists under ANDROID_USER_HOME"

if grep -q $'^avdmanager' "$log_file"; then
  fail "honours ANDROID_USER_HOME ahead of XDG_CONFIG_HOME for the AVD guard" "$(cat "$log_file")"
fi
pass "honours ANDROID_USER_HOME ahead of XDG_CONFIG_HOME for the AVD guard"

grep -qF "$android_user_home_fixture/avd/omarchy.avd" "$test_tmp/out" ||
  fail "names the ANDROID_USER_HOME-resolved path, not the XDG one, in the already-exists message" \
    "$(cat "$test_tmp/out")"
pass "names the ANDROID_USER_HOME-resolved path, not the XDG one, in the already-exists message"
