#!/bin/bash

# Apply the speaker tuning for this laptop. Runs at first-run rather than at
# finalize-user time because finalize-user also runs in the ISO chroot, where
# there is no audio server: the sink the tuning has to target does not exist, so
# nothing could be written and nothing would retry -- the finalizer marks all
# shipped migrations complete on a fresh install. By first-run the session is up
# and the sink is present.
#
# A no-op on machines no tuning matches.

set -euo pipefail

omarchy-audio-tuning on
