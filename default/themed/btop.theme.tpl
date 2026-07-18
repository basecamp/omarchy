# Main background, empty for terminal default, need to be empty if you want transparent background
theme[main_bg]="{{ background }}"

# Main text color
theme[main_fg]="{{ foreground }}"

# Title color for boxes
theme[title]="{{ foreground }}"

# Highlight color for keyboard shortcuts
theme[hi_fg]="{{ accent }}"

# Background color of selected item in processes box
theme[selected_bg]="{{ selection }}"

# Foreground color of selected item in processes box
theme[selected_fg]="{{ accent }}"

# Color of inactive/disabled text
theme[inactive_fg]="{{ muted }}"

# Color of text appearing on top of graphs, i.e uptime and current network graph scaling
theme[graph_text]="{{ light_foreground }}"

# Background color of the percentage meters
theme[meter_bg]="{{ selection }}"

# Misc colors for processes box including mini cpu graphs, details memory graph and details status text
theme[proc_misc]="{{ light_foreground }}"

# CPU, Memory, Network, Proc box outline colors
theme[cpu_box]="{{ magenta }}"
theme[mem_box]="{{ green }}"
theme[net_box]="{{ red }}"
theme[proc_box]="{{ accent }}"

# Box divider line and small boxes line color
theme[div_line]="{{ muted }}"

# Temperature graph color (Green -> Yellow -> Red)
theme[temp_start]="{{ green }}"
theme[temp_mid]="{{ yellow }}"
theme[temp_end]="{{ red }}"

# CPU graph colors (Teal -> Blue -> Magenta)
theme[cpu_start]="{{ cyan }}"
theme[cpu_mid]="{{ blue }}"
theme[cpu_end]="{{ magenta }}"

# Mem/Disk free meter
theme[free_start]="{{ magenta }}"
theme[free_mid]="{{ blue }}"
theme[free_end]="{{ cyan }}"

# Mem/Disk cached meter
theme[cached_start]="{{ blue }}"
theme[cached_mid]="{{ cyan }}"
theme[cached_end]="{{ magenta }}"

# Mem/Disk available meter
theme[available_start]="{{ yellow }}"
theme[available_mid]="{{ red }}"
theme[available_end]="{{ red }}"

# Mem/Disk used meter (Green -> Teal -> Blue)
theme[used_start]="{{ green }}"
theme[used_mid]="{{ cyan }}"
theme[used_end]="{{ blue }}"

# Download graph colors
theme[download_start]="{{ yellow }}"
theme[download_mid]="{{ red }}"
theme[download_end]="{{ red }}"

# Upload graph colors (Green -> Teal -> Blue)
theme[upload_start]="{{ green }}"
theme[upload_mid]="{{ cyan }}"
theme[upload_end]="{{ blue }}"

# Process box color gradient for threads, mem and cpu usage
theme[process_start]="{{ cyan }}"
theme[process_mid]="{{ blue }}"
theme[process_end]="{{ magenta }}"

# Graph gradient colors (spectrum shades from background to foreground)
theme[gradient_color_0]="{{ background }}"
theme[gradient_color_1]="{{ lighter_background }}"
theme[gradient_color_2]="{{ selection }}"
theme[gradient_color_3]="{{ muted }}"
theme[gradient_color_4]="{{ dark_foreground }}"
theme[gradient_color_5]="{{ foreground }}"
theme[gradient_color_6]="{{ light_foreground }}"
theme[gradient_color_7]="{{ bright_foreground }}"
