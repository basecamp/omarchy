#!/bin/bash

# --- CONFIGURATION ---
# Base paths
BASE_DIR="$HOME/hyprwhspr"
WHISPER_DIR="$BASE_DIR/whisper.cpp"

# Whisper settings
MODEL="models/ggml-base.en.bin"
WHISPER_BIN="./build/bin/whisper-cli" 
AUDIO_FILE="/tmp/whisper_input.wav"
PID_FILE="/tmp/whisper_rec.pid"

# Ensure we operate inside the whisper directory for relative paths to models/binaries
cd "$WHISPER_DIR" || { notify-send -u critical "Whisper Error" "Could not find $WHISPER_DIR"; exit 1; }

# --- TOGGLE LOGIC ---

if [ -f "$PID_FILE" ]; then
    # ========================
    # STATE: STOP RECORDING
    # ========================
    
    # 1. Kill the recording process
    REC_PID=$(cat "$PID_FILE")
    if kill -0 "$REC_PID" 2>/dev/null; then
        kill "$REC_PID"
        wait "$REC_PID" 2>/dev/null
    fi
    rm "$PID_FILE"

    # 2. Notify: Processing (using same stack tag to replace the recording notification)
    notify-send -u low -t 2000 -h string:x-dunst-stack-tag:whisper-recording "Whisper" "🧠 Transcribing..."

    # 3. Transcribe
    # -nt: no timestamps
    # grep -v: filters out system warnings/brackets
    TEXT=$($WHISPER_BIN -m "$MODEL" -f "$AUDIO_FILE" -nt 2>/dev/null | grep -v "WARNING" | grep -v "\[")
    
    # Clean whitespace
    CLEAN_TEXT=$(echo "$TEXT" | xargs)

    # 4. Final Output
    if [ -z "$CLEAN_TEXT" ]; then
        notify-send -u normal "Whisper" "❌ No speech detected."
    else
        echo "$CLEAN_TEXT" | wl-copy
        notify-send -u normal "Whisper" "✅ Copied to clipboard!"
        wtype -d 5 -s 50 "$CLEAN_TEXT"
        notify-send -u low "Whisper" "✅ Typed into active window!"
    fi

    # Cleanup audio
    rm -f "$AUDIO_FILE"

else
    # ========================
    # STATE: START RECORDING
    # ========================

    # 1. Start parecord (PulseAudio) in background
    parecord --channels=1 --rate=16000 --format=s16le "$AUDIO_FILE" > /dev/null 2>&1 &
    
    # 2. Save PID to file
    echo $! > "$PID_FILE"

    # 3. Notify User (with replace-id so we can close it later)
    notify-send -u critical -t 0 -h string:x-dunst-stack-tag:whisper-recording "🎙️ Recording Started" "Press SUPER+R to stop."
fi