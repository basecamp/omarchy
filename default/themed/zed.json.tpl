{
  "$schema": "https://zed.dev/schema/themes/v0.2.0.json",
  "name": "Omarchy",
  "author": "APS",
  "themes": [
    {
      "name": "Omarchy",
      "appearance": "{{ mode }}",
      "style": {
        "background": "{{ background }}",
        "foreground": "{{ foreground }}",
        "border": "{{ dark_background }}",
        "border.variant": "{{ lighter_background }}",
        "border.focused": "{{ accent }}",
        "border.selected": "{{ accent }}",
        "border.transparent": "#00000000",
        "border.disabled": "{{ lighter_background }}",
        "elevated_surface.background": "{{ dark_background }}",
        "surface.background": "{{ background }}",
        "drop_target.background": "{{ accent }}33",
        "element.background": "{{ background }}",
        "element.hover": "{{ lighter_background }}",
        "element.active": "{{ accent }}66",
        "element.selected": "{{ lighter_background }}",
        "element.disabled": "{{ muted }}",
        "ghost_element.background": "#00000000",
        "ghost_element.hover": "{{ lighter_background }}",
        "ghost_element.active": "{{ accent }}66",
        "ghost_element.selected": "{{ accent }}33",
        "ghost_element.disabled": "{{ lighter_background }}",
        "text": "{{ foreground }}",
        "text.muted": "{{ muted }}",
        "text.placeholder": "{{ muted }}",
        "text.disabled": "{{ muted }}",
        "text.accent": "{{ accent }}",
        "icon": "{{ foreground }}",
        "icon.muted": "{{ muted }}",
        "icon.disabled": "{{ muted }}",
        "icon.placeholder": "{{ muted }}",
        "icon.accent": "{{ accent }}",
        "status_bar.background": "{{ dark_background }}",
        "title_bar.background": "{{ dark_background }}",
        "toolbar.background": "{{ background }}",
        "tab_bar.background": "{{ dark_background }}",
        "tab.inactive_background": "{{ dark_background }}",
        "tab.active_background": "{{ background }}",
        "search.match_background": "{{ lighter_background }}",
        "panel.background": "{{ dark_background }}",
        "panel.focused_border": "{{ accent }}",
        "pane.focused_border": "{{ accent }}",
        "scrollbar.thumb.background": "{{ mix background bright_foreground 20% }}",
        "scrollbar.thumb.hover_background": "{{ lighter_background }}",
        "scrollbar.thumb.border": "{{ lighter_background }}",
        "scrollbar.track.background": "{{ dark_background }}",
        "scrollbar.track.border": "{{ dark_background }}",
        "editor.foreground": "{{ foreground }}",
        "editor.background": "{{ background }}",
        "editor.gutter.background": "{{ background }}",
        "editor.subheader.background": "{{ dark_background }}",
        "editor.active_line.background": "{{ lighter_background }}",
        "editor.highlighted_line.background": "{{ lighter_background }}",
        "editor.line_number": "{{ muted }}",
        "editor.active_line_number": "{{ foreground }}",
        "editor.invisible": "{{ muted }}",
        "editor.wrap_guide": "{{ lighter_background }}",
        "editor.active_wrap_guide": "{{ muted }}",
        "editor.document_highlight.read_background": "{{ accent }}33",
        "editor.document_highlight.write_background": "{{ accent }}33",
        "terminal.background": "{{ background }}",
        "terminal.foreground": "{{ foreground }}",
        "terminal.bright_foreground": "{{ foreground }}",
        "terminal.dim_foreground": "{{ muted }}",
        "terminal.ansi.black": "{{ color0 }}",
        "terminal.ansi.bright_black": "{{ color8 }}",
        "terminal.ansi.dim_black": "{{ color0 }}",
        "terminal.ansi.red": "{{ color1 }}",
        "terminal.ansi.bright_red": "{{ color9 }}",
        "terminal.ansi.dim_red": "{{ color1 }}",
        "terminal.ansi.green": "{{ color2 }}",
        "terminal.ansi.bright_green": "{{ color10 }}",
        "terminal.ansi.dim_green": "{{ color2 }}",
        "terminal.ansi.yellow": "{{ color3 }}",
        "terminal.ansi.bright_yellow": "{{ color11 }}",
        "terminal.ansi.dim_yellow": "{{ color3 }}",
        "terminal.ansi.blue": "{{ color4 }}",
        "terminal.ansi.bright_blue": "{{ color12 }}",
        "terminal.ansi.dim_blue": "{{ color4 }}",
        "terminal.ansi.magenta": "{{ color5 }}",
        "terminal.ansi.bright_magenta": "{{ color13 }}",
        "terminal.ansi.dim_magenta": "{{ color5 }}",
        "terminal.ansi.cyan": "{{ color6 }}",
        "terminal.ansi.bright_cyan": "{{ color14 }}",
        "terminal.ansi.dim_cyan": "{{ color6 }}",
        "terminal.ansi.white": "{{ color7 }}",
        "terminal.ansi.bright_white": "{{ color15 }}",
        "terminal.ansi.dim_white": "{{ color7 }}",
        "link_text.hover": "{{ accent }}",
        "conflict": "{{ yellow }}",
        "conflict.background": "{{ yellow }}33",
        "conflict.border": "{{ yellow }}",
        "created": "{{ green }}",
        "created.background": "{{ green }}33",
        "created.border": "{{ green }}",
        "deleted": "{{ red }}",
        "deleted.background": "{{ red }}33",
        "deleted.border": "{{ red }}",
        "error": "{{ red }}",
        "error.background": "{{ red }}33",
        "error.border": "{{ red }}",
        "hidden": "{{ muted }}",
        "hidden.background": "{{ background }}",
        "hidden.border": "{{ lighter_background }}",
        "hint": "{{ muted }}",
        "hint.background": "{{ accent }}33",
        "hint.border": "{{ accent }}",
        "ignored": "{{ muted }}",
        "ignored.background": "{{ background }}",
        "ignored.border": "{{ lighter_background }}",
        "info": "{{ accent }}",
        "info.background": "{{ accent }}33",
        "info.border": "{{ accent }}",
        "modified": "{{ yellow }}",
        "modified.background": "{{ yellow }}33",
        "modified.border": "{{ yellow }}",
        "predictive": "{{ muted }}",
        "predictive.background": "{{ lighter_background }}",
        "predictive.border": "{{ lighter_background }}",
        "renamed": "{{ color4 }}",
        "renamed.background": "{{ color4 }}33",
        "renamed.border": "{{ color4 }}",
        "success": "{{ green }}",
        "success.background": "{{ green }}33",
        "success.border": "{{ green }}",
        "unreachable": "{{ muted }}",
        "unreachable.background": "{{ background }}",
        "unreachable.border": "{{ lighter_background }}",
        "warning": "{{ yellow }}",
        "warning.background": "{{ yellow }}66",
        "warning.border": "{{ yellow }}",
        "players": [
          {
            "cursor": "{{ accent }}",
            "background": "{{ accent }}",
            "selection": "{{ accent }}33"
          },
          {
            "cursor": "{{ color5 }}",
            "background": "{{ color5 }}",
            "selection": "{{ color5 }}33"
          },
          {
            "cursor": "{{ color6 }}",
            "background": "{{ color6 }}",
            "selection": "{{ color6 }}33"
          },
          {
            "cursor": "{{ color2 }}",
            "background": "{{ color2 }}",
            "selection": "{{ color2 }}33"
          }
        ],
        "version_control.added": "{{ green }}",
        "version_control.added_background": "{{ green }}33",
        "version_control.deleted": "{{ red }}",
        "version_control.deleted_background": "{{ red }}33",
        "version_control.modified": "{{ yellow }}",
        "version_control.modified_background": "{{ yellow }}33",
        "syntax": {
          "attribute": {
            "color": "{{ color3 }}",
            "font_style": null,
            "font_weight": null
          },
          "boolean": {
            "color": "{{ color1 }}",
            "font_style": null,
            "font_weight": null
          },
          "comment": {
            "color": "{{ muted }}",
            "font_style": "italic",
            "font_weight": null
          },
          "comment.doc": {
            "color": "{{ muted }}",
            "font_style": "italic",
            "font_weight": null
          },
          "constant": {
            "color": "{{ color1 }}",
            "font_style": null,
            "font_weight": null
          },
          "constructor": {
            "color": "{{ color5 }}",
            "font_style": null,
            "font_weight": null
          },
          "embedded": {
            "color": "{{ foreground }}",
            "font_style": null,
            "font_weight": null
          },
          "emphasis": {
            "color": "{{ color1 }}",
            "font_style": "italic",
            "font_weight": null
          },
          "emphasis.strong": {
            "color": "{{ color1 }}",
            "font_style": null,
            "font_weight": 700
          },
          "enum": {
            "color": "{{ color6 }}",
            "font_style": null,
            "font_weight": null
          },
          "function": {
            "color": "{{ color4 }}",
            "font_style": null,
            "font_weight": null
          },
          "hint": {
            "color": "{{ color6 }}",
            "font_style": null,
            "font_weight": 700
          },
          "keyword": {
            "color": "{{ color5 }}",
            "font_style": null,
            "font_weight": null
          },
          "label": {
            "color": "{{ color4 }}",
            "font_style": null,
            "font_weight": null
          },
          "link_text": {
            "color": "{{ color4 }}",
            "font_style": "italic",
            "font_weight": null
          },
          "link_uri": {
            "color": "{{ color5 }}",
            "font_style": null,
            "font_weight": null
          },
          "number": {
            "color": "{{ color1 }}",
            "font_style": null,
            "font_weight": null
          },
          "operator": {
            "color": "{{ color6 }}",
            "font_style": null,
            "font_weight": null
          },
          "predictive": {
            "color": "{{ muted }}",
            "font_style": "italic",
            "font_weight": null
          },
          "preproc": {
            "color": "{{ foreground }}",
            "font_style": null,
            "font_weight": null
          },
          "primary": {
            "color": "{{ foreground }}",
            "font_style": null,
            "font_weight": null
          },
          "property": {
            "color": "{{ color4 }}",
            "font_style": null,
            "font_weight": null
          },
          "punctuation": {
            "color": "{{ muted }}",
            "font_style": null,
            "font_weight": null
          },
          "punctuation.bracket": {
            "color": "{{ muted }}",
            "font_style": null,
            "font_weight": null
          },
          "punctuation.delimiter": {
            "color": "{{ muted }}",
            "font_style": null,
            "font_weight": null
          },
          "punctuation.list_marker": {
            "color": "{{ muted }}",
            "font_style": null,
            "font_weight": null
          },
          "punctuation.special": {
            "color": "{{ color6 }}",
            "font_style": null,
            "font_weight": null
          },
          "string": {
            "color": "{{ color2 }}",
            "font_style": null,
            "font_weight": null
          },
          "string.escape": {
            "color": "{{ color5 }}",
            "font_style": null,
            "font_weight": null
          },
          "string.regex": {
            "color": "{{ color6 }}",
            "font_style": null,
            "font_weight": null
          },
          "string.special": {
            "color": "{{ color5 }}",
            "font_style": null,
            "font_weight": null
          },
          "string.special.symbol": {
            "color": "{{ color2 }}",
            "font_style": null,
            "font_weight": null
          },
          "tag": {
            "color": "{{ color4 }}",
            "font_style": null,
            "font_weight": null
          },
          "text.literal": {
            "color": "{{ color2 }}",
            "font_style": null,
            "font_weight": null
          },
          "title": {
            "color": "{{ color4 }}",
            "font_style": null,
            "font_weight": 700
          },
          "type": {
            "color": "{{ color3 }}",
            "font_style": null,
            "font_weight": null
          },
          "variable": {
            "color": "{{ foreground }}",
            "font_style": null,
            "font_weight": null
          },
          "variable.special": {
            "color": "{{ color1 }}",
            "font_style": null,
            "font_weight": null
          },
          "variant": {
            "color": "{{ color4 }}",
            "font_style": null,
            "font_weight": null
          }
        }
      }
    }
  ]
}
