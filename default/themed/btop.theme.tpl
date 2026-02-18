# Main background, empty for terminal default, need to be empty if you want transparent background
theme[main_bg]="{{ background }}"

# Main text color
theme[main_fg]="{{ foreground }}"

# Title color for boxes
theme[title]="{{ foreground }}"

# Highlight color for keyboard shortcuts
theme[hi_fg]="{{ accent }}"

# Background color of selected item in processes box
theme[selected_bg]="{{ base03 }}"

# Foreground color of selected item in processes box
theme[selected_fg]="{{ accent }}"

# Color of inactive/disabled text
theme[inactive_fg]="{{ base03 }}"

# Color of text appearing on top of graphs, i.e uptime and current network graph scaling
theme[graph_text]="{{ foreground }}"

# Background color of the percentage meters
theme[meter_bg]="{{ base03 }}"

# Misc colors for processes box including mini cpu graphs, details memory graph and details status text
theme[proc_misc]="{{ foreground }}"

# CPU, Memory, Network, Proc box outline colors
theme[cpu_box]="{{ base0E }}"
theme[mem_box]="{{ base0B }}"
theme[net_box]="{{ base08 }}"
theme[proc_box]="{{ accent }}"

# Box divider line and small boxes line color
theme[div_line]="{{ base03 }}"

# Temperature graph color (Green -> Yellow -> Red)
theme[temp_start]="{{ base0B }}"
theme[temp_mid]="{{ base0A }}"
theme[temp_end]="{{ base08 }}"

# CPU graph colors (Teal -> Lavender)
theme[cpu_start]="{{ base0C }}"
theme[cpu_mid]="{{ base0D }}"
theme[cpu_end]="{{ base0E }}"

# Mem/Disk free meter (Mauve -> Lavender -> Blue)
theme[free_start]="{{ base0E }}"
theme[free_mid]="{{ base0D }}"
theme[free_end]="{{ base0C }}"

# Mem/Disk cached meter (Sapphire -> Lavender)
theme[cached_start]="{{ base0D }}"
theme[cached_mid]="{{ base0C }}"
theme[cached_end]="{{ base0E }}"

# Mem/Disk available meter (Peach -> Red)
theme[available_start]="{{ base0A }}"
theme[available_mid]="{{ base08 }}"
theme[available_end]="{{ base08 }}"

# Mem/Disk used meter (Green -> Sky)
theme[used_start]="{{ base0B }}"
theme[used_mid]="{{ base0C }}"
theme[used_end]="{{ base0D }}"

# Download graph colors (Peach -> Red)
theme[download_start]="{{ base0A }}"
theme[download_mid]="{{ base08 }}"
theme[download_end]="{{ base08 }}"

# Upload graph colors (Green -> Sky)
theme[upload_start]="{{ base0B }}"
theme[upload_mid]="{{ base0C }}"
theme[upload_end]="{{ base0D }}"

# Process box color gradient for threads, mem and cpu usage (Sapphire -> Mauve)
theme[process_start]="{{ base0C }}"
theme[process_mid]="{{ base0D }}"
theme[process_end]="{{ base0E }}"
