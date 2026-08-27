#!/bin/bash

# A QML Text element with no textFormat uses Text.AutoText. Qt then runs
# mightBeRichText() over the string and promotes it to Text.RichText when it
# looks like markup, and RichText fetches <img src="http://..."> through
# QQuickPixmap. Any string that reaches such an element from outside the shell
# — a notification summary, an MPRIS track title, a window title, an SSID, a
# Bluetooth device name, clipboard content, a weather API response — can
# therefore make the shell issue an unauthenticated outbound GET with no user
# interaction.
#
# The promotion needs only that the attacker contribute the first `<` in the
# string, on the first line. A fixed label in front of the value does not
# protect it, and neither does .toUpperCase(), because the parser lowercases
# the tag before looking it up.
#
# So require an explicit textFormat on every Text whose text: binding is not a
# bare string literal. A literal carries no external data, so AutoText has
# nothing to promote; this test is what catches the edit that later turns such
# a literal into an expression.
#
# The scan itself lives in qml-text-format-scan.py. It is run twice: over the
# real tree, and over the fixtures below, which are the forms that have already
# slipped past it once. A guard nothing can fail is a guard nobody should trust,
# and every one of those fixtures passed silently before it was written down.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command python3

SCAN="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/qml-text-format-scan.py"

violations=$(python3 "$SCAN" "$ROOT")

if [[ -n $violations ]]; then
  count=$(printf '%s\n' "$violations" | wc -l)
  fail "every Text with a dynamic text binding declares textFormat" \
    "$violations

$count Text element(s) rely on Text.AutoText for a non-literal binding.
Add an explicit textFormat. Text.PlainText is right for anything that renders
data from outside the shell; use Text.StyledText only where markup is a
deliberate, documented feature, and strip <img> before it reaches the renderer."
fi

pass "every Text with a dynamic text binding declares textFormat"

# The scanner's own tests. Each fixture is a Text that renders external data
# with no textFormat, written in a form that once passed. `caught` asserts the
# scan reports something; `clean` asserts it does not, so the fixtures prove the
# scanner can fail rather than that it fails at everything.
fixture_root=$(mktemp -d)
trap 'chmod -R u+rwX "$fixture_root" 2>/dev/null; rm -rf "$fixture_root"' EXIT

function scan_fixture {
  local name=$1
  local dir="$fixture_root/$name"
  mkdir -p "$dir/shell/Ui"
  cat > "$dir/shell/Ui/Fixture.qml"
  python3 "$SCAN" "$dir" 2>&1
}

function caught {
  local name=$1 description=$2 output
  output=$(scan_fixture "$name" || true)
  if [[ -z $output ]]; then
    fail "$description" "the scan reported nothing for fixture $name"
  fi
  pass "$description"
}

function clean {
  local name=$1 description=$2 output
  output=$(scan_fixture "$name" || true)
  if [[ -n $output ]]; then
    fail "$description" "the scan reported: $output"
  fi
  pass "$description"
}

caught plain "the scan reports a plain dynamic binding with no textFormat" <<'QML'
import QtQuick
Item {
  property string external: "x"
  Text {
    text: external
  }
}
QML

clean literal "the scan leaves a string literal alone" <<'QML'
import QtQuick
Item {
  Text {
    text: "a literal"
  }
}
QML

clean declared "the scan leaves a declared textFormat alone" <<'QML'
import QtQuick
Item {
  property string external: "x"
  Text {
    textFormat: Text.PlainText
    text: external
  }
}
QML

# strip_noise() knew `//` and not `/* */`, so a block comment between the type
# name and its brace hid the whole element from every rule.
caught block-comment "the scan reads a Text whose brace a block comment hides" <<'QML'
import QtQuick
Item {
  property string external: "x"
  Text /* explanation */ {
    text: external
  }
}
QML

caught block-comment-multiline "the scan reads past a block comment spanning lines" <<'QML'
import QtQuick
Item {
  property string external: "x"
  /*
   * Text { text: "not this one" }
   */
  Text {
    text: external
  }
}
QML

# `import QtQuick as QQ` makes the element `QQ.Text`, which compared unequal to
# `Text` and was skipped outright.
caught namespaced "the scan reads a Text reached through a namespaced import" <<'QML'
import QtQuick as QQ
QQ.Item {
  property string external: "x"
  QQ.Text {
    text: external
  }
}
QML

# textFormat was matched as a substring, so any property whose name merely
# started that way exempted the element.
caught namespaced-inline "the scan reads a one-line namespaced Text block" <<'QML'
import QtQuick as QQ
QQ.Item {
  property string external: "x"
  QQ.Text { text: external }
}
QML

caught namespaced-unscannable "the scan rejects an unreadable namespaced Text block" <<'QML'
import QtQuick as QQ
QQ.Item {
  property string external: "x"
  QQ.Text { text: external
    color: "red"
  }
}
QML

caught textformat-substring "the scan does not accept a lookalike property as textFormat" <<'QML'
import QtQuick
Item {
  property string external: "x"
  property bool textFormatEnabled: true
  Text { text: external; visible: textFormatEnabled }
}
QML

# A component root takes its text from every caller, so the file it lives in
# never binds it. The one-line form was covered; this one was not.
caught component-next-line "the scan reads a component root whose Text sits on the next line" <<'QML'
import QtQuick
Item {
  component Info:
    Text {
    }
}
QML

caught component-one-line "the scan reads a component root written on one line" <<'QML'
import QtQuick
Item {
  component Info: Text { color: "red" }
}
QML

# Forms the scanner cannot read are reported rather than passed, which is the
# whole reason it can be a line scanner at all.
caught brace-next-line "the scan rejects a Text whose opening brace is on the next line" <<'QML'
import QtQuick
Item {
  property string external: "x"
  Text
  {
    text: external
  }
}
QML

caught trailing-binding "the scan rejects a Text with a binding after the opening brace" <<'QML'
import QtQuick
Item {
  property string external: "x"
  Text { text: external
    color: "red"
  }
}
QML

# A wrapped binding is judged whole: a literal first line says nothing about
# what is concatenated onto it below.
caught wrapped-binding "the scan follows a wrapped binding past its literal first line" <<'QML'
import QtQuick
Item {
  property string external: "x"
  Text {
    text: "prefix"
      + external
  }
}
QML

clean wrapped-literals "the scan leaves a wrapped concatenation of literals alone" <<'QML'
import QtQuick
Item {
  Text {
    text: "one"
      + "two"
  }
}
QML

# A nested child's textFormat says nothing about its parent.
caught nested-child "the scan does not let a nested child's textFormat cover its parent" <<'QML'
import QtQuick
Text {
  text: external.value
  Text {
    textFormat: Text.PlainText
    text: "literal"
  }
}
QML

# A scan that reads less than the tree holds must not report success. Both of
# these once did.
empty_root=$(mktemp -d)
mkdir -p "$empty_root/shell"
if python3 "$SCAN" "$empty_root" > /dev/null 2>&1; then
  rm -rf "$empty_root"
  fail "the scan fails when it reads no files" "an empty shell/ tree exited 0"
fi
rm -rf "$empty_root"
pass "the scan fails when it reads no files"

blind_root="$fixture_root/blind"
mkdir -p "$blind_root/shell/Ui/locked"
printf 'import QtQuick\nItem {\n  Text {\n    textFormat: Text.PlainText\n    text: "ok"\n  }\n}\n' > "$blind_root/shell/Ui/Good.qml"
printf 'import QtQuick\nItem {\n  property string external: "x"\n  Text {\n    text: external\n  }\n}\n' > "$blind_root/shell/Ui/locked/Bad.qml"
chmod 000 "$blind_root/shell/Ui/locked"
if python3 "$SCAN" "$blind_root" > /dev/null 2>&1; then
  chmod 755 "$blind_root/shell/Ui/locked"
  fail "the scan fails when a directory hides files from it" "an unreadable subdirectory exited 0"
fi
chmod 755 "$blind_root/shell/Ui/locked"
pass "the scan fails when a directory hides files from it"
