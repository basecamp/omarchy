# Omarchy Icon Font

Read this before adding a branded glyph to `default/fonts/omarchy/omarchy.ttf`.

The Omarchy icon font is a small private-use font carrying the marks Nerd
Fonts does not have: the Omarchy logo and the agent and app brand marks. The
menu draws one by naming the font on an entry:

```jsonc
"setup.default.agent.grok": {"icon":"","iconFont":"omarchy","label":"Grok", ...}
```

Without `iconFont`, an entry's `icon` is drawn in the menu font, so reach for
this font only when a Nerd Font glyph would misrepresent the thing. A generic
robot for four different AI apps is the case that justifies a real mark; a
folder or a microphone is not.

`default/fonts/omarchy/README.md` lists every glyph with the URL its artwork
came from. Keep that list accurate — it is the only record of provenance.

## Adding a glyph

`omarchy dev font` does the work:

```bash
omarchy dev font list
omarchy dev font add ollama https://simpleicons.org/icons/ollama.svg
```

`add` fetches the SVG, scales it into the same 64..960 box the existing marks
use so it lands at their optical size, appends it at the next free private-use
codepoint, and adds a line to the font README. It prints the codepoint and the
glyph itself.

The source must be a **monochrome SVG with a single `<path>`**, because the
menu recolors the glyph with the active theme's foreground and selection
colors. Brand icon sets such as <https://simpleicons.org> publish exactly that
shape. App favicons usually do not: they are multi-color, carry a container
tile, or split across several paths. Prefer the official mark when it is
published as flat monochrome art, and fall back to an icon set's redraw when it
is not.

Two-tone marks are a trap. Every path becomes solid foreground, so a logo whose
meaning depends on lighter and darker halves turns into an unreadable blob.
Pick a source whose silhouette alone reads.

## After adding

The command prints these, and all of them matter:

- Point the menu entry at the new codepoint with `"iconFont":"omarchy"`.
- Bump the charset range asserted in `test/shell.d/menu-test.sh`; that test
  pins the font's coverage and fails until it matches.
- Check the README line the command added, and give it a proper display name
  with `--label` if the glyph name is not the brand's name.

The font is package-owned: `omarchy-settings` installs it to
`/usr/share/fonts/omarchy/omarchy.ttf`, so a new glyph reaches the desktop
through a settings release, not through `omarchy update`. Between the merge and
that release, a pulled checkout renders the new entry with no icon.

## Verifying

Render the whole font and look at it, which catches inverted contours and
filled counters that a glyph list cannot show:

```bash
python3 -c "open('/tmp/row.txt','w').write(' '.join(chr(c) for c in range(0xE900, 0xE910)))"
magick -background white -fill black -font default/fonts/omarchy/omarchy.ttf \
  -pointsize 110 label:@/tmp/row.txt /tmp/font-row.png
```

Then confirm it in the running menu per
[`visual-verification.md`](visual-verification.md). Fontconfig prefers the
packaged font over a copy in `~/.local/share/fonts` for the same family, so a
preview needs either the real file replaced or a `<rejectfont>` rule in
`~/.config/fontconfig/conf.d/` pointing fontconfig away from the packaged one.
Restart the shell afterwards — Qt reads the font database at startup, so
`omarchy menu refresh` alone will not pick up a changed font.
