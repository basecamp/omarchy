echo "Change omarchy-screenrecord to use gpu-screen-recorder"
omarchy-pkg-drop wf-recorder wl-screenrec

# Add slurp in case it hadn't been picked up from an old migration
omarchy-pkg-add slurp gpu-screen-recorder
