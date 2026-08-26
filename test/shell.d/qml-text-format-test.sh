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

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command python3

violations=$(ROOT="$ROOT" python3 <<'PY'
import os
import re
from pathlib import Path

OPEN_ELEMENT = re.compile(r'(?:^|[:\s])([A-Z][A-Za-z0-9_.]*)\s*\{\s*$')
PROP = re.compile(r'^\s*([A-Za-z_][A-Za-z0-9_.]*)\s*:')
STRING_LITERAL = re.compile(r'"(?:[^"\\]|\\.)*"|\'(?:[^\'\\]|\\.)*\'')
PROPERTY_DECL = re.compile(r'^\s*(?:readonly\s+)?property\b')
ROOT_TEXT = re.compile(r'^Text\s*\{\s*$')


def strip_noise(line, keep_strings=False):
    out = []
    i = 0
    quote = None
    while i < len(line):
        c = line[i]
        if quote:
            if keep_strings:
                out.append(c)
            if c == '\\':
                if keep_strings and i + 1 < len(line):
                    out.append(line[i + 1])
                i += 2
                continue
            if c == quote:
                quote = None
                if not keep_strings:
                    out.append('S')
            i += 1
            continue
        if c in '"\'':
            quote = c
            if keep_strings:
                out.append(c)
            i += 1
            continue
        if c == '/' and i + 1 < len(line) and line[i + 1] == '/':
            break
        out.append(c)
        i += 1
    return ''.join(out)


def is_pure_literal(expr):
    residue = STRING_LITERAL.sub('', expr)
    residue = re.sub(r'[\s+]', '', residue)
    return residue == '' and STRING_LITERAL.search(expr) is not None


def blocks(lines):
    stack = []
    done = []
    depth = 0
    for idx, raw in enumerate(lines):
        code = strip_noise(raw)
        opened = OPEN_ELEMENT.search(code)
        prop = PROP.match(code)
        if (prop and stack and stack[-1]['depth'] == depth
                and not opened and not PROPERTY_DECL.match(code)):
            stack[-1]['props'].setdefault(prop.group(1), idx)
        n_open = code.count('{')
        n_close = code.count('}')
        if opened and n_open > 0:
            depth += 1
            stack.append({'name': opened.group(1), 'depth': depth,
                          'props': {}, 'start': idx})
            depth += n_open - 1 - n_close
        else:
            depth += n_open - n_close
        while stack and depth < stack[-1]['depth']:
            done.append(stack.pop())
    done.extend(stack)
    return done


root = Path(os.environ['ROOT'])
found = []
for path in sorted((root / 'shell').rglob('*.qml')):
    lines = path.read_text().splitlines()
    rel = path.relative_to(root)

    # A component whose root element is a Text takes its binding from callers,
    # so the default has to be declared in the component itself.
    if lines and any(ROOT_TEXT.match(l) for l in lines[:40]):
        if not any(re.match(r'\s*textFormat\s*:', l) for l in lines):
            found.append(f'{rel}: root Text element declares no textFormat')

    for b in blocks(lines):
        if b['name'] != 'Text' or 'textFormat' in b['props']:
            continue
        if 'text' not in b['props']:
            continue
        tline = b['props']['text']
        expr = strip_noise(lines[tline], keep_strings=True).split(':', 1)[1]
        if is_pure_literal(expr):
            continue
        found.append(f'{rel}:{tline + 1}: text binding without textFormat')

for line in found:
    print(line)
PY
)

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
