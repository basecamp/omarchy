# Syntax
"keyword" = "color5"
"keyword.control" = { fg = "color5", modifiers = ["italic"] }
"function" = "color4"
"function.builtin" = "color4"
"function.macro" = "color5"
"type" = "color3"
"type.builtin" = "color5"
"type.enum.variant" = "color6"
"constructor" = "color4"
"constant" = "color3"
"constant.builtin" = "color3"
"constant.numeric" = "color3"
"constant.character" = "color6"
"constant.character.escape" = "color5"
"string" = "color2"
"string.regexp" = "color5"
"string.special" = "color4"
"comment" = { fg = "color8", modifiers = ["italic"] }
"variable" = "foreground"
"variable.parameter" = { fg = "color5", modifiers = ["italic"] }
"variable.builtin" = "color1"
"variable.other.member" = "color4"
"label" = "color4"
"punctuation" = "color8"
"punctuation.special" = "color6"
"operator" = "color6"
"tag" = "color4"
"namespace" = { fg = "color3", modifiers = ["italic"] }
"special" = "color5"
"attribute" = "color3"

# Markup
"markup.heading.1" = "color1"
"markup.heading.2" = "color3"
"markup.heading.3" = "color3"
"markup.heading.4" = "color2"
"markup.heading.5" = "color4"
"markup.heading.6" = "color5"
"markup.list" = "color6"
"markup.list.unchecked" = "color8"
"markup.list.checked" = "color2"
"markup.bold" = { fg = "color1", modifiers = ["bold"] }
"markup.italic" = { fg = "color1", modifiers = ["italic"] }
"markup.strikethrough" = { modifiers = ["crossed_out"] }
"markup.link.url" = { fg = "color4", modifiers = ["italic", "underlined"] }
"markup.link.text" = "color5"
"markup.link.label" = "color4"
"markup.raw" = "color2"
"markup.quote" = "color5"

# Diff
"diff.plus" = "color2"
"diff.minus" = "color1"
"diff.delta" = "color4"

# Leave the editor background transparent so the terminal background shows through
"ui.background" = { }

"ui.linenr" = { fg = "color8" }
"ui.linenr.selected" = { fg = "foreground" }

# Statusline uses an inverted band (background-color text on foreground-color
# background) to guarantee contrast across both light and dark Omarchy themes.
"ui.statusline" = { fg = "background", bg = "foreground" }
"ui.statusline.inactive" = { fg = "background", bg = "color8" }
"ui.statusline.normal" = { fg = "background", bg = "color4", modifiers = ["bold"] }
"ui.statusline.insert" = { fg = "background", bg = "color2", modifiers = ["bold"] }
"ui.statusline.select" = { fg = "background", bg = "color5", modifiers = ["bold"] }

"ui.popup" = { fg = "foreground", bg = "background" }
"ui.window" = { fg = "color8" }
"ui.help" = { fg = "foreground", bg = "background" }

"ui.bufferline" = { fg = "color8", bg = "background" }
"ui.bufferline.active" = { fg = "foreground", bg = "background", underline = { color = "color5", style = "line" } }

"ui.text" = "foreground"
"ui.text.focus" = { fg = "foreground", modifiers = ["bold"] }
"ui.text.inactive" = { fg = "color8" }
"ui.text.directory" = { fg = "color4" }

"ui.virtual" = "color8"
"ui.virtual.ruler" = { bg = "color0" }
"ui.virtual.indent-guide" = "color8"
"ui.virtual.inlay-hint" = { fg = "color8" }
"ui.virtual.jump-label" = { fg = "color1", modifiers = ["bold"] }
"ui.virtual.whitespace" = "color8"

"ui.selection" = { fg = "selection_foreground", bg = "selection_background" }
"ui.selection.primary" = { fg = "selection_foreground", bg = "selection_background" }

"ui.cursor" = { fg = "background", bg = "cursor" }
"ui.cursor.primary" = { fg = "background", bg = "cursor" }
"ui.cursor.match" = { fg = "color3", modifiers = ["bold"] }
"ui.cursor.primary.normal" = { fg = "background", bg = "cursor" }
"ui.cursor.primary.insert" = { fg = "background", bg = "color2" }
"ui.cursor.primary.select" = { fg = "background", bg = "color5" }

"ui.cursorline.primary" = { bg = "color0" }

"ui.highlight" = { fg = "selection_foreground", bg = "selection_background", modifiers = ["bold"] }

"ui.menu" = { fg = "foreground", bg = "background" }
"ui.menu.selected" = { fg = "background", bg = "foreground", modifiers = ["bold"] }

"diagnostic.error" = { underline = { color = "color1", style = "curl" } }
"diagnostic.warning" = { underline = { color = "color3", style = "curl" } }
"diagnostic.info" = { underline = { color = "color4", style = "curl" } }
"diagnostic.hint" = { underline = { color = "color6", style = "curl" } }
"diagnostic.unnecessary" = { modifiers = ["dim"] }
"diagnostic.deprecated" = { modifiers = ["crossed_out"] }

error = "color1"
warning = "color3"
info = "color4"
hint = "color6"

[palette]
background = "{{ background }}"
foreground = "{{ foreground }}"
cursor = "{{ cursor }}"
selection_background = "{{ selection_background }}"
selection_foreground = "{{ selection_foreground }}"
color0 = "{{ color0 }}"
color1 = "{{ color1 }}"
color2 = "{{ color2 }}"
color3 = "{{ color3 }}"
color4 = "{{ color4 }}"
color5 = "{{ color5 }}"
color6 = "{{ color6 }}"
color7 = "{{ color7 }}"
color8 = "{{ color8 }}"
