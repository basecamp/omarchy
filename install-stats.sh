#!/bin/bash
# Omarchy installation benchmark analyzer
# Reads journalctl logs and reports timing for each installation step

echo "Omarchy Installation Benchmark Report"
echo "====================================="
echo

# Get all completed steps with timing
journalctl -t omarchy-install --output=cat | grep "^Completed:" | while IFS= read -r line; do
  # Extract step name and duration
  if [[ $line =~ ^Completed:\ (.+)\ \(([0-9]+)s\)$ ]]; then
    step="${BASH_REMATCH[1]}"
    duration="${BASH_REMATCH[2]}"
    
    # Format duration as MM:SS
    minutes=$((duration / 60))
    seconds=$((duration % 60))
    formatted_time=$(printf "%02d:%02d" $minutes $seconds)
    
    printf "%-60s %s (%ds)\n" "$step" "$formatted_time" "$duration"
  fi
done | sort -k4 -nr | while IFS= read -r line; do
  echo "$line"
done

echo
echo "Summary Statistics"
echo "------------------"

# Calculate total time
total_seconds=$(journalctl -t omarchy-install --output=cat | grep "^Completed:" | sed -n 's/.*(\([0-9]*\)s)$/\1/p' | awk '{sum+=$1} END {print sum}')
total_minutes=$((total_seconds / 60))
remaining_seconds=$((total_seconds % 60))

echo "Total installation time: ${total_minutes}m ${remaining_seconds}s"
echo

# Show top 5 longest steps
echo "Top 5 Longest Steps:"
echo "-------------------"
journalctl -t omarchy-install --output=cat | grep "^Completed:" | while IFS= read -r line; do
  if [[ $line =~ ^Completed:\ (.+)\ \(([0-9]+)s\)$ ]]; then
    step="${BASH_REMATCH[1]}"
    duration="${BASH_REMATCH[2]}"
    printf "%4ds - %s\n" "$duration" "$step"
  fi
done | sort -rn | head -5