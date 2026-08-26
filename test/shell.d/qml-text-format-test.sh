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
INLINE_COMPONENT = re.compile(r'^\s*component\s+[A-Za-z_][A-Za-z0-9_]*\s*:\s*Text\s*\{\s*$')
INLINE_COMPONENT_ONELINE = re.compile(r'^\s*component\s+[A-Za-z_][A-Za-z0-9_]*\s*:\s*Text\s*\{')
PROP = re.compile(r'^\s*([A-Za-z_][A-Za-z0-9_.]*)\s*:')
STRING_LITERAL = re.compile(r'"(?:[^"\\]|\\.)*"|\'(?:[^\'\\]|\\.)*\'')
PROPERTY_DECL = re.compile(r'^\s*(?:readonly\s+)?property\b')
# A binding that runs onto the next line: this line ends on an operator, or the
# next line opens with one.
TRAILING_OPERATOR = re.compile(r'(?:&&|\|\||[?:+\-*/,(\[=&|])$')
LEADING_OPERATOR = re.compile(r'^\s*(?:&&|\|\||[?:+\-*/,)\]&|.])')


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


def binding_expression(lines, start):
    """The whole right-hand side of the binding beginning on line `start`.

    The literal exemption has to be judged on the complete expression. Reading
    only the physical `text:` line would exempt `text: "prefix"` while
    `+ externalValue` sits underneath, letting a dynamic AutoText binding
    through. Reading a wrapped concatenation of literals as dynamic would be
    the opposite error, so follow the expression to its end either way.
    """
    parts = []
    parens = brackets = 0
    i = start
    while i < len(lines):
        parts.append(strip_noise(lines[i], keep_strings=True))
        counted = strip_noise(lines[i])
        parens += counted.count('(') - counted.count(')')
        brackets += counted.count('[') - counted.count(']')
        # Look past blank and comment-only lines for the continuation. A
        # comment or a blank line dropped into a wrapped expression does not
        # end it, and stopping there would read `text: "prefix"` as the whole
        # binding and exempt it as a literal while `+ externalValue` waits
        # below — the exact misreading this function exists to prevent.
        following = ''
        for ahead in range(i + 1, len(lines)):
            candidate = strip_noise(lines[ahead])
            if candidate.strip():
                following = candidate
                break
        continues = (parens > 0 or brackets > 0
                     or TRAILING_OPERATOR.search(counted.rstrip())
                     or LEADING_OPERATOR.match(following))
        if not continues:
            break
        i += 1

    chunk = ' '.join(parts)
    return chunk.split(':', 1)[1] if ':' in chunk else chunk


def exempt_as_literal(lines, tline):
    """True when the binding is only string literals, however many lines."""
    return is_pure_literal(binding_expression(lines, tline))


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
        depth += n_open - n_close
        if opened and n_open > 0:
            # OPEN_ELEMENT anchors at the end of the line, so the element it
            # matched is the innermost one opened here and its depth is the
            # depth after every brace on the line.
            stack.append({'name': opened.group(1), 'depth': depth,
                          'props': {}, 'start': idx})
        while stack and depth < stack[-1]['depth']:
            done.append(stack.pop())
    done.extend(stack)
    return done


INLINE_TEXT = re.compile(r'(?:^|[:\s])Text\s*\{([^{}]*)\}')
INLINE_BINDING = re.compile(r'\btext\s*:\s*(.*?)\s*(?:;|$)')


def inline_violations(lines, rel):
    """Whole Text blocks written on one line.

    OPEN_ELEMENT anchors at the end of the line, so the brace scanner never
    sees these. A Repeater delegate is a plausible place for one.
    """
    out = []
    for idx, raw in enumerate(lines):
        code = strip_noise(raw, keep_strings=True)
        for match in INLINE_TEXT.finditer(code):
            body = match.group(1)
            if 'textFormat' in body:
                continue
            # A component root written on one line needs the default whether or
            # not this line binds `text`, for the same reason the block form
            # does: every caller supplies the binding.
            if INLINE_COMPONENT_ONELINE.match(code):
                out.append(f'{rel}:{idx + 1}: inline component root Text declares no textFormat')
                continue
            binding = INLINE_BINDING.search(body)
            if not binding or is_pure_literal(binding.group(1)):
                continue
            out.append(f'{rel}:{idx + 1}: inline Text block without textFormat')
    return out


# `Text { text: someValue` with the block carrying on below is valid QML and is
# invisible to both scanners: OPEN_ELEMENT anchors its `{` at the end of the
# line so the brace tracker never opens the block, and INLINE_TEXT needs the
# closing brace on the same line. A dynamic AutoText binding written that way
# passes this file in silence, which is the one failure a test like this must
# not have.
#
# Rather than teach a line scanner to parse QML, require the two forms it can
# read: the whole block on one line, or nothing after the opening brace. Every
# Text in this tree is already written that way, so keeping to it costs nothing.
UNSCANNABLE_TEXT = re.compile(r'(?:^|[:\s])Text\s*\{\s*\S')
BARE_TEXT_OPENER = re.compile(r'(?:^|[:\s])Text\s*$')

UNSCANNABLE = ('Text block written in a form this scanner cannot read; put the '
               'opening brace last on the line, or write the whole block on '
               'one line with no nested braces')


def unscannable_violations(lines, rel):
    out = []
    for idx, raw in enumerate(lines):
        code = strip_noise(raw)

        # `Text` with its brace on the next line. OPEN_ELEMENT needs both on
        # one line, so the block is never opened and everything in it is
        # attributed to the enclosing element instead.
        if BARE_TEXT_OPENER.search(code):
            following = ''
            for ahead in range(idx + 1, len(lines)):
                candidate = strip_noise(lines[ahead]).strip()
                if candidate:
                    following = candidate
                    break
            if following.startswith('{'):
                out.append(f'{rel}:{idx + 1}: {UNSCANNABLE}')
                continue

        for match in UNSCANNABLE_TEXT.finditer(code):
            # A complete one-line block with no nested braces is fine —
            # inline_violations reads those. Count rather than looking for a
            # `}`, because `Text { text: ({ a: external }).a }` closes on this
            # line yet INLINE_TEXT's brace-free body pattern cannot match it,
            # so treating any `}` as "handled elsewhere" would drop it.
            rest = code[match.end() - 1:]
            depth = 1
            closed = False
            for char in rest:
                if char == '{':
                    depth += 1
                elif char == '}':
                    depth -= 1
                    if depth == 0:
                        closed = True
                        break
            if closed and '{' not in rest:
                continue
            out.append(f'{rel}:{idx + 1}: {UNSCANNABLE}')
    return out


root = Path(os.environ['ROOT'])
found = []
scanned = 0
for path in sorted((root / 'shell').rglob('*.qml')):
    scanned += 1
    lines = path.read_text().splitlines()
    rel = path.relative_to(root)
    found.extend(inline_violations(lines, rel))
    found.extend(unscannable_violations(lines, rel))

    for b in blocks(lines):
        if b['name'] != 'Text' or 'textFormat' in b['props']:
            continue

        # Read the block's own properties. A nested child declaring textFormat
        # says nothing about its parent, so `Text { Text { textFormat: ... } }`
        # must still report the outer element.
        # The root element of a component takes its binding from callers, so it
        # needs the default whether or not this file binds `text`. Require both
        # depth 1 and column 0: the scanner attributes one element per line, so
        # a `Row { Text {` line would report depth 1 for a nested block, and
        # falling through to the binding check below is the safe reading.
        # Indentation is not what makes it a root; depth 1 is. A `Row { Text {`
        # line still reads as `Row` here, so leading whitespace can be ignored
        # without letting a nested block be mistaken for the file's root.
        if b['depth'] == 1 and lines[b['start']].lstrip().startswith('Text'):
            found.append(f'{rel}:{b["start"] + 1}: root Text element declares no textFormat')
            continue

        # A QML inline component is a root for the same reason, and the rule
        # above cannot see one: `component InfoValue: Text {` sits inside
        # another element, so its depth is not 1 and its line does not start
        # with `Text`. Its `text` comes from every caller, so the file it lives
        # in never binds it and the binding check below lets it through in
        # silence. Only one file-level root Text exists in this tree, so
        # without this the root rule is very nearly dead code.
        if INLINE_COMPONENT.match(lines[b['start']]):
            found.append(f'{rel}:{b["start"] + 1}: inline component root Text declares no textFormat')
            continue

        if 'text' not in b['props']:
            continue
        tline = b['props']['text']
        if exempt_as_literal(lines, tline):
            continue
        found.append(f'{rel}:{tline + 1}: text binding without textFormat')

# A scan that read nothing reports nothing, and an all-clear from a run that
# never opened a file is the one result this test must never give. Only a
# checkout with no shell/ QML at all reaches this.
if scanned == 0:
    raise SystemExit('no .qml files found under shell/; the scan read nothing')

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
