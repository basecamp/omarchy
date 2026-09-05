mise reshim --system
# The reshim above cannot fail when a lazy tool is cold. This call can: it exits
# non-zero when Hermes Desktop owns Hermes but has not finished setting it up,
# and this leaf is sourced under `bash -eE`, so that would abort the rest of
# omarchy-provision-user -- the default browser, the mailto handler and the
# finalize-user marker all come after it.
omarchy-install-hermes-cli || true
