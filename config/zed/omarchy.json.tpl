{
  "$schema": "https://zed.dev/schema/themes/v0.2.0.json",
  "name": "Omarchy",
  "author": "Omarchy",
  "themes": [
    {
      "name": "Omarchy",
      "appearance": "{{appearance}}",
      "style": {
        "background": "{{background}}",
        "foreground": "{{foreground}}",
        "border": "{{background_darker}}",
        "border.variant": "{{background_lighter}}",
        "border.focused": "{{accent}}",
        "border.selected": "{{accent}}",
        "border.transparent": "#00000000",
        "border.disabled": "{{background_lighter}}",
        "elevated_surface.background": "{{background_darker}}",
        "surface.background": "{{background}}",
        "drop_target.background": "{{accent_20}}",
        "element.background": "{{background}}",
        "element.hover": "{{background_lighter}}",
        "element.active": "{{accent_40}}",
        "element.selected": "{{background_lighter}}",
        "element.disabled": "{{foreground_muted}}",
        "ghost_element.background": "#00000000",
        "ghost_element.hover": "{{background_lighter}}",
        "ghost_element.active": "{{accent_40}}",
        "ghost_element.selected": "{{accent_20}}",
        "ghost_element.disabled": "{{background_lighter}}",
        "text": "{{foreground}}",
        "text.muted": "{{foreground_muted}}",
        "text.placeholder": "{{foreground_muted}}",
        "text.disabled": "{{foreground_muted}}",
        "text.accent": "{{accent}}",
        "icon": "{{foreground}}",
        "icon.muted": "{{foreground_muted}}",
        "icon.disabled": "{{foreground_muted}}",
        "icon.placeholder": "{{foreground_muted}}",
        "icon.accent": "{{accent}}",
        "status_bar.background": "{{background_darker}}",
        "title_bar.background": "{{background_darker}}",
        "toolbar.background": "{{background}}",
        "tab_bar.background": "{{background_darker}}",
        "tab.inactive_background": "{{background_darker}}",
        "tab.active_background": "{{background}}",
        "search.match_background": "{{background_lighter}}",
        "panel.background": "{{background_darker}}",
        "panel.focused_border": "{{accent}}",
        "pane.focused_border": "{{accent}}",
        "scrollbar.thumb.background": "{{background_much_lighter}}",
        "scrollbar.thumb.hover_background": "{{background_lighter}}",
        "scrollbar.thumb.border": "{{background_lighter}}",
        "scrollbar.track.background": "{{background_darker}}",
        "scrollbar.track.border": "{{background_darker}}",
        "editor.foreground": "{{foreground}}",
        "editor.background": "{{background}}",
        "editor.gutter.background": "{{background}}",
        "editor.subheader.background": "{{background_darker}}",
        "editor.active_line.background": "{{background_lighter}}",
        "editor.highlighted_line.background": "{{background_lighter}}",
        "editor.line_number": "{{foreground_muted}}",
        "editor.active_line_number": "{{foreground}}",
        "editor.invisible": "{{foreground_muted}}",
        "editor.wrap_guide": "{{background_lighter}}",
        "editor.active_wrap_guide": "{{foreground_muted}}",
        "editor.document_highlight.read_background": "{{accent_20}}",
        "editor.document_highlight.write_background": "{{accent_20}}",
        "terminal.background": "{{background}}",
        "terminal.foreground": "{{foreground}}",
        "terminal.bright_foreground": "{{foreground}}",
        "terminal.dim_foreground": "{{foreground_muted}}",
        "terminal.ansi.black": "{{color0}}",
        "terminal.ansi.bright_black": "{{color8}}",
        "terminal.ansi.dim_black": "{{color0}}",
        "terminal.ansi.red": "{{color1}}",
        "terminal.ansi.bright_red": "{{color9}}",
        "terminal.ansi.dim_red": "{{color1}}",
        "terminal.ansi.green": "{{color2}}",
        "terminal.ansi.bright_green": "{{color10}}",
        "terminal.ansi.dim_green": "{{color2}}",
        "terminal.ansi.yellow": "{{color3}}",
        "terminal.ansi.bright_yellow": "{{color11}}",
        "terminal.ansi.dim_yellow": "{{color3}}",
        "terminal.ansi.blue": "{{color4}}",
        "terminal.ansi.bright_blue": "{{color12}}",
        "terminal.ansi.dim_blue": "{{color4}}",
        "terminal.ansi.magenta": "{{color5}}",
        "terminal.ansi.bright_magenta": "{{color13}}",
        "terminal.ansi.dim_magenta": "{{color5}}",
        "terminal.ansi.cyan": "{{color6}}",
        "terminal.ansi.bright_cyan": "{{color14}}",
        "terminal.ansi.dim_cyan": "{{color6}}",
        "terminal.ansi.white": "{{color7}}",
        "terminal.ansi.bright_white": "{{color15}}",
        "terminal.ansi.dim_white": "{{color7}}",
        "link_text.hover": "{{accent}}",
        "conflict": "{{ensured_yellow}}",
        "conflict.background": "{{ensured_yellow_20}}",
        "conflict.border": "{{ensured_yellow}}",
        "created": "{{ensured_green}}",
        "created.background": "{{ensured_green_20}}",
        "created.border": "{{ensured_green}}",
        "deleted": "{{ensured_red}}",
        "deleted.background": "{{ensured_red_20}}",
        "deleted.border": "{{ensured_red}}",
        "error": "{{ensured_red}}",
        "error.background": "{{ensured_red_20}}",
        "error.border": "{{ensured_red}}",
        "hidden": "{{foreground_muted}}",
        "hidden.background": "{{background}}",
        "hidden.border": "{{background_lighter}}",
        "hint": "{{foreground_muted}}",
        "hint.background": "{{accent_20}}",
        "hint.border": "{{accent}}",
        "ignored": "{{foreground_muted}}",
        "ignored.background": "{{background}}",
        "ignored.border": "{{background_lighter}}",
        "info": "{{accent}}",
        "info.background": "{{accent_20}}",
        "info.border": "{{accent}}",
        "modified": "{{ensured_yellow}}",
        "modified.background": "{{ensured_yellow_20}}",
        "modified.border": "{{ensured_yellow}}",
        "predictive": "{{foreground_muted}}",
        "predictive.background": "{{background_lighter}}",
        "predictive.border": "{{background_lighter}}",
        "renamed": "{{color4}}",
        "renamed.background": "{{color4_20}}",
        "renamed.border": "{{color4}}",
        "success": "{{ensured_green}}",
        "success.background": "{{ensured_green_20}}",
        "success.border": "{{ensured_green}}",
        "unreachable": "{{foreground_muted}}",
        "unreachable.background": "{{background}}",
        "unreachable.border": "{{background_lighter}}",
        "warning": "{{ensured_yellow}}",
        "warning.background": "{{ensured_yellow_40}}",
        "warning.border": "{{ensured_yellow}}",
        "players": [
          {
            "cursor": "{{accent}}",
            "background": "{{accent}}",
            "selection": "{{accent_20}}"
          },
          {
            "cursor": "{{color5}}",
            "background": "{{color5}}",
            "selection": "{{color5_20}}"
          },
          {
            "cursor": "{{color6}}",
            "background": "{{color6}}",
            "selection": "{{color6_20}}"
          },
          {
            "cursor": "{{color2}}",
            "background": "{{color2}}",
            "selection": "{{color2_20}}"
          }
        ],
        "version_control.added": "{{ensured_green}}",
        "version_control.added_background": "{{ensured_green_20}}",
        "version_control.deleted": "{{ensured_red}}",
        "version_control.deleted_background": "{{ensured_red_20}}",
        "version_control.modified": "{{ensured_yellow}}",
        "version_control.modified_background": "{{ensured_yellow_20}}",
        "syntax": {
          "attribute": {
            "color": "{{color3}}",
            "font_style": null,
            "font_weight": null
          },
          "boolean": {
            "color": "{{color1}}",
            "font_style": null,
            "font_weight": null
          },
          "comment": {
            "color": "{{foreground_muted}}",
            "font_style": "italic",
            "font_weight": null
          },
          "comment.doc": {
            "color": "{{foreground_muted}}",
            "font_style": "italic",
            "font_weight": null
          },
          "constant": {
            "color": "{{color1}}",
            "font_style": null,
            "font_weight": null
          },
          "constructor": {
            "color": "{{color5}}",
            "font_style": null,
            "font_weight": null
          },
          "embedded": {
            "color": "{{foreground}}",
            "font_style": null,
            "font_weight": null
          },
          "emphasis": {
            "color": "{{color1}}",
            "font_style": "italic",
            "font_weight": null
          },
          "emphasis.strong": {
            "color": "{{color1}}",
            "font_style": null,
            "font_weight": 700
          },
          "enum": {
            "color": "{{color6}}",
            "font_style": null,
            "font_weight": null
          },
          "function": {
            "color": "{{color4}}",
            "font_style": null,
            "font_weight": null
          },
          "hint": {
            "color": "{{color6}}",
            "font_style": null,
            "font_weight": 700
          },
          "keyword": {
            "color": "{{color5}}",
            "font_style": null,
            "font_weight": null
          },
          "label": {
            "color": "{{color4}}",
            "font_style": null,
            "font_weight": null
          },
          "link_text": {
            "color": "{{color4}}",
            "font_style": "italic",
            "font_weight": null
          },
          "link_uri": {
            "color": "{{color5}}",
            "font_style": null,
            "font_weight": null
          },
          "number": {
            "color": "{{color1}}",
            "font_style": null,
            "font_weight": null
          },
          "operator": {
            "color": "{{color6}}",
            "font_style": null,
            "font_weight": null
          },
          "predictive": {
            "color": "{{foreground_muted}}",
            "font_style": "italic",
            "font_weight": null
          },
          "preproc": {
            "color": "{{foreground}}",
            "font_style": null,
            "font_weight": null
          },
          "primary": {
            "color": "{{foreground}}",
            "font_style": null,
            "font_weight": null
          },
          "property": {
            "color": "{{color4}}",
            "font_style": null,
            "font_weight": null
          },
          "punctuation": {
            "color": "{{foreground_muted}}",
            "font_style": null,
            "font_weight": null
          },
          "punctuation.bracket": {
            "color": "{{foreground_muted}}",
            "font_style": null,
            "font_weight": null
          },
          "punctuation.delimiter": {
            "color": "{{foreground_muted}}",
            "font_style": null,
            "font_weight": null
          },
          "punctuation.list_marker": {
            "color": "{{foreground_muted}}",
            "font_style": null,
            "font_weight": null
          },
          "punctuation.special": {
            "color": "{{color6}}",
            "font_style": null,
            "font_weight": null
          },
          "string": {
            "color": "{{color2}}",
            "font_style": null,
            "font_weight": null
          },
          "string.escape": {
            "color": "{{color5}}",
            "font_style": null,
            "font_weight": null
          },
          "string.regex": {
            "color": "{{color6}}",
            "font_style": null,
            "font_weight": null
          },
          "string.special": {
            "color": "{{color5}}",
            "font_style": null,
            "font_weight": null
          },
          "string.special.symbol": {
            "color": "{{color2}}",
            "font_style": null,
            "font_weight": null
          },
          "tag": {
            "color": "{{color4}}",
            "font_style": null,
            "font_weight": null
          },
          "text.literal": {
            "color": "{{color2}}",
            "font_style": null,
            "font_weight": null
          },
          "title": {
            "color": "{{color4}}",
            "font_style": null,
            "font_weight": 700
          },
          "type": {
            "color": "{{color3}}",
            "font_style": null,
            "font_weight": null
          },
          "variable": {
            "color": "{{foreground}}",
            "font_style": null,
            "font_weight": null
          },
          "variable.special": {
            "color": "{{color1}}",
            "font_style": null,
            "font_weight": null
          },
          "variant": {
            "color": "{{color4}}",
            "font_style": null,
            "font_weight": null
          }
        }
      }
    }
  ]
}
