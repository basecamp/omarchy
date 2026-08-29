#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

cat >"$tmp_dir/setsid" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "$*" >"$TEST_LOG"
printf '%s\n' "$@" >"$TEST_ARGV"
SCRIPT
chmod +x "$tmp_dir/setsid"

export TEST_LOG="$tmp_dir/log"
export TEST_ARGV="$tmp_dir/launch-argv"
export PATH="$tmp_dir:$ROOT/bin:$PATH"

"$ROOT/bin/omarchy-launch-floating-terminal-with-presentation" "echo hello"

launch=$(<"$TEST_LOG")
[[ $launch == *"xdg-terminal-exec --app-id=org.omarchy.terminal"* ]] || fail "floating terminal launches Omarchy terminal" "$launch"
pass "floating terminal launches Omarchy terminal"

# The wrapper runs its caller's words rather than rebuilding them into shell
# source, so a value that arrives as one argument stays one argument whatever it
# holds. Run the script the wrapper actually built, not a copy of it: a copy
# would keep passing if the real one started reparsing its arguments.
cat >"$tmp_dir/omarchy-show-logo" <<'STUB'
#!/bin/bash
exit 0
STUB
cp "$tmp_dir/omarchy-show-logo" "$tmp_dir/omarchy-show-done"

cat >"$tmp_dir/record-argv" <<'STUB'
#!/bin/bash
printf '%s\n' "$#" "$@" >"$OMARCHY_TEST_RECORDED"
STUB

chmod +x "$tmp_dir/omarchy-show-logo" "$tmp_dir/omarchy-show-done" "$tmp_dir/record-argv"

export OMARCHY_TEST_RECORDED="$tmp_dir/recorded"
canary="$tmp_dir/canary"
hostile="a';touch $canary;'b"

"$ROOT/bin/omarchy-launch-floating-terminal-with-presentation" record-argv "$hostile" "two words"

# What the wrapper handed the terminal, from `-e` onward: the shell it starts,
# the script it wrote, and the words it passes to it.
mapfile -t launch_argv <"$TEST_ARGV"
terminal_command=()
for ((i = 0; i < ${#launch_argv[@]}; i++)); do
  if [[ ${launch_argv[i]} == "-e" ]]; then
    terminal_command=("${launch_argv[@]:i+1}")
    break
  fi
done

(( ${#terminal_command[@]} > 0 )) ||
  fail "the wrapper hands the terminal a command to run" "$(printf '%s\n' "${launch_argv[@]}")"

"${terminal_command[@]}"

[[ ! -e $canary ]] || fail "an argument carrying shell syntax reaches the wrapped command as data"

printf '%s\n' 2 "$hostile" "two words" >"$tmp_dir/recorded-expected"
cmp -s "$OMARCHY_TEST_RECORDED" "$tmp_dir/recorded-expected" ||
  fail "the wrapped command gets each argument whole" "$(cat "$OMARCHY_TEST_RECORDED")"

pass "the presentation wrapper hands its caller's words over as argv"

# An argv wrapper runs its first argument as the command name, so a caller that
# still packs a command and its arguments into one quoted string asks for a
# program whose name contains a space. Nothing runs and nothing complains where
# the user can see it -- the menu entry simply does nothing. No caller may spell
# it that way, in a script or in a menu action, and none may hide it behind a
# variable: matching the quote rather than the space catches `wrapper "$command"`
# too, which no search for a literal space would ever see.
cat >"$tmp_dir/string-caller.re" <<'RE'
omarchy-launch-floating-terminal-with-presentation +\\?["'][^"']*[[:space:]$]
RE

# The sweep only ever reports what it finds, so a renamed directory would turn it
# into a check that passes because it read nothing. Count the callers first.
caller_lines=$(
  { grep -rhcF "omarchy-launch-floating-terminal-with-presentation" \
      "$ROOT/bin" "$ROOT/default" "$ROOT/config" "$ROOT/applications" "$ROOT/shell" 2>/dev/null || true; } |
    awk '{ total += $1 } END { print total + 0 }'
)

(( caller_lines > 0 )) ||
  fail "the sweep reads the directories that hold the wrapper's callers"

string_callers=$(
  grep -rnEf "$tmp_dir/string-caller.re" \
    "$ROOT/bin" "$ROOT/default" "$ROOT/config" "$ROOT/applications" "$ROOT/shell" 2>/dev/null || true
)

[[ -z $string_callers ]] ||
  fail "every caller passes the command and its arguments as separate words" "$string_callers"

pass "no caller packs a command line into one string for the presentation wrapper"

# Two callers build the wrapper's argument list in another language, where the
# sweep above cannot see the shape: a Nautilus extension in Python and a panel in
# QML. Both once handed over a whole command line as one string, so both are
# pinned to passing the command and its arguments as separate words.
transcode_extension="$ROOT/default/nautilus-python/extensions/transcode.py"
network_panel="$ROOT/shell/plugins/panels/network/Panel.qml"

grep -Fq 'argv = [wrapper, binary, paths[0]]' "$transcode_extension" ||
  fail "the transcode extension passes the transcoder and its path as separate argv words"
grep -Fq 'Gio.Subprocess.new(argv,' "$transcode_extension" ||
  fail "the transcode extension launches the argv list it built"
grep -q 'shlex' "$transcode_extension" &&
  fail "the transcode extension has no command line left to quote"

grep -Fq 'launcher + " omarchy-dns " + Util.shellQuote(provider)' "$network_panel" ||
  fail "the network panel passes the DNS provider as its own word"

pass "the callers that build the wrapper's arguments in another language pass separate words"

# Selecting several files hands the wrapper a loop rather than one command, so
# run the loop the extension actually ships and check every path went through
# whole.
transcode_loop=$(sed -n "s/^ *'\(for path;.*\)',$/\1/p" "$transcode_extension")

[[ -n $transcode_loop ]] ||
  fail "the transcode extension still ships the loop that walks several paths"

cat >"$tmp_dir/fake-transcode" <<'STUB'
#!/bin/bash
printf '%s\n' "$#" "$@" >>"$OMARCHY_TEST_RECORDED"
STUB
chmod +x "$tmp_dir/fake-transcode"

: >"$OMARCHY_TEST_RECORDED"
bash -c "$transcode_loop" "$tmp_dir/fake-transcode" "/tmp/my clip.mp4" "/tmp/it's.mkv" >/dev/null

printf '%s\n' 1 "/tmp/my clip.mp4" 1 "/tmp/it's.mkv" >"$tmp_dir/transcode-expected"
cmp -s "$OMARCHY_TEST_RECORDED" "$tmp_dir/transcode-expected" ||
  fail "each selected path reaches the transcoder whole" "$(cat "$OMARCHY_TEST_RECORDED")"

pass "several selected files each reach the transcoder as one argument"
