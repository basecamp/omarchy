# Syntax
"keyword" = "magenta"
"keyword.control" = { fg = "magenta", modifiers = ["italic"] }
"function" = "blue"
"function.builtin" = "blue"
"function.macro" = "magenta"
"type" = "yellow"
"type.builtin" = "magenta"
"type.enum.variant" = "cyan"
"constructor" = "blue"
"constant" = "orange"
"constant.character" = "cyan"
"constant.character.escape" = "magenta"
"string" = "green"
"string.regexp" = "magenta"
"string.special" = "blue"
"string.special.symbol" = "red"
"comment" = { fg = "muted", modifiers = ["italic"] }
"variable" = "foreground"
"variable.parameter" = { fg = "red", modifiers = ["italic"] }
"variable.builtin" = "red"
"variable.other.member" = "blue"
"label" = "blue"
"punctuation" = "muted"
"punctuation.special" = "cyan"
"operator" = "cyan"
"tag" = "blue"
"namespace" = { fg = "yellow", modifiers = ["italic"] }
"special" = "blue"
"attribute" = "yellow"

# Markup
"markup.heading" = "red"
"markup.heading.1" = "red"
"markup.heading.2" = "orange"
"markup.heading.3" = "yellow"
"markup.heading.4" = "green"
"markup.heading.5" = "blue"
"markup.heading.6" = "magenta"
"markup.list" = "cyan"
"markup.list.unchecked" = "muted"
"markup.list.checked" = "green"
"markup.bold" = { fg = "red", modifiers = ["bold"] }
"markup.italic" = { fg = "red", modifiers = ["italic"] }
"markup.strikethrough" = { modifiers = ["crossed_out"] }
"markup.link.url" = { fg = "blue", modifiers = ["italic", "underlined"] }
"markup.link.text" = "magenta"
"markup.link.label" = "blue"
"markup.raw" = "green"
"markup.quote" = "magenta"

# Diff
"diff.plus" = "green"
"diff.minus" = "red"
"diff.delta" = "blue"

# Leave the editor background transparent so the terminal background shows through
"ui.background" = { }

"ui.linenr" = { fg = "muted" }
"ui.linenr.selected" = { fg = "foreground" }

# Statusline uses an inverted band (background-color text on foreground-color
# background) to guarantee contrast across both light and dark Omarchy themes.
"ui.statusline" = { fg = "background", bg = "foreground" }
"ui.statusline.inactive" = { fg = "background", bg = "muted" }
"ui.statusline.normal" = { fg = "background", bg = "blue", modifiers = ["bold"] }
"ui.statusline.insert" = { fg = "background", bg = "green", modifiers = ["bold"] }
"ui.statusline.select" = { fg = "background", bg = "magenta", modifiers = ["bold"] }

"ui.popup" = { fg = "foreground", bg = "background" }
"ui.window" = { fg = "muted" }
"ui.help" = { fg = "foreground", bg = "background" }

"ui.bufferline" = { fg = "muted", bg = "background" }
"ui.bufferline.active" = { fg = "foreground", bg = "background", underline = { color = "magenta", style = "line" } }

"ui.text" = "foreground"
"ui.text.focus" = { fg = "foreground", bg = "lighter_background", modifiers = ["bold"] }
"ui.text.inactive" = { fg = "muted" }
"ui.text.directory" = { fg = "blue" }

"ui.virtual" = "muted"
"ui.virtual.ruler" = { bg = "lighter_background" }
"ui.virtual.indent-guide" = "muted"
"ui.virtual.inlay-hint" = { fg = "muted" }
"ui.virtual.jump-label" = { fg = "red", modifiers = ["bold"] }
"ui.virtual.whitespace" = "muted"

"ui.selection" = { bg = "selection_background", fg = "selection_foreground" }

"ui.cursor" = { fg = "background", bg = "bright_foreground" }
"ui.cursor.primary" = { fg = "background", bg = "bright_foreground" }
"ui.cursor.match" = { fg = "orange", modifiers = ["bold"] }
"ui.cursor.primary.normal" = { fg = "background", bg = "bright_foreground" }
"ui.cursor.primary.insert" = { fg = "background", bg = "green" }
"ui.cursor.primary.select" = { fg = "background", bg = "magenta" }

"ui.cursorline.primary" = { bg = "lighter_background" }

"ui.highlight" = { bg = "lighter_background", modifiers = ["bold"] }

"ui.menu" = { fg = "foreground", bg = "background" }
"ui.menu.selected" = { fg = "background", bg = "foreground", modifiers = ["bold"] }

"diagnostic.error" = { underline = { color = "red", style = "curl" } }
"diagnostic.warning" = { underline = { color = "yellow", style = "curl" } }
"diagnostic.info" = { underline = { color = "blue", style = "curl" } }
"diagnostic.hint" = { underline = { color = "cyan", style = "curl" } }
"diagnostic.unnecessary" = { modifiers = ["dim"] }
"diagnostic.deprecated" = { modifiers = ["crossed_out"] }

error = "red"
warning = "yellow"
info = "blue"
hint = "cyan"

[palette]
background = "{{ background }}"
lighter_background = "{{ lighter_background }}"
foreground = "{{ foreground }}"
bright_foreground = "{{ bright_foreground }}"
muted = "{{ muted }}"
selection_background = "{{ selection_background }}"
selection_foreground = "{{ selection_foreground }}"
red = "{{ red }}"
green = "{{ green }}"
yellow = "{{ yellow }}"
orange = "{{ orange }}"
blue = "{{ blue }}"
magenta = "{{ magenta }}"
cyan = "{{ cyan }}"
