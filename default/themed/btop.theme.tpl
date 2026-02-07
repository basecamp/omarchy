# Main background, empty for terminal default, need to be empty if you want transparent background
theme[main_bg]="{{ background }}"

# Main text color
theme[main_fg]="{{ foreground }}"

# Title color for boxes
theme[title]="{{ foreground }}"

# Highlight color for keyboard shortcuts
theme[hi_fg]="{{ accent }}"

# Background color of selected item in processes box
theme[selected_bg]="{{ base02 }}"

# Foreground color of selected item in processes box
theme[selected_fg]="{{ accent }}"

# Color of inactive/disabled text
theme[inactive_fg]="{{ base03 }}"

# Color of text appearing on top of graphs, i.e uptime and current network graph scaling
theme[graph_text]="{{ base06 }}"

# Background color of the percentage meters
theme[meter_bg]="{{ base02 }}"

# Misc colors for processes box including mini cpu graphs, details memory graph and details status text
theme[proc_misc]="{{ base06 }}"

# CPU, Memory, Network, Proc box outline colors
theme[cpu_box]="{{ base0D }}"
theme[mem_box]="{{ base0A }}"
theme[net_box]="{{ base09 }}"
theme[proc_box]="{{ accent }}"

# Box divider line and small boxes line color
theme[div_line]="{{ base03 }}"

# Temperature graph color (Green -> Yellow -> Red)
theme[temp_start]="{{ base0A }}"
theme[temp_mid]="{{ base0B }}"
theme[temp_end]="{{ base09 }}"

# CPU graph colors (Teal -> Blue -> Purple)
theme[cpu_start]="{{ base0E }}"
theme[cpu_mid]="{{ base0C }}"
theme[cpu_end]="{{ base0D }}"

# Mem/Disk free meter
theme[free_start]="{{ base0D }}"
theme[free_mid]="{{ base0C }}"
theme[free_end]="{{ base0E }}"

# Mem/Disk cached meter
theme[cached_start]="{{ base0C }}"
theme[cached_mid]="{{ base0E }}"
theme[cached_end]="{{ base0D }}"

# Mem/Disk available meter
theme[available_start]="{{ base0B }}"
theme[available_mid]="{{ base09 }}"
theme[available_end]="{{ base09 }}"

# Mem/Disk used meter (Green -> Teal -> Blue)
theme[used_start]="{{ base0A }}"
theme[used_mid]="{{ base0E }}"
theme[used_end]="{{ base0C }}"

# Download graph colors
theme[download_start]="{{ base0B }}"
theme[download_mid]="{{ base09 }}"
theme[download_end]="{{ base09 }}"

# Upload graph colors (Green -> Teal -> Blue)
theme[upload_start]="{{ base0A }}"
theme[upload_mid]="{{ base0E }}"
theme[upload_end]="{{ base0C }}"

# Process box color gradient for threads, mem and cpu usage
theme[process_start]="{{ base0E }}"
theme[process_mid]="{{ base0C }}"
theme[process_end]="{{ base0D }}"

# Graph gradient colors (spectrum shades from background to foreground)
theme[gradient_color_0]="{{ base00 }}"
theme[gradient_color_1]="{{ base01 }}"
theme[gradient_color_2]="{{ base02 }}"
theme[gradient_color_3]="{{ base03 }}"
theme[gradient_color_4]="{{ base04 }}"
theme[gradient_color_5]="{{ base05 }}"
theme[gradient_color_6]="{{ base06 }}"
theme[gradient_color_7]="{{ base07 }}"
