echo "Cure Chromium crash bug caused by mixing 145 and 144 sync logs"

rm -rf ~/.config/chromium/Default/Sync\ Data/LevelDB/*.log
