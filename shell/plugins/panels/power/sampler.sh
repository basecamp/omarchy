#!/bin/bash
# Power Hungry sampler: one pass over /proc, emitted as key\tvalue lines that
# the power panel's Model.js parses. Consecutive snapshots are diffed for
# per-process CPU share; watts come from the same source the stock panel
# displays so the stats rows and the attribution always agree.
#
# Lines:
#   watts\t<absolute battery flow in watts>
#   cputotal\t<busy jiffies on the aggregate cpu line of /proc/stat>
#   p\t<pid>\t<utime+stime jiffies>\t<comm>\t<rss kB>

WATTS=""
bat=""
for b in /sys/class/power_supply/macsmc-battery /sys/class/power_supply/BAT*; do
  if [[ -d $b ]]; then
    bat=$b
    break
  fi
done

# omarchy-battery-status reads the same telemetry the stock panel shows, with
# its smoothing, so prefer it over raw sysfs. Its rate is signed (negative
# while discharging) and macsmc mirrors that sign in sysfs, so strip it here —
# direction belongs to UPower on the QML side, never to this value.
STOCK_RATE=$(omarchy-battery-status --shell 2>/dev/null | awk -F'\t' '$1=="rate"{gsub(/W/,"",$2); print $2}')
if [[ -n $STOCK_RATE ]]; then
  WATTS=${STOCK_RATE#-}
elif [[ -n $bat && -f $bat/power_now ]]; then
  # µW, negative while discharging on macsmc. An empty or garbage read (kernel
  # races, permission hiccups) must omit the line entirely rather than emit a
  # bogus -0.0 that would render as "-0 W".
  raw=$(cat "$bat/power_now" 2>/dev/null)
  if [[ $raw =~ ^-?[0-9]+$ ]]; then
    WATTS=$(awk -v v="$raw" 'BEGIN{printf "%.1f", (v < 0 ? -v : v) / 1000000}')
  fi
fi
if [[ -z ${WATTS:-} && -n $bat && -f $bat/current_now && -f $bat/voltage_now ]]; then
  # µA × µV = pW, so watts needs 10^12, not 10^6. current_now is signed on
  # macsmc, and the same numeric guard applies to both reads.
  cnow=$(cat "$bat/current_now" 2>/dev/null)
  vnow=$(cat "$bat/voltage_now" 2>/dev/null)
  if [[ $cnow =~ ^-?[0-9]+$ && $vnow =~ ^-?[0-9]+$ ]]; then
    WATTS=$(awk -v i="$cnow" -v u="$vnow" 'BEGIN{p=i*u; printf "%.1f", (p < 0 ? -p : p) / 1000000000000}')
  fi
fi

if [[ -n $WATTS ]]; then
  printf 'watts\t%s\n' "$WATTS"
fi

# Busy jiffies only: user+nice+system+irq+softirq+steal. Idle and iowait are
# excluded so per-process shares are shares of CPU activity — with idle in the
# denominator the idle time would surface as "everything else" watts. Guest
# time is already counted inside user (kernels since 2.6.33, per proc(5)), so
# summing the guest column as well would double-count it. The per-process side
# matches: utime in /proc/<pid>/stat likewise includes guest time.
printf 'cputotal\t%s\n' "$(awk '/^cpu /{print $2+$3+$4+$7+$8+$9}' /proc/stat)"

# System vitals. Two CPU denominators exist on purpose: cputotal above is
# busy jiffies only (per-process shares must be shares of CPU activity), while
# system CPU% needs busy over ALL ticks including idle and iowait — so the
# vitals pair below carries its own all-ticks total. cpu_busy repeats
# cputotal's value under a self-describing name; cputotal itself stays as the
# attribution key so that consumer is untouched.
awk '/^cpu /{
  busy = $2+$3+$4+$7+$8+$9
  printf "cpu_busy\t%d\ncpu_total\t%d\n", busy, busy+$5+$6
}' /proc/stat

# RAM: MemTotal/MemAvailable from /proc/meminfo, in kB. MemAvailable (not
# MemFree) is what "how much can I still use" means, per proc(5).
awk '
  /^MemTotal:/ { total = $2 }
  /^MemAvailable:/ { avail = $2 }
  END {
    if (total > 0) printf "mem_total_kb\t%d\n", total
    if (avail > 0) printf "mem_avail_kb\t%d\n", avail
  }' /proc/meminfo

# GPU utilization: first user-readable source wins; when none exists the line
# is simply omitted (echo silence, like watts) and the panel hides the row.
# amdgpu exposes a busy percentage per card; nvidia-smi is probed only when
# already on PATH and only behind a 50 ms timeout so a wedged driver can never
# stall the 1 Hz sampling loop. debugfs nodes are root-only at runtime and
# therefore disqualified as panel sources even where they exist.
GPU=""
for g in /sys/class/drm/card*/device/gpu_busy_percent; do
  if [[ -r $g ]]; then
    v=$(cat "$g" 2>/dev/null)
    if [[ $v =~ ^[0-9]+$ ]]; then
      GPU=$v
      break
    fi
  fi
done
if [[ -z $GPU ]] && command -v nvidia-smi >/dev/null 2>&1; then
  v=$(timeout 0.05 nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>/dev/null | head -n1 | tr -d ' ')
  [[ $v =~ ^[0-9]+$ ]] && GPU=$v
fi
if [[ -n $GPU ]]; then
  printf 'gpu_pct\t%s\n' "$GPU"
fi

# comm sits between the first "(" and the last ")" of a stat line and may
# contain spaces, slashes, and unbalanced parens, so anchor at the last ")":
# everything after it splits cleanly, with utime at field 12 and stime at 13
# (shifted by two because pid and comm are fields 1 and 2 of the raw line).
# rss comes from statm, read per pid inside the awk: a pid that exits
# mid-scan makes getline return -1 (rss 0) instead of aborting — a plain
# multi-file awk dies fatally on the first vanished /proc entry, which the
# constant process churn on a busy box turns into intermittent empty or
# truncated snapshots. rss is field 2 of statm in pages — pagesize varies
# (16K on Asahi, 4K typical elsewhere), so multiply by getconf PAGESIZE.
cat /proc/[0-9]*/stat 2>/dev/null | awk -v PG="$(getconf PAGESIZE)" '
{
  tail = $0; sub(/.*\)/, "", tail)
  head = substr($0, 1, length($0) - length(tail) - 1)
  op = index(head, "(")
  pid = substr(head, 1, op - 1); gsub(/^ +| +$/, "", pid)
  comm = substr(head, op + 1)
  split(tail, f, " ")
  rss = 0
  if ((getline mline < ("/proc/" pid "/statm")) > 0) {
    split(mline, m, " ")
    if ((m[2] + 0) > 0) rss = int(m[2] * PG / 1024)
  }
  close("/proc/" pid "/statm")
  print "p\t" pid "\t" (f[12] + f[13]) "\t" comm "\t" rss
}'
