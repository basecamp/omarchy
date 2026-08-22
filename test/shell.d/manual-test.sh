#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# The menu advertises the reader; the reader summons the plugin. Both ends of
# that wiring live in different files, so check they still meet.
grep -q '"learn.manual".*omarchy-launch-manual' "$ROOT/default/omarchy/omarchy-menu.jsonc" ||
  fail "menu entry learn.manual does not launch omarchy-launch-manual"
grep -q 'summon omarchy.manual' "$ROOT/bin/omarchy-launch-manual" ||
  fail "omarchy-launch-manual does not summon the omarchy.manual plugin"
pass "menu entry and launcher wiring"

run_node_test <<'JS'
const fs = require('fs')
const model = requireFromRoot('shell/plugins/manual/ManualModel.js')

const theme = model.themeFor('#aabbcc', '#cacccc', '#101315', '#707880')

// ---- parseChapterIndex ----------------------------------------------------

const index = model.parseChapterIndex(
  '02-getting-started.md\tGetting Started\n' +
  '01-welcome-to-omarchy.md\tWelcome to Omarchy!\n' +
  '10-notices.md\t\n' +
  'not-markdown.txt\tIgnored\n' +
  '\n'
)
assertEqual(index.length, 3, 'parseChapterIndex keeps only markdown chapters')
assertEqual(index[0].file, '01-welcome-to-omarchy.md', 'parseChapterIndex sorts by filename')
assertEqual(index[0].title, 'Welcome to Omarchy!', 'parseChapterIndex keeps scanned titles')
assertEqual(index[0].number, 1, 'parseChapterIndex extracts the chapter number')
assertEqual(index[0].slug, 'welcome-to-omarchy', 'parseChapterIndex extracts the slug')
assertEqual(index[2].title, 'Notices', 'parseChapterIndex falls back to a filename-derived title')

// ---- theming --------------------------------------------------------------

assertEqual(model.mixColors('#000000', '#ffffff', 0.5), '#808080', 'mixColors blends midpoints')
assertEqual(model.mixColors('#ff0000', '#000000', 1), '#ff0000', 'mixColors at t=1 returns the first color')
assertEqual(theme.link, '#aabbcc', 'themeFor wires the accent to links')
assertEqual(theme.inlineCodeBg, model.mixColors('#cacccc', '#101315', 0.1), 'themeFor tints chips from foreground over background')

// ---- splitBlocks ----------------------------------------------------------

const blocks = model.splitBlocks(
  '# Title\n' +
  '\n' +
  'Some prose with an inline ![icon](images/icon.webp) image.\n' +
  '\n' +
  ' ![shot](images/shot.webp)\n' +
  '\n' +
  '```bash\n' +
  '# a comment\n' +
  'omarchy theme set "nord" $HOME\n' +
  '```\n' +
  'Tail prose.\n',
  theme
)
assertDeepEqual(
  blocks.map(b => b.kind),
  ['text', 'text', 'image', 'code', 'text'],
  'splitBlocks separates paragraphs, images, and fenced code'
)
assertEqual(blocks[0].heading, true, 'splitBlocks flags heading blocks')
assertEqual(blocks[1].heading, false, 'splitBlocks leaves prose unflagged')
assertEqual(blocks[2].source, 'images/shot.webp', 'splitBlocks captures the image source')
assertEqual(blocks[2].alt, 'shot', 'splitBlocks captures the image alt text')
assert(blocks[1].text.includes('inline ![icon]'), 'splitBlocks leaves inline images in prose')

const code = blocks[3]
assertEqual(code.language, 'bash', 'splitBlocks captures the fence language')
assert(!code.text.includes('```'), 'splitBlocks strips the fence markers')
assert(code.html.startsWith('<pre>') && code.html.endsWith('</pre>'), 'code html is a pre block')
assert(code.html.includes('<span style="color:#707880"># a comment</span>'), 'bash comments render muted')
assert(code.html.includes('<span style="color:#aabbcc">"nord"</span>'), 'bash strings render in the string color')
assert(code.html.includes('$HOME</span>'), 'bash variables get a span')

const list = model.splitBlocks('Steps:\n\n1. First\n\n2. Second\n\nDone now.', theme)
assertEqual(list.length, 2, 'splitBlocks splits trailing prose off a list')
assert(list[0].text.includes('1. First') && list[0].text.includes('2. Second'),
  'splitBlocks keeps blank-separated list items in one block')

const bare = model.splitBlocks('Some [link](https://x.y) and `code`.\n\n```bash\nls\n```')
assertEqual(bare[0].text, 'Some [link](https://x.y) and `code`.', 'splitBlocks without a theme leaves markdown raw')
assertEqual(bare[1].html, '', 'splitBlocks without a theme skips highlighting')

// ---- source line tracking -------------------------------------------------

assertDeepEqual(blocks.map(b => b.startLine), [1, 3, 5, 7, 11], 'blocks remember their source start line')
assertEqual(model.blockIndexForLine(blocks, 8), 3, 'blockIndexForLine finds the containing block')
assertEqual(model.blockIndexForLine(blocks, 1), 0, 'blockIndexForLine handles the first line')
assertEqual(model.blockIndexForLine(blocks, 99), 4, 'blockIndexForLine clamps past the end to the last block')
assertEqual(model.blockIndexForLine([], 5), -1, 'blockIndexForLine on no blocks misses cleanly')

// ---- parseSearchResults ---------------------------------------------------

const searchChapters = model.parseChapterIndex('06-themes.md\tThemes\n07-hotkeys.md\tHotkeys\n')
const found = model.parseSearchResults(
  '/path/to/manual/06-themes.md:12:## Picking a theme\n' +
  '/path/to/manual/07-hotkeys.md:3:  - Use `Super + K` freely\n' +
  '/path/to/manual/99-unknown.md:1:not indexed\n' +
  'garbage line\n',
  searchChapters, 50
)
assertEqual(found.length, 2, 'parseSearchResults keeps hits in indexed chapters only')
assertEqual(found[0].chapterIndex, 0, 'parseSearchResults maps files to chapter indexes')
assertEqual(found[0].line, 12, 'parseSearchResults keeps the line number')
assertEqual(found[0].title, 'Themes', 'parseSearchResults carries the chapter title')
assertEqual(found[0].snippet, 'Picking a theme', 'parseSearchResults strips heading markers from snippets')
assertEqual(found[1].snippet, 'Use `Super + K` freely', 'parseSearchResults trims list markers and whitespace')
assertEqual(model.parseSearchResults(Array(99).fill('/m/06-themes.md:1:x').join('\n'), searchChapters, 10).length, 10, 'parseSearchResults respects the cap')

// ---- highlightCode --------------------------------------------------------

const plain = model.highlightCode('~ ❯ omarchy capture\nplain output line', '', theme)
assert(plain.includes('<span style="color:#cacccc;font-weight:bold"> omarchy capture</span>'), 'plain prompt commands render bold')
assert(plain.includes('\nplain output line'), 'plain output lines stay untouched')

const lua = model.highlightCode('local x = "hi" -- note', 'lua', theme)
assert(lua.includes('font-weight:bold">local</span>'), 'lua keywords render bold')
assert(lua.includes('<span style="color:#707880">-- note</span>'), 'lua comments render muted')

const jsonc = model.highlightCode('{\n  // note\n  "key": "value",\n}', 'jsonc', theme)
assert(jsonc.includes('<span style="color:#707880">// note</span>'), 'jsonc comments render muted')
assert(jsonc.includes('<span style="color:#aabbcc">&quot;key&quot;</span>') === false, 'sanity: quotes are not html-escaped')
assert(jsonc.includes('<span style="color:#aabbcc">"key"</span>'), 'json keys take the variable color')
assert(jsonc.includes('<span style="color:#aabbcc">"value"</span>'), 'json string values take the string color')

const escaped = model.highlightCode('a < b && c > d', '', theme)
assert(escaped.includes('a &lt; b &amp;&amp; c &gt; d'), 'code html escapes angle brackets and ampersands')

// ---- styleLine ------------------------------------------------------------

assertEqual(
  model.styleLine('see [docs](https://x.y) now', theme),
  'see <a href="https://x.y" style="color:#aabbcc">docs</a> now',
  'styleLine rewrites links into accent-colored anchors'
)
assertEqual(
  model.styleLine('run `omarchy theme set <name>` now', theme),
  'run <code style="background-color:' + theme.inlineCodeBg + '">omarchy theme set &lt;name&gt;</code> now',
  'styleLine turns inline code into tinted chips with escaped angle brackets'
)
assertEqual(
  model.styleLine('`a_b*c`', theme),
  '<code style="background-color:' + theme.inlineCodeBg + '">a\\_b\\*c</code>',
  'styleLine escapes markdown specials inside chips'
)
assertEqual(
  model.styleLine('code `[x](y)` stays', theme),
  'code <code style="background-color:' + theme.inlineCodeBg + '">\\[x\\](y)</code> stays',
  'styleLine keeps link syntax inside chips literal'
)
assertEqual(
  model.styleLine('![alt](images/x.webp)', theme),
  '![alt](images/x.webp)',
  'styleLine leaves image syntax alone'
)
assertEqual(
  model.styleLine('[vi](<https://en.wikipedia.org/wiki/Vi_(text_editor)>)', theme),
  '<a href="https://en.wikipedia.org/wiki/Vi_(text_editor)" style="color:#aabbcc">vi</a>',
  'styleLine unwraps angle-bracketed URLs'
)
assertEqual(
  model.styleLine('[proton](https://en.wikipedia.org/wiki/Proton_(software))', theme),
  '<a href="https://en.wikipedia.org/wiki/Proton_(software)" style="color:#aabbcc">proton</a>',
  'styleLine survives URLs with nested parentheses'
)
assertEqual(model.styleLine('see [docs](https://x.y)', null), 'see [docs](https://x.y)', 'styleLine without a theme is a no-op')

// Qt imports `_x_` as underline (md4c's underline extension), so underscore
// emphasis is normalized to the star form, which imports as italic.
assertEqual(
  model.styleLine('under _Remove > Security > Fido2_ in the menu', theme),
  'under *Remove > Security > Fido2* in the menu',
  'styleLine converts underscore emphasis to italic star emphasis'
)
assertEqual(
  model.styleLine('both __strong__ and _soft_', theme),
  'both **strong** and *soft*',
  'styleLine converts double underscores to star bold'
)
assertEqual(
  model.styleLine('intraword snake_case_name stays', theme),
  'intraword snake_case_name stays',
  'styleLine leaves intraword underscores alone'
)
assertEqual(
  model.styleLine('`keep _this_ literal`', theme),
  '<code style="background-color:' + theme.inlineCodeBg + '">keep \\_this\\_ literal</code>',
  'styleLine leaves emphasis inside chips literal'
)

// ---- resolveChapter -------------------------------------------------------

const chapters = model.parseChapterIndex(
  '06-themes.md\tThemes\n' +
  '07-hotkeys.md\tHotkeys\n' +
  '45-troubleshooting.md\tTroubleshooting\n'
)
assertEqual(model.resolveChapter(chapters, '7'), 1, 'resolveChapter matches a bare number')
assertEqual(model.resolveChapter(chapters, '07'), 1, 'resolveChapter matches a zero-padded number')
assertEqual(model.resolveChapter(chapters, '06-themes.md'), 0, 'resolveChapter matches a filename')
assertEqual(model.resolveChapter(chapters, 'themes'), 0, 'resolveChapter matches a slug')
assertEqual(model.resolveChapter(chapters, 'Trouble'), 2, 'resolveChapter matches a title fragment case-insensitively')
assertEqual(model.resolveChapter(chapters, 'nonexistent'), -1, 'resolveChapter misses cleanly')

// ---- linkTarget -----------------------------------------------------------

assertDeepEqual(model.linkTarget('https://omarchy.org'), { kind: 'external', url: 'https://omarchy.org' }, 'linkTarget passes URLs through')
assertDeepEqual(model.linkTarget('mailto:x@y.z'), { kind: 'external', url: 'mailto:x@y.z' }, 'linkTarget treats mailto as external')
assertDeepEqual(model.linkTarget('./06-themes.md#making'), { kind: 'chapter', file: '06-themes.md' }, 'linkTarget resolves relative chapter links')
assertDeepEqual(model.linkTarget('#anchor'), { kind: 'anchor' }, 'linkTarget recognizes in-page anchors')
assertEqual(model.linkTarget('images/shot.webp').kind, 'none', 'linkTarget ignores non-chapter relative links')

// ---- against the real manual ----------------------------------------------

const manualDir = path.join(root, 'manual')
const files = fs.readdirSync(manualDir).filter(f => f.endsWith('.md')).sort()
assert(files.length > 0, 'the repo ships manual chapters')

const scan = files.map(f => {
  const text = fs.readFileSync(path.join(manualDir, f), 'utf8')
  const heading = text.split('\n').find(line => line.startsWith('# '))
  return f + '\t' + (heading ? heading.slice(2) : '')
}).join('\n')

const real = model.parseChapterIndex(scan)
assertEqual(real.length, files.length, 'every manual chapter parses into the index')
assert(real.every(c => c.title.length > 0), 'every chapter gets a title')

const missing = []
let unhighlighted = 0
let unclosedFences = 0
for (const chapter of real) {
  const text = fs.readFileSync(path.join(manualDir, chapter.file), 'utf8')
  for (const block of model.splitBlocks(text, theme)) {
    if (block.kind === 'code') {
      if (!block.html.startsWith('<pre>')) unhighlighted++
      if (block.text.includes('```')) unclosedFences++
    }
    if (block.kind !== 'image') continue
    if (!fs.existsSync(path.join(manualDir, block.source))) missing.push(chapter.file + ': ' + block.source)
  }
}
assertDeepEqual(missing, [], 'every standalone manual image resolves to a shipped file')
assertEqual(unhighlighted, 0, 'every manual code block gets highlighted html')
assertEqual(unclosedFences, 0, 'no manual code block swallows a fence marker')
JS
