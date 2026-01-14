# Main background, empty for terminal default, need to be empty if you want transparent background
theme[main_bg]="{{ background }}"

# Main text color
theme[main_fg]="{{ foreground }}"

# Title color for boxes
theme[title]="{{ foreground }}"

# Highlight color for keyboard shortcuts
theme[hi_fg]="{{ accent }}"

# Background color of selected item in processes box
theme[selected_bg]="{{ color8 }}"

# Foreground color of selected item in processes box
theme[selected_fg]="{{ accent }}"

# Color of inactive/disabled text
theme[inactive_fg]="{{ color8 }}"

# Color of text appearing on top of graphs, i.e uptime and current network graph scaling
theme[graph_text]="{{ foreground }}"

# Background color of the percentage meters
theme[meter_bg]="{{ color8 }}"

# Misc colors for processes box including mini cpu graphs, details memory graph and details status text
theme[proc_misc]="{{ foreground }}"

# CPU, Memory, Network, Proc box outline colors
theme[cpu_box]="{{ color5 }}"
theme[mem_box]="{{ color2 }}"
theme[net_box]="{{ color1 }}"
theme[proc_box]="{{ accent }}"

# Box divider line and small boxes line color
theme[div_line]="{{ color8 }}"

# Temperature graph color (Green -> Yellow -> Red)
theme[temp_start]="{{ color2 }}"
theme[temp_mid]="{{ color3 }}"
theme[temp_end]="{{ color1 }}"

# CPU graph colors (Teal -> Lavender)
theme[cpu_start]="{{ color6 }}"
theme[cpu_mid]="{{ color4 }}"
theme[cpu_end]="{{ color5 }}"

# Mem/Disk free meter (Mauve -> Lavender -> Blue)
theme[free_start]="{{ color5 }}"
theme[free_mid]="{{ color4 }}"
theme[free_end]="{{ color6 }}"

# Mem/Disk cached meter (Sapphire -> Lavender)
theme[cached_start]="{{ color4 }}"
theme[cached_mid]="{{ color6 }}"
theme[cached_end]="{{ color5 }}"

# Mem/Disk available meter (Peach -> Red)
theme[available_start]="{{ color3 }}"
theme[available_mid]="{{ color1 }}"
theme[available_end]="{{ color1 }}"

# Mem/Disk used meter (Green -> Sky)
theme[used_start]="{{ color2 }}"
theme[used_mid]="{{ color6 }}"
theme[used_end]="{{ color4 }}"

# Download graph colors (Peach -> Red)
theme[download_start]="{{ color3 }}"
theme[download_mid]="{{ color1 }}"
theme[download_end]="{{ color1 }}"

# Upload graph colors (Green -> Sky)
theme[upload_start]="{{ color2 }}"
theme[upload_mid]="{{ color6 }}"
theme[upload_end]="{{ color4 }}"

# Process box color gradient for threads, mem and cpu usage (Sapphire -> Mauve)
theme[process_start]="{{ color6 }}"
theme[process_mid]="{{ color4 }}"
theme[process_end]="{{ color5 }}"
