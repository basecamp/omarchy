#!/bin/bash
set -e

# --- CONFIGURATION ---
BASE_DIR="$HOME/hyprwhspr"
WHISPER_DIR="$BASE_DIR/whisper.cpp"
MODEL_NAME="base.en" 

echo "🚀 Starting hyprwhspr installation..."

# 1. Install System Dependencies (Fedora)
echo "📦 Installing dependencies..."
sudo dnf install -y git make automake gcc gcc-c++ SDL2 SDL2-devel wl-clipboard pulseaudio-utils cmake libnotify wtype

# 2. Setup Directories & Clone
mkdir -p "$BASE_DIR"

if [ -d "$WHISPER_DIR" ]; then
    echo "📂 Directory $WHISPER_DIR already exists. Pulling latest changes..."
    cd "$WHISPER_DIR"
    git pull
else
    echo "📂 Cloning whisper.cpp into $WHISPER_DIR..."
    git clone https://github.com/ggml-org/whisper.cpp.git "$WHISPER_DIR"
    cd "$WHISPER_DIR"
fi

# 3. Download Model
echo "🧠 Downloading model ($MODEL_NAME)..."
bash ./models/download-ggml-model.sh "$MODEL_NAME"

# 4. Compile
echo "🔨 Compiling whisper-cli..."
rm -rf build
cmake -B build -DWHISPER_SDL2=ON
cmake --build build --config Release

echo "✅ Installation complete!"
echo "➡️  Please place 'transcribe.sh' inside $BASE_DIR and run: chmod +x $BASE_DIR/transcribe.sh"