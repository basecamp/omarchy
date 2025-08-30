echo "Ensure Ollama is properly configured to utilize NVIDIA GPUs"

if command -v ollama &>/dev/null; then
  if command -v nvidia-smi &>/dev/null; then
    sudo pacman -S --noconfirm ollama-cuda
  fi
fi
