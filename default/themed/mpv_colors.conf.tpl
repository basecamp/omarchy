# AVAILABLE VARIABLES:
#   {{ background }}            - Main background color (e.g., "#1a1b26")
#   {{ foreground }}            - Main foreground/text color
#   {{ cursor }}                - Cursor color
#   {{ accent }}                - Theme accent color
#   {{ selection_background }}  - Selection highlight background
#   {{ selection_foreground }}  - Selection highlight foreground
#
#   {{ color0 }} through {{ color15 }} - Standard 16-color terminal palette
#     color0-7:  Normal colors (black, red, green, yellow, blue, magenta, cyan, white)
#     color8-15: Bright variants
#
# VARIABLE MODIFIERS:
#   {{ variable_strip }} - Hex color without the # prefix (e.g., "1a1b26")
#   {{ variable_rgb }}   - Decimal RGB values (e.g., "26,27,38")
#
# Example using modifiers:
#   background = "{{ background }}"       -> background = "#1a1b26"
#   background = "{{ background_strip }}" -> background = "1a1b26"
#   background = "rgb({{ background_rgb }})" -> background = "rgb(26,27,38)"
#
# ---------------------------------------------------------------------------
#
# Colors and style for mpv
#
# accent color of the OSC and title bar
osc_color={{ background }}
# color of the title in borderless/fullscreen mode
window_title_color={{ foreground }}
# color of the window controls (close, minimize, maximize) in borderless/fullscreen mode
window_controls_color={{ foreground }}
# color of close window control on hover
windowcontrols_close_hover={{ accent }}
# color of maximize window controls on hover
windowcontrols_max_hover={{ accent }}
# color of minimize window controls on hover
windowcontrols_min_hover={{ accent }}
# color of the title (above seekbar)
title_color={{ foreground }}
# color of the cache information
cache_info_color={{ foreground }}
# color of the seekbar progress and handle
seekbarfg_color={{ accent }}
# color of the remaining seekbar
seekbarbg_color={{ foreground }}
# color of the cache ranges on the seekbar
seekbar_cache_color={{ selection_foreground }}
# match volume bar color with seekbar color (ignores side_buttons_color)
volumebar_match_seek_color=no
# color of the timestamps (below seekbar)
time_color={{ foreground }}
# color of the chapter title next to timestamp (below seekbar)
chapter_title_color={{ foreground }}
# color of the side buttons (audio, subtitles, playlist, etc.)
side_buttons_color={{ foreground }}
# color of the middle buttons (skip, jump, chapter, etc.)
middle_buttons_color={{ foreground }}
# color of the play/pause button
playpause_color={{ foreground }}
# color of the element when held down (pressed)
held_element_color={{ cursor }}
# color of a hovered button when hover_effect includes "color"
hover_effect_color={{ accent }}
# color of the border for thumbnails (with thumbfast)
thumbnail_border_color={{ foreground }}
# color of the border outline for thumbnails
thumbnail_border_outline={{ accent }}
