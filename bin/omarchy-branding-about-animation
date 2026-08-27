#!/bin/bash

# omarchy:summary=Shared helpers for animating the About branding (source this, don't run it).
# omarchy:group=branding
# omarchy:name=about-animation
# omarchy:hidden=true

# The About branding's animation: a sheen, and the frames that make it. *When*
# those frames are written stays with the caller, because that is inseparable
# from how the caller's window closes and resizes; this only says what to write,
# and where — it is handed a logo and knows nothing about About beyond that.

# A band of light leans across the logo, rests, and leans across again. Two
# columns per row puts it at 45 degrees on screen, where a cell is twice as tall
# as it is wide.
ESC=$'\e'
# Bright white, so the band does not depend on how the terminal reads bold. Foot's
# bold-text-in-bright brightens a bold regular colour into its bright counterpart,
# which turns a bold green logo bright green — exactly the colour a bright green
# band would have used, leaving a glint nobody can see. No regular colour
# brightens into bright white, so this one shows either way.
SHEEN_BAND="${ESC}[1m${ESC}[97m"
SHEEN_SLANT=2
SHEEN_HALF=2
SHEEN_FRAME_SECONDS=0.025
SHEEN_REST_TICKS=8
# Re-measure the grid every half second, the cadence a still logo already cost,
# rather than spawning a process per frame.
SHEEN_POLL_FRAMES=20

# A frame is one string holding every row of the logo, positioned and coloured,
# so a tick writes the whole logo at once and never shows it half drawn.
compose_frame() {
  local centre=$1
  local row line length at from to frame=""

  for (( row = 0; row < SHEEN_ROWS; row++ )); do
    line=${SHEEN_LINES[row]}
    length=${#line}

    # Where the band crosses this row. Running off the right needs no clamp,
    # because a slice that starts past the end of a line is already empty, but a
    # negative offset would count from the end of it instead of off the left.
    at=$(( centre - row * SHEEN_SLANT ))
    from=$(( at - SHEEN_HALF ))
    from=$(( from < 0 ? 0 : from ))
    to=$(( at + SHEEN_HALF + 1 ))
    to=$(( to < 0 ? 0 : to ))

    frame+="${ESC}[$((SHEEN_TOP + row));${SHEEN_LEFT}H"
    frame+="${SHEEN_BASE}${line:0:from}${SHEEN_BAND}${line:from:to - from}${SHEEN_BASE}${line:to}"
  done

  SHEEN_COMPOSED=$frame
}

# Builds every frame up front: a tick that recomputed a logo's worth of colour
# spans in bash would not hold the frame rate, and the sweep is the same every
# time. Leaves them in SHEEN_FRAMES, and answers whether this logo can be
# animated at all — one it cannot put back exactly as it found it is one to leave
# alone, because nothing on screen would say the difference.
#
#   sheen_build <logo-file> <top-row> <left-column> <base-colour> <columns-available>
sheen_build() {
  local file=$1 columns=$5
  SHEEN_TOP=$2
  SHEEN_LEFT=$3
  SHEEN_BASE=$4

  SHEEN_LINES=()
  # A failing redirection reports itself before 2>/dev/null would apply, so order
  # it first: the caller's window must not get a shell error painted across it.
  mapfile -t SHEEN_LINES 2>/dev/null <"$file" || return 1
  SHEEN_ROWS=${#SHEEN_LINES[@]}
  (( SHEEN_ROWS > 0 )) || return 1

  local row line width=0
  for (( row = 0; row < SHEEN_ROWS; row++ )); do
    line=${SHEEN_LINES[row]}

    # A renderer substitutes $1 to $9 for colours, so a logo written with those is
    # not the text that reached the screen.
    [[ $line == *'$'* ]] && return 1

    # These frames slice the row by character and a terminal draws it by column,
    # so one character has to be one cell — and everything that breaks that breaks
    # it here. A wide glyph, a combining mark or a joined emoji is not one cell; a
    # tab or an escape is one the renderer expanded itself; and a shell whose
    # locale is counting bytes is not counting characters at all.
    (( ${#line} == $(printf '%s' "$line" | LC_ALL=C.UTF-8 wc -L) )) || return 1

    if (( ${#line} > width )); then
      width=${#line}
    fi
  done
  (( width > 0 && width <= columns )) || return 1

  SHEEN_FRAMES=()
  local centre last=$(( width + SHEEN_ROWS * SHEEN_SLANT + SHEEN_HALF ))
  for (( centre = -SHEEN_HALF; centre <= last; centre++ )); do
    compose_frame "$centre"
    SHEEN_FRAMES+=("$SHEEN_COMPOSED")
  done
}
