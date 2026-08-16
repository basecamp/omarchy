// Pure data helpers for the manual reader. Kept free of QML types so
// test/shell.d/manual-test.sh can exercise them under node.

// Fallback when a chapter file carries no `# ` heading: derive a readable
// title from the "NN-some-slug.md" filename.
function titleFromFilename(name) {
  var base = String(name || "").replace(/\.md$/, "").replace(/^\d+-/, "")
  var words = base.split("-").filter(function(w) { return w.length > 0 })
  return words.map(function(w) {
    return w.charAt(0).toUpperCase() + w.slice(1)
  }).join(" ")
}

// Input: one "filename\ttitle" line per chapter (title may be empty), in
// whatever order the scanner emitted them. Output: chapters sorted by
// filename, which the manual numbers deliberately.
function parseChapterIndex(raw) {
  var chapters = []
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    if (!line.trim()) continue
    var tab = line.indexOf("\t")
    var file = tab >= 0 ? line.slice(0, tab) : line
    var title = tab >= 0 ? line.slice(tab + 1).trim() : ""
    file = file.trim()
    if (!file.match(/\.md$/)) continue
    var numberMatch = file.match(/^(\d+)-/)
    chapters.push({
      file: file,
      number: numberMatch ? parseInt(numberMatch[1], 10) : 0,
      slug: file.replace(/\.md$/, "").replace(/^\d+-/, ""),
      title: title || titleFromFilename(file)
    })
  }
  chapters.sort(function(a, b) { return a.file < b.file ? -1 : (a.file > b.file ? 1 : 0) })
  return chapters
}

// ---------------------------------------------------------------- theming

// Mix #rrggbb (or #aarrggbb) colors: t of a over (1 - t) of b. Used to bake
// solid chip and panel colors, since Qt's rich text CSS subset takes plain
// hex but no alpha.
function mixColors(a, b, t) {
  function channels(hex) {
    var h = String(hex || "").replace("#", "")
    if (h.length === 8) h = h.slice(2)
    if (h.length !== 6) return null
    return [parseInt(h.slice(0, 2), 16), parseInt(h.slice(2, 4), 16), parseInt(h.slice(4, 6), 16)]
  }
  var ca = channels(a)
  var cb = channels(b)
  if (!ca || !cb) return String(a || b || "")
  var out = "#"
  for (var i = 0; i < 3; i++) {
    var v = Math.round(ca[i] * t + cb[i] * (1 - t))
    out += (v < 16 ? "0" : "") + v.toString(16)
  }
  return out
}

// The rendering style splitBlocks needs, derived from the four foundational
// theme colors. Kept here so the derivation is testable and the panel only
// hands over what it knows.
function themeFor(accent, foreground, background, muted) {
  return {
    link: accent,
    inlineCodeBg: mixColors(foreground, background, 0.1),
    comment: muted,
    string: accent,
    keyword: foreground,
    variable: accent
  }
}

// ---------------------------------------------------------------- links

// Qt's markdown importer bakes the application palette's link color into the
// document, so links keep their default blue no matter what the item is told.
// md4c passes raw inline HTML through, which gives us a working override:
// rewrite markdown links into anchors styled with the theme accent.
function rewriteLinkSegment(segment, linkColor) {
  var re = /\[([^\]]+)\]\(\s*(?:<([^>\s]+)>|((?:[^()\s]|\([^()]*\))+))(\s+"[^"]*")?\s*\)/g
  return segment.replace(re, function(match, text, angled, bare, title, offset, whole) {
    if (offset > 0 && whole.charAt(offset - 1) === "!") return match
    return '<a href="' + (angled || bare || "") + '" style="color:' + linkColor + '">' + text + "</a>"
  })
}

// ---------------------------------------------------------------- code

function escapeHtml(text) {
  return String(text).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
}

// Inline chips stay inside markdown text, where md4c would still interpret
// emphasis and bracket syntax between the chip's tags — escape those away.
function escapeMarkdownSpecials(text) {
  return String(text).replace(/[\\*_\[\]`~]/g, "\\$&")
}

function span(color, bold, text) {
  var style = "color:" + color + (bold ? ";font-weight:bold" : "")
  return '<span style="' + style + '">' + text + "</span>"
}

// Line-based token coloring over already HTML-escaped code. One combined
// alternation per language keeps matches from overlapping: whatever the scan
// reaches first (a string, a comment opener, a variable) wins the region.
function highlightLine(line, language, theme) {
  var rules
  if (language === "bash" || language === "sh") {
    rules = /("(?:[^"\\]|\\.)*"|'[^']*')|((?:^|\s)#.*$)|(\$\{[^}]*\}|\$[A-Za-z_][A-Za-z0-9_]*|\$\d)/g
  } else if (language === "lua") {
    rules = /("(?:[^"\\]|\\.)*"|'[^']*')|(--.*$)|(\b(?:local|function|end|if|then|else|elseif|return|for|while|do|in|not|and|or|true|false|nil)\b)/g
  } else if (language === "json" || language === "jsonc") {
    rules = /("(?:[^"\\]|\\.)*")|(\/\/.*$)|(\b(?:true|false|null)\b|-?\b\d+(?:\.\d+)?\b)/g
  } else {
    // Plain blocks are terminal transcripts: make prompt lines' commands
    // stand out and leave the output alone.
    var prompt = line.match(/^(~ ❯|\$)( .*)$/)
    if (prompt) return span(theme.comment, false, prompt[1]) + span(theme.keyword, true, prompt[2])
    return line
  }
  return line.replace(rules, function(match, string, comment, third, offset, whole) {
    if (string !== undefined) {
      // A json key is the string right before a colon; color it like a
      // variable so structure reads at a glance.
      if ((language === "json" || language === "jsonc") && /^\s*:/.test(whole.slice(offset + match.length)))
        return span(theme.variable, false, match)
      return span(theme.string, false, match)
    }
    if (comment !== undefined) return span(theme.comment, false, match)
    if (language === "bash" || language === "sh") return span(theme.variable, false, match)
    return span(theme.keyword, true, match)
  })
}

function highlightCode(code, language, theme) {
  var lines = escapeHtml(code).split("\n")
  for (var i = 0; i < lines.length; i++) lines[i] = highlightLine(lines[i], language, theme)
  return "<pre>" + lines.join("\n") + "</pre>"
}

// ---------------------------------------------------------------- lines

// Qt imports markdown with md4c's underline extension, so `_emphasis_`
// renders underlined instead of italic. Rewrite word-bounded underscore
// emphasis to the star form, which imports as italic. Intraword underscores
// (snake_case, URLs) don't sit on word boundaries and stay untouched.
function normalizeEmphasis(segment) {
  return String(segment)
    .replace(/(^|[^A-Za-z0-9_\\])__(?!_)([^_]+)__(?![A-Za-z0-9_])/g, "$1**$2**")
    .replace(/(^|[^A-Za-z0-9_\\])_(?!_)([^_]+)_(?![A-Za-z0-9_])/g, "$1*$2*")
}

// Rewrite one markdown line for display: links get accent-colored anchors,
// inline code spans become tinted chips, underscore emphasis becomes star
// emphasis. The rewrites ride on md4c's raw-HTML passthrough. Code spans are
// transformed first so link and emphasis syntax inside them stays literal.
function styleLine(line, theme) {
  if (!theme) return line
  var parts = String(line).split(/(`[^`]+`)/)
  for (var i = 0; i < parts.length; i++) {
    if (parts[i].charAt(0) === "`" && parts[i].length > 1) {
      var code = escapeMarkdownSpecials(escapeHtml(parts[i].slice(1, -1)))
      parts[i] = '<code style="background-color:' + theme.inlineCodeBg + '">' + code + "</code>"
    } else {
      parts[i] = rewriteLinkSegment(normalizeEmphasis(parts[i]), theme.link)
    }
  }
  return parts.join("")
}

// ---------------------------------------------------------------- blocks

// Split chapter markdown into text, image, and code blocks. Qt markdown
// quirks drive the shape: images draw at natural size (the manual's
// screenshots are 1600px wide), so standalone image paragraphs become
// width-fitted Image blocks; paragraphs get no vertical margins, so each
// blank-line-separated paragraph becomes its own block and the panel's
// Column provides the spacing; and fenced code gets neither styling nor
// horizontal scrolling, so fences become code blocks the panel renders in
// its own highlighted, scrollable panel. Blank lines followed by a list item
// or indented continuation don't split, so ordered lists keep their
// numbering across gaps between items. Without a theme the styling rewrites
// are skipped and blocks carry raw markdown only.
function splitBlocks(markdown, theme) {
  var blocks = []
  var textLines = []
  var textStart = 1
  var textHasContent = false
  var codeLines = null
  var codeLanguage = ""
  var codeStart = 1

  function flushText() {
    var text = textLines.join("\n")
    if (text.trim()) blocks.push({ kind: "text", text: text, heading: /^\s*#/.test(text), startLine: textStart })
    textLines = []
    textHasContent = false
  }

  function flushCode() {
    var code = codeLines.join("\n")
    blocks.push({
      kind: "code",
      language: codeLanguage,
      text: code,
      html: theme ? highlightCode(code, codeLanguage, theme) : "",
      startLine: codeStart
    })
    codeLines = null
    codeLanguage = ""
  }

  function continuesBlock(lines, from) {
    for (var i = from; i < lines.length; i++) {
      if (!lines[i].trim()) continue
      return lines[i].match(/^\s*([-*+]|\d+[.)])\s/) !== null || lines[i].match(/^ {4,}\S/) !== null
    }
    return false
  }

  var lines = String(markdown || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    var fence = line.match(/^\s*(```|~~~)\s*([A-Za-z0-9_-]*)\s*$/)
    if (fence) {
      if (codeLines === null) {
        flushText()
        codeLines = []
        codeLanguage = fence[2].toLowerCase()
        codeStart = i + 1
      } else {
        flushCode()
      }
      continue
    }
    if (codeLines !== null) {
      codeLines.push(line)
      continue
    }
    var image = line.match(/^\s*!\[([^\]]*)\]\(([^)\s]+)\)\s*$/)
    if (image) {
      flushText()
      blocks.push({ kind: "image", alt: image[1], source: image[2], startLine: i + 1 })
    } else if (!line.trim()) {
      if (continuesBlock(lines, i + 1)) textLines.push(line)
      else flushText()
    } else {
      if (!textHasContent) {
        textStart = i + 1
        textHasContent = true
      }
      textLines.push(styleLine(line, theme))
    }
  }
  if (codeLines !== null) flushCode()
  flushText()
  return blocks
}

// The block a 1-based source line landed in — the jump target for a search
// hit. Lines before the first block clamp to the first.
function blockIndexForLine(blocks, line) {
  if (!blocks || blocks.length === 0) return -1
  var index = 0
  for (var i = 0; i < blocks.length; i++)
    if (blocks[i].startLine <= line) index = i
  return index
}

// ---------------------------------------------------------------- search

// Parse `grep -rinF` output ("path/NN-file.md:12:matched text") into jump
// targets ordered the way grep found them, which follows chapter order.
// Hits in files the chapter index doesn't know are dropped.
function parseSearchResults(raw, chapters, limit) {
  var cap = limit || 50
  var results = []
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length && results.length < cap; i++) {
    var match = lines[i].match(/^(.*?([^\/:]+\.md)):(\d+):(.*)$/)
    if (!match) continue
    var file = match[2]
    var chapterIndex = -1
    for (var c = 0; c < chapters.length; c++)
      if (chapters[c].file === file) { chapterIndex = c; break }
    if (chapterIndex < 0) continue
    results.push({
      chapterIndex: chapterIndex,
      file: file,
      title: chapters[chapterIndex].title,
      line: parseInt(match[3], 10),
      snippet: match[4].replace(/^[\s#>*-]+/, "").trim()
    })
  }
  return results
}

// ---------------------------------------------------------------- lookups

// Resolve a user-supplied chapter reference — number, filename, slug, or a
// case-insensitive fragment of the slug or title — to a chapter index.
function resolveChapter(chapters, ref) {
  var wanted = String(ref || "").trim()
  if (!wanted) return -1
  var lower = wanted.toLowerCase()
  var i

  if (wanted.match(/^\d+$/)) {
    var number = parseInt(wanted, 10)
    for (i = 0; i < chapters.length; i++)
      if (chapters[i].number === number) return i
  }
  for (i = 0; i < chapters.length; i++)
    if (chapters[i].file === wanted || chapters[i].slug === lower) return i
  for (i = 0; i < chapters.length; i++)
    if (chapters[i].slug.indexOf(lower) !== -1) return i
  for (i = 0; i < chapters.length; i++)
    if (chapters[i].title.toLowerCase().indexOf(lower) !== -1) return i
  return -1
}

// Classify an activated link: external URLs open a browser, relative .md
// links navigate between chapters, in-page anchors are ignored.
function linkTarget(href) {
  var link = String(href || "").trim()
  if (!link) return { kind: "none" }
  if (link.match(/^[a-z][a-z0-9+.-]*:/i)) return { kind: "external", url: link }
  if (link.charAt(0) === "#") return { kind: "anchor" }
  var file = link.replace(/^\.\//, "").split("#")[0]
  if (file.match(/\.md$/)) return { kind: "chapter", file: file }
  return { kind: "none" }
}

if (typeof module !== "undefined") {
  module.exports = {
    titleFromFilename: titleFromFilename,
    parseChapterIndex: parseChapterIndex,
    mixColors: mixColors,
    themeFor: themeFor,
    styleLine: styleLine,
    highlightCode: highlightCode,
    splitBlocks: splitBlocks,
    blockIndexForLine: blockIndexForLine,
    parseSearchResults: parseSearchResults,
    resolveChapter: resolveChapter,
    linkTarget: linkTarget
  }
}
