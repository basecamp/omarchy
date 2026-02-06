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
theme[temp_mid]="{{ spectrum3 }}"
theme[temp_end]="{{ color1 }}"

# CPU graph colors
theme[cpu_start]="{{ spectrum0 }}"
theme[cpu_mid]="{{ spectrum3 }}"
theme[cpu_end]="{{ spectrum6 }}"

# Mem/Disk free meter
theme[free_start]="{{ color5 }}"
theme[free_mid]="{{ spectrum3 }}"
theme[free_end]="{{ spectrum1 }}"

# Mem/Disk cached meter
theme[cached_start]="{{ spectrum2 }}"
theme[cached_mid]="{{ color4 }}"
theme[cached_end]="{{ spectrum5 }}"

# Mem/Disk available meter
theme[available_start]="{{ color3 }}"
theme[available_mid]="{{ spectrum5 }}"
theme[available_end]="{{ spectrum7 }}"

# Mem/Disk used meter
theme[used_start]="{{ spectrum0 }}"
theme[used_mid]="{{ color4 }}"
theme[used_end]="{{ spectrum7 }}"

# Download graph colors
theme[download_start]="{{ color3 }}"
theme[download_mid]="{{ spectrum6 }}"
theme[download_end]="{{ color1 }}"

# Upload graph colors
theme[upload_start]="{{ color2 }}"
theme[upload_mid]="{{ spectrum1 }}"
theme[upload_end]="{{ spectrum2 }}"

# Process box color gradient for threads, mem and cpu usage
theme[process_start]="{{ spectrum1 }}"
theme[process_mid]="{{ color4 }}"
theme[process_end]="{{ spectrum5 }}"

# Graph gradient colors
theme[gradient_color_0]="{{ spectrum0 }}"
theme[gradient_color_1]="{{ spectrum1 }}"
theme[gradient_color_2]="{{ spectrum2 }}"
theme[gradient_color_3]="{{ spectrum3 }}"
theme[gradient_color_4]="{{ spectrum4 }}"
theme[gradient_color_5]="{{ spectrum5 }}"
theme[gradient_color_6]="{{ spectrum6 }}"
theme[gradient_color_7]="{{ spectrum7 }}"
